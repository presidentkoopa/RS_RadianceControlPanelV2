# Glow In The Dark

Lighting for a fork of GZDoom built around darkness. Four independent glow
lanes, travelling bands of light that wrap every surface, real beams, mist you
stand in that reacts to what happens in it, tornadoes you can walk inside, and
a darkness model that works per pixel instead of per room.

One idea runs through all of it: **stop placing objects to represent an effect,
and give the fragment shader the maths instead.** A sweep asks each pixel its
distance from a point. A beam asks its distance from a segment. Fog asks how
much of the ray from your eye lay below a plane. Darkness asks what a pixel's
own light is rather than what its room's is.

That is why a lattice can be four lines or four hundred for the same cost, why
a laser is continuous at any length, and why mist has a surface you can look
down at.

**Requires the forked engine.** Floor and ceiling glow, two colours per glow,
Sector Sweep, the volumetric beam, per-fragment darkness, glow waves, the fog
slab, reactive fog, tornadoes, the heatmap, real beams, selective desaturation,
and the bloom threshold and knee are all engine features that do not exist in
stock GZDoom. On stock this mod will not load.

Everything lives under **Options → Glow In The Dark**.

## What is here

| | |
| --- | --- |
| **Four glow lanes** | floor, ceiling, wall bottom, wall top — identical controls on each |
| **Presets** | two finished environments, each carrying a whole room rather than a palette |
| **Glow waves** | the *edge* of a glow rises and falls along a wall |
| **Sector Sweep** | up to eight bands of light travelling through the map |
| **Laser grid** | a wall of lasers standing inside a sweep, floor to ceiling |
| **Beams** | segment lasers, continuous, visible in the air, lighting what they pass |
| **Darkness** | per room, or per pixel — with distance and height falloff |
| **Selective colour** | a grey world that still has blood in it |
| **Fog** | mist with a *top*, on the floor or the ceiling, that reacts to what happens in it |
| **Tornado** | a funnel you can walk into and stand inside |
| **Heatmap** | the floor remembers where the fighting happened |
| **Flashlight** | volumetric beam with dust, four mount positions |
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

## Texture in the glow

A wave varies a glow's **edge**. That stops helping the moment your coverage is
high enough that the edge is off screen — a maxed lane is a solid card of
colour, and the wave is moving a boundary nobody can see.

These five happen **inside** the lit area instead. None of them can change a
band's shape; the wave owns shape, these own substance. All off by default.

- **Noise** — a lit wall was one flat brightness across its whole face. This
  gives it veining and unevenness, drifting slowly so it is not a decal.
  Contrast takes it from marble to plasma. *If you turn on one thing here, this
  is the one.*
- **Flow** — current running *along* the surface, rather than a wave arriving
  *from* somewhere. Vertical on a wall, horizontal on a floor, taken from the
  surface's own facing.
- **Veins** — an irregular cell network with light crawling its edges, each
  cell on its own clock so it never blinks as one. Free at any density, exactly
  like the laser lattice, because it is a pattern and not a set of objects.
- **Walls react** — the same eight disturbance slots the fog uses. A shot or a
  death sends a ring travelling across every lit surface in the room, not just
  through the air. Needs *React to events* on the Reactive Fog page.
- **Alarm pulse** — every glow in the level pulsing together, driven by nearby
  monsters, your health, or a scripted number. The rate rises with the level as
  well as the depth, because faster is what reads as urgency — brighter alone
  just reads as brighter. This is the one that makes the light carry
  information rather than only look good.

All of it is sampled in **world space**, so a pattern crossing a wall/floor
join carries on through the corner instead of restarting at it. That is what
makes it read as something the room is made of rather than paint on each face.

## Presets

A preset is not a palette. It carries the whole room: 32 colours *and* their
durations, the shape of every lane, the darkness underneath, the air, the
flashlight, bloom and exposure, and whatever is travelling through.

**Choosing one replaces your settings. Disable Preset gives them all back** —
every value a preset overwrites is recorded first, so nothing is lost.

**Two ship**, and they are the two ends of one range on purpose. A preset list
with only the middle of it teaches nobody what this can do.

