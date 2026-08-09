# THE EDITOR'S CUT

Adversarial pass over the design swarm's output: `ideas.md` (~50 ideas),
`glow-lanes.md` (~23), `systems-connection.md` (~14 integration packages),
`death-ping.md` (import + 5 escalations), `ambush-wiring.md` (finished code),
and the HF Captain synthesis. Roughly ninety billable ideas walked in.
**Fifteen walk out.** Everything else is in the morgue with a cause of death,
or absorbed into a survivor and credited there.

Rubric applied: still Doom (shoot, kill, move); readable in a dark room in one
glance; the Minibosses mod's ~340-actors-per-boss is the smell test; every
option earns its menu row; perf kills only where the stress doc says
pathological (it said nothing qualifies — nothing below died of perf).

One fact that reshaped the table: **the ambush framework is not a proposal.**
`zscript/Ambush.zs` exists, self-contained, inert until four wiring edits
(`ambush-wiring.md` has the exact lines). Everything that was "waiting on the
ambush lane" is now waiting on an afternoon.

---

## 1. THE SURVIVORS — fifteen, ranked

**1. Overload** — every kill fires a ring; kill a marked monster while the
mark is fresh and the chain keeps itself alive.
*Why:* the cheapest mechanic in the pile relative to how much play it changes;
the combo system rewritten as light; zero new engine surface.
*wgType:* the sweep bands draw the travelling rings; **BB_DEATHPING (3)** pops
at each link's corpse. *Effort:* S. *Depends on:* nothing — every part ships.

**2. The Seam Captain** — the HF captain synthesis, judged and **passed**: a
boss wearing three colour-coded lenders you kill in order, each lender tethered
to a burning seam in the arena instead of orbiting the boss; kill a lender and
a strip-wave visibly carries the theft to the captain; the bullet-time chain
window is a collapsing ring drawn in the world; affixes cut to four specced
(SWIFT, SHELLED, BURNING, SUMMONING) plus two optional; two archetypes only —
Puppeteer and Light-Eater.
*Verdict on the synthesis:* this is the raw concept with exactly the right
things removed. The orbiting orb-actors were the Minibosses disease and the
seam tethers cure it; the burning seams make the arena itself the boss's
health bar — one glance says what the captain still is; kill order as the only
grammar means the player composes the fight with no verb but shooting. Keep
the HF escalation curve as one cvar defaulting gentle; without bullet-time-x
loaded the chain window degrades to a plain timer ring and still works.
*wgType:* **hex field (4)** is SHELLED's glyph and the shield-skin flash —
hexagons are the universal armour language; **invert (11)** is the
Light-Eater's presence, a pool of reversed polarity walking with the one boss
that eats light; the chain window is **BB_DEATHPING (3) run backwards**
(progress 1→0 = a collapsing ring, free).
*Effort:* M once ambush is wired. *Depends on:* ambush wiring, survivor 3,
affix classes; the two imports are garnish, not blockers.

**3. The Captain Kernel** — the every-captain presentation: native promotion,
lives via an AbsorbDamage tail item (not the Buddha misfire), one BB_RING
pip billboard instead of 340 orbiters, the Herald (light funnels inward to
announce), the Aura (presence radius = remaining health), the Board Clear
(death ring that pays out in arrival order, ending in the obituary plaque),
and the lives-strip (no invuln window — the pushback ring IS the pause).
*Why:* the flagship strip-job — it deletes actors from the current design
rather than adding any, and it is the chassis survivor 2 stands on. Obituary
Plaques and the resurrected `captnams` names ship inside it; the ceiling-lean
is a Reactive row.
*wgType:* **sunburst (9)** as the Board Clear's payoff stamp under the plaque.
*Effort:* S–M. *Depends on:* tier palette authority for colours; nothing else.

**4. The Reactive page** — one routing-table menu: source → lane response ×
strength × decay; hurt-flash ships on by default and the page demos itself.
*Why:* owner-steered; the room wired to the fight; the envelope-compositor
design means it cannot fight presets, patterns, or randomise. Absorbs
combo-floor-flash, captain-ceiling-lean, bullet-time drain, the EKG Pulse()
API, and the tempo plumbing as rows and internals.
*wgType:* none. *Effort:* M for page + first four sources. *Depends on:*
`GITD_Lane.Pulse()` addition; shared sources (`GITD_Pacing`, `GITD_TimeSense`)
built once with survivor 10.

