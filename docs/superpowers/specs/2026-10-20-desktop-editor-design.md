# Desktop level editor and level import/export

## Goal

Build and edit Zero-GX levels on Windows, macOS and Linux, mainly so the author can work on the official levels with a mouse and keyboard, and also for players on those platforms. Levels move between the phone app and the desktop as files. The desktop build can open, edit, test-fly and record demos of a level. Final demos, scores and submissions still come only from the Android app, which the server already enforces (community design, R5).

## Decisions

| Topic | Decision |
|---|---|
| Codebase | The existing Godot project. No second editor. The desktop editor is `scenes/editor.gd` with extra mouse and keyboard input. |
| Platforms | Windows, macOS and Linux now. A web build comes later. |
| Moving levels | Files, through native file dialogs (`DisplayServer.file_dialog_show`). On Android this is the system picker (Storage Access Framework), which covers Downloads, USB and local storage. Drive may not be listed, because Godot's Android picker asks for local files only. No Android share sheet for now. |
| File format | The existing level format. Export always writes plain `.json` in the stable `LevelFormat.to_json` layout. Import accepts `.json` and `.json.gz`. |
| Official levels | No special mode. Import `levels/<id>.json`, edit, test, then export over the same file. The stable layout keeps `git diff` limited to real changes. |
| Demos | Test flights on desktop record and replay through the existing `MyLevels.save_demo` and Watch. Demos stay on the device. There is no demo export. |
| Community features | The app has no community client yet. When it gets one, its UI shows only when `OS.has_feature("android")`. |

## Import and export

The My levels screen (`scenes/my_levels_screen.gd`) gains an **Import** button in its top bar and an **Export** button on each level row. Both platforms use the same code.

**Import**

1. Open a file dialog filtered to `*.json` and `*.json.gz`.
2. Reject files larger than 64 KB before parsing; this is the server's submission limit.
3. Parse with `LevelFormat.read`. The file must be a JSON object whose `format` is `"zero-gx-level"` and whose `version` is the current `LevelFormat.VERSION`.
4. Unfinished drafts are accepted: `LevelFormat.validate(data, true)` checks only that the file is well formed (types and shapes), not its sizes, ranges, limits or placement, so half-built levels can move between phone and PC. The editor shows the level's problems, and Play stays disabled until it is valid, as for any draft. A file with the wrong shape (for example a missing ship or a number for the title) is refused.
5. On any error, show the errors in an overlay and save nothing.
6. On success, save the level under a new id from `MyLevels.new_id()`. Import never overwrites an existing level.

**Export**

1. Open a save dialog. The default file name comes from the level title.
2. Write `LevelFormat.to_json` of the saved level.
3. If writing fails, show a short message. A cancelled dialog does nothing.

The import and export logic takes a file path, separate from the dialog, so tests can call it directly.

## Desktop input in the editor

Additions to `_unhandled_input` in `scenes/editor.gd`. The touch path does not change, so Android behaviour cannot regress. The left mouse button already acts as a finger, and the ship already flies with the left mouse button.

| Input | Action |
|---|---|
| Right-drag or middle-drag | Pan, with the same camera maths as a two-finger drag. |
| Mouse wheel | Zoom around the cursor. The wheel already zooms, but around the screen centre. |
| Trackpad pinch and swipe (macOS) | Zoom around the cursor, and pan. |
| `Ctrl+Z` / `Cmd+Z` | Undo (`LevelDoc.undo`). |
| `Ctrl+S` / `Cmd+S` | Save (`save`). |
| `T` | Test flight (`_test`). |

There is no redo and no Delete key: `LevelDoc` has no redo, and the sheet already deletes things.

## Finer grid and easier wall points

These apply to touch and mouse alike.

- **Two grid modes.** Normal is the default: walls, the start and the goal snap to the 10 m (100 px) step. The **Fine grid** toggle switches to Fine mode, where they snap to the 1 m (10 px) step. The drawn grid follows the mode: in Fine mode, 1 m lines are drawn in faint white once they are at least 8 screen px apart, with the 10 m lines drawn over them; in Normal mode, and in Fine mode when zoomed out further, only the 10 m lines are drawn, as before.
- **Pick radius in screen pixels.** `LevelDoc.hit` takes the pick radius as a parameter. The editor passes `HIT_SLOP` divided by the camera zoom, so a target is the same size under the finger at every zoom. Today the radius is 40 world px, which is only 20 screen px at the default zoom of 0.5.
- **Wall points win over walls.** Wall points get 1.5 times the pick radius and are still checked first, so a near miss on a point moves the point, not the whole wall.
- **Visible handles.** Every wall point is drawn as a small dot. With the Select, Wall or Erase tool, each dot also has a ring.
- **Close circle.** The circle around a wall's first point, and the distance that closes a wall, are 20 screen px at every zoom.

## Builds

New export presets: Windows (`.exe`), Linux (`.x86_64`) and macOS (`.zip`). The display is already 1280×720 landscape with `canvas_items` stretch, so a resizable desktop window scales correctly. `.github/workflows/build.yml` exports the three builds on its existing runner and attaches them to the prerelease beside the APK.

The desktop builds are not code-signed. On macOS the first launch needs System Settings → Privacy & Security → Open Anyway (macOS 15 and later; older versions use right-click and Open); on Windows SmartScreen shows a warning.

## Tests

In the existing `tests/` runner:

- **Round-trip through a draft:** importing an official level and exporting it again produces a file byte-identical to the original, under a new `user_` id, with the original untouched. (`tests/test_level_format.gd` already checks that every official level is in the stable layout.)
- **Import rejects bad files:** invalid JSON, a JSON value that is not an object, a wrong `format` or `version` (including values of the wrong type), a file with the wrong shape (a bare header, a number for the title, an unknown wall kind), and a file over 64 KB each leave no level saved. An unfinished draft imports, and a gzip level imports whatever its file name.
- **Grid and picking:** a new wall point snaps to 1 m by default; at zoom 0.2 a press 30 screen px from a wall point picks the point, and a press on the middle of a segment picks the wall.
- **Editor input:** right-drag pans; wheel zoom and trackpad pinch keep the world point under the cursor fixed; a trackpad swipe pans; `Ctrl+Z` undoes the last change, but not with a sheet open or with Shift held.

Smoke test before release: run a local desktop build, import an official level, edit it, test-fly it, and export it.

## Not included

- A web build.
- An Android share sheet (`ACTION_SEND`).
- Demo export or import.
- Editing files in place on desktop.
- Redo and a Delete key.
- Code signing for the desktop builds.
