# Death-Ping — the import plan and its life as a system

The dice picked Death-Ping. This document is three things: the original code
and what it draws, the plan for a LITERAL transcription into the engine
(following `func_wg13.fp`, the gold standard — transcribe, never approximate),
and the design for what a ping becomes once it is a trigger source rather than
a decoration.

Draft files, not wired into anything:

- `design/drafts/func_deathping.fp` — the shader transcription
- `design/drafts/DeathPing.zs` — the mod-side system

---

## 1. The original, verbatim

### Where it lives

`GlowInTheDark.pk3:shaders/glsl/main.fp` (the packaged build at
`D:\SteamLibrary\steamapps\Common\DooM VR\not relevant for claude project\New folder\GITD-Win64\GITD\GlowInTheDark.pk3`).
The wgType dispatch runs lines 831–1073. Death-Ping is **wgType 3**, lines
1026–1031 — the shortest branch in the whole family. The naming chain that
proves it: `menudef` `GITD_DeathStyle` value 3 is `"Death-Ping (ring)"`,
`gitd3_deathfx.zs` line 1157 maps style 3 to class `GITD_FX_DeathPing`, and
that class emits `wipeType 3`, which the shader catches at `wgType > 2.5`.
The same ring doubles as the original's "Ring" impact stamp
(`GITD_ImpactStyle` 2 → the same class).

For the record, the full wgType roster as shipped: 0 bloom, 1 seam,
2 stroke/bar (Ghost Walk's trail, Stylized X's strokes), **3 ring
(Death-Ping)**, 4 hex field, 5 hex rings, 6 spiral, 7 square rings, 8 star,
9 sunburst, 10 grid, 11 invert, 12 box window, 13 kill badge (imported
already as `func_wg13.fp` / `BB_WG13`).

### The shader branch, line for line

Context first — these are set once for every glow spot, before the dispatch
(lines 755–763):

```glsl
float wgDist = length(pixelpos.xz - wgSp.xy);
if (wgDist < wgSp.w)
{
    float wgPk = wgSp.z;
    vec3 wgCol = vec3(floor(wgPk / 65536.0), floor(mod(wgPk, 65536.0) / 256.0), mod(wgPk, 256.0)) / 255.0;
    vec4 wgMask = uWallGlowMask[wgIdx];
    ...
```

`wgSp` is the spot: `.xy` centre, `.w` radius, `.z` packed colour.
`wgMask.y` is progress. And the branch itself, lines 1026–1031, VERBATIM:

```glsl
				else if (wgType > 2.5)
				{
					float ringR = wgMask.y * wgSp.w;
					float thick = wgSp.w * 0.10;
					wgAdd = wgCol * (1.0 - smoothstep(0.0, thick, abs(wgDist - ringR)));
				}
```

Three lines of maths. What each does:

- **`ringR = wgMask.y * wgSp.w`** — the ring's current radius is progress
  times the full reach. Progress 0 is a point at the corpse; progress 1 is
  the full circle. Progress IS the animation; the shader holds a still frame.
- **`thick = wgSp.w * 0.10`** — the band is a fixed tenth of the full radius,
  which means a bigger ping has a proportionally thicker ring. It does not
  thin as it expands.
- **`wgAdd = wgCol * (1.0 - smoothstep(0.0, thick, abs(wgDist - ringR)))`** —
  brightness peaks exactly on the circle and falls off smoothly over `thick`
  on BOTH sides, inside and out. One symmetric falloff; no separate core and
  halo terms, no hard edge anywhere — except one:
- **the outer gate.** The whole dispatch sits inside
  `if (wgDist < wgSp.w)`, so the ring's skirt is cut dead at the full radius.
  As progress approaches 1 the leading half of the band is clipped by the
  spot's own boundary and the ring dies AT the edge, not politely beyond it.
  That cut is part of the look and must survive the transcription.

Notably absent from the shader: any fade. The ring at progress 0.9 is as
bright as at 0.1, as far as the GLSL is concerned.

### The animation layer, verbatim

The fade lives in script. `ZSCRIPT/gitd3_deathfx.zs` lines 444–463:

