# Radiance Control Panel

Doom in the dark, lit by what you do to it.

The map is crushed toward black. Light comes back from surfaces that glow,
bands that sweep through the room, mist you stand in, your torch, and the
violence you commit. Every map you already own becomes a different place, with
no patches and no per-WAD setup.

**Requires the forked engine.** It will not load on stock GZDoom.

Everything is under **Options → Glow In The Dark**.

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

**The world is dark.** Not a filter over the screen — real darkness, with four
curves to choose from, that can also grow with distance and pool below a
height so pits and stairwells go deeper than the rooms around them.

**Surfaces glow.** Four independent lanes — the bottom of walls, the top of
walls, the ceiling, the floor — each cycling through eight colours in patterns
you choose. Corners blend so a wall meeting a floor reads as one light source
rather than two arguing.

**Bands of light sweep the map.** Up to eight at once, travelling as spheres,
cylinders or planes, wrapping floor to wall to ceiling in one unbroken line.
They can brighten, darken, reveal, or wake monsters — a wave the AI hears. They
can carry a lattice inside them, which is the corridor of lasers.

**There is mist you stand in.** A layer with a real surface you can look down
at, that follows the floor so it pools in low ground and thins on high. It
takes colour from the pool it is lying over. You part it as you walk and it
closes behind you. Gunfire, deaths and explosions disturb it.

**Your torch is a real cone in the air**, with dust hanging in it, and it drags
slightly behind your aim the way a thing held at the end of an arm does.

**The floor remembers.** Where the fighting happened accumulates and stays.

**Kills leave marks**, numbers count in the world where things died, and the
walls pulse harder as monsters close in — a health bar you feel instead of read.

**Your footsteps match the floor.** Doom has never had them -- the sound
comes from whatever flat is under you: metal, wood, gravel, dirt, rock, tile,
flesh, or a splash in liquid.

---

## Options

Every page below is under **Options → Glow In The Dark**.

### On the front page
Master switch, the preset picker and **Customise this preset**, seamless
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
| **Footsteps** | Volume and stride -- how far you walk between footfalls. |
| **Colours Change the Fight** | The room's current colour carries a rule — monsters tougher, weaker, faster, slower, or health raining down. Reached from the sweep's gameplay page. |
| **Glow waves / Texture in the glow** | Undulation along a surface, and structure inside the lit area. |
| **Shapes** | Marks stamped on the floor by kills and shots. |
| **Numbers** | Kill counter and damage numbers in the world, four display styles. |
| **Bloom** | Threshold, knee, amount, anamorphic streak, tint, chromatic fringing, exposure. |

Sliders move the picture **while the menu is open**, and the world keeps running
behind it — you can be hurt while adjusting.

---

## Playing with other mods

Load a **liquid pack** (TERRAIN-based) and this defers to it: its splashes and
step sounds win, and its liquid flats feed the fog colour even for flats this
mod has never heard of.

Do **not** load *Environmental FancyWorld* separately. It is built in.

---

## Credits

**DarkDoomZ** — sector light darkening — by Sterling Parker ("Caligari87"),
zlib licensed. Original credits: inspired by "Dark Doom" by Josh771 (no code
used); code from Kinsie, Gutawer, FishyClockwork, phantombeta, Marisa Kirisame,
Accensus; logo by Accensus. Its own flashlight and fog were removed, as this
mod already had both.

**Environmental FancyWorld** — the footstep sounds began as the 2019 mod of
that name, along with the texture research behind them: the mapping from
Doom's flat names to what material they actually depict. The ambience scan
built on top of that research — emitters read off waterfalls, computers,
lavafalls and lit ceilings — was removed for being more maintenance than it
was worth; the implementation was never original to the source mod regardless.
The original does not name its author anywhere in its own files; if you know
who wrote it, please say so and the credit goes in. Assets are sourced from
several commercial games and no ownership is claimed over them.

**Tooltip menu library** by ToxicFrog, MIT.

---

*How any of it works, and why it is built the way it is:*
[`TECHNICAL.md`](TECHNICAL.md) · [`SECTOR_SWEEP.md`](SECTOR_SWEEP.md)
