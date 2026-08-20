# Radiance Control Panel

Doom in the dark, lit by what you do to it.

The map is crushed toward black. Light comes back from surfaces that glow,
bands that sweep through the room, mist you stand in, your torch, and the
violence you commit. Every map you already own becomes a different place, with
no patches and no per-WAD setup.

**Requires the forked engine.** It will not load on stock GZDoom.

Everything is under **Options → Radiance Control Panel**.

---

## Start here

Open the options and pick a preset. That is the whole setup.

| Preset | What it feels like |
|---|---|
| **Blackout** | A true void. The only light in the world is the light you brought — your torch, your muzzle, your laser, and a floor that remembers where you killed. You navigate by ear. |
| **Low Power** | A facility on a failing supply. Amber light that catches, holds, slips and goes, in a four-beat cycle. Low mist pooling in the sunken rooms, wisps rising off it, and your own footsteps the loudest thing left. |
| **Red Alert** | A containment breach on a five-minute procedure. The alarm trips, sweeps the building for forty seconds, and then the facility sits with it. Thin red air the klaxon bands push ahead of themselves. |
| **Black and White** | Everything drains to grey except what is worth seeing. Blood stays red. A flat sheet of grey air at one height, because this one is composing an image rather than a room. |
| **Off** | Your own colours, your own dials. Everything below is yours to set. |

Presets overwrite the glow settings. Set one, then adjust — or pick **Off** and
build your own.

---

## What it does

Three components under one roof, shipped as one pk3. Each has its own menu
page and its own cvar namespace, and any of them can be switched off without
touching the others.

### GITD — the light

- **Per-pixel darkness** — real darkness rather than a filter, four curves, growing with distance and pooling below a height so pits go deeper than the rooms around them.
- **Surfaces glow** — four independent lanes (wall bottom, wall top, ceiling, floor), eight colours each, corners blending so a wall meeting a floor reads as one source.
- **Bands sweep the map** — up to eight at once as spheres, cylinders or planes, wrapping floor to wall to ceiling in one unbroken line; they can brighten, darken, reveal or wake monsters.
- **A lattice inside a band** — the corridor of lasers, hanging in the air.
- **Mist you stand in** — a layer with a real surface that follows the floor, pooling in low ground and taking its colour from the pool it lies over.
- **The mist reacts** — gunfire, deaths, explosions, monsters shouldering through it, and your own wake closing behind you.
- **A tornado** — a funnel of that same mist you can stand inside, with an origin that can hunt the nearest monster.
- **The floor remembers** — where the fighting happened accumulates and stays.
- **A volumetric flashlight** — a real cone in the air with dust hanging in it, dragging behind your aim the way a thing held at arm's length does.
- **Kills leave marks** — SDF shapes stamped into the floor by deaths and shots.
- **Shapes that stand up** — freestanding in open air with full yaw/pitch/roll, continuous rotation rates, and parent-child linking so they compose into structures.
- **Numbers in the world** — a kill counter and damage numbers where things died.
- **Bloom** — threshold, knee, anamorphic streak, tint, chromatic fringing, exposure.
- **Colour changes the fight** — the room's current colour carries a rule: monsters tougher, weaker, faster, slower.
- **Eight presets** — one tap for Blackout, Low Power, Red Alert, Black and White and the rest.

### FancyWorld — the ambience

- **The map makes noise** — every waterfall, computer, lavafall and lit ceiling flat is found at load and given sound, light and particles, on WADs that never heard of this mod.
- **Footsteps** — the material comes from the flat under you: metal, grating, wood, gravel, dirt, rock, tile, flesh.
- **Sound muffles through walls** — a real sight trace, so a waterfall behind a sealed door stops being as loud as one in front of you.
- **Liquids tint the mist** — the fog takes its colour from the pool it is lying over.
- **Liquids splash** — real TERRAIN-driven splashes on nukage, blood, slime, water and lava, not a timed guess.
- **And ring after** — a wave spreads across the surface where something broke it, and a couple of bubbles rise behind it.

### Universal Map Enhancements — the props

