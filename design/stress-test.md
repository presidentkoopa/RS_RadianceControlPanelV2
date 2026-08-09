# Stress test: what a tic costs

Static cost analysis of GITD's per-tic work, mod (E:\GlowInTheDark) and engine
(E:\UZDXREMA) together. Nothing here was measured in-game; every number is an
estimate built from the code paths below and the unit costs stated first, so
treat absolute numbers as ±2-3x and the *ratios* as the finding. There is no
performance budget yet — this file records and ranks so the someday-pass knows
where to start.

Date: 2026-08-09. Branch state: GITD at "Sweep gains a wake", engine at
`neon-text` 7cdcf669da.

---

## Unit costs assumed

Desktop x86, JIT-compiled ZScript. These are the error bars on everything else.

| Operation | Cost | Basis |
|---|---|---|
| Simple VM native call (SetGlowColor etc.) | ~50 ns | param marshalling + field write |
| `Sector.SetColor` native | ~120 ns | vmthunks.cpp:352 → p_sectors.cpp:750: two field writes **+ `P_RecalculateAttachedLights`** (p_3dfloors.cpp:634 — walks the sector's XFloor lightlist; empty on flat maps, real work on 3D-floor maps) |
| `CVar.FindCVar` (constant name) | ~150 ns | c_cvars.cpp:1418 — FName find-only + TMap hash. Not a list walk. |
| `CVar.FindCVar` (concatenated name, `prefix .. suffix`) | ~300 ns | above + FString build/free per call |
| `StaticEventHandler.Find` | ~100 ns | events.cpp:1705 — linked-list walk comparing class pointers, ~10 handlers live |
| ZScript loop iteration + arithmetic | ~15 ns | JIT, bounds checks included |
| `ZatPoint` / `GetTexture` native | ~60 ns | |
| Tic budget at 35 Hz | 28,571 ns × 1000 = **28.6 ms** | |

Parameter grid: N sectors ∈ {150, 1500, 10000}, W live waves ∈ {1, 8, 64},
M live monsters ∈ {20, 200, 1000}. Thinker-list walks visit every actor, not
just monsters; assume total actors ≈ 2M.

---

## 1. GITD_Composite.WorldTick — the flush

SectorComposite.zs:150. N iterations, each an unconditional `SetColor` plus
channel resets; `SetLightLevel` only for held/asked sectors.

Engine side: `SetColor` is *almost* free — two field writes — but it always
calls `P_RecalculateAttachedLights`, which walks `XFloor.lightlist`. On a map
without 3D floors the list is empty and the call is pure overhead; on a
3D-floor-heavy map every one of the N calls does per-lightlist work
(`UpdateColormap` per entry, p_3dfloors.cpp:608). Nothing is dirtied for the
renderer — no vertex data depends on Colormap — so there is no hidden
invalidation cost beyond that walk.

Cost ≈ **160 ns × N** (flat map): 24 µs / 240 µs / 1.6 ms for N = 150 / 1500 /
10000. Runs whether or not anything changed, every tic, even with every GITD
feature switched off.

**Dirty check worth proposing: yes, and it is the easy kind.** In steady state
(darkness at a constant level, no sweep overhead) the composed colour is
identical tic after tic. Cache the last written packed colour+desat per sector
(one more `Array<int>`), skip `SetColor` when equal. Typical skip rate ~100%;
the loop drops to ~50 ns × N and the 3D-floor lightlist walk disappears from
the steady state entirely.

## 2. DarkDoomZ.ApplyDarkness

DarkDoomZ.zs:214. Per sector per tic: two `GetTexture` sky checks, one
`GITD_Composite.Tint`, one `Desaturate`. Tint and Desaturate each begin with
`StaticEventHandler.Find` (SectorComposite.zs:59) — two handler-list walks per
sector per tic.

Cost ≈ **370 ns × N**: 56 µs / 555 µs / 3.7 ms. Also unconditional: with
darkness disabled, `DarknessMul()` returns 1.0 and the loop still runs, tinting
every sector white at full price.

Cheap wins recorded for later: (a) sky flags are constant per map — cache a
`Array<bool>` at WorldLoaded, saves 2 natives × N; (b) hoist the composite
handler lookup out of the loop (fetch once per tic, call instance methods, or
pass it in); (c) early-out the whole loop when `m == 1.0 && desat == 0`.

## 3. ApplySectorSweepEffects — sectors × waves

GlowHandler.zs:1010. Per sector: `IsOverridden` (linear over the override list,
normally empty), `centerspot`, one `floorplane.ZatPoint` native, then per live
wave a `WaveDistance` + `WaveNearest` (loops that wave's bands). Touched
sectors with fx 3 pay 8 glow natives (~400 ns) on top. While *any* wave is
live, `ClearAll()` also runs first — 8 natives × N ≈ 400 ns × N — every tic
(GlowHandler.zs:528).

Per-sector fixed ≈ 100 ns; per wave visited ≈ 70 ns (1-band scripted) to
140 ns (8-band ambient).

| N \ W | 1 (ambient, 8 bands) | 8 | 64 |
|---|---|---|---|
| 150 | 36 µs | 100 µs | 0.7 ms |
| 1,500 | 0.36 ms | 1.0 ms | 7 ms |
| 10,000 | 2.4 ms | 6.6 ms | **~46 ms — over the whole tic** |

Add ClearAll: +60 µs / +600 µs / +4 ms.

The documented "64 waves over a large map is not free" is quantified: the
MAX_WAVES=64 ceiling **cannot actually be spent** on a 10,000-sector map —
the sector pass alone is ~1.6 tics. On 1,500 sectors it fits, ugly but alive.
Someday-fix: per-wave band envelope (min/max band position, computed once in
PrepareWave) so a sector outside `[min-reach, max+reach]` skips the wave in
one compare; most sectors are outside most waves.

ZatPoint per sector per tic is also cacheable — sector centre height changes
only when a plane moves.

## 4. ApplySweepToActors — the thinker walk

GlowHandler.zs:1127. Gated off unless `gitd_ss_actors`, a registered effect
wants actors, or any band carries fx 5-7 / an actor-wanting action. When on:
full `ThinkerIterator` walk of STAT_DEFAULT (every actor — corpses,
decorations, projectiles — not just monsters), then per live monster the same
W × bands math as sectors, plus `FindInventory("GITD_SweepMark")` (linear
inventory scan) on marked paths.

Cost ≈ iterator (~80 ns × 2M actors) + M × W × ~70 ns:

| M \ W | 1 | 8 | 64 |
|---|---|---|---|
| 20 | ~4 µs | ~15 µs | ~93 µs |
| 200 | ~40 µs | ~144 µs | ~0.9 ms |
| 1,000 | ~0.2 ms | ~0.7 ms | **~4.6 ms** |

Separately, ambient origin mode 5 (nearest monster, GlowHandler.zs:792) is a
*second* full thinker walk every tic, ~80 ns × 2M ≈ 0.16 ms at M=1000,
regardless of whether the actor pass runs. The two walks could share one pass.

## 5. PrepareWave — allocation pressure

GlowHandler.zs:681. Per live wave per tic: 4 × `Array.Clear` + up to 32
Pushes. **Verified: ZScript `Clear` does not free.** dynarrays.cpp:142 →
`TArray::Clear()` sets Count=0 and keeps the allocation, so after a wave's
first tic every Clear+Push cycle is allocation-free. No GC churn, no malloc
churn. Cost is just native-call overhead: ~2-4 µs per wave, ~130 µs even at
W=64. Ambient additionally resolves its per-band cvars here — ≤68 `FindCVar`
at 8 bands ≈ 20 µs — which is the *fix* for the old tens-of-thousands-a-tic
disease, working as designed.

Object churn elsewhere: `GITD_Wave` allocated per Fire (event-driven, capped
64); `GITD_SweepMark` is one Inventory actor per monster first marked (bounded
by M, lives with the monster). Nothing allocates per tic as a function of
time. Verdict: **not a problem.**

## 6. Remaining CVar.FindCVar-by-string per tic — the census

140 occurrences total across the mod; the ones on per-tic paths, multiplied
out:

| Site | Per tic | Notes |
|---|---|---|
| **`GITD_Lane.AnimFactor`** (GlowHandler.zs:222-237 via :117-119) | **4N (anim off) to 20N (anim on, 4 lanes)** | called per lane per SECTOR in `Apply()`; every call concatenates `prefix .. suffix` (an FString alloc) then hashes |
| `Apply()` per-tic constants (patterns, speeds, coverage…) | ~45 | fine |
| Sweep path (RefreshAmbient 16 + triggers 2 + effects 3 + actors 1 + PrepareWave ≤68) | ~90, independent of N | fine — this path was already fixed |
| DarkDoomZ (noflash, enabled ×2) | 3 | fine |
| Flashlight beam (Flashlight.zs:189-212) | ~20 | fine |
| NeonNumeric | ~2 + 1 per live fading badge (`Linger()` inside the loop, :363) | fine |
| GITD_SetpieceSelfTest (`gitd_ss_demo`, SweepEngine.zs:843) | 1 | a self-test cvar polled every tic in shipping code |
| GITD_PresetCustomiser | 1 | fine |

The multiplication that matters: lane mode (the mod's default state — sweep
off, glow lanes on) pays **AnimFactor**:

- N=1,500: 6,000–30,000 lookups/tic ≈ **1.8–9 ms** (6-30% of the tic)
- N=10,000: 40,000–200,000 lookups/tic ≈ **12–60 ms** — with animation on all
  four lanes, a slaughtermap cannot hold 35 Hz on lane glow alone.

This is the exact disease PrepareWave already cured for the sweep, alive in
the lane path. The fix is the same shape and touches ~20 lines: resolve
`_anim`, `_anim_length`, `_anim_depth`, `_anim_sharp`, `_anim_phase` once per
tic in `GITD_Lane.Step()` into fields; `AnimFactor` reads fields. Removes
80-95% of lane-mode cost in one commit. On top of that, `Apply()`'s ~16 glow
natives per sector (ApplyOne, :1346) are unconditional; when anim is off the
values are identical map-wide and tic-to-tic, so the same last-written dirty
check as item 1 applies.

## 7. GITD_Setpiece — journal, jTouched, jSpawned, revert

SweepEngine.zs:518.

- **Journal growth**: `jIdx`/`jFloor`/`jCeil` grow to distinct sectors passed
  (≤ N), `jTouched` is exactly N bools, `jBillboards` ≤ touched sectors and
  cleared by UnstampAll, `jSpawned` ≤ N/spawnOdds. All bounded by map size,
  all cleared on revert. **No unbounded growth.**
- **jSpawned dangling refs — verified safe.** ZScript object loads go through
  the GC read barrier: vmexec.h:249 and jit_load.cpp:209 apply
  `GC::ReadBarrier` (dobjgc.h:105), which returns null for any object with
  `OF_EuthanizeMe`. A Destroy()ed actor in `jSpawned` reads as null, and
  `DespawnAll` checks `if (a && ...)`. The assumption in the task brief holds
  on this engine.
- **Revert is quadratic, concentrated per tic.** During a revert wave,
  `OnSector` fires **every tic for every sector under the band** (strength ≥
  0.5), and each call runs `RestoreSector` — a full linear scan of `jIdx`
  (SweepEngine.zs:716). The record is never removed from `jIdx`, so a sector
  under the band for 20 tics is re-scanned and re-restored (including
  `SetTexture` natives) 20 times. Per tic ≈ (covered sectors) × J iterations;
  whole revert is O(J²).
  - Realistic arena (J=500 journaled, ~100 covered/tic): 50k compares/tic
    ≈ 0.75 ms — fine.
  - Pathological (J=10,000, 1,000 covered/tic): 10M compares/tic ≈ **tens of
    ms — dropped tics for the duration of the revert**. Requires a setpiece
    that swept an entire slaughtermap first, so it is self-inflicted, but the
    failure mode is a multi-second stutter during the "put it back" moment.
  - `RestoreRecord` also linear-scans and `Delete`s from `tinted` (O(T)
    memmove each) — O(T²)/2 element moves over a full revert.
  - Someday-fix: `jTouched` is already a per-sector array; make it store the
    journal index instead of a bool, and mark records restored so repeat
    coverage is O(1).
- **Republish** (SweepEngine.zs:615, called every tic from SSRepublish): T
  tinted sectors × (~150-250 ns of handler-Find + math). A setpiece holding a
  whole 10,000-sector map tinted costs ~2.5 ms/tic for as long as it stays.
  Same handler-hoist win as item 2.

## 8. sonarGlow

GlowHandler.zs:420, decay at :1098. Sized to N at load and resized lazily.
When any live band anywhere has fx 4, every sector pays the decay/override
branch: ~40 ns × N plus an `OverrideLight` (handler Find + write) for sectors
still glowing. ≈ 0.4-1 ms at N=10,000. When no sonar band exists the branch is
skipped; the array just sits there (N doubles ≈ 80 KB at 10k — fine).

Behaviour note, not perf: decay only runs inside `ApplySectorSweepEffects`,
which only runs while any wave is live. If the last wave dies while rooms are
still sonar-lit, the composite releases their light next flush (instant snap
to base) and `sonarGlow` freezes at stale values until the next wave.

## 9. Engine side — what a frame pays

- **Playsim natives are free at this scale.** SetSweepBand/Origin/Trail are
  bare field writes (vmthunks.cpp:3363-3429); ≤ 10 calls per tic.
- **Per scene, not per wave.** hw_drawinfo.cpp:840 copies
  `level.Sweep*` into the render state once per scene. **Wave count W has
  zero engine cost** — only the ≤ 8 slots PresentWaves filled exist below the
  ZScript line.
- **GL, per draw call** (gl_renderstate.cpp:171-180): `muSweepOrigin` is an
  unbuffered `FUniform4f` (gl_shader.h:179 — raw `glUniform4fv` every draw,
  no change check), count/trail are buffered, and while a sweep is visible
  two more `glUniform4fv` uploads (≤ 8 vec4 each) run per draw. At 2,000
  draws/frame that is ~2,000 always + ~4,000 while sweeping extra driver
  calls ≈ 0.2-0.6 ms of render-thread CPU per frame. Flat glow is worse per
  draw when active: `uFlatGlowLines[64]` is a 1 KB upload (:188).
- **Vulkan, per draw**: the whole `StreamData` struct is streamed per draw.
  Field-by-field sum of hw_renderstate.h:176-247 gives **sizeof(StreamData) =
  1,760 bytes**, so `MAX_STREAM_DATA = 65536/1760 = 37` draws per 64 KB UBO
  block (vk_shader.h:27). Without the fork's additions (sweep 288 B, flat
  glow 1,056 B, glow falloff 16 B) the struct is ~400 B ≈ 163 draws per
  block: **the fork cut Vulkan draw batching ~4.4×**, and `uFlatGlowLines[64]`
  alone is 58% of every draw's upload, paid whether or not flat glow is on
  that draw. 2,000 draws = 3.4 MB streamed per frame ≈ 310 MB/s at 90 fps.
  This is the context for SECTOR_SWEEP.md's refusal to add per-band origins —
  correct call; the budget is already spent.

---

## Ranked: top 5 costs

Worst realistic case per tic, biggest first:

1. **Lane-mode AnimFactor cvar lookups + unconditional glow writes** (item 6 +
   Apply): 4N-20N string-built FindCVars plus 16N natives, every tic, in the
   mod's *default* mode. 12-60 ms at N=10,000; ~2-10 ms at N=1,500.
2. **Sector × wave sweep pass** (item 3): fine to W=8 anywhere; the W=64
   ceiling is unspendable at N=10,000 (~46 ms + 4 ms ClearAll).
3. **The always-on floor** (items 1+2): composite flush + darkness pass ≈
   530 ns × N every tic even with everything off — 5.3 ms at N=10,000, plus
   lightlist walks on 3D-floor maps.
4. **Setpiece revert scan** (item 7): O(J²) with per-tic re-restores;
   ms-scale stutter for map-wide setpieces on big maps, invisible on arenas.
5. **Actor walks** (item 4): full thinker iteration × W when on, plus the
   independent second walk for origin mode 5 — ~5 ms at M=1,000 / W=64.

## Cheapest wins for the someday-pass, best value first

1. Hoist `AnimFactor`'s five cvars into `GITD_Lane.Step()` fields — ~20
   lines, removes 80-95% of the #1 item. Identical in shape to the
   PrepareWave fix that already exists.
2. Last-written dirty check in `GITD_Composite.WorldTick` (and the same trick
   in `ApplyOne`) — one cached int array each, near-eliminates #3 and most of
   #1's native calls in steady state.
3. Cache sky flags per sector at WorldLoaded + fetch the composite handler
   once per tic in ApplyDarkness — removes ~60% of item 2.
4. Journal index array + restored flag in GITD_Setpiece — kills the O(J²).
5. Per-wave band envelope prefilter in the sector pass — one compare per
   wave per sector, prunes most of N × W.

## URGENT

**Nothing qualifies.** Checked against the brief's definitions:

- Unbounded growth: none. Waves cap at 64 with loud refusal; journals bound
  by map size and clear on revert; NeonNumeric's permanent list self-caps at
  64 with oldest-first eviction (NeonNumeric.zs:331); damage accumulators
  retire on quiet/death.
- Arrays that never shrink: none that grow past map-sized.
- Per-tic allocations scaling with time: none. `Clear` keeps capacity
  (verified engine-side); the FString temporaries in cvar-name concatenation
  are per-tic churn but scale with N, not time.
- Dangling references to destroyed objects: none — the GC read barrier nulls
  destroyed actors in `jSpawned`, `dtar`, and everywhere else ZScript reads
  them (verified at vmexec.h:249, dobjgc.h:105).

Watch list (real, but not urgent by the stated bar):

- DarkDoomZ_Handler.UiTick sends a network event **every tic** to re-read
  settings (DarkDoomZ.zs:132). Constant cost in singleplayer; in multiplayer
  it is a per-tic net message per client and it pads demos. Inherited
  DarkDoomZ behaviour, trivially replaceable with a per-tic check in
  WorldTick.
- Sonar rooms snap instead of fading if the last live wave dies while they
  are lit (item 8).
- `GITD_SetpieceSelfTest` polls its demo cvar every tic in shipping builds.