**5. Underlay** — waves ride over the lanes instead of blacking them out; a
passing band drags every lane colour toward itself and lets go.
*Why:* one deleted `ClearAll()` behind a cvar makes the mod's two flagship
systems finally coexist; no restore bookkeeping because the lanes rewrite
themselves every tic. The most musical S in the pile.
*wgType:* none. *Effort:* S. *Depends on:* nothing.

**6. The Lockdown kit on the Ambush framework** — Door Toll (the LED
monsters-remaining readout on the arena door — the thing that makes lockdowns
feel fair), The Breath, Escalation, the menu-gated Fake-Out, the Reversal
(warden elite whose corpse fires the SweepOut — the one place Ping-Back
survives), the Reward Pop, the Closing Wall re-homed as an authored
`GITD_Ambush` subclass, Undertow as a room-cast net, and the script-side
Speaking Wavefront ("LOCKDOWN" riding the band, one repositioned billboard).
*Why:* the framework is finished code; every play here is S on top of it, and
the kit is what turns the ambush from an event into a designer's instrument.
*wgType:* **square rings (7)** as the lockdown's markPayload — containment
stamped into every locked sector.
*Effort:* four wiring edits, then S per play. *Depends on:* `ambush-wiring.md`
steps 1–4.

**7. Death-Ping, import and system** — the drafted wgType 3 transcription
(six touch points, drafts already written), every corpse pings, sonar returns
ping the living, ping→sweep escalation, and the Ember Field folded in as the
ping's afterglow option so there is exactly one corpse-glow system.
*Why:* it is the ring primitive half the survivors draw with, the import is
the cheapest engine win available, and "your kills paint the room's
intelligence" is pure GITD. Its corpse-to-corpse auto-chain and seam ceded to
Overload and Corpse Circuit (see conflicts).
*wgType:* **it IS wgType 3.** *Effort:* engine S + script S–M. *Depends on:*
nothing; drafts exist.

**8. Corpse Circuit + the Coronation** — at N chain links the first corpse in
the chain gets the ceremony: seam opens, rising sweep, the monster returns one
tier up; the Coronation is that promotion staging specced once and reused by
every promoter in the mod (ambush tierup, setpiece tierBoost, tier mod).
*Why:* the signature scene — chains as power AND debt; and one promotion
ceremony instead of three ad-hoc ones. The tier ladder already exists in the
death-ping draft (`TierUp()`), so the two lanes' work merges instead of
duplicating.
*wgType:* **spiral (6)** as the wind-up mark under the promoted monster —
spiral is the universal summoning-charge glyph.
*Effort:* M on top of Overload. *Depends on:* survivor 1; seam machinery
(ships today).

**9. The Combo Ledger** — the both-stacked accumulator finished: per-monster
running combo riding the monster, lifetime total popping as the WG13 badge on
death, tier colours via the EntropyTier/RS resolver, the crit flare, RS
per-weapon combo windows, and the badge-matches-floor colour fallback.
*Why:* it completes shipping code, honours the settled Damnums coexistence
law, and is the one number system that earned its place — the world is what
earned the number.
*wgType:* **star (8)** as the crit-kill badge variant — the star is the
critical-hit language every arcade already taught.
*Effort:* S–M. *Depends on:* `GITD_Probe`; RS palette when present.

**10. The Patchbay + WorldPlayerFired** — four wave slots, each a readable
sentence (trigger → wave → effect), the shared source vocabulary with the
Reactive page, the netevent wave bus for foreign mods, FX_CHAOS and
FX_FIXTURES as new band effects, the bullet-time/grapple/director/giant_down
trigger set, `gitd_ss_timescale`, and the ~30-line `WorldPlayerFired` engine
event so per-shot triggers stop undercounting chainguns.
*Why:* MORE OPTIONS, delivered as one grammar instead of forty toggles; and
it is where a dozen small systems-doc integrations live as rows instead of
subsystems.
*wgType:* none inherent. *Effort:* M + engine S. *Depends on:* detectors from
the systems doc built per-section; the Reactive page's shared source list.

**11. Lights Out** — one toggle: near-black floor, ambient sweep off, the
trigger-pull sonar flash as the only light in the world.
*Why:* a total conversion made of existing cvars; ships now as a named preset.
The Moments container it was going to ride waits for a third curated look
(see conflicts).
*wgType:* none. *Effort:* S. *Depends on:* nothing.

