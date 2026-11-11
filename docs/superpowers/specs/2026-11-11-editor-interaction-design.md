# Level editor interaction redesign

Revision 3: incorporates design review rounds 1 and 2 (S1–S20, G1–G10).

## Goal

Make the level editor behave like established editing tools, so a mouse and keyboard on desktop and a finger on a phone both grab what the user points at, reshape walls, and size bodies while looking at them. The level format, `LevelFormat` validation, test flights, import and export do not change.

The patterns come from vector editors (Figma, Inkscape: the nearest handle wins, a selection shows handles, a midpoint handle adds a point) and game level editors (Super Mario Maker, Tiled: tap selects, long-press or right-click opens a context menu, properties edit in place).

## Problems in the current editor

| Problem | Cause |
|---|---|
| Two close points: the wrong one is grabbed. | `LevelDoc.hit` checks things in a fixed type order and returns the first match. Every wall point is tested first with 1.5 × the grab radius, so the first point in the list wins, not the closest. |
| The grab area is too wide for a mouse. | One radius (`HIT_SLOP`, 40 screen px) serves touch and mouse. |
| A closed wall's last edge cannot be grabbed. | `hit` stops at `points.size() - 1`. |
| Grabbing a wall in the middle makes it jump. | `LevelDoc.move` puts the wall's first point at the pointer. Bodies jump to the pointer too. |
| A wall cannot gain a point. | `LevelDoc` adds points only while drawing a new wall. |
| Body sizes are set blind. | Radius, mass and reach sliders sit in a full-screen `Overlay` sheet that hides the level. |
| Wall colour is a text dropdown. | `_kind_option` builds an `OptionButton`. |
| My levels has no picture of a level. | The rows show text only. |

## Picking

One editor picker serves click, tap, hover and the context menu, with the slop of the device that sent the event.

**Units.** Canvas and chrome sizes are in **viewport units**: the coordinates `event.position` already uses under the project's `canvas_items` / `expand` stretch (base 1280 × 720). They are not physical pixels and not dp. Picking distances are viewport units divided by the camera zoom:

- Touch: `HIT_SLOP`, 40 units of radius (about a 48 dp diameter on a 2400 × 1080, 420 dpi phone, whose stretch is 1.5).
- Mouse: `HIT_SLOP_MOUSE`, 14 units.

New chrome controls (colour buttons, menu rows, Close, slider, number box) are at least 48 dp tall, converted once from display density and the stretch factor: 84 viewport units on that phone. Handle markers may be drawn smaller than their hit area. Godot's emulated mouse events from touch stay ignored, as today.

Candidates come in four groups. The first group with a candidate in reach wins; inside a group, the smallest distance wins, and ties keep list order.

| Group | Candidates | Distance | Reach |
|---|---|---|---|
| 1. Points | The selected thing's handles (wall point handles, "+" midpoint handles, body knob targets); every wall point; ship; asteroids; pickups | to the centre | `slop` |
| 2. Bodies | Planets, stars, black holes | to the centre | `LevelDoc.drawn_radius(body) + slop` |
| 3. Wall segments | Every segment of every wall, including the closing edge of a closed wall | to the segment | `slop` |
| 4. Goal | The goal | to the centre | `Goal.RADIUS` |

A handle does not beat a closer point: the selected wall's "+" handle 13 units away loses to another wall's point 2 units away. A segment through a body picks the body (walls near bodies are reshaped through their points and "+" handles, which are group 1). A segment through the goal ring picks the segment, so that wall stays grabbable; an empty spot inside the ring picks the goal. The 1.5 × factor for wall points is removed.

`LevelDoc.hit(at, slop)` keeps document geometry only (groups 1–4 without handles), with the closing edge fixed. Selection and handles live in `LevelEditor`, whose picker checks handles together with group 1.

## Selection

Selecting applies to the **Select tool** only. The Wall, placing, Start, Goal and Erase tools keep today's press and tap, including grab-instead-of-stack and erase-on-release.

