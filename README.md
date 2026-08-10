# Glow In The Dark

Lighting for a fork of GZDoom built around darkness: four independent glow
lanes, a travelling sweep, a volumetric flashlight, base-light darkening, and
bloom controls that make any of it read as emissive.

**Requires the forked engine.** Floor and ceiling glow, falloff and intensity
on the wall lanes, two colours per glow, Sector Sweep, the volumetric beam,
and the bloom threshold and knee are all engine features that do not exist in
stock GZDoom. On stock this mod will not load.

## What is here

| | |
| --- | --- |
| **Four glow lanes** | floor, ceiling, wall bottom, wall top — identical controls on each |
| **Seamless corners** | a glow holds two colours, so a corner is a gradient instead of an edge |
| **Sector Sweep** | up to eight lines of light travelling through the map |
| **Flashlight** | volumetric beam with dust, four mount positions |
| **Presets** | eleven, each generating 32 related colours, and customisable |
| **Darkness** | DarkDoomZ, folded in |
| **Bloom** | threshold, soft knee, anamorphic streak, tint, fringing |

Everything lives under Options → Glow In The Dark.

## The four lanes

| Lane | What it lights |
| --- | --- |
| **Floor Glow** (`fg`) | The floor surface itself, glowing inward from its edges |
| **Ceiling Glow** (`cg`) | The ceiling surface itself, glowing inward from its edges |
| **Wall Bottom** (`wb`) | The wall, lit upward from where it meets the floor |
| **Wall Top** (`wt`) | The wall, lit downward from where it meets the ceiling |

`wb` and `wt` are the glow mechanic stock Doom has always had. `fg` and `cg`
are new — a floor or ceiling that glows on its own face, not just spilling
onto the nearby wall.

Every lane has the same controls, deliberately: on/off, eight colour slots,
how many of those slots are in rotation, a transition pattern, transition
speed, coverage, falloff curve, intensity, and a pulse. If a control exists
for one lane it exists for all four — and they mean the same thing on all
four. **Coverage** is how far the glow reaches; **Intensity** is how bright it
is. (Intensity used to widen the floor and ceiling lanes instead of
brightening them, so the same-named slider did two different jobs depending
on which lane it sat on. If a configuration from before this changed looks
tighter than it used to, raise its Coverage.)

## Corners

Where a wall meets a floor, two glows arrive at the same line — the wall lit
upward from it, the floor lit inward from it — and both are at full strength
exactly where they touch. The hard edge there was never a missing blend. It
was the two sides disagreeing about what colour to be at a line they share.

**Seamless Corners** makes them agree at the line and disagree everywhere
else. Each glow carries two colours now and ramps between them as it fades:
both surfaces take the same blended colour where they meet, and each fades
back to its own lane's colour going away from it. The corner reads as one
continuous gradient — floor colour, blend, wall colour — with no flat region
in it and no seam.

Both junctions do this together, floor-to-wall and ceiling-to-wall, because
a room with only one of them ramping looks worse than a room with neither:
the eye finds the mismatch immediately.

The earlier version of this setting simply made both sides the *same* colour
near the join. That removed the seam and the two-colour transition along with
it, which was the interesting part. This keeps both lane colours.

Reach, falloff and brightness are matched across the junction too — a ramp
that changes width or brightness halfway across a corner reads as a seam even
when the colour is continuous.

## Colours

Each lane holds eight colour slots and cycles through however many are set
to be in rotation. A slot set to **Random** re-rolls every time it comes
around, so the default configuration keeps moving without anyone
configuring anything.

Ten presets are also available. A preset is not four flat colours: each one
defines a hue range and a swing in saturation and brightness, and every lane
takes a different quarter of that range and walks eight shades through it --
32 related but distinct colours, with brightness and saturation swinging on
different periods so it never settles into an obvious loop. Turning a preset
off restores your own colour choices, which it never overwrites.

Transition patterns:

- **Snap** — hold each colour, then jump
- **Fade** — smooth crossfade
- **Flash** — jump to the new colour, then decay back
- **Breathe** — fade through darkness between colours
- **Ping-Pong** — walk up the slot list and back down instead of wrapping

## Sector Sweep

A train of up to eight thin lines of light travelling through the map, each
wrapping across floor, walls and ceiling as one unbroken band. Four shapes: a
ring expanding outward, a bar sweeping east/west or north/south, or a shell
that rises as it expands. Each sweep in the train has its own colour, and its
own spacing behind the one in front of it.

