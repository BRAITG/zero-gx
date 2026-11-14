class_name CommunityLevelDetails
extends RefCounted
## The details sheet of one community version: hero, difficulty (Rated, Reviewed, player votes), how players did, and this
## player's own tries, Like and difficulty vote. The catalogue's Details and an ended run's Rate level both open it.
## A RefCounted, not a Node: the sheet keeps it alive through its meta, and so does any request it awaits, so a sheet
## closed under a held request resumes into this object and touches no freed control.

const DIFFICULTIES := CommunityHistory.DIFFICULTIES
const MIN_VOTERS := 5  # fewer voters show no community label
const MIN_STARTERS := 10  # fewer starters show no ratios
const TARGETS := ["like", "difficulty"]
const BANDS := {"easy": [0.8, 1.0], "normal": [0.5, 0.8], "hard": [0.2, 0.5], "expert": [0.0, 0.2]}  # the P10 range each Rated label stands for
const LIMITS := "The rating describes the Android Play audience, not desktop players. A player who quits early counts only for the attempts they made, so a level that drives people away after one try can look easier than it is. Once a version has hundreds of starters who each play few levels, its interval is narrower than the stated 90% and its label leans slightly easy. Each new version starts as Estimating; the previous version's label is not carried over."

var _overlay: Overlay
var _level := ""
var _sha := ""
var _account := ""  # whose private state is shown; "" until the first answer
var _data := {}  # the last payload: labels, statistics and this player's eligibility; {} until one arrives
var _error := ""  # why the last read failed
var _loading := true
var _reading := false  # a read is in flight
var _again := false  # a read was asked for while one was in flight
var _liked := false  # confirmed state of this player
var _vote := ""
var _settled := {}  # target → true once a choice made here was confirmed: only an older cached answer after a failed read must not undo it
var _want := {"like": false, "difficulty": ""}  # the latest choice per target
var _pending := {"like": false, "difficulty": false}  # chosen here, not confirmed yet
var _asked := {"like": 0, "difficulty": 0}  # serial of the latest choice per target
var _note := ""  # why a pending choice has not gone through
var _refusal := ""  # the server's sentence for a choice it will never take

var _row := {}  # the catalogue-like row the sheet opened for
var _to_you := false  # scroll to the You section once the first answer is in
var _chip_slot: HBoxContainer
var _meta: Label
var _difficulty: VBoxContainer
var _facts: VBoxContainer
var _you_heading: Label
var _progress: Label
var _best: HBoxContainer
var _like: Button
var _like_note: Label
var _votes: HBoxContainer
var _vote_title: Label
var _vote_buttons := {}  # wire value → toggle Button
var _vote_note: Label
var _pending_label: Label
var _sync_icon: SyncIndicator
var _sync_row: HBoxContainer
var _refusal_label: Label
var _hint: Label
var _refresh: Button
var _board_slot: VBoxContainer
var _board := {}
var _board_read := 0  # invalidates an old owner's held answer


## Shows the sheet of the catalogue-like `row` (level_id, sha256, latest, title, author, likes) over `parent`, opaque. Without `on_play` there is no Play button; with `to_you` it opens scrolled to the player's own section.
static func open(parent: Node, row: Dictionary, on_play := Callable(), to_you := false) -> Overlay:
	return CommunityLevelDetails.new()._build(parent, row, on_play, to_you)