- **Click or tap** selects the picked thing; empty space clears the selection.
- **Drag** moves the picked thing. Nothing moves before the drag threshold (`DRAG_START`, 12 viewport units). A whole wall or body keeps the offset between pointer and object captured at press: it moves by the pointer's displacement, as one snapped translation for a wall, so nothing jumps. Point handles follow the pointer, snapped.
- **Hover** (mouse only): the thing a click would pick gets a thin neutral outline. Hover never hides the selection.
- The **selected** thing shows its handles (see Walls and Bodies).

Selection is cleared after undo, delete, switching tool, save and test flight, so no index ref outlives a change to the arrays. Selecting another thing or clearing the selection first closes the old context menu and property panel and ends its edit session; no write from that panel reaches the new selection.

### Gesture ownership

- The context menu, property panel and colour strip take their own presses: a press on them never selects, places, moves or opens a menu on the canvas.
- A second finger cancels the one-finger edit in progress (a move, knob drag, midpoint insertion, or a placement this press already made) back to the data before the gesture, with no history entry, then pans and zooms. Edits finished before the gesture stay.
- Mouse left never starts the long-press timer; right-click is the only mouse route to the menu. A left-hold without a drag does nothing extra.

### Keyboard

| Key | Action |
|---|---|
| `Delete`, `Backspace` | Delete the selection. A selected wall point removes only that point. |
| `Esc` | Close the context menu; otherwise close the property panel; otherwise end the wall being drawn; otherwise clear the selection. |
| `Enter` | End the wall being drawn. |
| `Ctrl/Cmd+Z` | Close the menu and panel, then undo one step. |
| `Ctrl/Cmd+S`, `T` | Unchanged: save, test flight. |

While a text or number field has focus, `Delete`, `Backspace`, `T` and undo go to the field and never to the level; `Esc` still closes the panel. The Level settings overlay stays modal and blocks canvas editing and shortcuts, as today.

### Android Back

Back first lets the OS dismiss its keyboard, then closes the context menu or property panel, and only then saves and leaves the editor, as today. While the OS keyboard is up, the canvas hint is hidden.

## Undo

Only real edits enter the history.

- Selecting, hovering, opening and closing a menu or panel, and a gesture that changes nothing record nothing.
- Each drag, point insertion, recolour, deletion and knob drag is one undo step, recorded on its first actual change.
- A property panel session is one undo step: the first effective change records the pre-edit state, later changes in the same session write in place. Coupled values (radius and strength) change inside that one step.
- Closing a panel with `Esc` or Close keeps its edits. Undo, a tool switch, save, test flight, selecting something else, and a new drag on the same target close the panel and end its session first; the drag then records its own step.

`LevelDoc` therefore gains a way to write without a snapshot after a session has begun; `set_property` and `set_setting` no longer snapshot on every call when used from a session.

## Walls

A selected wall, or a selected point of a wall, shows:

- A handle on each point. Dragging it moves that point, snapped to the grid.
- A "+" handle at the middle of each segment, including the closing edge. A press without a drag inserts the exact geometric midpoint, rounded to whole coordinates and not snapped. A drag inserts the point and moves it, snapped. Either way it is one undo step, and the new point becomes the selection.
- **Double-click** a segment (Select tool, mouse) inserts a point at the snapped pointer position.

If an insertion lands on an adjacent point, nothing is inserted and nothing is recorded.

`LevelDoc` gains `insert_wall_point(wall: int, after: int, at: Vector2) -> Dictionary`. It inserts after point `after`; on an open wall `after == points.size() - 1` appends; on a closed wall the edge from the last point back to the first inserts after the last point. It returns the new point's ref.

### Removing points

`Delete`, `Backspace`, Remove point and the Erase tool share one rule for a **wall point**: on a closed wall of four or more points, ask **Keep closed** or **Open here**; otherwise remove the point, and remove the wall if fewer than two points are left. The Erase tool on a segment, and **Delete wall**, remove the whole wall without that question.

## Bodies

A selected body shows two edit rings, each with a labelled knob:

- **Radius** ring, knob up and to the right of the centre.
- **Reach** ring, knob down and to the right.

Ring radii follow the body's real radius and reach at the current zoom. Values are whole pixels, clamped to `LevelFormat.KIND_LIMITS[kind]`. Changing the radius keeps the total pull (mass) constant: `strength = total_pull / (radius / 1000)²`. The two values stay independent, as the limits are.

