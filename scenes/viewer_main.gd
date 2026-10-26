class_name ViewerMain
extends Control
## The browser page at https://braitg.github.io/zero-gx/viewer/: plays a community level's demo. `?level=<URL>&demo=<URL>` name the two
## files; they must be raw files of BRAITG/zero-gx-levels at a commit. A Godot run off the web reads `level=<URL> demo=<URL>` after `--`.

const SCENE := "res://scenes/viewer_main.tscn"
const REFUSED := "Only files from BRAITG/zero-gx-levels at a commit can be shown."
const NOT_LOADED := "The level or its demo could not be loaded."
const WRONG_LEVEL := "The demo was recorded on a different level."
const BAD_LEVEL := "The level file is not a valid Zero-GX level."
const BAD_DEMO := "The demo file is not a valid Zero-GX demo."

# The path takes no `%` and no `..`: the browser would resolve either to a file outside the commit.
static var _url := RegEx.create_from_string("\\Ahttps://raw\\.githubusercontent\\.com/BRAITG/zero-gx-levels/[0-9a-f]{40}/[A-Za-z0-9_./-]+\\z")

var _shown: Node  # the message or the DemoViewer on screen


static func allowed_url(url: String) -> bool:
	return _url.search(url) != null and not url.contains("..")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pairs := str(JavaScriptBridge.eval("location.search")).trim_prefix("?").split("&") if OS.has_feature("web") else OS.get_cmdline_user_args()
	var query := {}
	for pair in pairs:
		var parts := pair.split("=", true, 1)
		if parts.size() == 2:
			query[parts[0]] = parts[1].uri_decode()
	var level_url: String = query.get("level", "")
	var demo_url: String = query.get("demo", "")
	if not allowed_url(level_url) or not allowed_url(demo_url):
		_message(REFUSED)
		return
	_message("Loading…")
	var level := await Community.transport.send("GET", level_url, PackedStringArray(), PackedByteArray())
	var demo := await Community.transport.send("GET", demo_url, PackedStringArray(), PackedByteArray())
	if level.status != 200 or demo.status != 200:
		_message(NOT_LOADED)
		return
	start(level.body, demo.body)


## Shows the demo played over its level and returns "", or shows why it cannot be and returns that reason.
func start(level_bytes: PackedByteArray, demo_bytes: PackedByteArray) -> String:
	var json := JSON.new()
	var data: Dictionary = json.data if json.parse(level_bytes.get_string_from_utf8()) == OK and json.data is Dictionary else {}
	var demo := Demo.decode(demo_bytes)
	var reason := ""
	if data.is_empty() or not LevelFormat.validate(data).is_empty():
		reason = BAD_LEVEL
	elif demo == null or demo.frame_count() == 0:
		reason = BAD_DEMO
	elif demo.level_sha256 != CommunityWire.sha256_hex(level_bytes):
		reason = WRONG_LEVEL
	if reason != "":
		_message(reason)
	else:
		_show(DemoViewer.create(data, demo, get_tree().reload_current_scene))
	return reason


func _message(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 24)
	_show(label)


func _show(node: Node) -> void:
	if _shown:
		_shown.queue_free()
	_shown = node
	add_child(node)
