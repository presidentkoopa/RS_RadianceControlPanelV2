# Inventory — everything the engine can do

Written 2026-08-12. Engine `90acf99cc1`, mod `34277eb`.

The point of this document is the **keep/cut pass** and the **setpiece design**
that follows it. No opinions in the tables — what each thing does, what drives
it, and what it costs. Judgement goes in the review, not here.

**Read the cost column.** It is the thing that decides whether two features can
run at once, and it is the only reason any of this is affordable.

---

## 1. THE FOUR LANES — "the 4x8"

The baseline. Everything else runs on top of this.

| | |
| --- | --- |
| **What** | Four glow lanes — wall bottom, wall top, ceiling face, floor face — each cycling 8 colour slots |
| **Drives** | `gitd_wb_* / wt_* / cg_* / fg_*` — colours, slots, pattern, speed, coverage, falloff, intensity, saturation |
| **Per lane** | pattern (snap/fade/flash/breathe/ping-pong), per-slot hold times, bleed toward neighbours, per-sector anim (ripple / roll X / roll Y / roll Z) |
| **Cost** | Per sector, once a tic. Cheap. |
| **Survives reset** | Yes — this is what "back to a clean room" leaves running |

---

## 2. SECTOR SWEEP

| | |
| --- | --- |
| **What** | Up to 8 bands of light travelling through the world, each wrapping floor→wall→ceiling as one continuous line |
| **Shapes** | bar E/W, bar N/S, ring, shell, rising sheet |
| **Origins** | map centre, where you started, follows you, last shot, last kill, nearest monster |
| **Per band** | speed, thickness, colour, gap, draw mode, shape, light amount, per-band FX |
| **Draw modes** | Add (a line), Reveal (pulls dark aside), Shadow (travelling darkness), Re-colour (drives all 4 lanes to its own hue) |
| **Triggers** | continuous, on kill, on damage, on trigger-pull, on secret |
| **Extras** | trails, dropped bands left behind, spin, ping-pong, sonar floor reveal, per-band scripts, monster interaction (wake/mark/slow) |
| **Cost** | Per fragment, one distance test per band. 8 bands = 8 tests. |

### 2a. Band fill — what is drawn INSIDE a band

| | |
| --- | --- |
| **What** | A band can carry a lattice, a field of dots, or a solid slab instead of a wash |
| **Drives** | `gitd_ss_fill_*` — spacing U/V, line width, softness, colour, gap, rotation, drift, flicker, jitter, major lines, gradient |
| **Cost** | O(1) — a `fract()` pattern. 4×4 and 400×400 cost the same. |

### 2b. Laser grid — the lattice IN THE AIR

| | |
| --- | --- |
| **What** | The same lattice standing in the air inside the band rather than painted on what it lands on. The RE-corridor look. |
| **Drives** | `gitd_ss_fill_air`, plus `gitd_hallway` console alias for the whole shot |
| **Cost** | One ray/plane intersect + the same O(1) pattern |
| **Note** | Replaced an 8-beam version that was deleted. Bar shapes only; ring/shell fall back to painted. |

---

## 3. DARKNESS

| | |
| --- | --- |
| **What** | DarkDoomZ's four curves, moved from per-sector to per-fragment |
| **Modes** | Subtract, Compress, Crush, + three fixed DarkDoom compatibility modes |
| **Per-pixel extras** | darkness by distance from viewer, darkness pooling by height |
| **Drives** | `ddz_mode`, `ddz_preset`, `gitd_dd_perpixel`, `gitd_dd_dist*`, `gitd_dd_height*` |
| **Cost** | A handful of ALU per fragment |

### 3a. Selective desaturation

| | |
| --- | --- |
| **What** | Colour drain weighted by each colour's own saturation — a grey world that still has red blood in it |
| **Drives** | `gitd_dd_keep`, `gitd_dd_keep_soft`, hue gate (any / red / green / blue) |
| **Cost** | One extra term inside the single `dodesaturate()` every path already goes through |

---

## 4. GLOW WAVES

| | |
| --- | --- |
| **What** | A glow's EDGE rises and falls as it travels along a wall, instead of being a straight line |
| **Can drive** | the edge, brightness, and the boundary between a glow's two colours — independently |
| **Drives** | `gitd_wave_*` — wavelength, speed, sharpness, shape, reach, climb, detune, per-room scatter, origin |
| **Cost** | One sine per fragment |
| **Conflict** | Mutually exclusive with seamless corners — waves force `gitd_seamless` off |

---

## 5. TEXTURE INSIDE THE GLOW

Five terms that act INSIDE a lit area, for when coverage is high enough that
the wave's edge is off screen.