func _build(parent: Node, row: Dictionary, on_play: Callable, to_you: bool) -> Overlay:
	_level = str(row.get("level_id", ""))
	_sha = str(row.get("sha256", ""))
	_row = row
	_to_you = to_you
	_overlay = Overlay.open(parent, str(row.get("title", "Level")), false, true)
	_overlay.set_meta("details", self)  # the sheet owns this object; a request in flight owns it too
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 24)
	_overlay.body.add_child(hero)
	var thumbnail := Thumbnail.of_sketch(row.get("sketch"))
	thumbnail.custom_minimum_size = Vector2(320, 180)
	thumbnail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hero.add_child(thumbnail)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 10)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.add_child(text)
	var byline := PackedStringArray()
	if row.get("author") is String:
		byline.append("by " + row.author)
	if row.get("latest") is int or row.get("latest") is float:
		byline.append("version %d" % int(row.latest))
	if not byline.is_empty():
		text.add_child(_label(" · ".join(byline), 24, Style.INK_DIM))
	_chip_slot = HBoxContainer.new()
	text.add_child(_chip_slot)
	_meta = _label("", 22, Style.INK_DIM)
	text.add_child(_meta)
	if on_play.is_valid():
		var play := _button(text, "Play", on_play, "Loading…")
		play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		play.add_theme_stylebox_override("normal", play.get_theme_stylebox("pressed"))  # primary, like the row's Play
	_overlay.heading("Difficulty")
	_difficulty = _overlay.card()
	_overlay.heading("How players did")
	_facts = _overlay.card()
	_you_heading = _overlay.heading("You")
	var mine := _overlay.card()
	_progress = _overlay.paragraph("", 22, Style.INK, mine)
	_best = HBoxContainer.new()
	_best.add_theme_constant_override("separation", 12)
	mine.add_child(_best)
	_like = _button(mine, "♥ Like", _liked_pressed)
	_like.toggle_mode = true
	_like.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_like_note = _overlay.paragraph("", 22, Style.INK_DIM, mine)
	_vote_title = _overlay.paragraph("Difficulty vote", 22, Style.INK, mine)
	_votes = HBoxContainer.new()
	_votes.add_theme_constant_override("separation", 12)
	mine.add_child(_votes)
	for difficulty: String in DIFFICULTIES:
		var vote := _button(_votes, difficulty.capitalize(), _voted.bind(difficulty))
		vote.toggle_mode = true
		_vote_buttons[difficulty] = vote
	_vote_note = _overlay.paragraph("", 22, Style.INK_DIM, mine)
	_sync_row = HBoxContainer.new()
	_sync_row.add_theme_constant_override("separation", 12)
	mine.add_child(_sync_row)
	_sync_icon = SyncIndicator.new()
	_sync_icon.name = "SyncIndicator"
	_sync_icon.expired.connect(_render)
	_sync_row.add_child(_sync_icon)
	_pending_label = _overlay.paragraph("", 22, Style.ACCENT, _sync_row)
	_refusal_label = _overlay.paragraph("", 22, Style.INK, mine)
	_hint = _overlay.paragraph("", 22, Style.INK_DIM, mine)
	_refresh = _button(mine, "Refresh", _refresh_now, "Refreshing…")
	_refresh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if Community.available():
		# After You: delayed board expansion cannot move the result-origin anchor or steal manual scroll.
		_overlay.heading("Board")
		_board_slot = _overlay.card()
		var full := _button(_overlay.body, "Full board", _open_board)
		full.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		Community.board_updated.connect(_board_updated)
		_board = Community.cached_board(_sha)
		_show_board()
	Community.vote_result.connect(_vote_result)
	Community.play_history_synced.connect(_plays_synced)
	Community.identity_changed.connect(_identity_changed)
	_read_feedback()
	if _board_slot != null:
		_read_board()
	return _overlay


func _open_board() -> void:
	Leaderboard.open(_overlay, _sha, str(_row.get("title", "Level")), Progress.best_points(Community.STAGE_PREFIX + _sha))


func _read_board() -> void:
	_board_read += 1
	var serial := _board_read
	var owner := Community.player_id()
	var reply: Dictionary = await Community.board(_sha)
	if _alive() and serial == _board_read and owner == Community.player_id():
		_board = reply
		_show_board()


func _board_updated(sha256: String) -> void:
	if _alive() and sha256 == _sha:
		_board = Community.cached_board(_sha)
		_show_board()


