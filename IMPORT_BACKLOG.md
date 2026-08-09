# Neon Numeric Engine — status

In-world text and numbers. Started as a port of GITD's `wgType 13` (the
kill-counter digits) out of the packaged build at
`D:\SteamLibrary\...\GITD-Win64\GITD`, and ended up somewhere larger.

Two repos, and the split matters:

| | |
|---|---|
| **`E:\UZDXREMA`** | the engine — payloads, shaders, billboard API, cvars |
| **`E:\GlowInTheDark`** | this — when a number appears, and the menu over it |

Engine says *that*, GITD says *do this*. GITD's numeric features therefore
need this engine build, which is already true of billboards, bloom and sweep.

---

## Built and working

**Three ways to draw a string**, all billboard payloads, so all three inherit
every placement for free.

| Payload | What it is |
|---|---|
| `BB_TEXT` | real typeface from an SDF atlas. Any of the arcade TTFs. |
| `BB_SEGMENT` | 16-segment display, dark bed, glowing bars. **No asset at all** — the glyphs are arithmetic. |
| `BB_SEGLCD` | the same inverted: lit face, characters punched out dark. This is wgType 13's polarity. |
| `BB_SEAM` | a glowing slit that opens. `BBFL_VOID` makes it a hole rather than a lit panel. |

**Three placements, from arguments rather than code:** `tilt 90` lays a quad
flat on the floor, `BBF_CAMERAYAW` turns it to face the player,
`AttachBillboard` rides it on a monster.

**The script layer** is `zscript/NeonNumeric.zs` — `GITD_Neon.Pop()`,
`.Mark()`, `.Above()`, `.Seam()`. **Neon Numeric Engine Options** sits at the
top of the GITD options page.

**Tooling:** `E:\UZDXREMA\tools\sdffont\mksdf.ps1` turns any TTF into an
atlas; `sdfpreview.ps1` is its regression test and should be re-run after any
change to it.

---

## Better than the original, deliberately

- **16 segments, not 7.** Seven cannot draw `B`, `T` or `X`, and its `B` is
  identical to `8` — so `B0002` reads `80002`. RS_Main names every boss with
  those letters.
- **`B` is not the textbook glyph either.** The standard 16-segment `B` has no
  left verticals and reads as a `3` with a bar. Given `B0001`, that had to go.
- **No 5-character cap.** The original packed its number into a colour channel.
- **Any colour**, not four.
- **The floor half needed no new engine channel.** A billboard at `tilt 90`
  lies flat. The uniform channel, per-pixel text layout and per-surface
  culling I budgeted for were all unnecessary.

---

## Known limits

- **Stairs and slopes.** A flat quad is one plane; on stepped ground it clips
  one step and floats over the next. Not fixable in the shader.
- **Glow reach cannot exceed the atlas spread.** Past it the field has no
  answer and the halo clips to a square. Wider glow means regenerating with a
  bigger `-Spread`.
- **No see-through portals.** A seam can teleport you (`SweepBillboard`
  already detects the crossing); it cannot show another room. That is GZDoom's
  own portal machinery, tied to map geometry.

---

## Open

**The colour question — owner's call, still unanswered.** Three ladders in
RS_Main overlap: monster tier (13 rungs), elite type (17), weapon tier (8).
Green means monster-tier-2 *and* elite-C06 *and* common-weapon. Until it is
decided what a number's colour tells the player, it teaches nothing.
Recommendation: **colour by monster tier**, since the elite pentagram already
announces elite type and loot has its own card. `RS_TierPalette` must be the
source — its own header forbids a fifth table.

**Font licensing.** `PixeloidMono` is baked in as a placeholder, not a
decision. Six of the fonts in `freearcadefonts` are `Trial`/`DEMO` builds and
cannot ship in a pk3.

**Nothing counts kills yet.** The display layer exists; no gameplay calls it.

---

## Next

1. **Progress plumbing** — an effect advancing 0→1 over its own lifetime
   without script poking each instance. Every remaining wgType needs it.
2. **Death-Ping (the expanding ring)** — simplest animated shape, natural
   first customer for the above.
3. **The rest, one at a time** — Death Pool, Hex Field, Hex Rings, Spiral,
   Square Rings, Star, Sunburst, Grid, Invert.
4. **Seam depth on stairs**, if it ever actually bites.

---

## Fixed in passing

GITD's own colour cvars were broken. `GlowHandler.zs:133`, `:539` and
`Flashlight.zs:51` all did `return Color(cvar.GetInt())`, which compiles and
then fails at **load** with *"Return type Color mismatch with SInt4"* — so the
function returned nothing usable and the colour was silently unset. A comment
above one of them argued the cast was what made it work; it never did. All
three now build the Color from its bytes.

Still outstanding and unrelated: `GITD_Flashlight.Tick` throws
*"Unexpected JIT error: Unknown REGT value passed to EmitPARAM"* at load. It
falls back to the interpreter so the flashlight still runs, but something in
that Tick is passing a type the JIT cannot emit.