- **Lit props** — fifteen vanilla decorations that already animate bright (torches, tech lamps, candles, the burning barrel) now cast the light they were always implying, and break in one hit.
- **Two of them breathe** — the evil eye and the floating skull pulse rather than glow, and go wrong under Lovecraftian Fog.
- **Breakable scenery** — thirteen unlit props (columns, impaled heads, trees, stalagmites) shatter into debris. No glow: none of them are lit in vanilla.
- **Keys you can find** — each key carries its own light in its lock's colour, because a keycard is a small flat sprite and this mod makes floors black.

---

## Options

Every page below is under **Options → Radiance Control Panel**.

### On the front page
The GITD light switch, the preset picker and **Customise this preset**, seamless
corners, and every submenu below.

Two buttons worth knowing:

- **The Hallway** — one tap, and the room fills with a grid of laser light
  hanging in the air.
- **Back to a clean room** — undoes everything and hands the map back.

### The pages

| Page | What is on it |
|---|---|
| **Wall Bottom / Wall Top / Ceiling / Floor Glow** | One page each. Eight colour slots, hold time, pattern, coverage, saturation, falloff, animation, random colour. |
| **Per-pixel darkness** | Which curve, how dark, light floor, gains either side, distance falloff, height pooling. |
| **Fog Options** | Height, thickness, softness, colour and where it comes from, edge following, surface swell, density banks, tendrils, bottom edge, vertical repeat. |
| **↳ Reactive fog** | What disturbs the mist: gunfire, deaths, explosions, monsters moving through it, and your own wake. |
| **↳ Tornado** | A funnel of the same mist you can stand inside. Swirl, spin, twist, lean, and an origin that can hunt the nearest monster. |
| **↳ Heatmap** | The floor record of where you fought. Colours, spread, ceiling, decay. |
| **Sector Sweep — Visual** | Colour, speed, shape, thickness and timing for each of eight bands. |
| **↳ Gameplay** | What each band *does*, its strength, and a script to run. |
| **↳ Edit one band** | All ten settings for a single band, with a selector. |
| **↳ Grid options** | The lattice inside a band — spacing, width, rotation, drift, flicker, and whether it hangs in the air. |
| **Volumetric Flashlight** | Mount, range, cone angles, intensity, colour cycling, dust, bounce fill, beam drag, and whether it wakes monsters. |
| **World Ambience** | The texture scan: lights and their detail, particles, footsteps and their stride, how hard sounds muffle when you cannot see them, emitter range and spacing. |
| **Enhancements** | Lit props, breakable scenery, and whether keys carry their own light. |
| **Colours Change the Fight** | The room's current colour carries a rule — monsters tougher, weaker, faster, slower, or health raining down. Reached from the sweep's gameplay page. |
| **Glow waves / Texture in the glow** | Undulation along a surface, and structure inside the lit area. |
| **Shapes** | Marks stamped on the floor by kills and shots. |
| **Numbers** | Kill counter and damage numbers in the world, four display styles. |
| **Bloom** | Threshold, knee, amount, anamorphic streak, tint, chromatic fringing, exposure. |

Sliders move the picture **while the menu is open**, and the world keeps running
behind it — you can be hurt while adjusting.

---

## Playing with other mods

Liquids already splash — nukage, blood, slime, water and lava all have real
TERRAIN-driven splashes built in, not just ambience, plus a ring across the
surface and a couple of bubbles after. Load a **different liquid pack** on
top and normal load order applies: whichever loads last wins for any flat
both define, same as any other TERRAIN lump. Either way, liquid flats
neither this mod nor a loaded pack recognise still feed the fog colour
through a neutral fallback — see `TERRAIN` in the mod root for the `floor
optional` entries already covering FreeDoom and Eviternity.

Want the splash itself to be a real animated 3D mesh instead of this mod's
own shader ring? Load **Universal Map Enhancements** after this mod. Same
load-order rule applies, and its splash actors take over — and if it also
loads after, its own torch and lamp replacers win over this mod's for the
same reason: last `replaces` for a given actor wins.

Do **not** load *Environmental FancyWorld* separately. It is built in.

---

## Credits