func _show_board() -> void:
	if not _alive() or _board_slot == null:
		return
	Leaderboard.preview(_board_slot, _board, Progress.best_points(Community.STAGE_PREFIX + _sha))
	for label: Label in _board_slot.find_children("*", "Label", true, false):
		if label.get_parent() is VBoxContainer:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _board.is_empty():
		var label := _board_slot.get_node("LeaderboardPreview").get_child(0) as Label
		label.text = "Loading standings…"


# --- reading ------------------------------------------------------------------------------------------------------------


## Reads the feedback of this version. Reads are coalesced: one in flight at a time, and a reason to read that comes meanwhile (a settled vote, another player) drops the answer in flight, which may predate it, and reads once more. An answer is used only for the player who was signed in when its read began.
func _read_feedback() -> void:
	if _reading:
		_again = true
		return
	_reading = true
	_again = true
	while _again and _alive():
		_again = false
		_loading = true
		_render()
		var owner := Community.player_id()
		var reply: Dictionary = await Community.feedback(_level, _sha)
		if not _alive():
			break
		if _again:
			continue
		if owner != "" and Community.player_id() != owner:
			_forget_owner()  # that answer belongs to the player who is gone
			_again = true
			continue
		_apply(reply)
	_reading = false


## Takes an answer in. What the server says of this player is adopted, except where a choice is out (still the player's) or, for a stale cached answer after a failed read, where this sheet already confirmed a newer one.
func _apply(reply: Dictionary) -> void:
	_loading = false
	var account := Community.player_id()
	if account != _account:
		_forget_owner()  # nothing of the previous player carries over
		_account = account
	_error = reply.get("error", "")
	var queued := Community.pending_feedback(_level, _sha)  # choices left queued by an earlier sheet resolve here too
	for kind: String in TARGETS:
		if _error == "" and _pending[kind] and not queued.has(kind):
			_pending[kind] = false  # nothing is queued any more: the server's answer is the state
			_note = ""
		if queued.has(kind) and not _pending[kind]:
			_pending[kind] = true
			_want[kind] = queued[kind]
	if reply.get("stats") is Dictionary:
		_data = reply
		var you: Dictionary = reply.get("you", {})
		var adopt := _error == ""  # an online answer is current; a cached one only fills what is not confirmed yet
		if not _pending.like and (adopt or not _settled.has("like")):
			_liked = you.get("liked") == true
		if not _pending.difficulty and (adopt or not _settled.has("difficulty")):
			var value: Variant = you.get("difficulty")
			_vote = value if value is String and value in DIFFICULTIES else ""
	_render()
	if _to_you:  # the layout of the first answer must settle before the scroll position means anything
		_to_you = false
		_scroll_to_you()


## Whether the sheet is still on screen.
func _alive() -> bool:
	return is_instance_valid(_overlay) and _overlay.is_inside_tree() and not _overlay.get_parent().is_queued_for_deletion()


## Drops everything private to the shown player, including choices not settled yet.
func _forget_owner() -> void:
	_account = ""
	_data = {}
	_liked = false
	_vote = ""
	_settled.clear()
	_pending = {"like": false, "difficulty": false}
	_note = ""
	_refusal = ""
	_sync_icon.clear()


## Whether the signed-in player is still the one shown; if not, the answer in hand is not used and the sheet starts over for the new player.
func _owner_kept(account: String) -> bool:
	if Community.player_id() == account:
		return true
	_forget_owner()
	_read_feedback()
	return false


# --- choosing -----------------------------------------------------------------------------------------------------------


func _liked_pressed() -> void:
	_choose("like", _like.button_pressed)


## A press on a vote button: the selected one removes the vote, any other one casts it.
func _voted(value: String) -> void:
	_choose("difficulty", "" if _shown_vote() == value else value)