A knob drag keeps the press offset, so the value never jumps on press or on the first move: `value = value_at_press + (pointer distance from centre − pointer distance at press)`, then clamped.

Each knob's **hit target** sits at least one `slop` clear of the body's centre and of the other knob. When the real ring point is closer than that, the target moves out along a short leader line from the ring point, and the centre stays the body's move target. When a ring is off-screen, the Radius and Reach entries of the context menu still edit it.

## Context menu and property panel

**Right-click** (mouse) or **long-press** (touch, every tool) on a thing opens a context menu. A right-press that moves past the drag threshold pans instead, as today; middle-drag and trackpad pan stay. A long-press does nothing else first: it does not place, erase, insert or move, and its release is consumed. The goal and empty space have no menu.

Placement: next to the mouse pointer; for touch, above the finger and at least 24 viewport units clear of it. If the menu does not fit above, it goes beside the finger with the same clearance; it is then clamped to the free canvas and scrolls if it is still too tall. Rows never shrink below 48 dp to fit.

| Thing | Menu items |
|---|---|
| Wall | Colour (Blue, Orange, Red), Delete wall |
| Wall point | Remove point, Colour (of its wall), Delete wall |
| Planet | Radius, Mass, Reach, Destructible, Health, Delete |
| Star, black hole | Radius, Mass, Reach, Delete |
| Asteroid | Orbit speed (orbiting rocks only), Delete |
| Pickup | Kind (Thrust up, Thrust down, Boost), Delete |
| Start | Start motion |

Colour, Kind, Destructible and the deletions act at once. A numeric item opens the **property panel**:

- One opaque dark panel in the existing `Style` look, with a quiet border: the property name and units, a Close button, a slider and a number box. Radius, Mass, Reach, Health and Orbit speed have one row; **Start motion** has two rows, Direction and Speed, so a heading survives while the speed is zero. Speed 0 removes the velocity, as today.
- About 360–420 viewport units wide on a 1600 × 900 desktop. On a phone in landscape it is a compact side panel: the title has its own line, the units or help text a second wrapping line (at least 14 sp; control labels at least 16 sp), and the slider and number box may take two rows. Its content scrolls if it is too tall; Close and the focused field stay reachable.
- It sits beside the edited thing with a small gap, flipping side at the edges of the free canvas, and stays clear of the top bar, the colour strip, the hint line, the palette and the knob being dragged. It stays put for the session. If the thing's centre is off-screen, it goes to the nearest free corner of the canvas. It never pans the camera. It keeps out of safe-area insets and of the rectangle the OS keyboard covers.
- The slider and number box share bounds, step and units, as `_number_box` does today. Text that is not a finite number in range is not written to the level.
- Ranges and units stay as today: Mass is the pull at 100 m (`LevelFormat.total_pull`), Orbit speed is signed rad/s, Health 1–1000.
- Opening a panel does not change an old out-of-range draft; an actual edit clamps and stores the affected values within that edit's undo step.

The full-screen per-thing sheet (`_open_sheet`, `_choice`, `_slider`) is removed. The reclose question becomes a two-item context menu. The Level settings overlay stays as it is.

## Visual treatment

- Marker sizes, label sizes, stroke widths and dash lengths stay constant in viewport units at every zoom; ring radii follow the world values and the zoom. Touch uses larger markers than mouse.
- Selection: an accent stroke over a dark under-stroke, so it shows on blue walls and blue UI. Hover: a thinner neutral outline.
- Wall points: solid light circles with dark edges; the selected point gets an extra accent rim. "+" handles: smaller outlined markers with a visible plus, never the vertex shape.
- Body edit rings: crisp dashed strokes with a dark under-stroke, distinct from the faint gravity-field arcs. The knobs are labelled Radius and Reach; the active knob shows its value and units on a small dark backing.
- Only the selected thing gets this treatment; unselected geometry stays quiet.
- Canvas decorations (selection outlines, rings, leaders, knob labels) draw below all chrome, the menu and the panel, clipped to the free canvas. The menu and the panel are fully opaque. Knob labels flip to the other side of their knob at the canvas edge.
- The selection outline stays thinner and quieter than the active edit handle.

## Wall colour strip

