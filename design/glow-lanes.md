# Glow Lanes — pretty it up, expand it, wire it in

Subject: the mod's oldest core, the **4×8** — four lanes (`gitd_wb_*` wall
bottom, `gitd_wt_*` wall top, `gitd_cg_*` ceiling, `gitd_fg_*` floor), eight
colour slots each, plus pattern/speed, the spatial animation system, coverage,
falloff, intensity, saturation, bleed, and the preset machinery.

Ground rules honoured throughout: everything is **additive and cvar-gated**,
nothing changes what an existing config does; tier/monster colour language is
**consumed, never redefined**; ideas that simplify outrank ideas that layer.
Effort: S = an afternoon, M = a few sessions, L = real engine work.
Wow/effort: 1–5.

What the exploration turned up before any invention: three loose bricks
already in the wall.

1. **`Side.SetGlowColor` exists in the engine and nothing calls it.**
   `vmthunks.cpp` exports a per-wall glow override (colour + height, alpha 0
   = fall back to the sector, so it is invisible until used) and
   `hw_walls.cpp` (`ApplyWallOwnGlow`) honours it. GITD never touches it.
   That is a whole axis of expression — per-WALL, not per-sector — sitting
   installed and unlit.
2. **The flat-glow Intensity slider is quietly lying.** `hw_flats.cpp` folds
   intensity into *reach* (`reach = FlatGlowHeight * FlatGlowIntensity`) and
   the flat branch of `main.fp` never multiplies the colour by intensity at
   all. So on the cg/fg lanes, Intensity makes the glow *wider*, while on
   wb/wt the same-named slider makes it *brighter*. Half the 4×8's intensity
   controls do a different job than the other half.
3. **`SetSectorOverride` has zero callers.** The per-sector claim mechanism
   is built, documented in the README, and no feature has ever used it.

---

## 1. PRETTY — what the lanes lack visually

### P1. Drift — a pattern that never arrives
All four current patterns are built around *arrival*: Snap holds and cuts,
Fade/Flash/Breathe all land exactly on a slot colour and then set off for the
next one. Drift is the pattern with no arrivals — instead of easing A→B, the
lane's colour follows a smooth closed loop *through* the slots (Catmull-Rom
through the slot colours in RGB, using `fromCol`'s neighbours, which
`slotIndex` already knows). The player sees the lanes stop pulsing between
colours and start slowly swimming; there is never a frame where the room is
"at" a colour. This is the smoothest transition the 4×8 can offer and it costs
one new case in the `Step()` switch.
**Built from:** `GITD_Lane.Step` pattern switch + a 4-point spline helper in
`GITD_Palette`. Slot count, presets, randomise all keep working (randomise
under Drift is genuinely lovely — an endless wander).
**Effort:** S. **Wow/effort: 4.**

### P2. Breathe-in-place and Heartbeat — anims tied to nothing
Every animation mode is spatial (`AnimFactor` measures distance — ripple,
east/west, north/south, height). There is no mode where the room simply
*breathes*. Add two: mode 5 **Breathe** (the wave is a function of `animClock`
alone, `dist = 0`; the whole map inhales and exhales together, depth and speed
already have sliders), and mode 6 **Heartbeat** (a shaped lub-dub waveform —
two crests close together, then a rest, on the existing clock). In a dark
room the heartbeat is uncanny in exactly the right way: the architecture has a
pulse and it is not yours. Pure ambience, zero gameplay meaning, and it makes
Blackout-adjacent looks feel alive instead of static.
**Built from:** two branches in `GITD_Lane.AnimFactor`; the phase-offset cvar
already lets lanes beat against each other.
**Effort:** S. **Wow/effort: 4.**

### P3. Comet crests — the streak gets a wake
`_anim_sharp` narrows the travelling crest into the EKG streak, but the streak
is symmetric — it approaches the way it leaves. The sweep already solved this
(`gitd_ss_trail`: stretch one side of the falloff, no second gradient, no
seam). Port the idea down: `gitd_*_anim_trail` stretches the trailing side of
the crest, so the pulse travelling through a lane reads as a comet with a
dimming tail rather than a scanner blip. One multiply in `AnimFactor` on the
falling side of the wave.
**Built from:** the sweep's proven trail maths, applied to the lane wave.
**Effort:** S. **Wow/effort: 3.**