**12. The map speaks** — accent walls (locked doors glow their key's colour
via the never-called `Side.SetGlowColor`), hazard floors (damaging sectors
pulse their warning via the never-called `SetSectorOverride`), and the exit
beacon (the one still room in a swimming map).
*Why:* thirty years of Doom's own colour language finally consumed; zero
per-tic cost on the walls; the single biggest legibility gift a dark game can
receive. Both dead engine channels get their first customers.
*wgType:* none. *Effort:* M (the special-classification table is the work).
*Depends on:* nothing.

**13. The Coin-Op, telegraphs first** — pull the Storefront seam (the wall
that knows you're there) and the Delivery collapse-countdown (inward ring +
LED 3-2-1 landing on the spawn) forward NOW as the mod's universal
"something is about to happen here" grammar; the shop proper — price tags,
insert-coin-by-shooting, repossession, Continue? — waits behind the currency
decision.
*Why:* the two telegraphs serve the Seam Captain, the ambush, and every
future setpiece regardless of whether the shop ever opens; the shop itself is
owner-seeded and stays alive, but nothing in it may be built before a
currency exists to spend.
*wgType:* **box window (12)** is the Storefront's widening browse-window;
**sunburst (9)** takes the paid-in-full flare when the shop lands.
*Effort:* S now, L later. *Depends on:* telegraphs — nothing; shop — currency
decision + ambush delivery.

**14. The minigame parenthesis** — the Stasis Journal (sweep monsters into
stasis, restore them wavefront-ordered — specced once, M, the category's
shared spine) + THE FLOOR IS LAVA as the opener (90% existing machinery, no
engine work, islands are real sectors). THE GUIDE LIGHT is next in the
category the moment RoomSense keeps its parent pointers — flag to the master
session: keep RoomSense general, Guide Light is its second customer.
*Why:* the owner's seed, cut from seven siblings to the two that need no new
verbs and no engine keys; the visible monster-refill alone is worth the
journal.
*wgType:* none needed (Lava islands are sonar-lit sectors).
*Effort:* M + M, then M. *Depends on:* Stasis Journal first; Guide Light on
RoomSense parents + the Blackout preset.

**15. Engine A: the sweep block moves to a frame UBO** — sweep uniforms leave
StreamData; batching *improves* ~10%, and per-band origins/shapes become free,
dissolving the one-origin-one-shape constraint that makes most scripted waves
invisible.
*Why:* last in rank, first in leverage-per-engine-hour: it un-spends the bytes
the stress test flagged (StreamData bloat cut Vulkan batching 4.4×) and it
multiplies survivors 1, 2, 6, and 10 — overlapping visible waves from
different origins is the next tier of everything above. Supersedes the ideas
doc's multi-origin moonshot outright.
*wgType:* none. *Effort:* ~two engine days + a GL/Vulkan/GLES soak.
*Depends on:* an open engine week; nothing script-side blocks on it.

**Standing repair that rides along (not a slot):** E1 flat-glow intensity
honesty — cg/fg Intensity multiplies colour, not reach — plus the
`level.isFrozen()` correctness fix in `Step()`. Both are bug fixes, not ideas;
they go into the first engine-touching session (build order step 2) on
principle: the removal of a lie outranks any feature it delays.

---

## 2. THE MORGUE

Absorbed items are marked; they live on inside a survivor but died as
line-items. Everything else is dead until it re-auditions.

### From ideas.md

- **Second Bell** — stacks a second "kill when the light says so" timing rule
  on Overload's window; two overlapping ring-timing rules cannot both be read
  mid-fight, and the lane itself flagged the new verb.
- **Infection Chain** — self-demoted by its own lane; herding is half a new
  verb; shelved unless a captain design pulls it in.
- **Ping-Back Elites** (as a general elite rule) — aggro-roulette on every
  elite is punishment noise; survives only as the Reversal's warden inside
  the lockdown kit. *(partially absorbed → 6)*
- **Death Marks** — Graveyard already plants persistent markers at death
  sites; `gitd_graveyard_glow` (one cvar, systems §10.5) lights them; a second
  marker system is clutter. Death Pool's payload id stays reserved.
- **Secret Echo** — won the secrets conflict against secret shimmer, then
  lost its slot: a rumour system for optional content while core-loop
  survivors are unbuilt. Rebuild later as a patchbay script on the existing
  secret trigger — it is twenty lines there.
- **Heartbeat (world as health bar)** — the Reactive low-health row plus the
  existing `gitd_ss_health_speed` say the same thing without standing
  furniture circling the player all game.
