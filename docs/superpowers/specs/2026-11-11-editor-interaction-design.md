# Level editor interaction redesign

## Goal

Make the level editor behave like established editing tools, so a mouse and keyboard on desktop and a finger on a phone both grab what the user points at, reshape walls, and size bodies while looking at them. The level format, `LevelFormat` validation, test flights, import and export do not change.

The patterns come from vector editors (Figma, Inkscape: nearest handle wins, selection shows handles, a midpoint handle adds a point) and game level editors (Super Mario Maker, Tiled: tap selects, long-press or right-click opens a context menu, properties edit in place).

## Problems in the current editor

| Problem | Cause |
|---|---|
| Two close points: the wrong one is grabbed. | `LevelDoc.hit` checks things in a fixed type order. Every wall point in the level is tested first with 1.5 × the grab radius, so the first point in the list wins, not the closest. |
| The grab area is too wide for a mouse. | One radius (`HIT_SLOP`, 40 screen px) serves touch and mouse. |
| A wall cannot gain a point. | `LevelDoc` can add points only while drawing a new wall. |
| Body sizes are set blind. | Radius, mass and reach sliders sit in a full-screen `Overlay` sheet that hides the level. |
| Wall colour is a text dropdown. | `_kind_option` builds an `OptionButton`. |
| My levels has no picture of a level. | The rows show text only. |

## Picking

`LevelDoc.hit(at, slop)` returns the thing closest to the pointer, in layers. The first layer that has a candidate within reach wins; inside a layer, the smallest distance wins. Ties keep list order.

| Layer | Candidates | Distance | Reach |
|---|---|---|---|
| 1. Handles | The selected thing's handles: wall points, "+" midpoint handles of a selected wall, a selected body's radius and reach knobs | to the handle centre | `slop` |
| 2. Points | Wall points of every wall, ship, goal, asteroids, pickups | to the centre | `slop`; the goal also counts its whole ring (`Goal.RADIUS`) |
| 3. Wall segments | Every segment of every wall | to the segment | `slop` |
| 4. Bodies | Planets, stars, black holes | to the centre | the body's drawn radius plus `slop` |

The 1.5 × factor for wall points is removed.

`slop` is in screen pixels, divided by the camera zoom as today:

- Touch: `HIT_SLOP` stays 40 px.
- Mouse: `HIT_SLOP_MOUSE` is 14 px. The editor uses it for mouse events, and `HIT_SLOP` for touch events.

## Selection

The Select tool selects instead of opening a sheet.

- **Click or tap** selects the picked thing; empty space clears the selection.
- **Drag** moves the picked thing, as today. One drag is one undo step.
- **Hover** (mouse only): the thing that a click would pick gets a thin outline, so the user sees the target before clicking.
- The **selected** thing is outlined in `Style.ACCENT` and shows its handles (see Walls and Bodies).

Keyboard, ignored while a text field has focus:

| Key | Action |
|---|---|
| `Delete`, `Backspace` | Delete the selection. A point taken from a closed wall with four or more points still asks whether the wall stays closed. |
| `Esc` | End the wall being drawn; otherwise clear the selection; otherwise close the property panel. |
| `Enter` | End the wall being drawn. |
| `Ctrl/Cmd+Z`, `Ctrl/Cmd+S`, `T` | Unchanged: undo, save, test flight. |

The Erase tool stays for touch, where there is no Delete key.

## Walls

A selected wall shows:

- A round handle on each point. Dragging it moves that point, snapped to the grid.
- A small "+" handle at the middle of each segment. Dragging it inserts a new point there and moves it with the drag, snapped. A press without a drag inserts the point in place.

Also:

- **Double-click** a segment (mouse) inserts a point at the snapped position under the pointer.
- **Dragging the segment** itself moves the whole wall, as today.
- **Removing a point:** select its handle and press `Delete`, or use Remove point in the context menu.

