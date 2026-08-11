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

	// ---- the two systems that are not sector work ------------------------
	//
	// The glow wave and per-pixel darkness are render terms, so a profile
	// sets them like anything else -- but they are worth their own helpers
	// because every preset that uses them sets the same eight or nine cvars
	// and a wall of F() calls buries which numbers actually matter.

	clearscope static void Wave(double length, double speed, double sharp, int shape,
	                            double reach, double bright, double colour,
	                            double detune, double seed, int climb)
	{
		B("gitd_wave_enabled", true);
		B("gitd_seamless", false);   // exclusive; see GITD_Render.PushWave
		F("gitd_wave_length", length);
		F("gitd_wave_speed", speed);
		F("gitd_wave_sharp", sharp);
		I("gitd_wave_shape", shape);
		F("gitd_wave_reach", reach);
		F("gitd_wave_bright", bright);
		F("gitd_wave_colour", colour);
		F("gitd_wave_detune", detune);
		F("gitd_wave_seed", seed);
		I("gitd_wave_climb", climb);
	}

	clearscope static void NoWave()
	{
		B("gitd_wave_enabled", false);
	}

	// Distance is the term that only exists per pixel, and it is the reason
	// to turn this on at all -- a room stops being uniformly dim and starts
	// having depth. Height pools what is left on the floor.
	clearscope static void DeepDark(double dist, double distRange,
	                                double height, double heightRef, double heightRange)
	{
		B("gitd_dd_perpixel", true);
		F("gitd_dd_dist", dist);
		F("gitd_dd_dist_range", distRange);
		F("gitd_dd_height", height);
		F("gitd_dd_height_ref", heightRef);
		F("gitd_dd_height_range", heightRange);
	}

	// ---- dispatch -------------------------------------------------------

	clearscope static bool HasProfile(int preset)
	{
		return preset == 1 || preset == 2 || preset == 3
			|| preset == 11 || preset == 12;
	}

	clearscope static void Apply(int preset)
	{
		switch (preset)
		{
			case 1:  Blackout(); return;
			case 2:  LowPower(); return;
			case 3:  RedAlert(); return;
			case 11: BlackAndWhite(); return;
			case 12: OmgWtf(); return;
			default: return;   // no profile yet: colours only, as before
		}
	}

	// ---- the engine half ------------------------------------------------
	//
	// BLOOM AND EXPOSURE BELONG TO THE ENGINE, and ZScript will not write a
	// non-mod cvar unless DMenu::InMenu is set. It is set around MenuEvent
	// and NOT around Ticker, so this cannot ride the same path as everything
	// else -- see DarkDoomZ_OptionMenu.MenuEvent, which is the only caller.
	//
	// Not captured for recall either, deliberately. The backup record is
	// written by F/I/B during Apply, which runs in both scopes; making these
	// go through it would mean a capture that sometimes happens and sometimes
	// throws depending on which clock got there first. Bloom is a handful of
	// sliders on their own page and the Bloom page's own defaults are one
	// click away, which is a better answer than a recall that is only usually
	// correct.
	clearscope static void ApplyEngine(int preset)
	{
		switch (preset)
		{
			case 1:  BlackoutBloom(); return;
			case 2:  LowPowerBloom(); return;
			case 3:  RedAlertBloom(); return;
			case 11: BlackAndWhiteBloom(); return;
			case 12: OmgWtfBloom(); return;
			default: return;
		}
	}

	// Raw setters for engine cvars. No Capture -- see above.
	clearscope static void EF(string n, double v) { let c = CVar.FindCVar(n); if (c) c.SetFloat(v); }
	clearscope static void EI(string n, int v)    { let c = CVar.FindCVar(n); if (c) c.SetInt(v); }

	clearscope static void Bloom(double amount, double threshold, double knee,
	                             double r, double g, double b)
	{
		EI("gl_bloom", 1);
		EF("gl_bloom_amount", amount);
		EF("gl_bloom_threshold", threshold);
		EF("gl_bloom_knee", knee);
		EF("gl_bloom_tint_r", r);
		EF("gl_bloom_tint_g", g);
		EF("gl_bloom_tint_b", b);
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
	// 2. LOW POWER -- the grid is failing, and you can watch it fail
	//
	// WHAT IT IS. The grid is not dead; Blackout is dead. Something down in
	// the plant is still fighting to keep the lights on and mostly
	// succeeding, and every few minutes it loses a round. The horror is not
	// the dark. It is that the dark is SCHEDULED, and that whatever is
	// keeping it away is losing.
	//
	// WHY THIS ONE IS THE SHOWPIECE. Every system this mod has now points the
	// same way for once, because a failing electrical grid is the one subject
	// where all of them are literally true at the same time:
	//
	//   rolling glow    a brownout IS light undulating. The wave is not
	//                   decoration here, it is the thing being depicted.
	//   per-pixel dark  distance falloff, so the corridor does not end -- it
	//                   stops being visible. A per-sector multiplier could
	//                   never say that.
	//   fog             gives the failing light something to hang in, and
	//                   gives the torch beam something to cut.
	//   flashlight      with dust in it, because a facility nobody has
	//                   maintained since the incident has dust in the air.
	//   bloom           a dying filament blooms. Low threshold so the little
	//                   light there is smears rather than sits.
	//   sweep           the four-beat failure, using CRUSH for the drops --
	//                   travelling darkness, per pixel, which is the thing
	//                   that used to have to be faked room by room.
	//
	// The whole preset is one four-beat sentence spoken every three and a
	// half minutes: it catches -- it holds -- it slips -- it goes.
	// =====================================================================
	clearscope static void LowPower()
	{
		// ---- the baseline ------------------------------------------------
		//
		// SNAP, on long holds. A dying grid does not shimmer, pulse or
		// breathe -- it sits at one value until it changes to another.
		// Anything smoother reads as ambience, and ambience is comfortable;
		// this should feel switched off rather than asleep.
		//
		// The transition speed still has to be quick even though the
		// crossfade is never drawn, because the phase clock is what advances
		// the slot. Left slow, nine seconds becomes sixteen and the palette
		// drifts away from the sweep it is supposed to sit under.
		LanesI("_enabled", 1);
		LanesI("_pattern", 0);
		LanesI("_anim", 0);
		LanesI("_slots", 8);
		LanesI("_falloff", 1);
		Lanes("_saturation", 0.85);
		Lanes("_speed", 0.060);
		Hold(9.0);

		// Coverage low, so the glow CLINGS to the bottom of walls and the
		// edges of floors the way real light pools when there is not enough
		// of it to fill a space. The ceiling gets least: emergency circuits
		// do not light ceilings.
		I("gitd_wb_coverage", 104); F("gitd_wb_intensity", 0.90);
		I("gitd_wt_coverage",  72); F("gitd_wt_intensity", 0.55);
		I("gitd_cg_coverage",  56); F("gitd_cg_intensity", 0.45);
		I("gitd_fg_coverage",  96); F("gitd_fg_intensity", 0.70);

		// ---- THE BROWNOUT ------------------------------------------------
		//
		// This is the preset the glow wave was worth building for.
		//
		// Long wavelength and low speed: a swell that takes most of a
		// corridor to arrive, not corrugation. Sharpness 1 -- a plain sine,
		// because a failing supply sags, it does not spike.
		//
		// BRIGHTNESS DEEPER THAN REACH, which is the opposite of the obvious
		// setting and the right one here. A big reach swing makes the glow's
		// EDGE crawl, which reads as something moving. A big brightness swing
		// with a small edge swing reads as the SUPPLY moving -- the fixture
		// stays exactly where it is and what is arriving at it changes. That
		// is a brownout. The other is a ghost.
		//
		// Detune high, so the roll never resolves into a period you can count
		// -- the moment you can count it, it becomes machinery working
		// correctly, which is the exact opposite of the point.
		//
		// Climb 15, nearly nothing: the sag rolls ALONG the corridor rather
		// than up through the room. A grid browning out is a wave down a
		// cable, not something rising.
		Wave(1400.0, 0.35, 1.0, 2,   // shape 2: a plane, travelling the long axis
		     0.18,                   // edge: barely moves
		     0.55,                   // brightness: the sag itself
		     0.0,                    // no colour slide; the palette holds still
		     0.75,                   // detune: never repeats
		     0.6,                    // per-room scatter: rooms fail separately
		     15);

		// ---- the floor it stands on --------------------------------------
		//
		// PER-PIXEL, and this is the other reason this preset exists.
		// Compress at Oppressive was already dark; what it could not do is
		// make the corridor STOP rather than end. Distance 0.75 over 1280
		// units means you see the next twenty metres and then you do not --
		// not a wall, not a door, just the point where the light gave up.
		//
		// Height pools the rest on the floor, which is where light goes when
		// there is not enough of it to reach anywhere else.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 2);      // Compress -- proportional, keeps some shape
		I("ddz_preset", 4);    // Oppressive
		I("ddz_desat", 70);    // colour vision failing with the lamps
		DeepDark(0.75, 1280.0, 0.35, 48.0, 320.0);

		// ---- the air -----------------------------------------------------
		//
		// Fog is what turns every other system in this preset from a surface
		// effect into a volume. Without it the sweep's crush band is a dark
		// stripe on a wall; with it, it is a body of dark moving down a
		// corridor. It is also the only reason the torch has a beam rather
		// than a bright patch at the end of it.
		I("ddz_fog", 128);
		F("ddz_skymode", 1.0);

		// ---- the torch ---------------------------------------------------
		//
		// Halogen, because that is what a facility torch is, and warm against
		// everything else here being dead amber and cold grey.
		//
		// Narrow and long: this room does not want a lantern, it wants a
		// beam that shows you one thing at a time. Density high so the cone
		// is visible in the air; dust ON and drifting slowly, because nobody
		// has maintained this place since the incident and the fog should
		// have something in it.
		B("fl_enabled", true);
		I("fl_range", 1400);
		F("fl_intensity", 1.15);
		F("fl_inner", 7.0);
		F("fl_outer", 21.0);
		F("fl_falloff", 1.7);
		F("fl_density", 1.6);
		F("fl_dust", 0.55);
		F("fl_dust_scale", 0.05);
		F("fl_dust_drift", 0.12);
		B("fl_bounce", true);
		I("fl_slots", 1);
		I("fl_pattern", 0);

		// ---- THE EVENT ---------------------------------------------------
		//
		// range over speed 1 is the wait: 8192 over 40 is about 205 seconds
		// of nothing at all, then ten seconds of the grid losing an argument.
		//
		// Every band is SLOWER than the one before, so the four stretch
		// further apart the further they travel. The failure drags. Nothing
		// overtakes, because a power cut is not a race.
		//
		// AND THE LAST TWO ARE CRUSH, NOT DARKEN. Draw mode 3 multiplies the
		// finished pixel down per fragment, so the sag arrives as a moving
		// front and passes over you. The per-sector darken it replaces could
		// only ever switch whole rooms off in sequence, which reads as a
		// lighting bug rather than as a wave.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 4);
		I("gitd_ss_shape", 1);        // a ring: it comes from the plant
		I("gitd_ss_origin", 0);
		I("gitd_ss_direction", 0);
		I("gitd_ss_trigger", 0);      // free-running: it is a schedule
		I("gitd_ss_drive", 0);
		I("gitd_ss_range", 8192);
		F("gitd_ss_softness", 3.2);   // soft: a wave of power, not a scanline
		F("gitd_ss_intensity", 1.1);
		I("gitd_ss_thickness", 420);
		I("gitd_ss_trail", 260);
		B("gitd_ss_underlay", true);
		F("gitd_ss_drift", 0.0);
		F("gitd_ss_health_speed", 0.0);
		F("gitd_ss_spin", 0.0);
		F("gitd_ss_spin_radius", 0.0);
		I("gitd_ss_spin_colors", 0);
		B("gitd_ss_drop", false);
		B("gitd_ss_actors", false);
		B("gitd_ss_light", false);    // the drops are per pixel now, below

		I("gitd_ss_gap1", 70);        // two seconds: it catches
		I("gitd_ss_gap2", 105);       // three: it holds
		I("gitd_ss_gap3", 140);       // four: it slips, then it goes

		F("gitd_ss_speed1", 40.0);    // the clock: 8192 / 40 = ~205s
		F("gitd_ss_speed2", 34.0);
		F("gitd_ss_speed3", 28.0);
		F("gitd_ss_speed4", 22.0);
		for (int i = 1; i <= 4; i++) I("gitd_ss_shape" .. i, 1);
		I("gitd_ss_thick1", 380); I("gitd_ss_thick2", 440);
		I("gitd_ss_thick3", 520); I("gitd_ss_thick4", 700);

		I("gitd_ss_draw1", 1);        // a system cuts in: the corridor floods
		I("gitd_ss_draw2", 1);        // it holds, weaker
		I("gitd_ss_draw3", 3);        // losing it -- travelling darkness
		I("gitd_ss_draw4", 3);        // out, and darker than baseline

		// The surge is a touch warmer than the baseline: a filament heating
		// just before it gives up. The two crush bands carry no light of
		// their own -- their colour is only what the menu shows.
		I("gitd_ss_c1", 0xFFC070);
		I("gitd_ss_c2", 0xA07840);
		I("gitd_ss_c3", 0x1A1408);
		I("gitd_ss_c4", 0x0A0804);
	}

	// Bloom for a dying filament: threshold LOW, because there is almost no
	// light here and if only blown-out pixels bloomed, nothing would. Warm
	// tint so the smear is the same sodium the lamps are. Amount modest --
	// this is a glow around a weak source, not a haze over the screen.
	clearscope static void LowPowerBloom()
	{
		Bloom(1.10, 0.28, 0.55, 1.0, 0.86, 0.62);
		EF("gl_bloom_anamorphic", 0.35);   // a slight horizontal streak, like
		EF("gl_bloom_anamorphic_ratio", 2.5);  // a tube fixture seen sideways
		EF("gl_bloom_chromatic", 0.0);
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

		// ---- NO SWEEP. THE SWEEP IS THE THING THIS PRESET IS NOT ---------
		//
		// It had one: a hard white bar crossing the room every two minutes
		// with a black bar behind it, the room examined and then put back.
		// Good line, wrong film. A travelling band is a CAMERA MOVE, and this
		// is a preset made of held compositions and hard cuts -- the entire
		// palette below is eight long stares per surface on four clocks that
		// never agree. Something gliding through it turns all of that into
		// background for the thing that moves.
		//
		// So the sweep is switched off rather than merely not configured,
		// because a preset that inherits whatever band the last one left
		// running is not a preset, it is a leftover.
		B("gitd_ss_enabled", false);

		// ---- ETCHED, NOT UNDULATING --------------------------------------
		//
		// The wave is here and it is doing the opposite of what it does
		// anywhere else. Speed 0.06 is very nearly stopped -- a full cycle
		// takes about two minutes -- and sharpness 7 makes it a hard narrow
		// crest rather than a swell.
		//
		// What that produces is not motion. It is a fixed, uneven, hand-cut
		// edge on every band of light, that you would swear was painted
		// there, and which has moved when you come back down the corridor.
		// REACH ONLY: no brightness swing and no colour slide, so nothing
		// pulses. The shape is wrong and stays wrong.
		//
		// Climb 0 -- all four surfaces share one phase, so the edge is
		// continuous where a wall meets a floor rather than stepping at the
		// join. This is the one preset that wants the corner to look intact,
		// having given up the seamless machinery to get the wave at all.
		Wave(720.0, 0.06, 7.0, 2,
		     0.42,                 // deep, because it is the only thing moving
		     0.0,
		     0.0,
		     0.0,                  // no detune: repetition is the point here
		     0.85,                 // and every room cut by a different hand
		     0);

		// ---- deep focus --------------------------------------------------
		//
		// Distance falloff hard and long: 0.85 over 3600 units. Near is
		// legible, far is black, and there is no midtone to speak of in
		// between -- which is the whole look. Combined with Crush above, the
		// image is what is in front of you and then nothing, with an edge
		// between them rather than a gradient.
		//
		// No height pooling. Dark on the floor would be atmosphere, and
		// atmosphere is softness.
		DeepDark(0.85, 3600.0, 0.0, 0.0, 256.0);

		// A little air -- enough for the torch to have a shaft, not enough to
		// soften anything. Grey haze is still grey.
		I("ddz_fog", 40);

		// The torch is hard and clean. NO DUST: motes are texture, and this
		// preset has no texture in it anywhere. A cone with an edge.
		B("fl_enabled", true);
		I("fl_range", 1300);
		F("fl_intensity", 1.30);
		F("fl_inner", 6.0);
		F("fl_outer", 16.0);
		F("fl_falloff", 1.2);
		F("fl_density", 1.3);
		F("fl_dust", 0.0);
		B("fl_bounce", false);      // no fill. One light, and its absence.
		I("fl_slots", 1);
		I("fl_pattern", 0);
	}

	// White that BLOWS OUT rather than glows. Threshold high, so only what is
	// genuinely near-white blooms at all and the greys stay matte; amount
	// high, so when something does cross the line it goes completely. No
	// tint, and chromatic fringing explicitly at zero -- colour fringing on a
	// monochrome preset is exactly the kind of small dishonesty that makes a
	// black and white image look like a filter over a colour one.
	clearscope static void BlackAndWhiteBloom()
	{
		Bloom(1.60, 0.72, 0.10, 1.0, 1.0, 1.0);
		EF("gl_bloom_anamorphic", 0.0);
		EF("gl_bloom_chromatic", 0.0);
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

		// ---- THE THROB, UNDERNEATH ALL OF IT ----------------------------
		//
		// The table above is the alarm's SCRIPT -- what happens and when. The
		// wave is its PULSE, and it runs continuously through all five
		// minutes including the four of them where nothing is scripted to
		// happen. That is what stops the quiet stretch reading as the preset
		// having stopped: the room keeps breathing even when the beacon is
		// dark and the sweep is silent.
		//
		// Short wavelength, quick, and SHARP -- pow on the crest, so it is a
		// spike through an otherwise flat lane rather than a swell. Weather
		// swells; machinery spikes, and an alarm is machinery.
		//
		// Climb 90 is the good number here: a quarter turn between each
		// surface, so the throb visibly travels UP -- floor, wall bottom,
		// wall top, ceiling. That is what a rotating beacon does to a
		// corridor, and it is the effect that only became possible once the
		// four channels were allowed to disagree.
		//
		// Detune stays LOW, which is the opposite of every other preset here.
		// Everything else wants a wave that never repeats; a warning has to
		// repeat, because one you cannot anticipate is just noise.
		Wave(320.0, 3.2, 4.0, 1,   // ring, quick, spiky
		     0.30,                 // the edge guts and recovers
		     0.45,                 // and the light with it
		     0.0,                  // colour holds: the palette is the script
		     0.15,                 // barely detuned -- it MUST repeat
		     0.25,                 // rooms mostly agree: one alarm, one building
		     90);

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

		// PER-PIXEL, but restrained, and restrained ON PURPOSE. Low Power
		// uses distance falloff to make a corridor stop being visible; doing
		// that here would hide the alarm, and an alarm you cannot see is not
		// one. 0.30 over 2600 units is just enough that the far end of a hall
		// is dimmer than your feet -- depth, not concealment.
		//
		// No height pooling at all. Dark gathering on the floor is a stillness
		// effect and this room is not still.
		DeepDark(0.30, 2600.0, 0.0, 0.0, 256.0);

		// FOG IS THE VOLUMETRIC LEVER. With air in the room, a band is
		// visible BETWEEN you and the wall rather than only on it, so the
		// klaxon is a body of red moving down the corridor instead of a
		// colour arriving on a surface. Lighter than Low Power's: this is a
		// lit room having an emergency, not a dead one.
		I("ddz_fog", 72);

		// The torch, wide-ish and clean. Red Alert is not a preset about not
		// being able to see -- the light is already on and it is already
		// telling you something. A little dust so the cone reads against the
		// fog, and no more.
		B("fl_enabled", true);
		I("fl_range", 1100);
		F("fl_intensity", 1.05);
		F("fl_inner", 11.0);
		F("fl_outer", 27.0);
		F("fl_density", 1.1);
		F("fl_dust", 0.20);
		B("fl_bounce", true);

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
		//
		// THE DROPS ARE CRUSH BANDS NOW (draw mode 3), not the per-sector
		// darken this used to use. That mattered more here than anywhere
		// else: the whole burst is six beats six seconds apart, and the old
		// path made each drop a room-by-room switch-off that arrived a whole
		// sector at a time. Per pixel, the dark is a front that crosses the
		// wall you are looking at, in the same place the bright band just
		// crossed it. Even beats are wider than odd ones, so the dark takes
		// longer to pass than the light did -- the room loses ground.
		for (int i = 2; i <= 7; i++)
		{
			bool flood = (i % 2) == 0;
			F("gitd_ss_speed" .. i, 420.0);
			I("gitd_ss_shape" .. i, 1);
			I("gitd_ss_thick" .. i, flood ? 90 : 150);
			I("gitd_ss_draw" .. i, flood ? 1 : 3);
		}

		// The all clear.
		F("gitd_ss_speed8", 150.0); I("gitd_ss_shape8", 1);
		I("gitd_ss_thick8", 400);   I("gitd_ss_draw8", 2);   // reveal

		// THE NEGATIVE BAND IS STILL THE POINT -- IT JUST MOVED SYSTEMS.
		//
		// This used to ask the per-sector light path for the drops:
		// gitd_ss_light on, per-band fx 2 (darken) with a magnitude. That
		// worked and it worked A ROOM AT A TIME, which for a six-beat burst
		// meant the alarm's dark half arrived as sectors popping off in
		// sequence while its bright half swept smoothly past. Two halves of
		// one effect on two different granularities.
		//
		// Draw mode 3 does the same job in the fragment shader, so both
		// halves are now the same kind of thing. The per-sector light path is
		// switched off here entirely rather than left on underneath, because
		// running both would darken the drop twice.
		//
		// Band 8 keeps its sonar reveal, which has no per-pixel equivalent:
		// revealing a room to its natural brightness and letting it decay is
		// a statement about ROOMS, and that is the one place where the coarse
		// path is saying the right thing.
		B("gitd_ss_light", true);
		B("gitd_ss_perband", true);
		for (int i = 1; i <= 7; i++) I("gitd_ss_fx" .. i, 0);
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

	// Bloom for a klaxon: amount HIGH and threshold LOW, so the red does not
	// sit on the wall, it bleeds off it and fills the corridor. Tinted red so
	// even the white trip-flash smears warm.
	//
	// Chromatic fringing on, lightly, and it is the only preset here that
	// gets it. Fringing is an artefact -- a lens failing to agree with itself
	// -- and everywhere else that would be a small dishonesty. In a room that
	// is telling you something has gone wrong, an image that is slightly
	// wrong is saying the same thing the alarm is.
	clearscope static void RedAlertBloom()
	{
		Bloom(1.85, 0.30, 0.40, 1.0, 0.42, 0.34);
		EF("gl_bloom_anamorphic", 0.0);
		EF("gl_bloom_chromatic", 0.35);
	}

	// =====================================================================
	// 12. OMGWTF -- every system at once, on purpose
	//
	// Every other preset in this file is an argument for restraint. One is
	// about a failing supply and spends most of its time doing nothing; one
	// is four surfaces refusing to agree; one is literally the absence of
	// light. Restraint is right for all of them and it is also a claim, and a
	// claim is worth testing against its own opposite.
	//
	// So this is the opposite. Every system on, every one of them turned up,
	// nothing subordinated to anything else. It is not tasteful and it is not
	// trying to be -- what it is for is showing, in one place, everything the
	// mod can do at the same time, and finding out what breaks when it does.
	//
	// Treat it as the stress test it is. If a frame rate is going to fall
	// over or two systems are going to disagree, they will do it here first.
	// =====================================================================
	clearscope static void OmgWtf()
	{
		// PING-PONG on fast holds, so the palette walks its eight slots
		// forwards and back instead of cycling -- the same thirty-two colours
		// arriving in an order that keeps changing.
		LanesI("_enabled", 1);
		LanesI("_pattern", 4);       // ping-pong
		LanesI("_anim", 1);          // and the per-sector ripple ON TOP
		LanesI("_slots", 8);
		LanesI("_falloff", 0);
		Lanes("_saturation", 1.35);  // past 1: pushed toward white
		Lanes("_intensity", 2.40);
		Lanes("_speed", 0.020);
		Lanes("_anim_speed", 1.4);
		Lanes("_anim_depth", 0.7);
		Lanes("_anim_sharp", 2.5);

		// Four different hold patterns on four different totals, because
		// nothing here should ever line up with anything else.
		HoldFor("gitd_wb", 0.4, 0.9, 0.3, 1.2, 0.5, 0.8, 0.4, 1.1);
		HoldFor("gitd_wt", 0.7, 0.3, 1.1, 0.4, 0.9, 0.3, 1.3, 0.5);
		HoldFor("gitd_cg", 0.3, 1.3, 0.5, 0.7, 0.3, 1.1, 0.6, 0.9);
		HoldFor("gitd_fg", 1.1, 0.5, 0.8, 0.3, 1.2, 0.4, 0.9, 0.3);

		I("gitd_wb_coverage", 340);
		I("gitd_wt_coverage", 340);
		I("gitd_cg_coverage", 420);
		I("gitd_fg_coverage", 420);

		// THE WAVE, WITH EVERY TERM AT ONCE. Edge, brightness AND colour all
		// swinging, short wavelength, fast, sharp, fully detuned, every room
		// on its own phase, and a 180 degree climb so opposite surfaces are
		// in antiphase -- the floor crests exactly as the ceiling troughs.
		// This is the setting the wave was NOT designed for and it should be
		// available anyway.
		Wave(180.0, 5.5, 3.0, 4,   // shape 4: a shell, so it has volume too
		     0.60, 0.85, 0.80,
		     1.0,                  // maximum detune
		     1.0,                  // maximum scatter
		     180);

		// Darkness on, deep, with both spatial terms -- so the chaos still
		// falls off with distance and pools on the floor. Without it this is
		// just a bright mess; with it, it is a bright mess with depth, which
		// is at least a mess you can navigate.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 4);      // Crush
		I("ddz_preset", 5);
		I("ddz_desat", 0);     // every colour survives. That is the point.
		DeepDark(0.55, 2200.0, 0.30, 32.0, 400.0);

		I("ddz_fog", 110);

		B("fl_enabled", true);
		I("fl_range", 1600);
		F("fl_intensity", 1.5);
		F("fl_density", 2.0);
		F("fl_dust", 1.0);
		F("fl_dust_scale", 0.09);
		F("fl_dust_drift", 0.5);
		B("fl_bounce", true);

		// EIGHT BANDS, AND ONE OF EACH KIND OF THING A BAND CAN DO. Add,
		// lift, crush and recolour all running in the same train, with the
		// origin orbiting, drift on so they pull apart and fold back, and
		// speed rising as you lose health.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 8);
		I("gitd_ss_shape", 1);
		I("gitd_ss_origin", 2);       // follows you. It is about you.
		I("gitd_ss_direction", 2);    // ping-pong: it comes back
		I("gitd_ss_trigger", 0);
		I("gitd_ss_drive", 0);
		I("gitd_ss_range", 1536);
		F("gitd_ss_softness", 1.6);
		F("gitd_ss_intensity", 2.2);
		I("gitd_ss_thickness", 110);
		I("gitd_ss_trail", 320);
		B("gitd_ss_underlay", true);
		F("gitd_ss_drift", 0.55);     // they overtake each other
		F("gitd_ss_health_speed", 1.6);// and hurry as you weaken
		F("gitd_ss_spin", 140.0);
		F("gitd_ss_spin_radius", 420.0);
		I("gitd_ss_spin_colors", 8);
		B("gitd_ss_drop", false);
		B("gitd_ss_actors", false);   // still off: it walks the thinker list
		B("gitd_ss_light", false);    // all per pixel, via draw modes below

		for (int i = 1; i <= 7; i++) I("gitd_ss_gap" .. i, 14);

		static const int omgDraw[] = { 1, 4, 2, 1, 3, 4, 1, 2 };
		static const int omgShape[] = { 1, 4, 2, 5, 1, 3, 4, 1 };
		static const int omgCol[] = {
			0xFF00E6, 0x00FF66, 0xFFD400, 0x6600FF,
			0x00E5FF, 0xFF3300, 0x99FF00, 0xFF0066 };

		for (int i = 1; i <= 8; i++)
		{
			F("gitd_ss_speed" .. i, 260.0 + i * 55.0);
			I("gitd_ss_shape" .. i, omgShape[i - 1]);
			I("gitd_ss_thick" .. i, 80 + i * 30);
			I("gitd_ss_draw" .. i, omgDraw[i - 1]);
			I("gitd_ss_c" .. i, omgCol[i - 1]);
			I("gitd_ss_fx" .. i, 0);
		}
		B("gitd_ss_perband", true);
	}

	// Bloom with no restraint left: threshold on the floor so everything
	// blooms, amount high, and both the anamorphic streak and the chromatic
	// fringing on at once -- which no preset that respected the image would
	// ever do, and which is exactly why they are here.
	clearscope static void OmgWtfBloom()
	{
		Bloom(2.40, 0.15, 0.80, 1.0, 1.0, 1.0);
		EF("gl_bloom_anamorphic", 0.85);
		EF("gl_bloom_anamorphic_ratio", 4.0);
		EF("gl_bloom_chromatic", 0.9);
	}

	// Blackout's bloom is no bloom. There is nothing to bleed and a threshold
	// low enough to find something would only find the thing this preset is
	// defined by not having.
	clearscope static void BlackoutBloom()
	{
		EI("gl_bloom", 0);
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