## A choice for `target` ("like": bool, "difficulty": String, "" removes): shown at once as pending and handed to Community at once, which queues it durably (whatever happens to this sheet) and serializes the flushes. Its own answer is used only while it is still the latest choice.
func _choose(target: String, value: Variant) -> void:
	if not _owner_kept(_account):  # the controls show another player's state: nothing is queued from them
		_render()
		return
	_want[target] = value
	_asked[target] += 1
	var serial: int = _asked[target]
	var account := _account
	_pending[target] = true
	_note = ""
	_refusal = ""
	_render()
	var result: Dictionary
	if target == "like":
		result = await Community.set_like(_level, value)
	else:
		result = await Community.set_difficulty(_level, _sha, value)
	if not _alive() or not _owner_kept(account):
		return
	if _asked[target] == serial and _pending[target]:  # a vote_result event may have settled it already (and read once): not twice
		_settle(target, result)
	elif _pending[target] and Community.pending_feedback(_level, _sha).has(target):
		# the flush this older choice ran has ended while a newer one waits behind it, queued: send it now (once, no timer)
		await Community.sync_feedback()  # each result of it arrives as a vote_result


## One attempt at a queued choice of the signed-in player (Community.vote_result): applied (`error` empty), refused for good, or kept for a later flush. Its `value` says which choice it was: an applied one is the confirmed state whatever was chosen since, but only ends pending when no revision of that target is queued any more; a failed one concerns only the choice that is still wanted.
func _vote_result(account: String, kind: String, level: String, sha256: String, value: Variant, error: String) -> void:
	if not _alive() or account != _account or level != _level or not kind in TARGETS or (kind == "difficulty" and sha256 != _sha):
		return
	var shown: Variant = value if kind == "like" else (value if value is String else "")
	var queued := Community.pending_feedback(_level, _sha).has(kind)
	if error == "":
		_liked = shown == true if kind == "like" else _liked
		_vote = shown if kind == "difficulty" else _vote
		_settled[kind] = true
		if _pending[kind] and shown == _want[kind] and not queued:
			_pending[kind] = false
			_note = ""
		if not queued:
			_confirm_sync()
		_render()
		_read_feedback()
		return
	if not _pending[kind] or shown != _want[kind]:
		return
	if queued:
		_note = error
	else:
		_pending[kind] = false
		_note = ""
		_refusal = error
	_render()


## Reports of this player on this version reached the server (Community.play_history_synced): eligibility may have opened.
func _plays_synced(account: String, sha256: String) -> void:
	if _alive() and sha256 == _sha and account == Community.player_id():
		_confirm_sync()
		_read_feedback()


## The persisted player changed or was erased (Community.identity_changed): what this sheet shows of the previous one goes at once, before anything of the new one is read. Nobody is signed in any more: nothing is read, a read would sign in again.
func _identity_changed(account: String) -> void:
	if not _alive():
		return
	_error = ""
	_forget_owner()
	if _board_slot != null:
		_board_read += 1
		_board = Community.cached_board(_sha)
		_show_board()
		if account != "":
			_read_board()
	_loading = account != ""
	_render()
	if account != "":
		_read_feedback()


## Applies what Community answered for the choice of `target`: still queued stays pending; applied becomes the confirmed state (and the cached feedback is read again); anything else is a refusal and the confirmed state shows again.
func _settle(target: String, result: Dictionary) -> void:
	var error: String = result.get("error", "")
	if Community.pending_feedback(_level, _sha).has(target):
		_pending[target] = true  # an acknowledgment of an older revision must not have ended it
		_note = error
		_render()
		return
	_pending[target] = false
	_note = ""
	if error != "":
		_refusal = error
		_render()
		return
	if target == "like":
		_liked = _want.like
	else:
		_vote = _want.difficulty
	_settled[target] = true
	_confirm_sync()
	_render()
	_read_feedback()  # the acknowledgement does not rewrite the cached answer; counts and eligibility move too


