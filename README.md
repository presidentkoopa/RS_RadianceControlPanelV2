# Glow In The Dark

Lighting for a fork of GZDoom built around darkness. Four independent glow
lanes, travelling bands of light that wrap every surface, real beams, mist you
stand in, and a darkness model that works per pixel instead of per room.

**Requires the forked engine.** Floor and ceiling glow, two colours per glow,
Sector Sweep, the volumetric beam, per-fragment darkness, glow waves, the fog
slab, real beams, and the bloom threshold and knee are all engine features that
do not exist in stock GZDoom. On stock this mod will not load.

Everything lives under **Options → Glow In The Dark**.

## What is here

| | |
| --- | --- |
| **Four glow lanes** | floor, ceiling, wall bottom, wall top — identical controls on each |
| **Presets** | five finished environments, each carrying a whole room rather than a palette |
| **Glow waves** | the *edge* of a glow rises and falls along a wall |
| **Sector Sweep** | up to eight bands of light travelling through the map |
| **Band fill** | a band can be a lattice or a slab instead of a wash |
| **Laser grid** | real beams standing across a corridor |
| **Beams** | segment lasers, continuous, visible in the air, no dynamic lights |
| **Darkness** | per room, or per pixel — with distance and height falloff |
| **Floor fog** | mist with a *top*, that you stand in and leave a trail through |
| **Flashlight** | volumetric beam with dust, four mount positions |
| **Muzzle flash** | a brief attenuated light at chest height when anything fires |
| **Bloom & exposure** | threshold, knee, anamorphic streak, tint, fringing, and an eye that adapts |

---

## The four lanes

| Lane | What it lights |
| --- | --- |
| **Floor Glow** (`fg`) | The floor surface itself, glowing inward from its edges |
| **Ceiling Glow** (`cg`) | The ceiling surface itself, glowing inward from its edges |
| **Wall Bottom** (`wb`) | The wall, lit upward from where it meets the floor |
| **Wall Top** (`wt`) | The wall, lit downward from where it meets the ceiling |

`wb` and `wt` are the glow mechanic stock Doom has always had. `fg` and `cg`
are new — a floor or ceiling that glows on its own face, not just spilling onto
the nearby wall.

Every lane has the same controls, deliberately: on/off, eight colour slots, how
many are in rotation, a transition pattern, transition speed, coverage, falloff
curve, intensity, and a pulse. If a control exists for one lane it exists for
all four, and it means the same thing on all four. **Coverage** is how far the
glow reaches; **Intensity** is how bright it is.

Each slot also has a **Duration** — how long that colour holds before moving
on. Durations are what turn a palette into a *rhythm*: a lane that sits on one
colour for twenty seconds and then flicks through three in a second is not a
colour scheme, it is a behaviour.

## Corners

Where a wall meets a floor, two glows arrive at the same line — the wall lit
upward from it, the floor lit inward from it — and both are at full strength
exactly where they touch. The hard edge there was never a missing blend. It was
the two sides disagreeing about what colour to be at a line they share.

**Seamless Corners** makes them agree at the line and disagree everywhere else.
Each glow carries two colours and ramps between them as it fades, so both
surfaces take the same blended colour where they meet and each fades back to
its own lane's colour going away from it. The corner reads as one continuous
gradient — floor colour, blend, wall colour — with no flat region and no seam.

Both junctions do this together, floor-to-wall and ceiling-to-wall, because a
room with only one of them ramping looks worse than a room with neither: the
eye finds the mismatch immediately.

> **Seamless Corners and Glow Waves are mutually exclusive.** The corner works
> by matching how far each glow reaches across the junction; a wave moves that
> edge. Run both and every corner grows a seam that travels along it. Turning
> waves on turns corners off, and the menu says so.

## Glow waves

A glow fades smoothly *up* a wall and used to be perfectly flat *along* it — a
dead straight top edge from one end of a room to the other.

Waves give it the other axis. The **edge itself** rises and falls as it
travels, so the band of light has peaks and valleys running along the wall. It
can also drive brightness, and the boundary between a glow's two colours,
independently — same wave, three completely different looks.

- **Wavelength and speed** — corrugation, or a swell that takes a corridor to arrive
- **Sharpness** — a gentle roll, or a narrow spike through an otherwise flat lane
- **Climb** — phase offset per surface, so one wave travels *up* through the
  room: floor, then lower wall, then upper wall, then ceiling
- **Detune** — a second wave that never lines up with the first, so it never
  repeats and never becomes a beat you can count
- **Per-room scatter** — without it the whole map undulates as one organism,
  which reads as a filter over the game rather than as lighting in it

## Presets

A preset is not a palette. It carries the whole room: 32 colours *and* their
durations, the shape of every lane, the darkness underneath, the air, the
flashlight, bloom and exposure, and whatever is travelling through.

**Choosing one replaces your settings. Disable Preset gives them all back** —
every value a preset overwrites is recorded first, so nothing is lost.