- **Time Sculptor** — the Reactive bullet-time drain plus `gitd_ss_timescale`
  already say "time is dilated"; a third telling of the same message.
- **Undertow (player pickup version)** — a new verb; the room-cast version
  lives in the lockdown kit. *(partially absorbed → 6)*
- **Debt Ledger** — a third floor-number system; a brag made of absence
  doesn't read; speedrunner niche.
- **Milestone Monuments** — milestone kills already pop the big WG13 badge;
  permanent monuments accumulate into exactly the clutter this pass exists to
  prevent.
- **Overkill Receipts** — a number about waste, mid-fight, in a mod already
  popping badges per kill: noise. The crit star owns the spike moment.
- **Chain Ledger** — Overload pops its own link counts; the exit-door
  best-chain plaque is furniture.
- **Muzzle Ripples** — *(absorbed)* ships as a named preset beside Lights
  Out, not a feature.
- **Ember Field** — *(absorbed → 7)* becomes Death-Ping's afterglow option;
  two corpse-glow systems would double-paint every kill.
- **The EKG Room** — *(absorbed → 4)* it IS the Reactive page's Pulse
  response.
- **Two-Tone Breath** — lost to P2 Breathe on cost, which then lost its own
  slot; the room breathes another day.
- **VERTIGO** — shelved with its engine key: native billboard collision is
  deferred on purpose in the billboard backlog, and this pass honours the
  deferral. The markers-over-real-geometry prototype may audition later. Takes
  **grid (10)** down with it; invert (11) found new work with the Light-Eater.
- **Native billboard collision** — the backlog deferral stands; its only
  surviving customer left with it.
- **Shooting Gallery** — the whole mod is already a shooting gallery; a
  carnival frame around the existing verb adds no new fun.
- **Pellet Run** — collect-the-trail is a new verb wearing Doom's clothes;
  the hunter doesn't save it.
- **Bullet Garden** — removes the only verb; a dodge interlude in a shooting
  mod.
- **Simon Sector** — a memory quiz in a reflex game; fails the one-glance
  test by definition.
- **Multi-Origin Waves (StreamData version)** — superseded by Engine A's
  frame-UBO move, which improves batching instead of taxing it.
- **Interference** — a customer of Engine A; re-audition once multi-origin
  ships; until then it is shader speculation.
- **Death Pool** — moonshot deferred; payload id stays reserved under Death
  sites and Graveyard stones; needs progress plumbing nothing shipping needs.
- **Phosphor Memory** — the largest engine item in the pile, for a
  screenshot; nothing surviving depends on it.
- **Speaking Wavefront (engine version)** — arc-length glyph layout for a
  caption; the S script version ships inside the lockdown kit. *(script half
  absorbed → 6)*
- **Regional Time** — the lane priced it 2 "so nobody re-litigates it later";
  honoured.

### From glow-lanes.md

- **P1 Drift / P2 Breathe + Heartbeat** — the prettiest of the small fry and
  the hardest kill in this file: zero new menu rows (enum additions to
  existing dropdowns), S each. Died purely of opportunity cost against
  fight-readable survivors. First recall when a session has a spare
  afternoon.
- **P3 Comet crests** — the sweep already owns the wake look; lane-side
  duplicate polish.
- **P4 Bleed dial** — exposes one constant to buy a lava-lamp screenshot;
  doesn't read mid-fight.
- **P5/E3 Flat-edge modes (Tron stairs, centre pools)** — two good images,
  but engine touches queue behind Engine A and the ping import; on parole for
  the second engine session.
- **X2 GITD_LaneAction** — the lane's own rule: build it the moment a second
  mod asks; the Reactive built-ins don't need the public hook yet.
- **X3 Secret shimmer** — unearned standing information about unfound
  secrets; lost the conflict to Secret Echo (which then also died — see
  above).
- **X5 Tempo** — *(absorbed → 4)* it is the Reactive Hurry response's
  plumbing.
- **T2 Combo floor-flash** — *(absorbed → 4)* a Reactive row.
- **T3 Captain ceiling-lean** — *(absorbed → 4)* a Reactive row fed by the
  captain source.
- **T4 Bullet-time drain** — *(absorbed → 4)* a Reactive standing row.
- **T5 Badge matches floor** — *(absorbed → 9)* one line in the ledger's
  colour resolver.
- **T6 Setpiece Moments** — premature until M1 exists; the ambush journal
  already carries its own look in and out.