The Wall tool's bar becomes a compact opaque strip at the top right, under the top bar and clear of Test:

- Three toggle buttons, Blue, Orange and Red. Each shows a solid chip of the exact wall colour on the existing dark button surface, with its label beside the chip for contrast. The pressed one has a checkmark and an outline, so it reads in greyscale.
- **Done** stays in the strip while a wall is being drawn, and hides otherwise.
- The strip shows while the Wall tool is active or a wall or wall point is selected. With a selection, the pressed button is that wall's colour and pressing another recolours it (one undo step). Without a selection, it sets the colour of new walls.

## Hints

The hint line above the palette is updated in the same slice as each gesture change:

- Select tool, mouse: "Click to select · drag to move · right-click for properties".
- Select tool, touch: "Tap to select · drag to move · hold for properties".
- A wall selected: "+ adds a point". A body selected: "Drag Radius or Reach to resize".

The hint gets a subtle dark backing where the level competes with it, and may take two lines on a narrow screen instead of clipping.

## Thumbnails in My levels

Each level card starts with a 16:9 slot, about 128 × 72 UI units, holding `Thumbnail.of_sketch(LevelFormat.sketch(data))`, the picture the community list uses. It ignores the mouse. It is computed from the saved level when the list is built, so new, edited, imported and even invalid levels show their current shape. No image is stored.

The title and status sit beside the thumbnail; a long title ends in an ellipsis. When the actions do not fit beside them, they wrap to a second row in the same card. No action is hidden and there is no horizontal scrolling. Warnings and publishing status stay below, in the card.

## Testing

Behavioural tests in `tests/test_level_doc.gd` and `tests/test_editor.gd`, using routed mouse and touch events at a zoom other than 1 where input matters:

- Two points closer than the slop: a press nearer the second picks the second, with and without another wall selected.
- A "+" handle and another wall's point in reach: the closer one wins.
- A point inside the goal ring wins within its slop; a segment crossing the ring wins near it; an empty spot inside the ring picks the goal.
- A segment through a planet: the planet wins unless a point or handle is closer.
- Mouse and touch slop differ: a press 20 viewport units from a point picks it by touch and not by mouse.
- The closing edge of a closed wall can be picked, moved and split.
- Dragging the middle of a long wall or the edge of a body moves it without a jump.
- `insert_wall_point` on open and closed walls, the midpoint click (exact midpoint) and drag (snapped) paths, and a duplicate insertion that records nothing.
- All four point-removal paths ask Keep closed or Open here on a closed four-point wall.
- A radius knob drag keeps the total pull and does not jump; knobs clamp; radius equal to reach, reach 0, and a minimum-size body at minimum zoom keep separate centre, Radius and Reach targets.
- Opening and closing a menu or panel records nothing; a panel session is one undo step; selecting something else ends it.
- Right-click opens the menu; right-drag pans; mouse left-hold opens nothing. Long-press with the Wall, Erase and placing tools opens the menu without changing the level. A second finger during a knob drag, a midpoint insertion, or a placing press cancels it with no history entry and no new thing.
- A press on the menu, the panel or the colour strip does not reach the canvas.
- The Erase tool on a segment removes the wall without asking.
- With a number field focused, `Delete` and undo do not change the level; `Esc` closes the panel.
- A swatch recolours the selected wall.
- A My levels card shows a thumbnail for an imported invalid level, and all its actions on a narrow screen.

## Delivery

One branch, in this order, each slice tested and reviewed:

1. Picking, selection, undo sessions and gesture rules. Tap in the Select tool selects instead of opening the sheet; long-press still opens the sheet until slice 4, so no property becomes uneditable.
2. Wall point handles, insertion and the shared point-removal rule.
3. Body edit rings.
4. Context menu and property panel; long-press switches to the menu; the full-screen sheet is removed.
5. Colour strip and My levels thumbnails.

Each slice updates the hint text for the gestures it changes.

Visual acceptance: slices 3–5 are rendered from the real editor at 1600 × 900 and at phone landscape and reviewed against these rules, including a target near each edge, an off-screen star, a minimum-size body, the touch menu and a focused number field with the keyboard up.

## Out of scope

Multi-select, box select, copy and paste, redo, rotating things, a tool framework and any change to the level format.
