# Presets as complete environments

A preset today is 32 colours. This is the spec for a preset that is a
**place**: palette, rhythm, a sweep program, and the darkness it sits in.

Nothing here is built. No gameplay is attached — setpieces come later.

---

## 1. The machine, stated plainly

Three systems, and the useful thing is how their clocks relate.

**The glow lanes are the resting state.** 32 colours, each with its own
Duration. Durations are what turn a palette into a *rhythm* — a lane that holds
one colour for twenty seconds and flicks through three more in a second is not
a colour scheme, it is a behaviour.

**The sweeps are events, and they arrive as a BURST.** This is the part worth
internalising:

```
how often the burst happens   =  range / speed
how long the burst lasts      =  sum of the gaps  (tics / 35 = seconds)
```

The gaps are measured in **tics, not distance** — band N arrives exactly
`gap/35` seconds after band N−1 no matter how fast the sweep travels. So the
eight sweeps are always a tight cluster, and `range / speed` decides how long
the silence is between clusters.

| range | speed | period |
|---|---|---|
| 2048 | 260 | 8 s |
| 2048 | 20 | 1 m 42 s |
| 4096 | 15 | 4 m 33 s |
| 8192 | 5 | **27 minutes** |

So a ten-minute loop is comfortably reachable. That is the shape of every
preset below: *a long quiet, then something happens.*

**Darkness is the floor** the whole thing stands on. A palette means nothing
without knowing how dark the room is underneath it.

### The one blocker

Gaps cap at **210 tics = 6 seconds**, so all eight sweeps must land inside 42
seconds. That is fine for a burst and useless for a slow procession. To spread
sweeps across a long loop the cap wants raising to about **2100 tics (60 s
each)**, which allows a seven-minute spread. One number in MENUDEF and one
clamp; nothing else changes, because the gaps are already only ever read as
`gap/35` seconds.

---

## 2. The techniques

Things the three systems can do together that neither does alone.

**A waveform passing through a room.** Give consecutive sweeps different light
amounts — `+100, +40, −80, −128` — and what crosses the map is not a line, it
is an *envelope*. Surge, sag, collapse.

**Overtaking.** Per-sweep speed means sweep 3 can pass sweep 1 mid-flight.
Where they cross, the light adds — a bright knot that appears once per cycle at
a predictable place. Set 1 slow and 3 fast and the burst has an internal event.

**Agreement or disagreement.** Hue spread controls both the variety inside a
lane and how far apart the four lanes drift, because each lane takes a quarter
of the range. Narrow spread = one colour breathing. Wide spread = four
arguments.

**Stillness is a choice.** A dead grid should not shimmer. Long Durations and a
Snap transition make the glow *sit there*, so the sweep is the only thing that
moves. Most presets should be far stiller than the defaults.

**Thickness and softness set the object.** Thin and hard is a scanline —
machinery, scanning, deliberate. Thick and soft is a wash — weather, pressure,
something arriving. Same system, different fiction entirely.

**Direction is meaning.** Rising (shape 5) is heat and dread. Collapsing inward
is a countdown. A ring from map centre is impersonal; a ring that follows you
is being watched.

---

## 3. What Doom means

Doom is not fantasy hell. It is **industrial hell** — a corporate mining and
research facility that drilled into somewhere it should not have, and the whole
look is the collision of those two vocabularies:

- *Institutional*: fluorescent green terminals, amber warning lamps, grey
  concrete, rust, sodium corridor light
- *Hell*: blood, bone, fire, brimstone, flesh, marble
- *Tech*: teleporter white-blue, plasma cyan, reactor green

And its rhythm is **long silence punctuated by an event** — which is exactly
the burst-and-wait shape the sweep system already has. That is why this works.

---

## 4. The ten

### 1. BLACKOUT — the absence
Pure black, all 32 slots. **No sweep at all.** Darkness at Crush / Pure. The
one preset that is defined by what it does not do; anything travelling through
it would be a light source, and there are none.

### 2. LOW POWER — the grid is failing
*Worked in full in section 5.*

### 3. RED ALERT — containment breach
The klaxon. Short period (~12 s), so it comes round and round. Two sweeps only,
one bright red and one dark behind it, thick and soft, with a wake — a rotating
beacon rather than a scanline. Light amount high and positive on the first,
negative on the second, so the room genuinely pulses. Glow is red through
amber, narrow spread, short Durations, Flash transition. Nothing here is
subtle; that is the point.

### 4. REACTOR — coolant cycle
Acid green through bile yellow. Four sweeps, thick, slow, soft, evenly spaced
over ~40 s inside a ~3 minute period, all mildly brightening — a surge of
coolant moving through the building and away. Glow holds long on two greens
and briefly flicks to yellow, so the baseline itself breathes. Shell shape, so
it moves in three dimensions rather than sweeping the floor.

