// ===========================================================================
// A preset is an ENVIRONMENT, not a palette.
//
// It used to be 32 colours. That is a colour scheme, and a colour scheme is
// not a place. A place has a rhythm (how long each colour holds), a weather,
// and a floor to stand on (how dark it is underneath). All of it together, or
// the preset is just a swatch. In time a profile will reach further still --
// volumetrics, bloom, the sweep, all four lanes and their eight slots each.
//
// So a profile writes ALL of it, and it writes it OVER whatever the player
// had. REPLACE AND RECALL is the deal:
//
//   choosing a preset  -> every value it is about to write is recorded first,
//                         then overwritten
//   Disable Preset     -> every recorded value goes back exactly as it was
//
// That is what makes the override safe to offer. A preset that replaced
// settings with no way back would be a thing players tried once.
//
// THE CAPTURE IS AUTOMATIC. Every write in this file goes through F/I/B, and
// those record the old value before writing it. A profile author does not
// maintain a list of what to back up and cannot forget to, which matters
// because the list is about to get much longer.
//
// Only BLACKOUT ships a profile today. The others were removed rather than
// left half-built -- they are in git, and they come back when a preset is a
// whole environment rather than a palette with a sweep bolted on.
// ===========================================================================
class GITD_PresetProfile abstract
{
	// ---- the record of what the player had ------------------------------
	//
	// "name=value;name=value;" in gitd_preset_backup. First write wins, so a
	// profile that touches the same cvar twice still records the value the
	// PLAYER had rather than the one the profile set a line earlier.
	//
	// Empty means no preset is holding anything, which is also how the menu
	// and the playsim decide whether a profile still needs applying. Anything
	// that clears it is saying "the player's settings are their own again".

	clearscope static void Capture(string name)
	{
		let b = CVar.FindCVar("gitd_preset_backup");
		if (!b) return;

		string cur = b.GetString();

		// Match ";name=" against ";" .. record, so a name is only found at
		// the start of a record and never inside a value or as the prefix of
		// a longer name. gitd_pc_sat must not count as having captured
		// gitd_pc_satvar; the trailing "=" is what keeps those apart.
		if ((";" .. cur).IndexOf(";" .. name .. "=") >= 0) return;

		let c = CVar.FindCVar(name);
		if (!c) return;

		b.SetString(cur .. name .. "=" .. c.GetString() .. ";");
	}

	// ---- writers, all null-guarded --------------------------------------
	// Everything here writes this mod's own server cvars, which is allowed
	// from play scope. ENGINE cvars are not -- setting one throws "Attempt to
	// change CVAR outside of menu code" and aborts the whole function, which
	// is how GITD once silently stopped running entirely. Nothing in this file
	// touches an engine cvar, and nothing in it should. When profiles reach
	// bloom and exposure, those have to be written from MENU scope instead --
	// see GlowHandler.zs, the same wall the reset button hit.
	clearscope static void F(string n, double v) { let c = CVar.FindCVar(n); if (c) { Capture(n); c.SetFloat(v); } }
	clearscope static void I(string n, int v)    { let c = CVar.FindCVar(n); if (c) { Capture(n); c.SetInt(v); } }
	clearscope static void B(string n, bool v)   { let c = CVar.FindCVar(n); if (c) { Capture(n); c.SetInt(v ? 1 : 0); } }

	// Same value across all four lanes, which is the common case -- a preset
	// that wants the lanes to differ says so explicitly.
	clearscope static void Lanes(string suffix, double v)
	{
		static const string p[] = { "gitd_wb", "gitd_wt", "gitd_cg", "gitd_fg" };
		for (int i = 0; i < 4; i++) F(p[i] .. suffix, v);
	}

	clearscope static void LanesI(string suffix, int v)
	{
		static const string p[] = { "gitd_wb", "gitd_wt", "gitd_cg", "gitd_fg" };
		for (int i = 0; i < 4; i++) I(p[i] .. suffix, v);
	}

	// The rhythm. One hold time written to all 32 colour slots.
	clearscope static void Hold(double seconds)
	{
		static const string p[] = { "gitd_wb", "gitd_wt", "gitd_cg", "gitd_fg" };
		for (int i = 0; i < 4; i++)
			for (int s = 1; s <= 8; s++) F(p[i] .. "_hold" .. s, seconds);
	}

