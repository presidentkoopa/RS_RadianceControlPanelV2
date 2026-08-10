// ===========================================================================
// A preset is an ENVIRONMENT, not a palette.
//
// It used to be 32 colours. That is a colour scheme, and a colour scheme is
// not a place. A place has a rhythm (how long each colour holds), a weather
// (what the sweeps do and how often), and a floor to stand on (how dark it
// is underneath). All four together, or the preset is just a swatch.
//
// So a profile writes ALL of it, and it writes it OVER whatever the player had.
// That is the deal and it is deliberate: choosing Low Power means the room
// becomes Low Power, not that it becomes Low Power's colours on top of your
// sweep settings. Anyone who wants their own tuning back picks preset Off,
// which writes nothing.
//
// A preset with no profile here still works exactly as before -- colours only,
// via GITD_Presets.SlotColor. Profiles are added one at a time as each preset
// is designed, so an undesigned preset degrades to what it always was rather
// than to something half-written.
// ===========================================================================
class GITD_PresetProfile abstract
{
	// ---- writers, all null-guarded ------------------------------------
	// Everything here writes this mod's own server cvars, which is allowed
	// from play scope. ENGINE cvars are not -- setting one throws "Attempt to
	// change CVAR outside of menu code" and aborts the whole function, which
	// is how GITD once silently stopped running entirely. Nothing in this file
	// touches an engine cvar, and nothing in it should.
	static void F(string n, double v) { let c = CVar.FindCVar(n); if (c) c.SetFloat(v); }
	static void I(string n, int v)    { let c = CVar.FindCVar(n); if (c) c.SetInt(v); }
	static void B(string n, bool v)   { let c = CVar.FindCVar(n); if (c) c.SetInt(v ? 1 : 0); }

	// Same value across all four lanes, which is the common case -- a preset
	// that wants the lanes to differ says so explicitly.
	static void Lanes(string suffix, double v)
	{
		static const string p[] = { "gitd_wb", "gitd_wt", "gitd_cg", "gitd_fg" };
		for (int i = 0; i < 4; i++) F(p[i] .. suffix, v);
	}

	static void LanesI(string suffix, int v)
	{
		static const string p[] = { "gitd_wb", "gitd_wt", "gitd_cg", "gitd_fg" };
		for (int i = 0; i < 4; i++) I(p[i] .. suffix, v);
	}

	// The rhythm. One hold time written to all 32 colour slots.
	static void Hold(double seconds)
	{
		static const string p[] = { "gitd_wb", "gitd_wt", "gitd_cg", "gitd_fg" };
		for (int i = 0; i < 4; i++)
			for (int s = 1; s <= 8; s++) F(p[i] .. "_hold" .. s, seconds);
	}

	static void SweepColor(int band, int packed)
	{
		I("gitd_ss_c" .. band, packed);
	}

	// ---- dispatch -------------------------------------------------------

	static void Apply(int preset)
	{
		switch (preset)
		{
			case 2: LowPower(); return;
			default: return;   // no profile yet: colours only, as before
		}
	}