**DarkDoomZ** — sector light darkening — by Sterling Parker ("Caligari87"),
zlib licensed. Original credits: inspired by "Dark Doom" by Josh771 (no code
used); code from Kinsie, Gutawer, FishyClockwork, phantombeta, Marisa Kirisame,
Accensus; logo by Accensus. Its own flashlight and fog were removed, as this
mod already had both.

**Environmental FancyWorld** — the ambience layer began as the 2019 mod of that
name, which contributed its sound and sprite assets and its texture research.
The implementation is not original to it. The original does not name its author
anywhere in its own files; if you know who wrote it, please say so and the
credit goes in. Assets are sourced from several commercial games and no
ownership is claimed over them.

**Liquid splashes** — the splash and lava sprites and the water/muck/lava
sounds are from *Environmental_MTOLiquids*, a small freeware resource by
MObreck built on Heretic's water terrain effects; its own credits trace the
assets further back to Heretic and Hexen. The TERRAIN lump and the ZScript
splash classes in this mod are written for it, not copied from MTOLiquids'
own DECORATE — only the sprites, sounds, and the general shape of the idea
(TERRAIN-driven splashes rather than a scan) carried over.

**Liquid flourishes** — the ring and the bubbles are this mod's own shader
Shapes, not ported code, but the idea of putting *something* there came from
looking at *Universal Map Enhancements* (a Brutal Doom v21 companion pack by
BROS_ETT_311)'s comparable effects. No assets or DECORATE from it are used —
it states no licence over its own splash actors or its animated 3D splash
model the way MTOLiquids does over its sprites, so only the concept carried
over.

**Universal Map Enhancements, the third component** — decorative props
(torches, tech lamps, candles, the burning barrel) that already animate
BRIGHT in their own vanilla IWAD sprite now cast a real light and break in
one hit, the same idea GITD already applies to lit ceiling flats and wall
textures. Props that are *not* lit in vanilla — columns, impaled heads,
trees, stalagmites — get the breaking without the glow, on their own
switch: lighting them would be inventing something the map never said.
Every class is a `replaces` for a stock Doom actor, keeping that actor's own
sprite and size unchanged — nothing is copied from UME's DECORATE or its
assets, only the observation that these props were already implying a light
source.

The glowing keys are not from that pack at all. UME touches the six vanilla
keys only cosmetically; the reason to light them is this mod's own premise —
a map crushed toward black, and a keycard that is a small flat sprite on a
dark floor. A blue glow across a black room *is* the sentence "the blue key
is over there". Nothing about the pickup changes, and it has its own off
switch, being the one thing here that can affect whether a map is finishable.

The rest of that pack — roughly 2,000 more actors covering gore,
Sgt Mark IV's vehicles, active/disabled bosses, and a hand-authored per-map
decoration database spanning dozens of specific vanilla and community maps
— is deliberately not here. Gore's own mechanic (20-30 real flying giblet
actors per death) is the actor-swarm pattern this mod exists to avoid, not
a borderline case; the vehicles carry an explicit "ask me first" notice from
their actual author; the per-map database is a scale of hand-placed,
non-portable content a single component shouldn't try to absorb wholesale.
None of that is ruled out forever, just not part of this first slice.

**Ambience additions** — the sky wind, the cave drip, the wall drips and the
torches come from three community ambience mods: *Universal Ambience*,
*Ambient Decorations*, and a Cosmo ambience script. Their own samples trace
back to S.T.A.L.K.E.R., Half-Life 1 and 2, Portal, Silent Hill and Resident
Evil. As with FancyWorld above, none of those three name an author anywhere
in their own files; if you know who wrote them, please say so and the credit
goes in. No ownership is claimed over any of it. (The klaxon on the sweep
band and the four preset voices these mods also contributed are not
currently part of this build.)

Everything here was downmixed to mono on the way in, and that is not a
housekeeping note. GZDoom does not spatialise a stereo sound: it plays flat at
your head, at full volume, everywhere in the map. A stereo file in this mod
would be exactly the thing this mod exists to avoid.

---

*How any of it works, and why it is built the way it is:*
[`TECHNICAL.md`](TECHNICAL.md) · [`SECTOR_SWEEP.md`](SECTOR_SWEEP.md)