### 5. FURNACE — fire from below
**Rising** sweeps (shape 5), which is the whole idea: heat climbing the level.
Ember palette, deep red to yellow, the widest brightness swing of any preset.
Three sweeps at different speeds so they overtake each other on the way up.
Thick and very soft. Period ~90 s. Darkness deep, so the rising light is the
only thing you see coming.

### 6. COLD STORAGE — sterile and clinical
Cyan-white, almost no saturation variance, high brightness, minimal coverage.
One sweep. Thin, hard-edged, no wake, slow and steady, bar shape east-west. It
scans. Long period (~4 min) so it is genuinely an event, and the light amount
is small — this room is not dramatic, it is *inspecting*.

### 7. HELLMOUTH — no rhythm you can trust
Red through magenta with a wide spread, so the four lanes disagree. Eight
sweeps with deliberately uneven gaps and mismatched speeds — the burst has no
countable beat, and the overtakes land in different places each cycle because
drift is on. Period around 2 minutes. Thick, soft, heavy wake. The room feels
like it is breathing wrong.

### 8. TECHBASE — the facility still works
Amber and terminal-green, the two institutional colours. Regular bar sweeps,
east-west, thin, hard, evenly spaced, modest light amount, short period (~20 s)
— the readable, dependable pulse of machinery that is fine. This is the
baseline the other presets are a failure of. Deliberately the least dramatic
one in the set, and better for it.

### 9. ABYSS — pressure
Deep teal into blue-black. **One** sweep. Maximum range at minimum speed — a
single enormous shell expanding over twenty-plus minutes, so slow that you are
never sure it is moving. Very thick, very soft, tiny light amount. Long
Durations everywhere. Nothing about this is urgent and nothing about it is
safe.

### 10. NEON CHAOS — the arcade
Full 360° hue spread, full saturation, high brightness — the four lanes in
completely different colour families. Eight sweeps, all different colours,
different speeds, tight gaps, high drift, so they overtake constantly and the
crossings never repeat. Short period. This is the one that exists because we
*can*, and it earns its place by being the opposite of everything else here.

---

## 5. LOW POWER, in full

**What it means.** The grid is not dead. It is *failing*. Something down in the
plant is still trying to keep the lights on and mostly succeeding, and every
few minutes it stumbles — a surge as a system cuts in, a sag as it loses the
argument, a moment of nothing, and then back to the same tired baseline. The
horror is not the dark. It is that the dark is *scheduled*.

**Baseline.** Grey-purple, barely lit. Minimal coverage on every lane so the
glow clings to edges rather than filling anything. Low intensity, low
saturation. Long Durations and Snap transitions — a dying grid does not
shimmer, it just sits there. The four lanes almost agree: narrow hue spread, so
this reads as one failing colour rather than a scheme.

**Darkness.** Compress, at Dismal or Oppressive. Enough that the baseline glow
is doing real work.

**The event.** Four sweeps, thick and soft and slow, inside a burst of about
ten seconds, on a period of three to five minutes:

| sweep | light | what it is |
|---|---|---|
| 1 | **+100** | a system cuts in; the corridor floods |
| 2 | +40 | it holds, weaker |
| 3 | **−80** | losing it |
| 4 | **−128** | out — darker than baseline |

Then nothing, for minutes, and the baseline creeps back. The sweeps carry the
same grey-purple, with the surge a touch warmer — a filament heating before it
gives up.

**Why it works.** The 42-second burst cap is not a limitation here, it is the
design: the whole failure happens in a few seconds and the silence around it is
what makes it land.

---

## 6. What building this actually needs

A preset writes 32 colours today. To carry the above it must also carry:

1. **32 Durations** — the rhythm. Same shape as the colour table.
2. **Per-lane look** — coverage, saturation, intensity, falloff, transition and
   its speed, plus the animation block.
3. **A sweep program** — count, shape, origin, direction, range, thickness,
   softness, brightness, trail, drift, and per-sweep colour / speed / gap /
   light amount. This is the biggest new part and the one that makes a preset
   an environment instead of a palette.
4. **A darkness suggestion** — mode and level.

**Darkness should be opt-in.** A player who has spent an hour tuning how dark
their game is will not thank a palette for overriding it. One row —
*"Presets also set darkness: yes/no"* — defaulting to **no**.

**The nine generated presets stay generated.** Hue/spread/sat/val is a good
compact way to describe a palette and the customiser already edits it. What
gets added is everything *around* the palette. Blackout and Black and White
remain literal, and the customiser should grey out for them rather than
pretending.

**Open question for the owner:** should a preset also set the four lanes'
per-colour Durations, or should Durations stay the player's own? Setting them
is what makes a preset a rhythm; not setting them means a player's tuning
survives a preset change. Recommend: presets set them, and the same opt-in row
that governs darkness governs this too.