- **M1 Moments / M2 shipped Moments** — the container waits for a third
  curated look; Lights Out ships as a plain preset today; capture, cycle key,
  and attract mode return with the container.
- **E2 Two-stop wall gradient** — costs the exact StreamData bytes Engine A
  exists to reclaim.
- **E4 Per-side falloff** — the lane's own rule: not until accent walls exist
  and complain.
- **E5 Glow dither** — nameless polish; batch it into the next
  shader-touching session, not the roadmap.

### From systems-connection.md

- **Minibosses wrap-mode** (announcement/life-waves inferred by watching the
  mod's orbiter actors) — coupling to the exact bloat GITD replaces; the
  native captain layer is the one path. The mod stays loadable, uncelebrated.
- **gitd_chaos global cadence** — a map-wide random strobe is the noise GITD
  exists to replace. FX_CHAOS as a band effect (patchbay fx 8) keeps the
  Crazy Colors homage *aimed*; CC's trails never touched sectors and keep
  working regardless. *(band form absorbed → 10)*
- **Richer died-event (§13.D)** — the doc killed it itself; recorded here so
  it stays dead.
- **GITD_DeathSave / LivesLedger standalone** — RS_ScoreLives/Revival own
  save and economy in the user's actual config (settled in §8); the death
  ritual becomes a default patchbay binding on the `life_spent` trigger
  (collapsing white shell + lives pop) instead of a subsystem. Build the
  standalone parts only if a GITD-without-RS audience materialises.
- **GITD_RespawnRitual** — rides a lives system deferred with it.
- **Engine C (TexMan.IsGlowing)** — an opportunistic hour, not a roadmap row;
  the fixture census approximation ships first.
- **Fixture census floor / graveyard glow / BigDoom range fraction** —
  *(absorbed → 10)* small coherence rows riding the patchbay session.

### From death-ping.md

- **Corpse-to-corpse auto-chains (§3.5)** — chains that propagate by
  geography, with no player input per link; Overload's kill-inside-the-window
  chain is the skill version. One chain system.
- **Ping seam reveal (§3.6)** — the same seam-resurrection as Corpse Circuit
  minus the player's authorship; one ceremony, and it is Corpse Circuit's.
  Its `TierUp()` ladder is salvaged into survivor 8.

### From the HF Captain concept (the parts the synthesis cut)

- **Orbiting orb-champions** — the Minibosses smell in new clothes; seam
  tethers won, and the user's loved visual (three readable colour-coded
  lenders, killed in order) survives intact without a single orbiting actor.
- **Ladder-Climber** — a phase boss every game already has.
- **Lich** — disguised anchors are hidden information; fails one-glance, and
  the hunt is a new verb.
- **Time-Thief** — attacks a meta-resource; illegible mid-fight.
- **Mirror** — punishes the only verb.
- **Berserker** — a fast monster with no puzzle doesn't need captain framing;
  the director already manufactures pressure.

---

## 3. CONFLICTS RESOLVED

1. **Reactive page vs Patchbay.** Not rivals — twins, and both ship. The
   ruling: the systems doc's shared source table (§12) is the single
   vocabulary; a player who learns "combo" on one page finds it meaning the
   same thing on the other. Shared infrastructure (`GITD_Pacing`,
   `GITD_TimeSense`, the ledger, captain tracking) is built once and exported
   to both. Reactive routes sources into lanes; Patchbay routes triggers into
   waves; neither grows the other's machinery.
2. **Five captain-adjacent designs → one stack.** Native captain layer
   (systems §2) is the chassis; Herald/Aura/Board Clear (ideas) is the
   presentation kernel on every captain; the Seam Captain (= the HF synthesis)
   is the flagship encounter on top; the ceiling-lean is a Reactive row; the
   Minibosses wrap-mode is dead. The HF doc's orbit-orbs lost to seam tethers;
   five of its seven archetypes died; the loved visual — three readable
   colour-coded lenders killed in order — is the one thing every layer of the
   stack preserves.
3. **Two kill-chain systems → one.** Overload/Corpse Circuit (player-timed
   links) beats Death-Ping's auto-chains (geography-timed links). Death-Ping
   keeps the import, the corpse ping, the sonar returns, and donates its ring
   primitive and its tier ladder; there is exactly one seam-resurrection
   ceremony and it is Corpse Circuit's.
