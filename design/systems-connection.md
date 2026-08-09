# Systems Connection — the rotation mods, wired into GITD

Every claim below is from the mods' actual source, read at
`D:\SteamLibrary\steamapps\Common\DooM VR\__CurrentRotationDONOTDELETE\testfile\`,
and from our own trees (`E:\GlowInTheDark`, `E:\UZDXREMA`, `E:\RS_Main`).
Where a mod's documentation and its code disagree, the code won.

Design law honoured throughout (not relitigated here):

- Damnums **coexists** — it sprays per-hit numbers, we keep the cumulative
  combo. Both-stacked: pause resets the running combo, death pops the
  lifetime total as a wgType-13 badge.
- Colour rules for numbers and monsters are settled; existing cvars are
  reused, never redesigned.
- Everything below is an **option**, cvar-gated, off by default unless noted.
- Waves ride game tics; a bullet-time behaviour option exists (§7).
- No perf budget. It's still Doom.
- Not reinventing the wheel: every integration below rides the machinery we
  already have — the wave list, `GITD_SweepEffect`/`GITD_SweepAction`,
  `GITD_Composite`, `GITD_Neon`, billboards. Nothing grows a parallel system.

---

## 0. The probe idioms — graceful presence and absence

The user sideloads SOME combination of these mods. Nothing may hard-reference
a foreign class, and nothing may care whether a mod is missing. Three idioms
cover every case in this document:

```zscript
// 1. Does a class exist at all?  (runtime name->class, null when missing)
class<Actor> cls = "PostTickDummyController";
if (cls) { ... }

// 2. Is THIS actor one of / carrying one of theirs?
//    `is "Name"` and CountInv("Name") are name-resolved at runtime and are
//    simply false / 0 when the mod is absent. No compile-time dependency.
if (mo is "HookShot") { ... }
if (mo.CountInv("minibossinfo") > 0) { ... }

