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

	// Eight holds for ONE lane. Hold() gives all four lanes the same rhythm,
	// which is right for a preset that wants a pulse and useless for one that
	// wants the four to drift apart and never re-sync.
	static void HoldFor(string pre, double a, double b, double c, double d,
	                    double e, double f, double g, double h)
	{
		F(pre .. "_hold1", a); F(pre .. "_hold2", b);
		F(pre .. "_hold3", c); F(pre .. "_hold4", d);
		F(pre .. "_hold5", e); F(pre .. "_hold6", f);
		F(pre .. "_hold7", g); F(pre .. "_hold8", h);
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
			case 3: RedAlert(); return;
			case 6: NeonUnison(); return;
			case 7: NeonChaos(); return;
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

		// TRANSITION SPEED MATTERS EVEN FOR SNAP. The phase clock is what
		// advances the slot, so a slow transition delays the NEXT colour even
		// when the crossfade itself is never drawn. Left at the default this
		// preset held each colour for sixteen seconds rather than nine, and
		// the Duration slider was describing less than half of what you saw.
		Lanes("_speed", 0.050);      // ~0.6s, so 9s means 9s
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

	// =====================================================================
	// 3. RED ALERT -- containment breach
	//
	// This absorbed Furnace, and the merge is the point rather than a
	// compromise. Two hot, saturated, urgent presets sitting side by side
	// would have been one preset and a variant of it -- but they were urgent
	// about DIFFERENT THINGS, and putting them in one room turns two half
	// ideas into a whole one:
	//
	//     the alarm            -- the facility's response
	//     the heat rising      -- what it is responding TO
	//
	// You are standing between a building that has noticed something and the
	// something it noticed. Neither half means much alone. Together they are
	// a place.
	//
	// It is also the first preset where one train disagrees with itself about
	// SHAPE: bands 1 and 2 are planes climbing out of the floor while 3, 4 and
	// 5 are rings orbiting your feet. That was impossible until per-band
	// origins and shapes landed, and it is the clearest thing to point at as
	// proof they work.
	// =====================================================================
	static void RedAlert()
	{
		// ---- the room, under emergency power ----------------------------
		//
		// An alarm means the emergency circuit is ON, so this is not dark the
		// way Low Power is dark -- it is dim and RED and entirely legible.
		// The hue sits at 5 rather than pure red and spreads to 48, which
		// reaches orange: wide enough that the heat below and the alarm above
		// belong to one family, narrow enough that all four lanes still say
		// the same thing. A warning that disagrees with itself is decoration.
		F("gitd_pc_hue", 5.0);
		F("gitd_pc_spread", 48.0);
		F("gitd_pc_sat", 0.90);
		F("gitd_pc_satvar", 0.08);
		F("gitd_pc_val", 0.38);
		F("gitd_pc_valvar", 0.28);

		// BREATHE, not snap. Low Power sits still because it is dying; this
		// throbs because something is still running and wants you to know.
		LanesI("_enabled", 1);
		LanesI("_pattern", 3);
		LanesI("_coverage", 144);
		Lanes("_intensity", 1.00);
		Lanes("_saturation", 1.00);
		LanesI("_anim", 0);
		LanesI("_slots", 8);

		// Breathe draws the transition, so its LENGTH is the pulse. At the
		// default this throbbed on a seven-second cycle -- becalmed, for a
		// preset whose entire job is urgency. Just over a second gives the
		// hard alarm rhythm the beacon is turning against.
		Lanes("_speed", 0.030);      // ~1.2s in, 1.4s held
		Hold(1.4);

		// Subtract rather than Compress: emergency lighting is uniformly dim
		// rather than proportionally scaled, and a flat fade is what that
		// looks like. Colour drain stays LOW -- draining an alarm is the one
		// place it would be actively wrong.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 1);
		I("ddz_preset", 3);
		I("ddz_desat", 20);

		// ---- one train, two jobs ----------------------------------------
		//
		// range over speed 1 is the shared clock: 1024 over 200 is about five
		// seconds, and everything in the train answers to it. The BEACON does
		// not, though -- the spin is its own clock at 80 degrees a second, so
		// the lamp comes round every four and a half seconds against a
		// five-second pulse. Close enough to feel related, different enough
		// that they never lock into a pattern you can predict.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 5);
		I("gitd_ss_shape", 1);        // the shared default; bands override
		I("gitd_ss_origin", 2);       // you are the centre of this
		I("gitd_ss_direction", 0);
		I("gitd_ss_trigger", 0);
		I("gitd_ss_drive", 0);
		I("gitd_ss_range", 1024);
		F("gitd_ss_softness", 2.2);
		F("gitd_ss_intensity", 1.6);
		I("gitd_ss_trail", 160);
		F("gitd_ss_drift", 0.0);
		F("gitd_ss_health_speed", 0.0);
		I("gitd_ss_thickness", 120);

		F("gitd_ss_spin", 80.0);
		F("gitd_ss_spin_radius", 320.0);
		I("gitd_ss_spin_colors", 0);

		B("gitd_ss_light", false);    // per pixel; the coarse path stays off
		B("gitd_ss_perband", true);
		for (int i = 1; i <= 8; i++) I("gitd_ss_fx" .. i, 0);

		// THE HEAT, first in the train so it carries no lag.
		//
		// Shape 5 is a rising PLANE, not a column -- it measures height and
		// ignores where you are standing, which is exactly right for heat
		// coming up through a floor and also why the spin below cannot
		// disturb it. Band 1 is the wide front, band 2 the hotter core
		// climbing just behind it. Both ADD, because they are the light.
		I("gitd_ss_shape1", 5);  I("gitd_ss_draw1", 1);
		I("gitd_ss_thick1", 260); F("gitd_ss_speed1", 200.0);
		I("gitd_ss_shape2", 5);  I("gitd_ss_draw2", 1);
		I("gitd_ss_thick2", 160); F("gitd_ss_speed2", 180.0);

		// THE ALARM, orbiting you. Two lamps and what they show.
		//
		// Rings, so they wrap the room; a hair thinner and faster than the
		// heat so they read as machinery rather than weather. Band 5 REVEALS
		// behind the pair, which is the moment you actually see where you are
		// rather than just seeing red -- and it is the only band whose colour
		// does nothing, since reveal multiplies what is already there.
		I("gitd_ss_shape3", 1);  I("gitd_ss_draw3", 1);
		I("gitd_ss_thick3", 70);  F("gitd_ss_speed3", 200.0);
		I("gitd_ss_shape4", 1);  I("gitd_ss_draw4", 1);
		I("gitd_ss_thick4", 90);  F("gitd_ss_speed4", 190.0);
		I("gitd_ss_shape5", 1);  I("gitd_ss_draw5", 2);
		I("gitd_ss_thick5", 200); F("gitd_ss_speed5", 175.0);

		for (int i = 6; i <= 8; i++)
		{
			I("gitd_ss_shape" .. i, 0);
			I("gitd_ss_draw" .. i, 1);
			I("gitd_ss_thick" .. i, 0);
		}

		// Gaps are tics, and a band's lag is that many tics AT SWEEP ONE'S
		// SPEED -- so a slow band with a big lag can start so far back it
		// never arrives before the cycle resets. Kept tight for that reason
		// as much as for the rhythm.
		I("gitd_ss_gap1", 12);   // heat core behind the front
		I("gitd_ss_gap2", 20);   // then the first lamp
		I("gitd_ss_gap3", 18);   // its hot edge
		I("gitd_ss_gap4", 22);   // and the reveal

		SweepColor(1, 0xFF7A20);   // the heat: furnace orange
		SweepColor(2, 0xFFC040);   // its core: near-white yellow
		SweepColor(3, 0xFF1810);   // the alarm itself
		SweepColor(4, 0xFF5A18);   // its hot edge
		SweepColor(5, 0x904038);   // reveal ignores rgb; kept for the swatch
	}

	// =====================================================================
	// 7. NEON CHAOS -- the signal breaks
	//
	// WHERE NEON BELONGS IN DOOM. Not the techbase and not hell: both of
	// those have a palette and keep to it. Neon belongs to the moment the
	// machine stops agreeing with itself -- the teleporter mid-transit, the
	// screen when the cable is kicked, a lighting rig with every channel
	// arguing. Doom is a game about being inside broken machinery, and this
	// is the preset where the machinery breaks LOUDLY rather than quietly.
	//
	// Low Power is a system that has given up. Red Alert is a system doing
	// its job under pressure. This is a system having a seizure -- and what
	// separates that from a screensaver is that a seizure has no tempo you
	// can settle into. So nothing here shares a clock with anything else, and
	// that is the entire design.
	//
	// ONE RULE holds it together: everything stays fully saturated and
	// bright. Chaos in muddy colours is noise. Chaos where every element is
	// unmistakably ITSELF reads as too much happening at once, which is the
	// intent.
	// =====================================================================
	static void NeonChaos()
	{
		// ---- 32 colours, maximum disagreement ---------------------------
		//
		// Spread 360 is the whole wheel, and because each lane takes its own
		// QUARTER of the spread, the four land in completely different colour
		// families -- floor cyan while the ceiling is orange. Every other
		// preset keeps this narrow so the lanes agree; this is the one that
		// wants them not to.
		//
		// Saturation pinned near 1 with almost no variance is the rule above,
		// enforced: the generator is never allowed to wander toward grey.
		F("gitd_pc_hue", 0.0);
		F("gitd_pc_spread", 360.0);
		F("gitd_pc_sat", 0.98);
		F("gitd_pc_satvar", 0.02);
		F("gitd_pc_val", 0.85);
		F("gitd_pc_valvar", 0.15);

		LanesI("_enabled", 1);
		LanesI("_coverage", 200);
		Lanes("_intensity", 1.30);
		Lanes("_saturation", 1.00);
		LanesI("_slots", 8);

		// A DIFFERENT TRANSITION AND ANIMATION PER LANE. Every other preset
		// sets these four the same, because agreement is what makes a mood.
		// Disagreement is the mood here.
		I("gitd_wb_pattern", 2);  I("gitd_wb_anim", 1);   // flash, ripple out
		I("gitd_wt_pattern", 1);  I("gitd_wt_anim", 0);   // fade, still
		I("gitd_cg_pattern", 4);  I("gitd_cg_anim", 2);   // ping-pong, east
		I("gitd_fg_pattern", 3);  I("gitd_fg_anim", 3);   // breathe, north

		Lanes("_anim_speed", 1.4);
		Lanes("_anim_depth", 0.7);
		Lanes("_anim_length", 384.0);
		F("gitd_wb_anim_phase", 0.0);   F("gitd_wt_anim_phase", 0.25);
		F("gitd_cg_anim_phase", 0.5);   F("gitd_fg_anim_phase", 0.75);

		// HOLD TIMES THAT NEVER RE-SYNC. Each lane's eight durations sum to a
		// different total and none divides another, so the four rotations
		// drift apart and the room never repeats a combination you have
		// already seen. This is the single thing separating chaos from a fast
		// loop, and it is only possible because durations are per COLOUR
		// rather than per lane.
		// Fast, or the transitions swamp the holds and the careful desync
		// below never surfaces: at the default every colour took seven
		// seconds to arrive, which is longer than most of these hold for.
		Lanes("_speed", 0.040);      // ~0.9s

		HoldFor("gitd_wb", 0.5, 1.0, 0.5, 1.5, 0.5, 1.0, 0.5, 2.0);   // 7.5s
		HoldFor("gitd_wt", 0.7, 0.7, 2.1, 0.7, 1.4, 0.7, 0.7, 2.8);   // 9.8s
		HoldFor("gitd_cg", 1.1, 0.6, 1.1, 0.6, 2.2, 0.6, 1.1, 0.6);   // 7.9s
		HoldFor("gitd_fg", 0.9, 1.8, 0.9, 0.9, 2.7, 0.9, 1.8, 0.9);   // 10.8s

		// ---- dark enough for neon to mean something ---------------------
		// Neon needs somewhere to be bright AGAINST -- but not Low Power
		// dark, because you have to see all of it at once or the chaos is
		// wasted. Colour drain is ZERO: draining neon is the one setting that
		// would destroy the entire preset.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 2);      // Compress
		I("ddz_preset", 2);    // Murky
		I("ddz_desat", 0);

		// ---- all eight sweeps, none of them agreeing --------------------
		//
		// Every band a different shape, speed and job. Because the speeds all
		// differ they OVERTAKE constantly, and because drift is high the
		// crossings land somewhere new every cycle -- the one thing this
		// system does that cannot be authored, only set in motion.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 8);
		I("gitd_ss_shape", 1);
		I("gitd_ss_origin", 2);       // you are the centre of the storm
		I("gitd_ss_direction", 2);    // out and back: it never resolves
		I("gitd_ss_trigger", 0);
		I("gitd_ss_drive", 0);
		I("gitd_ss_range", 2048);
		F("gitd_ss_softness", 1.6);
		F("gitd_ss_intensity", 1.5);
		I("gitd_ss_trail", 260);
		F("gitd_ss_drift", 0.40);     // high: the train tears itself apart
		F("gitd_ss_health_speed", 0.0);
		I("gitd_ss_thickness", 140);

		// A slow orbit under everything, so even the geometry keeps moving.
		// THE ROLODEX IS ON: band colour is picked by where the spin
		// currently is and cross-faded between neighbours, so all eight are
		// thumbed through continuously rather than each band owning one.
		F("gitd_ss_spin", 40.0);
		F("gitd_ss_spin_radius", 200.0);
		I("gitd_ss_spin_colors", 8);

		B("gitd_ss_light", false);
		B("gitd_ss_perband", true);
		for (int i = 1; i <= 8; i++) I("gitd_ss_fx" .. i, 0);

		// Shapes cycle through everything the engine has. Draw modes mix all
		// four: most ADD, one REVEALS, one CRUSHES, and two RECOLOUR -- so
		// the palette itself gets dragged around by the bands crossing it.
		static const int shp[] = { 1, 2, 5, 3, 1, 5, 2, 1 };
		static const int drw[] = { 1, 4, 1, 4, 2, 1, 1, 3 };
		static const int thk[] = { 90, 220, 160, 240, 200, 130, 180, 110 };
		static const double spd[] = { 300.0, 250.0, 190.0, 340.0, 220.0, 400.0, 170.0, 280.0 };
		for (int i = 0; i < 8; i++)
		{
			I("gitd_ss_shape" .. (i + 1), shp[i]);
			I("gitd_ss_draw"  .. (i + 1), drw[i]);
			I("gitd_ss_thick" .. (i + 1), thk[i]);
			F("gitd_ss_speed" .. (i + 1), spd[i]);
		}

		// Uneven gaps, for the same reason as the hold times.
		I("gitd_ss_gap1", 14);  I("gitd_ss_gap2", 26);
		I("gitd_ss_gap3", 9);   I("gitd_ss_gap4", 33);
		I("gitd_ss_gap5", 17);  I("gitd_ss_gap6", 21);
		I("gitd_ss_gap7", 11);

		// The eight neon primaries. With the rolodex on these are a WHEEL
		// rather than eight assignments, so the ORDER matters more than the
		// pairing -- adjacent entries are what cross-fade into each other.
		SweepColor(1, 0xFF00A0);   // magenta
		SweepColor(2, 0xFF3000);   // orange-red
		SweepColor(3, 0xFFD000);   // amber
		SweepColor(4, 0x40FF00);   // acid green
		SweepColor(5, 0x00FFC0);   // aqua
		SweepColor(6, 0x00A0FF);   // cyan-blue
		SweepColor(7, 0x6000FF);   // violet
		SweepColor(8, 0xFF00E0);   // hot pink, back round to magenta

		// ---- and the air itself -----------------------------------------
		//
		// The flashlight's beam is VOLUMETRIC -- it lights the air rather
		// than only what it lands on -- and every part of it is a cvar, so a
		// preset can own it. Here the beam runs the same eight colours on a
		// fast cycle, the haze is thick enough that the shaft reads as solid,
		// and the air carries slow drifting motes. Sweep a coloured beam
		// through that dust and the motes take the colour: the chaos stops
		// being something on the walls and becomes something you are standing
		// IN. It is the only preset where the volumetrics are part of the
		// idea rather than a separate feature.
		//
		// fl_enabled is deliberately NOT touched. A preset may decide what
		// your torch looks like; whether you are carrying one is yours.
		I("fl_slots", 8);
		I("fl_random", 0);
		I("fl_pattern", 1);        // fade between them
		F("fl_speed", 0.030);      // fast: the beam never settles either
		F("fl_intensity", 1.40);
		F("fl_density", 1.80);     // thick haze, so the shaft reads as solid
		F("fl_dust", 0.60);
		F("fl_dust_scale", 0.020); // fine motes
		F("fl_dust_drift", 20.0);
		F("fl_falloff", 1.20);
		I("fl_bounce", 1);

		// The torch runs the same wheel as the sweeps, so the beam and the
		// bands are never a different argument.
		static const int neon[] = { 0xFF00A0, 0xFF3000, 0xFFD000, 0x40FF00,
		                            0x00FFC0, 0x00A0FF, 0x6000FF, 0xFF00E0 };
		for (int i = 0; i < 8; i++) I("fl_c" .. (i + 1), neon[i]);
	}

	// =====================================================================
	// 6. NEON UNISON -- everything agrees
	//
	// Chaos's twin, and the pair only work because they are built from the
	// same parts pointed in opposite directions. Chaos gives every lane its
	// own hue quarter, its own transition, its own animation and eight hold
	// times that never re-sync. Unison gives all four the SAME hue, the SAME
	// transition, the SAME animation and one shared hold -- so the whole room
	// changes colour as one object.
	//
	// That is the effect worth having and it is the one thing four
	// independent lanes are usually incapable of: a wall, its skirting, the
	// ceiling and the floor all arriving at the same violet at the same
	// instant, then all leaving it together. It does not read as four lit
	// surfaces. It reads as the room being ONE surface that is lit.
	//
	// And it is only possible now that the sweeps ride OVER the lanes instead
	// of replacing them: the bands are the thing that breaks the unison for a
	// moment, and there has to be a unison there to break.
	// =====================================================================
	static void NeonUnison()
	{
		// ---- one colour, four surfaces ----------------------------------
		//
		// Spread 40 is the tightest of any preset here. Each lane still takes
		// its own quarter, but a quarter of 40 degrees is ten -- close enough
		// that the four are shades of one hue rather than four hues. The
		// eight slots then walk that hue around the wheel over the rotation,
		// so the room is always one colour and never the same one for long.
		//
		// Value variance is small on purpose: if the lanes agree on hue but
		// disagree on brightness, the illusion of a single lit object breaks
		// immediately. Unison is as much about matching BRIGHTNESS as colour.
		F("gitd_pc_hue", 300.0);      // start on violet; the slots travel
		F("gitd_pc_spread", 40.0);
		F("gitd_pc_sat", 0.95);
		F("gitd_pc_satvar", 0.03);
		F("gitd_pc_val", 0.80);
		F("gitd_pc_valvar", 0.06);

		LanesI("_enabled", 1);
		LanesI("_slots", 8);
		LanesI("_coverage", 208);     // generous: surfaces should meet
		Lanes("_intensity", 1.20);
		Lanes("_saturation", 1.00);

		// FADE, everywhere, at the same speed. Snap would let you see the
		// four switch and notice they are four. A fade of the same length
		// starting at the same instant is what fuses them.
		LanesI("_pattern", 1);
		Lanes("_speed", 0.0060);

		// One hold for all thirty-two slots -- the whole point. Four seconds
		// is long enough to register the colour as a STATE rather than as a
		// transition you happened to catch.
		Hold(4.0);

		// Animation on, identical, and CRUCIALLY in phase. Every other preset
		// that animates offsets the lanes so they chase each other; here they
		// must not. Zero phase on all four means the ripple crosses the whole
		// room as one wave rather than four.
		LanesI("_anim", 1);           // ripple from centre
		Lanes("_anim_speed", 0.5);
		Lanes("_anim_depth", 0.35);
		Lanes("_anim_length", 768.0);
		Lanes("_anim_phase", 0.0);

		// Bleed on, which matters more here than anywhere: it pulls each
		// lane's colour toward the lanes it physically meets, so corners stop
		// being seams. In a preset about the room being one object, a visible
		// join is the failure case.
		LanesI("_bleed", 1);

		// ---- the floor --------------------------------------------------
		// Dark enough that saturated colour is the brightest thing present,
		// no darker. And no colour drain at all -- the same reasoning as
		// Chaos, for a preset that is entirely about hue.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 2);      // Compress
		I("ddz_preset", 3);    // Dismal
		I("ddz_desat", 0);

		// ---- and one wave, to prove the unison is deliberate ------------
		//
		// A single slow shell, wide and soft, on a thirty-second cycle. It
		// RECOLOURS rather than adds: as it passes it drags the glow toward
		// its own colour and lets go, so for a few seconds part of the room
		// disagrees with the rest -- and then rejoins.
		//
		// That is the whole argument for the preset. Perfect agreement is
		// only legible when something occasionally breaks it; a room that
		// has never been out of unison just looks monochrome.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 1);
		I("gitd_ss_shape", 4);        // shell: it arrives in three dimensions
		I("gitd_ss_origin", 0);       // map centre, indifferent to you
		I("gitd_ss_direction", 0);
		I("gitd_ss_trigger", 0);
		I("gitd_ss_drive", 0);
		I("gitd_ss_range", 6144);
		F("gitd_ss_softness", 4.0);   // very soft: no edge to catch on
		F("gitd_ss_intensity", 1.0);
		I("gitd_ss_trail", 0);
		F("gitd_ss_drift", 0.0);
		F("gitd_ss_health_speed", 0.0);
		I("gitd_ss_thickness", 900);  // wide, so the disagreement is gradual
		F("gitd_ss_spin", 0.0);
		F("gitd_ss_spin_radius", 0.0);
		I("gitd_ss_spin_colors", 0);

		B("gitd_ss_light", false);
		B("gitd_ss_perband", true);
		for (int i = 1; i <= 8; i++) I("gitd_ss_fx" .. i, 0);

		I("gitd_ss_shape1", 0);       // inherit the shell
		I("gitd_ss_draw1", 4);        // RECOLOUR -- the point of the wave
		I("gitd_ss_thick1", 0);
		F("gitd_ss_speed1", 200.0);   // 6144 / 200 = about half a minute
		for (int i = 2; i <= 8; i++)
		{
			I("gitd_ss_shape" .. i, 0);
			I("gitd_ss_draw" .. i, 1);
			I("gitd_ss_thick" .. i, 0);
		}

		// The complement of wherever the palette currently is, so the band is
		// always the one thing in the room that disagrees.
		SweepColor(1, 0x30FFB0);
		SweepColor(2, 0x30FFB0);
		SweepColor(3, 0x30FFB0);
		SweepColor(4, 0x30FFB0);
		SweepColor(5, 0x30FFB0);
		SweepColor(6, 0x30FFB0);
		SweepColor(7, 0x30FFB0);
		SweepColor(8, 0x30FFB0);
	}
}