## Sends what is queued, then reads again. Each choice it settles is reported by `vote_result`, not by this batch answer, which may belong to another target; a read that finds nothing queued and nothing out ends any pending mark that is left.
func _refresh_now() -> void:
	var account := _account
	await Community.sync_feedback()
	if not _alive() or not _owner_kept(account):
		return
	await _read_feedback()


func _confirm_sync() -> void:
	if not Community.play_progress(_sha).pending and Community.pending_feedback(_level, _sha).is_empty():
		_sync_icon.confirm()


# --- showing ------------------------------------------------------------------------------------------------------------


func _shown_like() -> bool:
	return _want.like if _pending.like else _liked


func _shown_vote() -> String:
	return _want.difficulty if _pending.difficulty else _vote


func _render() -> void:
	if not _alive():
		return
	var ready := not _data.is_empty()
	var you: Dictionary = _data.get("you", {})
	var like_ok: bool = you.get("like_eligible") == true
	var vote_ok: bool = you.get("difficulty_eligible") == true
	_show_hero(ready)
	_show_difficulty(ready)
	_show_facts()
	_progress.text = "Counted tries: %d%s" % [_count(you.get("attempts")), " · Cleared" if you.get("cleared") == true else ""] if ready else ""
	_show_best()
	_like.set_pressed_no_signal(_shown_like())
	_like.disabled = not ready or not (_liked or like_ok)
	_like_note.text = "Likes open after you clear this level on any version or try its versions %d times." % Community.FEEDBACK_TRIES if ready and not (_liked or like_ok) else ""
	var shown := _shown_vote()
	_votes.visible = ready and (vote_ok or shown != "")  # a vote already held can always be removed
	_vote_title.visible = _votes.visible
	for difficulty: String in DIFFICULTIES:
		var vote: Button = _vote_buttons[difficulty]
		vote.set_pressed_no_signal(difficulty == shown)
		vote.disabled = not vote_ok and difficulty != shown
	var queued: bool = _pending.like or _pending.difficulty
	var play_pending: bool = Community.play_progress(_sha).pending
	_pending_label.text = "Pending sync" + (" · " + _note if _note != "" else "") if queued or play_pending else ""
	_sync_icon.set_pending(queued or play_pending, _error != "" or _note != "" or _refusal != "")
	_refusal_label.text = _refusal
	var local_wait: bool = ready and not vote_ok and Community.play_progress(_sha).can_offer_rating
	_vote_note.text = _hint_text(ready, local_wait, vote_ok, _count(you.get("attempts")))
	_hint.text = _error
	for label: Label in [_progress, _like_note, _vote_note, _pending_label, _refusal_label, _hint]:
		label.visible = label.text != ""
	_sync_row.visible = _sync_icon.visible or _pending_label.visible
	_refresh.visible = queued or local_wait or _error != ""
	if _overlay.get_viewport().gui_get_focus_owner() == null:
		Style.focus_first(_overlay)  # a control that just turned off took the focus with it


## The line that stands in for the vote buttons while they are locked.
func _hint_text(ready: bool, local_wait: bool, vote_ok: bool, attempts: int) -> String:
	if not ready or vote_ok or _shown_vote() != "":
		return ""
	if local_wait:
		return "Voting opens once your play history reaches the server."
	var more := maxi(1, Community.FEEDBACK_TRIES - attempts)
	return "Clear it or try %d more %s to vote" % [more, "time" if more == 1 else "times"]


## Thumbnail-side facts: the one chip with its source, and likes and players.
func _show_hero(ready: bool) -> void:
	for old in _chip_slot.get_children():
		old.free()
	var source := _row.duplicate()
	if ready:
		for key: String in ["rated", "rated_high", "reviewed_difficulty", "community_difficulty"]:
			source[key] = _data.get(key)
	var chip := DifficultyChip.of(source)
	if chip:
		chip.get_child(0).add_theme_font_size_override("font_size", 26)
		_chip_slot.add_child(chip)
	var meta := PackedStringArray()
	var likes: Variant = _row.get("likes")
	if likes is int or likes is float:
		meta.append("♥ %d" % int(likes))
	var players: Variant = _counts().players if ready else _row.get("starters", _row.get("players"))
	if players is int or players is float:
		meta.append("%d %s" % [int(players), "player" if int(players) == 1 else "players"])
	_meta.text = " · ".join(meta)
	_meta.visible = not meta.is_empty()