Five are finished. The others were removed rather than shipped half-built.

| | |
| --- | --- |
| **Blackout** | The absence. Pure black, crushed as far as the mod goes, nothing travelling, no mist. Defined by what it does not do. |
| **Low Power** | The grid is failing. Dying sodium, a slow brownout rolling along the corridor, dead air settled on the floor that holds your trail for seconds. Every few minutes the plant loses a round: it catches, it holds, it slips, it goes. The horror is that the dark is *scheduled*. |
| **Red Alert** | Containment breach, on a five-minute procedure. Klaxon beats in lockstep with a beacon turning overhead, a red band that floods the corridor and then drops it below its own baseline. Your eye adapts fast, so the room pumps with the alarm. |
| **Black and White** | Not a monochrome palette — a monochrome *world*. Colour drain takes the textures with it. Four surfaces on four clocks that never re-sync, hard cuts, an etched edge that has moved by the time you come back, and a neutral haze that refuses to be tinted by anything. |
| **OMGWTF** | Every system at once, turned up. Eight bands doing four different things, chest-deep fog that is a different colour in every direction, a laser grid riding the sweep at you, and an eye that never settles. It is a stress test with a paint job. |

## Sector Sweep

A train of up to eight bands of light travelling through the map, each wrapping
across floor, walls and ceiling as **one unbroken line**.

Five shapes: a ring expanding outward, a bar sweeping east/west or north/south,
a shell that grows in three dimensions, and a **rising** plane that climbs or
falls through the level. Every band has its own colour, speed, shape, origin
and spacing behind the one in front.

This is not one of the four lanes and could not be. A lane is per sector — one
colour for a whole room — so an expanding ring built that way would light rooms
in sequence, chunky and wrong. A sweep is tested per pixel against world
position, which keeps the line thin and lets it stay continuous where floor
meets wall meets ceiling. A cylinder cuts all three at the same radius; a plane
draws an unbroken rectangle around a corridor.

**What a band does** to the pixels it covers is per band:

- **Add** — a glowing line
- **Reveal** — multiplies the room up, pulling the dark aside
- **Shadow** — the same inverted: a band of travelling darkness
- **Re-colour** — drives all four lanes to shades of the band's own colour, so
  a green band leaves 32 cooperating greens behind it

Shadow is the one that surprises people. A dark band is far more legible than a
bright one in an already-dark room, because your eye tracks the edge rather
than the fill.

### Inside a band

A band does not have to be a wash. It can carry a **lattice**, a field of
**dots**, or a **solid slab** of light with hard edges.

Spacing is per axis, and zero in one axis means no lines in it — so a grid,
horizontal slats, and a single tripwire are all the same mode with one number
changed. Line width is in world units, so a line keeps its real size at any
distance instead of shimmering.

The band's own colour is the **field** and the fill colour is the **lines**.
With the gap at zero only the lines are lit and you see the room between them,
which is what reads as actual lasers; turn it up and it becomes a lit pane with
structure in it. Negative inverts it: lit gaps, dark lines, a grid of shadow.

Plus rotation, drift, per-line flicker, jitter, and every Nth line bolder.

## Beams and the laser grid

A laser in Doom is usually a sprite, or a chain of puffs close enough together
to read as a line. Both give themselves away: the sprite lights nothing, and
the chain stitches and gaps at range.

A beam here is a **segment**, and every pixel is lit by its distance from it.
That one difference buys everything:

- **Continuous** at any length — no repeat, no stitching
- **Wraps** floor, wall and ceiling as one object
- **It lights the room** — surfaces near it brighten because they *are* near it
- **Visible in the air**, not just where it lands, and **correctly hidden** by
  walls in front of it
- **It blooms by itself** — no dynamic light, no sprite, no quad
- **Energy travels along it**, it tapers tight at the aperture and blooms
  toward what it hits, and it flares where it lands

The **Laser Grid** stands eight of these across a corridor. It can ride the
sweep — the lattice sits on the travelling band and comes down the hall at you
— or stand still ahead of you as a tripwire.

> Band fill and the laser grid are meant to be used **together**. The fill
> draws the lattice *on* every surface, continuous around corners and up walls,
> which a straight beam cannot do. The beams put it *in* the air between those
> surfaces, which a fill cannot do. Both on, and the grid is drawn on the room
> and present in it.

## Darkness

Base darkening with four curves — subtract, compress, cap the brightest, deepen
the shadows — a nine-step dial, gains either side, a floor, and colour drain.

**Per-pixel darkness** is the same four curves asked a different question. Off,
a room is darkened as one: a long hall is exactly as dark at the far end as at
your feet, because a sector is the smallest thing the old way can talk about.
On, each pixel is darkened by its own light, and two things become possible
that a per-sector multiplier can never express:

- **Distance** — darkness deepening with range. This is what makes a dark room
  feel like it has depth rather than like the brightness slider went down. A
  corridor stops *ending* and starts stopping being visible.
- **Height** — dark pooling on the floor, or rising as a tide.

