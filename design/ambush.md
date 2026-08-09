# Ambush setpieces

A wave sweeps a LOCKDOWN over wherever you are standing. The room darkens and
tints behind the wavefront, a fight sized to that room materialises inside it,
and killing everything sweeps the level back to what it was — the restoration
travelling as a wave too, so the room un-becomes the ambush from the centre
outward rather than snapping.

Everything rides the existing machinery. `GITD_Setpiece` journals what the
room was and reverts it; `GITD_Composite` composes the lockdown's darkness
with whatever else wants a say; the sweep engine carries the scripts and tells
us when a wave has finished. This file added three things that did not exist:
a room measurer, a budgeted spawner scoped to that room, and a win condition.

The shape is deliberately fixed: a beginning (sweep in), a middle (fight), an
end (sweep out). That is the whole state machine and it is not getting more
states. An ambush is shoot-your-way-out; it is still Doom, with an arcadey
direction. Anything that would layer a second mechanic on top belongs in the
"later" list at the bottom, not in `Configure()`.

Code: `zscript/Ambush.zs`. Wiring: `design/ambush-wiring.md` — until the
master session applies it, none of this is compiled or reachable.

---

## GITD_RoomSense — the room measurer

The reusable half, and the piece other systems should steal.

`GITD_RoomSense.Measure(pos)` starts in the sector under the point and floods
breadth-first across sector boundaries. It crosses a shared line only when
the opening is genuinely passable — a ceiling-to-floor gap over 56 units
(player height) and a floor step of 24 or less (walkable) — measured at the
line's midpoint so slopes answer for the actual crossing. Blocking flags stop
it, closed doors stop it (their gap is zero), line portals stop it, and it
gives up at a radius (default 1024) and a sector cap (96), because "the room"
on an open plain is a lie at any size.

The step rule means a tall drop-off ends the room even though a player could
jump down it. Deliberate: this measures the space a *fight* happens in, and a
monster spawned beyond a 128-unit ledge is not in your fight. Same reasoning
for treating `ML_BLOCKMONSTERS` as a wall.

It returns a `GITD_RoomInfo`: the visited sectors (as indices, plus an O(1)
membership mask), a summed area, the region's bounding extents, and a
classification — **closet / room / hall / arena**. The area is an honest
overestimate (each sector contributes its bounding box, so notches and
overlaps double-count) and the classification thresholds are tuned by eye:
small is a closet, long-and-narrow is a hall, big is an arena, everything
else is a room. Good enough to size an encounter, which is all it claims.

`netevent gitd_ambush_room` prints the measurement for wherever you stand —
that is the calibration tool for the thresholds.

## GITD_Ambush — the framework

Extends `GITD_Setpiece`. One launch runs this lifecycle:

1. **Measure.** The room around the origin, capped at `gitd_ambush_radius`.
2. **Budget.** By room class — closet: 0 or 2, hall: 5, room: 7, arena: 14 —
   scaled by `gitd_ambush_budget` and by the launch tier. If the plan comes
   up empty and tier-up is off, nothing fires and nothing was changed.
3. **Plan.** Each budget point picks a room sector (avoiding the player's
   immediate surroundings and piling at most two per sector) and a monster
   class from the ambush's weighted table.
4. **Sweep in.** A red ring (`GITD_Sweep.FireScript`). As the band core
   crosses each *room* sector it is journalled, tinted and darkened through
   the compositor, and its planned spawns appear in teleport fog, awake and
   aware of you. Sectors outside the room are never touched — the visible
   light sweeps past, the lockdown does not. Optionally the band promotes
   monsters already in the room (`tierBoost`); anything the band's core
   missed is spawned when the wave completes, so the budget means what it
   says.
5. **Hold.** The lockdown re-declares its tint every tic (the base class's
   `Republish`); the controller watches the kill list.
6. **Sweep out.** All tracked monsters dead → victory: badge, reward hook,
   and a blue return wave restores the journal. The journal pattern is the
   win condition too: `aSpawned` + `aMarked` are the ledger, and the ambush
   ends when every entry is dead.

Edge behaviours, chosen and documented rather than left to chance:

- **Player dies**: blunt instant revert (`RestoreEverything`), conjured
  monsters despawn (kill counters cleared first, so the stats stay honest).
  No wave — a death screen does not need the pretty version.
- **Player leaves** (beyond 1.5× the radius for 2 seconds): the ambush loses
  interest and sweeps out. Its conjured monsters leave with it; anything it
  *promoted* stays promoted — the room remembers what you did to it. No
  badge.
- **Timer** (`gitd_ambush_timer`, 0 = off): outlasting it also lifts the
  lockdown, without a badge.