	// Eight holds for ONE lane. Hold() gives all four lanes the same rhythm,
	// which is right for a preset that wants a pulse and useless for one that
	// wants the four to drift apart and never re-sync.
	clearscope static void HoldFor(string pre, double a, double b, double c, double d,
	                               double e, double f, double g, double h)
	{
		F(pre .. "_hold1", a); F(pre .. "_hold2", b);
		F(pre .. "_hold3", c); F(pre .. "_hold4", d);
		F(pre .. "_hold5", e); F(pre .. "_hold6", f);
		F(pre .. "_hold7", g); F(pre .. "_hold8", h);
	}

	// ---- state ----------------------------------------------------------

	// True while a preset is holding the player's settings hostage.
	clearscope static bool Holding()
	{
		let b = CVar.FindCVar("gitd_preset_backup");
		return b && b.GetString().Length() > 0;
	}

	// ---- dispatch -------------------------------------------------------
	//
	// A preset with no profile here still works as it always did -- colours
	// only, via GITD_Presets.SlotColor -- so an undesigned preset degrades to
	// a palette rather than to something half-written.

	clearscope static bool HasProfile(int preset)
	{
		return preset == 1 || preset == 3 || preset == 11;
	}

	clearscope static void Apply(int preset)
	{
		switch (preset)
		{
			case 1:  Blackout(); return;
			case 3:  RedAlert(); return;
			case 11: BlackAndWhite(); return;
			default: return;   // no profile yet: colours only, as before
		}
	}

	// ---- apply and recall, derived from state ---------------------------
	//
	// This used to fire on "the number is different from last tic", which
	// meant it could only work if something was watching at the moment the
	// player chose. Two things fell through that:
	//
	//   - the watcher's memory resets on every map load, so "different" was
	//     true on the first tic of every map and the profile re-asserted the
	//     whole environment at every level change, undoing anything the player
	//     had changed since.
	//   - choosing a preset from the title screen, or with the menu open and
	//     the game paused, happens when no WorldTick runs at all. The change
	//     was over before anything looked, and the profile never went on.
	//
	// The backup record answers both without a guess: it is non-empty exactly
	// when a profile is holding the player's settings. A preset that is chosen
	// but not holding needs applying; a preset switched off while still
	// holding needs recalling. That is true whenever it is asked, on any tic,
	// from any scope, no matter what happened while nothing was watching -- so
	// the playsim and the open menu can both just ask, every tic, and the
	// first one to notice does the work. A new map applies nothing, because it
	// is already holding.
	clearscope static void Sync(int preset)
	{
		bool holding = Holding();

		if (preset > 0 && HasProfile(preset))
		{
			if (!holding) Apply(preset);
		}
		else if (holding)
		{
			// Covers Disable Preset, and equally a preset selected from the
			// console that has no profile of its own -- either way nothing
			// should still be holding the player's settings.
			Restore();
		}
	}

	// ---- recall ---------------------------------------------------------
	//
	// Every captured value back where it was, in one pass, then the record is
	// cleared so nothing is holding anything.
	//
	// SetString for all of it, whatever the cvar's type: the engine converts,
	// and it means this loop does not have to know or care which of the sixty
	// names is an int, a float, a bool or a colour. That is the property that
	// lets a future profile write anything at all and still be recallable.
	//
	// NOTE ON WHAT "the player's settings" MEANS. It means what they had when
	// the preset was chosen, not what they had a moment ago. Edits made WHILE
	// a preset is active are overwritten by the recall, because the preset was
	// always going to hand back the room it borrowed.
	clearscope static void Restore()
	{
		let b = CVar.FindCVar("gitd_preset_backup");
		if (!b) return;

		string rec = b.GetString();

		// Cleared FIRST. Restore writes dozens of cvars and anything watching
		// them could re-enter this; an empty record makes that a no-op rather
		// than a second pass over a half-restored set.
		b.SetString("");

		Array<String> parts;
		rec.Split(parts, ";");

		for (int i = 0; i < parts.Size(); i++)
		{
			string p = parts[i];
			int eq = p.IndexOf("=");
			if (eq <= 0) continue;   // empty tail token, or a nameless record

			// Split on the FIRST "=" only. A value is free to contain more.
			let c = CVar.FindCVar(p.Left(eq));
			if (c) c.SetString(p.Mid(eq + 1));
		}
	}