### P4. A real bleed dial
`BleedToward` is a boolean that always pulls 35% toward a fixed 50/50 mix of
the neighbouring lanes. It reads as one light at a corner — the goal — but
the number is not the player's. Make the 0.35 a per-lane slider
(`gitd_*_bleed_amt`, 0–1, default 0.35 so nothing changes): at 0 the corner
is two crisp ribbons, at 1 the four lanes melt into one continuous wash and
the room becomes a single gradient. The high end is a *look*, not a fix — a
lava-lamp room — and it falls out of exposing one constant.
**Built from:** `GITD_Handler.BleedToward` + four cvars + four menu lines.
**Effort:** S. **Wow/effort: 3.**

### P5. Flat-edge glow, untapped: edge select and the centre pool
Today a flat glows inward from **all** of its linedefs equally (`hw_flats.cpp`
uploads every line of the sector, capped at 64). Two options hiding in that
line list:

- **Edge select** (`gitd_fg_edges` / `gitd_cg_edges`: All / Walls only /
  Steps only): choose which lines make the list — one-sided lines only
  (glow hugs real walls, ignores step edges) or two-sided-with-height-change
  only (every stair tread lights its own riser edge — instant Tron
  staircases). The selection is a branch in the CPU loop that already builds
  the list per draw; the shader never changes.
- **The centre pool** (`gitd_*_shape`: Edges / Centre): feed the shader ONE
  degenerate segment — the sector's centroid as a zero-length line — and the
  existing nearest-segment distance maths turns inside out for free: the flat
  glows outward from its middle instead of inward from its rim. Floor lanes
  become pools of light in the middle of rooms; ceiling lanes become
  chandeliers. **Zero shader change** — a point is a segment with a == b.

**Built from:** the list-building loop in `HWFlat::DrawFlat` + a per-plane
mode int plumbed like `FlatGlowFalloff` already is.
**Effort:** engine S–M (see E3). **Wow/effort: 4** — stairs and pools are
both screenshot generators.

### P6. Intensity honesty for the flats (the quiet fix that outranks features)
Fix brick #2 above: make cg/fg Intensity multiply the glow **colour** (as
floats, pre-clamp, exactly like `uGlowTopIntensity` does for walls) and leave
reach to Coverage alone. Every existing config gets slightly more correct:
the sliders finally mean the same thing on all four lanes, intensity 2 on a
floor lane finally punches into bloom the way the wall lanes always could,
and the menu text stops needing an asterisk nobody wrote. This is the
strip-to-essence item: not a new option, the removal of a lie.
**Built from:** two lines in `hw_flats.cpp`, one multiply in `main.fp`'s flat
branch. **Effort:** engine S (see E1). **Wow/effort: 5** for the cost.

---

## 2. EXPAND — lanes that answer the game