## Rated (or Estimating), Reviewed, the vote distribution, the disagreement line and the known limits.
func _show_difficulty(ready: bool) -> void:
	for old in _difficulty.get_children():
		old.free()
	if not ready:
		_overlay.paragraph("Rated: " + ("Loading…" if _loading else "Not available"), 24, Style.INK, _difficulty)
		return
	var rated: Variant = _data.get("rated")
	if rated in DifficultyChip.LABELS:
		_overlay.paragraph(DifficultyChip.text_of({"rated": rated, "rated_high": _data.get("rated_high")}), 26, Style.INK, _difficulty)
		var sentence := _rated_sentence(rated, _data.get("rated_high"))
		if sentence != "":
			_overlay.paragraph(sentence, 22, Style.INK, _difficulty)
	else:
		var starters: int = _counts().players
		_overlay.paragraph("Estimating · %d %s" % [starters, "player" if starters == 1 else "players"], 26, Style.INK, _difficulty)
	_overlay.paragraph(reviewed_label(_data.get("reviewed_difficulty")), 24, Style.INK, _difficulty)
	_show_votes()
	var gap := _disagreement(rated, _data.get("rated_high"), _data.get("reviewed_difficulty"))
	if gap != "":
		_overlay.paragraph(gap, 22, Style.ACCENT, _difficulty)
	if rated in DifficultyChip.LABELS:  # the limits qualify a rating; Estimating has none
		_overlay.paragraph(LIMITS, 20, Style.INK_DIM, _difficulty)


## "A typical player clears it within 10 tries 35–55% of the time", plus a note while the published label no longer covers the interval.
func _rated_sentence(low_label: String, high_label: Variant) -> String:
	var low: Variant = _data.get("p10_low")
	var high: Variant = _data.get("p10_high")
	if not ((low is int or low is float) and (high is int or high is float)):
		return ""
	var text := "A typical player clears it within 10 tries %d–%d%% of the time" % [roundi(low * 100.0), roundi(high * 100.0)]
	var labels := [low_label, high_label if high_label in DifficultyChip.LABELS else low_label]
	var easiest: int = labels.map(DifficultyChip.LABELS.find).min()
	var hardest: int = labels.map(DifficultyChip.LABELS.find).max()
	if low < BANDS[DifficultyChip.LABELS[hardest]][0] - 1e-9 or high > BANDS[DifficultyChip.LABELS[easiest]][1] + 1e-9:
		text += " (the label updates once the estimate settles)"
	return text


## One line when Rated and Reviewed are two or more steps apart; a Rated range counts from its nearer end.
func _disagreement(low_label: Variant, high_label: Variant, reviewed: Variant) -> String:
	var scale: Array = DifficultyChip.LABELS
	if not (low_label in scale and reviewed in scale):
		return ""
	var target: int = scale.find(reviewed)
	var ends := [scale.find(low_label), scale.find(high_label if high_label in scale else low_label)]
	var gap: int = ends[0] - target if absi(ends[0] - target) <= absi(ends[1] - target) else ends[1] - target
	if gap >= 2:
		return "Players find it harder than the moderator rated it"
	return "Players find it easier than the moderator rated it" if gap <= -2 else ""


