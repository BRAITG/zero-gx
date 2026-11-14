class_name Leaderboard
extends RefCounted
## One shared renderer for the full sheet and preview. Requests outlive a closed sheet, never its controls.

var _overlay: Overlay
var _content: VBoxContainer
var _refresh: Button
var _sha := ""
var _local_points := -1
var _board := {}
var _loading := false
var _reading := false
var _again := false
var _force := false


static func open(parent: Node, sha256: String, title: String, local_points := -1) -> Overlay:
	return Leaderboard.new()._open(parent, sha256, title, local_points)


## Pure presentation: replaces only its own top-five/own-standing widget, never reads a board or adds a Full board button.
static func preview(parent: Control, board: Dictionary, local_points: int) -> void:
	var previous := parent.get_node_or_null("LeaderboardPreview")
	if previous != null:
		parent.remove_child(previous)
		previous.free()
	var content := VBoxContainer.new()
	content.name = "LeaderboardPreview"
	content.add_theme_constant_override("separation", 12)
	parent.add_child(content)
	_fill(content, board, local_points, 5)
	# Keep preview rows readable on a phone; headings retain their larger size.
	for label: Label in content.find_children("*", "Label", true, false):
		label.add_theme_font_size_override("font_size", maxi(24, label.get_theme_font_size("font_size")))
	for box: VBoxContainer in [content] + content.find_children("*", "VBoxContainer", true, false):
		box.add_theme_constant_override("separation", 6)
	var own := content.get_node_or_null("OwnStanding") as PanelContainer
	if own != null:
		own.get_theme_stylebox("panel").set_content_margin_all(8)


func _open(parent: Node, sha256: String, title: String, local_points: int) -> Overlay:
	_sha = sha256
	_local_points = local_points
	_overlay = Overlay.open(parent, title, false, true)
	_overlay.set_meta("leaderboard", self)
	_content = VBoxContainer.new()
	_content.custom_minimum_size.x = Overlay.WIDTH
	_content.add_theme_constant_override("separation", 14)
	_overlay.body.add_child(_content)
	_refresh = Button.new()
	_refresh.name = "RefreshBoard"
	_refresh.text = "Refresh"
	_refresh.custom_minimum_size = Vector2(180, 56)
	_refresh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_refresh.pressed.connect(Sfx.play.bind("tap"))
	_refresh.pressed.connect(_read.bind(true))
	_overlay.body.add_child(_refresh)
	Community.board_updated.connect(_updated)
	Community.identity_changed.connect(_identity_changed)
	Community.score_result.connect(_score_result)
	_board = Community.cached_board(_sha)
	_render()
	_read()
	Community.sync_scores()  # explicit opening retries only scores; drawing and feedback activation never wait for it
	return _overlay


func _alive() -> bool:
	return is_instance_valid(_overlay) and _overlay.is_inside_tree() and not _overlay.get_parent().is_queued_for_deletion()


func _read(force := false) -> void:
	_force = _force or force
	_again = true
	if _reading:
		return
	_reading = true
	while _again and _alive():
		_again = false
		var fresh := _force
		_force = false
		_loading = true
		_render()
		var reply: Dictionary = await Community.board(_sha, fresh)
		if not _alive():
			break
		if _again:
			continue
		_board = reply
		_loading = false
		_render()
	_reading = false


func _updated(sha256: String) -> void:
	if _alive() and sha256 == _sha:
		_board = Community.cached_board(_sha)
		_render()  # cache-only: board_updated must not cause another board request


func _identity_changed(account: String) -> void:
	if not _alive():
		return
	_board = Community.cached_board(_sha)
	_render()
	if account != "":
		_read()


func _score_result(account: String, sha256: String, revision: int, result: Dictionary) -> void:
	if _alive() and sha256 == _sha and account == Community.player_id() and result.get("state") == "posted" and Community.score_state(_sha).get("revision") == revision:
		_read(true)  # if an older read is still out, read once more after it rather than showing its pre-upload rank


func _render() -> void:
	if not _alive():
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.free()
	_refresh.disabled = _loading
	_refresh.text = "Refreshing…" if _loading else "Refresh"
	if _board.is_empty():
		_label(_content, "Loading standings…" if _loading else "Standings unavailable", 22, Style.INK_DIM)
		return
	if _loading:
		_label(_content, "Refreshing standings…", 22, Style.INK_DIM)
	_fill(_content, _board, _local_points, 20)