```zscript
// ---- STYLE 4: Death-Ping -- a bright pulse detonates outward (tier-scaled).
//      (v1 = filled expanding pulse; a true hollow ring is a ring-shader add.)
// A hollow neon ring detonates outward from the corpse and fades as it expands (radar ping).
class GITD_FX_DeathPing : GITD_DeathEffect
{
    double maxReach;
    // Short life; ring radius scales with tier.
    override void EffectSpawn()
    {
        lifeTics = 30;
        int sz = FxSize();
        maxReach = double(sz) * (1.0 + 0.35 * tier);
    }
    // wipeType 3 = expanding hollow ring; progress = t drives the ring outward, brightness = 1-t.
    override void Tick01(double t)
    {
        // hollow RING detonates outward (wipeType 3), fading as it expands
        EmitSpot(FxColor(t, 1.0 - t), PlaneR(maxReach), pos.x, pos.y, 3, t, 1.0, 0.0, PlaneFlags());
    }
}
```

So the ORIGINAL Death-Ping, complete: on a kill, a ring detonates outward
from the corpse over **30 tics** (~0.86 s). Its reach is the death-glow size
scaled by monster tier — `size × (1 + 0.35 × tier)`, so a tier-3 kill rings
at just over double a tier-0 one. Progress advances linearly with life
(`t`), brightness dims linearly to nothing (`1 − t`), and the colour comes
from the tier/fixed/random/rainbow colour machinery every death style
shares. One glow spot, re-emitted each tic; nothing persists.

On screen: a radar ping. A thick soft neon circle snaps out of the corpse,
races outward on the floor, dimming as it goes, and is gone in under a
second — cyan for fodder, hot red for the thing that nearly killed you.

---

## 2. The transcription plan

`func_wg13.fp` is the precedent and this follows it exactly, at every layer.
The engine change is SMALL — WG13 minus the digit maths. Six touch points:

### 2.1 The shader — `wadsrc/static/shaders/glsl/func_deathping.fp` (new)

Draft at `design/drafts/func_deathping.fp`. The one legitimate change, and
it is the SAME change func_wg13 documented: the original works in world
space, measuring from a glow spot's centre; a billboard fragment is already
in the quad's own space, −1..1 on both axes. On a SQUARE quad,

```
wgDist / wgSp.w  ==  length(p)        ringR / wgSp.w  ==  nProg
thick  / wgSp.w  ==  0.10
```

