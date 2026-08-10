# Darkness as a shader term

*Written while the reveal was fresh. Not scheduled, not approved — this is the
argument and the plan, so the decision can be made later on evidence rather
than on memory.*

---

## The realisation

Sector Sweep stopped being sector light. It measures **every pixel** against up
to eight independent origins and decides what that pixel should be. The sector
is no longer the unit of lighting — it is only where the baseline comes from.

DarkDoomZ is still built for the old world. It darkens by scaling each
**sector's colour**: one multiplier, one room, uniform from wall to wall. Every
curve it has — Subtract, Compress, Clamp, Crush — is arithmetic on a single
light level.

That was correct when a sector's light level was the only lever there was. It
is now the coarse layer underneath a fine one.

## The tell

The reveal works by **multiplying back up what DarkDoom multiplied down**.

That is the giveaway. One system is inverting another system's arithmetic to
recover information the first system deliberately destroyed. It works — the
detail survives because scaling is lossy in precision but not in ratio — but
nobody would design it this way on purpose. Two features are politely undoing
each other and calling the result a lighting model.

Three systems currently contribute and none of them share a model:

| | works on | granularity | when |
|---|---|---|---|
| DarkDoomZ | sector colour | per sector | per tic, script |
| Sector Sweep, per-sector mode | sector light level | per sector | per tic, script |
| Sector Sweep, per-pixel mode | the fragment | per pixel | per frame, shader |

The compositor already fixed the *ordering* problem between the first two. It
cannot fix the *granularity* problem, because a per-sector channel has nothing
to say about one corner of a room.

## What it should be

One lighting term, evaluated per pixel, that everything contributes to:

```
final = base × darkness(pixel) × Π tints  +  Σ additive bands
```

`darkness(pixel)` is the piece that does not exist yet. Today it is
`darkness(sector)`, hoisted out of the shader and into a per-tic script loop.

Moving it into the shader gets four things that are impossible now:

**1. Darkness that varies inside a room.** The curves already take a light
level and return a darker one. Feed them the *fragment's* light instead of the
*sector's* and the maths is unchanged — but a large room stops being uniformly
dim.

**2. Distance falloff.** Darkness deepening with distance from the viewer is a
one-line term in a shader and impossible per sector. This is the single biggest
visual gain: it is what makes a dark room feel like it has depth instead of
like the brightness slider went down.

**3. The reveal stops being an inversion.** A lift band becomes a negative
contribution to the darkness term rather than a multiply against its output.
Same picture, honest arithmetic, and it composes with anything else that wants
a say.

**4. The per-tic sector walk disappears.** DarkDoomZ currently writes every
sector every tic. The stress pass measured that as real but modest; in the
shader it is free, and it removes the mod's largest always-on cost.

## The plan

Four uniforms carry what the curves need: **mode**, **adjustment** (the
`32 × preset` the script already computes), **min light**, and the two gains.
All four are frame-global, so they belong in the per-view buffer, not the
per-draw block.

Then the curve, transcribed into GLSL exactly as it is transcribed into ZScript
today — it is the same four expressions, and they are already documented
verbatim in `DarkDoomZ.zs` with the original as the reference.

Sky handling stays as it is: it scales the *adjustment*, not the result, which
the shader can read from a flag the geometry already knows.

Script keeps one job: deciding *what* the settings are, and writing them once
when they change. It stops touching sectors.

## What has to be got right

**The sector's own colour must survive.** Map authors tint sectors, Crazy
Colors strobes them, setpieces stain them. Darkness multiplies *through* those,
never replaces them — which is exactly what the compositor established and must
not be lost in the move.

**Doom's light thinkers must keep working.** Blinking and pulsing sectors write
`lightlevel` at up to 35Hz. The current design survives them by only writing
light for sectors something asked about and handing the rest back. In the
shader this stops being a hazard at all: the fragment reads whatever the sector
currently is, thinkers included. That is a genuine simplification and the
strongest argument for the move.

**Nothing may regress.** Eight modes, eight levels, pre-gain, post-gain,
min-light, sky scaling, colour drain. A rewrite that loses one of them is a
downgrade wearing a new coat.

## Cost, honestly

Two or three sessions. The GLSL is small — the curves are four expressions —
and the plumbing is the same four touch points the sweep uniforms already
proved out. The risk is not the code, it is the **tuning**: every existing
darkness setting is calibrated against a per-sector multiply, and the same
numbers through a per-pixel term will not feel identical. Expect to re-taste
all eight levels.

## When to decide

**After the reveal has been played with, not before.** If per-pixel reveal
feels as good in a headset as it does on paper, that is the evidence this
rewrite is worth it. If it does not, the *reason* it does not will change what
the rewrite should be — and that reason is worth more than this document.
