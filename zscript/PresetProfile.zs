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
	// It is not dead. Something down in the plant is still trying to keep the
	// lights on and mostly succeeding, and every few minutes it stumbles: a
	// surge as a system cuts in, a sag as it loses the argument, a moment of
	// less-than-nothing, and then the same tired baseline. The horror is not
	// the dark. It is that the dark is SCHEDULED.
	// =====================================================================
	static void LowPower()
	{
		// ---- palette: grey-purple, barely there -------------------------
		// Narrow hue spread so the four lanes almost agree -- this should
		// read as one failing colour, not as a scheme. Saturation and
		// brightness both near the floor, with small swings: a dying grid
		// has no energy to vary with.
		F("gitd_pc_hue", 275.0);      // violet, drained
		F("gitd_pc_spread", 30.0);    // all four lanes within one family
		F("gitd_pc_sat", 0.16);
		F("gitd_pc_satvar", 0.08);
		F("gitd_pc_val", 0.18);
		F("gitd_pc_valvar", 0.06);

		// ---- the lanes sit still ----------------------------------------
		// SNAP, not fade. A dead grid does not shimmer -- it holds, and then
		// it changes. Eight seconds a colour, so across a minute you get
		// seven or eight almost-imperceptible shifts and nothing that reads
		// as an animation.
		LanesI("_enabled", 1);
		LanesI("_pattern", 0);        // Snap
		LanesI("_coverage", 64);      // clings to edges, fills nothing
		Lanes("_intensity", 0.55);
		Lanes("_saturation", 0.70);
		LanesI("_anim", 0);           // no travelling animation at all
		LanesI("_slots", 8);
		Hold(8.0);

		// ---- the floor it stands on -------------------------------------
		B("gitd_dd_enabled", true);
		I("ddz_mode", 2);             // Compress
		I("ddz_preset", 4);           // Oppressive
		I("ddz_desat", 60);

		// ---- the failure, once every three and a half minutes -----------
		//
		// range / speed sets how often: 8192 / 40 is about 205 seconds of
		// nothing. Then four bands arrive within thirteen seconds of each
		// other and the grid audibly loses a fight.
		//
		// Thickness 120 at speed 40 means each band takes six seconds to
		// pass you -- a wave of power moving through the building, not a
		// scanline. Soft edges for the same reason.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 4);
		I("gitd_ss_shape", 1);        // ring
		I("gitd_ss_origin", 0);       // from the plant, wherever that is
		I("gitd_ss_direction", 0);    // outward, then wait
		I("gitd_ss_trigger", 0);      // free-running: it is a schedule
		I("gitd_ss_drive", 0);
		I("gitd_ss_range", 8192);
		I("gitd_ss_thickness", 120);
		F("gitd_ss_softness", 3.0);
		F("gitd_ss_intensity", 1.2);
		I("gitd_ss_trail", 200);      // a wake, so it reads as travelling
		F("gitd_ss_drift", 0.0);
		F("gitd_ss_health_speed", 0.0);
		F("gitd_ss_spin", 0.0);
		F("gitd_ss_spin_radius", 0.0);
		I("gitd_ss_spin_colors", 0);

		for (int i = 1; i <= 8; i++) F("gitd_ss_speed" .. i, 40.0);

		// Two seconds, two seconds, three. Tight enough to read as one
		// event, loose enough that you can count the stages.
		I("gitd_ss_gap1", 70);
		I("gitd_ss_gap2", 70);
		I("gitd_ss_gap3", 105);

		// ---- the shape of the failure -----------------------------------
		//
		//   1  +100  a system cuts in and the corridor floods
		//   2   +40  it holds, weaker
		//   3   -80  losing it
		//   4  -128  out, darker than baseline
		//
		// Then minutes of nothing, and the baseline creeps back on its own
		// because the compositor hands every sector's light back the moment
		// no band is asking for it.
		B("gitd_ss_light", true);
		B("gitd_ss_perband", true);
		I("gitd_ss_fx1", 1);  I("gitd_ss_amount1", 100);   // brighten
		I("gitd_ss_fx2", 1);  I("gitd_ss_amount2", 40);    // brighten, weaker
		I("gitd_ss_fx3", 2);  I("gitd_ss_amount3", 80);    // darken
		I("gitd_ss_fx4", 2);  I("gitd_ss_amount4", 128);   // darken, hard
		for (int i = 5; i <= 8; i++) I("gitd_ss_fx" .. i, 0);

		// The surge runs warm -- a filament heating before it gives up --
		// and the collapse runs cold. Same family as the baseline so the
		// event belongs to the room rather than visiting it.
		SweepColor(1, 0x8A6A78);
		SweepColor(2, 0x6A5566);
		SweepColor(3, 0x3A2E4A);
		SweepColor(4, 0x241C33);
	}
}
