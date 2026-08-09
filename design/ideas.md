# GITD Ideas — the fun lane

Theme: **chain reactions**. Everything below is built from parts that exist
today unless marked otherwise: the wave list (`GITD_Sweep.Fire*`, unlimited
logical waves, 8 draw slots), band scripts (`GITD_SweepAction`), reversible
setpieces (`GITD_Setpiece`, journalled), sweep marks (`GITD_SweepMark`), the
neon numeric engine (`GITD_Neon.Pop/Mark/Above/Seam`, `GITD_SeamStrip`, WG13
badges), the compositor (`GITD_Composite` — declare, never write), and the
sideloaded rotation (tiers/entropy, minibosses with lives-rings and thralls,
AI director with a roster, crits (`csh_*`), bullet time (`bt_*`),
soft-permadeath lives).

Standing orders respected throughout: **every idea is menu-gated** (a cvar and
a MENUDEF line are part of the estimate), **no actor-per-number** (billboards
are level-owned quads), **tier colour language is decided elsewhere** (ideas
say *a colour from the tier palette*, never which one), and engine-level ideas
state their cost.

Two ranking biases, by direction from the owner:

- **Strip, don't stack.** The miniboss mechanic is conceptually right and
  practically bloated (arrays of orbiting FX actors, thrall trails, flag
  juggling). An idea that reduces a concept to its arcade kernel —
  announcement, presence, payoff — outranks an idea that adds a layer.
- **No new verbs.** It's still Doom: shoot, kill, move, with a fun weapon
  system and creative monsters. Ideas that make that loop *glow harder* rank
  above ideas that ask the player to learn something new. Where an idea below
  flirts with a new verb, it says so and takes the rank hit.

Effort: S = an afternoon, M = a few sessions, L = real engine work.
Wow/effort: 1–5, where 5 = "players will screenshot it and effort was small."

---

## 1. Chain reactions

### Overload — kill inside the ring and the ring stays alive
Every kill fires a thin ring from the corpse (`FireFrom`, fx = MARK). If you
kill a *marked* monster while its mark is fresh (`GITD_SweepMark.Age < ~45`),
that corpse fires the next ring — slightly faster, slightly brighter, and the
chain count pops over the corpse. Miss the window and the light just… dies
out, visibly, the ring fading into the dark. The combo system stops being a
number in a HUD corner and becomes a wave you are physically keeping alive by
hunting along its edge. The player's eye learns to read "who is marked" as
"who is next," which is the whole game loop rewritten in light.
**Built from:** `WorldThingDied` + `FireFrom` + `GITD_SweepMark` +
`GITD_Neon.Pop`. No new engine surface at all.
**Effort:** S. **Wow/effort: 5.** This is the flagship chain — cheapest
mechanic in the doc relative to how it changes play.

### Corpse Circuit — the chain that brings one back promoted
The grown version of the user's seed. Each chain link (kill-inside-the-window,
above) stamps a small floor mark on the corpse it fired from. At N links
(menu: 5 default), the *first* corpse in the chain gets the ceremony: a
vertical `GITD_Neon.Seam` (BBFL_VOID — a hole with a burning rim) opens over
it, driven 0→1 over ~20 tics, a rising sweep (`SHAPE_RISING`) climbs the
sector, and the monster comes back **one tier up** — re-spawned via the tier
mod's ladder (or `tierBoost`-style health/speed until RS_Tier is reachable),
shaded from the tier palette. The player made this happen and watched the bill
arrive: chains are power AND debt. Great risk/reward — long chains feel
amazing and then the room answers.
**Built from:** Overload's bookkeeping + `GITD_Neon.Seam` + `ResizeBillboard`
easing + `SHAPE_RISING` + a spawn. The seam-as-door and the signed rising
shape already exist.
**Effort:** M. **Wow/effort: 5.** The signature moment of the mod.

### The Second Bell — rings that double when they reap two
If a single ring's wavefront passes over a monster that dies during that same
pass (band strength > 0.5 at time of death), the ring **doubles**: range and
brightness up, and a "x2" pops at the doubling point. Doubles can double.
Players start leading kills into an incoming ring on purpose — shooting a
monster *because the light is about to arrive* is a new verb.
**Built from:** `WorldThingDied` + checking `GITD_SweepMark.Age(thing) == 0`
+ cancel-and-refire a bigger wave from the same origin (waves are cheap and
unlimited).
**Effort:** S. **Wow/effort: 4.**

### Ping-Back Elites — the monster that answers you
An elite (miniboss controller already picks candidates) carries a standing
rule: when hit, it emits its own short sonar ring — fx = ALERT — that **wakes
everything it touches**. Shoot the wrong silhouette in the dark and you watch
your mistake propagate outward as a visible wave crossing sleeping monsters
one by one. The chain reaction here is aggro itself, and it is legible: you
see exactly which monsters the ring reached, so the ambush you caused never
feels random.
**Built from:** `WorldThingDamaged` + `FireFrom(fx: FX_ALERT)` on a cooldown.
**Effort:** S. **Wow/effort: 4.**

### Death Marks — your own deaths, still on the floor
Every place the lives system catches you (soft-permadeath sets you to 1hp and
teleports you out; the column of flame stands where you fell), GITD burns a
permanent floor mark: attempt number in LED digits, in a dimmed colour, plus
a slow, dark, collapsing micro-ring that breathes around it every thirty
seconds or so. Walk past the site of attempt 3 on attempt 4 and the floor
remembers. Because soft-permadeath respawns without a map reload, persistence
is free; a small handler keeps the list across the session. Cap the count like
the perm-badge list does. **Leave the payload id after the mark reserved for
Death Pool** (moonshots, below) so the upgrade later is a data change, not a
migration.
**Built from:** watching player "death" (health==1 + Buddha event, or the
lives cvar ticking down) + `GITD_Neon.Mark(permanent)` + a tiny looping
`Fire`.
**Effort:** S. **Wow/effort: 4.** Cheap, and it gives the run a memory.