| | What | Drives |
| --- | --- | --- |
| Noise | veining/unevenness in the wash | `gitd_glowtex_noise`, `_scale`, `_drift`, `_contrast` |
| Flow | current running along the surface | `gitd_glowtex_flow`, `_spacing`, `_speed`, `_sharp` |
| Cells | vein network, each cell on its own clock | `gitd_glowtex_cell`, `_scale`, `_pulse`, `_vein` |
| React | disturbance rings crossing lit surfaces | `gitd_glowtex_react` |
| Alarm | every glow pulsing together, driven by state | `gitd_glowtex_alarm`, `_source`, `_rate` |

Sampled in world space, so a pattern carries through a wall/floor corner.
Cost: noise is 2 octaves; cells is 9 samples; the rest are a sine each.

---

## 6. FLOOR FOG — the slab

| | |
| --- | --- |
| **What** | Fog with a TOP. A layer of mist you stand in, solved analytically along the view ray |
| **Two edges** | top and bottom — which makes it floor fog, ceiling fog, a chest-height band, or drain/fill |
| **Vertical hold** | the layer repeats up the room and rolls, for the price of one layer |
| **Surface** | swell (two interfering waves) so the top rolls rather than corrugating |
| **Lit by** | the torch cone (scatter), and it picks up colour from whatever is behind it |
| **Wake** | a lagged point that thins the mist where you walk, stretchable along your direction of travel |
| **Two colours** | across the layer's own thickness |
| **Cost** | Closed form. No march. A handful of ALU. |

### 6a. Reactive fog — ONE primitive, five effects

Eight slots, oldest recycled. A point, a radius, an age, a strength, a sign.

| Mode | What |
| --- | --- |
| Disc | pushes mist aside — wakes, and monsters displacing it |
| Ripple | a ring travelling outward |
| Ignite | an expanding sphere that adds LIGHT, works in clear air, feeds bloom |
| Gout | an expanding disc that ADDS mist |

Fired by: your gunfire (trigger rising edge), monster deaths, and the nearest
4–6 monsters as displacers.

### 6b. Density noise

Mist banks and drifts instead of being one number for the whole map. Sampled at
the midpoint of the eye-to-pixel line.

### 6c. Tendrils

Wisps rising off the surface as a `fract()` lattice — hundreds cost what one
costs. Spacing, radius, height, rise, curl, taper.

### 6d. Bow wave

A sweep band piles mist against its leading face and scours it out behind.

---

## 7. TORNADO

| | |
| --- | --- |
| **What** | The same mist gathered around a vertical axis. A funnel you can stand inside — the centre is hollow, so you see out through the far wall |
| **Shape** | base/top height, radius at each, flaring on a curve rather than a straight taper |
| **Motion** | swirl (what reads as rotation), spin, twist, lean, sway period |
| **Anchor** | fixed point, where you started, follows you, last shot, last kill, **nearest live monster** |
| **Own colour and own torch scatter** — independent of the floor fog |
| **Cost** | The most expensive thing in the shader. Does NOT early out the way a floor layer does. Off is free. |

---

## 8. BEAMS

| | |
| --- | --- |
| **What** | Real segment lasers, lit per pixel by distance from the segment. Continuous, depth-correct, visible in the air, and they light what they pass |
| **Along the beam** | taper, scrolling energy, impact flare |
| **Extras** | they light fog they cross; they feed bloom on their own |
| **Cap** | 8, shared globally |
| **Used by** | RS_Main's Lance. **Nothing in GITD touches beams.** |

---

## 9. VOLUMETRIC FLASHLIGHT

| | |
| --- | --- |
| **What** | A raymarched cone — the beam visible in the air, not just the disc where it lands |
| **Mounts** | main hand, off hand, head, chest. The hand mounts read their own tracked VR pose |
| **Dust** | motes sampled in world space, so they stay put as you sweep |
| **Extras** | colour cycling through 8 slots, bounce fill (off by default), agitates monsters it lights |
| **Axis fade** | fades as your view lines up with it — a cone seen end-on is a disc |
| **Cost** | The only marching loop in the codebase. Bounded. |

---

## 10. HEATMAP

| | |
| --- | --- |
| **What** | A 256² grid over the map's bounding box. Every death stamps it; marks accumulate over the whole level |
| **Records** | monster deaths, and where the player was hurt (separately) |
| **Reads back** | `Level.HeatmapAt(x,y)` — so a spawn director could weight against fought-over ground |
| **Drawn as** | a postprocess pass — so it paints over the frame rather than tinting the light |
| **Stores** | deposit height, so a balcony kill does not mark the floor beneath |
| **Cost** | One texture sample per pixel |

---