	// =====================================================================
	// 2. LOW POWER -- the grid is failing
	//
	// WHAT DOOM IS. Not a fantasy dungeon: a corporate mining and research
	// facility on a moon, built by people who cut corners, running machinery
	// nobody has maintained since the incident. Concrete, rust, sodium
	// corridor lamps, and a computer somewhere still trying to do its job.
	//
	// WHAT LOW POWER IS. The grid is not dead. Something down in the plant is
	// still fighting to keep the lights on and mostly succeeding, and every
	// few minutes it loses a round. The horror is not the dark -- Blackout is
	// the dark. The horror is that the dark is SCHEDULED, and that whatever
	// is keeping it away is losing.
	//
	// The whole preset is one four-beat sentence, spoken every three and a
	// half minutes: it catches -- it holds -- it slips -- it goes.
	// =====================================================================
	static void LowPower()
	{
		// ---- the baseline: sodium light, almost gone --------------------
		//
		// Not violet-for-mood. This is a facility, so the light it has left
		// is the light it was built with -- dying sodium and fluorescent,
		// which go ORANGE-GREY as they fail, with the faintest cold cast off
		// the emergency circuit that is still nominally alive.
		//
		// Hue 34 is that dead-lamp amber. The spread is tiny, so all four
		// lanes read as one failing colour rather than a palette; saturation
		// and brightness both near the floor because there is no energy here
		// to be colourful with.
		F("gitd_pc_hue", 34.0);
		F("gitd_pc_spread", 26.0);
		F("gitd_pc_sat", 0.30);
		F("gitd_pc_satvar", 0.10);
		F("gitd_pc_val", 0.16);
		F("gitd_pc_valvar", 0.05);

		// ---- and it does not move ---------------------------------------
		//
		// SNAP, not fade, on nine-second holds. This is the single most
		// important decision in the preset: a dying grid does not shimmer,
		// pulse or breathe. It sits at one value until it changes to
		// another. Anything smoother reads as ambience, and ambience is
		// comfortable -- the room should feel switched off, not asleep.
		//
		// Coverage low so the glow clings to the bottom of walls and the
		// edges of floors, the way real light pools when there is not enough
		// of it to fill a space.
		LanesI("_enabled", 1);
		LanesI("_pattern", 0);
		LanesI("_coverage", 56);
		Lanes("_intensity", 0.50);
		Lanes("_saturation", 0.75);
		LanesI("_anim", 0);
		LanesI("_slots", 8);
		Hold(9.0);

		// ---- the floor it stands on -------------------------------------
		B("gitd_dd_enabled", true);
		I("ddz_mode", 2);      // Compress -- proportional, keeps some shape
		I("ddz_preset", 4);    // Oppressive
		I("ddz_desat", 70);    // colour vision failing along with the lamps

		// ---- the event --------------------------------------------------
		//
		// range / speed sets the wait: 8192 over 40 is about 205 seconds of
		// nothing at all. Sweep 1 is the clock, so its speed is the one that
		// decides the period -- the others are expressed against it.
		//
		// Every band after the first is SLOWER than the one before, so the
		// four stretch further apart the further they travel. The failure
		// drags. Nothing overtakes, because a power cut is not a race.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 4);
		I("gitd_ss_shape", 1);        // a ring: it comes from the plant
		I("gitd_ss_origin", 0);       // wherever that is on this map
		I("gitd_ss_direction", 0);    // outward, then silence
		I("gitd_ss_trigger", 0);      // free-running: it is a schedule
		I("gitd_ss_drive", 0);
		I("gitd_ss_range", 8192);
		F("gitd_ss_softness", 3.0);   // soft: a wave of power, not a scanline
		F("gitd_ss_intensity", 1.0);
		I("gitd_ss_trail", 240);      // a wake, so it reads as travelling
		F("gitd_ss_drift", 0.0);
		F("gitd_ss_health_speed", 0.0);
		F("gitd_ss_spin", 0.0);
		F("gitd_ss_spin_radius", 0.0);
		I("gitd_ss_spin_colors", 0);
		I("gitd_ss_thickness", 200);  // the shared default; bands override

		// THE PER-SECTOR LIGHT PATH IS OFF, and that is the point of the
		// rewrite. It changed a whole room at once off one measurement at
		// the sector's centre, so a hall wider than the band lit in one go
		// while you could still see the line crossing the far wall. The draw
		// modes below do it per pixel instead. Leaving both on would apply
		// the same idea twice, once well and once chunkily.
		B("gitd_ss_light", false);
		B("gitd_ss_perband", true);
		for (int i = 1; i <= 8; i++) I("gitd_ss_fx" .. i, 0);

		// ---- the four beats ---------------------------------------------
		//
		//   1  IT CATCHES.  A hard warm flash, thin and quick -- the arc as
		//                   something upstream bites. This one ADDS, because
		//                   it is a light source igniting, and add is the
		//                   only mode whose colour you actually see.
		//
		//   2  IT HOLDS.    REVEAL, wide and slower. Not a lamp being carried
		//                   past: the darkness is pulled aside and the room's
		//                   own colour comes back, per pixel, in a moving
		//                   strip. For a few seconds you see where you are.
		//
		//   3  IT SLIPS.    SHADOW, gentle. The dark closes again from the
		//                   same direction the light came.
		//
		//   4  IT GOES.     SHADOW, hard and widest -- below baseline, so the
		//                   moment after the failure is darker than the
		//                   minute before it. Then the wake fades and the
		//                   tired amber creeps back on its own, because the
		//                   compositor hands a sector's light back the moment
		//                   nothing is asking for it.
		I("gitd_ss_draw1", 1);  I("gitd_ss_thick1", 40);   F("gitd_ss_speed1", 40.0);
		I("gitd_ss_draw2", 2);  I("gitd_ss_thick2", 240);  F("gitd_ss_speed2", 34.0);
		I("gitd_ss_draw3", 3);  I("gitd_ss_thick3", 280);  F("gitd_ss_speed3", 26.0);
		I("gitd_ss_draw4", 3);  I("gitd_ss_thick4", 340);  F("gitd_ss_speed4", 20.0);
		for (int i = 5; i <= 8; i++) { I("gitd_ss_draw" .. i, 1); I("gitd_ss_thick" .. i, 0); }

		// Beats one to two is fast -- the catch and the flood are one event.
		// Two to three is the pause where you get to look around. Three to
		// four is the slow slide out.
		I("gitd_ss_gap1", 45);    // 1.3 s
		I("gitd_ss_gap2", 75);    // 2.1 s
		I("gitd_ss_gap3", 100);   // 2.9 s

		// COLOUR ONLY MATTERS FOR BAND 1. Reveal and Shadow multiply what is
		// already on the pixel and never introduce a hue of their own -- a
		// reveal that tinted would be showing you its colour, not the room's,
		// which is the opposite of revealing. So band 1 carries the hot
		// filament orange and the rest carry their intensity in the alpha the
		// slider sets; their RGB is written for the menu swatch's sake and
		// for anyone who switches them back to Add.
		SweepColor(1, 0xFFA24C);   // the arc: hot, orange, brief
		SweepColor(2, 0xC08A5A);
		SweepColor(3, 0x4A3A30);
		SweepColor(4, 0x241C18);
	}
}