### Secret Echo — secrets that ping other secrets
Finding a secret already triggers a sweep (`gitd_ss_trigger`). Give that wave
a job: gold sonar ring from the secret's sector; any *other* secret sector it
passes gets a faint standing shimmer for a few seconds (declared brighten +
tint through the compositor — no writes). It doesn't mark the spot, it lets
you glimpse a glow through a doorway and think "there's another one, that
way." Sonar becomes a rumour rather than a map.
**Built from:** secret trigger + a `GITD_SweepEffect` whose `SectorPass`
checks `sec.IsSecret()`.
**Effort:** S–M (the "glimpse, don't mark" tuning is the work).
**Wow/effort: 4.**

### Infection Chain — the mark that jumps
A named band script ("Contagion") for setpieces and elites: any monster the
band marks becomes a carrier for ten seconds; if a carrier gets within touch
range of an unmarked monster, the mark jumps (fresh `SweepMark.Set`, tiny
one-metre ring drawn for legibility) — and carriers take bonus crit damage
from behind (`csh_backstab_factor` already exists; this just makes marked
targets the thing backstabs want). Herding marked monsters into packs becomes
play.
**Built from:** `GITD_SweepEffect.ActorPass` + a per-tic carrier scan (bounded
— carriers only, not the whole thinker list) + tiny `Fire` calls.
**Effort:** M. **Wow/effort: 2.** Demoted on the strip-don't-stack rule: this
is a layer on the mark system, and herding is half a new verb. Keep the idea
on the shelf; build it only if a captain design pulls it in.

---

## 2. Captains — the miniboss, stripped to its kernel

The miniboss mod proves the *concept*: a named enemy with lives, presence,
and an entourage is the best thing in a room. It also proves the cost: every
piece of its presentation is an actor — orbiting life pips, invuln shells,
thrall trails, dozens of thinkers warped every tic. GITD's whole thesis is
that presence is a *lighting* problem. A captain moment has exactly three
beats — you learn it's here, you feel where it is, you get paid when it dies
— and each beat is one call into machinery that already exists. Everything
else in the miniboss controller is bloat these three replace.

### The Herald — announcement
The moment a captain first sees you, the room's light *funnels toward it*:
one inward-collapsing ring (`Fire`, direction inward, origin on the captain,
fx = DARKEN on the leading band) converging on its body over about a second,
ending in a single flare and its name popping once in BB_TEXT above it
(`mbosnams`-style names already exist). An explosion in reverse — the light
gets sucked to where the threat is, so your eye arrives before the first
shot does. No horn sting, no screen text, no orbiting actors: the
announcement is that the room itself points.
**Built from:** one `FireFrom` with `dir = -1` + `GITD_Neon.Pop`. Zero new
systems.
**Effort:** S. **Wow/effort: 5.**

### Aura — presence and health bar in one
The captain's presence is a standing tint on the sectors around it, declared
through the compositor every tic (which is exactly what the compositor was
built for), with a radius **proportional to its remaining health**. Fresh, a
captain owns half the arena and you're fighting inside its colour; wounded,
the aura contracts until, at the end, it's a skin-tight rim — so *how close
the fight is to over* is readable from across the room without a single HUD
element or FX actor. Lives (the miniboss lives system, kept but slimmed) are
a one-line LED numeral riding above it, restrung on each life lost — one
attached billboard replacing the entire orbiting-pip array.
**Built from:** a per-tic sector-radius declare (`Tint`/`AddLight`) +
`GITD_Neon.Above` + `SetBillboardText`. This *deletes* actors from the
current design rather than adding any.
**Effort:** S–M (the radius falloff tuning is the work).
**Wow/effort: 5.** The flagship strip-job: the whole miniboss presentation
kernel, rebuilt as light.

### The Board Clear — payoff
A captain's death is the one moment allowed to be loud. The aura collapses
into the corpse as a fast inward ring; on impact, one outward Death-Ping
fires, and every surviving member of its pack dies as the ring reaches them
— staggered pops marching outward, each with its own small badge, ending in
the captain's obituary plaque (name, damage, time-to-kill) burned into the
floor. The arcade board-clear, delivered entirely by the wavefront's arrival
order, so the payoff literally radiates from your kill. If a lockdown is
running, `SweepOut` fires from the same corpse — the arena and the entourage
un-become together.
**Built from:** two `Fire` calls + `ActorPass` kill-on-arrival + the
Obituary Plaque (below) + `GITD_Setpiece.SweepOut`.
**Effort:** S–M. **Wow/effort: 5.**

### On lives and invulnerability — keep the count, cut the ceremony
The miniboss invulnerability phase (timer, flag save/restore, shell actors)
is the bloat that keeps the concept from being arcade. Strip it to: losing a
life fires one bright outward ring that *pushes the fight back* (fx = SLOW,
short range) — a beat of breathing room that reads instantly — and the LED
life numeral ticks down. No invulnerable window at all: the pause **is** the
ring. Death-with-lives-remaining becomes a rhythm the player can count,
which is what a captain fight should be.
**Built from:** `FireFrom` + the Aura's numeral. Deletes the whole
invuln-flag state machine.
**Effort:** S. **Wow/effort: 4.**