## Four labelled bars with counts, then the voter total and, from 5 voters, the upper median.
func _show_votes() -> void:
	var counts: Variant = _data.get("votes")
	var voters := 0
	if counts is Dictionary:
		var most := 5  # one voter must not fill a bar
		for difficulty: String in DIFFICULTIES:
			most = maxi(most, _count(counts.get(difficulty)))
		for difficulty: String in DIFFICULTIES:
			var count := _count(counts.get(difficulty))
			voters += count
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 12)
			_difficulty.add_child(line)
			var title := _label(difficulty.capitalize(), 22, Style.INK)
			title.custom_minimum_size.x = 120
			title.size_flags_horizontal = Control.SIZE_FILL
			line.add_child(title)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.max_value = most
			bar.value = count
			bar.custom_minimum_size.y = 22
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var fill := StyleBoxFlat.new()
			fill.bg_color = DifficultyChip.COLORS[difficulty]
			bar.add_theme_stylebox_override("fill", fill)
			line.add_child(bar)
			var number := _label(str(count), 22, Style.INK)
			number.custom_minimum_size.x = 60
			number.size_flags_horizontal = Control.SIZE_FILL
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line.add_child(number)
	else:
		voters = _count(_data.get("community_difficulty", {}).get("votes"))
	var text := "%d %s" % [voters, "voter" if voters == 1 else "voters"]
	var voted: Variant = _data.get("community_difficulty", {}).get("value")
	if voted in DIFFICULTIES and voters >= MIN_VOTERS:
		text += " · Voted " + String(voted).capitalize()
	_overlay.paragraph(text, 22, Style.INK_DIM, _difficulty)


## How the players so far did, up to each player's first clear: the curve, the three numbers and the audience line. Observed shares only; nothing here is a difficulty grade.
func _show_facts() -> void:
	for old in _facts.get_children():
		old.free()
	if _data.is_empty():
		return
	var counts := _counts()
	var started: int = counts.players
	var cleared: int = counts.cleared
	var curve: Variant = _data.get("curve")
	if counts.row and started >= MIN_STARTERS and curve is Array and curve.size() > 1:
		var plot := ClearCurve.new(curve)
		_facts.add_child(plot)
		_overlay.paragraph("Share of players who cleared within each number of tries, 1 to %d" % ClearCurve.MAX_TRIES, 20, Style.INK_DIM, _facts)
		var late := cleared - roundi(plot.shares.back() * started)
		if late > 0:
			_overlay.paragraph("%d cleared after more than %d tries" % [late, ClearCurve.MAX_TRIES], 20, Style.INK_DIM, _facts)
	_overlay.paragraph("Players: %d" % started, 22, Style.INK, _facts)
	var share := " (%d%%)" % roundi(100.0 * cleared / started) if started >= MIN_STARTERS else ""
	_overlay.paragraph("Cleared: %d%s" % [cleared, share], 22, Style.INK, _facts)
	var missing := maxi(0, started - cleared)
	var slow: int = counts.slow
	_overlay.paragraph("%d not cleared%s" % [missing, ", %d of them after 20+ tries" % slow if slow > 0 else ""], 22, Style.INK, _facts)
	var audience: Variant = _data.get("audience")
	if (audience is float or audience is int) and absf(audience) >= 0.5:
		_overlay.paragraph("Players so far were %s than typical" % ("stronger" if audience > 0 else "weaker"), 22, Style.ACCENT, _facts)


## The player's best score on this device, with its medal.
func _show_best() -> void:
	for old in _best.get_children():
		old.free()
	var points := Progress.best_points(Community.STAGE_PREFIX + _sha)
	_best.visible = points >= 0 and not _data.is_empty()
	if not _best.visible:
		return
	_best.add_child(_label("Best score: %d" % points, 22, Style.INK))
	var medal := Progress.medal(points, Community.par_of(_row))
	if medal != Progress.Medal.NONE:
		_best.add_child(ScoreIcon.new(ScoreIcon.Kind.MEDAL, medal))


## Brings the You section into view once the sheet has been laid out.
func _scroll_to_you() -> void:
	await _overlay.get_tree().process_frame
	if not _alive():
		return
	await _overlay.get_tree().process_frame
	if _alive():
		_overlay.scroll.scroll_vertical = int(_you_heading.global_position.y - _overlay.body.global_position.y)