`LevelDoc` gains `insert_wall_point(wall: int, after: int, at: Vector2) -> Dictionary`, which inserts after point `after` (the last point of a closed wall connects back to the first), records one undo step, and returns the new point's ref.

## Bodies

A selected body shows two dashed rings with a round knob on each, at 45° up and to the right of the centre:

- **Radius ring** at the body's radius. Dragging its knob sets the radius to the knob's distance from the centre.
- **Reach ring** at its gravity reach. Dragging its knob sets the reach.

Values are rounded to whole pixels and clamped to `LevelFormat.KIND_LIMITS[kind]`. While dragging, the value shows as a label next to the knob. Changing the radius keeps the total pull (mass) constant, as the sliders do today. Each knob drag is one undo step.

## Context menu and property panel

**Right-click** (mouse) or **long-press** (touch) on a thing opens a context menu at the pointer, listing what that thing can change:

| Thing | Menu items |
|---|---|
| Wall | Colour (Blue, Orange, Red), Delete |
| Wall point | Remove point |
| Planet, star, black hole | Radius, Mass, Reach, and for a planet Destructible and Health; Delete |
| Asteroid | Orbit speed (orbiting rocks only), Delete |
| Pickup | Kind (Thrust up, Thrust down, Boost), Delete |
| Start | Direction, Speed |

Colour, Kind, Destructible and Delete act at once. A numeric item opens a **property panel**: a small floating panel with the item's name, a slider, a number box and a close button. It sits next to the thing on screen, kept inside the view, and the level stays visible and live behind it. Opening a panel records one undo step. `Esc`, the close button, or selecting something else closes it.

The full-screen per-thing sheet (`_open_sheet`, `_choice`, `_slider`, `_ask_reclose` as a separate Overlay) is removed. The reclose question becomes a two-item context menu (Keep closed, Open here). The Level settings overlay stays as it is.

## Wall colour

The wall tool's bar becomes three colour swatches at the top right, under the top bar. Each swatch is a toggle button filled with the colour its walls are drawn in, labelled Blue, Orange and Red. The pressed swatch is the colour of new walls. When a wall is selected, pressing a swatch recolours it (one undo step).

## Thumbnails in My levels

Each row in My levels starts with a small map of the level: `Thumbnail.of_sketch(LevelFormat.sketch(data))`, the same picture the community list uses. It is computed from the saved level when the list is built, so new, edited and imported levels all show their current shape. No image file is stored.

## Touch behaviour

Touch keeps its gestures: one finger runs the tool, two fingers pan and zoom, long-press opens the context menu (instead of the sheet). Taps select instead of opening the sheet. Handles are drawn large enough for a finger (radius 12 screen px, hit area `HIT_SLOP`).

## Testing

Behavioural tests in the existing suites (`tests/test_level_doc.gd`, `tests/test_editor.gd`):

- Two points closer together than the slop: a press nearer the second picks the second.
- A wall point beside another wall's segment wins only within its slop; the segment wins outside it.
- Mouse and touch slop differ: a press 20 screen px from a point picks it by touch, and not by mouse.
- `insert_wall_point` on open and closed walls, including after the last point of a closed wall; undo restores the original wall.
- Dragging a "+" handle inserts and moves one point in one undo step.
- Dragging a body's radius knob keeps the total pull; both knobs clamp to `KIND_LIMITS`.
- `Delete` removes the selection; `Esc` ends a wall, then clears the selection.
- A numeric property panel changes the level live and is one undo step.
- A swatch recolours the selected wall.
- A My levels row shows a thumbnail for an imported level.

## Delivery

One branch, delivered in this order, each slice tested and reviewed:

1. Picking and selection (layers, mouse slop, hover, keyboard).
2. Wall point handles and insertion.
3. Body ring handles.
4. Context menu and property panel; removal of the full-screen sheet.
5. Colour swatches and My levels thumbnails.

## Out of scope

Multi-select, box select, copy and paste, redo, and rotating things. `LevelDoc` has no redo, and these were not requested.