| | |
| --- | --- |
| **Black and White** | Not a monochrome palette — a monochrome *world*. Colour drain takes the textures with it. Four surfaces on four clocks that never re-sync, hard cuts, an etched edge that has moved by the time you come back down the corridor, and a floor that quietly remembers who died on it. **Except the blood.** It refuses almost every system here — no sweep, no lattice, no wisps, no funnel — and what is left is composition. |
| **OMGWTF** | Refuses nothing. Eight bands doing four different things, chest-deep fog banked and drifting, a forest of wisps, a tornado that follows the nearest live monster so it is always standing where the fight is, a laser lattice in the air inside every band, every monster dragging a hole through the mist, and an eye that never settles. Four systems arguing about the same cubic metre of air. It is not a look, it is a test. |

The others — Blackout, Low Power, Red Alert — are written but switched off.
They predate half the systems on this page, and a preset that does not *mention*
a system does not skip it: it inherits whatever the last one left running. That
makes a stale profile worse than no profile.

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

## The laser grid

**The grid is what a sweep fires.** It is not its own toggle and not its own
system — turn *Fire lasers into the air* up on the sweep page and the band stops
being a wash and becomes a wall of laser light standing in the room, floor to
ceiling and wall to wall, coming down the hall at you.

`gitd_hallway` in the console sets the whole shot at once: dense diagonal cyan,
dark room, haze to catch the light. Every value it writes is a slider you can
find on the menu, so it is a starting point rather than a mode.

**Density is free.** The lattice is a *pattern* evaluated where your view ray
crosses the band, not a set of objects, so four lines by four and four hundred
by four hundred cost exactly the same. Make it a screen door if you want one.

That is why the grid became part of the sweep rather than competing with it.
The old version placed eight real beam segments in a rectangle — which is a
small panel floating in a large room, not a wall of light filling it, and every
line you added cost another solve for every pixel on screen.

## Beams

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
- **It lights fog** — a beam through mist is a shaft along its whole length,
  not a bright dot on whatever it eventually hits

Nothing in this mod claims the beam slots any more. They belong entirely to
weapons, which is what a weapon mod needs from a lighting mod.

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

### What survives the colour drain

Colour drain used to be all or nothing: a monochrome world made blood exactly
as grey as the wall it was sprayed on.

**Keep above saturation** weights the drain by each colour's *own* vividness.
Turn it up and the drain skips colours that are already saturated, so the world
goes grey and the blood stays red. Doom's palette is very saturated at the top
end, so around 0.75 keeps blood and pickups while brown walls still drain.

Nothing is tagged for this. No actor, sprite or texture knows it is exempt,
because **the rule is about the colour, not about the thing wearing it** — which
is why it reaches textures, sprites, glow, sweep bands and brightmaps at once.

*Which hues* narrows it further. Any-hue keeps every vivid thing, which is its
own look. **Red only** is the one that means blood and nothing else: a green
nukage pool at full saturation drains away with the walls.

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
- **The surface moves** — two waves at an angle, so it rolls rather than
  corrugating in one direction.

### It also has a bottom

That one number turns a half-space into a **layer**, and the same setting is
four different effects depending on where the two edges sit:

| bottom | top | what you get |
| --- | --- | --- |
| far below | at the knee | floor fog |
| near the ceiling | above it | **ceiling fog** |
| both mid-room | just above | a band floating at chest height |
| walked toward the other | — | fog **draining** or **filling** |

**Vertical hold** repeats the layer up the room and rolls the whole stack
through, wrapping at the top — the old television fault. The stack costs
exactly what one layer costs.

### Reactive fog

The mist is a substance standing in the room, not a filter over the picture,
and a substance reacts to what happens in it.

- **Uneven density** — the biggest one. Density used to be a single number for
  the whole map, which is the main tell that fog is a filter. Now it banks:
  thick in the corners, thin across the open, and drifting slowly on its own.
- **Rings off your muzzle** — this is the one that sells it. A hard front
  travelling outward proves the mist is *between* you and the wall rather than
  painted over the picture. Bursts on monster death too, and **Ignite** lights
  the mist instead of moving it, so an explosion works even in clear air.
