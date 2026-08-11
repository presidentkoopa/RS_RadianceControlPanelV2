# Peaks and valleys: making the four channels move

*The glow varies per pixel vertically and is dead flat horizontally. This is
the spec for the missing axis. Confirmed against the engine source, not from
memory — file and line references are real.*

---

## 1. What is actually wrong

A wall glow fades beautifully from the floor line upward and is **the same
height everywhere along the wall**. `main.fp:838` computes

```glsl
float botfrac = glowdist.y / uGlowBottomColor.a;
```

`glowdist.y` is the fragment's distance from the plane — vertical, per pixel,
smooth. The reach it is divided by, `uGlowBottomColor.a`, is one number for the
whole surface. So the band has a perfectly straight top edge, forever.

The shader already says this out loud, at `main.fp:784`, in the comment
explaining why sweep recolour exists:

> Glow already varies per pixel VERTICALLY... Horizontally it could not vary at
> all, because the colour arrives as one value for the whole surface.

Recolour solved that for *colour*, by letting a travelling band overwrite it.
Nothing solved it for **shape**.

### And the thing that looks like it should already do this, doesn't

The lanes have an animation system — `animMode`, `animLength`, `animDepth`,
`animSharp`, `animPhase` — and it explicitly describes a travelling crest:
each sector's phase offset by where it sits, so a wave moves through the map.

But it is `AnimFactor(sec, mapCentre)`, evaluated **once per sector per tic**,
and it feeds Intensity. A room is one value. What it produces is rooms taking
turns, not peaks and valleys. It is the same granularity problem the darkness
rewrite is about, in a different channel.

---

## 2. What to build

One extra term, per fragment, that modulates the glow's **reach**:

```glsl
float u    = waveDistance(pixelpos);              // world-space scalar
float w    = 0.5 + 0.5 * sin(u / len + timer * spd + phase);
w          = pow(w, sharp);                       // narrow the crest
float mod  = 1.0 + depth * (2.0 * w - 1.0);       // [1-depth, 1+depth]
float reach = uGlowBottomColor.a * mod;
```

and then the existing block, unchanged, reading `reach` instead of
`uGlowBottomColor.a`.

**Reach, not brightness.** Multiplying the finished contribution only makes the
band pulse brighter and dimmer with a straight edge. Multiplying the reach
makes the top edge of the glow itself rise and fall along the wall — that is
the literal peaks and valleys, and it is the thing that cannot be faked any
other way. Brightness modulation costs one more multiply once `w` exists, so
ship both as separate depth sliders and let them be used together.

**The far colour follows for free.** The corner ramp is
`mix(far, near, atten)` and `atten` is derived from the modulated reach, so the
gradient stretches and squashes with the edge without another line of code.

### The clock is already there

`StreamData.timer` (`hw_renderstate.h:188`) is a live per-frame float that the
warp shaders already animate from. Undulation needs **no new time uniform**.

### The distance function should be the sweep's

The mod already owns a shape vocabulary — ring, bar east/west, bar
north/south, shell, rising — and `GlowHandler.WaveDistanceFor` is the ZScript
half of it, deliberately kept in step with `smode` in `main.fp`. Undulation
should measure with the same five shapes and the same per-band origin logic.

That is not tidiness. It means a wave running along the floor glow and a sweep
band crossing the room can be given the same shape and origin and made to
**agree** — the sweep arrives exactly on a crest. Two systems that measure the
world differently can never be made to line up; two that share one distance
function line up by construction.

---

## 3. Where the uniforms go

Six floats: wavelength, reach depth, brightness depth, speed, sharpness, shape.
Plus four phases, one per channel.

They are **frame-global** — identical for every draw in a frame — so they
belong in `HWViewpointUniforms` (`hw_viewpointuniforms.h:16`), *not* in
`StreamData`.

This matters and it is the same argument `darkness-rewrite.md` makes for the
darkness uniforms. `StreamData` is the per-draw block; it is a fixed 64KB
buffer shared with `uFlatGlowLines[64]`, and growing it costs draw batching in
every frame of the game forever. The viewpoint block is written a handful of
times per frame. Two `FVector4` there cost nothing measurable, and the struct
has a `mPadding0` and a 16-byte-alignment assert that two vec4s keep happy.

**Consequence worth stating plainly:** this rewrite and the darkness rewrite
want the same new buffer plumbed to the same shaders. Doing them in sequence
pays that cost twice. Doing undulation first and darkness second is nearly
free the second time.

### The one per-draw bit

