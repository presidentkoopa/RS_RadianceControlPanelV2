# Ambush wiring — exact lines for the master session

`zscript/Ambush.zs` is self-contained and touches no existing file. Until the
four edits below are made it is inert: not compiled, not ticking, no cvars.
Every cvar read in the code is defensive (missing cvar = shipped default), so
partial wiring degrades rather than crashes — but the handler line is the one
that matters most, because a handler not in `AddEventHandlers` never runs and
never says so.

---

## 1. zscript.txt

Add this line at the end (after the NeonNumeric include):

```
#include "zscript/Ambush.zs"
```

## 2. mapinfo.txt

`GITD_AmbushControl` must be added to `AddEventHandlers`, and it must come
**before `GITD_Composite`** — the ambush declares tint and light during its
tick, and the compositor flushes last. `GITD_Composite` stays the final name
in the list, always.

The full replacement line:

```
	AddEventHandlers = "DarkDoomZ_Handler", "GITD_PresetCustomiser", "GITD_Handler", "GITD_FlashlightHandler", "GITD_NeonKillCounter", "GITD_ResetHandler", "GITD_SetpieceConsole", "GITD_SetpieceSelfTest", "GITD_AmbushControl", "GITD_Composite"
```

(One change from the current line: `"GITD_AmbushControl", ` inserted before
`"GITD_Composite"`.)

## 3. cvarinfo

Append this block. Defaults here MUST match the fallback defaults in
`zscript/Ambush.zs` (they do, as written):

```
// ---- Ambush setpieces ------------------------------------------------------
// A wave sweeps a lockdown over the room you are in, spawns a fight sized to
// that room, and clearing it sweeps the level back to what it was. Everything
// journalled, everything reverted. All triggers ship OFF.
server bool  gitd_ambush_enabled = false;   // master switch for the triggers
server bool  gitd_ambush_ambient = false;   // random ambushes while you play
server float gitd_ambush_period  = 30.0;    // seconds between ambient rolls
server int   gitd_ambush_chance  = 15;      // percent chance per roll
server float gitd_ambush_spacing = 120.0;   // quiet seconds between ambushes
                                            // (also the grace at map start)
server int   gitd_ambush_radius  = 1024;    // room flood / lockdown reach
server float gitd_ambush_budget  = 1.0;     // spawn budget scale, 0-4
server bool  gitd_ambush_tierup  = false;   // promote what already lives there
server float gitd_ambush_tier    = 1.35;    // promotion factor when on
server float gitd_ambush_timer   = 0.0;     // seconds before the ambush gives
                                            // up; 0 = it never does
server color gitd_ambush_color   = "ff 20 10";  // the sweep band
server color gitd_ambush_tint    = "6e 28 28";  // lockdown tint (multiplies
                                                // sector colour; authored
                                                // ambushes may override)
server int   gitd_ambush_light   = -70;     // lockdown light delta
server int   gitd_ambush_desat   = 100;     // lockdown colour drain
server float gitd_ambush_speed   = 700.0;   // wave speed, map units/second
server bool  gitd_ambush_badge   = true;    // victory count via the Neon engine
server string gitd_ambush_class  = "GITD_Ambush_Blackout";  // which ambush the
                                            // triggers fire
```

## 4. MENUDEF

Two edits.

**4a.** In `OptionMenu "GITDOptions"`, after the Sector Sweep block (the
`Submenu "Sector Sweep Options","GITDSweep"` line) and before the blank line
that precedes `Submenu "Bloom Options"`, add:

```
	StaticText ""
	Submenu "Ambush Setpieces",		"GITDAmbush"
```

**4b.** Append this page at the end of the file (before the final
`AddOptionMenu "OptionsMenu"` block, with the other pages):

