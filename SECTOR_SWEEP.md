# Sector Sweep

A band of light travelling through the map, measured in world space. Because
the distance is world-space and the test runs on every surface, the band wraps
across floor, wall and ceiling by itself — a cylinder cuts all three at the
same radius, a plane draws an unbroken rectangle around a corridor. Nothing in
the shader knows what kind of surface it is shading, and that is the whole
trick.

The band is also a **spatial query with a wavefront attached**, and that turns
out to be the more useful half. Everything below hangs off the same question,
asked once per tic: *how close is this sector — or this monster — to which
band, and how strongly?*

---

## 1. The parts

| Layer | Lives in | What it does |
|---|---|---|
| The band itself | `main.fp`, `hw_drawinfo.cpp` | Draws it. Up to 8, GPU uniform array. |
| Geometry and timing | `zscript/GlowHandler.zs` | Where each band is, how fast, which shape. |
| What arrival *means* | `zscript/SweepEngine.zs` | Effects, band scripts, setpieces. |
| Who owns a sector | `zscript/SectorComposite.zs` | The single writer for light and colour. |

---

## 2. Shapes, and what the band measures

`gitd_ss_shape`, and it must agree with `smode` in `main.fp` or the sector
effects will lag the visible band and look like a renderer bug.

| # | Shape | Distance |
|---|---|---|
| 1 | Ring | `length(pos.xz - origin.xz)` — a cylinder |
| 2 | Bar east/west | `abs(pos.x - origin.x)` — a plane |
| 3 | Bar north/south | `abs(pos.z - origin.z)` |
| 4 | Shell | `length(pos.xyz - origin.xyz)` — a sphere |
| 5 | **Rising** | `pos.y - origin.y`, **signed** — climbs vertically |

Mode 5 is signed on purpose: a negative radius travels downward, so the same
band can rise or fall without a second mode.

## 3. Where it starts

`gitd_ss_origin` — map centre, where you spawned, follows you, **your last
shot**, **the last monster that died**, **the nearest live monster**.

The nearest-monster origin is re-found every tic, so it walks from one enemy
to the next as they die and as you move.

## 4. When it runs

`gitd_ss_trigger` is the single biggest change to how the sweep reads. Free
running, it is weather. Fired by an event, it is the room answering you.

- Never stops (the original behaviour)
- Each kill
- Each time you are hurt
- Each trigger pull — the **rising edge**, not the shot. GZDoom has no
  "weapon fired" event, and an edge gives one wave per pull rather than a
  solid wall of them out of a chaingun.
- Each secret found

`gitd_ss_direction` — outward, **inward (collapsing)**, or out-and-back. An
expanding ring is a reveal; a closing one is a countdown. It is a sign flip.

`gitd_ss_drive` — normally the band's position is a clock. Set it to **kills**
or **health** and the position *is* the readout; nothing on screen has to say
the number.

`gitd_ss_health_speed` — the sweep hurries as you weaken. Nothing announces
it, which is the point.

## 5. Shape of each band

`gitd_ss_trail` — the **wake**. A band is symmetric until this says otherwise,
and then it is simply *wider* on the side it came from. Stretching one half
keeps it a single falloff, so there is no seam where a bolted-on second
gradient would have met the core. The sign follows travel direction, and at
zero it is byte-for-byte the symmetric band it always was.

`gitd_ss_drift` — gives each band its own speed, so a train that started
evenly spaced drifts in and out of phase forever.

## 6. Per-band effects

`gitd_ss_perband` off, every band uses `gitd_ss_light_mode`. On, each of the
eight carries its own `gitd_ss_fxN`:

`0` nothing · `1` brighten · `2` darken · `3` re-colour glows ·
`4` sonar reveal · `5` wake monsters · `6` mark monsters · `7` slow monsters

Set band 1 to darken and band 2 to brighten and the room breathes as the train
passes. That is the reason eight bands exist.

**Sonar** reveals a room to its natural brightness and then lets it decay back
to `gitd_ss_sonar_floor` over `gitd_ss_sonar_fade` tics. Pairs with DarkDoom
rather than fighting it.

**Monster effects** need `gitd_ss_actors`, off by default because it walks the
thinker list every tic.

---

## 7. Scripting

Three ways in, increasing in power.

### GITD_SweepEffect — listen to everything

```zscript
class RS_EliteRetier : GITD_SweepEffect
{
    override bool WantsActors() { return true; }
    override void ActorPass(Actor a, int band, double strength)
    {
        if (band == 0 && strength > 0.6) RS_Tier.Promote(a);
    }
}
// from any handler's WorldLoaded:
GITD_Sweep.Register(new("RS_EliteRetier"));
```

Registrations are dropped on every map load **on purpose** — an effect holding
Sectors or Actors from a level that no longer exists is the standard way to
crash on a map change.

### GITD_SweepAction — bind a script to one band