	// =====================================================================
	// 11. BLACK AND WHITE -- and it has to be ALL the way black and white
	//
	// The colours were already black and white. The ROOM was not, and that is
	// the difference between a monochrome palette and a monochrome film: the
	// textures underneath were still brown and green and the glow sat on top
	// of them like a filter someone forgot to finish applying.
	//
	// Two halves, and it needs both:
	//
	//   1. Colour drain at 255. That is a sector desaturation, so it takes the
	//      TEXTURES with it -- the whole world renders grey, not just the
	//      thing this mod draws.
	//   2. Lane colours that are literally black and white, which preset 11
	//      already is. The glow is added by the shader and does not pass
	//      through the desaturation, so a coloured glow would survive the
	//      drain and be the one colour left in the frame. Both halves, or it
	//      is a grey room with a blue light in it.
	//
	// THE RHYTHM IS THE POINT, AND IT NEVER REPEATS. Four lanes on four
	// coprime cycles -- 105, 97, 113 and 89 seconds -- so the surfaces of a
	// room never come back into agreement. There is no beat to learn and no
	// state to wait out. Long stillness, then a hard cut, and the cut lands on
	// a different surface every time.
	//
	// SNAP, everywhere. No crossfades: a cut is a cut. A dissolve would make
	// it dreamlike, and this is not a dream, it is a procedure being carried
	// out on you by people who will not explain it.
	// =====================================================================
	clearscope static void BlackAndWhite()
	{
		// ---- no colour anywhere ------------------------------------------
		//
		// 255 is the whole reason this preset needed a profile rather than a
		// palette. Everything else here is composition.
		B("gitd_dd_enabled", true);
		I("ddz_desat", 255);

		// Crush, and deep -- but not Pure. Blackout is Pure; this one needs a
		// floor for the whites to have something to be brighter THAN. The
		// contrast is the image.
		I("ddz_mode", 4);
		I("ddz_preset", 6);

		// A little air, and no more. Enough that the white bar below reads as
		// a shaft rather than a stripe on a wall; not enough to soften
		// anything. Grey haze is still grey.
		I("ddz_fog", 40);

		// ---- hard edges ---------------------------------------------------
		//
		// Sharp falloff and low coverage: thin bright seams against black,
		// not a wash. Saturation nailed to zero as well, so nothing that
		// leaks in from bleed or a sweep can put colour back.
		LanesI("_enabled", 1);
		LanesI("_pattern", 0);       // Snap
		LanesI("_anim", 0);
		LanesI("_slots", 8);
		LanesI("_falloff", 2);       // Sharp
		Lanes("_saturation", 0.0);
		Lanes("_intensity", 2.20);
		Lanes("_speed", 0.080);

		I("gitd_wb_coverage",  96);
		I("gitd_wt_coverage",  96);
		I("gitd_cg_coverage", 128);
		I("gitd_fg_coverage", 128);

		// ---- four clocks that never agree ---------------------------------
		//
		// Each lane alternates black and white slot by slot (SlotColor,
		// preset 11), so a long hold is a surface sitting lit or unlit for
		// half a minute. The uneven holds inside each row are what stop it
		// being a metronome; the coprime totals are what stop the four rows
		// ever lining up again.
		HoldFor("gitd_wb", 14,  2, 20,  3, 26,  2, 34,  4);   // 105
		HoldFor("gitd_wt",  9, 31,  4, 18,  2, 27,  2,  4);   //  97
		HoldFor("gitd_cg", 40,  3, 22,  2, 16,  5, 21,  4);   // 113
		HoldFor("gitd_fg", 11, 24,  3, 29,  2, 13,  5,  2);   //  89

		// ---- the interrogation light --------------------------------------
		//
		// One bar, east to west, thin and hard-edged with no wake at all --
		// the opposite of weather. It is a machine passing over the room to
		// look at it. 4096 over 34 is two minutes between passes, which is
		// long enough to stop expecting it.
		//
		// And a second bar three seconds behind, which takes the light away
		// again. That is the whole joke: the room is examined, and then it is
		// put back exactly as it was.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 2);
		I("gitd_ss_shape", 2);        // bar, east/west
		I("gitd_ss_origin", 0);
		I("gitd_ss_direction", 0);
		I("gitd_ss_trigger", 0);
		I("gitd_ss_drive", 0);
		I("gitd_ss_range", 4096);
		F("gitd_ss_softness", 0.6);   // hard: a line, not a wash
		F("gitd_ss_intensity", 2.0);
		I("gitd_ss_thickness", 40);
		I("gitd_ss_trail", 0);        // no wake. It does not linger.
		B("gitd_ss_underlay", true);
		F("gitd_ss_drift", 0.0);
		F("gitd_ss_health_speed", 0.0);
		F("gitd_ss_spin", 0.0);
		F("gitd_ss_spin_radius", 0.0);
		I("gitd_ss_spin_colors", 0);
		B("gitd_ss_drop", false);
		B("gitd_ss_actors", false);

		I("gitd_ss_gap1", 105);       // three seconds
		for (int i = 2; i <= 7; i++) I("gitd_ss_gap" .. i, 210);

		F("gitd_ss_speed1", 34.0);    // the clock: 4096 / 34 = two minutes
		I("gitd_ss_shape1", 2); I("gitd_ss_thick1", 40); I("gitd_ss_draw1", 1);
		F("gitd_ss_speed2", 34.0);
		I("gitd_ss_shape2", 2); I("gitd_ss_thick2", 60); I("gitd_ss_draw2", 1);

		B("gitd_ss_light", true);
		B("gitd_ss_perband", true);
		I("gitd_ss_fx1", 1); I("gitd_ss_amount1", 120);   // seen
		I("gitd_ss_fx2", 2); I("gitd_ss_amount2", 120);   // and not
		for (int i = 3; i <= 8; i++) { I("gitd_ss_fx" .. i, 0); I("gitd_ss_thick" .. i, 0); }

		I("gitd_ss_c1", 0xFFFFFF);
		I("gitd_ss_c2", 0x000000);
	}

