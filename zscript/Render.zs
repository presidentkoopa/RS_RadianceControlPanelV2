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
		PushHeatmap();
		PushGlowTexture();
		PushShapeLook();
		PushSweepFill();
	}

	// ---- how shapes are drawn --------------------------------------------
	//
	// Only the shared look. WHICH shapes exist is decided by whatever placed
	// them -- GITD_Handler on a kill, a script, eventually an actor -- and a
	// placed shape carries its own kind, size and colour with it.
	//
	// Softness doubles as the master switch, because it is the one number the
	// evaluator tests before doing anything at all: at 0 the whole loop is
	// skipped rather than run sixteen times over empty slots.
	clearscope static void PushShapeLook()
	{
		bool on = GetB("gitd_shape_enabled", false);
		int u = GetI("gitd_shape_under", 0xFF2610);

		level.SetShapeLook(
			on ? max(GetF("gitd_shape_soft", 2.0), 0.01) : 0.0,
			max(GetF("gitd_shape_height", 24.0), 1.0),
			max(GetF("gitd_shape_reach", 0.0), 0.0),
			Color(255, (u >> 16) & 255, (u >> 8) & 255, u & 255));
	}

	// ---- texture inside the glow -----------------------------------------
	//
	// The wave varies a lane's EDGE and has nothing left to say once reach
	// saturates and that edge is off screen. These four happen WITHIN the lit
	// area, as multipliers on its contribution, so none of them can move a
	// band's shape.
	//
	// The alarm LEVEL is not pushed here -- it needs to count monsters, which
	// is a playsim read, so GITD_Handler pushes it. Same split as the glow
	// wave's origin and the tornado's anchor, for the same reason.
	clearscope static void PushGlowTexture()
	{
		level.SetGlowTexture(
			max(GetF("gitd_gtex_noise", 0.0), 0.0),
			max(GetF("gitd_gtex_scale", 0.02), 0.00001),
			GetF("gitd_gtex_drift", 1.0),
			max(GetF("gitd_gtex_contrast", 1.0), 0.001));

		level.SetGlowFlow(
			max(GetF("gitd_gflow", 0.0), 0.0),
			max(GetF("gitd_gflow_spacing", 64.0), 1.0),
			GetF("gitd_gflow_speed", 0.4),
			max(GetF("gitd_gflow_sharp", 2.0), 0.001));

		level.SetGlowCells(
			max(GetF("gitd_gcell", 0.0), 0.0),
			max(GetF("gitd_gcell_scale", 96.0), 1.0),
			GetF("gitd_gcell_speed", 1.2),
			max(GetF("gitd_gcell_width", 0.08), 0.01));
	}

	// ---- the heatmap -----------------------------------------------------
	//
	// Only how it is DRAWN. What is in it is stamped by GITD_Handler when
	// something dies, and it survives being switched off -- scale 0 stops
	// drawing without discarding the accumulation, so you can toggle it on
	// after a fight to see the shape of one you have already had.
	//
	// That asymmetry is deliberate. Everything else in GITD is stateless and
	// can be cleared by pushing zero; a heatmap is a RECORD, and a record that
	// erases itself when you stop looking at it is not a record.
	clearscope static void PushHeatmap()
	{
		int lo = GetI("gitd_heat_low", 0x2040FF);
		int hi = GetI("gitd_heat_high", 0xFF2000);

		level.SetHeatmap(
			GetB("gitd_heat_enabled", false)
				? max(GetF("gitd_heat_scale", 0.8), 0.0) : 0.0,
			Color(255, (lo >> 16) & 255, (lo >> 8) & 255, lo & 255),
			Color(255, (hi >> 16) & 255, (hi >> 8) & 255, hi & 255),
			max(GetF("gitd_heat_ceiling", 8.0), 0.01),
			max(GetF("gitd_heat_decay", 0.0), 0.0),
			max(GetF("gitd_heat_tolerance", 96.0), 1.0));
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

		int tpk = GetI("gitd_tornado_color", 0x8C99B3);
		level.SetTornadoLook(
			Color(255, (tpk >> 16) & 255, (tpk >> 8) & 255, tpk & 255),
			max(GetF("gitd_tornado_scatter", 1.2), 0.0));

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
			// 0-4 now: 4 is Pickets, which measures its own spacing from the
			// room box rather than from absolute world space. Clamping this at
			// 3 would have swallowed the new mode silently, which is the kind
			// of thing that reads as "the option does nothing".
			level.SetSweepBandFill(i - 1, clamp(GetI("gitd_ss_fill" .. i, 0), 0, 4));

		level.SetSweepFillAir(max(GetF("gitd_ss_fill_air", 0.0), 0.0));
	}

	// ---- the fog slab ----------------------------------------------------
	//
	// Everything except the WAKE, which needs the player's position and so
	// lives in GITD_Handler where the playsim is. Same split as the glow
	// wave's origin, and for the same reason: these are numbers off sliders
	// and can be pushed from a menu tic, that one cannot.
	clearscope static void PushFog(bool haveTint = false, Color tint = 0)
	{
		bool on = GetB("gitd_fog_enabled", false);

		// EVERY ONE OF THESE IS PUSHED WHETHER THE FOG IS ON OR OFF, and that
		// is not tidiness. A value that stops being pushed does not stop being
		// used -- it holds whatever it last had, so the tendrils keep rising
		// and the sweep keeps shouldering air that is not there, at full
		// per-fragment price, while the switch that names them reads Off.
		//
		// The same fault has now cost this project three separate days: eight
		// beams standing in an empty room, a tornado whose density uniform was
		// only written when floor fog happened to be on, and the whole render
		// push freezing under a sweep. Turning something off is a thing you
		// DO, not a thing you skip.
		level.SetFogNoise(
			max(GetF("gitd_fog_noise_scale", 0.004), 0.00001),
			on ? clamp(GetF("gitd_fog_noise", 0.0), 0.0, 1.0) : 0.0,
			GetF("gitd_fog_noise_drift", 6.0),
			GetF("gitd_fog_noise_drift", 6.0) * 0.6);   // not parallel: two
			                                            // axes at one rate
			                                            // reads as a slide

		level.SetFogTendrils(
			max(GetF("gitd_fog_tendril_spacing", 96.0), 8.0),
			max(GetF("gitd_fog_tendril_radius", 10.0), 1.0),
			max(GetF("gitd_fog_tendril_height", 96.0), 1.0),
			on ? max(GetF("gitd_fog_tendril", 0.0), 0.0) : 0.0,
			GetF("gitd_fog_tendril_rise", 0.6),
			1.0,
			max(GetF("gitd_fog_tendril_lean", 6.0), 0.0),
			max(GetF("gitd_fog_tendril_taper", 1.6), 0.0));

		level.SetFogBow(
			on ? max(GetF("gitd_fog_bow", 0.0), 0.0) : 0.0,
			max(GetF("gitd_fog_bow_width", 64.0), 1.0),
			clamp(GetF("gitd_fog_bow_thin", 0.6), 0.0, 1.0));

		// Which reference each edge follows. Pushed whether the fog is on or
		// off for the usual reason -- a value that stops being pushed keeps
		// whatever it last held.
		level.SetFogFollow(
			on ? clamp(GetF("gitd_fog_follow_top", 0.0), -1.0, 1.0) : 0.0,
			on ? clamp(GetF("gitd_fog_follow_bottom", 0.0), -1.0, 1.0) : 0.0);

		int g2 = GetI("gitd_fog_color2", 0xB38059);
		level.SetFogGradient(
			Color(255, (g2 >> 16) & 255, (g2 >> 8) & 255, g2 & 255),
			on ? clamp(GetF("gitd_fog_color2_mix", 0.0), 0.0, 1.0) : 0.0);

		// Disturbances are NOT cleared here. They expire on their own clock,
		// and Ignite deliberately works in clear air -- an explosion lighting
		// mist that is not there is still a burning cloud, and wiping the
		// slots every tic because the floor layer is off would delete it one
		// frame after it was asked for.
		if (!on)
		{
			level.ClearFogSlab();
			return;
		}

		// Color(int) does NOT convert on this engine -- it compiles and then
		// fails at load with "Return type Color mismatch with SInt4". Build
		// it from bytes, the same way GITD_Lane.SlotColor has to.
		int pk = GetI("gitd_fog_color", 0xB41810);
		Color col = Color(255, (pk >> 16) & 255, (pk >> 8) & 255, pk & 255);

		// THE MIST CAN TAKE ITS COLOUR FROM THE ROOM.
		//
		// A fixed fog colour while four lanes cycle thirty-two around it reads
		// as two mods running at once rather than as one room.
		//
		// The tint arrives as a PARAMETER rather than being read here, because
		// only GITD_Handler knows what the lanes are currently showing and
		// this function also runs from the menu ticker where there is no
		// handler to ask. Same split as the tornado's anchor and the glow
		// wave's origin: the menu tic pushes everything it can compute, and
		// the world tic pushes the one thing it cannot.
		//
		// Mode 0 leaves the picker alone entirely, which is why the read above
		// happens first and this only ever blends away from it.
		if (haveTint && GetI("gitd_fog_color_mode", 0) > 0)
			col = GITD_Palette.Lerp(col, tint,
				clamp(GetF("gitd_fog_color_blend", 1.0), 0.0, 1.0));

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
		// ---- THE COLOUR DRAIN, AND WHAT SURVIVES IT ----------------------
		//
		// Both pushed BEFORE the early returns below, and that placement is
		// load-bearing. The drain is not part of the darkness curve: it runs
		// in the per-sector and per-pixel modes alike and is switched off by
		// neither. Under one of those returns, changing an unrelated mode
		// would stop blood being red, or leave a monochrome world stuck grey
		// with no way to clear it.
		//
		// THE DRAIN USED TO BE A WALK OVER EVERY SECTOR IN THE MAP.
		// ApplyDarkness wrote ddz_desat into each sector's colormap byte every
		// tic, on the reasoning -- correct when it was written -- that a sector
		// desaturation is what reaches the TEXTURES rather than only what this
		// mod draws, and that no per-fragment equivalent existed.
		//
		// SetDesatGlobal is that equivalent. It lands in the same
		// dodesaturate() every path already funnels through, so it reaches
		// textures, sprites, glow, sweeps and brightmaps exactly as the byte
		// did. The shader takes max() against the per-sector value rather than
		// replacing it, so a sector something else drained harder stays
		// drained harder -- which is what leaves the per-sector channel free
		// for the things that should be LOCAL, like a setpiece draining only
		// the rooms its wavefront has reached.
		//
		// Nothing is mutated, so switching it off is passing zero rather than
		// writing 255 sectors back, and a savegame does not carry a drained
		// map around inside it.
		//
		// The dial stays 0-255 because that is what the menu and every preset
		// speak. It is a byte there and a fraction here.
		//
		// It DOES honour the master switch, unlike the keep below: with GITD's
		// darkness turned off entirely, leaving the world grey would be the
		// mod still visibly running after being told to stop.
		double drain = GetB("gitd_dd_enabled", true)
			? clamp(GetI("ddz_desat", 0), 0, 255) / 255.0
			: 0.0;
		level.SetDesatGlobal(drain);

		level.SetDesatKeep(
			clamp(GetF("gitd_dd_keep", 0.0), 0.0, 1.0),
			max(GetF("gitd_dd_keep_soft", 0.15), 0.001),
			clamp(GetI("gitd_dd_keep_hue", 0), 0, 3));

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
