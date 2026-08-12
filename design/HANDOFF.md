# Handoff — 2026-08-12

Both repos clean, built, pushed. Engine at `106459a5ca`, mod at `e502bff`.
`GlowInTheDark.zip` is current.

---

## The one idea

**Stop placing objects to represent an effect; give the fragment shader the
maths.** A sweep asks a pixel its distance from a point. A beam asks its
distance from a segment. Fog asks how much of the eye-to-pixel ray lay below a
plane. Darkness asks what a pixel's own light is rather than what its room's is.

Every feature here is an instance of that, and it is why a lattice can be four
lines or four hundred for the same cost. When something new is asked for, the
first question is *what question does a pixel ask*, not *what do I spawn*.

---

## What shipped this session

| | |
| --- | --- |
| **Tornado** | mist around a vertical axis; hollow centre so you can stand inside; can follow the nearest live monster |
| **Fog bottom edge** | one number that makes the slab floor fog, ceiling fog, a chest-height band, or drain/fill |
| **Vertical hold** | the layer repeats up the room and rolls, for the price of one layer |
| **Reactive fog** | one disturbance primitive, eight slots: wake / ripple / ignite / gout, plus displacers |
| **Density noise** | mist banks and drifts instead of being one number for the map |
| **Tendrils** | wisps as a `fract()` lattice — hundreds cost what one costs |
| **Bow wave** | a sweep band shoulders the air in front of it |
| **Heatmap** | 256² grid over the map, accumulates deaths, drawn as a PP pass, readable from script |
| **Selective desaturation** | drain weighted by each colour's own saturation — grey world, red blood |
| **Laser grid** | folded into the sweep; it is what a band *fires*, not its own toggle |
| **Presets** | Black and White + OMGWTF ship; the other three stay off |

### Bugs fixed, all of them silent

- **The flashlight was never radial.** `AttackAngle` is stored as world yaw
  minus 90 and `AttackPitch` is stored negated; `ResolveMount` read them raw.
  The cone was aimed 90° right and upside down, forever. Also missing
  `+DYNAMICLIGHT.ATTENUATE`, so every surface in the cone lit identically.
- **The volumetric cone had never drawn a lit pixel.** A general ray/cone solve
  is degenerate when the apex is at the eye, which is the normal case.
- **GITD was erasing RS_Main's laser gun beams every tic** via an absolute
  `SetBeamCount(0)` on a shared global, after psprites had written theirs.
  Nothing in GITD touches beams now.
- **Vulkan: there are four uniform lists, not three.** Missing a `#define`
  compiles fine on GL and fails at startup on VK.
- **The render push froze** whenever a sweep ran with underlay off.

---

## Two rules this project keeps re-learning

**1. Turning something off is a thing you DO, not a thing you skip.** A push
that returns early leaves the last value live in engine state, so the feature
keeps costing its full per-fragment price while the switch naming it reads Off.
Cost three separate days: eight beams standing in an empty room, a tornado
whose density uniform was only written when floor fog happened to be on, and
the whole render push freezing under a sweep.

**2. A uniform in `HWViewpointUniforms` means FOUR lists, not three.**
`hw_viewpointuniforms.h`, the GL block in `gl_shader.cpp`, the VK struct in
`vk_shader.cpp`, **and a `#define` per field in `vk_shader.cpp`**. The first
three are matched by byte offset. Both checks are one line each and written at
the top of `hw_viewpointuniforms.h`. Run them before building.

Also: frame-global values go in `HWViewpointUniforms`, **never** `StreamData` —
StreamData's size divides a fixed 64KB into `MAX_STREAM_DATA` draws, so growing
it costs draw batching every frame forever.

---

## Gotchas that have bitten

- `packed` is reserved in GLSL. `cross` and `dot` are reserved in ZScript.
- ZScript rejects a trailing comma in a `static const` array initialiser, and
  the error points at the closing brace.
- `Color(int)` does not convert on this engine — build it from bytes.
- Deleting a handler's file is half the job; it must leave `mapinfo.txt` too.
- The build cannot link while `doomxr.exe` is running. Compilation still
  succeeds, so a lone `LNK1104` means the code is fine and the game is open.
- Repack with `Compress-Archive`, excluding `.git .claude .gitignore design *.md`.

---

## Open work

### Tabled, with requirements already agreed

**Floor shapes, seam reveals, and their use as combat telegraphs.** A shape on
the floor is one distance function — square is `max(|dx|,|dz|)`, circle is
`length()`, complex shapes are `min`/`max` of simple ones. A seam reveal is
that plus a second threshold that grows with age, which is the disturbance
primitive with a shape mode. Two requirements were stated and must be in the
initial scope, not proposed as follow-ups:

1. **Billboard mode is wanted regardless of difficulty**, specifically so a
   shape can call in monsters — a marker that stands up out of the floor rather
   than only lying on it. The fork's billboard system already exists.
2. **Lift the slot caps.** `MAX_FOG_DISTURB` and `MAX_BEAMS` are both 8 and
   that is explicitly too few. VR on a 3080 Ti; 8 was a budget for hardware
   they do not have.

### Raised, not yet scoped

- **10 presets, each with its own menu page.** Currently 2 ship of 5 written.
- **The tornado room.** A funnel in the centre firing laser grids outward in six
  directions, with holes punched in the grids to pass through. Every piece
  exists except the holes, which are one distance test subtracting from the
  lattice coverage.
- **`GITD_Setpiece`** — a template for scripted encounters built on these
  systems, tied to monster tiers and pack attacks.

### Known gaps

- The heatmap is a postprocess pass, so it paints **over** the frame rather
  than tinting the light, and cannot be occluded by translucent geometry. The
  scene-shader alternative is ~12 files and four coordinated Vulkan edits. The
  user has been told and has not yet chosen.
- Sky scaling is absent from per-pixel darkness (`uSweepPad1` is free for it).
- `BeamAirGlow` clamps `sc` to `fragDist` rather than rejecting, so a beam just
  behind geometry still glows through. Do **not** change it to a `continue` —
  that deletes near-parallel beams entirely. Documented, left alone.

---

## Working style that has worked

Long explanatory comments in the code carrying the *reasoning*, not the
mechanics — especially for anything that looks wrong until you know why. Commit
messages in the same register. The user reads them.

Build, pack, commit, push without being asked each time. They will say "ping me
when done" and mean it.