	// =====================================================================
	// 3. RED ALERT -- containment breach, on a five-minute procedure
	//
	// THE SHAPE THE MACHINE ACTUALLY HAS. Sweep gaps cap at 210 tics, so all
	// eight bands land inside forty-two seconds and the burst cannot be moved
	// to the middle of a long cycle. That is not fought here, it is used: the
	// alarm trips at the top of the loop, runs for forty-two seconds, and then
	// the facility sits with it for four minutes and eighteen more.
	//
	// ONE CLOCK, TWO TABLES. The lane cycle and the sweep period are both set
	// to three hundred seconds, so the palette IS the five minutes and the
	// burst lands in the same place in it every time. An alarm is a procedure.
	// It should repeat exactly, and it should be boring by minute four, which
	// is what makes minute five land.
	//
	//   0:00  the trip           white-hot, every lane at once
	//   0:06  klaxon             three beats, red into near-black
	//   0:42  sustained          deep red, the sweep gone quiet
	//   2:00  decay              rust, dimming
	//   3:30  the wait           dead amber, nothing moving
	//   5:00  again
	//
	// The colours are in GITD_Presets.SlotColor. This is the timing, the
	// shape and the weather. The two only mean something read together.
	// =====================================================================
	clearscope static void RedAlert()
	{
		// ---- the room ---------------------------------------------------
		//
		// SNAP, not fade. An alarm changes state; it does not ease between
		// states. But the transition speed still has to be fast even though
		// the crossfade is never drawn, because the phase clock is what
		// advances the slot -- at the default, six-second holds would run
		// past eight and the whole table would drift out of the sweep it is
		// supposed to be locked to.
		LanesI("_enabled", 1);
		LanesI("_pattern", 0);
		LanesI("_anim", 0);
		LanesI("_slots", 8);
		Lanes("_saturation", 1.00);
		Lanes("_speed", 0.080);      // ~0.4s, so six seconds means six

		// Per-lane shape, because the four are doing different jobs. The
		// strip is narrow and bright; the ceiling is a wide soft wash so the
		// beacon has something to bloom into; the floor is the dimmest,
		// since a deck is lit by what is above it rather than by itself.
		I("gitd_wb_coverage", 120);  F("gitd_wb_intensity", 1.60); I("gitd_wb_falloff", 2);
		I("gitd_wt_coverage", 200);  F("gitd_wt_intensity", 1.20); I("gitd_wt_falloff", 1);
		I("gitd_cg_coverage", 320);  F("gitd_cg_intensity", 2.00); I("gitd_cg_falloff", 1);
		I("gitd_fg_coverage", 160);  F("gitd_fg_intensity", 1.10); I("gitd_fg_falloff", 1);

		// ---- the five minutes, lane by lane -----------------------------
		//
		// Every row sums to 300. Uneven holds are the whole trick: a slot
		// that holds for four minutes and five that hold for six seconds is
		// how a fixed eight-slot cycle produces a PHASE -- a long nothing,
		// then a burst, at a known point in the loop. Without that, eight
		// slots can only ever be eight equal beats.
		//
		// Wall bottom carries the narrative. The ceiling is the beacon and
		// is black for the other four and a half minutes. Wall top runs the
		// same beacon three seconds out of step, which is the difference
		// between a lamp turning and two lanes changing colour at once.
		HoldFor("gitd_wb",   6, 12,  6, 12,  6,  60,  90, 108);
		HoldFor("gitd_wt",   3,  6,  6,  6,  6,   6,   6, 261);
		HoldFor("gitd_cg",   6,  6,  6,  6,  6,   6,   6, 258);
		HoldFor("gitd_fg",  12, 12, 12, 12, 12,  60,  90,  90);

		// ---- the floor it stands on -------------------------------------
		//
		// Subtract rather than Compress: emergency lighting is uniformly dim
		// rather than proportionally scaled. Dismal rather than Oppressive,
		// because you have to be able to SEE red -- this is the one preset
		// where making the room darker makes it less frightening.
		//
		// And colour drain near zero. Draining an alarm is the one place it
		// would be actively wrong.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 1);      // Subtract
		I("ddz_preset", 3);    // Dismal
		I("ddz_desat", 15);

		// FOG IS THE VOLUMETRIC LEVER. With air in the room, a band's light
		// amount is visible BETWEEN you and the wall rather than only on it,
		// so the klaxon is a body of red moving down the corridor instead of
		// a colour arriving on a surface. It is also what gives the
		// flashlight cone something to cut through, which is the whole
		// reason to have one in a red room.
		I("ddz_fog", 96);

		// BLOOM IS NOT SET HERE, AND CANNOT BE. gl_bloom_* belong to the
		// engine, and an engine cvar written from play scope throws and
		// aborts the rest of the profile -- the same wall the reset button
		// hit. This profile is applied from BOTH the playsim and the menu,
		// so it must be legal in the stricter of the two. A preset that
		// carries bloom needs a menu-scope half that does not exist yet;
		// until then, turn bloom up on the Bloom page and it will smear the
		// red exactly as intended.

		// ---- the weather ------------------------------------------------
		//
		// TWO JOBS IN ONE TRAIN.
		//
		// Band 1 is the CLOCK. Range over speed 1 is the period, and 8100
		// over 27 is three hundred seconds to the tic. It is also the
		// pressure wave: eight hundred units thick at twenty-seven units a
		// second takes a full minute to pass, so what it reads as is not a
		// band at all but the room slowly getting heavier.
		//
		// Bands 2 to 7 are the KLAXON, at six seconds apart -- the cap, and
		// the same six seconds the ceiling lane is flicking on. They are
		// fast and thin, because a lamp sweeping a corridor is machinery,
		// not weather.
		//
		// Band 8 is the ALL CLEAR. Reveal, wide and slow, six seconds after
		// the last klaxon beat: the moment you see where you actually are
		// rather than just seeing red.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 8);
		I("gitd_ss_shape", 1);        // rings; bands override where they differ
		I("gitd_ss_origin", 0);       // map centre -- the breach has a place,
		                              // and it is not wherever you happen to be
		I("gitd_ss_direction", 0);    // outward, then silence
		I("gitd_ss_trigger", 0);      // free-running: it is a schedule
		I("gitd_ss_drive", 0);
		I("gitd_ss_range", 8100);
		F("gitd_ss_softness", 2.4);
		F("gitd_ss_intensity", 1.5);
		I("gitd_ss_thickness", 120);
		I("gitd_ss_trail", 200);
		B("gitd_ss_underlay", true);  // the lanes keep running underneath;
		                              // the palette is half the preset
		F("gitd_ss_drift", 0.0);      // no drift and no overtaking. This is
		F("gitd_ss_health_speed", 0.0);// disciplined panic, not chaos.
		F("gitd_ss_spin", 0.0);       // the swung origin reads as wobble
		F("gitd_ss_spin_radius", 0.0);// rather than rotation -- left off until
		I("gitd_ss_spin_colors", 0);  // it turns a plane instead
		B("gitd_ss_drop", false);
		B("gitd_ss_actors", false);

		// Six seconds between every band: 7 gaps x 210 tics = the full
		// forty-two second burst, and every beat lands on the ceiling lamp.
		for (int i = 1; i <= 7; i++) I("gitd_ss_gap" .. i, 210);

		// The pressure wave.
		F("gitd_ss_speed1", 27.0);  I("gitd_ss_shape1", 4);  // shell: it has volume
		I("gitd_ss_thick1", 800);   I("gitd_ss_draw1", 1);

		// The klaxon: six lamps, alternating flood and drop.
		for (int i = 2; i <= 7; i++)
		{
			F("gitd_ss_speed" .. i, 420.0);
			I("gitd_ss_shape" .. i, 1);
			I("gitd_ss_thick" .. i, 90);
			I("gitd_ss_draw" .. i, 1);
		}

		// The all clear.
		F("gitd_ss_speed8", 150.0); I("gitd_ss_shape8", 1);
		I("gitd_ss_thick8", 400);   I("gitd_ss_draw8", 2);   // reveal

		// LIGHT: THE NEGATIVE BAND IS THE POINT.
		//
		// Amount is a magnitude, 0-128, and the DIRECTION is the per-band
		// effect -- 1 brightens, 2 darkens. So the room floods and then
		// drops below its own baseline, three times. A klaxon that only ever
		// brightens reads as a light show; the drop is what makes it an
		// alarm. Band 1 darkens gently for a minute, which is the weight.
		B("gitd_ss_light", true);
		B("gitd_ss_perband", true);

		I("gitd_ss_fx1", 2); I("gitd_ss_amount1", 32);   // the pressure
		I("gitd_ss_fx2", 1); I("gitd_ss_amount2", 112);  // flood
		I("gitd_ss_fx3", 2); I("gitd_ss_amount3", 72);   // drop
		I("gitd_ss_fx4", 1); I("gitd_ss_amount4", 112);
		I("gitd_ss_fx5", 2); I("gitd_ss_amount5", 72);
		I("gitd_ss_fx6", 1); I("gitd_ss_amount6", 112);
		I("gitd_ss_fx7", 2); I("gitd_ss_amount7", 72);
		I("gitd_ss_fx8", 4); I("gitd_ss_amount8", 48);   // sonar reveal

		// Colours of the bands themselves. The klaxon pair alternates the
		// alarm red with a near-black that carries the drop; reveal ignores
		// rgb entirely but keeps a swatch so the menu shows something true.
		I("gitd_ss_c1", 0x4A0804);   // the pressure: dried blood
		I("gitd_ss_c2", 0xFF1810);   // the alarm
		I("gitd_ss_c3", 0x140000);
		I("gitd_ss_c4", 0xFF1810);
		I("gitd_ss_c5", 0x140000);
		I("gitd_ss_c6", 0xFF3018);   // the last beat, a touch hotter
		I("gitd_ss_c7", 0x140000);
		I("gitd_ss_c8", 0x8A5A40);   // all clear: the room's own colour back
	}