## 11. SHAPES ON SURFACES

| | |
| --- | --- |
| **What** | Signed distance fields drawn onto floors or walls. Maths, not geometry — no model, no actor |
| **Kinds** | disc, ring, square, square outline, cross, hexagon, triangle |
| **Per shape** | size, rotation, thickness, colour, intensity, lifetime, growth rate |
| **Seam** | splits down the middle, showing a second colour through the widening gap |
| **Formation** | single, radial (N around a circle, spinning), grid (tiled, drifting) — one slot, any count |
| **Slots** | 128, loop runs only to the highest in use |
| **Fired by** | monster death, your gunfire |
| **Cost** | Squared-radius reject, then a few ALU |

---

## 12. BILLBOARDS

| | |
| --- | --- |
| **What** | Oriented world quads with hit testing — an in-world UI primitive, depth-tested and occluded properly |
| **Payloads** | panel, texture, digits, glyph, ring, bar, **SDF text**, 16-segment display, inverted segment display, seam, **WG13 (the kill badge)** |
| **Queries** | aim a ray at one, touch one, sweep a segment through one |
| **Groups** | a shared transform so a composed panel scales as one object |
| **Extras** | view-locking resolved at render rate, per-billboard alpha, gradients, glow from the distance field, save/load |
| **Font** | real SDF atlas built offline from any TTF (`tools/sdffont/mksdf.ps1`) |

---

## 13. NUMERIC ENGINE

Kill counts and damage numbers drawn through the billboard system. Styles,
colours by streak/milestone, placement, linger.

---

## 14. BLOOM AND EXPOSURE

Threshold, knee, amount, tint, anamorphic streak, chromatic fringing, and
auto-exposure with its own speed. Engine cvars — writable only from menu scope.

---

## 15. SUPPORTING

| | |
| --- | --- |
| **Non-pausing menus** | a settings page can let the world run behind it, so every slider is live |
| **Presets** | replace your settings and hand them all back on Disable. Two ship: Black and White, OMGWTF |
| **Colour law** | the conductor lane's active colour slot becomes a game rule — tougher/frailer/faster/slower monsters, health or armour rain |
| **VR weapon wheel** | a wheel per hand, worked by the hand it belongs to |
| **Reset** | back to a clean room — everything off except the four lanes, active preset preserved |

---

# What the original mod had, for the keep/cut pass

From `GlowInTheDark.pk3` — the names are the menu's own.

## Death effects

| # | Name |
| --- | --- |
| 0 | Death Pool |
| 1 | **Seam Reveal** |
| 2 | Ghost Walk |
| 3 | Death-Ping (ring) |
| 4 | Stylized X |
| 5 | Hex Field |
| 6 | Hex Rings |
| 7 | Spiral |
| 8 | Pulse Detect |
| 9 | Firework |
| 10 | Square Rings |
| 11 | Star |
| 12 | Sunburst |
| 13 | Grid |
| 14 | Random per kill |

## Wall patterns

Neon Pillar · Scan Lines · Light Grid · Pulse Bars

## Impact effects (on hit, not kill)

Glow · Ring · Stylized X · Hex Field · Hex Rings · Spiral · Square Rings ·
Star · Sunburst · Grid · Random · **Inverse Glow (negative flash)**

## Spark styles

Sparks · Eruption · Dust Puff · Flak Burst · Scorch

## Accents

Lightning · Shrapnel · Sparks

## Colour modes

Death: by tier (toughness) · fixed · random · rainbow
Kill count: cyan · gold · cyan/gold milestones · **heatmap by streak** · spectrum

---

# Notes for the setpiece pass

Things worth knowing when combining these.

**What can anchor to a monster:** sweep origin, glow wave origin, tornado
anchor, fog displacers, shapes (placed at a position). So "the effect follows
the fight" is already expressible in several systems.

**What is free at any density:** the band lattice, the laser grid, tendrils,
glow cells, shape formations. All `fract()` patterns. Scale these without fear.

**What is NOT free:** the tornado (no early out), beams (8 max, segment solve
each), the volumetric cone (the only march).

**What already reacts to events:** fog disturbances (gunfire, death, monsters),
glow react rings, shapes (death, gunfire), heatmap (death, player damage),
sweep triggers (kill, damage, trigger-pull, secret), colour law.

**What can read back into gameplay:** `HeatmapAt(x,y)`, and the colour law
driving monster speed/toughness and pickup rain.

**The one thing missing for gameplay:** nothing can ask "is the player standing
in the light". Every effect is a distance function the shader evaluates; the
playsim has no copy. Mirroring those functions into ZScript is the piece any
"stay in the light" mode needs, and it is deliberately not built.