4. **Four countdown/telegraph designs → one grammar.** The Delivery's
   collapse-countdown (inward ring + LED count landing on the event) is THE
   standard "something big happens here" telegraph, built once inside the
   lockdown kit session and spoken by the Coin-Op, the Seam Captain's chain
   window (same ring, run as a timer), the director's ASSAULT flip, and the
   captain's life-loss ring. The Closing Wall was never a telegraph — it is a
   fight — and is re-homed as an authored `GITD_Ambush` subclass instead of
   its own framework.
5. **Two combo displays → one.** The systems-doc Combo Ledger is the
   accumulator; the Chain Ledger died (Overload pops its own links); the
   milestone floor-flash is a Reactive row; badge colour fallback folded into
   the ledger's resolver.
6. **Two secret-hint designs → zero, for now.** Echo beat shimmer on
   earned-vs-free information, then lost its slot; when secrets get an answer
   it is the Echo, rebuilt as a patchbay script.
7. **Lights Out standalone vs Moments container.** Standalone preset now;
   M1 returns when there are three curated looks to contain.
8. **Two multi-origin proposals.** Systems §13.A (move the block to a frame
   UBO, batching improves) supersedes the ideas-doc moonshot (second
   StreamData block, batching pays). No contest once both were priced.
9. **Lives.** RS owns save + economy when present (the user's real config);
   GITD contributes ritual only, and the ritual is a default patchbay binding
   on `life_spent`, not a subsystem. Death Marks die to the Graveyard
   integration.
10. **Crazy Colors.** The compositor erases CC's sector strobe by design;
    the reconciliation is FX_CHAOS as an aimed band effect, not a global
    channel. CC's trails were never in conflict.

---

## 4. BUILD ORDER — the first five

1. **Overload.** S, zero dependencies, changes every minute of play, and it
   establishes the mark/ring language that survivors 2, 6, 7, and 8 all
   speak. The chain-count pop rides along.
2. **The engine session.** Death-Ping import (drafts written, six touch
   points, WG13 is the template) + the E1 flat-intensity honesty fix + the
   `isFrozen()` correctness fix. Three S items, one session; Overload gets
   its corpse-ping primitive, every flat lane gets an honest slider.
3. **Wire the ambush framework** — the four edits in `ambush-wiring.md` —
   then Door Toll, The Breath, and the Reward Pop as the first plays, and the
   collapse-countdown telegraph built here as the shared piece. This one
   session unblocks the Seam Captain, the Closing Wall, and the Coin-Op
   delivery grammar.
4. **Underlay + the Reactive starter.** Delete the `ClearAll` behind a cvar;
   ship the page with the hurt-flash row and the envelope compositor; rows
   accrete from there. The lanes and the waves stop being strangers.
5. **The Captain Kernel.** Native promotion, AbsorbDamage lives, BB_RING
   pips, Aura, Herald, Board Clear + plaque. The Seam Captain follows
   directly on steps 3 + 5, and it is the first thing the Coin-Op will ever
   sell.

Shared S-pieces to build once, noted so no lane rebuilds them: `GITD_Probe`
(survivors 9, 10), the collapse-countdown telegraph (step 3; spoken by 2, 6,
13), the promotion Coronation (survivor 8; spoken by ambush tierup and every
setpiece), and `GITD_Pacing`/`GITD_TimeSense` (4 and 10 read the same
instances). Standing cheap win from the stress doc to take with any
lane-touching session: hoist `AnimFactor`'s five cvars into `Step()` fields —
twenty lines, removes the worst per-tic cost in the mod's default mode.

---

## 5. JOBLESS wgTYPES

Employed by survivors: **4 hex field** (SHELLED's shield language, Seam
Captain), **6 spiral** (the Coronation wind-up, Corpse Circuit), **7 square
rings** (lockdown containment stamp), **8 star** (crit-kill badge, Combo
Ledger), **9 sunburst** (Board Clear payoff now, Insert Coin flare later),
**11 invert** (the Light-Eater's walking negative — the best pairing in the
pile), **12 box window** (the Storefront's browse window). wgType 3 is the
workhorse: pings forward, chain windows backward.

Jobless:

- **10 grid** — its true customer (VERTIGO's platform tiles) is shelved with
  native billboard collision. No surviving idea wants a grid; import it last,
  or when VERTIGO's engine key gets cut.
- **5 hex rings** — near-jobless: the only work found is decorative (Coin-Op
  pedestal emblems), which is the forced-cameo smell this lens exists to
  catch. No mechanical job in any survivor; import behind 10 only if the shop
  wants dressing.

Everything else in 4–12 lands with a real job waiting the day it is imported.