// 3. Is their handler live?
if (EventHandler.Find("AIDirector")) { ... }
```

What we can NEVER do cross-mod: read a **field** of a foreign class
(`Shifter.size`, `minibosscontroller.minibosscolor`, `BulletTime.btActive`).
ZScript has no field reflection. Every integration below is therefore built
on what IS observable: inventory tokens by name, actor class names, scale
and health ratios, `fillcolor` (SetShade writes it), cvars, and net events —
which broadcast to every handler, including ours.

One shared piece of infrastructure serves several sections, so it is named
once: **`GITD_Probe`**, a tiny static class caching the class-exists checks
once per map (`GITD_Probe.HasEntropy()`, `HasMinibosses()`, `HasCrits()`,
`HasDamnums()`, `HasBulletTime()`, `HasGrapple()`, `HasSoftPD()`,
`HasCrazyColors()`, `HasTexLights()`, `HasRS()`). Rebuilt in WorldLoaded like
everything else we own.

---

## 1. Universal Entropy — tiers as a colour language

### What it actually does (randomise.zs, 167 lines)

`UE_randomisation_EventHandler.WorldThingSpawned`: every non-friendly monster
rolls `size1`, `size2` around a mean set by `ue_bias`/`ue_rr`. If the resize
roll passes (`ue_resize` in 5 chances): `A_SetSize`, then **Health, Mass,
Scale, PainChance, MeleeRange, PushFactor, Damage, DamageMultiply are all
scaled** by functions of the size. The monster is handed a `Shifter`
inventory item whose `size` field drives sound pitch and state-tic scaling
(big = slow, small = fast). A separate roll (`ue_recolour`) gives a random
256-entry palette translation. Items/ammo/armour scale similarly; enemy
missiles get randomised spread and inherit the shooter's size.

### Hook surface

- Cvars: `ue_rr`, `ue_rp`, `ue_bias`, `ue_resize`, `ue_recolour`,
  `ue_colour_v/b/t`, `ue_decor_*`, `ue_ammo`, `ue_healthkit`, `ue_armour`,
  `ue_friend`.
- Classes: `UE_randomisation_EventHandler`, `Shifter` (inventory, on every
  randomised actor), `ColorTranslationWrapper`.
- **The readable signal**: `Shifter.size` itself is unreadable, but UE writes
  it into public actor state: `a.Scale.X / a.default.Scale.X == size1`, and
  `a.Mass / a.default.Mass ≈ size`. Either recovers the roll without touching
  the foreign class.

### The tier→colour language: `GITD_EntropyTier`

There is no explicit tier in UE — the tier IS the size roll. We make it a
language:

```zscript
class GITD_EntropyTier
{
    // 0 runt, 1 lesser, 2 standard, 3 greater, 4 giant.  -1 = untouched.
    static int Of(Actor a)
    {
        if (!a || a.CountInv("Shifter") == 0) return -1;
        double r = (a.default.Scale.X != 0) ? a.Scale.X / a.default.Scale.X : 1.0;
        if (r < 0.70) return 0;
        if (r < 0.90) return 1;
        if (r < 1.10) return 2;
        if (r < 1.35) return 3;
        return 4;
    }
    // Colour ramp deliberately mirrors RS_TierPalette's loot ladder
    // (white -> green -> blue -> purple -> gold) so a player who reads one
    // system already reads the other. When RS_Main is loaded its table is
    // the authority; this is the standalone fallback with the same hues.
    static Color RGB(int tier);
}
```

### Integrations

1. **Tier-coloured combo numbers.** `GITD_NeonKillCounter.WorldThingDamaged`
   already takes an optional colour; pass `GITD_EntropyTier.RGB(tier)` when
   `tier >= 0` — a giant's climbing total reads gold, a runt's reads white.
   Cvar: `gitd_neon_tiercolor` (bool, off = settled colour rules untouched).
2. **Tier-coloured sweep marks.** Sweep fx 6 (mark) already exists; a new
   listener `GITD_TierPing : GITD_SweepEffect` (`WantsActors` true) recolours
   each monster's brief glow/badge on band contact by tier — the sonar wave
   becomes a threat readout: the room answers the ping in colour.
   Cvar: `gitd_ss_tierping`.
3. **Death badge size follows tier.** The WG13 kill badge already has a
   `big` variant (milestones). Tier 4 kills use it too; tier 0 kills shrink.
   One line in `WorldThingDied`; cvar-gated by the same `gitd_neon_tiercolor`.
4. **Patchbay trigger `giant_down`** (§12): tier-4 death fires a wave slot —
   the room reacts to a big kill without RS or Minibosses present.

---

## 2. Minibosses — the kernel, not the bloat

### What it actually does (minibosshandler/controller/fx, ~750 lines)

- `minibosshandler` (StaticEventHandler): for the **first 2 tics** of a map
  (`bossifytimer`), each qualifying monster spawn rolls `mbos_spawnrate`% to
  be promoted: pushed to a list and given the `minibossinfo` inventory token.
  At tic 0 the handler gathers nearby monsters (BlockThingsIterator, radius =
  spawn health clamped 64..2048), ties up to `spawnHealth/20` (max 50) of
  them as **thralls** (`minibossthrallinfo` token), and creates a
  `minibosscontroller` **thinker** per boss.
- `minibosscontroller`: gives the boss `bBUDDHA`; at health 1 it refills to
  spawn health, decrements `lives` (`mbos_lives`, default 3), and runs an
  invulnerability window (`bNODAMAGE + bALWAYSFAST + bNOBLOOD`, duration
  `mbos_invulnlength + thralls*mbos_invulnbonus` seconds) with flag
  save/restore bookkeeping. Living thralls give the boss up to 80% damage
  resistance (`DamageFactor = 1 - 0.8 * living/total`). Death runs a
  15-tic explosion shower.
- The visuals are the bloat: per boss, `lives+1` orbiting `minibosslifefx`
  actors warped every tic; during invulnerability `mbos_invulndensity`
  (default **20**) more orbiting actors; per thrall one marker actor plus
  `mbos_thralldensity` (default **30**) trail actors warped every tic along
  the boss→thrall line. A 10-thrall boss is ~340 actors being warped 35
  times a second, for decoration.
- **mbosnams.txt is dead code, by its own admission.** The lump literally
  reads "this feature isn't being used right now". `buildnamelist()` is
  commented out of WorldLoaded, the name is hardcoded to a joke string, and
  even `a.SetTag(minibossname)` is commented. There are no announcements to
  hook — **detection is the `minibossinfo` token, nothing else.**

### The kernel worth keeping (user ruling: concept source, not dependency)

1. Promotion at spawn — an ordinary monster, made singular.
2. Lives with invulnerability breathers — a boss fight in phases.
3. The thrall link — "kill the guards to hurt the captain."
4. An unmissable "this one is special" mark.

The names/announcement idea existed and was abandoned; it is the part GITD
is uniquely equipped to do properly.

### Integrations when the mod IS loaded (wrap, zero bloat inherited)

1. **Captain announcement wave.** One-shot scan at tic 4 (their promotion
   completes at tic 2) for monsters with `minibossinfo`:
   `GITD_Sweep.FireFrom(boss, SHAPE_RING, col, 700, 1600, priority: 20)`.
   The colour is theirs, recovered without touching their classes: the
   controller `SetShade`s its `minibosslifefx` orbiters with the boss's
   random colour, and SetShade writes public `fillcolor` — find the nearest
   `minibosslifefx` (`a is "minibosslifefx"`) and read `a.fillcolor`.
   Cvar: `gitd_captain_announce`.
2. **Life-lost wave.** Their life-loss moment is observable: a boss at
   full health that was at 1 last tic, or cleaner — the invuln orbiters
   appearing (`minibossinvulnfx` actors near a `minibossinfo` carrier).
   A `GITD_CaptainWatch` WorldTick (only when `GITD_Probe.HasMinibosses()`)
   fires a **collapsing** ring inward onto the boss per life lost: the room
   counts his lives down for you. Cvar: `gitd_captain_lifewaves`.
3. **Captain badge.** `GITD_Neon.Above(boss, "CAPTAIN", theirColour)` — or a
   name, see below — riding the monster, dying with it. No actor spawned.
4. **Death pops the badge.** Their death already satisfies our combo tracker
   (§5) — the lifetime-total WG13 pop simply inherits the captain's colour.

### The lean GITD-native captain layer (replacement option)

`gitd_captains` (off / wrap-if-present / native). Native mode is ~200 lines
against machinery that already exists, and replaces the mod outright:

- **Promotion**: WorldThingSpawned in the first 2 tics, `gitd_captain_odds`%,
  token `GITD_CaptainMark : Inventory` (mirrors their qualifying filter:
  ISMONSTER + COUNTKILL + !FRIENDLY + health > 10).
- **Lives**: reuse *their* good idea with *our* fixed mechanism — not
  bBUDDHA/health==1 (the misfire RS_ScoreRevival documents, §8), but an
  `AbsorbDamage` tail item: `damage >= owner.health` → refill, life--, brief
  `bNODAMAGE` window. ~40 lines, engine-verified technique (RS_ScoreRevival
  header cites p_interaction.cpp:1350).
- **The mark**: one attached billboard instead of 340 actors —
  `level.AttachBillboard(boss, (0,0,Height+14), w, h, 0, 0, BBF_CAMERAYAW,
  LevelLocals.BB_RING, livesLeft, col, ...)`. BB_RING with `data` = lives
  gives orbit-pip readout for free; `UpdateBillboard` on each life lost.
  Zero thinker cost, our glow, our colour rules.
- **Names**: resurrect the abandoned mbosnams idea properly — a GITD lump
  `captnams.txt`, one name per line, `GITD_Neon.Above(boss, name)` in a
  rolled arcade font (`SetBillboardFont`), announced by the wave. This is
  the part of their design that was "conceptually cool" and never shipped.
- **Announcement/death**: the same waves as the wrap mode — one code path.
- Thralls: **deliberately not replicated** in v1. It is the best gameplay
  idea in the mod but also its whole actor-spam budget; if the user wants
  it, a thrall is a `GITD_CaptainMark` field plus a `BB_SEAM` billboard laid
  boss→thrall (our seam already draws a glowing line), not 30 trail actors.

---

## 3. AI Director — a mood our weather can wear

### What it actually does (ZScript.txt, 275 lines — not what the name implies)

It is a spawn recycler, not an L4D pacing brain. At `level.time == 0` it
records every monster (and optionally item) as a spawn point + class-name
roster entry, **destroys the originals**, then: an initial seeding pass
(`aid_startspawns`% per point), and from then on a continual loop — every
`timer` tics pick a hidden spawn point near a player (`aid_mindistance` to
`aid_maxdistance`, ahead of travel unless `aid_bootysnatchers`, never in
line of sight), spawn a group of 1..`aid_maxgroupsize` **scaled by
`HealthFactor()`** (player health+armour /100). `timer` is reset to
`groupsize * aid_spawnrate * 35` and — the one genuinely director-ish touch —
with `aid_softenspawns` on, the timer only counts down at a rate
proportional to player health: hurt players get silence, healthy players
get pressure.

### Hook surface

- Cvars: all `aid_*` (readable; `aid_enabled`, `aid_spawnrate`,
  `aid_maxgroupsize`, `aid_softenspawns` are the useful ones).
- Classes: `AIDirector` (EventHandler — `EventHandler.Find("AIDirector")`),
  `AIDSpawnPoint` / `AIDMonsterSpawnPoint` / `AIDItemSpawnPoint` (real
  actors, iterable by name).
- **Not readable**: `timer`, the internal countdown. Pacing must be inferred
  from observables.

### `GITD_Pacing` — the inferred mood (shared with the Reactive page)

The Reactive lane needs the same source, so this is the one implementation
both pages read. A StaticEventHandler tracking, over a rolling 10-second
window: monsters spawned at `level.time > 0` (the director's signature —
vanilla maps almost never do this; Pain Elemental souls are filtered by
`a is "LostSoul"`), player damage taken, kills scored, and live monster
census. Three states, hysteresis on the transitions:

- **CALM** — no director spawns in the window, low damage.
- **BUILDUP** — spawns detected, contact light.
- **ASSAULT** — sustained spawns + damage + rising census.

When the director is absent the same states fall out of ordinary monster
census and damage flow, so the source works standalone — presence of
`AIDirector` just sharpens it (its spawn bursts are unambiguous).

### Integrations

1. **The ambient wave wears the mood.** `gitd_ss_pacing` (off/on): CALM =
   slow outward ring (weather), BUILDUP = speed ×1.5 and the wake stretches
   (`SetSweepTrail` already plumbed), ASSAULT = **collapsing countdown** —
   direction flips inward, speed ×2, colour slides toward the hot end of the
   band's own colour (`GITD_Palette.Scale/Saturate`, no new colour cvars).
   Implementation is three multipliers inside `RefreshAmbient()`; the wave
   object doesn't know moods exist.
2. **Spawn-burst announcement.** Patchbay trigger `director_burst`: the tick
   a burst is detected, fire the bound wave from the burst's centroid — the
   lights tell you the flank is coming from behind-left before the audio does.
3. **Sonar auto-arm.** In ASSAULT, if the ambient wave's fx is sonar, halve
   `gitd_ss_sonar_fade` — rooms go dark faster behind the band; the reveal
   becomes something you have to keep earning exactly when it matters.
   Cvar: `gitd_ss_pacing_sonar`.
4. **Director census for the Reactive page**: `GITD_Pacing.State()`,
   `GITD_Pacing.SpawnRate()` exported as the `director` source (§12 table).

---

## 4. mk-crits — crits feed the combo flare

### What it actually does (core.txt/handler.txt, ~400 lines)

Every monster spawn receives two inventory items: `csh_Brain` and
`csh_critController`. `csh_Brain.ModifyDamage` (passive) implements three
mechanics: **criticals** — when the controller judges the monster mid-attack
(`canStun`), incoming player damage stuns (tics = -1, forced Pain state,
~50 tics) and multiplies by `csh_critical_factor`; **headshots** — inflictor
Z within the top `headshot_height` fraction of the monster's height →
damage ×`csh_headshot_factor_h/p`, **DamageType rewritten to 'HeadShot'**
(`'SSGGib'` kept for DoomXP compat); **backstabs** — melee from behind →
×`csh_backstab_factor`. Stunned monsters take `csh_critical_factor_r`
bonus damage. Anti-cheese stacks: `csh_CriticalDelayer`,
`csh_HeadshotDelayer`, `csh_JustStunned`, `csh_JustAttacked` tokens.

### Hook surface (all observable without their classes)

- `WorldThingDamaged` sees `e.DamageType == 'HeadShot'` — headshots are
  free to detect.
- `mo.CountInv("csh_JustStunned")` / `CountInv("csh_JustAttacked")` — a crit
  or backstab landed this instant. `csh_critController` present = mod live.
- Cvars: all `csh_*`.

### Integrations

1. **Combo flare.** In the combo tracker (§5), a hit with
   `e.DamageType == 'HeadShot'` (or `CountInv("csh_JustStunned")` freshly
   > 0) flares the attached billboard: `SetBillboardGlow(id, 1.0, 1.0)` for
   6 tics then back to menu values, plus `SetBillboardGradient(id, white)`
   for the same window. The number itself doesn't change — the *display*
   spikes. Cvar: `gitd_neon_critflare`.
2. **Crit pop rides Damnums' lane.** Damnums already colours 'HeadShot'
   damage via its typecolor table — that's theirs. Ours is the running
   total; the flare is the only crit-specific thing we add. (Coexistence
   honoured: no second per-hit number.)
3. **Patchbay trigger `crit`.** A headshot/backstab fires a bound wave slot
   from the victim (a fast, thin, white ring, 300 u — a visual "dink").
   With a chaingun this would spam, so the trigger has a per-slot cooldown
   field (`gitd_wsN_cooldown`, default 10 tics) — the same edge-vs-stream
   reasoning as the existing trigger-pull edge.
4. **Stun = slow-motion mark.** A stunned monster (`csh_JustStunned`) gets
   `GITD_SweepMark.Set(mo, 7, 1.0)` — anything already listening to marks
   (setpieces, RS re-tierers) sees crit-stuns with zero extra plumbing.

---

## 5. Damnums + the both-stacked combo tracker (full design)

### What Damnums actually does (events.txt/damnum.txt, ~380 lines)

Two modes. `dam_spray` on: `WorldThingDamaged` spawns numbers per hit.
Default (spray off): every monster gets a `DamNumKeeper` **thinker** watching
`health` deltas per tic, plus a `DamNumCourier` inventory whose `OwnerDied`
flushes the final number — so one number per tic of damage, coalesced.
Each digit is a **separate Actor** (`DamNum`, +NOINTERACTION +CLIENTSIDEONLY,
tossed with gravity or floated, faded out). Sprite fonts, damage-type
colour translations (`dam_usetypes`, LANGUAGE-driven), `dam_shootable`
extends to barrels.

**Division of labour (settled, restated):** Damnums = the instantaneous
event, sprayed and physical. GITD = the accumulated state, glowing and
attached. They answer different questions and never collide — theirs are
actors near the wound; ours is one billboard riding the monster.

### The ledger — `GITD_ComboLedger`

The current accumulator in `GITD_NeonKillCounter` (parallel arrays
`dtar/dtotal/dbb/dlast`) is 80% of the design; this completes it. Per
monster currently being fought, one row:

```
Actor  who        — the monster (null = row dead)
int    combo      — running total since the last quiet gap
int    lifetime   — total ever dealt to this monster (never resets)
int    bb         — attached billboard handle (0 = none showing)
int    lastHit    — maptime of most recent hit
int    flare      — tics of crit-flare remaining (§4)
Color  col        — resolved once per burst: tier colour (§1) or menu colour
```

Behaviour, event by event:

- **WorldThingDamaged** (player-sourced, monster victim, damage > 0):
  find/create row. `combo += damage; lifetime += damage; lastHit = now`.
  No billboard yet? `GITD_Neon.Above(who, text, col)` — attached, so it
  rides the monster and dies with it, **no actor per number** (billboards
  are level-owned pictures; the whole reason the engine grew them).
  Else `SetBillboardText` / `UpdateBillboard` (WG13 carries the number in
  `data`, text styles in `text` — the existing `IsWG13()` fork) and
  `ResizeBillboard` to the new digit count (`BadgeSize`).
- **WorldTick**: rows whose `now - lastHit > gitd_neon_dmg_window` go
  quiet: **combo resets to 0 and the billboard is removed** — but the row
  survives (lifetime is still accruing history) until the monster dies or
  the map ends. This is the "pause breaks the combo" half of both-stacked.
  A row whose monster is gone without dying through us (Thing_Remove) is
  dropped. Flare counts down here.
- **WorldThingDied** (the monster has a row): the "death pops the total"
  half. Spawn the WG13 badge exactly as the kill counter does (`Spawn13`
  path: open 12 tics, hold, close 14 — or linger per `gitd_neon_kc_linger`),
  but `data = lifetime`, colour = row colour, placement per
  `gitd_neon_kc_place` (ground badge fits floor clearance, overhead pops
  above the corpse). Row deleted. The kill-counter badge (count of kills)
  and the lifetime badge would fight for the same spot when both are on;
  when both are enabled the lifetime badge takes the corpse and the kill
  count takes its next milestone — never two badges for one kill (the
  existing either-never-both rule, extended).

Cvars (existing ones keep their meanings): `gitd_neon_damage` (master),
`gitd_neon_dmg_window` (the pause), `gitd_neon_dmg_mode` (0 per-hit pops —
redundant with Damnums loaded, still valid standalone), new
`gitd_neon_dmg_deathpop` (bool: pop lifetime on death), new
`gitd_neon_critflare` (§4), new `gitd_neon_tiercolor` (§1).

Costs: one array walk per damage event (rows live ≈ monsters currently
being fought, a handful), one billboard per fought monster, zero thinkers,
zero actors. The whole tracker is an extension of code that already ships.

---

## 6. Bullet-time-x — how it actually dilates, and the wave option

### What it actually does (BulletTime.zs 1328 lines + PostTickDummyController)

**It never touches the tic rate.** The playsim runs at full 35 Hz
throughout; `level.maptime` advances normally. "Slow motion" is manufactured
per object, every tic:

- Monsters/projectiles: state `tics` multiplied by `btMultiplier`,
  velocities divided (with elaborate external-force reconstruction so
  rockets still shove things), powerup `EffectTics` stretched, sound pitch
  dropped. Bookkeeping via a `BtItemData` inventory on every actor.
- Players: separate, gentler multipliers (`bt_player_movement_multiplier`,
  weapon psprite tics via `bt_player_weapon_speed_multiplier`) — the
  asymmetry IS the power fantasy.
- Sectors: light effects, movers and scrollers are paused/stepped by
  juggling their thinkers between `STAT_STATIC` and live, from a
  `PostTickDummyController` actor (statnum 126) that runs after everything
  and self-destroys when slow ends.
- `bt_multiplier == 0` = full freeze: the activator gets `BtTimeFreeze`,
  a duration-less `PowerTimeFreezer` — engine-level `level.isFrozen()`.
- Fuel: `BtAdrenaline` inventory, earned from kills (health-scaled) and
  damage taken, spent while active; berserk pickups force it full.
- Activation: **net events `"bt_activate"` / `"bt_activate_dodge"`**
  (KEYCONF binds), or automatic on dodge-jump; deactivation automatic on
  fuel-out/landing/death.

### The honest finding

Our waves already "ride game tics" — `GITD_Wave.Step()` runs in WorldTick —
**and that is exactly why they do NOT dilate**: WorldTick keeps its 35 Hz
during bullet time, so a wave crosses a slowed room at real-time speed.
Whether that is a bug or the best effect in the mod is a taste question,
which is why it is the option the design law ordered:

`gitd_ss_timescale`:
- **0 — world time (default)**: waves divide their step by the sensed
  dilation and crawl with the monsters. The band in slow motion, VR bullet
  visible in the wavefront.
- **1 — real time**: current behaviour, kept deliberately. The room's
  nervous system keeps its own clock while everything else wades — the
  waves become the one thing bullet time cannot slow, which reads as the
  world *watching you*.

Freeze (`level.isFrozen()`) is respected unconditionally in `Step()` —
that's correctness, not an option, and it also fixes us under vanilla
TimeFreezer spheres. (Minibosses' controller does the same check; we
currently don't.)

### `GITD_TimeSense` — sensing the dilation without their classes

```zscript
class GITD_TimeSense
{
    // 1.0 = normal. Sampled once per tic by the handler.
    static double Dilation()
    {
        if (level.isFrozen()) return 0.0;          // hold everything
        if (!GITD_Probe.HasBulletTime()) return 1.0;
        // The controller actor EXISTS exactly while slow is applied --
        // it self-destroys the tic after applySlow goes false.
        bool active = false;
        ThinkerIterator it = ThinkerIterator.Create("Actor", 126); // their statnum
        Actor a;
        while (a = Actor(it.Next()))
            if (a is "PostTickDummyController") { active = true; break; }
        if (!active) return 1.0;
        // Which multiplier is live (base/dodge/berserk) is not readable;
        // bt_multiplier is the honest approximation and the player's own
        // setting. 0 means freeze mode and is handled by BtTimeFreeze ->
        // level.isFrozen() above.
        int m = CVar.FindCVar("bt_multiplier").GetInt();
        return max(m, 1);
    }
}
```

`Step()` becomes `pos += dir * speed / 35.0 / dil` (dil==0 → return).
Driven waves (`drive` = kills/health) ignore dilation — their position is a
readout, not a clock. We also hear their **`bt_activate` net event** in our
own `NetworkProcess` for free, which gives the patchbay its `bt_start` /
`bt_end` triggers (edge = controller appearing/disappearing, the netevent
alone can't tell a start from a failed start).

### Integrations

1. The `gitd_ss_timescale` option above.
2. **Patchbay triggers `bt_start` / `bt_end`**: bind a wave to the moment —
   the obvious one is a single expanding shell (shape 4) from the player in
   ice-blue as time collapses, and its inward twin on release.
3. **Sonar in frozen time.** With dilation 0, sonar decay (`sonarGlow`
   fade) also holds — revealed rooms stay revealed while frozen, releasing
   together. One `dil == 0` early-out in the decay loop; it reads as time
   itself holding its breath.
4. **Adrenaline as a Reactive source** (their fuel gauge is readable:
   `player.CountInv("BtAdrenaline")`, 0..525) — exported to the shared
   source list (§12) as `bt_fuel`; the Reactive lane can run lane
   brightness off it.

---

## 7. Jetpack (jp_1) + Grapple (jp_2) — sweep origins that move

### What they actually do (ACS)

- **jp_1_main**: hover — holding jump mid-air thrusts while `sv_hovertime`
  fuel lasts; `sv_maxjumps` extra air-jumps; `sv_shotgunstart`. Pure ACS on
  `GetPlayerInput`, no classes to probe; cvars `sv_hovertime`,
  `sv_maxjumps`, `cl_hover_*` are the presence signal.
- **jp_2_grapple**: `sv_allowhookshot` + BT_USER1 edge fires a `HookShot`
  FastProjectile (Speed 40, range-limited by state duration). On wall hit
  (`Death` state → script "Hook_HitWall"): **the player is thrust toward
  the hook point** (distance/12 per axis). On flesh hit (`XDeath` →
  "Hook_HitEnemy"): **the victim is pulled to the player**. Classes:
  `HookShot`, `HookShooter` — both probeable by name.

### Integrations

1. **Grapple-point wave.** `WorldThingDied` doesn't fire for puffs, but the
   HookShot is an actor we can watch: a `GITD_GrappleWatch` WorldTick scans
   for `a is "HookShot"` entering its Death/XDeath frames — cheaper and
   simpler: on *first sight* of a HookShot remember it, and the tic it
   despawns fire the bound wave from its last known position. That position
   is the anchor you are about to fly to — a ring blooming from where
   you're going, not where you are. Patchbay trigger: `grapple_hit`.
2. **Pull direction paints the wake.** The wave fired at a flesh hit uses
   direction inward (victim comes to you); at a wall hit, outward (you go
   to it). Same trigger, `gitd_wsN_dir` honours "event decides" as a mode.
3. **Jetpack hover = rising wave.** While hovering (player airborne,
   +jump held, `sv_hovertime` cvar exists), the patchbay's `jetpack_hover`
   trigger keeps a SHAPE_RISING (5) wave alive under the player — origin
   at liftoff Z, signed radius climbing with them: thruster wash climbing
   the walls. Released on landing. This is the one trigger that sustains a
   wave rather than firing one; the slot's wave is tagged and `Cancel`led
   on trigger-false — machinery that already exists.
4. **Air-time as a Reactive source** (`airborne`, seconds off the ground) —
   trivial to compute, shared with the sibling page.

---

## 8. SoftPermaDeath — read, then broken apart

### What it actually does (spdead.txt ACS + decorate, ~440 lines)

ENTER script stores the player's spawn position, spawns a `RespawnPoint`
MapSpot (TID 666999), and loops forever: keep `PowerBuddha` on the player
(via `NighInvulnerability`, duration 0x7FFFFFFF) while lives
(`OneUp` inventory, max 30) remain; when **health == 1** (Buddha floors
lethal damage at 1), count a death, apply skill-scaled punishment health
(`Punishment1..5` cvars), take a OneUp, optionally drop a pickupable
`ExtraLife` ankh where you "died" (TID 667000, previous one erased), and
teleport you back to the start. Global ACS vars carry deaths across maps;
rewards grant lives for deathless levels (`LevelsUntilReward`) or for
being broke (`RewardForNo1Ups`). BIGFONT HudMessage shows the count.

Weaknesses, from the code: the health==1 test bills *any* arrival at 1 hp
as a death (the exact bug RS_ScoreRevival documents and fixes); permanent
Buddha changes every fight; hardcoded TIDs; a HUD message where the user's
aesthetic is in-world; ACS globals where handlers now serve.

**Context that changes the assignment**: the user already hacked this mod
into a lives system with a "column of flame" — and that evolution now
*exists as real code* in RS_Main: `RS_ScoreLives` (the economy: lives
earned from damage taken/dealt, level clears, bosses, score, sprees) and
`RS_ScoreRevival` (the payload: an AbsorbDamage tail item that catches the
would-be-killing blow, and the fire cone — eight flame streams thrown
outward and eight raked along the floor from a spinning emitter, every
dimension a cvar, explicitly "survives every rewrite"). The rewrite must
serve that system, not compete with it.

### The break-apart (design: `GITD_Lives`, four parts, each optional)

1. **`GITD_DeathSave`** — the mechanism, done right: an inventory item at
   the tail of the chain overriding `AbsorbDamage`; `damage >= health` is
   the death test (RS technique, engine-verified at p_interaction.cpp:1350;
   DMG_FORCED/telefrag honestly excepted). No Buddha, no health==1 misfire.
   *Skipped entirely when RS is loaded* (`GITD_Probe.HasRS()` →
   `ClassExists("RS_LifeForce")`): RS owns the save.
2. **`GITD_LivesLedger`** — SoftPermaDeath's economy, kept but translated:
   `gitd_lives_start`, `gitd_lives_punish` (skill-scaled respawn health, the
   Punishment1..5 idea as one curve cvar), `gitd_lives_reward_level`,
   `gitd_lives_reward_broke` — a StaticEventHandler so the count survives
   the exit line. *Deferred to RS_ScoreLives when present* — two ledgers
   double-granting is the classic stacking bug.
3. **`GITD_DeathRitual`** — the part that is genuinely ours and runs in
   BOTH configurations (standalone or over RS): when a life is spent —
   observed directly in standalone mode; observed under RS by watching the
   revival fire cone begin (`ClassExists` probe on the emitter class +
   proximity, or simply damage-that-should-have-killed followed by
   survival) — the world reacts:
   - a white **collapsing shell** onto the player (`FireFrom(pmo, SHAPE_SHELL,
     white, 900, 1200, dir inward, priority 30)`) arriving as the flame
     column erupts — the room takes a breath in, the fire answers out;
   - `GITD_Neon.Pop` of the remaining lives over the player in WG13 (the
     lozenge opening on "02" *is* the arcade continue screen);
   - optional blackout-and-sonar: 20 tics of `GITD_Composite.OverrideLight`
     to near-black then a sonar reveal outward — death costs you the room
     and the ritual gives it back. All under `gitd_lives_ritual`.
4. **`GITD_RespawnRitual`** — SoftPermaDeath's teleport-to-start, kept as
   an *option* (`gitd_lives_teleport`, off by default since the flame
   column implies dying in place), and delivered as a `GITD_Setpiece` so
   the journey back is a wave: sweep the corridor dark behind you to the
   anchor, restore as it passes. Journaled, reversible, already the
   machinery setpieces have.

The mod itself is then fully superseded — every behaviour it had exists as
a named, separable option, minus its bugs, plus presentation.

---

## 9. Crazy Colors — a fight for the same sectors, settled

### What it actually does (ZSCRIPT + ZS_DOOM etc., ~3800 lines)

A `CrazyColors` control actor with speed-named states
(`Delay_VeryFast`..`Delay_VerySlow`, `Return_To_Normal`) calls
`RandomColorSectors()`: **every sector** gets `SetColor(random 24-bit,
desat 0.75-0.95)` and `SetLightLevel(random 172..232)` on a random cadence.
It snapshots original light levels at PostBeginPlay for the restore path.
The per-game files (ZS_DOOM etc.) replace the player and monsters with
subclasses that shed **stencil-coloured trail afterimages**
(`NewDoomPlayer_Trail` and kin, colour driven by ACS cvar via
`Get_TrippyTrails_Type` — player colour, fixed hues, or random). KEYCONF
binds puke scripts in compiled `CRAZYCOL.lmp` to switch modes.

### The collision, stated honestly

`GITD_Composite` **rewrites every sector's colour every tic** from its
load-time snapshot (that is its entire design). Crazy Colors writes sector
colours on a multi-tic cadence. With both loaded, whichever ticks later
wins for that tic, and since the compositor writes *every* tic, **Crazy
Colors' sector flashing is effectively erased while GITD runs** — its
SetLightLevel calls likewise fight the compositor's held/released logic and
DarkDoomZ's darkness. This is exactly the last-writer-wins disease
SectorComposite.zs was built to kill, arriving from outside.

### Integrations

1. **Chaos as a composite channel.** `gitd_chaos` (off/slow/normal/fast/
   veryfast): GITD generates the same effect *inside* the pipeline — per
   cadence tick, roll a random tint per sector and declare it via
   `GITD_Composite.Tint(idx, c)` + `Desaturate`, republished each tic until
   the next roll. Because it is a tint, it **composes**: chaos over
   DarkDoomZ is dark chaos; chaos under a setpiece's red is red-shifted
   chaos; the sweep still reads. When `GITD_Probe.HasCrazyColors()` and the
   user turns `gitd_chaos` on, we are the implementation and their sector
   pass is harmlessly overwritten; their trails — which don't touch sectors
   — keep working untouched and look *better* in our darkness (stencil
   trails against DarkDoomZ black).
2. **Chaos follows the wavefront.** The variant only we can do: chaos as a
   per-band effect (`FX_CHAOS = 8` in the EFx table) — sectors the band is
   crossing roll random tints at full strength, decaying behind the wake.
   A travelling seam of broken colour instead of a global strobe. This is
   the "Crazy Colors × our palette" answer: their idea, aimed.
3. **Trail hue handshake (small).** Their trail colour mode reads a cvar;
   mode "player colour" already matches whatever we do. Nothing to build —
   noted so nobody builds it.
4. **Preset guard.** `gitd_chaos` > off forces preset colour work to skip
   (a chaos room with the Ember preset fighting it reads as noise on
   noise); one early-out in the lane step, mirroring how Sector Sweep
   already takes over from lanes.

---

## 10. TextureLights, BigDoom, Graveyard — the environment set

### TextureLights_Extreme — what it actually is

Two wads. `texture_lights.wad` is Marisa Kirisame's texture-light spawner:
a ZScript `LightTextureHandler` reads an `LTEXDEFS` lump (texture name →
hotspot x/y, RGB, radius, spot flags) and **spawns real
`PointLightAttenuated` / `SpotLightAttenuated` actors** at every matching
texture hotspot on walls and flats at map load. Static, no animation
(the source says so itself). `lights2.wad` is a conventional GLDEFS pack
for object lights. So after load, every lamp texture in the map has a
dynamic-light actor sitting on it — **hundreds of iterable, positioned,
coloured "fixtures".**

### Integrations (× our glow lanes and waves)

1. **Fixture surge — the wave lights the lamps.** New per-band effect
   `FX_FIXTURES = 9`: during the actor pass (the fixtures are actors —
   the existing `WantsActors` walk picks them up with one class-name check),
   a band crossing a `PointLightAttenuated` bumps its radius arg ×2 and
   eases it back over ~20 tics — every lamp the wavefront passes flares and
   settles. Dynamic light actor args (`args[LIGHT_RED..LIGHT_INTENSITY]`)
   are writable at runtime; journal original values the first time we touch
   one, restore on wave end (the setpiece journal pattern, minus the
   setpiece). The sweep stops being the only light that moves — it plays
   the room's own lamps like keys. Cvar: `gitd_ss_fixtures`.
2. **Fixture census for DarkDoomZ.** `gitd_dd_fixturefloor`: sectors
   containing a fixture get a slightly higher darkness floor via
   `GITD_Composite.AddLight` — lamps keep a pool of glow in deep darkness,
   which is both readable navigation and exactly what texlights are for.
   One census pass at map load (they're static), a per-sector bool.
3. **Lane yield near fixtures** (needs the small engine native, §13.C, or
   the census above as approximation): flats that carry their own light
   hotspots skip the fg/cg lane recolour so a genuine lamp face is never
   repainted by an animation. Approximation without engine work: skip
   sectors from the census in integration 2.
4. **BigDoom** (LevelPostProcessor scaling all geometry ×2 with vertex
   clamps): no code needed, one *correctness note that must be honoured*:
   anything of ours derived from map extent already self-adjusts
   (`ComputeMapCentre` reads scaled sectors), but fixed-distance defaults
   (`gitd_ss_range` 2048, flashlight `fl_range` 1024) read half as far in a
   doubled map. Patchbay slots therefore take range as a *fraction of map
   diagonal* option (`gitd_wsN_range` = 0 → "fit the map": diagonal × 0.6),
   computed from the same min/max pass ComputeMapCentre already does.
5. **Graveyard** (m8f's persistent cross-session gravestones at player
   death spots, stored in `gy_hashes/gy_locations/gy_obituaries` cvars,
   spawned via `gy_spawn*` net events): one integration, cheap and worth
   it — `gitd_graveyard_glow`: at map load, for each `gy_Stone*` actor
   (probeable by name), lay a small permanent floor `GITD_Neon.Mark` under
   it — "HERE LIES" in a rolled arcade face, or just a neon seam-ring.
   Your own past deaths glow in the dark. Their net-event vocabulary also
   confirms the pattern our wave bus uses (§12.4).

---

## 11. RS_Main — the weapon system, first-party

RS is ours, so integration is direct; but it must *degrade* gracefully
since GITD also ships standalone. Two binding modes, both real today:

- **Load-order binding**: GITD loads before RS_Main; RS's ZScript compiles
  against `GITD_Sweep`/`GITD_Neon` directly (the SECTOR_SWEEP.md
  `RS_EliteRetier` example is written this way). RS guards each call site
  behind its own cvar so a GITD-less load of RS is a compile error — which
  is why the second mode exists.
- **The wave bus** (§12.4): net-event strings, zero compile-time coupling,
  for anything that must survive GITD's absence.

Connection points, from RS's actual source:

1. **Tier colour authority.** `RS_TierPalette` is THE tier table (one
   ladder: Cursed crimson → Trash olive → Basic white → Common green →
   Uncommon blue → Advanced purple → Designer yellow → Prototype cyan).
   NeonNumeric's header already promises "RS_Main should hand these
   RS_TierPalette.RGB(tier) and never touch the cvar" — the combo ledger's
   colour resolution order is therefore: RS tier colour (weapon that dealt
   the burst, or elite tier of the victim) → EntropyTier ramp (§1) →
   `gitd_neon_color`. One resolver, `GITD_Neon.ResolveColor(victim, source)`.
2. **Subclass-coloured trigger waves.** Every RS weapon declares
   `GetPaletteArchetype()` and a `Tier`. The patchbay's `shot` trigger, when
   RS is the source of the shot, colours the fired wave by
   `RS_TierPalette.RGB(weapon.Tier)` and can scale thickness by archetype
   class (shotgun = thick and short, railgun = thin and map-long). RS-side:
   ~10 lines in the fire path publishing "last shot: tier/archetype" to a
   static, GITD-side one read. (Per-shot fidelity wants the engine event,
   §13.B — the attack-edge trigger undercounts a chaingun by design.)
3. **Elite reveals announce.** RS's seventeen Elite types (C01–C17,
   controller thinkers that wake at the 50% reveal) each carry a signature
   colour; the reveal moment fires `GITD_Sweep.FireFrom(elite, SHAPE_RING,
   eliteColor, 600, 900, priority 15)` — the same grammar as captain
   announcements (§2) so the player learns one language. RS-side call,
   cvar `rs_elite_announce`.
4. **Per-weapon combo behaviour.** The ledger keys rows by *victim*; RS
   adds flavour per *source*: melee archetypes (Fist/Chainsaw) tighten the
   combo window (×0.5 — combos must be sustained at melee cadence to
   count), BFG-class widens it (×2 — one shot, many victims, all pop).
   Implemented as an optional multiplier the resolver hands back with the
   colour; standalone GITD keeps window = cvar.
5. **Lives systems already reconciled** — §8: RS_ScoreLives/RS_ScoreRevival
   own save + economy when present; GITD contributes the ritual only.
   `GITD_DeathRitual` is the one place both configurations share.

---

## 12. THE PATCHBAY — the expanded Sweep menu

### Design language (shared with the Reactive page — coordination note)

The sibling lane is building "Reactive" (`gitd_rx_*`): game-state
**sources** routed to glow-lane **responses**, one row per mapping. This
page is its twin: **triggers** fire **waves**. The contract between the two
pages, so the master session can merge cleanly:

- **One shared vocabulary of sources/triggers** — same names, same order,
  same OptionValue list where possible (`GITDSource`). A player who learns
  "combo" on one page finds "combo" meaning the same thing on the other.
- **Row-per-mapping layout**: each row reads left-to-right as a sentence.
  Reactive: *source → response*. Patchbay: *trigger → wave → effect*.
- **Cvar grammar**: `gitd_rx_<row>_<field>` there, `gitd_ws<slot>_<field>`
  here (ws = wave slot).
- Sources that need computing exist once and are exported to both pages:
  `GITD_Pacing` (§3), `GITD_TimeSense` (§6), the combo ledger (§5),
  captain tracking (§2).

**The shared source/trigger list** (superset; Reactive reads the leveled
ones as continuous values, the patchbay fires on their edges):

| id | name            | patchbay edge fires when                  | continuous form (Reactive) |
|----|-----------------|-------------------------------------------|----------------------------|
| 0  | off             | never                                     | —                          |
| 1  | always          | continuously (ambient behaviour)          | constant                   |
| 2  | kill            | a monster dies to the player              | kill pace (kills/10 s)     |
| 3  | hurt            | the player takes damage                   | damage taken rate          |
| 4  | shot            | attack-button rising edge (§13.B upgrades to true per-shot) | firing intensity |
| 5  | secret          | found_secrets increments                  | —                          |
| 6  | crit            | 'HeadShot'/stun/backstab lands (§4)       | crit rate                  |
| 7  | combo_pop       | a combo row pops its badge (§5)           | current best combo         |
| 8  | captain_spawn   | captain promoted/announced (§2)           | captain alive (bool)       |
| 9  | captain_down    | captain dies                              | —                          |
| 10 | giant_down      | Entropy tier-4 monster dies (§1)          | —                          |
| 11 | director_burst  | Director spawn burst detected (§3)        | pacing state (calm/buildup/assault) |
| 12 | bt_start        | bullet time engages (§6)                  | bt_fuel (adrenaline 0-525) |
| 13 | bt_end          | bullet time releases                      | —                          |
| 14 | grapple_hit     | hookshot lands (§7)                       | —                          |
| 15 | jetpack_hover   | sustained while hovering (§7)             | airborne seconds           |
| 16 | life_spent      | a death save fires (§8)                   | lives remaining            |
| 17 | low_health      | health crosses below 25% (edge, once)     | health fraction            |

### The menu (MENUDEF level)

Supersedes the current single-trigger layout **without breaking a single
existing cvar**: the ambient wave keeps `gitd_ss_trigger/direction/drive/*`
untouched and is presented as what it now truly is — the weather, one wave
among many (priority 0 in the wave list, exactly as implemented). The
patchbay adds four scripted slots on top. Four, not eight: each slot can
carry an 8-band train already, the wave list takes 64, and a menu of four
readable sentences beats a menu of eight abbreviations. `MAX_WAVES` refuses
loudly regardless.

```
OptionMenu "GITDSweep"
{
    Title "Sector Sweep"
    Option  "Sector Sweep",            "gitd_ss_enabled", "OnOff"

    StaticText ""
    StaticText "THE AMBIENT WAVE — the weather", gold
    // ... existing controls verbatim: shape/origin/count/colours,
    //     Fires (gitd_ss_trigger), Travels, Driven by, hurry/wake/drift,
    //     per-band fx and scripts, sonar, actors, Advanced submenu ...
    Option  "In bullet time",          "gitd_ss_timescale", "GITDTimescale"
    Option  "Wears the Director mood", "gitd_ss_pacing", "OnOff"

    StaticText ""
    StaticText "THE PATCHBAY — any trigger, any wave, any effect", gold
    StaticText "Each slot is a sentence: WHEN this happens, FIRE this", darkgray
    StaticText "wave, DOING this. Same trigger names as Reactive.", darkgray
    Submenu "Wave Slot 1",             "GITDWaveSlot1"
    Submenu "Wave Slot 2",             "GITDWaveSlot2"
    Submenu "Wave Slot 3",             "GITDWaveSlot3"
    Submenu "Wave Slot 4",             "GITDWaveSlot4"
}

OptionMenu "GITDWaveSlot1"   // 2..4 identical, cvar digit changes
{
    Title "Wave Slot 1"
    // WHEN --------------------------------------------------------
    Option      "Fires on",        "gitd_ws1_trigger", "GITDSource"
    Slider      "  Cooldown (tics)","gitd_ws1_cooldown", 0, 105, 5, 0
    // WHERE -------------------------------------------------------
    Option      "From",            "gitd_ws1_origin", "GITDWaveOrigin"
                // 0 the event itself  1 you  2 map centre
                // 3 last kill         4 nearest monster
    // WHAT --------------------------------------------------------
    Option      "Shape",           "gitd_ws1_shape", "GITDSweepShape"
    Option      "Travels",         "gitd_ws1_dir", "GITDSweepDirEx"
                // outward / inward / event decides (§7)
    Slider      "Speed",           "gitd_ws1_speed", 20, 2000, 20, 0
    Slider      "Range",           "gitd_ws1_range", 0, 8192, 128, 0
                // 0 = fit the map (diagonal-scaled; BigDoom-proof, §10.4)
    Slider      "Bands",           "gitd_ws1_count", 1, 8, 1, 0
    ColorPicker "Colour",          "gitd_ws1_color"
    Option      "  Colour from event","gitd_ws1_eventcolor", "OnOff"
                // tier / captain / elite colour when the event carries one
    // DOING -------------------------------------------------------
    Option      "Effect",          "gitd_ws1_fx", "GITDSweepFxEx"
                // 0-7 existing, 8 chaos (§9), 9 fixture surge (§10)
    TextField   "Script",          "gitd_ws1_script"
                // a GITD_SweepAction class name, as today, "" = none
    Slider      "Priority",        "gitd_ws1_priority", 1, 30, 1, 0
    Option      "Drawn",           "gitd_ws1_visible", "OnOff"
                // off = logical only: runs effects/scripts, never
                // competes for the eight shader slots
}
```

### Implementation (thin, honest)

One router in the handler — no new wave machinery whatsoever:

```zscript
// In GITD_Handler. Called by each detector with the shared source id and
// the event's position/colour. Detectors are the ones already built for
// their sections: kill/hurt/secret exist today; crit (§4), captain (§2),
// pacing (§3), bt (§6), grapple/hover (§7), lives (§8) are this document.
void PatchbayFire(int source, Vector3 at, Color eventCol)
{
    for (int s = 1; s <= 4; s++)
    {
        if (CVar.FindCVar("gitd_ws"..s.."_trigger").GetInt() != source) continue;
        if (level.maptime - wsLastFire[s] < CVar.FindCVar("gitd_ws"..s.."_cooldown").GetInt()) continue;
        wsLastFire[s] = level.maptime;

        // resolve origin/colour/range per the slot's cvars, then exactly:
        string script = CVar.FindCVar("gitd_ws"..s.."_script").GetString();
        if (script != "")
            GITD_Sweep.FireScript(origin, script, col, speed, range, shape, ...);
        else
            GITD_Sweep.Fire(origin, shape, col, speed, range, ..., fx, prio,
                            visible, String.Format("gitd_ws%d", s));
    }
}
```

Slot cvar values are read at fire time, not per tic — a fired wave is a
snapshot, matching how `Fire()` already works. The `jetpack_hover`
sustained trigger is the one special case: fire tagged, `Cancel(tag)` on
release.

### 12.4 The wave bus — the patchbay's back door for other mods

`NetworkProcess` command surface so ANY mod (RS in soft mode, user scripts,
a console bind) can fire a slot or a raw wave with zero compile-time
coupling, in the same spirit as Graveyard's `gy_spawn*` events:

```
netevent gitd_wave:<shape>:<rrggbb>:<speed>:<range>   // raw, from the player
netevent gitd_slot:<n>                                // fire slot n at the player
```

Parsed in `GITD_Handler.NetworkProcess`; arguments beyond the three ints
ride the event name string, Graveyard-style. Ten lines, and every trigger
in the table becomes reachable from a KEYCONF bind too — MORE OPTIONS.

---

## 13. Engine-level proposals (E:\UZDXREMA — ours, priced honestly)

### A. Move the sweep block out of StreamData — multi-origin for free, batching IMPROVED

**The current situation** (verified, `hw_renderstate.h:205-214`): the sweep
uniforms — `uSweepOrigin`, `uSweepBands[8]`, `uSweepColors[8]`, count,
trail — live in `StreamData`, the per-draw uniform struct. They cost
**288 bytes of every single draw's stream entry**, yet they are
**frame-global**: `SetSweepOrigin`/`SetSweepBand` set them once per tic for
the whole scene; no draw ever carries different sweep state from its
neighbour. They are in StreamData only because that is where the glow
wiring already was.

**The 64KB argument, engaged with** (SECTOR_SWEEP.md §9): the stated price
of per-band origins was "another vec4[8] in StreamData … roughly a tenth of
the draw batching". That maths is right *if they stay in StreamData* —
`MAX_STREAM_DATA = 65536 / sizeof(StreamData)` (vk_shader.h:27), StreamData
is ≈1.7KB (dominated by `uFlatGlowLines[64]` at 1KB), so ~37 entries per
page; +128B ≈ 35 entries, ~6-7% more page rollovers, forever. The section's
conclusion — "not a trade worth making silently" — was correct.

**The proposal inverts it**: move the *entire* sweep block into a small
frame-level UBO (alongside the viewpoint/matrices uniforms that are already
per-frame). Consequences:

- StreamData **shrinks** by 288 bytes → ≈41 entries per page, ~10% *fewer*
  page rollovers than today. The change pays for itself before adding
  anything.
- In a frame UBO, per-wave origins and shapes cost **zero per draw**:
  `uSweepOrigins[8]` + a shape per band are 160 bytes *per frame*. The
  "one origin, one shape for all eight" constraint — the reason
  `PresentWaves()` runs a priority competition and most scripted waves are
  invisible — disappears. Eight simultaneous, visibly drawn, differently
  shaped waves from eight different setpieces. The patchbay's four slots
  plus ambient all render at once instead of fighting for the lead.
- ZScript surface: `SetSweepBand` grows origin+shape parameters (defaulted,
  existing callers untouched); `PresentWaves()` loses its two-pass
  competition and becomes a straight fill of eight slots by priority.

**Price**: a new uniform block plumbed through both backends — GL
(`gl_shader.cpp` uniform binding, `gl_renderstate.cpp` apply) and Vulkan
(`vk_shader.cpp` descriptor set + generated GLSL declaration), the shader
(`main.fp` reads the new block; the per-pixel loop gains an origin/shape
index per band — a handful of ALU, nothing per-pixel expensive that isn't
already there), plus save/restore audit for portal and mirror passes
(frame-global is *correct* through portals — the wave is world-space).
Call it a day of engine work and a day of soak across GL/Vulkan/GLES.
Given it *improves* the baseline while unlocking the single most-requested
capability the current design refuses, this is the one to do.

### B. `WorldPlayerFired` — a real per-shot event

GZDoom has no weapon-fired event; GITD's trigger 4 is the attack-button
rising edge by necessity (documented in SSCheckTriggers), so a chaingun
burst is one wave and RS's per-shot tier-coloured waves (§11.2) undercount.
**Proposal**: dispatch a `WorldPlayerFired(player, weapon)` event from the
weapon fire path (`P_FireWeapon` / the psprite fire callsite in
p_pspr.cpp), mirrored into ZScript events alongside WorldThingDamaged.
**Price**: ~30 lines across events.h/events.cpp/dvmobject thunks; no cost
when no handler overrides it (the event manager already no-ops absent
overrides). **Value**: exact shot cadence for the patchbay, RS, and the
Reactive page's "firing intensity" source. Cheap, high value, do it after A.

### C. `TexMan.IsGlowing(TextureID)` / texture light metadata query

For §10.3 (lanes yielding to genuine lamp textures) the census
approximation works, but a one-line native exposing whether a texture
carries GLDEFS glow/brightmap metadata makes it exact and costs an hour.
**Value**: modest, quality-of-light. Take it opportunistically.

### D. A richer "monster died" event — assessed, and NOT worth it

The task asked for honest pricing of a "died of class X" event richer than
WorldThingDied. Verified against the engine's events.zs: `WorldThingDied`
already carries `e.Thing` **and `e.Inflictor`** (events.zs:80), the corpse
still holds `DamageTypeReceived` (Damnums relies on it), overkill is
`-e.Thing.health`, the killer is `e.Thing.target`, and the killing blow's
exact damage arrives one event earlier in `WorldThingDamaged` (our ledger
already catches it). Every field a richer event would add is already
reachable in script for the price of one array row we maintain anyway.
**Engine cost would be low; value is ~zero. Skip it.** (The genuinely
missing event is B — fired, not died.)

### E. Explicitly deferred (memory: billboard backlog — deliberate)

Native billboard collision, SDF payload extensions, attached-actor facing
modes stay deferred; nothing in this document needs them. The captain ring
(§2) uses BB_RING as it ships today.

---

## Appendix: new cvar roster (all server, all defaulting off/neutral)

```
gitd_neon_tiercolor      bool   false   tier colours on combo/badges (§1)
gitd_neon_critflare      bool   false   crit flare on combo billboard (§4)
gitd_neon_dmg_deathpop   bool   false   death pops lifetime total (§5)
gitd_ss_tierping         bool   false   sweep marks colour by tier (§1)
gitd_captain_announce    bool   false   wave when a captain appears (§2)
gitd_captain_lifewaves   bool   false   collapsing ring per life lost (§2)
gitd_captains            int    0       0 off / 1 wrap mod / 2 native layer (§2)
gitd_captain_odds        int    5       native promotion %, mirrors mbos_spawnrate
gitd_ss_pacing           bool   false   ambient wave wears Director mood (§3)
gitd_ss_pacing_sonar     bool   false   assault tightens sonar fade (§3)
gitd_ss_timescale        int    0       0 world time / 1 real time in bullet time (§6)
gitd_chaos               int    0       0 off / 1..4 cadence (§9)
gitd_dd_fixturefloor     int    0       darkness floor lift in fixture sectors (§10)
gitd_ss_fixtures         bool   false   FX_FIXTURES available / enabled (§10)
gitd_graveyard_glow      bool   false   neon marks under gravestones (§10)
gitd_lives_*                            see §8 (enable, start, punish, rewards,
                                        ritual, teleport)
gitd_ws{1..4}_trigger/cooldown/origin/shape/dir/speed/range/count/color/
gitd_ws{1..4}_eventcolor/fx/script/priority/visible          (§12)
```

Existing cvars: none renamed, none repurposed, none removed. The ambient
sweep's controls keep exactly their current meanings; `gitd_ss_pingpong`
stays declared-and-superseded as it already is.