```
// ---------------------------------------------------------------------------
// AMBUSH SETPIECES
//
// A wave sweeps a lockdown over wherever you are standing; the room darkens,
// a fight sized to that room appears inside it, and clearing it sweeps the
// level back to what it was. Everything is journalled and reverted -- a
// change you cannot undo is not a setpiece, it is damage.
// ---------------------------------------------------------------------------

OptionMenu "GITDAmbush"
{
	Class "DarkDoomZ_OptionMenu"
	Title "Ambush Setpieces"
	StaticText ""
	Option "Ambushes",				"gitd_ambush_enabled", "OnOff"
	StaticText "A wave locks down the room you are in,", darkgray
	StaticText "fills it, and clearing it puts it back.", darkgray
	StaticText "Manual start: netevent gitd_ambush", darkgray
	StaticText "(again while running = walk away from it).", darkgray
	StaticText ""
	StaticText "When", gold
	StaticText ""
	Option "Random ambushes",		"gitd_ambush_ambient", "OnOff"
	Slider "Roll every (seconds)",	"gitd_ambush_period", 5, 120, 5, 0
	Slider "Chance per roll (%)",	"gitd_ambush_chance", 1, 100, 1, 0
	Slider "Quiet time after (s)",	"gitd_ambush_spacing", 0, 600, 15, 0
	StaticText "The quiet time also holds at map start,", darkgray
	StaticText "so a level never opens with one.", darkgray
	StaticText ""
	StaticText "The room", gold
	StaticText ""
	Slider "Reach (map units)",		"gitd_ambush_radius", 256, 3072, 64, 0
	Slider "Spawn budget scale",	"gitd_ambush_budget", 0.0, 4.0, 0.25, 2
	StaticText "What spawns is sized to the room --", darkgray
	StaticText "a closet gets two imps, an arena a wave.", darkgray
	Option "Promote the locals",	"gitd_ambush_tierup", "OnOff"
	Slider "Promotion factor",		"gitd_ambush_tier", 1.0, 3.0, 0.05, 2
	StaticText "Monsters already in the room get faster", darkgray
	StaticText "and tougher as the wave crosses them.", darkgray
	Slider "Gives up after (s)",	"gitd_ambush_timer", 0, 300, 10, 0
	StaticText "0 = it never gives up. Otherwise", darkgray
	StaticText "outlasting it also lifts the lockdown.", darkgray
	StaticText ""
	StaticText "The look", gold
	StaticText ""
	ColorPicker "Sweep colour",		"gitd_ambush_color"
	ColorPicker "Lockdown tint",	"gitd_ambush_tint"
	StaticText "Authored ambushes may override the", darkgray
	StaticText "tint -- the Blackout goes near-black.", darkgray
	Slider "Lockdown light",		"gitd_ambush_light", -255, 64, 5, 0
	Slider "Colour drain",			"gitd_ambush_desat", 0, 255, 15, 0
	Slider "Wave speed",			"gitd_ambush_speed", 200, 2000, 50, 0
	Option "Victory badge",			"gitd_ambush_badge", "OnOff"
	StaticText "Pops your cleared-ambush count through", darkgray
	StaticText "the Numeric Violence Engine.", darkgray
}
```

---

## Netevents (no wiring needed, listed for reference)

- `netevent gitd_ambush` — start one at your feet (needs the master switch
  on); run it again mid-ambush to abandon it. Optional first argument is the
  difficulty tier: `netevent gitd_ambush 3`.
- `netevent gitd_ambush_room` — diagnostics: prints what the room measurer
  makes of where you are standing. Not gated; changes nothing.

Optional convenience alias if a bind is wanted (keyconf or autoexec, master's
call): `alias ambush "netevent gitd_ambush"`.

## After wiring — a two-minute check

1. Load any map. Console: `netevent gitd_ambush_room` — expect a one-line
   room report (class, sectors, area). If nothing prints, the include (step 1)
   is missing.
2. `gitd_ambush_enabled 1`, then `netevent gitd_ambush` — expect the red
   AMBUSH line, a red ring sweeping out, the room darkening behind it, spawns
   inside it, LOCKDOWN when the wave finishes. If the AMBUSH line prints but
   nothing ever happens afterwards, `GITD_AmbushControl` is missing from
   `AddEventHandlers` (step 2) — the code detects that case and says so.
3. Kill everything — expect AMBUSH CLEARED, the badge, and a blue return wave
   restoring the room.
4. `netevent gitd_ambush` twice in a row (start, then abandon) and once while
   dead-checking is impractical to script; the abandon path printing
   "abandoned" / "aborted mid-sweep" is the smoke test that the state machine
   is wired.