The dials mean the same thing in both modes, but they will not *feel* the same,
because they were tuned against the old one. Expect to re-taste the ladder.

## Floor fog

The fog on the Fog page is sector fog: a distance tint on surfaces, uniform
from floor to ceiling. It cannot have a ceiling or a thickness — you cannot be
knee deep in it, because it has no knees.

**Floor fog** is a slab of mist with a world-space top. You stand in it, look
down, and see its surface around your knees.

- **Top height and softness** — where the surface sits, and how sharply. Too
  hard and it reads as a sheet of coloured glass lying across the room.
- **Torch scatter** — the flashlight cone lights the mist it passes through
- **Picks up glow** — how much of whatever is behind it the mist takes on. At
  zero it is a flat colour over the scene and reads as a filter; turn it up and
  a red wall glow bleeds into the mist in front of it.
- **The wake** — walking clears a channel that closes behind you. The settling
  speed is the character: slow drags a long trail you can look back at, fast
  keeps the air moving.

## Flashlight

The beam is **volumetric** — visible in the air, not just the disc where it
lands. A real cone raymarched through the scene, cut off by walls, blooming and
feeding auto-exposure like any other light. It carries its own haze, so it does
not need fog in the room to show.

Four mounts: main hand, off hand, head, chest. The two hand mounts read their
own tracked pose in VR, so they are genuinely different positions rather than
one light nudged sideways.

Dust is sampled in **world space**, so motes stay put in the room as you sweep
rather than sliding along with the light.

**Bounce light** is a dim wide fill at the lens, and it is **off by default**.
It softens a harsh cone, and it is also an omnidirectional light — the opposite
of what a torch is — so it is opt-in rather than assumed.

No battery, no melee, no pickup. You always have it.

## Muzzle flash

A brief light on whatever just fired, at **chest height**, with realistic
falloff.

Both of those are reactions to the same bug, seen twice in this project's
history: a light placed at an actor's position sits at its *feet*, and an
unattenuated point light is near-full brightness right out to its radius.
Together that is a lamp switched on under you washing the floor in every
direction, which is not a muzzle flash.

Reach is deliberately small — this should light the wall you are pointing at
for an instant, not the room you are standing in. It fires on the *bang* rather
than the trigger, so it cannot light the room a tic before the gun goes off,
and the chaingun strobes instead of fading because it is a string of separate
bangs.

## Bloom and exposure

Bloom is what makes glow read as **emissive** rather than as paint, and the mod
switches it on the first time it loads for exactly that reason. Once only — if
you turn it off later it stays off.

Threshold is a slider rather than hardcoded, which is the difference between
glow that blooms at a sane brightness and glow you have to overdrive until the
colour breaks. Softness rolls the transition so things ease into blooming
instead of popping across the threshold. Anamorphic blurs wider horizontally
than vertically — thin bright seams plus anamorphic is most of the Tron look.

**Exposure** is the one that models an *eye* rather than a lens. Walking from a
lit corridor into a black room is not a change in what is there; it is your
pupil opening over a couple of seconds. Speed is the whole character: slow
adaptation means a room that is genuinely blind for a moment after you leave
the light. The finished presets disagree about it on purpose.

## The menus are live

Every page turns off the dim and the blur so you can see the room you are
adjusting — and the world keeps running behind them, so lane colours, presets,
sweeps and the darkness term all update as you drag a slider.

The cost is worth stating: monsters keep moving and you can be hurt while a
page is open. For a page whose only purpose is to show you the room, that is
the right trade.

## For mappers and modders

The menu settings are a map-wide default, not a mandate. Anything can claim a
single sector and drive its glow itself:

```
GITD_Handler.SetSectorOverride(sec, /* per-lane values */);
GITD_Handler.ClearSectorOverride(sec);
```

Once claimed, the handler never touches that sector again until it is released,
so the claimer can animate it freely without being fought.

Sweeps are scriptable well past the menu: fire one from an actor, bind a script
to a single band so a train of eight becomes a *program*, or run a reversible
setpiece that journals everything it changes and un-does it as a second wave
travelling outward. See [`SECTOR_SWEEP.md`](SECTOR_SWEEP.md).

## Credits

**DarkDoomZ** — base sector light darkening and the flashlight — by Sterling
Parker ("Caligari87"), used under the zlib license and altered for inclusion
here. Its original credits:

- Inspired by "Dark Doom" by Josh771 (no code used)
- Code: Kinsie, Gutawer, FishyClockwork, phantombeta, Marisa Kirisame, Accensus
- Flashlight sounds: mshahen (freesound.org 271109, modified) CC BY 3.0
- Logo: Accensus

Alterations made: the `version` directive was removed so the source could be
included alongside other files, and its menu was folded into this mod's MENUDEF
under a single root rather than adding a second top-level entry.

DarkDoomZ darkens sector light; the glow lanes are a separate mechanism added
on top, which is why floor and ceiling glow stay visible in a room crushed to
near black.