static func _fill(parent: Control, board: Dictionary, local_points: int, limit: int) -> void:
	if board.is_empty():
		_label(parent, "Standings unavailable", 22, Style.INK_DIM)
		return
	var cached: bool = board.get("cached", false)
	if board.get("offline", false):
		_label(parent, "Offline · cached standings" if cached else "Standings unavailable", 22, Style.INK_DIM)
	elif cached:
		_label(parent, "Cached standings · updated within the last hour" if Time.get_unix_time_from_system() - board.get("fetched_at", 0) < Community.BOARD_CACHE_SECONDS else "Cached standings", 22, Style.INK_DIM)
	if board.has("error"):
		_label(parent, str(board.error), 22, Style.INK_DIM)
	if not cached and board.has("error"):
		return  # a failed first read is not an empty board
	_label(parent, "Top %d" % limit, 28, Style.ACCENT)
	var rows: Array = board.get("rows", [])
	if rows.is_empty():
		_label(parent, "No ranked runs yet", 22, Style.INK_DIM)
	else:
		_columns(parent, ["Rank", "Name", "Points", "Time"], Style.INK_DIM)
		for row: Dictionary in rows.slice(0, limit):
			_ranked_row(parent, row)
	_own(parent, board, local_points)


static func _own(parent: Control, board: Dictionary, local_points: int) -> void:
	var panel := PanelContainer.new()
	panel.name = "OwnStanding"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Style.PANEL
	style.border_color = Style.ACCENT
	style.set_border_width_all(2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_label(box, "You", 28, Style.ACCENT)
	var you: Variant = _you(board)
	if local_points >= 0 and (not you is Dictionary or local_points != you.points):
		_label(box, "Local best · %d points" % local_points, 22)
		var estimate := standing(board, local_points).trim_suffix(" (cached)")
		if estimate != "No ranked runs yet":  # the empty-state line above already explains this
			_label(box, estimate, 22, Style.INK_DIM)
	if you is Dictionary:
		_label(box, standing(board, -1).trim_suffix(" (cached)"), 22)
		_ranked_row(box, you)
	elif local_points < 0:
		_label(box, "Not played yet", 22, Style.INK_DIM)


## The same honest local estimate / exact remote-best label on results, previews and campaign rows.
static func standing(board: Dictionary, local_points: int) -> String:
	var you: Variant = _you(board)
	var cached := " (cached)" if board.get("cached", false) or board.get("offline", false) else ""
	if local_points >= 0 and (not you is Dictionary or local_points != you.points):
		if you is Dictionary and local_points > you.points:
			# A known lower own score bounds a better score more tightly than lossy quantiles.
			return "Estimate: would rank #%d or better%s" % [you.rank, cached]
		var rows: Array = board.get("rows", [])
		var lowest: Variant = rows[19].points if rows.size() >= 20 else null
		var text: String = RankEstimate.estimate(local_points, int(board.get("count", -1)), board.get("quantiles", []), lowest).text
		return text + cached if text != "" else "Estimate unavailable"
	if you is Dictionary:
		var population := " of %d" % board.count if board.get("count", -1) >= you.rank else ""
		return "Your ranked best · Rank #%d%s%s" % [you.rank, population, cached]
	return "Not played yet" if local_points < 0 else "Estimate unavailable"


static func _you(board: Dictionary) -> Variant:
	var you: Variant = board.get("you")
	if you is Dictionary and board.get("owner", "") == Community.player_id() and you.get("player", {}).get("id") == board.get("owner"):
		return you
	return null


static func _ranked_row(parent: Control, row: Dictionary) -> void:
	var line := _columns(parent, ["#%d" % row.rank, str(row.player.name), str(row.points), "%.2f s" % row.seconds])
	line.set_meta("board_row", row)


static func _columns(parent: Control, values: Array, color := Style.INK) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	for i in values.size():
		var label := _label(row, values[i], 22, color)
		if i == 1:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		else:
			label.custom_minimum_size.x = 80 if i == 0 else 140
			if i > 1:
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row


static func _label(parent: Node, text: String, size := 22, color := Style.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
