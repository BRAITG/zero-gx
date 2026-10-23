class_name CommunityLevelDetails
extends RefCounted
## The details and rating sheet of one community version: Reviewed and Community difficulty, play statistics, and this
## player's own Like and difficulty vote. The catalogue's Details and an ended run's Rate level both open it.
## A RefCounted, not a Node: the sheet keeps it alive through its meta, and so does any request it awaits, so a sheet
## closed under a held request resumes into this object and touches no freed control.

const DIFFICULTIES := CommunityHistory.DIFFICULTIES
const MIN_VOTERS := 5  # fewer voters show no community label
const MIN_STARTERS := 10  # fewer starters show no ratios
const TARGETS := ["like", "difficulty"]

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

var _reviewed: Label
var _community: Label
var _like: Button
var _option: OptionButton
var _remove: Button
var _progress: Label
var _pending_label: Label
var _refusal_label: Label
var _hint: Label
var _refresh: Button
var _facts: VBoxContainer


## Shows the sheet of the catalogue-like `row` (level_id, sha256, latest, title, author) over `parent`. Without `on_play` there is no Play button.
static func open(parent: Node, row: Dictionary, on_play := Callable()) -> Overlay:
	return CommunityLevelDetails.new()._build(parent, row, on_play)


func _build(parent: Node, row: Dictionary, on_play: Callable) -> Overlay:
	_level = str(row.get("level_id", ""))
	_sha = str(row.get("sha256", ""))
	_overlay = Overlay.open(parent, str(row.get("title", "Level")))
	_overlay.set_meta("details", self)  # the sheet owns this object; a request in flight owns it too
	if on_play.is_valid():
		_button(_overlay.body, "Play", on_play, "Loading…").size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var byline := PackedStringArray()
	if row.get("author") is String:
		byline.append("by " + row.author)
	if row.get("latest") is int or row.get("latest") is float:
		byline.append("v%d" % int(row.latest))
	if not byline.is_empty():
		_overlay.paragraph(" · ".join(byline), 24, Style.INK_DIM)
	_overlay.heading("Difficulty")
	var labels := _overlay.card()
	_reviewed = _overlay.paragraph("", 24, Style.INK, labels)
	_community = _overlay.paragraph("", 24, Style.INK, labels)
	_overlay.heading("Your feedback")
	var mine := _overlay.card()
	_like = _button(mine, "♥ Like", _liked_pressed)
	_like.toggle_mode = true
	_like.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_overlay.paragraph("Difficulty vote", 22, Style.INK, mine)
	var vote := HBoxContainer.new()
	vote.add_theme_constant_override("separation", 12)
	mine.add_child(vote)
	_option = difficulty_option()
	_option.item_selected.connect(_picked)
	vote.add_child(_option)
	_remove = _button(vote, "Remove my vote", _choose.bind("difficulty", ""))
	_progress = _overlay.paragraph("", 22, Style.INK_DIM, mine)
	_pending_label = _overlay.paragraph("", 22, Style.ACCENT, mine)
	_refusal_label = _overlay.paragraph("", 22, Style.INK, mine)
	_hint = _overlay.paragraph("", 22, Style.INK_DIM, mine)
	_refresh = _button(mine, "Refresh", _refresh_now, "Refreshing…")
	_refresh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_overlay.heading("Statistics")
	_facts = _overlay.card()
	Community.vote_result.connect(_vote_result)
	Community.play_history_synced.connect(_plays_synced)
	Community.identity_changed.connect(_identity_changed)
	_read_feedback()
	return _overlay


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


func _picked(index: int) -> void:
	var value: Variant = _option.get_item_metadata(index)
	if value is String and value != "":
		_choose("difficulty", value)
	else:
		_render()


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
		_read_feedback()


## The persisted player changed or was erased (Community.identity_changed): what this sheet shows of the previous one goes at once, before anything of the new one is read. Nobody is signed in any more: nothing is read, a read would sign in again.
func _identity_changed(account: String) -> void:
	if not _alive():
		return
	_error = ""
	_forget_owner()
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
	_render()
	_read_feedback()  # the acknowledgement does not rewrite the cached answer; counts and eligibility move too