Floor and ceiling **time-share** `uFlatGlowColor` — `hw_renderstate.h:232`
says so, because a draw only ever covers one of them. So the shader cannot
tell which of the two flat phases to use.

`uFlatGlowPad1` (`hw_renderstate.h:239`) is already there and unused. Rename it
`uFlatGlowIsCeiling` and write 0 or 1 in `hw_flats.cpp` where it already knows
`ceiling`. Zero new per-draw space.

### Touch points

Same four the sweep and the far-colour work already proved out, plus the flats:

| piece | where |
|---|---|
| the two `FVector4` | `hw_viewpointuniforms.h` |
| uniform block + `#define` | `vk_shader.cpp`, `gl_shader.cpp` |
| the term, in three glow blocks | `main.fp:825`, `:838`, `:857` |
| `uFlatGlowIsCeiling` | `hw_renderstate.h`, `hw_flats.cpp:411` |
| cvars, menu, per-frame write | `cvarinfo`, `MENUDEF`, `GlowHandler.zs` |

---

## 4. What has to be got right

**SEAMLESS CORNERS AND WAVES ARE EXCLUSIVE, AND THAT IS THE DESIGN.**

The corner works by handing both surfaces the same junction colour *and*
matching their reach and falloff — `GlowHandler.zs:1830`, where the flat takes
the wall's coverage. Undulate the wall's reach and not the flat's and the two
edges stop meeting: every corner in the game grows a seam that moves.

Owner's call, and the right one: **it is a toggle, not a constraint.** Either
the room is bounded by continuous colour with no edge anywhere, or it is
bounded by a moving edge. Those are two different rooms and no preset needs
both at once. Waves on forces seamless off, loudly, in the menu.

The payoff is that the four phases stay four free parameters. A junction pair
does *not* have to agree, which means the wave can **travel between surfaces**:
floor crests, then wall bottom, then wall top, then ceiling. A pulse climbing
the room, out of phase offsets alone, at no cost at all. That is a better
effect than anything the constrained version could have produced, and it only
exists because the corner was let go of.

**Depth must not eat the band.** `mod` can reach `1 - depth`; at depth 1 the
glow vanishes entirely in the valleys, which is a legitimate look and a
terrible default. Clamp the slider at 0.6 or floor `mod` at something small.

**Sharpness is `pow` on a 0..1 value**, so it only ever narrows the crest and
never the trough. That is the EKG spike the existing anim modes describe, and
it is the setting that turns a gentle swell into something that reads as
machinery.

**The per-sector anim does not go away.** It does a different job — the whole
room breathing at once — and that is still worth having. But two controls both
called "animation", one per room and one per pixel, is how a menu becomes a
trap. Rename the old one to say it is per room.

---

## 5. Two bugs found while confirming this

**Sweep recolour reaches two channels out of four.** `main.fp:836` and `:849`
mix `sweepTint` into the wall glows. The flat-edge block at `:884` does not —
`gflat` is built from the far colour and used directly. So a recolour band
sweeping a room changes the walls and leaves the floor and ceiling on the old
palette. One line, same shape as the two that are already there.

**`SECTOR_SWEEP.md:289` is stale.** It states that all eight bands share one
origin and one shape, and argues at length that lifting it would cost a tenth
of draw batching. That got lifted: `uSweepBandOrigin[8]` exists
(`hw_renderstate.h:222`), the shader reads it per band inside the loop
(`main.fp:917`), and `GlowHandler.zs:1336` says so. The doc is describing a
constraint that no longer exists.

---

## 6. And the thing the sweep already does

Confirmed, since it was in question: **a band can already lower light per
pixel as it travels.** `main.fp:952`:

```glsl
else if (bmode == 3)
    color.rgb *= max(0.0, 1.0 - satten * scol.a);
```

Draw mode 3 — Crush — multiplies the finished fragment down by how strongly
the band covers it. Real travelling darkness, per pixel, no engine work
required. What snaps room to room is `gitd_ss_fxN = 2`, the *other* darken,
which is the per-sector script path through `GITD_Composite`.

Depth comes from the band colour's alpha, which is fed from the sweep's
intensity.

---

## 7. Cost

Smaller than seamless corners. The shader is about fifteen lines across three
blocks, the uniforms are two `FVector4` in a buffer that is written a few
times a frame, and there is no new per-draw data at all. The plumbing is four
files that have all been edited for exactly this shape of change twice before.

The risk is not the code. It is that undulating reach changes what every
existing coverage number looks like, so depth defaults want to start low
enough that nobody's saved config suddenly grows a wavy edge they did not ask
for. Default depth 0 — off, byte for byte — and let it be found.
