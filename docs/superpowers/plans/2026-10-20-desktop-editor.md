# Desktop Level Editor and Level Import/Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Edit, test-fly and move Zero-GX levels on Windows, macOS and Linux, with file import/export shared by the desktop builds and the Android app.

**Architecture:** The existing Godot project gains desktop export presets. `MyLevels` gains path-based `import_file`/`export_file`; the My levels screen calls them through a `FileDialog` with `use_native_dialog = true` (native picker on desktop and Android, Godot's own dialog where no native one exists). `LevelEditor._unhandled_input` gains mouse pan, cursor-centred zoom and keyboard shortcuts; the touch path is untouched.

**Tech Stack:** Godot 4.7.2, GDScript, the repo's headless test runner (`tests/run.sh`), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-20-desktop-editor-design.md`

## Global Constraints

- Godot `4.7.2`; no new addons, plugins or dependencies.
- Export writes plain `.json` in the `LevelFormat.to_json` stable layout. Import accepts `.json` and `.json.gz`.
- Import size limit: `LevelFormat.MAX_BYTES` (65536), checked on the file before parsing.
- Import never overwrites: every import gets `MyLevels.new_id()`.
- The editor's touch handling (`InputEventScreenTouch`, `InputEventScreenDrag`) does not change.
- Tests never touch the player's levels: the runner already points `MyLevels.dir` at `user://test_levels/`.
- Desktop builds are not code-signed (macOS uses Godot's built-in ad-hoc signature only).

## Review Focus

1. **Typing in a text field fires shortcuts.** Pressing `T` or `Ctrl+S` while the Settings title `LineEdit` has focus must type, not test-fly or save. `_unhandled_input` only sees keys the focused control did not consume; Task 2 pins it with a test.
2. **Export to a name without `.json`.** A user types `my level` in the save dialog; the file written must be `my level.json` so the app's import filter finds it. Task 1 pins it.
3. **Import of a file that is not a level** (an image, an empty file, a JSON array). No level saved, readable error shown, no crash. Task 1 pins empty, non-JSON and array.
4. **Pan or zoom starting over a UI button.** Right-drag that starts on the top bar must not move the camera; `_unhandled_input` already skips GUI-handled events. Checked in the smoke run.
5. **Android picker returns a `content://` URI.** `FileAccess` must open it on a real device. Not testable headless; checked in the device smoke run in Task 3.

---

### Task 1: Level import and export

**Files:**
- Modify: `scripts/my_levels.gd` (add two static functions)
- Modify: `scenes/my_levels_screen.gd` (Import button in the top bar, Export button per row, dialogs)
- Test: `tests/test_my_levels.gd`

**Interfaces:**
- Consumes: `LevelFormat.read(path) -> Dictionary`, `LevelFormat.validate(data) -> PackedStringArray`, `LevelFormat.write(path, data) -> Error`, `LevelFormat.MAX_BYTES`, `MyLevels.new_id()`, `MyLevels.save(id, data)`, `MyLevels.load_level(id)`, `Overlay.open(parent, title)` / `paragraph(text)` / `close()`.
- Produces:
  - `MyLevels.import_file(path: String) -> PackedStringArray`: errors; empty means imported. On success the level is saved under a new id.
  - `MyLevels.export_file(id: String, path: String) -> Error`: writes the saved level; appends `.json` when `path` does not end in `.json`.

- [ ] **Step 1: Write the failing tests** in `tests/test_my_levels.gd`

```gdscript
func test_official_level_round_trips_through_import_and_export() -> void:
	var source := "res://levels/level_05.json"
	var original := FileAccess.get_file_as_string(source)
	check(MyLevels.import_file(source).is_empty(), "official level must import")
	var ids := MyLevels.ids()
	check(ids.size() == 1 and ids[0].begins_with(MyLevels.PREFIX), "one new user level: %s" % ids)
	var out := "user://test_export.json"
	check(MyLevels.export_file(ids[0], out) == OK, "export must succeed")
	check(FileAccess.get_file_as_string(out) == original, "export must be byte-identical to the official file")
	check(FileAccess.get_file_as_string(source) == original, "source untouched")
	DirAccess.remove_absolute(out)


func test_import_never_overwrites() -> void:
	MyLevels.import_file("res://levels/level_05.json")
	MyLevels.import_file("res://levels/level_05.json")
	check(MyLevels.ids().size() == 2, "two imports, two levels: %s" % MyLevels.ids())


func test_import_rejects_bad_files() -> void:
	var cases := {
		"user://bad_empty.json": "",
		"user://bad_text.json": "not json",
		"user://bad_array.json": "[1, 2]",
		"user://bad_level.json": '{"format": "zero-gx-level", "version": 1}',
		"user://bad_big.json": "x".repeat(LevelFormat.MAX_BYTES + 1),
	}
	for path: String in cases:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(cases[path])
		f.close()
		check(not MyLevels.import_file(path).is_empty(), "%s must be rejected" % path)
		DirAccess.remove_absolute(path)
	check(MyLevels.ids().is_empty(), "nothing saved: %s" % MyLevels.ids())


func test_export_adds_json_extension() -> void:
	MyLevels.import_file("res://levels/level_05.json")
	check(MyLevels.export_file(MyLevels.ids()[0], "user://my level") == OK, "export")
	check(FileAccess.file_exists("user://my level.json"), "`.json` appended")
	DirAccess.remove_absolute("user://my level.json")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `tests/run.sh`
Expected: FAIL, script error `Static function "import_file()" not found`.

- [ ] **Step 3: Implement `import_file` and `export_file` in `scripts/my_levels.gd`**

`import_file`: if the file is missing or `FileAccess.get_file_as_bytes(path).size() > LevelFormat.MAX_BYTES`, return one error (`"file is larger than 65536 bytes"` / `"file cannot be read"`) without parsing. Then `LevelFormat.read`; an empty Dictionary returns `["not a Zero-GX level"]`; otherwise return `LevelFormat.validate(data)` if non-empty, else `save(new_id(), data)` and return empty. `export_file`: `LevelFormat.write(path if path.ends_with(".json") else path + ".json", load_level(id))`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `tests/run.sh`
Expected: all tests PASS, exit 0.

- [ ] **Step 5: Add the UI in `scenes/my_levels_screen.gd`**

- Top bar: `_button(top, "Import", _import)` after "New level".
- Row: `_button(row, "Export", _export.bind(id, data.get("title", "level")))` after "Play". Reduce the row label's `custom_minimum_size.x` from 460 to 300 and update its comment to "room for Watch, Edit, Play, Export and Delete".
- `_import()`: a `FileDialog` (`use_native_dialog = true`, `access = FileDialog.ACCESS_FILESYSTEM`, `file_mode = FileDialog.FILE_MODE_OPEN_FILE`, `filters = PackedStringArray(["*.json, *.json.gz ; Zero-GX levels"])`), added as a child and shown with `popup_file_dialog()`. On `file_selected(path)`: call `MyLevels.import_file`; on errors open `Overlay.open(self, "Cannot import")` with one `paragraph` per error; on success `_fill()`. Free the dialog on `file_selected` and `canceled`.
- `_export(id, title)`: same dialog with `FILE_MODE_SAVE_FILE`, `filters = PackedStringArray(["*.json ; Zero-GX level"])`, `current_file = title + ".json"`. On `file_selected(path)`: if `MyLevels.export_file(id, path) != OK`, open `Overlay.open(self, "Cannot export")` with `paragraph("The file could not be written.")`. Cancel does nothing.

- [ ] **Step 6: Smoke the screen on desktop**

Run: `godot --path .` → Main menu → My levels → Import `levels/level_05.json` → row appears → Export it to `/tmp/l5.json` → `diff /tmp/l5.json levels/level_05.json` prints nothing. Import `/etc/hosts` → "Cannot import" overlay.

- [ ] **Step 7: Commit**

```bash
git add scripts/my_levels.gd scenes/my_levels_screen.gd tests/test_my_levels.gd
git commit -m "feat: import and export levels as files from My levels"
```

---

### Task 2: Mouse and keyboard in the editor

**Files:**
- Modify: `scenes/editor.gd` (`_unhandled_input`, lines 143-179; the header comment at lines 3-4)
- Test: `tests/test_editor.gd`

**Interfaces:**
- Consumes: `LevelEditor.create(id)`, `doc.undo()`, `save()`, `_test()`, `_refresh()`, `_to_world(screen)`, `_camera`, `ZOOM_RANGE`, `MyLevels.load_level(id)`.
- Produces: no new public API.

- [ ] **Step 1: Write the failing tests** in `tests/test_editor.gd` (reuse the file's `editor()` helper)

```gdscript
func _mouse(button: MouseButton, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = at
	return ev


func _key(code: Key, command := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = command
	return ev


func test_right_drag_pans() -> void:
	var e := editor()
	await frames(1)
	var before: Vector2 = e._camera.position
	e._unhandled_input(_mouse(MOUSE_BUTTON_RIGHT, true, Vector2(600, 300)))
	var move := InputEventMouseMotion.new()
	move.position = Vector2(700, 300)
	move.button_mask = MOUSE_BUTTON_MASK_RIGHT
	e._unhandled_input(move)
	check(e._camera.position.x < before.x, "dragging right moves the view left: %s -> %s" % [before, e._camera.position])
	check(e.doc.data.get("bodies", []).is_empty() and e.doc.data.get("walls", []).is_empty(), "panning places nothing")


func test_wheel_zoom_keeps_the_point_under_the_cursor() -> void:
	var e := editor()
	await frames(1)
	var cursor := Vector2(1000, 200)
	var before: Vector2 = e._to_world(cursor)
	e._unhandled_input(_mouse(MOUSE_BUTTON_WHEEL_UP, true, cursor))
	await frames(1)
	check(e._to_world(cursor).distance_to(before) < 1.0, "world point under cursor moved: %s -> %s" % [before, e._to_world(cursor)])


func test_ctrl_z_undoes_and_ctrl_s_saves() -> void:
	var e := editor()
	await frames(1)
	e.select_tool("planet")
	e.press(Vector2(3000, 0))
	e.release(Vector2(3000, 0), false)
	e._unhandled_input(_key(KEY_S, true))
	check(MyLevels.load_level(e.level_id).get("bodies", []).size() == 1, "Ctrl+S saves the planet")
	e._unhandled_input(_key(KEY_Z, true))
	check(e.doc.data.get("bodies", []).is_empty(), "Ctrl+Z removes the planet")


func test_typing_in_a_text_field_is_not_a_shortcut() -> void:
	var e := editor()
	await frames(1)
	var field := LineEdit.new()
	e.add_child(field)
	field.grab_focus()
	await frames(1)
	tree.root.push_input(_key(KEY_T))
	await frames(2)
	check(tree.current_scene == null or not tree.current_scene is Level, "T in a text field must not start a test flight")
	field.free()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `tests/run.sh`
Expected: FAIL on `test_right_drag_pans`, `test_wheel_zoom_keeps_the_point_under_the_cursor`, `test_ctrl_z_undoes_and_ctrl_s_saves`. (`test_typing_in_a_text_field_is_not_a_shortcut` passes before and after; it guards the regression.)

- [ ] **Step 3: Implement in `scenes/editor.gd` `_unhandled_input`**

- Right/middle press stores `_pan_from = {"screen": event.position, "camera": _camera.position}` (new `var _pan_from := {}`); release clears it. `InputEventMouseMotion` with `button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)` and a non-empty `_pan_from` sets `_camera.position = _pan_from.camera - (event.position - _pan_from.screen) / _camera.zoom.x` and redraws `_marks`. Keep the existing `DEVICE_ID_EMULATION` guards.
- Wheel: keep the 1.1 / 0.9 steps and `ZOOM_RANGE`; after changing zoom, shift the camera so the world point under `event.position` stays put. The camera is centre-anchored, so with `half := get_viewport().get_visible_rect().size / 2.0`: `world := _camera.position + (event.position - half) / old_zoom`, then `_camera.position = world - (event.position - half) / new_zoom`.
- `InputEventKey` pressed, not echo: `event.is_command_or_control_pressed()` with `KEY_Z` → `doc.undo()` + `_refresh()`; with `KEY_S` → `save()`; plain `KEY_T` → `_test()`. Call `get_viewport().set_input_as_handled()` after each.
- Header comment: append "A mouse pans with the right or middle button and zooms with the wheel; Ctrl/Cmd+Z undoes, Ctrl/Cmd+S saves, T test-flies."

- [ ] **Step 4: Run tests to verify they pass**

Run: `tests/run.sh`
Expected: all tests PASS, exit 0.

- [ ] **Step 5: Smoke on desktop**

Run: `godot --path .` → My levels → Edit a level. Right-drag pans; right-drag starting on the top bar does nothing; wheel zooms toward the cursor; place a planet, `Ctrl+Z` removes it; open Settings, type `t` in the title field, no test flight; close it, press `T`, test flight starts.

- [ ] **Step 6: Commit**

```bash
git add scenes/editor.gd tests/test_editor.gd
git commit -m "feat(editor): pan, cursor zoom and shortcuts with mouse and keyboard"
```

---

### Task 3: Desktop builds in CI

**Files:**
- Modify: `export_presets.cfg` (append presets 2-4)
- Modify: `.github/workflows/build.yml` (templates unzip at line 58, export steps, upload-artifact paths, `gh release create` files and notes)
- Modify: `docs/superpowers/specs/2026-10-16-level-editor-design.md:14` ("Where" row: point to the 2026-10-20 desktop editor spec)
- Modify: `README.md` (one line: desktop builds on each prerelease; unsigned, with the macOS right-click → Open and Windows SmartScreen notes)

**Interfaces:**
- Consumes: Tasks 1-2 merged (the builds ship them).
- Produces: release assets `zero-gx-windows.exe`, `zero-gx-linux.x86_64`, `zero-gx-macos.zip`.

- [ ] **Step 1: Add the presets**

Three sections named `"Windows"` (`platform="Windows Desktop"`, `export_path="build/zero-gx-windows.exe"`, options `binary_format/embed_pck=true`, `application/modify_resources=false`), `"Linux"` (`platform="Linux"`, `export_path="build/zero-gx-linux.x86_64"`, `binary_format/embed_pck=true`) and `"macOS"` (`platform="macOS"`, `export_path="build/zero-gx-macos.zip"`, `application/bundle_identifier="dev.braitg.zerogx"`, `codesign/codesign=1` for the built-in ad-hoc signature, `notarization/notarization=0`). Each copies the Android preset's `include_filter` and `exclude_filter` verbatim. Windows and Linux x86_64 only.

- [ ] **Step 2: Export locally to check the presets**

Run: `godot --headless --path . --export-release "macOS" build/zero-gx-macos.zip && unzip -l build/zero-gx-macos.zip | grep -c levels` (needs local 4.7.2 export templates).
Expected: exit 0; `ditto -x -k build/zero-gx-macos.zip /tmp/zgx && open /tmp/zgx/*.app` launches to the main menu; My levels → Import works.

- [ ] **Step 3: Extend `build.yml`**

- Templates unzip (line 58): also extract `templates/linux_release.x86_64 templates/windows_release_x86_64.exe templates/macos.zip`.
- New step "Export desktop builds" after the APK export: `--export-release` for `"Windows"`, `"Linux"`, `"macOS"` to the paths above.
- Add the three files to `upload-artifact` `path` and to `gh release create`. Append to the release notes: "Desktop builds (Windows, macOS, Linux) are unsigned: on macOS right-click the app and choose Open; on Windows choose More info → Run anyway; on Linux run `chmod +x` first."

- [ ] **Step 4: Update the docs**

Level-editor spec line 14 and the README line, as listed under Files.

- [ ] **Step 5: Verify CI**

Run: push the branch, then `gh run watch` on the `build.yml` run.
Expected: run succeeds; the artifact `zero-gx-apk` lists the APK, AAB and three desktop files.

- [ ] **Step 6: Android device smoke** (author, on a phone, with the CI APK)

My levels → Export a level to Drive → Import it back from Drive → a second copy appears. Covers Review Focus 5.

- [ ] **Step 7: Commit**

```bash
git add export_presets.cfg .github/workflows/build.yml docs/superpowers/specs/2026-10-16-level-editor-design.md README.md
git commit -m "build: Windows, macOS and Linux builds on every prerelease"
```