- **Corpses stay.** Only living conjured monsters are removed on any exit;
  removing a corpse the player earned is worse than leaving it.
- **One at a time.** A second launch while one runs is refused; the manual
  netevent doubles as "walk away from this one".

### Launching

One way in, three callers today:

```
GITD_Ambush.Launch(origin, tier, rewardTag, clsName);
```

- `tier` (default 1) scales the budget (+50% per step) and, from tier 3 up,
  forces some promotion even if the menu has tier-up off.
- `rewardTag` is an opaque string the ambush carries and hands to
  `OnCleared()` at victory — printed today, meant for the setpiece shop
  later.
- `clsName` empty means the `gitd_ambush_class` cvar.

The console netevent and the ambient roll are just two callers of this. The
cvar gate (`gitd_ambush_enabled`) lives on the *triggers*, not on `Launch` —
a system calling `Launch` directly has already made its own decision.

## GITD_Ambush_Blackout — the authored one

The lights collapse to near-dark swept inward over the room: a near-black
tint, a −220 light delta, heavy desaturation. The sweep band carries the
engine's sonar reveal, so the travelling line lifts each sector to its
natural brightness for a moment and lets it sink back to near-black behind —
the band is the only look at the room you get. Spawns are imps, pinkies and
shotgunners, weighted toward imps; a pinky in the dark is the whole genre.
Victory pops your cleared-ambush count through the Neon engine (wgType 13
badge when that style is selected, driven open and closed like the kill
counter's).

## Authoring a new ambush

A subclass and a `Configure()` override. Nothing else.

```zscript
class RS_Ambush_Meltdown : GITD_Ambush
{
    override void Configure()
    {
        Super.Configure();              // the player's menu choices load first
        envColor = Color(255, 120, 40, 10);   // then your identity overrides
        envLight = -100;
        aSonar   = false;
        aSpawnCls.Clear(); aSpawnWt.Clear();
        AddSpawn("HellKnight", 2);
        AddSpawn("DoomImp", 5);
    }
}
```

Point `gitd_ambush_class` at it (or pass its name to `Launch`). The contract:
`Super.Configure()` first — it loads the cvar-fed defaults — and what you
write after it is what your ambush refuses to let the menu change. Override
`BudgetFor()` only if your ambush wants its own economy, and `OnCleared()`
only if victory should do more than the badge. If your subclass needs more
than a screenful of `Configure()`, the idea is out of scope for an ambush —
put it on the "later" list instead.

The tint/light/desat fields go through `GITD_Composite` automatically (the
base class republishes every tic); never call `SetColor` or `SetLightLevel`
from an ambush, for the reasons `SectorComposite.zs` documents at length.

## Honest limits

- The room is sectors, so the lockdown edge is a sector boundary, not the
  band's pixel edge. A huge single sector is all-or-nothing.
- Area is a bounding-box overestimate; classification is by-eye thresholds.
  `netevent gitd_ambush_room` exists to check them against real maps.
- Spawn placement tries the centerspot and four offsets per plan entry; in
  genuinely cramped geometry a budget point can fail and the wave arrives
  under strength. The win condition only counts what actually exists.
- Watchdog logic (death, flee, victory) follows `consoleplayer`, like the
  rest of GITD — single-player assumptions throughout.
- The sweep-out never fires while the sweep-in is still travelling (the
  underlying engine would run apply and revert against the same journal in
  one tic). The two mid-inbound exits are "let it finish" and the blunt
  abort; keep that true if the state machine ever changes.

## Later — on record, not built

The Minibosses lesson stands: conceptually cool is not a license to bloat.
These stay out of the framework until they earn their way in as their own
systems:

- **The setpiece shop.** An in-world shop where the player spends currency to
  buy encounters — real challengers — for higher-end drops. `Launch(origin,
  tier, rewardTag)` is already shaped for it: the shop is just a third
  caller that pays before calling and listens for the reward tag at
  `OnCleared`. No currency, no UI, no stock exists today; the parameter
  layer is the whole preparation.
- **Ambush variety rotation** — a weighted table of ambush classes for the
  ambient roll, instead of the single `gitd_ambush_class`.
- **A countdown readout** for the timer through the Neon engine, over the
  lockdown's origin.
- **Music stings** per ambush (the base class already journals and restores
  music; GITD ships no music lumps to use it with).
- **Reverting promotions** on flee/timeout — needs a journal of pre-promotion
  stats; today survivors deliberately stay promoted.
- **Multiple simultaneous ambushes** — the engine's wave list supports it;
  the watchdog and the fiction (one lockdown at a time) do not, on purpose.