### X1. The Reactive page (the centrepiece — full spec in §5)
One menu page where every "the room reacts" behaviour lives: get hurt and the
walls flinch; kill and the floor answers; a captain's presence leans on the
ceiling; bullet time drains the palette; kill pace sets the tempo. Each is a
routing-table row — SOURCE → response, lane, strength, decay — cvar-gated,
default off. The machinery is one small compositor for lane *modifiers*
(applied between `Step()` and `ApplyOne`, never touching the player's cvars),
so reactions stack with presets, randomise and patterns instead of fighting
them. Spec'd in full in §5 because it deserves cvar names.
**Effort:** M for the page + first four sources; each further source S.
**Wow/effort: 5.**

### X2. GITD_LaneAction — the lane script hook
`GITD_SweepAction` made the sweep programmable by *name* — a cvar can point
at a class. Mirror it: `gitd_lane_script` names a `GITD_LaneAction`; each tic
after the lanes resolve, it gets one call per lane —
`ModifyLane(int lane, GITD_Lane l)` — and may rewrite `outColor` /
`outIntensity` before application. Resolve-once-and-keep, exactly like
`GITD_SweepAction.Resolve`. Suddenly "the floor lane is the boss's health
bar", "lanes walk the tier palette in tier order", "lanes strobe on the beat
of D_RUNNIN" are twenty-line mods that ship outside GITD, and the Reactive
page's built-ins are just the house-written instances of the same hook.
**Built from:** the `ssActName/ssActObj` resolve pattern, four virtual calls
in `Apply()`. **Effort:** S–M. **Wow/effort: 4** (it multiplies other
people's wow).

### X3. Rooms that keep their own light (SetSectorOverride's first customers)
Brick #3: the override channel exists and nothing uses it. Three built-in
customers, each one toggle:

- **Hazard floors** (`gitd_hazard_lanes`): sectors with damaging specials get
  their floor lane forced to a hazard colour (own colour cvar; nukage green /
  lava orange defaults) with a slow warning pulse. In a pitch-dark room the
  floor itself says *don't step here* — arcade-legible, and it is information
  the map already encodes.
- **Secret shimmer** (`gitd_secret_lanes`): unfound secret sectors get a
  barely-there ceiling flicker — not a marker, a rumour; found ones stop.
  Deliberately subtle enough to argue about.
- **Exit beacon** (`gitd_exit_lanes`): the exit sector's lanes hold one
  steady colour that never cycles. When everything else swims, the still room
  is the way out.

All three are a `WorldLoaded` scan plus `SetSectorOverride`, refreshed only
when their colour cvars change. They also *prove the override channel* for
modders by example.
**Effort:** S each, M as a set. **Wow/effort: 4** (hazard floors alone: 5).

### X4. Accent walls — doors wear their key's colour
Brick #1: per-wall glow, installed and unused. At map load, classify lines by
special: locked doors get their sidedef glow set to **the key's colour** —
red card, blue card, yellow skull; Doom has had a colour language for locks
for thirty years and this finally consumes it — plain doors and switches get
an accent cvar colour, exit lines get the exit colour from X3. Written once,
sticky, **zero per-tic cost** (side glow persists until rewritten; the lane
loop never touches sides). The player sees: across a dark arena, every
usable wall is dressed, and a locked door advertises which key it wants from
two rooms away. This is the single biggest legibility gift the 4×8 can make
to a dark game.
Caveat, priced honestly: a side's falloff/intensity still come from its
sector (`hw_walls.cpp` reads sector values for those), so accents inherit
their room's glow *shape* — fine for v1; E4 lifts it if it ever matters.
**Built from:** `Side.SetGlowColor/SetGlowHeight` + a special-number
classification table (the actual work) + `gitd_accent_*` cvars.
**Effort:** M. **Wow/effort: 5.**

### X5. Tempo as a lane property
`_speed` and `_anim_speed` are constants. Add one global multiplier the game
can breathe on — `gitd_tempo` (float, default 1, script/Reactive-writable,
never saved): all four lanes' phase and anim clocks advance scaled by it. On
its own it is a QoL slider ("everything 20% slower" without editing eight
cvars); wired to kill pace (§5) the room hurries when you hurry; wired to
bullet time it crawls. One multiply in `Step()` and one in the animClock
advance.
**Effort:** S. **Wow/effort: 3** alone, more as plumbing for X1/T4.

---

## 3. TIE-INS — the 4×8 meets the newer systems

Judged against one test: **does it read in a dark room mid-fight, or is it
noise?**

### T1. Underlay — waves ride over the lanes instead of replacing them
Today ANY live wave calls `ClearAll()`: the whole 4×8 goes black while a
sweep runs, because the sweep was designed as "a dark room with nothing but
the lines". Keep that as the default — it is a valid look — but add
`gitd_ss_underlay`: lanes stay lit, `Apply()` still runs, and the wave
perturbs them in passing. The recolour fx (`fx = 3`) stops *replacing* lane
glow and instead **lerps each lane's own colour toward the band colour by
strength** — and because the lanes rewrite themselves every tic, the room
relaxes back to its resting palette on its own the moment the band moves on.
No restore bookkeeping, no journal: the resting state *is* the steady state.
The player sees their neon room stay theirs, and a passing wave drag every
colour in the room toward itself and let go — the single most
musical image the two systems can make together, and it falls out of
deleting one `ClearAll()` call behind a cvar.
Reads mid-fight: **yes** — it is the whole room, briefly, then gone.
**Built from:** a branch in `WorldTick` + a lerp in the fx-3 block (lane
`outColor` is already resolved and readable there).
**Effort:** S. **Wow/effort: 5.**

### T2. Combo milestones flash the floor
Consume the combo/chain state (Overload's chain count, or whatever ledger
ships): at each milestone the **floor lane** flashes to the milestone's
colour and decays over ~half a second. Floor, specifically: mid-fight your
eyes are at monster height and the floor under them is the one lane always
in frame. A milestone you *feel underfoot* beats a number in a corner.
Reads mid-fight: **yes** (brief, bright, floor-wide). Noise risk at high
combo rates — the decay envelope caps re-trigger, and it is one Reactive row.
**Effort:** S once §5 exists. **Wow/effort: 4.**

### T3. The captain leans on the ceiling
While a captain/miniboss lives, the **ceiling lane** is pulled partway toward
its tier colour (consumed from the tier palette authority, never chosen
here) — a standing pressure, not a flash. When it dies the ceiling releases
and the room visibly exhales. The ceiling is the right lane: it is the one
you see *over* the fight, it reads as weather, and "the sky belongs to the
boss until you take it back" is the arcade essence of a miniboss in one
sentence.
Reads mid-fight: **yes** — it is ambient state, not an event; the *release*
is the readable moment.
**Effort:** S (a standing Reactive row watching the roster).
**Wow/effort: 4.**

### T4. Bullet time drains the room
When `bt_*` engages, lane saturation scales toward 0 and `gitd_tempo` (X5)
drops with the dilation — the palette greys out and the crests crawl; on
exit, colour and tempo slam home together. The Saturate hook already exists
per-lane; this is a modifier on top of it. Pure spectacle riding a mechanic
another mod paid for, and the ideas-doc Time Sculptor wave layers on top of
it untouched.
Reads mid-fight: **yes** — whole-screen, unambiguous, state-locked.
**Effort:** S. **Wow/effort: 4.**

### T5. The badge agrees with the floor
`gitd_neon_color` is the numeric engine's *fallback* colour. Add
`gitd_neon_match_floor`: when no mod passed a meaningful colour, the badge
samples the floor lane's current `outColor` at pop time — so kill counters
and floor marks look native to whatever the room is wearing tonight.
Meaning always wins over matching: a passed colour is never overridden.
Reads mid-fight: n/a — it is coherence, not signal. The cheapest "one
product, not five mods" purchase available.
**Effort:** S. **Wow/effort: 3.**

### T6. Setpieces push a Moment (and journal it)
`GITD_Setpiece` gains one field: `moment` — a Moment id (§4). Sweep-in pushes
the whole look (lane palette, darkness, sweep config) through the same
working-set mechanism the preset customiser already uses, journalled like
everything else a setpiece touches; sweep-out pops it. The arena stops being
"the same room, tinted" and becomes "a different place with the same
geometry" — and it un-becomes itself on the way out, wave-shaped, like the
rest of the setpiece machinery.
**Effort:** M (mostly the capture/restore of the working set).
**Wow/effort: 4.**

---

## 4. PRESETS — from palette to Moment

### M1. Moments — one number for a whole look
A preset answers "what colours". It deliberately does not answer "how dark,
how fast, is the sweep running, what shape". A **Moment** does: it is a
named bundle of {preset/working set, lane pattern+speed+anim, darkness level
(`ddz_preset`), sweep on/off + its shape/trigger/fx}. Eight slots
(`gitd_m1..8_*`), each with **Capture current** (reads the live cvars in)
and a name. Switching Moments writes the bundle back through the cvars —
and because every lane pattern already eases, the room *crossfades itself*
to the new look with no extra animation code.
Then the two features that fall out free:
- **A bindable cycle key** (`netevent gitd_moment_next`): performing the room
  live — one keypress from Deep Sea calm to Red Alert lockdown.
- **Attract mode** (`gitd_moment_cycle` seconds): the mod demos itself.

Explicit simplification choice: presets do **not** grow thirty new `gitd_pN_*`
cvars each to capture sweep state. Presets stay colour+shape; Moments own
composition. Two clean concepts beat one bloated one.
**Built from:** the `GITD_PresetCustomiser` load/save pattern, generalised;
one menu page; two netevents.
**Effort:** M. **Wow/effort: 4.**

### M2. Ship the missing Moments
With M1 in, the curated bundles from the ideas doc (Lights Out, Two-Tone
Breath, Muzzle Ripples) become *shipped Moments* instead of prose — the
"total conversion made of existing cvars" finally has a container. Effort S
each once M1 lands.

---

## 5. THE REACTIVE PAGE — MENUDEF-level spec

One page, routing-table shaped, read top to bottom: **a list of sources,
each mappable to a response.** Every row default-off except the starter
(damage-taken flash), so the page demos itself the first time you are hit.
All cvars `server`, prefix `gitd_rx_`.

### The shared enums

```
OptionValue "GITDRxResponse"
{
    0, "Off"
    1, "Flash"            // spike to the row's colour, then decay
    2, "Tint while active" // standing pull toward the colour, releases with the source
    3, "Brighten"          // intensity spike
    4, "Darken"
    5, "Pulse"             // inject one anim crest -- the room's EKG skips
    6, "Drain colour"      // desaturate
    7, "Hurry"             // tempo up (uses gitd_tempo, X5)
}

OptionValue "GITDRxLane"
{
    0, "All lanes"
    1, "Floor"
    2, "Ceiling"
    3, "Both walls"
    4, "Wall bottom"
    5, "Wall top"
    6, "Floor + ceiling"
}
```

### The cvar grid — four per event source, three per standing source

Event sources (fire, then decay over `_decay` tics):

| Source | Response | Lane | Colour | Strength | Decay | Default |
|---|---|---|---|---|---|---|
| You are hurt | `gitd_rx_hurt` | `gitd_rx_hurt_lane` | `gitd_rx_hurt_color` | `gitd_rx_hurt_str` | `gitd_rx_hurt_decay` | **Flash, both walls, red, 0.6, 18** — the starter |
| You deal damage | `gitd_rx_dealt` | `_dealt_lane` | `_dealt_color` | `_dealt_str` | `_dealt_decay` | Off |
| You kill | `gitd_rx_kill` | `_kill_lane` | `_kill_color` | `_kill_str` | `_kill_decay` | Off |
| Combo milestone | `gitd_rx_combo` | `_combo_lane` | `_combo_color` | `_combo_str` | `_combo_decay` | Off (colour ignored if the combo system announces its own) |
| Secret found | `gitd_rx_secret` | `_secret_lane` | `_secret_color` | `_secret_str` | `_secret_decay` | Off |

Standing sources (active while the state holds, release when it ends):

| Source | Response | Lane | Param | Default |
|---|---|---|---|---|
| Low health | `gitd_rx_lowhp` + `_lowhp_lane`, `_lowhp_color`, `_lowhp_str` | | `gitd_rx_lowhp_below` (health %, default 25) | Off |
| Captain alive | `gitd_rx_captain` + `_captain_lane`, `_captain_str` | | colour consumed from the tier palette, never set here | Off |
| Director mood | `gitd_rx_mood` + `_mood_lane`, `_mood_str` | | colour consumed from the director's own announcement | Off |
| Bullet time | `gitd_rx_bt` + `_bt_str` | | response is Drain colour + tempo, lane always All | Off |
| Kill pace | `gitd_rx_pace` + `_pace_str` | | response is Hurry; `gitd_rx_pace_window` (secs, default 10) | Off |

### The page

```
OptionMenu "GITDReactive"
{
    Class "DarkDoomZ_OptionMenu"
    Title "Reactive Glow"
    StaticText ""
    StaticText "The room answers the fight. Each row: an", darkgray
    StaticText "event, and what the lanes do about it.", darkgray
    StaticText ""
    StaticText "When you are hurt", gold
    Option "  Response",        "gitd_rx_hurt", "GITDRxResponse"
    Option "  Lanes",           "gitd_rx_hurt_lane", "GITDRxLane", "gitd_rx_hurt"
    ColorPicker "  Colour",     "gitd_rx_hurt_color"
    Slider "  Strength",        "gitd_rx_hurt_str", 0.0, 1.0, 0.05, 2
    Slider "  Fades over",      "gitd_rx_hurt_decay", 5, 105, 5, 0
    StaticText ""
    StaticText "When you deal damage", gold
    ... same five rows, gitd_rx_dealt_* ...
    StaticText "When you kill", gold
    ... gitd_rx_kill_* ...
    StaticText "Combo milestones", gold
    ... gitd_rx_combo_* ...
    StaticText "When you find a secret", gold
    ... gitd_rx_secret_* ...
    StaticText ""
    StaticText "Standing states", gold
    StaticText "These hold while the state holds, and", darkgray
    StaticText "release when it ends.", darkgray
    ... low health block (adds the Below slider) ...
    ... captain block (no colour picker -- "Colour comes from the", darkgray
                       "captain's own tier.") ...
    ... director mood block ...
    Option "Bullet time drains the room", "gitd_rx_bt", "OnOff"
    Slider "  How far",         "gitd_rx_bt_str", 0.0, 1.0, 0.05, 2
    Option "Kill pace sets the tempo",    "gitd_rx_pace", "OnOff"
    Slider "  Up to",           "gitd_rx_pace_str", 1.0, 3.0, 0.1, 1
}
```

Root menu gets one line, under Lane control:
`Submenu "Reactive Glow", "GITDReactive"`.

### How it runs (and why it cannot fight anything)

One handler (`GITD_Reactions`, or folded into `GITD_Handler`) keeps a
0–1 **envelope per source**: event sources snap to 1 on their event
(`WorldThingDamaged` both directions, `WorldThingDied`,
`level.found_secrets`, combo state) and decay linearly over `_decay`;
standing sources track their state directly. Then, in `Apply()`, **after**
`Step()` resolves each lane and **before** `ApplyOne` writes it, the active
rows fold in, lane-compositor style so order never matters:

- tints/flashes: lerp `outColor` toward the row colour by
  `envelope * strength` (bounded, applied in fixed source order);
- brighten/darken: summed into an intensity delta;
- drain: max() into a desaturation term fed to the existing
  `GITD_Palette.Saturate`;
- pulse: one injected crest via a `Pulse()` method on `GITD_Lane`
  (a phase kick to `animClock`);
- hurry: multiplied into `gitd_tempo` for this tic.

Nothing writes a cvar, nothing survives the tic, presets and randomise and
patterns keep running underneath — a reaction is a *modifier on the resolved
colour*, exactly the relationship `GITD_Composite` has to sector light.
Every row a player reads is one line: *this happens → these lanes do this,
this hard, fading this fast.*

**Effort:** M for page + envelopes + the five event sources; each standing
source S on top (captain/mood land when their state is readable — until then
their rows simply do not appear). **Wow/effort: 5 — this is the item the
owner already steered toward.**

---

## 6. ENGINE PROPOSALS — priced honestly

We own the engine; the currency is StreamData bytes, cross-surface state
fragility (the flat-glow-leaked-onto-walls bug is the cautionary tale — new
per-surface uniforms mean new places to forget `ClearFlatGlow`-style resets),
and shader ALU.

### E1. Flat glow intensity multiplies colour, not reach — **do this one**
`hw_flats.cpp` stops folding intensity into reach; instead premultiply the
r/g/b floats by intensity (uniform is float — values above 1 are legal and
feed bloom exactly as wall glow does), reach = height alone.
**Cost:** two lines CPU, one multiply in `main.fp`'s flat branch. No new
uniforms, no new state to clear. Behaviour change is real but is the honest
one; note it in the menu text. **Effort: S.**

### E2. Two-stop wall gradient (colour A at the plane, through colour B)
A second colour per wall glow: `uGlowTopColor2/uGlowBottomColor2`, lerped by
the same `glowdist` fraction before attenuation. Buys true vertical gradients
per lane — sunset walls, fire-to-smoke — a genuinely new look the two-lane
overlap only approximates.
**Cost:** +2 vec4 per draw in StreamData (the fixed 64KB buffer the sweep
docs already treat as contended — this is the same trade multi-origin waves
were refused, at half the size), 2 setter thunks, 2 colour pickers per wall
lane, and the ZScript plumb. **Effort: M. Wow/effort: 3** — good, but it is
a layering idea; P1/P2 get 80% of the motion for none of the bytes.

### E3. Flat-glow line modes: edge select + centre pool
Per-plane mode int (like `FlatGlowFalloff` already is): All edges / one-sided
only / height-change only / centroid point. Selection happens in the CPU loop
in `HWFlat::DrawFlat` that already rebuilds the 64-line list per draw; the
centroid mode uploads one degenerate segment and **needs no shader change at
all**. One new sector-plane field, one thunk, savegame serialisation of one
int. **Effort: S–M.** The stair-tread look and the centre pool are the two
cheapest genuinely-new flat images available. **Wow/effort: 4.**

### E4. Per-side falloff/intensity
`ApplyWallOwnGlow` overrides colour+height but falloff/intensity still read
the sector. Only matters once X4 accent walls exist and someone wants a
crisp accent in a soft room. Two more side fields + thunks. **Effort: S,
but do not build until X4 proves the want.**

### E5. Glow dither
Low-intensity glow gradients band visibly in dark rooms (8-bit output of a
smooth ramp). A ±0.5/255 ordered-dither nudge on the glow contribution in
`main.fp` hides it. Tiny ALU, no state. **Effort: S. Wow/effort: 2** — but
it is the kind of polish nobody names and everyone feels.

Deliberately **not** proposed: per-sector glow uniforms beyond what exists
(the lanes are per-sector already via CPU writes — correct division of
labour), and any new render target (Phosphor Memory stays in the moonshot
doc where it belongs).

---

## 7. THE TOP TEN

| # | Idea | Effort | Why it wins |
|---|---|---|---|
| 1 | **X1/§5 Reactive page** | M | The room wired to the fight, one page, owner-steered. |
| 2 | **T1 Underlay** — waves perturb lanes, don't kill them | S | One deleted `ClearAll` behind a cvar; the two flagship systems finally coexist. |
| 3 | **X4 Accent walls** — locked doors glow their key's colour | M | Thirty-year-old colour language, finally consumed; zero per-tic cost. |
| 4 | **P6/E1 Flat intensity honesty** | S | Half the 4×8's sliders start telling the truth. |
| 5 | **M1 Moments** | M | Preset + darkness + sweep as one switchable, bindable, capturable look. |
| 6 | **P2 Breathe/Heartbeat anims** | S | Ambience with a pulse; two branches in `AnimFactor`. |
| 7 | **X3 Hazard floors / exit beacon / secret shimmer** | S–M | `SetSectorOverride` gets its first customers; the floor says *don't step here*. |
| 8 | **P1 Drift pattern** | S | The transition with no arrivals; smoothest thing the lanes can do. |
| 9 | **E3/P5 Flat-edge modes** — stair treads + centre pools | S–M | Two new images from a CPU loop we already own; centroid trick needs no shader. |
| 10 | **T4+T5** — bullet-time drain + badge matches floor | S | Two small coherence wins that make five systems read as one product. |

Near-misses kept on the record: P3 comet crests, P4 bleed dial, X2
`GITD_LaneAction` (build it the moment a second mod wants in), X5 tempo
(build as part of #1), T2/T3 (they ship *as rows* of #1), E2 gradient
(revisit if P1+P2 leave anyone wanting), T6 setpiece-Moments (after M1).

---

## Seamless Corners — DONE, both junctions, engine side included

**Status: built.** Each of the four glow channels now carries a second
colour and ramps between them by attenuation. Both junctions ship together.
The rest of this section is kept as the record of what was wrong and what
the fix actually was.

What landed:

| piece | where |
|---|---|
| `uGlowTopFar`, `uGlowBottomFar`, `uFlatGlowFar` | `hw_renderstate.h`, `vk_shader.cpp`, `gl_shader.*` |
| the `mix()` in all three glow blocks | `main.fp` |
| `GlowColorFar` / `FlatGlowColorFar` per plane | `r_defs.h` |
| `Sector.SetGlowColorFar` / `SetFlatGlowColorFar` | `vmthunks.cpp`, `mapdata.zs` |
| junction colour fed to both sides | `GlowHandler.zs`, the `gitd_seamless` block |

Three new uniforms, not four: floor and ceiling flat glow time-share one
slot because a draw only ever covers one of them. The cost was paid out of
the `padding4` slack already in `StreamData`, so `MAX_STREAM_DATA` is still
34 and draw batching is unchanged — verified by `static_assert`, both
directions.

Alpha 0 on a far colour means unset and the glow is byte-for-byte the flat
wash it always was, so nothing changes until `gitd_seamless` is on.

**E1 went in with it.** Flat intensity now multiplies colour, not reach, so
the wall and flat Intensity sliders are finally the same quantity — and the
workaround that scaled the flat's colour by the wall's intensity is deleted
rather than left in place.

---

### The record: what was wrong

Previously shipped: both surfaces took one shared colour at the junction,
with matched reach and falloff. The seam went away.

**Not what was asked for.** The ask was a GRADIENT across the corner -- floor
purple ramping into wall blue -- keeping both lane colours and blending
between them. What shipped made both sides *the same colour* near the join,
so the seam died and the two-colour transition died with it.

**What the real version needed.** A glow held one colour and only its
STRENGTH varied with distance:

```glsl
color.rgb += uGlowBottomColor.rgb * botatten * uGlowBottomIntensity;
```

Give each glow channel a SECOND colour and let it ramp:

```glsl
vec3 gc = mix(uGlowBottomFar.rgb, uGlowBottomColor.rgb, botatten);
color.rgb += gc * botatten * uGlowBottomIntensity;
```

`uGlowBottomColor` becomes the JUNCTION colour (at the line, atten 1) and
`uGlowBottomFar` the lane's own (as it fades out). Same for the flat-edge
glow. The corner then reads as one continuous ramp: floor colour → blend →
wall colour, with no flat region anywhere in it.

**BOTH junctions, not one.** A room has two of these and they are the same
problem twice:

| junction | the two glows that meet | pairs |
|---|---|---|
| floor / wall | flat floor glow + wall BOTTOM glow | `fg` ↔ `wb` |
| ceiling / wall | flat ceiling glow + wall TOP glow | `cg` ↔ `wt` |

The ceiling one matters more than it sounds. Wall-top glow fades DOWN from the
ceiling and the ceiling's edge glow fades IN from the same line, so the ramp
runs ceiling colour → blend → wall colour exactly as the floor's does --
mirrored. A room with both running is bounded top and bottom by continuous
colour and has no hard edge anywhere, which is the whole point of owning four
lanes rather than two.

Both junctions need the same treatment and the same uniform: four glow
channels, four second-colours. Doing one and not the other would look worse
than doing neither, because the eye reads the mismatch immediately.

Cost: one extra colour uniform per glow channel (wall top, wall bottom, flat
floor, flat ceiling), a `mix()` in each glow block, and the script side
feeding both ends. Small, but engine work rather than a script toggle -- which
is why the shipped version is script-only.

**Related bug to fix in the same pass.** The two Intensity values are not the
same quantity: on a wall it multiplies the colour, on a flat it multiplies the
REACH (hw_flats.cpp scales FlatGlowHeight by it). Seamless Corners works
around that by scaling the flat's colour by the wall's intensity. A real
brightness term for flats would remove the workaround and make the two
Intensity sliders mean the same thing, which they currently do not.