## Sends what is queued, then reads again. Each choice it settles is reported by `vote_result`, not by this batch answer, which may belong to another target; a read that finds nothing queued and nothing out ends any pending mark that is left.
func _refresh_now() -> void:
	var account := _account
	await Community.sync_feedback()
	if not _alive() or not _owner_kept(account):
		return
	await _read_feedback()


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
	var waiting := "Loading…" if _loading else "Not available"
	_reviewed.text = (reviewed_label(_data.get("reviewed_difficulty")) if ready else "Reviewed: " + waiting)
	_community.text = _community_text() if ready else "Community: " + waiting
	_like.set_pressed_no_signal(_shown_like())
	_like.disabled = not ready or not (_liked or like_ok)
	_option.select(DIFFICULTIES.find(_shown_vote()) + 1)
	_option.disabled = not ready or not vote_ok
	_remove.disabled = _shown_vote() == ""
	_progress.text = "Counted tries: %d%s" % [_count(you.get("attempts")), " · Cleared" if you.get("cleared") == true else ""] if ready else ""
	var queued: bool = _pending.like or _pending.difficulty
	_pending_label.text = "Pending sync" + (" · " + _note if _note != "" else "") if queued else ""
	_refusal_label.text = _refusal
	var local_wait: bool = ready and not vote_ok and Community.play_progress(_sha).can_offer_rating
	_hint.text = _hint_text(ready, local_wait, like_ok, vote_ok)
	for label: Label in [_progress, _pending_label, _refusal_label, _hint]:
		label.visible = label.text != ""
	_refresh.visible = queued or local_wait or _error != ""
	_show_facts()
	if _overlay.get_viewport().gui_get_focus_owner() == null:
		Style.focus_first(_overlay)  # a control that just turned off took the focus with it


func _community_text() -> String:
	return community_label(_data.get("community_difficulty"))


func _hint_text(ready: bool, local_wait: bool, like_ok: bool, vote_ok: bool) -> String:
	var lines := PackedStringArray()
	if _error != "":
		lines.append(_error)
	if local_wait:
		lines.append("Pending sync: your latest tries have not reached the server yet. Voting opens once they have.")
	elif ready and not vote_ok:
		if like_ok or _liked:
			lines.append("Difficulty voting opens after you clear this version or try it %d times." % Community.FEEDBACK_TRIES)
		else:
			lines.append("Likes open after you clear this level on any version or try its versions %d times." % Community.FEEDBACK_TRIES)
			lines.append("Difficulty votes open after you clear this version or try it %d times." % Community.FEEDBACK_TRIES)
	return "\n".join(lines)


## The raw observations as the server sent them. Ratios appear only when the server computed them; nothing here is a difficulty grade.
func _show_facts() -> void:
	for old in _facts.get_children():
		old.free()
	if _data.is_empty():
		return
	var stats: Dictionary = _data.get("stats", {})
	var started := _count(stats.get("players_started"))
	var lines := PackedStringArray([
		"Players started: %d" % started,
		"Players cleared: %d" % _count(stats.get("players_cleared")),
		"Counted attempts: %d" % _count(stats.get("total_attempts")),
	])
	var rate: Variant = stats.get("clear_rate")
	if rate is float or rate is int:
		lines.append("Clear rate: %s%%" % _number(float(rate) * 100.0))
		lines.append("Attempts per first clear: " + _number_or(stats.get("attempts_per_first_clear"), "No clears yet"))
		lines.append("Median tries among finishers only: " + _number_or(stats.get("median_tries"), "No clears yet"))
	else:
		lines.append("Not enough play data: %d of %d players have started." % [started, MIN_STARTERS])
	for tries in [5, 10, 20]:
		lines.append("Still unbeaten after %d attempts: %d" % [tries, _count(stats.get("unbeaten_%d" % tries))])
	for line in lines:
		_overlay.paragraph(line, 22, Style.INK, _facts)
	_overlay.paragraph("These figures describe the players so far; they are not a difficulty grade.", 20, Style.INK_DIM, _facts)


static func _name(value: Variant, fallback: String) -> String:
	return String(value).capitalize() if value is String and value in DIFFICULTIES else fallback


static func _count(value: Variant) -> int:
	return int(value) if value is int or value is float else 0


## One decimal at most, none when whole.
static func _number(value: float) -> String:
	return String.num(snappedf(value, 0.1))


static func _number_or(value: Variant, fallback: String) -> String:
	return _number(float(value)) if value is int or value is float else fallback


## The native choice of a difficulty: item 0 is the unselected placeholder (metadata ""), items 1-4 the four labels with their wire values as metadata. Used by this sheet and by the Publish confirmation.
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


## "Community: Hard (6 votes)", or the vote count against the five that a label needs.
static func community_label(community: Variant) -> String:
	var data: Dictionary = community if community is Dictionary else {}
	var votes := _count(data.get("votes"))
	var value: Variant = data.get("value")
	if value is String and value in DIFFICULTIES:
		return "Community: %s (%d %s)" % [value.capitalize(), votes, "vote" if votes == 1 else "votes"]
	return "Community: Not enough ratings (%d of %d votes)" % [votes, MIN_VOTERS]


## One compact line for a catalogue row: Reviewed and Community side by side, never one grade.
static func summary(row: Dictionary) -> String:
	return "%s · %s" % [reviewed_label(row.get("reviewed_difficulty")), community_label(row.get("community_difficulty"))]


func _button(parent: Control, text: String, action: Callable, busy := "") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action if busy == "" else Style.busy.bind(button, busy, action))
	parent.add_child(button)
	return button