## Players, clears and slow non-clears from one source, so they always add up: the cron's version row when the answer has one (`clears` is not null; the curve belongs to it), else the live stats, which carry no curve.
func _counts() -> Dictionary:
	var clears: Variant = _data.get("clears")
	if clears is int or clears is float:
		return {"row": true, "players": _count(_data.get("starters")), "cleared": int(clears), "slow": _count(_data.get("not_cleared_20"))}
	var stats: Dictionary = _data.get("stats", {})
	return {"row": false, "players": _count(stats.get("players_started")), "cleared": _count(stats.get("players_cleared")), "slow": _count(stats.get("unbeaten_20"))}


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 300
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func _name(value: Variant, fallback: String) -> String:
	return String(value).capitalize() if value is String and value in DIFFICULTIES else fallback


static func _count(value: Variant) -> int:
	return int(value) if value is int or value is float else 0


## The native choice of a difficulty: item 0 is the unselected placeholder (metadata ""), items 1-4 the four labels with their wire values as metadata. Used by the Publish confirmation.
static func difficulty_option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(320, 56)
	option.add_theme_font_size_override("font_size", 22)
	option.get_popup().add_theme_font_size_override("font_size", 22)
	option.get_popup().add_theme_constant_override("v_separation", 12)
	option.add_item("Choose difficulty")
	option.set_item_metadata(0, "")
	option.set_item_disabled(0, true)  # the placeholder is a state, not a vote
	for difficulty: String in DIFFICULTIES:
		option.add_item(difficulty.capitalize())
		option.set_item_metadata(option.item_count - 1, difficulty)
	option.select(0)
	return option


## The wire value chosen in a `difficulty_option`; "" for the placeholder.
static func chosen(option: OptionButton) -> String:
	var value: Variant = option.get_item_metadata(option.selected) if option.selected >= 0 else ""
	return value if value is String else ""


## "Reviewed: Hard" or "Reviewed: Not rated".
static func reviewed_label(value: Variant) -> String:
	return "Reviewed: " + _name(value, "Not rated")


func _button(parent: Control, text: String, action: Callable, busy := "") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action if busy == "" else Style.busy.bind(button, busy, action))
	parent.add_child(button)
	return button


class SyncIndicator extends Control:
	signal expired
	var confirmed := false
	var _remaining := 0.0
	var _stalled := false

	func _init() -> void:
		custom_minimum_size = Vector2(28, 28)
		pivot_offset = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process(false)
		hide()

	func clear() -> void:
		confirmed = false
		_remaining = 0.0
		rotation = 0.0
		set_process(false)
		hide()

	func set_pending(pending: bool, stalled: bool) -> void:
		if pending:
			confirmed = false
		_stalled = stalled
		visible = pending or confirmed
		set_process((pending and not stalled) or confirmed)
		if confirmed or stalled:
			rotation = 0.0
		queue_redraw()

	func confirm() -> void:
		confirmed = true
		_remaining = 2.0
		rotation = 0.0
		show()
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		if confirmed:
			_remaining -= delta
			if _remaining <= 0.0:
				clear()
				expired.emit()
		else:
			rotation = fmod(rotation + TAU * delta, TAU)

	func _draw() -> void:
		if confirmed:
			draw_line(Vector2(4, 14), Vector2(11, 21), Hud.GOAL_GREEN, 3.0, true)
			draw_line(Vector2(11, 21), Vector2(24, 6), Hud.GOAL_GREEN, 3.0, true)
		elif _stalled:
			draw_line(Vector2(10, 5), Vector2(10, 23), Style.INK_DIM, 3.0, true)
			draw_line(Vector2(18, 5), Vector2(18, 23), Style.INK_DIM, 3.0, true)
		else:
			draw_arc(Vector2(14, 14), 10.0, 0.0, TAU * 0.75, 24, Style.ACCENT, 3.0, true)
