# Orientation Design: Level Tours and Goal Arrow

Date: 2026-10-15
Status: Approved in conversation

## Purpose

A first-time player reported "I have no idea where I should go on the first stages" and "some stages are too big and I have no idea where I am". Players also skip the intro card's hint without reading it.

## Level tour

- On the first play of a level, the game pauses and a tour camera flies along the course, in the spirit of Angry Birds' opening pan:
  1. the goal ("Reach the green ring to finish the course."),
  2. each stop under the level's `Tour` node (`Marker2D` children, caption in `metadata/text`), in order,
  3. the ship ("This is your ship. Ready?"). A level stop already at the ship replaces this generic one.
- Each stop shows a caption card with a **Next** button (**Go!** on the last). The player must tap to advance. The camera flies between stops in 0.9 s, at zoom 0.8. The HUD is hidden during the tour.
- The tour plays only when the level has not been won and has not toured yet this session, so a restart after a crash goes straight to play. When the tour does not play, the intro card with the hint shows instead.
- A **Level tours** switch in the Tune panel turns tours off.
- Every level must have a `Tour` with at least one captioned stop; the level check enforces it.

## Goal arrow

- When the goal is off screen, a green arrow on the screen edge points at it, with the distance in px (`4.0k` above 1000).
- The arrow sits 48 px inside the edge, on the line from the screen centre to the goal.

## Sound

- Next and Go! play the tap sound, like every other button.