### THE SEAM CAPTAIN — the flagship: a boss you disassemble
The showcase fight, and the likely top-shelf item once the Coin-Op exists.
Seam reveals tear open in a geometric ring — three vertical cuts arranged
around one master cut in the arena's centre. Out of the outer seams: three
elites. Out of the master seam: a high-tier captain wearing **all three of
their affixes at once**. You fight the captain by *disassembling* it: kill
an elite and a strip-wave fires from its corpse to the captain, visibly
carrying the theft — when the band arrives, that affix is gone, the
captain's shade loses that colour, and the elite's seam **goes dark**. The
arena is the fight's UI: three burning cuts in the world, each in its
elite's affix colour with the affix glyph floating over it, and one glance
at which seams still burn tells you exactly what the captain still is.
Order is the grammar — kill SHELLED first and the captain becomes
damageable; save SWIFT for last and the endgame is fast; the player
composes the fight by choosing the kill order, using no verb but shooting.

**The affix set — lean on purpose (four specced, two optional).** Grounded
in what the rotation already proves works (Universal Entropy's stat
touches, the miniboss kernel), each claims a colour *from the palette
authority, decided elsewhere*:

| Affix | Carrier effect | Captain inherits |
|---|---|---|
| SWIFT | speed multiplier (the UE pattern) | same |
| SHELLED | damage factor down | optionally unkillable until stripped (cvar) |
| BURNING | a slow hurt-pulse ring off its body (`FireFrom`, tiny range) | same |
| SUMMONING | periodic spawn odds — the thrall kernel, slimmed to a number | same |
| VAMPIRIC (opt.) | heals off damage dealt | same |
| UNSEEN (opt.) | dims its own sector via the compositor | same |

**The pieces, priced separately:**
- *Seam arrangement* — ring of vertical `Seam`/`GITD_SeamStrip` cuts +
  glyph billboards, each bound dark-on-death to its elite: **S**; every
  part exists today.
- *Affix implementations* — stat touches in the Universal Entropy pattern,
  one small class each: **M**.
- *Inheritance* — captain's live affix set is the union of its living
  elites', recomputed on each elite death; optional Buddha-until-stripped:
  **M**.
- *The strip-wave moment* — `FireFrom(corpse)` + a band script whose
  `OnActor` delivers the strip when the band reaches the captain, seam
  darkened in the same tic: **S**, and it is the kill-wave doing narrative
  work — the fight's best single beat for the least code.
- *Delivery* — the ambush framework's parameterized Launch (other lane, in
  motion) with a difficulty and reward tag; Coin-Op wiring later: **S** on
  top of that framework.

**Effort:** M overall once the ambush framework lands; nothing engine-level
anywhere in it. **Wow/effort: 5.** Three elites, three seams, one captain,
one glance — the miniboss concept with every gram of bloat cut, and the
arena itself as the health bar.

---

## 3. Waves as gameplay

### Lights Out — sonar is the game
A curated menu preset, one toggle: DarkDoom floor near black, Blackout glow
preset, ambient sweep OFF, and the trigger-pull sweep (rising edge, origin =
your last shot) becomes the **only light in the world** — fx = SONAR, rooms
revealed to natural brightness and decaying back over `gitd_ss_sonar_fade`.
Every shot buys you a snapshot of the room; the shotgun becomes a camera
flash; reloading in the dark is terror by design. Monsters between flashes
are sound and muzzle-flare only. Every part of this exists as a menu setting
today — the idea is the *bundle*, tuned (fast band, long fade floor, short
range) and shipped as one switch called LIGHTS OUT.
**Built from:** existing cvars + one preset-writer.
**Effort:** S. **Wow/effort: 5.** The cheapest total-conversion in the doc.

### The Closing Wall — a countdown you fight back
Arena encounter: a collapsing ring (`gitd_ss_direction` inward) of darkness
with a slow-wake (fx = DARKEN + fx = SLOW on the band behind it) shrinks
toward the arena centre — but the position is **driven by kills**
(`gitd_ss_drive`), so every kill knocks the wall back out. Nothing on screen
says a number; the room itself is the timer, and the band's distance from
your ankles is the score. Stall and the dark closes over you (monsters in
the dark ring are slowed too — being caught is survivable, blind, and
mean). Clear the quota and the wall retreats out of the arena as a
brightening wave.
**Built from:** driven waves + inward direction + per-band fx. The drive
plumbing exists; the encounter wrapper is the work.
**Effort:** M. **Wow/effort: 5.**

### Lockdown encounters — a designer's kit (the framework is another lane's; these are the plays)
What makes a lockdown *great* is that the wave train is a **program the player
can read**: band colours announce intent in order, and the spacing between
bands is the difficulty dial. The kit:

- **The Breath (canonical form).** Four bands, tics apart: darken → spawn →
  promote → restore. The player learns the grammar in one encounter: when the
  third band passes over live monsters, they've let it linger too long.
- **Escalation.** Each subsequent lockdown on a map adds one band or shortens
  `subGap` by 15%. Never both. The train audibly "tightens" across a level.
- **The Fake-Out.** A full red alarm train sweeps in… spawnOdds 0. Nothing.
  The lights come back. The *next* one is real. Sell it with identical
  colours — dread is a resource and this mints it. (Menu-gated: some players
  will hate it; those players are wrong but paying customers.)
- **The Reversal.** A lockdown you can end early: kill the warden elite
  (Ping-Back elite, above) and `GITD_Setpiece.SweepOut` fires **from its
  corpse** — the arena un-becomes itself outward from your kill. Where you
  land the killing blow decides where the light returns first.
