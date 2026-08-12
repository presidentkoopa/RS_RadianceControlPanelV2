// ===========================================================================
// EVERY SETTING THAT REACHES THE SCREEN WITHOUT TOUCHING THE WORLD.
//
// Two systems now live in the fragment shader rather than in a per-sector
// script loop: the glow wave, which moves a glow's edge along a surface, and
// darkness, which runs the same four curves against each fragment's own light
// instead of once per room. Neither is playsim state. Both are just numbers
// the renderer reads every frame.
//
// THAT IS WHY THIS CLASS EXISTS SEPARATELY. It is called from two places:
//
//   GITD_Handler.Apply       once a tic, while the world runs
//   DarkDoomZ_OptionMenu     once a menu tic, while it is paused
//
// A menu pauses the game in single player, so a slider used to do nothing
// until you backed out of the page. The natives these call are clearscope for
// exactly this reason -- nothing downstream of them can change what happens
// in the world, so a menu may push them safely, and the picture moves as the
// slider moves.
//
// ONE IMPLEMENTATION, TWO CALLERS. If the menu had its own copy of this the
// two would drift, and the bug would be "it looks different once you close
// the menu", which is the worst kind: it only appears after you stop looking.
//
// The one thing that cannot be done from here is resolving a sweep or wave
// ORIGIN -- "follows you", "the nearest live monster" -- because that reads
// the playsim. GITD_Handler pushes the origin from the world tic and it keeps
// its last value while the game is stopped, which is correct: nothing in the
// world is moving either.
// ===========================================================================
class GITD_Render abstract
{
	clearscope static double GetF(string name, double def)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetFloat() : def;
	}

	clearscope static int GetI(string name, int def)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetInt() : def;
	}

	clearscope static bool GetB(string name, bool def)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetBool() : def;
	}

	clearscope static void PushAll()
	{
		PushWave();
		PushDarkness();
		PushFog();
		PushTornado();
		PushSweepFill();
	}

	// ---- the tornado -----------------------------------------------------
	//
	// The same fog, gathered around a vertical axis instead of spread under a
	// plane. It is a separate push rather than part of PushFog because it is
	// separately switchable: a room can have a knee-high layer and no funnel,
	// a funnel standing in clear air, or both.
	//
	// IT IS THE MOST EXPENSIVE THING IN THE SHADER and it does not early out
	// the way a floor layer does -- a layer stops mattering the moment you
	// look up, a funnel fills the screen from any angle you can see it. Off
	// costs nothing, because density 0 is tested before any of the maths.
	//
	// The centre is left hollow so you can stand inside one and see out. That
	// is not a compromise, it is what a real one looks like from the inside.
	clearscope static void PushTornado(bool haveAnchor = false, double ax = 0, double ay = 0)
	{
		if (!GetB("gitd_tornado_enabled", false))
		{
			level.SetTornado(0, 0, 0, 0, 0, 0, 0.0);
			return;
		}

		// WHERE IT STANDS. A fixed world point off two sliders by default, and
		// the handler passes an anchor in when the origin mode says the funnel
		// should follow something -- you, the nearest monster, where you last
		// fired. Same split, and for the same reason, as the glow wave's origin:
		// resolving "the nearest live monster" reads the playsim, and this
		// function has to stay callable from a menu tic.
		//
		// The sliders remain an OFFSET in the anchored case, so "on top of me,
		// two hundred units north" is expressible without a third mode.
		double px = GetF("gitd_tornado_x", 0.0);
		double py = GetF("gitd_tornado_y", 0.0);
		if (haveAnchor) { px += ax; py += ay; }

		level.SetTornado(px, py,
			GetF("gitd_tornado_base", 0.0),
			GetF("gitd_tornado_top", 512.0),
			max(GetF("gitd_tornado_rad_base", 48.0), 1.0),
			max(GetF("gitd_tornado_rad_top", 320.0), 1.0),
			max(GetF("gitd_tornado_density", 1.0), 0.0));

		level.SetTornadoMotion(
			clamp(GetF("gitd_tornado_swirl", 0.5), 0.0, 1.0),
			GetF("gitd_tornado_spin", 2.0),
			GetF("gitd_tornado_twist", 8.0),
			max(GetF("gitd_tornado_lean", 0.0), 0.0),
			max(GetF("gitd_tornado_lean_period", 6.0), 0.1));
	}

	// ---- what is drawn inside a sweep band -------------------------------
	//
	// Style is shared across all eight bands and only the MODE is per band --
	// see the note in g_levellocals.h for why. In practice that is not much of
	// a limit: a train can still be a solid wall, then a lattice, then a band
	// of travelling darkness, because that is all mode.
	clearscope static void PushSweepFill()
	{
		int pk = GetI("gitd_ss_fill_color", 0xFF2018);
		Color col = Color(255, (pk >> 16) & 255, (pk >> 8) & 255, pk & 255);

		level.SetSweepFill(
			max(double(GetI("gitd_ss_fill_u", 64)), 0.0),
			max(double(GetI("gitd_ss_fill_v", 64)), 0.0),
			max(GetF("gitd_ss_fill_width", 3.0), 0.1),
			max(GetF("gitd_ss_fill_soft", 1.5), 0.0),
			col,
			clamp(GetF("gitd_ss_fill_gap", 0.0), -1.0, 1.0));

		level.SetSweepFillMotion(
			GetF("gitd_ss_fill_rotate", 0.0),
			GetF("gitd_ss_fill_drift", 0.0),
			max(GetF("gitd_ss_fill_major", 0.0), 0.0),
			max(GetF("gitd_ss_fill_major_boost", 2.0), 1.0),
			clamp(GetF("gitd_ss_fill_jitter", 0.0), 0.0, 1.0),
			clamp(GetF("gitd_ss_fill_flicker", 0.0), 0.0, 1.0),
			clamp(GetF("gitd_ss_fill_grad", 0.0), 0.0, 1.0),
			GetI("gitd_ss_fill_grad_axis", 0));

		for (int i = 1; i <= 8; i++)
			level.SetSweepBandFill(i - 1, clamp(GetI("gitd_ss_fill" .. i, 0), 0, 3));

		level.SetSweepFillAir(max(GetF("gitd_ss_fill_air", 0.0), 0.0));
	}

	// ---- the fog slab ----------------------------------------------------
	//
	// Everything except the WAKE, which needs the player's position and so
	// lives in GITD_Handler where the playsim is. Same split as the glow
	// wave's origin, and for the same reason: these are numbers off sliders
	// and can be pushed from a menu tic, that one cannot.
	clearscope static void PushFog()
	{
		if (!GetB("gitd_fog_enabled", false))
		{
			level.ClearFogSlab();
			return;
		}

		// Color(int) does NOT convert on this engine -- it compiles and then
		// fails at load with "Return type Color mismatch with SInt4". Build
		// it from bytes, the same way GITD_Lane.SlotColor has to.
		int pk = GetI("gitd_fog_color", 0xB41810);
		Color col = Color(255, (pk >> 16) & 255, (pk >> 8) & 255, pk & 255);

		level.SetFogSlab(
			double(GetI("gitd_fog_top", 40)),
			max(GetF("gitd_fog_density", 1.2), 0.0),
			max(double(GetI("gitd_fog_soft", 20)), 1.0),
			clamp(GetF("gitd_fog_scatter", 0.7), 0.0, 4.0),
			col);

		// The bottom edge, and the vertical hold that repeats the layer up the
		// room. A period at or below 1 means "one layer", which is the old
		// behaviour and the reason the slider's floor is 0 rather than 32 --
		// off has to be reachable by dragging left, not by knowing a magic
		// number.
		level.SetFogBottom(
			GetF("gitd_fog_bottom", -32768.0),
			max(GetF("gitd_fog_period", 0.0), 0.0),
			GetF("gitd_fog_roll", 0.0));
		level.SetFogPickup(clamp(GetF("gitd_fog_pickup", 0.55), 0.0, 1.0));

		level.SetFogSurface(
			max(GetF("gitd_fog_surf", 0.0), 0.0),
			max(GetF("gitd_fog_surf_len", 256.0), 1.0),
			GetF("gitd_fog_surf_speed", 1.0),
			clamp(GetF("gitd_fog_surf_cross", 0.6), 0.0, 2.0));
	}

	// ---- the glow wave --------------------------------------------------
	//
	// WAVES AND SEAMLESS CORNERS CANNOT BOTH BE RIGHT, and this is where that
	// is enforced. The corner works by matching reach across the junction so
	// both surfaces arrive at the shared line agreeing about where they end.
	// A wave moves that end. Run both and every corner in the game grows a
	// seam that travels along it -- worse than either feature alone, and it
	// reads as a rendering bug rather than as two settings disagreeing.
	//
	// So waves win while they are on and the corner is switched back OFF,
	// rather than left set-but-overridden. A cvar that says On while the
	// thing it names is not happening is how a settings page stops being
	// trustworthy.
	clearscope static void PushWave()
	{
		if (!GetB("gitd_wave_enabled", false))
		{
			level.ClearGlowWave();
			return;
		}

		let seam = CVar.FindCVar("gitd_seamless");
		if (seam && seam.GetBool()) seam.SetInt(0);

		// The shader works in radians and the slider is in world units, so
		// the divide happens once here rather than once per pixel.
		double len = max(GetF("gitd_wave_length", 256.0), 1.0) / 6.28318530718;

		level.SetGlowWave(len,
			GetF("gitd_wave_speed", 1.0),
			max(GetF("gitd_wave_sharp", 1.0), 1.0),
			clamp(GetI("gitd_wave_shape", 1), 1, 5));

		level.SetGlowWaveDepth(
			clamp(GetF("gitd_wave_reach",  0.35), 0.0, 0.9),
			clamp(GetF("gitd_wave_bright", 0.0),  0.0, 1.0),
			clamp(GetF("gitd_wave_colour", 0.0),  0.0, 1.0),
			clamp(GetF("gitd_wave_detune", 0.0),  0.0, 1.0),
			clamp(GetF("gitd_wave_seed",   0.5),  0.0, 1.0));

		// CLIMB. One number, four phases, and the order is the whole point:
		// the wave reaches the floor first, then the bottom of the wall, then
		// the top, then the ceiling. A wave travelling UP through a room.
		//
		// The shader computes sin(distance + time + phase), so a LARGER phase
		// is FURTHER ALONG the wave and therefore arrives EARLIER. The floor
		// is meant to be first, so the floor gets the largest phase and the
		// ceiling none -- which reads backwards until you remember that phase
		// is a head start, not a delay.
		double climb = GetF("gitd_wave_climb", 60.0) * 0.01745329252;
		level.SetGlowWavePhase(climb * 1.0, climb * 2.0, climb * 3.0, 0.0);
	}

	// ---- darkness -------------------------------------------------------
	//
	// The curves themselves have not changed and are not here -- they are in
	// main.fp, transcribed from DarkDoomZ.zs, which took them verbatim from
	// the original. This only decides what to feed them, which is the job the
	// script was always supposed to keep.
	//
	// Adjust is pre-multiplied here so the shader never has to know what a
	// "preset" is: 32 x the 0-8 dial is the same expression the per-sector
	// version used, and doing it once a tic instead of once a pixel is free.
	clearscope static void PushDarkness()
	{
		if (!GetB("gitd_dd_enabled", true) || !GetB("gitd_dd_perpixel", false))
		{
			level.ClearDarkness();
			return;
		}

		int mode = GetI("ddz_mode", 2);
		if (mode <= 0)
		{
			level.ClearDarkness();
			return;
		}

		// The three DarkDoom compatibility modes are fixed subtractions with
		// no dial, so they arrive as mode 1 with the adjustment they imply.
		// Four expressions in the shader rather than seven, and nothing about
		// what the player sees changes.
		double adjust;
		if (mode == 10)      { mode = 1; adjust = 96.0; }
		else if (mode == 11) { mode = 1; adjust = 128.0; }
		else if (mode == 12) { mode = 1; adjust = 256.0; }
		else adjust = 32.0 * clamp(GetI("ddz_preset", 3), 0, 8);

		level.SetDarkness(mode, adjust,
			GetF("ddz_minlight", 0.0),
			GetF("ddz_pregain", 0.0),
			GetF("ddz_postgain", 0.0));

		// The two a sector could never have said anything about.
		level.SetDarknessSpace(
			clamp(GetF("gitd_dd_dist", 0.0), 0.0, 1.0),
			max(GetF("gitd_dd_dist_range", 2048.0), 1.0),
			clamp(GetF("gitd_dd_height", 0.0), 0.0, 1.0),
			GetF("gitd_dd_height_ref", 0.0),
			max(GetF("gitd_dd_height_range", 256.0), 1.0));
	}
}