and dividing all three arguments of a `smoothstep` by the same positive
radius changes nothing. Every constant survives untouched. The outer gate
`if (wgDist < wgSp.w)` becomes `if (nR >= 1.0)` — same cut, same place.
Alpha follows the band so the ping is a ring rather than a square quad
(func_wg13.fp line 94's move). The fade stays OUT of the shader, where the
original kept it: script dims the colour.

Square dimensions are the caller's contract. A rectangular quad would draw
an elliptical ping the original could not — the exact inverse of WG13's
lozenge note, where CIRCULAR was the caller error.

### 2.2 `src/common/textures/textures.h` — the enum

Add `SHADER_DeathPing,` immediately after `SHADER_WG13` (line 91), before
`FIRST_USER_SHADER`.

**THE SYNC HAZARD, spelled out because nothing else will:** the comment at
textures.h line 85 warns that `defaultshaders[]` in `hw_shaderpatcher.cpp`
is indexed by this enum and NOTHING checks that they agree. Add the enum
entry without the table row — or in a different position — and every shader
after it shifts one slot: the wrong .fp compiles under the wrong name and
the failure appears somewhere unrelated. The enum entry and the table row
are ONE edit that happens to touch two files.

### 2.3 `src/common/rendering/hwrenderer/data/hw_shaderpatcher.cpp` — the table

Add after the WG13 row (line 305), before the null terminator:

```cpp
	// [BB] GITD's Death-Ping, transcribed. A radar ring; progress IS the
	// animation and rides uAddColor.r, exactly as WG13's does.
	{"DeathPing", "shaders/glsl/func_deathping.fp", "shaders/glsl/material_nolight.fp", "#define NO_LAYERS\n"},
```

`material_nolight` + `NO_LAYERS` for the same reason as the other three
billboard shaders: it is emissive UI in world space and samples no texture
(callers bind `bbwhite` because the material path needs something valid).

### 2.4 `src/g_levellocals.h` — the payload

Add to `EBillboardPayload` after `BB_WG13` (line 127):

```cpp
	// [BB] GITD's Death-Ping, transcribed rather than approximated. A radar
	// ring: brightness peaks on a circle at progress x radius and falls off
	// over a tenth of the radius both ways, cut dead at the quad edge as the
	// original cut at its spot radius. Drive `progress` to detonate it; the
	// fade is the caller dimming `color`, as the original's script did.
	// `data` is unused. Square dimensions or it is an ellipse.
	BB_DEATHPING = 11,
```

### 2.5 `src/rendering/hwrenderer/scene/hw_sprites.cpp` — the dispatch

New case in `EmitBillboardPayload` beside `case BB_WG13:` (line 2365),
following it exactly:

```cpp
	case BB_DEATHPING:
	{
		FGameTexture* white = GetBillboardShape("bbwhite");
		if (white == nullptr) return;

		// Progress in red, as WG13 carries it. The other three channels
		// carried the original's packed colour; colour arrives as the tint
		// (uObjectColor) here, so they carry nothing.
		const int pr = (int)(clamp(bb->progress, 0.0, 1.0) * 255.0 + 0.5);
		const PalEntry savedGlow = bbGlow;
		bbGlow = PalEntry(0, (uint8_t)pr, 0, 0);

		const int savedShader = OverrideShader;
		OverrideShader = SHADER_DeathPing;
		emit(0.0, 0.0, halfw, halfh, white, tint, FBillboardUV());
		OverrideShader = savedShader;
		bbGlow = savedGlow;
		return;
	}
```

(`PalEntry(a, r, g, b)` — red is the second argument; WG13's dispatch at
line 2375 is the template. `bbGlow` rides to the shader as `uAddColor` via
`state.SetAddColor(bbGlow)` at line 262.)

### 2.6 `wadsrc/static/zscript/doombase.zs` — the script enum

Add `BB_DEATHPING = 11,` to the script-side `EBillboardPayload` copy
(after `BB_WG13 = 10` at line 580), with the sizing contract in the comment.

### What carries what — the full manifest

| Channel | Carries | Original equivalent |
|---|---|---|
| `uObjectColor` | the tint, pre-dimmed by script each tic | `wgCol` × script's `FxColor(t, 1-t)` |
| `uAddColor.r` | progress 0..1 as a byte (`bbGlow.r`) | `wgMask.y` |
| `uAddColor.gba` | nothing | carried the packed colour |
| `data` | nothing | — |
| quad half-extent | the full reach `wgSp.w` (square!) | `wgSp.w` |
| billboard `alpha` | whole-effect fade handle, if wanted | — |

Progress quantises to 8 bits riding a colour channel — 1/255 steps. WG13
accepted the same and nothing stepped visibly; a ring sweeping its radius
in 30 tics moves ~8 counts per tic, far below notice.

Cost verdict: **small**. One new .fp, one enum entry, one table row, one
payload entry, one dispatch case, one script-enum line. No uniforms added,
no formats touched, no Vulkan/GL special-casing (verified: `WG13` appears in
exactly five places across `src/`, all of them the five above).

---

## 3. The system — a ping is a trigger source

The original ping was a picture. Here it becomes the START of things: a
corpse pings, the ring is a travelling QUERY over the world, and what it
touches can escalate. Everything below is menu-gated and defaults to the
tame end; the escalations are opt-in. No actor is ever spawned for a ping —
billboards are level-owned, and the driver is plain Objects in the handler,
the kill counter's own pattern.

Draft implementation: `design/drafts/DeathPing.zs`.

### 3.1 Lifecycle at a corpse

1. `WorldThingDied` fires. Gates: `gitd_ping_enabled`, thing is a monster,
   and `gitd_ping_playeronly` decides whether infighting corpses ping too
   (default they DO — "every corpse pings" is the directive; the kill
   counter's player-only rule is about score, this is about the world).
2. One persistent `BB_DEATHPING` billboard is laid flat (`tilt 90`) at the
   corpse, `floorz + 4`, square, `BBFL_NOHIT`. Reach is
   `gitd_ping_size × (1 + gitd_ping_tier_scale × tier)` — the original's
   tier scaling with the 0.35 now a knob. Progress starts 0.
3. A ping record (plain Object) joins the handler's array. Per tic it
   drives `SetBillboardProgress(id, t)` and re-tints via `UpdateBillboard`
   with the colour dimmed by `1 − t` — the original's fade, done where the
   original did it. Life is `gitd_ping_life` seconds (default 0.85 ≈ the
   original 30 tics).
4. At end of life: `RemoveBillboard`, unless `gitd_ping_echoes > 0`, in
   which case the SAME billboard re-runs, each echo starting dimmer —
   radar sonar, no new allocation.
5. Cap: `gitd_ping_max` live pings; past it the oldest is retired early
   (the original's impact ring-buffer lesson — a slaughtermap must not
   starve everything else, and 200 corpses in one blast radius is Tuesday).

### 3.2 The ring as a query

While a ping runs, its wavefront radius is known exactly:
`R(t) = reach × t`. Once per tic the handler tests candidates against the
ring: a thing is TOUCHED the tic its 2D distance crosses R (previous R <
d ≤ R). Monsters come from a `BlockThingsIterator` at the ping's reach,
gated by `gitd_ping_actors` (walking things is not free — same reasoning
as `gitd_ss_actors`). Corpses come from the handler's own ledger of recent
deaths, which is cheap and already there.

Everything below keys off "touched".

### 3.3 Ping → Sweep (`gitd_ping_sweep`)

The corpse becomes a sweep origin. When a ping fires (mode 1/2/3), it also
calls `GITD_Sweep.Fire(corpse.pos, SHAPE_RING, col, gitd_ping_sweep_speed,
gitd_ping_sweep_range)` — the ping is the fuse, the sector-sweep band is
the payload, and because `Fire` ADDS a wave, a firefight becomes
overlapping ripples of room-lighting without any wave stealing another's
state. Modes: 0 off · 1 every ping · 2 every Nth (`gitd_ping_sweep_every`)
· 3 milestone kills only (the kill counter's milestone cvar decides which).
The sweep inherits the ping's colour, so a red elite's death visibly
floods the room red.

### 3.4 Ring → ping the living (`gitd_ping_sonar`)

A ring that touches a LIVE monster pings IT: a small `BB_DEATHPING` is
attached to the monster (`AttachBillboard`, upright, `BBF_CAMERAYAW`), runs
one fast cycle and dies with it — sonar return. In a DarkDoom-black room
this is position intelligence painted by your own kills. Modes:
0 off · 1 mark (visual only) · 2 mark + wake (the return alerts the
monster — sonar works both ways, which keeps it Doom) · 3 mark + a
`GITD_SweepMark` stamped on the monster, so ANY other system (a damage
function, RS tiering) can ask "was this thing painted, and how recently"
without either side knowing the other exists.

### 3.5 Corpse-to-corpse chains (`gitd_ping_chain`)

The handler keeps a ledger of recent corpses (`gitd_ping_chain_window`
tics, default 700 ≈ 20 s). A ring that touches a ledger corpse RE-PINGS it
at link + 1: the new ping starts hotter (tint walks the tier ramp toward
red) and slightly larger/faster (`gitd_ping_chain_boost` per link). Kill a
line of imps down a corridor and the wave you started at one end hands
itself corpse to corpse to the other — light travelling through your own
violence.

Two rules keep it sane, both learned from the original's budget comments:

- a corpse relays ONCE per chain (the ledger stores the chain id it last
  served) — otherwise two adjacent corpses ping-pong forever;
- `gitd_ping_chain_links` caps total links (default 8).

### 3.6 N links → the seam opens (`gitd_ping_seam_links`)

The payoff, and the one that changes the fight. When a chain reaches N
links (default 5; 0 disables), the Nth corpse does not just ping — a
VERTICAL seam tears open above it: `GITD_Neon.Seam` upright with
`BBFL_VOID`, a dark hole with a burning rim, opened over ~20 tics by
`ResizeBillboard` (the seam shader has no progress term on purpose; the
easing is ours). Out of it, that monster COMES BACK — promoted:

- `gitd_ping_promote 0` — raised as it was (`corpse.RaiseActor`; if the
  corpse cannot be raised — gibbed, crushed — the class is spawned fresh
  at the seam).
- `1` — **a tier higher**: the ladder in `GITD_DeathPing.TierUp()` maps
  each vanilla monster to its next step (zombie→shotgunner→chaingunner,
  imp→demon, demon→cacodemon, ... baron→archvile); off the ladder's end,
  health × 1.5 and speed × 1.2 instead.
- `2` — **elite**: same class, health × 2, speed × 1.25, tinted to the
  chain's colour, and stamped with a `GITD_SweepMark` so a mod that HAS an
  elite system (RS_Main) can catch the stamp and do it properly. GITD
  standalone does the stat version; it reaches into nobody's mod.

`gitd_ping_seam_cooldown` (default 2100 tics = 60 s) keeps it an event
rather than a factory, and the seam removes itself after the delivery. The
chain that fired the seam ends there — the reveal IS its final link.

It's still Doom: the player made every link of that chain by killing, the
reveal telegraphs loudly (a minute-gated glowing tear in the air is not an
ambush), and what steps out is a Doom monster with Doom numbers.

### 3.7 The cvar roster

```
// master
server bool  gitd_ping_enabled      = true;    // every corpse pings
server bool  gitd_ping_playeronly   = false;   // true: only your kills ping
server int   gitd_ping_size         = 160;     // full reach, map units
server float gitd_ping_life         = 0.85;    // seconds per ping
server float gitd_ping_tier_scale   = 0.35;    // the original's tier term
server int   gitd_ping_echoes       = 0;       // extra fading repeats, 0-3
server int   gitd_ping_max          = 12;      // live-ping cap, oldest out
server int   gitd_ping_color_mode   = 0;       // 0 tier, 1 fixed, 2 random, 3 rainbow
server color gitd_ping_color        = "00 dc ff";
server bool  gitd_ping_ceiling      = false;   // mirror each ping on the ceiling

// the ring as a query
server bool  gitd_ping_actors       = false;   // let rings touch monsters (cost)

// ping -> sweep
server int   gitd_ping_sweep        = 0;       // 0 off, 1 every, 2 every Nth, 3 milestones
server int   gitd_ping_sweep_every  = 5;
server float gitd_ping_sweep_speed  = 600.0;
server float gitd_ping_sweep_range  = 1200.0;

// ring -> the living
server int   gitd_ping_sonar        = 0;       // 0 off, 1 mark, 2 +wake, 3 +sweepmark
server float gitd_ping_sonar_life   = 0.6;     // seconds a return rides its monster

// corpse-to-corpse
server bool  gitd_ping_chain        = false;
server int   gitd_ping_chain_links  = 8;       // hard cap on links
server int   gitd_ping_chain_window = 700;     // tics a corpse stays chainable
server float gitd_ping_chain_boost  = 0.15;    // size/speed gain per link

// the seam
server int   gitd_ping_seam_links   = 0;       // 0 off; N links fire the reveal
server int   gitd_ping_promote      = 1;       // 0 as-was, 1 tier up, 2 elite
server int   gitd_ping_seam_cooldown = 2100;   // tics between reveals
```

---

## 4. The menu — Death-Ping Options

Its own page, submenu'd from the GITD panel (the panel absorbs feature
menus; this is shaped to be absorbed). Pickers and toggles up top, the
escalation ladder in the middle in the order it escalates, sliders at the
bottom — the panel's front-page/advanced split, folded into one page since
it is one feature.

```
OptionValue "GITD_PingColorMode"
{
    0, "By Tier (toughness)"
    1, "Fixed Colour"
    2, "Random"
    3, "Rainbow"
}
OptionValue "GITD_PingSweep"
{
    0, "Off"
    1, "Every Ping"
    2, "Every Nth Ping"
    3, "Milestone Kills"
}
OptionValue "GITD_PingSonar"
{
    0, "Off"
    1, "Mark"
    2, "Mark + Wake"
    3, "Mark + Sweep-Mark"
}
OptionValue "GITD_PingPromote"
{
    0, "Back As It Was"
    1, "A Tier Higher"
    2, "Elite"
}
OptionValue "GITD_PingEchoes"
{
    0, "Off"  1, "One"  2, "Two"  3, "Three"
}
OptionValue "GITD_PingSeamLinks"
{
    0, "Off"  3, "3 Links"  5, "5 Links"  8, "8 Links"  12, "12 Links"
}

OptionMenu "GITD_DeathPingOptions"
{
    Title "DEATH-PING"
    StaticText "Every corpse pings. What the ring touches, escalates.", "DarkGray"
    StaticText " "

    StaticText "- The Ping -", "Cyan"
    Option "Death-Ping",            "gitd_ping_enabled",     "OnOff"
    Option "Only My Kills",         "gitd_ping_playeronly",  "OnOff"
    Option "Colour Mode",           "gitd_ping_color_mode",  "GITD_PingColorMode"
    ColorPicker "Fixed Colour",     "gitd_ping_color"
    Option "Echoes",                "gitd_ping_echoes",      "GITD_PingEchoes"
    Option "Ceiling Mirror",        "gitd_ping_ceiling",     "OnOff"

    StaticText " "
    StaticText "- What the Ring Does -", "Gold"
    Option "Rings Touch Monsters",  "gitd_ping_actors",      "OnOff"
    StaticText "  Needed by Sonar and Chains. Costs a little per ping.", "DarkGray"
    Option "Trigger Sweep",         "gitd_ping_sweep",       "GITD_PingSweep"
    Option "Sonar (ping the living)","gitd_ping_sonar",      "GITD_PingSonar"
    StaticText "  Wake means sonar works both ways.", "DarkGray"
    Option "Corpse Chains",         "gitd_ping_chain",       "OnOff"
    StaticText "  Rings re-ping recent corpses they reach, hotter each link.", "DarkGray"

    StaticText " "
    StaticText "- The Seam -", "Gold"
    Option "Seam Reveal At",        "gitd_ping_seam_links",  "GITD_PingSeamLinks"
    StaticText "  A chain this long tears a seam open at its last corpse...", "DarkGray"
    Option "What Comes Back",       "gitd_ping_promote",     "GITD_PingPromote"
    StaticText "  ...and that monster returns through it.", "DarkGray"

    StaticText " "
    StaticText "- Sliders -", "Cyan"
    Slider "Ping Size",             "gitd_ping_size",         64, 512, 16, 0
    Slider "Ping Life (seconds)",   "gitd_ping_life",         0.3, 3.0, 0.05, 2
    Slider "Tier Size Bonus",       "gitd_ping_tier_scale",   0.0, 1.0, 0.05, 2
    Slider "Max Live Pings",        "gitd_ping_max",          4, 32, 1, 0
    Slider "Sweep Every Nth",       "gitd_ping_sweep_every",  2, 20, 1, 0
    Slider "Sweep Speed",           "gitd_ping_sweep_speed",  200, 1200, 50, 0
    Slider "Sweep Range",           "gitd_ping_sweep_range",  400, 3000, 100, 0
    Slider "Chain Max Links",       "gitd_ping_chain_links",  2, 16, 1, 0
    Slider "Chain Window (tics)",   "gitd_ping_chain_window", 175, 1750, 35, 0
    Slider "Chain Heat Per Link",   "gitd_ping_chain_boost",  0.0, 0.5, 0.05, 2
    Slider "Seam Cooldown (tics)",  "gitd_ping_seam_cooldown", 350, 5250, 175, 0
}
```

Hook into the panel:

```
// on the GITD front page, with the other feature submenus
Submenu "Death-Ping  >>", "GITD_DeathPingOptions"
```

---

## 5. What needs the user's eye (honestly)

None of this has run. The shader maths is a mechanical transform of code
that shipped, and every equality in §2.1 is checkable by hand — but what it
LOOKS like at billboard scale is exactly the judgement that cannot be made
from here.

1. **The birth frame.** At progress 0 the band formula lights a filled dot
   (|dist − 0| < thick) that immediately opens into a ring. The original
   behaved identically, but on a fullbright billboard over GITD's own floor
   glow the first tics may read as a flash rather than a detonation. If it
   pops, the fix belongs in the DRIVER (start t at 0.05), never the shader.
2. **The end-of-life clip.** The outer gate cuts the ring at the quad edge
   as progress → 1 — at the quad's edge midpoints the band clips while the
   corners still have room. Faithful to the original's spot-radius cut, but
   whether the squarish death of the circle shows at ping sizes needs eyes.
3. **The fade curve.** The original dimmed an additive glow-channel term;
   this dims a billboard tint on the translucent path. Same numbers,
   different blend downstream — perceived brightness over the 30 tics may
   differ, and there is an alpha handle if colour-dimming alone reads wrong.
4. **Floors it lies on.** One quad is one plane: pings on stairs clip a
   step and float over the next, the known flat-billboard limit. If corpse
   pings on stairs grate, the seam-strip trick (N segments asking their own
   floor) generalises to rings only awkwardly — that would be a real
   design conversation, not a transcription.
5. **Resurrection edge cases.** `RaiseActor` against gibbed/crushed corpses
   falls back to a fresh spawn in the draft; interactions with archviles,
   respawn flags, kill-percentage counting (a promoted monster re-killed
   counts again) are all untested territory.
6. **Chain cost on slaughtermaps.** The ledger and caps are designed for
   hundreds of corpses, but the per-tic crossing tests with
   `gitd_ping_actors` on have a real cost that only a busy map will show.
7. **8-bit progress.** Progress rides a colour byte (1/255 steps), as
   WG13's does. Invisible there; a fast-sweeping ring is the harder case.