- **The Reward Pop.** The restore band carries the receipts: total damage as
  one big WG13 badge at the arena centre, and pickups spawned in the restore
  wave's wake (spawnOdds on the *outbound* setpiece), so loot arrives as the
  light does.
- **Fought-out, not waited-out.** Never gate the exit on time. Gate it on the
  Door Toll readout (numerics, below) so the lock is a number the player is
  actively driving to zero.

**Built from:** `GITD_Setpiece` + band scripts + `SweepOut` origin choice —
all existing.
**Effort:** each play S once the framework lands; the kit as a set M.
**Wow/effort: 4.**

### Undertow — herding with the wake
A hunting tool: a slow ring with a very long wake (`gitd_ss_trail`) and
fx = SLOW bound to the wake side. Monsters caught in the wake wade as if
through water while the bright leading edge stays honest. Fire it *past* a
pack and they're held in the trailing light for seconds — a net made of a
lighting effect. The no-new-verb reading is the right first build: it
belongs to **captains and lockdowns** (the room casting the net at the
player's escape route), not to the player's hands; a player-carried
"Undertow charge" pickup is the optional later version and takes the
new-verb rank hit if built.
**Built from:** trail + per-band fx, both existing.
**Effort:** S. **Wow/effort: 4** as an encounter tool; 3 as a pickup.

### Heartbeat — the world is your health bar
Drive = health: a dim ring stands around you at a radius proportional to your
health, and `gitd_ss_health_speed` already makes the ambient sweep hurry as
you weaken. Compose them: healthy, the ring is a wide, calm horizon you
barely notice; at 20hp it's a tight, fast, red-shifted collar strobing at the
edge of your vision, and the room outside it is declared darker (compositor
delta). No HUD element moves — the *geometry of light around your body* is
the readout. Menu-gated hard (some will find it oppressive; that's the
point).
**Built from:** driven waves + `AddLight` deltas.
**Effort:** S–M. **Wow/effort: 4.**

### Time Sculptor — bullet time repaints the level
When bullet time engages (the `bt_*` mod owns the dilation; its state is
readable), GITD fires a low-priority sweep from the player that travels at
*world* speed — which under dilation reads as gorgeous slow expansion — 
recolouring glows (fx = RECOLOR) into a desaturated "dilated" palette and
sonar-revealing as it goes. The world drains to monochrome at the speed of
thought, radially, from you. When time resumes, a restore wave snaps back
out at full speed — the colour slams home like a bass drop. Pure spectacle
riding a mechanic another mod already paid for.
**Built from:** a `GITD_Setpiece` (envDesat, revert via SweepOut) + a watcher
on the bullet-time state.
**Effort:** M (the watcher and not-fighting-the-shader is the work).
**Wow/effort: 4.**

---

## 4. Numerics / readouts

The rule from the combo ledger generalises: **a number deserves to exist in
the world when the world is what earned it.** Ledgers that pass that test:

### Door Toll
A lockdown door carries a standing LED readout (BB_SEGMENT, vertical,
attached to the door's sector edge): monsters remaining. Every kill inside
the arena ticks it down *visibly, from across the room*, and at zero it
flares once and the seam over the doorframe opens. The lock is a number the
player drives. No actor: one persistent billboard, restrung with
`SetBillboardText`.
**Built from:** `AddBillboardPersistent` + kill watcher.
**Effort:** S. **Wow/effort: 5.** This is the readout that makes lockdowns
feel fair.

### Obituary Plaques
When an elite or miniboss dies (the miniboss mod names them — `mbosnams`),
a permanent floor plaque appears where it fell: name in BB_TEXT, damage it
took, time-to-kill in seconds. LED for the numbers, typeface for the name —
exactly the split the numeric engine argues for. A long session turns the
map into a trophy hall you walk back through. Cap like perm badges.
**Built from:** `WorldThingDied` + `GITD_Neon.Mark(permanent)` + the damage
accumulator that already tracks per-monster totals.
**Effort:** S. **Wow/effort: 4.**

### The Debt Ledger
The combo ledger counts what you gave; the debt ledger counts what you took.
On leaving a room (sector-group transition, or simply every exit line you
cross during a lockdown), the damage you *received* there is burned into the
floor at the threshold, small and un-celebratory, in a cold colour. Zero is
not printed — a clean room simply says nothing, and the absence becomes the
brag. Speedrunners will screenshot corridors of silence.
**Built from:** `WorldThingDamaged` (player as victim) + `Mark`.
**Effort:** S. **Wow/effort: 3.**

### Milestone Monuments
Every 100th kill plants a permanent monument where it happened: the padded
number, full-size WG13 badge, opened once and left standing (linger = stay
already exists). Your route through the level acquires mile-markers; on
death, the walk back is punctuated by your own history. Pairs with the
lifetime-total-on-death badge the combo system already promises.
**Built from:** kill counter + `Spawn13` with linger 2.
**Effort:** S. **Wow/effort: 3.**

### Overkill Receipts
On kill, if damage dealt exceeded remaining health by 2x or more, the badge
that pops is the *overkill* amount at large scale — the number you wasted.
Crit kills (the `csh_*` mod already decides what a crit is) pop with the
badge's "big" size. Colour stays with the palette authority. Teaches ammo
discipline through vanity alone.
**Built from:** `WorldThingDied` damage bookkeeping (last-hit amount vs
health), `BadgeSize(big)`.
**Effort:** S. **Wow/effort: 3.**

### The Chain Ledger
Overload's chain count deserves the full ceremony: while a chain is alive,
one billboard rides the most recent corpse showing the link count; when the
chain dies, that number pops as a badge *and* the longest-chain-this-map
lives as a small standing readout by the exit door. Best-chain is exactly
the kind of number arcades put on the wall.
**Built from:** Overload + `Above`/`Mark`.
**Effort:** S (on top of Overload). **Wow/effort: 4.**

---

## 5. Pure visual identity

### Muzzle Ripples
The trigger-pull sweep, tuned to identity: hair-thin, very fast, short-range
ring from your last shot, barely brightening — a ripple on the world's
surface per pull. In a firefight the room shimmers concentrically around
your aggression. It's the mod's signature idle animation, and it's already
in the menu — this is a tuning preset with a name, not code.
**Built from:** existing trigger + origin cvars.
**Effort:** S. **Wow/effort: 4.**

### The Coronation
Whenever anything is promoted (Corpse Circuit, setpiece tierBoost, the tier
mod's own elevation), the promotion gets staging: a one-sector rising sweep
(`SHAPE_RISING`) climbs floor-to-ceiling around the monster while the sector
brightens bottom-to-top, and a hairline seam opens beneath it for the
duration. Promotion stops being a stat change you infer and becomes an event
you interrupt — shootable, mid-ceremony, if you're fast.
**Built from:** `Fire(SHAPE_RISING)` scoped tight + `Seam` + compositor
deltas.
**Effort:** M. **Wow/effort: 4.**

### Ember Field
Corpses cool. Each death leaves a small floor glow that decays from the kill
colour to near-black over ~60 seconds (billboard alpha ramp; the perm-cap
pattern keeps the budget honest). After a big fight the room reads as a
field of dimming embers — you can *see how recently* the violence happened,
everywhere, at a glance. Old battlefields go cold behind you.
**Built from:** `AddBillboard` with life + `SetBillboardAlpha` ramp.
**Effort:** S. **Wow/effort: 4.**

### The EKG Room
The lane animation system already does the sharpened travelling crest. Add
one API: `GITD_Lane.Pulse()` injects a single extra crest into a lane's
animClock. Call it on player damage. The room's ambient streak *skips a
beat* when you're hit — subliminal, uncanny, and free of any HUD flash.
**Built from:** a small addition to `GITD_Lane` (script only).
**Effort:** S. **Wow/effort: 3.**

### Two-Tone Breath
The documented brighten/darken band pairing, shipped as identity: ambient
train of two bands, one darken one brighten, long gap, so every room the
sweep crosses inhales and exhales roughly once a minute. Blackout preset
between breaths. It makes an empty map feel like it's asleep — which makes
everything else feel like waking it.
**Built from:** existing per-band fx cvars; a named preset.
**Effort:** S. **Wow/effort: 3.**

---

## 6. The Coin-Op — an in-world setpiece shop

Future work, seeded by the owner: the player spends currency to *buy
encounters* — real challengers, for higher-end drops. Risk-for-reward as a
purchase, made in the world, never in a menu. The shop as a whole is
L-effort and lives behind the ambush framework and a currency decision, but
almost all of its **presentation** is made of parts GITD already owns, and
several pieces are worth pulling forward on their own. The register: insert
coin, fight thing, take prize. Nothing in it may add a verb — you browse by
walking and you buy by shooting. The top shelf is already designed: **the
Seam Captain** (captains section) is the "real challenger" tier this shop
exists to sell, and the minigame setpieces (next section) are its novelty
row.

### The Storefront — a seam in the wall that knows you're there
The shop is a place you find, not a menu you open: a hairline vertical seam
in a wall (`GITD_Neon.Seam`, BBFL_VOID — a hole with a burning rim), closed
to a thread until you're within a few metres, then widening
(`ResizeBillboard` easing) into a doorway-shaped slot of dark with the wares
glowing inside. Walk away mid-browse and it narrows behind you. A pool of
floor glow (flat billboard, slow alpha breathing) spills out under it so the
storefront is findable across a dark room — the only warm light on the
wall. Every part of this runs today.
**Built from:** `Seam` + proximity check + `ResizeBillboard` + a floor
glow quad.
**Effort:** S — and worth building early as the *template* for any
"place-that-reacts" presentation, shop or not.
**Wow/effort: 5.**

### Price Tags — the wares priced in world neon
Each purchasable encounter is a pedestal: a floor mark (its emblem, a
`markPayload` wgType) with an LED numeral floating above it — the price,
drawn by the numeric engine, restrung live if the price ever moves. The
player's balance (whatever currency is chosen — kills banked, chain-ledger
best, score) burns as one standing readout by the storefront seam, so
affordability is a glance: your number versus its number, both in the world,
no HUD. Unaffordable wares dim their numerals (billboard alpha); nothing is
hidden, poverty is just visibly dimmer — very arcade.
**Built from:** `AddBillboardPersistent` + `SetBillboardText` +
`SetBillboardAlpha`.
**Effort:** S. **Wow/effort: 4.**

### Insert Coin — you buy it by shooting it
The purchase action is the game's only verb: shoot the price tag. On the
hit, the numeral slot-machines down to zero over half a second (restring per
tic — the LED font is *made* for this), the pedestal emblem flares, and your
balance readout ticks down by the same animation in sync across the room.
Two numbers spinning to agreement is the whole transaction, and it is
entirely legible with zero text. A shot at a tag you can't afford gives one
dull red flicker and the price stays — the machine eating your coin,
declined.
**Built from:** `WorldThingDamaged`-adjacent hitscan detection on the tag's
position (or a thin invisible switch line), plus restring loops.
**Effort:** S–M (the hit-detection on a billboard is the only real work; a
map-placed switch special is the cheap fallback).
**Wow/effort: 5.**

### The Delivery — a countdown that collapses onto what you bought
What you paid for arrives by wavefront: a collapsing ring
(`Fire`, dir inward, origin on the pedestal) closes over three seconds with
big LED numerals — 3, 2, 1 — popping above the pedestal as it shrinks. When
the ring lands: the challenger arrives through the ambush framework, and the
room repaints to *its* colours as a setpiece sweeping outward from the
pedestal (`GITD_Setpiece`: envColor from the challenger's tier palette
entry, journal armed). The collapse is the countdown, the impact is the
spawn, the outward wave is the arena — three beats, one origin, no cutscene.
This piece is worth pulling forward *now* as the standard "something big is
about to happen here" telegraph, shop or no shop.
**Built from:** inward `Fire` + `Pop` countdown + `FireScript` setpiece +
ambush framework (other lane).
**Effort:** S for the telegraph alone; M wired to a real challenger.
**Wow/effort: 5.**

### The Repossession — buying a fight you can't win
The failure case, kept arcade. When the lives system catches you
mid-challenge (health to 1, column of flame), the challenger's setpiece
drains back out — `SweepOut` fired **from where you fell**, so the arena's
colour visibly abandons your body toward the pedestal — and the prize goes
back on the shelf with its price tag relit *higher* (interest, slot-machined
upward this time; the room charging you for the lesson). The challenger
stays, unhurried, holding what you paid for: the standing invitation to come
back with more. Your death mark (chain-reactions section) sits in its arena
as the receipt. No game-over screen does the job this does.
**Built from:** the lives-catch watcher + `SweepOut(origin: deathPos)` +
price restring + Death Marks.
**Effort:** S on top of the Delivery. **Wow/effort: 4.**

### Continue? — the buy-back
Optional topper: while the challenger holds the field, a big LED "9"
appears over your death mark and counts down once per second. Reach the mark
and shoot it before zero to buy back in — one life, the arena repaints, the
fight resumes at the challenger's current health. Let it hit zero and the
shop closes the tab: challenger despawns via its journal, prize retired for
the map. It is the arcade continue screen, rebuilt out of a floor mark, a
numeral, and the one verb.
**Built from:** Delivery + Insert Coin pieces, recombined.
**Effort:** S once those exist. **Wow/effort: 4.**

---

## 7. Minigame setpieces — a sweep replaces Doom, a sweep hands it back

The owner's seed, promoted to a category. The shape is always the same
parenthesis: **a wave sweeps the ordinary rules out, different rules run
under timer pressure, a wave sweeps Doom back in** — and it is still Doom on
either side. The setpiece journal already knows how to transform a room and
un-transform it; these extend that from *rooms* to *rules*. Everything is
menu-gated, and each minigame ends the same honest way: the return wave
crosses the arena and whatever it touches is Doom again, monster by monster,
sector by sector.

**When do they fire?** Proposed trigger conditions, tune-by-menu, any subset:

- **Chain overflow** — an Overload chain hits 8+ links: the world briefly
  can't hold the charge, and a seam opens instead of a promotion.
- **Bought at the Coin-Op** — the shop's premium shelf: minigames as
  purchasable wares, prize scaled by performance. The two systems were made
  for each other.
- **Standing on your own death mark** — return to the site of a previous
  attempt's death and hold for two seconds: the world offers redemption.
- **Perfect board-clear** — a captain killed without taking damage; the room
  applauds by dealing you in.
- **Milestone kills** — every 500th kill (the monument spawns anyway; some
  monuments are doors).
- **The director notices you coasting** — full health, full ammo, no kills
  for 90 seconds: the AI-director's health-factor logic inverted into an
  invitation.

### The framework capability first: the Stasis Journal
"A sweep removes the monsters and returns them" is the setpiece journal
extended to **live monsters**, and it deserves to be specced once, on its
own, because every minigame below leans on it. Inbound band, per
`ActorPass`: record the monster, its position and state, then put it in
stasis — `bDORMANT` + `bNOINTERACTION` + invisible, *never destroyed*, so
nothing is lost and nothing double-spawns. The return band restores each one
where the wavefront reaches it, so the room refills outward from the origin
— monsters faded back in band by band is the category's signature shot.
Edge rules: stasis monsters take no damage and count for nothing; anything
that dies mid-restore died fairly; map change calls the blunt
`RestoreEverything` path like every other journal.
**Built from:** `GITD_Setpiece` journal pattern + `ActorPass` + flag work.
No engine changes.
**Effort:** M, once, shared by everything below. **Wow/effort: 5** as
infrastructure — the visible refill alone is worth it.

### VERTIGO — the worked example: vanishing platforms over an inverted map
The headline act, as seeded. The seam opens vertically, a rising sweep
(`SHAPE_RISING`) climbs the room, and the Stasis Journal empties it. Flat
billboard tiles materialise in a climbing trail above the player — glowing
quads, WG13-family payloads, each one a platform. The map *inverts*: the
Invert wgType (import backlog — this is its purpose) repaints the world in
flipped polarity while player gravity drops low. Then the arcade essence:
**platform across the tiles, and each tile dies when your boots touch it**
— the disappearing floor, a game older than Doom, which is exactly why it
works — while a big LED timer counts down at the summit. Reach the top
prize or run dry; either way the return sweep restores gravity, polarity,
and the monsters, wavefront-ordered, while you're still falling back into
the fight.
**Two honest notes.** (1) *Platforms need native billboard collision* — an
engine feature deliberately deferred in the billboard backlog. This is the
use case that justifies it; priced below. (2) *"Invert the map"* has two
readings, and only one is scriptable today: ZScript can do **low gravity**
(per-actor `Gravity` multipliers, the player included) but not true
ceiling-walking — GZDoom's movement has no upside-down. So the physics half
is low-grav, and the *visual* half — the Invert payload plus a flipped
palette — is what sells "the world turned over." Sell it visually, cheat it
physically.
**Built from:** Stasis Journal + `SHAPE_RISING` + seam + billboard tiles +
LED timer + Invert wgType (backlog) + **native billboard collision
(engine)**.
**Effort:** L end-to-end; the choreography without collision (tiles as
markers over real geometry) is M and worth prototyping first.
**Wow/effort: 4** — priced with its engine dependency; 5 the moment
collision exists.

### The engine unlock: native billboard collision
Deferred on purpose in the billboard backlog; VERTIGO is the case that
earns it. What it takes: collidable billboards registered into the clip
tests the playsim already runs (blockmap entry or a dedicated pass in the
movement code), a solid/walkable flag in the billboard API, serialization
so a savegame mid-minigame doesn't drop the floor out from under the
player, and a cap so a runaway script can't fill the blockmap. It touches
movement code, which is the most regression-sensitive place in the engine —
budget for the audit, not just the feature.
**Effort:** L, honestly. **Wow/effort: 3 alone — but it is the key that
opens this whole category's ceiling,** and platforms are only its first
customer (cover walls, light bridges, bought barricades at the Coin-Op).

### Sibling minigames — same parenthesis, different games

**THE FLOOR IS LAVA.** The inbound setpiece swaps every floor flat to a
burning texture (`envFloorTex` — journalled, already built) and declares
the floor lethal-hot; safe islands glow as sonar-bright sectors that the
band chose (one in N, the spawnOdds pattern). Islands *cool and go dark*
one by one on a visible schedule — LED numerals over each counting their
remaining seconds — so you are always leaving. Survive to the return sweep.
The oldest playground game, run on machinery that is 90% already in the
repo.
**Effort:** M (no engine work — islands are real sectors, not billboards).
**Wow/effort: 5.**

**SHOOTING GALLERY.** The Stasis Journal clears the room; pop-up targets —
flat billboard ducks in tier colours — rise from floor seams on timers,
worth more the shorter they stand. Shoot-to-hit reuses the Insert Coin
detection; scores pop as badges where the duck stood; the combo ledger
runs hot the whole time. Timer out, return sweep, and the prize scales
with the count — straight into the Coin-Op's currency. It is Doom's one
verb, distilled to carnival purity.
**Effort:** M. **Wow/effort: 4.**

**PELLET RUN.** The map dims to Blackout; a breadcrumb trail of small floor
glows (billboard dots, proximity-collected — no engine collision needed,
touching a *position* is a distance check) threads the corridors of the
real map. Eat the trail before the timer; one hunter — a single restored
monster, promoted, sonar-pinging its own position every few seconds — walks
the maze with you. Collecting the last dot fires the return sweep from
wherever that dot was. Doom's own level geometry is the maze; the mod just
paints the dots into it.
**Effort:** M. **Wow/effort: 4.**

**BULLET GARDEN.** The one sibling that needs no new collision at all:
projectiles are actors and always were. Monsters go to stasis; emitters at
the arena edges fill the room with slow, glowing, patterned projectiles —
rings, fans, spirals in lane colours — and the game is *moving*: survive
the garden until the timer. No shooting required, nothing to shoot — a
pure read-and-weave interlude that makes the player's feet the hero, then
hands them back their shotgun with the room refilling around them.
**Effort:** M. **Wow/effort: 4.**

**SIMON SECTOR.** The room's sectors flash a colour sequence through the
compositor — three, then four, then five — and you answer by shooting the
sectors in order (hit detection per sector centre, Insert Coin tech).
Each correct round brightens the room one step; a wrong answer fires the
sequence *as an ambush train instead*, one band per colour you failed to
remember. Memory as a wager, in a game that is otherwise pure reflex.
**Effort:** S–M. **Wow/effort: 3.**

### THE GUIDE LIGHT — ride the only light in the world
The level drops to true black — not DarkDoom-dark, *black* — and one warm
pool of light stands on the floor, and it knows the way. Stand in it and it
travels: toward the red key, then the blue, then the exit, at walking pace
across the real map; step out and it stops (or, crueller menu setting,
*shrinks* until you return). You ride the only light in the world through
the dark, and everything it touches is briefly, dangerously visible —
including you. Each objective reached is a beat: the spot flares, collapses
to a ring, pops the objective's badge, and sets off again. Arrival at the
exit gets the full ceremony in this system's language: the spot collapses
inward to a point, the return sweep fires *from that point*, and the level
relights outward as the exit seam opens. The fail state (timer variant, or
the light's radius reaching zero) is the inverse: the light dies where it
stands, the level relights all at once — and everything in it is awake and
marked, and knows where you are.
**The honest hard part is seeking.** GZDoom has no navmesh — but the ambush
lane is already building `GITD_RoomSense`, a sector-adjacency BFS flood-fill,
and a BFS **with parent pointers kept is sector-level pathfinding**: flood
from spot to objective across passable boundaries, then walk the spot along
the chain of sector centerspots. Flag for the master session: keep RoomSense
general — this mode is its second customer, not a fork.
**What's honestly findable:** keys (iterate the level for `Key`-class
actors), exit lines (iterate `level.lines` for exit specials), secret
sectors. *Not* findable: script-driven exits with no exit special — fall
back to seeking the farthest unvisited room and say nothing.
**The spot itself:** one invisible actor carrying an `AttachBillboard` floor
glow — and this is the natural home of **Ghost Walk**, the unimported v1
wgType whose name already describes the mode; this mode is a concrete
reason to move that import up the backlog.
**The dials (MORE OPTIONS, as ever):** wait-or-shrink when unattended;
travel speed; pool radius; monsters present in the dark versus swept to
stasis; timer on or off; and what the light does to a monster that steps
into it — *it sees you*, or *it burns*. Those last two are different games
sharing every line of code.
**Built from:** Stasis Journal + RoomSense reuse (in motion, other lane) +
`AttachBillboard` + Ghost Walk import (backlog) + Blackout preset.
**Effort:** M riding RoomSense; L only if built standalone.
**Wow/effort: 5** — the strongest single image in the category after
VERTIGO, and cheaper than it.

---

## 8. Engine-unlocked moonshots

We own the engine, so these are real options — priced honestly.

### Multi-Origin Waves (the constraint-lifter)
Today all eight drawn bands share one origin and shape (documented GPU
constraint: another `vec4[8]` in a fixed 64KB StreamData, ~10% draw batching
cost, permanently). The moonshot is not "pay it" but "pay it only when
used": a second, small uniform block bound solely when a multi-origin frame
is live, so the cost exists only in frames that need it. What it buys is the
whole next tier of spectacle: your trigger-ripples visibly crossing a boss's
shockwave, two lockdown waves converging from opposite doors, Second Bell
doubles drawn as their own rings mid-flight.
**Built from:** `hw_drawinfo.cpp` + `main.fp` + the existing slot allocator
(which already ranks waves by priority).
**Effort:** L. **Wow/effort: 3** — but it multiplies the wow of half this
document.

### Interference (needs multi-origin)
Where two drawn bands overlap, add constructively in the shader: bright
standing nodes where wavefronts cross. Then the encounter: two emitters at
arena ends, and monsters standing in a node when the crest passes take the
mark. The player is doing wave physics with their feet. Shader cost is a few
ALU ops once multi-origin exists.
**Effort:** M after multi-origin. **Wow/effort: 4 (conditional).**

### Death Pool (the reserved wgType)
The payload Death Marks holds space for: a dark liquid glow that spreads
from a death site, drawn in the flats branch with a metaball-style union so
neighbouring pools **merge** instead of overlapping as quads. Player death
sites feed pools; heavy fights flood low rooms with slow black shine. Needs
the progress plumbing already listed as "next" in the backlog, plus a
payload that samples several centres (per-billboard data array or a small
uniform list per pool cluster).
**Effort:** L. **Wow/effort: 4.** The single most GITD-looking image in the
doc.

### Phosphor Memory — the world remembers light
Sonar today is per-sector and forgets by timer. The moonshot: a persistent
accumulation target the band writes as it passes each *pixel*, decaying like
CRT phosphor, sampled in the light path. Everything any band has ever lit
glows faintly in proportion to how recently — wakes become true trails,
sonar becomes an actual afterimage, and walking a dark map literally leaves
the past visible. This is a render-target and a lifetime-management problem,
not a uniform: real engine work, touching the framebuffer pipeline.
**Effort:** L (the largest here). **Wow/effort: 3**, but it would be *the*
screenshot feature, and Lights Out mode would graduate from great to
unreasonable.

### The Speaking Wavefront
Text riding a band's leading edge — "LOCKDOWN" crawling along the ring as it
crosses the arena. Script-side approximation first: one flat billboard
repositioned each tic to `origin + toPlayer * wave.pos` (S, no engine, do
this regardless). Engine version bends BB_SEGMENT glyphs along the arc:
new payload variant, arc-length layout in the shader.
**Effort:** S script / L engine. **Wow/effort: 4 for the script version.**

### Regional Time — slow inside the wake, engine-true
fx = SLOW halves monster speed by touching stats. The engine version scales
*tic rate* for actors inside a band region — projectiles, animations,
gravity, everything — so a wake genuinely is thicker time, and bullet-time
becomes a place instead of a state. Cost: per-actor tic scaling in the
playsim, savegame implications, and a fairness audit (player projectiles in
the region too?). Priced for honesty: this is the expensive one relative to
how well fx = SLOW already fakes it.
**Effort:** L. **Wow/effort: 2** — listed so nobody re-litigates it later.

---

## The shortlist, if only five get built

1. **Overload** (S) — chains as living light; changes every minute of play.
2. **Lights Out** (S) — a total conversion made of existing cvars.
3. **Aura + The Herald** (S–M) — the captain kernel: the miniboss concept
   stripped to light, deleting actors rather than adding them.
4. **Door Toll** (S) — the readout that makes every lockdown feel fair.
5. **Corpse Circuit** (M) — the chain finisher and the mod's signature scene.

Waiting just behind them: **the Seam Captain** the moment the ambush
framework lands (its seam ring and strip-wave are S pieces of an M fight),
and **the Guide Light** the moment RoomSense keeps its parent pointers.

**Pull-forward pieces** worth building out of order because they serve
everything: the **Storefront seam** and the **Delivery collapse-countdown**
(S each — the universal "something is about to happen here" telegraphs), and
the **Stasis Journal** (M — the capability every minigame and half the
future setpieces will lean on).