- **Monsters shoulder it aside** — a pack wading through knee-deep mist, each
  with its own wake.
- **Tendrils** — wisps drifting up off the surface, curling as they climb.
  Hundreds of them cost what one costs, so the spacing slider is free in both
  directions.
- **The sweep moves the air** — mist piles against a band's leading face and is
  scoured out behind it.
- **A stretched wake** — at zero the disturbance is a disc, a hole you carry
  around. Turn it up and it draws out behind into a corridor you carve and
  leave.
- **Two colours through the layer** — cold at the floor, warm at the top,
  measured against the layer's own thickness.

### Tornado

The same mist gathered around a **vertical axis** instead of spread under a
plane. A funnel you can walk into and stand inside — its centre is hollow, so
from within you are looking out through the far wall of it with the room beyond
still legible.

It can stand at a fixed point, or follow the nearest live monster, in which
case it walks the room on its own and is always where the fight is.

Swirl, not spin, is what makes it look like it is rotating: with swirl at zero
it is a smooth cone of haze and will not appear to turn at any speed, because
there is nothing on it to watch go past. Turn swirl up first.

Fully independent of the floor fog — run either, or both at once in different
colours. This is the expensive one, and unlike a floor layer it does not stop
costing anything when you look up. Off is free.

## Heatmap

Every monster death drops a mark on the floor and the marks **accumulate over
the whole life of the map**. Walk back through somewhere you cleared and the
ground shows you what happened there.

Player damage can mark too, and it is a different map: one shows what you
controlled, the other shows what controlled you. Run both and the pair is the
actual shape of a fight.

Marks are recorded whether the display is on or off, because a heatmap is a
**record** — one that erased itself when you stopped looking at it would not be.
Switch it on after a fight and you see the fight you just had.

*Forgets* turns it into a live picture of the last minute instead. At zero it
never forgets, which is what you want for reading a level after the fact.

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

**A cone seen end-on is a disc**, and that is worth knowing before you go
looking for the beam. Point the torch where you are already looking and the
cross-section you look *through* is the whole cone — it fills the middle of the
screen as a soft circle that tells you nothing, because it marks the place your
eye is already on. On a flat screen the main-hand mount tracks your view, so
end-on is the *only* way you would ever see it.

So the beam fades as your view lines up with it (`vol_beam_axisfade`, on by
default). A torch held off to one side — an off-hand mount, or a tracked
controller in VR — keeps its full strength, and that is the shot worth having.
Set it to 0 if you want the old behaviour back.

`fl_density` is **per 1000 units**, the same convention the floor fog uses. It
starts low deliberately: turn it up until the shaft reads.

**Bounce light** is a dim wide fill at the lens, and it is **off by default**.
It softens a harsh cone, and it is also an omnidirectional light — the opposite
of what a torch is — so it is opt-in rather than assumed.

No battery, no melee, no pickup. You always have it.

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

**Environmental FancyWorld** — the ambience layer in `zscript/fw/` began as the
2019 mod of that name, and what survives from it is worth stating precisely,
because it is not much and it is not nothing.

What came from the original: its **sound and sprite assets**, and its
**texture research** — the mapping from Doom's flat and wall texture names to
what they actually depict. That mapping is the tedious, valuable part and it was
theirs.

What did not: the implementation. The scan was rewritten (texture names now
resolve once into a flat lookup instead of ~500 string comparisons per linedef,
and it walks sectors rather than sweeping a fixed grid over the whole map); the
twenty-four near-identical emitter classes became one base declaring what a
thing *is* while the base decides when any of it happens; and the light,
particles, footsteps, sight-line occlusion and per-emitter detune are all new.

**The original mod does not name its author anywhere in its own files** — its
credits thank the people who helped and never sign themselves. If you know who
wrote it, or you are them, please say so and the credit goes here. Its own
credits, preserved:

- Id Software, for everything
- Gutawer — ZScript help
- PhantomBeta — further ZScript help
- Sound and sprite assets sourced from Nintendo, Epic Games, Valve, Bungie,
  Bethesda, Volition and Remedy/Rockstar. No ownership is claimed over any of
  them.