	// =====================================================================
	// 1. BLACKOUT -- the absence
	//
	// Every other preset is a place. This is the lack of one, and it needs a
	// profile precisely BECAUSE it is defined by what it does not do: without
	// one, selecting Blackout only changed the 32 colours to black and left
	// every lane still lit and shaped as before. Pure darkness that still has
	// glow in it is not pure darkness.
	//
	// So this switches things OFF. That is the whole design.
	//
	// IT DOES NOT TOUCH THE SWEEP. It used to switch the sweep off, on the
	// reasoning that a wave crossing pure darkness would be the only thing
	// visible and that is the opposite of the intent -- true, but not this
	// preset's call to make. A preset reaching across into another system to
	// silence it is how choosing a palette ended up stopping a player's
	// sweep, and the fix is the rule rather than the one case: presets and
	// the sweep are separate until a profile is designed to drive both.
	// =====================================================================
	clearscope static void Blackout()
	{
		// The colours are already pure black -- GITD_Presets.SlotColor
		// special-cases preset 1 and returns 0,0,0 for all thirty-two. The
		// lanes are left enabled rather than disabled so the mod is still
		// composing the room; it is just composing nothing.
		LanesI("_enabled", 1);
		LanesI("_pattern", 0);
		LanesI("_coverage", 0);
		Lanes("_intensity", 0.0);
		LanesI("_anim", 0);
		Lanes("_speed", 0.050);
		Hold(30.0);

		// As dark as the mod goes. Crush is the exponential curve, Pure is
		// the bottom of the ladder.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 4);      // Crush
		I("ddz_preset", 8);    // Pure
		I("ddz_desat", 255);   // no colour survives here either
	}
}