A `GITD_SweepEffect` hears everything. A `GITD_SweepAction` is bound to a
single band, by name, and only that band's arrivals reach it. That is what
makes a train of eight a *program* rather than decoration:

```
band 1  ->  "Blackout"     kills the lights
band 2  ->  "ArenaSpawn"   fills the dark with things
band 3  ->  "TierUp"       promotes what it passes
band 4  ->  "Restore"      puts the level back
```

Four waves crossing a room in sequence, spacing between them set in tics. The
wavefront is the clock and the cursor at once.

Bind from the menu (`gitd_ss_script1..8`) or fire directly:

```zscript
GITD_Sweep.FireScript(boss.pos, "RS_ArenaLockdown", 0xFF2000, 700, 2048);
```

### GITD_Setpiece — reversible world transformation

The hard part of "sweep an arena in, then sweep it back" is not the sweeping.
It is that **a change you cannot undo is not a setpiece, it is damage.** So it
journals: every sector it alters is recorded before it is touched, spawned
actors are remembered, billboards are remembered, music is remembered.

```zscript
class RS_BloodArena : GITD_Setpiece
{
    override void Configure()
    {
        envColor    = "80 00 00";
        envDesat    = 60;
        envFloorTex = "FLOOR1_1";
        music       = "D_E1M8";
        spawnClass  = "RS_ArenaImp";
        spawnOdds   = 8;       // one sector in eight
        tierBoost   = 1.5;     // health and speed of what it passes
        markPayload = 10;      // stamp a wgType into every sector
    }
}

GITD_Sweep.FireScript(boss.pos, "RS_BloodArena", 0xFF2000, 700, 2048);
// ...later
GITD_Setpiece.SweepOut("RS_BloodArena", boss.pos, 700, 2048);
```

The restoration travels as a wave too, so the room un-becomes itself from the
origin outward rather than snapping.

`markPayload` places billboards — the same wgType machinery the kill badge
uses — into every sector the wave passes, and the return sweep pulls them.
That is how a sweep draws a setpiece into the world and then un-draws it.

### GITD_SweepMark

For code that does not want to write an effect class at all. A band with
`fx = 6` leaves a mark on every monster it touches; anything, anywhere, can
then ask:

```zscript
if (GITD_SweepMark.Age(mo) in [0..35]) ...    // touched in the last second
GITD_SweepMark.BandOf(mo)                      // by which band
```

---

## 8. GITD_Composite — why nothing writes to a sector any more

Three systems wanted to change how a sector looks, and all three did it the
obvious way — `SetColor` and `SetLightLevel`, every tic:

- DarkDoomZ dims every sector in the map
- Sector Sweep brightens or darkens the ones under a band
- A setpiece tints the ones a wave has passed

**Whichever ran last won**, so the visible result was decided by the order of
names in `mapinfo.txt`. That is not a bug you fix once — it comes back every
time anything new wants a say, and it had already bitten twice. The sweep's
brighten was being erased by the darkness pass. A setpiece's tint vanished
within a frame of being applied and looked like it had never run at all.

So nothing writes to a sector now. Everything *declares*, and the compositor
flushes once per tic:

```
colour = the map's own colour  x  every tint, multiplied
light  = the map's own level   +  every delta, added
```

Multiplication and addition both commute, so **order stops mattering**.
Darkness and a red setpiece compose into a dark red room instead of one
deleting the other.

### Light and colour are handled differently, deliberately

Nothing in Doom animates a sector's **colour**, so colour is rewritten every
tic for every sector and nobody minds.

Doom animates **light** constantly — every blinking, pulsing and flickering
sector is a thinker writing `lightlevel` at up to 35Hz. Writing light
unconditionally fights all of them and the walls strobe; that exact bug cost
an evening once already. So light is only written for sectors something
actually asked about, and released back to the engine the moment nothing does,
which lets vanilla's light effects keep running everywhere the tic did not
reach.

### Consequences

- `DarkDoomZ.ApplyLightLevels` is **gone**. It had had no caller for some
  time and was now actively dangerous: a second writer stamping raw light
  values would resurrect the flicker. `ddz_mode` still selects the darkness
  *curve* — see `DarknessMul`.
- The sweep's own `sweepBase` snapshot is gone; `GITD_Composite.BaseLight` is
  the one baseline. Three copies of "what did the map say this was" was two
  too many.
- A setpiece must **re-declare its tint every tic** (`Republish`), because the
  compositor forgets all contributions after each flush. That forgetting is
  what stops effects accumulating.

---

## 9. Known limits

- **8 bands is a GPU limit, not a design one.** `uSweepBands[8]` is a uniform
  array. It should only cap how many bands can be *drawn* — the logical wave
  that drives scripts needs no GPU at all and has no reason to be capped.
  Splitting visual bands from logical waves is the obvious next move and is
  **not done**.
- Sector effects are per-sector and therefore coarser than the band, which is
  per-pixel. A large sector changes all at once.
- The trigger-pull trigger fires on the button edge, not per projectile.