This is **not** one of the four lanes, and could not be. A lane is
per-sector -- one colour for a whole sector -- so an expanding ring built
that way would light whole rooms in sequence, chunky and wrong. Sector Sweep
is tested per pixel against world position, which is what keeps a line thin
and lets it stay continuous where floor meets wall meets ceiling.

Because the distance is measured in world space and the same test runs on
every surface, the wrapping is automatic rather than coordinated: a cylinder
expanding from a point cuts floor, wall and ceiling at the same radius, and a
plane travelling down a corridor draws an unbroken rectangle around it.

**While Sector Sweep is on it takes over** from the presets and lane
settings. The point of it is a dark room with nothing in it but the lines, so
leaving the lanes lit underneath would defeat it.

A sweep can also affect the rooms it passes through: brighten them, darken
them, or **re-colour the glows to match** -- that last one drives all four
lanes to shades of the passing sweep's own colour, so a green sweep leaves 32
cooperating greens behind it. That part is necessarily per-sector, since
light level is a sector property, so it is coarser than the line itself.

## Map-wide wave

Instead of every room pulsing in step, brightness can travel across the map
like a stadium wave — each sector's phase offset by where it sits, so a
crest visibly rolls through the level. Ripples from the map centre, or rolls
along either axis. Affects all four lanes at once.

## Per-sector override

The menu settings are a map-wide default, not a mandate. Anything can claim
a single sector and drive its glow itself:

```
GITD_Handler.SetSectorOverride(sec, /* per-lane values */);
GITD_Handler.ClearSectorOverride(sec);
```

Once claimed, the handler never touches that sector again until it is
released — so the claimer can animate it freely without being fought. This
is the hook for things like a hazard whose floor glow closes in as a
countdown.

## Flashlight

The beam is **volumetric** — visible in the air, not just the disc where it
lands. That is a real cone of light raymarched through the scene, cut off
properly by walls, and it blooms and feeds auto-exposure like any other light.

Four mounts: main hand, off hand, head, chest. The two hand mounts read their
own tracked pose in VR, so they are genuinely different positions rather than
one light nudged sideways. Head and chest hang off the view, for when both
hands are busy.

Dust in the beam is sampled in **world space**, so motes stay put in the room
as you sweep rather than sliding along with the light. Fine dust needs a
higher beam quality to resolve — coarse dust is fine at low quality.

Colour uses the same eight-slot system as the glow lanes, so the flashlight
can cycle and fade like everything else, or sit on one steady colour.

Bounce light is a dim wide fill at the lens. A bare cone in a black room reads
as harsh and floating; this puts a little light back into the space the way a
real torch does off whatever it is pointed at.

No battery, no melee, no pickup. You always have it.

## Bloom

Bloom is what makes glow read as **emissive** rather than as paint, and this
mod switches it on the first time it loads for exactly that reason — the
engine ships it off, and the glow looks flat and wrong without it. It does
that once, so if you turn it off later it stays off.

The threshold used to be hardcoded, meaning only things already blown past
white could bloom at all. It is a slider now, which is the difference between
glow that blooms at a sane brightness and glow you have to overdrive until the
colour breaks.

Softness rolls the transition so things ease into blooming instead of popping
as they cross the threshold — worth having when glow is pulsing and beams are
sweeping past it constantly.

Anamorphic blurs wider horizontally than vertically, so bright edges streak
sideways. Thin bright seams plus anamorphic is most of the Tron look.

## Credits

**DarkDoomZ** — base sector light darkening and the flashlight — by Sterling
Parker ("Caligari87"), used under the zlib license and altered for
inclusion here. Its original credits:

- Inspired by "Dark Doom" by Josh771 (no code used)
- Code: Kinsie, Gutawer, FishyClockwork, phantombeta, Marisa Kirisame, Accensus
- Flashlight sounds: mshahen (freesound.org 271109, modified) CC BY 3.0
- Logo: Accensus

Alterations made: the `version` directive was removed so the source could be
included alongside other files, and its menu was folded into this mod's
MENUDEF under a single root rather than adding a second top-level entry.

DarkDoomZ darkens `Sector.LightLevel`; the glow lanes are a separate
mechanism added on top. Floor and ceiling glow therefore stay visible even
in a room DarkDoomZ has crushed to near black.
