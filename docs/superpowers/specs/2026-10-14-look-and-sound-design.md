# Look and Sound Design

Date: 2026-10-14
Status: Creative direction delegated by the developer ("some creative control, no need to go crazy")
Part 3 of 3 of the vertical slice

## Direction

**Neon vector space.** Deep blue-black space, thin glowing lines, soft light, and synthesized sound. Everything stays code-drawn and procedural, with no image, audio or font files. Every addition must also help play, not only look good:

- A **starfield** shows motion when no wall is in view, which matters in a game about inertia.
- A short **exhaust trail** shows the ship's path, so drift and gravity bending are visible.
- **Shake, flash and vibration** make hits readable and make damage feel physical.

## Items

| Area | What |
|---|---|
| Bloom | Real 2D glow through a `WorldEnvironment`, if the Compatibility renderer supports it on Android. Otherwise keep the hand-made glow. |
| Background | Three parallax star layers (`Parallax2D`) and faint nebula blobs on the farthest layer, in levels and on the menu. |
| Ship | Outlined hull with a cockpit; a flickering two-tone flame; exhaust particles; a fading trail; a red flash on damage; a particle explosion. |
| Feedback | Camera shake scaled by damage (strong on explosion); phone vibration on hits. |
| Bodies | Planets shaded like spheres with an atmosphere rim and a per-planet hue; black holes with a rotating accretion ring and a bright photon ring; stars with a pulsing corona. Asteroids with an outline and craters. |
| Goal | Rings expanding outward from a soft core. |
| UI | One theme: translucent dark panels and buttons with rounded corners and blue borders; a glowing title. |
| Countdown (#8) | A large pulsing number with an "OUT OF FUEL" caption, and a tick sound each second. |
| Sound | A seamless ambient drone; an engine whose pitch follows speed; a laser "zap" for barrier hits and a "thud" for bodies; distinct sounds for each pickup kind; a deeper explosion; a richer goal chime. |

## Constraints

- Phone performance: CPU particles, small particle counts, no per-pixel shaders unless bloom needs them.
- Startup sound rendering stays under about 0.3 s on a phone, so the drone loop is 4 s long.
- Gameplay and tests are unchanged. Feedback logic (shake decay) gets a test; looks are checked on the emulator.

## Out of scope

- Music beyond the ambient drone.
- New gameplay.
