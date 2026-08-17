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

	// ---- WHICH preset is holding, and why that had to be recorded --------
	//
	// Holding() answers "is something holding", and for a long time that was
	// treated as enough. It is not, and the gap was doing real damage: Sync()
	// applied a profile only when NOTHING was holding, so choosing a second
	// preset while a first one was active did nothing at all. Cold War then
	// Neon Chaos left Cold War's fog, torch, darkness curve and sweep running
	// under Neon Chaos's name.
	//
	// It looked like it worked, which is why it survived. Two other systems
	// DO switch on the preset number -- LoadWorkingSet repoints the palette
	// and DarkDoomZ_OptionMenu.SyncEngine reapplies the bloom -- so the room
	// visibly changed colour and glare the moment you picked. Everything that
	// changed was the half that never went through Sync. The only way to
	// actually get the preset you chose was to select Off in between.
	//
	// THE MARKER LIVES IN THE RECORD, not in a new cvar. The record already
	// means "a profile is holding"; making it say which profile is a strictly
	// better record and costs nothing. "#held=N;" is written first so it sits
	// at the front, and "#" cannot begin a cvar name, so it can never collide
	// with a captured one.
	const HELDKEY = "#held";

	clearscope static int HeldPreset()
	{
		let b = CVar.FindCVar("gitd_preset_backup");
		if (!b) return 0;

		string rec = b.GetString();
		int at = rec.IndexOf(HELDKEY .. "=");
		if (at < 0) return 0;

		// A record written before this marker existed has no #held and reads
		// as 0 -- "holding something, but nothing that names itself". Sync
		// treats that as a mismatch and hands it back before applying, which
		// is the correct and safe answer for a config saved by an older build.
		int from = at + HELDKEY.Length() + 1;
		int end = rec.IndexOf(";", from);
		if (end < 0) end = rec.Length();
		return rec.Mid(from, end - from).ToInt();
	}

	clearscope static void MarkHeld(int preset)
	{
		let b = CVar.FindCVar("gitd_preset_backup");
		if (!b) return;
		if (b.GetString().IndexOf(HELDKEY .. "=") >= 0) return;   // first write wins, as with Capture
		b.SetString(HELDKEY .. "=" .. preset .. ";" .. b.GetString());
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

	// BACK TO THE PER-SECTOR CURVE, and this is not a cosmetic choice.
	//
	// DarkDoomZ runs exactly one of the two implementations: the sector path
	// checks gitd_dd_perpixel and, if it is set, disables itself outright
	// (DarkDoomZ.zs:251 -- "if (perPixel) on = false"). So a preset that wants
	// the sector curve and does not say so does not merely get a different
	// look if per-pixel was left on by the last preset -- it gets NO DARKENING
	// AT ALL, while every dial in the menu still reads as though it should.
	clearscope static void NoDeepDark() { B("gitd_dd_perpixel", false); }

	// Mist with a top. The one atmospheric system that has a SHAPE, so it is
	// the one that changes what a room feels like to stand in rather than
	// what it looks like from across the map.
	clearscope static void Fog(int top, double density, int soft, int color,
	                           double scatter, double pickup,
	                           double wake, int wakeSize, double wakeLag)
	{
		B("gitd_fog_enabled", true);
		I("gitd_fog_top", top);
		F("gitd_fog_density", density);
		I("gitd_fog_soft", soft);
		I("gitd_fog_color", color);
		F("gitd_fog_scatter", scatter);
		F("gitd_fog_pickup", pickup);
		F("gitd_fog_wake", wake);
		I("gitd_fog_wake_size", wakeSize);
		F("gitd_fog_wake_lag", wakeLag);
	}

	clearscope static void NoFog()
	{
		B("gitd_fog_enabled", false);
	}

	// THE LASER GRID, which is a property of the sweep and not a thing of its
	// own -- a wall of light standing in the band, dense as you like, because
	// it is a pattern rather than a set of segments. Spacing in world units.
	//
	// Rotate 45 is most of the look on its own: diamonds instead of squares.
	// Gap 0 lights only the lines, so you see the room between them, which is
	// what reads as real lasers rather than as a lit pane.
	clearscope static void Grid(double spacing, double width, double soft,
	                            int color, double rotate, double strength)
	{
		F("gitd_ss_fill_air", strength);
		I("gitd_ss_fill_u", int(spacing));
		I("gitd_ss_fill_v", int(spacing));
		F("gitd_ss_fill_width", width);
		F("gitd_ss_fill_soft", soft);
		I("gitd_ss_fill_color", color);
		F("gitd_ss_fill_rotate", rotate);
		F("gitd_ss_fill_gap", 0.0);
		for (int i = 1; i <= 8; i++) I("gitd_ss_fill" .. i, 1);
	}

	clearscope static void NoGrid()
	{
		F("gitd_ss_fill_air", 0.0);
	}

	// ---- the mist as a substance -----------------------------------------
	//
	// Everything below arrived with reactive fog. A profile that sets none of
	// them still has to say so, because a preset that inherits whatever the
	// last one left running is not a preset, it is a leftover -- so each has
	// its own explicit Off.

	// Density stops being one number. Depth is the whole dial; scale is how
	// big the banks are and drift is how fast they cross the room.
	clearscope static void FogBanks(double depth, double scale, double drift)
	{
		F("gitd_fog_noise", depth);
		F("gitd_fog_noise_scale", scale);
		F("gitd_fog_noise_drift", drift);
	}

	// What the mist does when something happens in it. Mode: 0 push aside,
	// 1 ring, 2 ignite, 3 gout.
	clearscope static void Reactive(int mode, double shot, double death,
	                                double speed, double life, double stretch)
	{
		B("gitd_fog_react", true);
		I("gitd_fog_react_mode", mode);
		F("gitd_fog_react_shot", shot);
		F("gitd_fog_react_death", death);
		F("gitd_fog_react_speed", speed);
		F("gitd_fog_react_life", life);
		F("gitd_fog_wake_stretch", stretch);
	}

	clearscope static void NoReactive()
	{
		B("gitd_fog_react", false);
		F("gitd_fog_displace", 0.0);
		F("gitd_fog_wake_stretch", 0.0);
	}

	// Wisps off the surface. Spacing is the density dial and it is free in
	// both directions -- this is a lattice, not a set of objects.
	clearscope static void Tendrils(double amount, double spacing,
	                                double radius, double height, double lean)
	{
		F("gitd_fog_tendril", amount);
		F("gitd_fog_tendril_spacing", spacing);
		F("gitd_fog_tendril_radius", radius);
		F("gitd_fog_tendril_height", height);
		F("gitd_fog_tendril_lean", lean);
	}

	clearscope static void NoTendrils() { F("gitd_fog_tendril", 0.0); }

	// A funnel you can stand inside. Origin 0 is a fixed point; 5 is the
	// nearest live monster, which is the one that makes it walk the room.
	clearscope static void Tornado(int origin, double baseZ, double topZ,
	                               double radBase, double radTop,
	                               double density, int color,
	                               double swirl, double spin, double lean)
	{
		B("gitd_tornado_enabled", true);
		I("gitd_tornado_origin", origin);
		F("gitd_tornado_base", baseZ);
		F("gitd_tornado_top", topZ);
		F("gitd_tornado_rad_base", radBase);
		F("gitd_tornado_rad_top", radTop);
		F("gitd_tornado_density", density);
		I("gitd_tornado_color", color);
		F("gitd_tornado_swirl", swirl);
		F("gitd_tornado_spin", spin);
		F("gitd_tornado_lean", lean);
	}

	clearscope static void NoTornado() { B("gitd_tornado_enabled", false); }

	// The sweep shoulders the air in front of it.
	clearscope static void Bow(double strength, double width, double thin)
	{
		F("gitd_fog_bow", strength);
		F("gitd_fog_bow_width", width);
		F("gitd_fog_bow_thin", thin);
	}

	// Where the fighting happened. Deposits are recorded regardless; this
	// only decides whether they are drawn and how.
	clearscope static void Heat(double scale, int low, int high,
	                            double ceiling, double size, double hurt)
	{
		B("gitd_heat_enabled", true);
		F("gitd_heat_scale", scale);
		I("gitd_heat_low", low);
		I("gitd_heat_high", high);
		F("gitd_heat_ceiling", ceiling);
		F("gitd_heat_size", size);
		F("gitd_heat_hurt", hurt);
	}

	clearscope static void NoHeat() { B("gitd_heat_enabled", false); }

	// What survives a colour drain. Hue: 0 any, 1 red, 2 green, 3 blue.
	clearscope static void KeepColor(double threshold, double soft, int hue)
	{
		F("gitd_dd_keep", threshold);
		F("gitd_dd_keep_soft", soft);
		I("gitd_dd_keep_hue", hue);
	}

	clearscope static void NoKeepColor() { F("gitd_dd_keep", 0.0); }

	// A second colour through the layer's own thickness.
	clearscope static void FogGradient(int color, double mix)
	{
		I("gitd_fog_color2", color);
		F("gitd_fog_color2_mix", mix);
	}

	// ---- the shape of the layer ------------------------------------------
	//
	// HOW HARD THE MIST CLINGS TO THE GROUND UNDER IT, which no preset in this
	// file had ever said anything about -- so every one of them was getting a
	// flat sheet at one world height, and inheriting whatever the last one set
	// if it had been touched from the menu.
	//
	//   0.0  a level, like water in a tank. The low room fills and a staircase
	//        rises out of it; the landing above is clear air.
	//   1.0  constant depth everywhere. It coats the world, climbs every step,
	//        and lies ankle deep in rooms that should be dry.
	//
	// The interesting settings are low but not zero: the layer sags toward low
	// ground and pools there without following you upstairs, which is what
	// reads as weather rather than as geometry.
	clearscope static void Follow(double top, double bottom)
	{
		F("gitd_fog_follow_top", top);
		F("gitd_fog_follow_bottom", bottom);
	}

	// THE TOP SURFACE MOVES. A flat top is a horizontal plane, and once you
	// can see it clearly that is what it reads as -- a sheet, not a body of
	// mist. Two waves at an angle interfere, and interference is what looks
	// like a surface rolling rather than a pattern scrolling.
	//
	// wavelength is world units PER RADIAN, so the visible period is about 2pi
	// times it. This is the easiest number in the whole fog API to get wrong by
	// a factor of six.
	// The last parameter is crossSwell and NOT "cross": `cross` is the vector
	// cross-product operator and a reserved word, so naming anything after it
	// fails to parse -- and the error points at the declaration rather than at
	// anything resembling a vector, which is why it is worth a line here.
	// `dot` is reserved the same way.
	clearscope static void Surface(double amp, double wavelength,
	                               double speed, double crossSwell)
	{
		F("gitd_fog_surf", amp);
		F("gitd_fog_surf_len", wavelength);
		F("gitd_fog_surf_speed", speed);
		F("gitd_fog_surf_cross", crossSwell);
	}

	clearscope static void NoSurface() { F("gitd_fog_surf", 0.0); }

	// ---- the ambience layer ----------------------------------------------
	//
	// RESTORED after removal. gitd_voice stays out on a separate decision, so
	// none of these three touch it.

	// detail: 0 none, 1 only where the map implies a light source, 2 everything.
	clearscope static void Ambience(int detail, double lightScale, double particles)
	{
		B("fw_enabled", true);
		B("fw_lights", detail > 0);
		I("fw_light_detail", detail);
		F("fw_light_scale", lightScale);
		B("fw_particles", particles > 0.0);
		F("fw_particle_scale", particles);
	}

	// The scan still runs and the ambient SOUND still plays -- this turns off
	// what it draws, not what it is. A preset that wants silence as well has
	// to say so with the range.
	clearscope static void NoAmbienceLight()
	{
		B("fw_enabled", true);
		B("fw_lights", false);
		B("fw_particles", false);
	}

	clearscope static void Steps(double volume)
	{
		B("gitd_steps", volume > 0.0);
		F("gitd_steps_volume", volume);
	}

	// amount is what an emitter drops to with no sight line. Not 0 by default
	// anywhere: sound goes round corners, and a waterfall down a bent corridor
	// should still reach you.
	clearscope static void Occlude(double amount)
	{
		B("gitd_occlusion", amount < 1.0);
		F("gitd_occlusion_amount", amount);
	}

	// ---- dispatch -------------------------------------------------------

	clearscope static bool HasProfile(int preset)
	{
		// EIGHT SHIP. Blackout (1), Low Power (2), Red Alert (3), Cold War (4),
		// Neon Unison (6), Neon Chaos (7), Lovecraftian Fog (9) and Black and
		// White (11).
		//
		// Three of these were switched off for a real reason, not an arbitrary
		// one: they predate reactive fog, the tornado, the heatmap, the
		// lattice and the whole ambience layer, and a profile that does not
		// mention a system does not merely skip it -- it INHERITS whatever the
		// last preset left running. A stale profile is worse than no profile,
		// because its failures look like bugs in the systems it never asked
		// for.
		//
		// So each has had the pass that comment asked for. Every one of them
		// now states a position on fog, reactive fog, tendrils, the tornado,
		// the heatmap, the grid, colour keep, ambience light, particles,
		// footsteps and occlusion -- Off counts as a position, and saying it
		// out loud is the entire discipline this file runs on.
		//
		// THE FOUR NEW ONES WERE HELD TO A LONGER LIST THAN THAT, and it is
		// worth writing down what the longer list is rather than only that it
		// exists. The systems that had no helper when the original four were
		// written are exactly the ones that inherit INVISIBLY, because nothing
		// in the menu reads wrong while they do: the five glow-texture terms
		// (gitd_gtex_noise, gitd_gflow, gitd_gcell, gitd_greact, gitd_gpulse),
		// the floor shapes, the colour law, the three live randomiser MODES
		// (gitd_rnd_times is the one that can delete a preset's rhythm without
		// touching a cvar that preset wrote), the three fog cvars Fog() does not
		// reach (roll, period, bottom -- and bottom's "no bottom" sentinel is
		// outside its own slider, so a profile is the only way back to it), the
		// per-band gitd_ss_fill1..8 table that NoGrid() does not clear,
		// gitd_pc_shape, and gitd_ss_light_mode. Cold War, Neon Unison, Neon
		// Chaos and Lovecraftian Fog each take a stated position on all of them,
		// by hand, because there is still no helper for any of it.
		//
		// The original four mostly do not. That is a debt against those four,
		// recorded here rather than quietly paid off by the new ones, and it is
		// not a licence for the next preset to skip them.
		//
		// OMGWTF is gone. It had no dispatch case in any of the three switches
		// below, so it had never once run; it was 273 lines describing a
		// preset nobody could select. That is why a preset has to be registered
		// in FOUR places -- here, Apply, ApplyEngine and HasEngineHalf -- and
		// why a profile function missing any one of them is dead code however
		// well it reads. Adding a case to this list without the other three is
		// how OMGWTF happened.
		return preset == 1 || preset == 2 || preset == 3 || preset == 4
		    || preset == 6 || preset == 7 || preset == 9 || preset == 11;
	}

	clearscope static void Apply(int preset)
	{
		// STAMP THE RECORD BEFORE ANYTHING WRITES TO IT, so the marker lands
		// at the front and every Capture below it is attributed to this
		// preset. Guarded on HasProfile rather than on the switch's default
		// arm, because a preset number with no profile must not leave a marker
		// claiming it is holding something it never wrote.
		//
		// The default arm below is kept anyway. These two lists have drifted
		// apart before -- that is exactly what left OMGWTF as 273 lines with
		// no dispatch case -- and a switch that silently falls through is a
		// cheaper failure than one that runs the wrong preset.
		if (HasProfile(preset)) MarkHeld(preset);

		switch (preset)
		{
			case 1:  Blackout(); return;
			case 2:  LowPower(); return;
			case 3:  RedAlert(); return;
			case 4:  ColdWar(); return;
			case 6:  NeonUnison(); return;
			case 7:  NeonChaos(); return;
			case 9:  LovecraftianFog(); return;
			case 11: BlackAndWhite(); return;
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
			case 4:  ColdWarBloom(); return;
			case 6:  NeonUnisonBloom(); return;
			case 7:  NeonChaosBloom(); return;
			case 9:  LovecraftianFogBloom(); return;
			case 11: BlackAndWhiteBloom(); return;
			default: return;
		}
	}

	// LEAVING A PRESET HAS TO PUT THE BLOOM BACK.
	//
	// This did not exist, and the reasoning for not having it was written when
	// no preset shipped: bloom is not captured for recall, the Bloom page's
	// own defaults are one click away, and a recall that is only usually
	// correct is worse than none.
	//
	// OMGWTF is what made that indefensible. Its bloom is amount 3.2 at
	// threshold 0.05 with the anamorphic streak and the chromatic fringe both
	// on -- deliberately ruinous, and correct for that preset. Turning the
	// preset off left every one of those set while the Preset row read Off,
	// which is the same fault as a cvar that reads Off while the thing it
	// names is still running, and it is the third time this project has
	// shipped that fault.
	//
	// The engine's OWN defaults, not a GITD house style: 1.4 / 1.0 / 0.5,
	// white, no streak, no fringe. Anyone who had tuned their own bloom loses
	// it, which is the honest cost of not capturing -- but it only fires on
	// the transition OUT of a preset, so someone who never touches presets is
	// never touched by this. See the guard in DarkDoomZ_OptionMenu.
	clearscope static void RestoreEngine()
	{
		EI("gl_bloom", 1);
		EF("gl_bloom_amount", 1.4);
		EF("gl_bloom_threshold", 1.0);
		EF("gl_bloom_knee", 0.5);
		EF("gl_bloom_tint_r", 1.0);
		EF("gl_bloom_tint_g", 1.0);
		EF("gl_bloom_tint_b", 1.0);
		EF("gl_bloom_anamorphic", 0.0);
		EF("gl_bloom_chromatic", 0.0);

		// AND THE FIVE THIS FUNCTION FORGOT, which made it the fourth time
		// rather than the third.
		//
		// The comment above names OMGWTF's streak as the fault that forced this
		// function to exist, and then the function restored the streak's GATE
		// and not its RATIO -- so a preset's anamorphic width survived being
		// switched off, invisibly, because the gate was zero and a zero gate
		// makes the ratio unobservable until the next preset turns the gate
		// back on. It would then apply the previous preset's width.
		//
		// Exposure was worse: not one of the four gl_exposure_* cvars was here
		// at all, while six presets write all four of them. Turning any preset
		// off left its eye running -- Low Power's three-second adaptation, Red
		// Alert's half-second chase -- with the Preset row reading Off. That is
		// the same fault this function was written to fix, sitting inside it.
		//
		// ENGINE DEFAULTS, READ OUT OF hw_postprocess_cvars.cpp, not guessed.
		// They are not the round numbers you would assume, and assuming them
		// is how this line nearly shipped restoring base 1.0 / min 0.0 /
		// scale 1.0 -- a brighter, flatter eye than stock, applied to everyone
		// who ever turned a preset off. The file says 0.35 / 0.35 / 1.3, and
		// the anamorphic ratio is 3.0 rather than 1.0.
		EF("gl_bloom_anamorphic_ratio", 3.0);   // cvars.cpp:66
		EF("gl_exposure_base",  0.35);          // cvars.cpp:87
		EF("gl_exposure_min",   0.35);          // cvars.cpp:86
		EF("gl_exposure_scale", 1.3);           // cvars.cpp:85
		EF("gl_exposure_speed", 0.05);          // cvars.cpp:88
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

	// EXPOSURE, WHICH NO PRESET HAS EVER TOUCHED AND SHOULD HAVE.
	//
	// For a mod this dark it is a bigger lever than bloom, because it is the
	// only one that models an EYE rather than a lens. Walking from a lit
	// corridor into a black room is not a change in what is there; it is your
	// pupil opening over a couple of seconds. Bloom cannot say that. This can.
	//
	// SPEED IS THE WHOLE CHARACTER. Fast adaptation is a camera and feels
	// like cheating -- the dark stops being dark almost immediately. Slow
	// adaptation is an eye, and it means a room that is genuinely blind for a
	// moment after you leave the light, which is the single most atmospheric
	// thing available here.
	//
	// MIN is the floor the auto-exposure will not lift past. Set it too high
	// and the whole mod's darkness is quietly undone by the exposure pass.
	//
	// ---- SPEED IS NOT SECONDS, AND EVERY CALLER USED TO THINK IT WAS -------
	//
	// Four of the six presets carried a comment stating a number in seconds,
	// and all four were wrong by roughly sixty times. Two were also outside
	// the range the maths permits at all. Nobody caught it because a badly
	// tuned exposure still looks like *something*.
	//
	// What it actually is, from the engine rather than from guessing.
	// hw_postprocess.cpp:530 puts gl_exposure_speed into the ExposureCombine
	// uniforms; exposurecombine.fp emits it as FragColor.a; line 569 draws
	// that quad with SetAlphaBlend(). So it is the source alpha of a standard
	// alpha blend over the running exposure value:
	//
	//     new = measured * speed + old * (1 - speed)
	//
	// which is a per-FRAME exponential lerp, not a per-second one. The time
	// constant is 1 / (speed * framerate). At 35 fps:
	//
	//     speed 0.05 (engine default)  ~0.6 s     speed 0.03   ~1 s
	//     speed 0.01                   ~3 s       speed 0.007  ~4 s
	//     speed 0.6                    ~48 ms     speed 0.45   ~63 ms
	//
	// AND ABOVE 1.0 IT IS NOT SLOW OR FAST, IT IS BROKEN: (1 - speed) goes
	// negative, so each frame overshoots past the target and flips sign. The
	// meter oscillates instead of converging. Red Alert shipped 3.0 and Neon
	// Unison shipped 1.6, both of which are that.
	//
	// So: pick the seconds you want, divide 1 by (seconds * 35), and never
	// exceed 1.0. The comment at each call site now states both.
	clearscope static void Exposure(double base, double minimum, double scale, double speed)
	{
		EF("gl_exposure_base", base);
		EF("gl_exposure_min", minimum);
		EF("gl_exposure_scale", scale);
		EF("gl_exposure_speed", speed);
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
			// PRESET TO PRESET IS A RECALL AND THEN AN APPLY, and for a long
			// time it was neither. This read `if (!holding) Apply(preset)`,
			// so a profile went on only when nothing was holding -- which made
			// choosing a second preset while a first was active do NOTHING.
			//
			// Applying straight over the top would have been wrong too, and is
			// why the naive fix is not the fix. The backup record takes the
			// FIRST value written for each name, so a second profile applied
			// on top of a live one would capture the FIRST profile's settings
			// as though they were the player's. Turning it off afterwards
			// would then "restore" you to a preset you never chose, and the
			// player's real settings would be gone for good. The record has to
			// be spent before the next profile starts writing.
			if (HeldPreset() == preset) return;   // already this one; nothing to do
			if (holding) Restore();               // hand the old one back FIRST
			Apply(preset);
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
			string nm = p.Left(eq);

			// The held-preset marker is bookkeeping, not a captured setting.
			// FindCVar would fail on it anyway and the loop would skip it, but
			// skipping it BY ACCIDENT is precisely the habit this project keeps
			// getting burned by -- a guard that happens to do the right thing
			// reads identically to one that happens to do nothing. Say it.
			if (nm == HELDKEY) continue;

			let c = CVar.FindCVar(nm);
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
		I("ddz_desat", 78);    // colour vision failing with the lamps
		//
		// DISTANCE HARDER, RANGE SHORTER. 0.86 over 1000 units means the
		// corridor does not recede, it ENDS -- not at a wall, at the point
		// where the light gave up. Twenty metres of visibility in a facility
		// you are supposed to be lost in.
		//
		// And the height term deeper, so what little is left has fallen to
		// the floor. Light pools downward when there is not enough of it to
		// reach anywhere; that is not a stylisation, it is what a dying
		// fixture actually does.
		DeepDark(0.86, 1000.0, 0.50, 56.0, 260.0);

		// ---- the air -----------------------------------------------------
		//
		// Fog is what turns every other system in this preset from a surface
		// effect into a volume. Without it the sweep's crush band is a dark
		// stripe on a wall; with it, it is a body of dark moving down a
		// corridor. It is also the only reason the torch has a beam rather
		// than a bright patch at the end of it.
		F("ddz_skymode", 1.0);
		I("ddz_minlight", 0);   // no floor. Where it goes dark it goes dark.

		// ---- AND IT HAS SETTLED ON THE FLOOR -----------------------------
		//
		// Sector fog fills a room evenly, which is weather. This is a LAYER,
		// and a layer is what a building gets when its air handling has been
		// off for a long time: cold, heavy, dead-still, lying in the bottom
		// forty units of every corridor and going nowhere.
		//
		// Dead sodium grey-brown, not white -- it is the same dying light
		// everything else here is made of, hanging in the air instead of
		// clinging to a wall.
		//
		// PICKUP HIGH. The mist takes its colour from whatever is behind it,
		// so the amber strip glow bleeds into the fog in front of it and the
		// two stop being separate systems. Without that the layer reads as a
		// filter laid over the room.
		//
		// AND THE WAKE IS SLOW. Lag 0.06 drags a long channel that takes
		// several seconds to close, so you can look back and see where you
		// walked. In a preset about a place nobody has been in for a while,
		// leaving a mark is the whole point.
		// LOW AND ROLLING, which is a different thing from thick.
		//
		// Top dropped from 44 to 30 and density from 1.5 to 1.1: the old
		// values put a chest-deep bank across the whole map, and once mist is
		// above your eyeline you stop reading it as a layer lying on the floor
		// and start reading it as a filter over the lens. Waist height is
		// where it still has a SURFACE you can look down at, which is the
		// whole reason this engine's fog has a top at all.
		Fog(30, 1.10, 24, 0x3A2E1E,
		    0.9,      // the torch lights it -- this is where the beam earns its keep
		    0.75,     // and it picks up the failing amber from the walls
		    0.7, 130, 0.06);

		// And it POOLS. 0.3 sags toward low ground without climbing stairs, so
		// the mist gathers in the sunken rooms and the stairwells while the
		// landing above stays clear -- and walking up out of it is a thing you
		// can watch happen.
		Follow(0.3, 0.0);

		// A slow, long swell. Wavelength 52 is a visible period of about 330
		// units -- roughly a room -- so the surface rolls rather than ripples.
		// Speed 0.18 is barely moving: this air is settling, not circulating.
		Surface(3.0, 52.0, 0.18, 0.65);

		// THE AIR IS NOT EVEN, and this is the difference between a fog layer
		// and a fog FILTER. Uniform density is a value applied to the screen;
		// density that is thick in one corner and thin in the next is a
		// substance occupying a room. Large and slow -- 0.0022 is a bank about
		// the size of a hall, drifting across one in half a minute.
		FogBanks(0.45, 0.0022, 1.4);

		// AND THINGS RISE OFF IT. The only preset of the four that takes
		// tendrils, and the only one where they mean anything: wisps lifting
		// off standing air in a building nobody has ventilated since the
		// incident. Sparse and tall, not a forest -- spacing 150 puts one
		// every few paces, and they lean because the air is barely moving
		// rather than still.
		//
		// Cheap enough to afford here: the lattice is a fract(), so four
		// hundred of them cost what one costs.
		Tendrils(0.20, 150.0, 12.0, 110.0, 5.0);

		// AND THE POOLS KEEP THEIR OWN COLOUR. Amber is what the failing
		// lights are doing to the air; a nukage sump is not part of that
		// argument and should not be recoloured by it. This is the one source
		// that comes from the map rather than from the preset.
		I("gitd_fog_color_mode", 4);
		F("gitd_fog_color_blend", 0.7);   // toward the liquid, not all the way

		NoGrid();

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
		I("fl_range", 1500);
		F("fl_intensity", 1.20);
		F("fl_inner", 6.0);      // tighter core: one thing at a time
		F("fl_outer", 19.0);
		F("fl_falloff", 1.9);    // concentrated near the lens, dies with range
		F("fl_density", 2.0);    // the cone is a solid object in this air
		F("fl_dust", 0.80);      // heavy. Nobody has swept this place since.
		F("fl_dust_scale", 0.06);
		F("fl_dust_drift", 0.07); // slow settle -- motes hanging, barely falling
		B("fl_bounce", false);   // no omnidirectional fill. A torch is a cone.
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

		// ---- the systems that postdate this preset ------------------------
		//
		// A building on a failing supply is a building that has gone QUIET,
		// and quiet is the one thing this preset could not previously say --
		// it had no position on the ambience layer at all, so it inherited
		// whichever one the last preset left on.

		// Its fog is already stated further up and is not touched here. What
		// follows is only the systems that did not exist to be refused.
		//
		// NOT NoTendrils(). This preset takes them, above, and is the only one
		// that does -- a blanket "refuse the new systems" block appended after
		// the fog was written turned that nine-line argument off on the very
		// next screen.
		NoTornado();
		NoReactive();     // nothing here reacts; that IS the preset
		NoHeat();
		NoKeepColor();

		// Light only where the map already implies a source, and dim. An
		// emergency circuit lights the fixtures it must and nothing else, so
		// the flavour glow on slime and computers is exactly wrong here.
		Ambience(1, 0.7, 0.35);

		// LOUD FEET IN A QUIET BUILDING. Your own footsteps are the most
		// present sound left, which is the whole feeling being aimed at.
		Steps(1.15);

		// And heavily muffled through walls -- a dying building does not carry
		// sound the way a live one does.
		Occlude(0.25);
	}

	// Bloom for a dying filament: threshold LOW, because there is almost no
	// light here and if only blown-out pixels bloomed, nothing would. Warm
	// tint so the smear is the same sodium the lamps are. Amount modest --
	// this is a glow around a weak source, not a haze over the screen.
	clearscope static void LowPowerBloom()
	{
		Bloom(1.35, 0.22, 0.60, 1.0, 0.84, 0.58);
		// 1.0, NOT 0.45, AND THE BEHAVIOUR DOES NOT CHANGE -- which is the
		// point. gl_bloom_anamorphic is CVAR(Bool) and the engine uses it as a
		// bare gate: `if (gl_bloom_anamorphic) hAmount = blurAmount *
		// gl_bloom_anamorphic_ratio`. Any non-zero value is fully on. 0.45 has
		// always produced a FULL streak, so the number was describing an
		// intention the engine never had a way to honour.
		//
		// The ratio is the only strength lever there is. It stays at 3.0
		// because that is what has actually been shipping; a milder streak
		// means a lower ratio, not a fractional gate.
		EF("gl_bloom_anamorphic", 1.0);
		EF("gl_bloom_anamorphic_ratio", 3.0);  // fixture seen from the side
		EF("gl_bloom_chromatic", 0.0);

		// THE SLOWEST EYE IN THE SET, and it is what makes this preset.
		//
		// Speed 0.6 is roughly three seconds to adapt. Step out of the one lit
		// doorway on the level and you are BLIND for three seconds -- not
		// dimmed, blind -- and then the room slowly arrives. Nothing else here
		// produces that, because nothing else models an eye.
		//
		// Min low, so the adaptation is never allowed to undo the darkness it
		// is adapting to. Base under 1 so even a fully adapted eye reads this
		// place as underlit, which it is: the grid is failing, not fixed.
		// 0.01, for the three seconds the comment above always meant. 0.6 was
		// 48 milliseconds -- the eye this preset is built around was snapping
		// instantly, and the whole "step out of the doorway and go blind"
		// effect has never once happened. See Exposure() for the derivation.
		Exposure(0.85, 0.28, 1.0, 0.01);
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

		// ---- EXCEPT THE BLOOD -------------------------------------------
		//
		// 255 above drains every colour in the world. This puts one back, and
		// it is the only colour in the preset.
		//
		// RED ONLY, and high. Any-hue would keep green nukage and blue
		// keycards too, and a monochrome film with three colours in it is not
		// monochrome, it is badly graded. 0.82 is above Doom's brown and
		// grey-brown wall textures and below its blood, its gore, its
		// pickup reds and the kill badges the Numeric Violence Engine draws --
		// so what survives is blood and score, which is an honest summary of
		// what this game is about.
		//
		// The edge is narrow at 0.08. A wide one leaves half-drained pinks
		// lying around, and a colour that is nearly grey is worse than either.
		KeepColor(0.82, 0.08, 1);

		// Crush, and deep -- but not Pure. Blackout is Pure; this one needs a
		// floor for the whites to have something to be brighter THAN. The
		// contrast is the image.
		I("ddz_mode", 4);
		I("ddz_preset", 6);

		// A little air, and no more. Enough that the white bar below reads as
		// a shaft rather than a stripe on a wall; not enough to soften
		// anything. Grey haze is still grey.

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

		// A LOW, THIN, COLOURLESS LAYER, and PICKUP AT ZERO.
		//
		// Every other preset turns pickup up, because mist taking colour from
		// what is behind it is what stops it reading as a filter. This one
		// wants exactly that flatness: a neutral grey layer that refuses to
		// be tinted by anything, because the moment it picks up a colour this
		// preset has a colour in it and the whole argument collapses.
		//
		// Very shallow -- ankle rather than knee. It is not weather here, it
		// is the floor of the frame: something for the bottom of a composition
		// to sit in, the way a Bergman floor is never quite empty.
		//
		// Scatter high, though. The torch cutting a clean shaft through flat
		// grey air is the most Bergman thing in the whole mod.
		Fog(22, 0.7, 14, 0x9EA2A6,
		    1.6,      // the beam carves
		    0.0,      // and NOTHING tints it
		    0.35, 90, 0.12);

		// FLAT ON PURPOSE, and it is the only preset here that is.
		//
		// The other three sag their layer into low ground, because mist that
		// pools reads as weather. This one wants the opposite: a horizontal
		// plane at one height across the whole map, so the grey sits in the
		// frame like a printed tone rather than like something the room is
		// doing. A layer that follows the floor is describing terrain; a level
		// one is describing the IMAGE.
		//
		// A little swell so it is not a sheet of card -- long, slow, and small
		// enough that you notice it only when looking along the surface.
		Follow(0.0, 0.0);
		Surface(2.0, 64.0, 0.10, 0.7);

		NoGrid();

		// ---- the air is uneven, and nothing else about it is ------------
		//
		// Density banks, and that is the ONLY thing on the reactive page this
		// preset takes. Uneven grey air is a composition -- it puts weight in
		// one part of the frame and lifts another -- which is the argument
		// this whole preset is making. Large, slow banks: 0.0015 is roughly
		// room-sized, and a drift of 2 crosses one in half a minute.
		//
		// NOT tendrils. Wisps are texture and this preset has no texture in it
		// anywhere. Not a tornado either: a funnel is a baroque object and
		// there is nothing baroque here.
		FogBanks(0.55, 0.0015, 2.0);
		NoTendrils();
		NoTornado();
		Bow(0.0, 64.0, 0.6);

		// A RING, AND ONLY OFF THE GUN.
		//
		// A hard circular front travelling out through flat grey air is a
		// geometric event in a still composition, which is the one kind of
		// motion this preset can afford. Slow -- 190 rather than the usual
		// 320 -- so it reads as a front you can watch arrive rather than a
		// pop, and long-lived so it is still crossing the room when the shot
		// has been forgotten.
		//
		// Nothing from deaths. A monster dying should not be decorated here;
		// the heatmap below is what remembers it, and it remembers in silence.
		Reactive(1, 0.5, 0.0, 190.0, 3.2, 1.4);
		F("gitd_fog_displace", 0.0);   // and nothing pushes the air but you

		// A slightly lighter top to the layer. The grey floor of the frame
		// wants a gradient in it or it is a flat card -- but a small one,
		// because two greys is already a colour decision.
		FogGradient(0xC6C9CC, 0.30);

		// ---- THE GROUND REMEMBERS ---------------------------------------
		//
		// Greyscale on both ends, so a heatmap that is normally the loudest
		// thing on screen becomes the quietest: pale pooling where bodies
		// fell, on a floor already flattened to near black.
		//
		// This is the most Bergman thing in the mod and it arrived by
		// accident. A room you walk back into is not the room you left, and
		// it says so without a line of dialogue.
		//
		// Ceiling 3 so a single death already registers -- one is meant to
		// mean something here -- and the spread wide and soft so it pools
		// rather than marks.
		Heat(0.55, 0x3C3C3C, 0xDCDCDC, 3.0, 72.0, 0.0);

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

		// This preset already refuses almost everything, and the newest layer
		// is no exception -- but it has to REFUSE it rather than not mention
		// it, which is the discipline the whole file runs on.
		//
		// Light and particles off: coloured mist and orange embers in a
		// monochrome image are the exact small dishonesty the bloom note above
		// is about. The drain would grey them anyway, and grey embers are
		// worse than none.
		NoAmbienceLight();

		// SOUND STAYS, and it is doing more work here than anywhere else.
		// Strip a scene of colour and hearing carries proportionally more of
		// it; footsteps and a room that closes behind you are the texture this
		// preset removed from the image.
		Steps(1.0);
		Occlude(0.4);
	}

	// White that BLOWS OUT rather than glows. Threshold high, so only what is
	// genuinely near-white blooms at all and the greys stay matte; amount
	// high, so when something does cross the line it goes completely. No
	// tint, and chromatic fringing explicitly at zero -- colour fringing on a
	// monochrome preset is exactly the kind of small dishonesty that makes a
	// black and white image look like a filter over a colour one.
	// BLACK AND WHITE NO LONGER TOUCHES BLOOM, and that is the point of it.
	//
	// It used to set threshold 0.72 and amount 1.6, on the reasoning that
	// white should blow out rather than glow. Defensible, and wrong to ship: a
	// preset that overwrites the Bloom page is a preset you cannot use
	// alongside your own bloom, and bloom is not part of what makes this
	// preset black and white. The colour drain is.
	//
	// Kept as an empty function rather than deleted so the dispatch below
	// stays a straight table -- and so the next person who wonders whether the
	// bloom was forgotten finds this note instead of a missing case.
	clearscope static void BlackAndWhiteBloom() {}

	// Which presets have an engine half at all. Only ones that do get their
	// bloom restored on the way out -- see SyncEngine. Without this, leaving a
	// preset that never touched bloom would still reset the player's own.
	clearscope static bool HasEngineHalf(int preset)
	{
		// THIS RETURNED false UNCONDITIONALLY, and that was a leak.
		//
		// It is the gate on RestoreEngine (DarkDoomZ.zs:676), so while it
		// always said no, nothing ever put the bloom and exposure back. A
		// preset could rewrite both, and turning it off left them rewritten
		// with the Preset row reading Off -- the exact failure the comment
		// above RestoreEngine describes, still happening, because the function
		// that decides when to call it never said yes.
		//
		// It could get away with it only while the one shipping preset was
		// Black and White, whose engine half is deliberately empty. The moment
		// Blackout, Low Power or Red Alert became selectable again it stopped
		// being harmless.
		//
		// Black and White is still false, and for the right reason rather than
		// by accident: BlackAndWhiteBloom() sets nothing, so there is nothing
		// of its to restore, and claiming otherwise would have leaving it
		// stamp the Bloom page's defaults over settings it never touched.
		//
		// 4, 6, 7 and 9 all say yes, and all four genuinely earn it: ColdWarBloom,
		// NeonUnisonBloom, NeonChaosBloom and LovecraftianFogBloom each write the
		// six Bloom() cvars AND all four gl_exposure_*, and 4 additionally writes
		// gl_bloom_anamorphic_ratio.
		//
		// THIS USED TO SAY THE ANSWER WAS ONLY HALF TRUE, because RestoreEngine
		// put back nine gl_bloom_* cvars and nothing else -- not the anamorphic
		// ratio, not any of the four gl_exposure_*. Leaving a preset therefore
		// left its exposure curve standing while the Preset row read Off, which
		// Low Power and Red Alert had done since they shipped.
		//
		// RestoreEngine now restores all five, so this is a whole answer. The
		// note is kept rather than deleted because the numbers it named were
		// WRONG and the wrong ones are worth recording: it proposed ratio 1.0
		// and exposure 1.0 / 0.0 / 1.0 / 0.05, guessed as the round values any
		// engine would use. The real defaults, read out of
		// hw_postprocess_cvars.cpp, are ratio 3.0 and 0.35 / 0.35 / 1.3 / 0.05.
		// Shipping the guess would have handed a brighter, flatter eye than
		// stock to everyone who ever turned a preset off -- a new bug wearing
		// the shape of a fix.
		return preset == 1 || preset == 2 || preset == 3 || preset == 4
		    || preset == 6 || preset == 7 || preset == 9;
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
		DeepDark(0.45, 2100.0, 0.18, 40.0, 300.0);

		// FOG IS THE VOLUMETRIC LEVER. With air in the room, a band is
		// visible BETWEEN you and the wall rather than only on it, so the
		// klaxon is a body of red moving down the corridor instead of a
		// colour arriving on a surface. Lighter than Low Power's: this is a
		// lit room having an emergency, not a dead one.

		// A THIN RED LAYER, and thin on purpose. Low Power's fog is a dead
		// building's settled air; this is not that. It is smoke from whatever
		// went wrong -- shallower, lighter, and disturbed, because the room is
		// having an emergency rather than sitting in one.
		//
		// The wake is FAST here (lag 0.35): the layer closes up almost as
		// soon as you pass, so it reads as moving air rather than as
		// something that has been undisturbed for months.
		// SOME, not much. Thinner than Low Power's on purpose: this preset's
		// whole argument is made by the klaxon bands sweeping the room, and a
		// dense layer would soften the leading edge of every one of them. What
		// the mist is here for is to be something for those bands to CROSS --
		// a band you can see travelling through the air reads as a volume, and
		// a band painted only on the walls reads as a texture.
		Fog(26, 0.55, 18, 0x4A0E08,
		    1.1,      // and the klaxon's own bands light it as they cross
		    0.85,     // taking red from every surface it stands in front of
		    0.5, 100, 0.35);

		// Barely any sag. An alert is a room with the air handling still
		// running, so the layer sits level rather than settling into corners.
		Follow(0.1, 0.0);

		// Short and quick, and the opposite of Low Power's. Period about 190
		// units at nearly four times the speed -- air being moved rather than
		// air going still.
		Surface(2.0, 30.0, 0.65, 0.5);

		// Fine and fast-moving, where Low Power's banks are large and slow.
		// 0.006 is roughly a doorway rather than a hall, drifting at three
		// times the speed: this is air being pushed by handling that is still
		// running, not air that has settled. Shallow depth, because a klaxon
		// preset wants the mist EVEN enough that the bands crossing it read as
		// clean edges.
		FogBanks(0.25, 0.006, 4.0);

		// A BOW WAVE, and this is the only preset that has any business with
		// one. It is mist shouldered aside by a travelling sweep band -- which
		// requires a travelling sweep band, and this is the preset built
		// around eight of them. The alarm does not merely light the room, it
		// pushes the air in front of it.
		Bow(0.7, 90.0, 0.55);

		NoTendrils();   // nothing hangs in moving air

		// The mist stays RED. Deliberately not the liquid source Low Power
		// takes: this preset is a building shouting one colour, and a green
		// sump in the middle of that is the alarm losing an argument with the
		// scenery. The one place the composition beats the map.
		I("gitd_fog_color_mode", 1);     // match a lane
		I("gitd_fog_color_lane", 3);     // the floor, which carries the klaxon
		F("gitd_fog_color_blend", 0.55); // part way, so it never goes pure

		NoGrid();

		// The torch, wide and clean. Red Alert is not a preset about being
		// unable to see -- the light is already on and already telling you
		// something. Dust raised enough that the klaxon's own bands have
		// something to hang in, which is what turns the beacon from a stripe
		// on a wall into a body of red crossing the room.
		B("fl_enabled", true);
		I("fl_range", 1200);
		F("fl_intensity", 1.10);
		F("fl_inner", 10.0);
		F("fl_outer", 26.0);
		F("fl_density", 1.5);
		F("fl_dust", 0.38);
		F("fl_dust_scale", 0.05);
		F("fl_dust_drift", 0.20);   // stirred air, not settled dust
		B("fl_bounce", false);   // no omnidirectional fill. A torch is a cone.

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

		// ---- the systems that postdate this preset ------------------------
		//
		// An alarm is a building REACTING, so this is the one of the three
		// that should have the reactive layer turned up rather than off.

		// Its fog is already stated further up, pickup and all, and is not
		// touched here. What follows is only what did not exist to be refused.
		NoTornado();

		// Gunfire and death push the mist around. In a room already pulsing
		// this reads as the air being disturbed by what is happening in it.
		Reactive(1, 0.9, 1.0, 190.0, 3.0, 1.2);

		// THE FLOOR KEEPS SCORE. An alert that ends with no trace of what
		// happened during it is a light show; this leaves the room marked by
		// the fight afterwards.
		Heat(0.55, 0x200000, 0xFF3018, 0.6, 52.0, 0.4);

		NoKeepColor();

		// Everything lit, including the flavour glow -- a building at full
		// alert has every panel it owns switched on.
		Ambience(2, 1.0, 1.0);
		Steps(0.9);

		// Barely muffled. Alarms are meant to carry through walls; that is
		// what they are for.
		Occlude(0.75);
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
		Bloom(2.10, 0.24, 0.35, 1.0, 0.38, 0.30);
		EF("gl_bloom_anamorphic", 0.0);
		EF("gl_bloom_chromatic", 0.45);

		// A FAST EYE, and fast for a reason. Low Power's slow adaptation is
		// about being lost in the dark; this one is the opposite situation --
		// the room is lit and screaming at you, and an eye that took three
		// seconds to catch up would blunt every beat of the klaxon.
		//
		// Speed 3.0 is roughly half a second, so the eye chases the alarm
		// instead of averaging it. The floor rides HIGH: each time the beacon
		// drops below baseline the exposure lifts after it, and the room
		// swells back at you rather than simply going dark. That pumping is
		// the alarm breathing, and it only exists because exposure is live.
		// 0.06 for the half second the comment asks for. 3.0 was not fast, it
		// was above 1.0, where the blend's destination factor goes negative and
		// the exposure meter oscillates rather than settling -- so the klaxon
		// the eye was supposed to chase was being chased by an eye that never
		// arrived anywhere. See Exposure() for the derivation.
		Exposure(1.15, 0.55, 1.0, 0.06);
	}

	// =====================================================================
	// 4. COLD WAR -- the lights work, and nobody has been warm in here
	//
	// WHAT IT IS. A hardened installation that is still powered, still lit,
	// still watched, and has not been warm in a very long time. Fluorescent
	// that has gone blue with age. Frost coming in through the structure
	// rather than in through a door. A few sodium emergency lamps that are
	// the only warm thing in the building and are losing.
	//
	// WHAT IT IS NOT, and this is the harder half. It is not Low Power. Low
	// Power is a grid FAILING, and everything in it moves: the brownout wave,
	// the four-beat drop, the tendrils rising off dead air. Cold War is the
	// same building with the maintenance contract still in force. Nothing
	// here is failing, nothing is reacting, and nothing is addressed to you.
	// The unease is that it all works perfectly and none of it is for you.
	//
	// SO THE DESIGN IS RESTRAINT, and restraint has to be built rather than
	// merely claimed. Every system in this mod that says "something is
	// HAPPENING" is switched off on purpose:
	//
	//   no wave           undulation is a supply moving. This supply is fine.
	//   no reactive fog   the building does not notice you. That is the point.
	//   no tendrils       wisps rise off warm air. Nothing here is warm.
	//   no heatmap        a floor that remembers is a place you changed.
	//   no lattice        a laser grid says "do not cross", which is drama.
	//   no bow wave       the scan is light. Light has no mass.
	//   no glow pulse     a light that brightens when monsters are near is
	//                     the building acknowledging you, and it is the ONE
	//                     toy this preset had a genuine claim on and still
	//                     refuses. Refusing the loudest available system is
	//                     what makes the other six refusals credible.
	//
	// AND FOUR THAT ARE ON, ON HARD. There were three, and three was the
	// fault: the preset was a set of correct decisions with no image in it.
	//
	//   the key light     lit from ABOVE, linear falloff, wide and even. An
	//                     institutional ceiling, not a pool of light.
	//   the substance     the mains hum this preset wrote four paragraphs
	//                     wanting and could not get out of the glow wave. It
	//                     is in the glow TEXTURE layer instead -- a fine fast
	//                     line running along the lit surface, a stain in the
	//                     diffuser and frost veining in the glass. It samples
	//                     WITHIN the lit area, so unlike the wave it does not
	//                     need an edge on screen to say anything.
	//   the cold air      a thin layer at CONSTANT DEPTH everywhere, because
	//                     cold comes off the structure, it does not pool.
	//   the scan          one thin bar, out and back over eighty-five
	//                     seconds, with a wide dim crush band behind it.
	//
	// The colours are generated, not literal: GITD_Presets.Params case 4 is
	// hue 210 spread 80, sat 0.78 +/- 0.20, val 0.62 +/- 0.28. SlotColor
	// divides the spread by four, so the four lanes sit at 210 / 230 / 250 /
	// 270 -- azure through violet-blue, four neighbours of one family rather
	// than four different colours -- and the eight slots inside a lane walk
	// 17.5 degrees. The dominant axis is therefore BRIGHTNESS, not hue: val
	// runs 0.34 to 0.90, a 2.6x range, under a saturation this file pulls
	// down again to 0.72. That is the correct reading of a fluorescent bank
	// and it is worth stating plainly, because a reader who takes "hue 210
	// spread 80" at face value will expect four colours and see one.
	//
	// This file supplies the timing, the shape, the substance and the cold.
	// =====================================================================
	clearscope static void ColdWar()
	{
		// ---- the baseline ------------------------------------------------
		//
		// SNAP, like the other three, and for a different reason than any of
		// them. Low Power snaps because a dying supply sits at a value until
		// it changes; Black and White snaps because a cut is a cut. This one
		// snaps because a bank of tubes changing over is a relay closing.
		// There is no dimmer in a facility like this. There is a contactor.
		//
		// Speed is phase per tic and the phase wraps at 1, so a slot costs its
		// hold PLUS 1/speed tics (GITD_Lane.Step -- the hold runs first, then
		// the clock). 0.070 is 14 tics, four tenths of a second, so the
		// crossfade that is never drawn costs under half a second on top of a
		// twenty-second hold and the row totals below are honest to about two
		// per cent. Left at the shipped 0.004 default it would be 250 tics --
		// seven seconds on every slot, nearly a minute added to each of the
		// four service intervals, and they stop being the numbers they say.
		//
		// LINEAR FALLOFF, and this is the first preset in the file to take 0.
		// The other three take Smooth or Sharp, which concentrate the glow at
		// the seam where two surfaces meet -- light POOLING, which is what
		// light does when there is not enough of it. There is plenty here. A
		// linear ramp across a wide coverage is an evenly illuminated surface
		// that simply stops where the fixture's throw stops, which is what a
		// ceiling of tubes actually does to a corridor, and it is the reason
		// shadows in this preset have edges instead of gradients.
		//
		// Saturation 0.72 rather than 1.0. The generated palette is already
		// blue; pushing it to full would make it a nightclub. Aged fluorescent
		// is not saturated, it is merely wrong.
		LanesI("_enabled", 1);
		LanesI("_pattern", 0);
		LanesI("_anim", 0);
		LanesI("_slots", 8);
		LanesI("_falloff", 0);
		Lanes("_saturation", 0.72);
		Lanes("_speed", 0.070);

		// ---- lit from above ----------------------------------------------
		//
		// The four lanes are not four surfaces here, they are one lighting
		// plan. Every fixture in this building is in the ceiling, so the
		// ceiling is the key and the floor is only what falls on it.
		//
		//   ceiling      the source. Widest and brightest by a distance.
		//   wall top     the throw down the wall, most of the way to the
		//                floor, because a linear ramp over 200 units does not
		//                run out the way a smooth one does.
		//   wall bottom  a skirting return, dim. There is no fixture here;
		//                this is bounce, and concrete bounces badly.
		//   floor        dimmest of all. A deck lit from above has no glow of
		//                its own, and giving it one would put a second light
		//                source in a room designed around having exactly one.
		//
		// The intensities are all at or below 1.5, where Red Alert runs to
		// 2.0 and Black and White to 2.2. This preset does not have a bright
		// thing in it anywhere and must not acquire one by accident.
		I("gitd_cg_coverage", 288); F("gitd_cg_intensity", 1.45);
		I("gitd_wt_coverage", 200); F("gitd_wt_intensity", 1.05);
		I("gitd_wb_coverage", 160); F("gitd_wb_intensity", 0.75);
		I("gitd_fg_coverage", 120); F("gitd_fg_intensity", 0.55);

		// AND THE SHAPE OVERRIDE HAS TO BE SAID OUT LOUD, which no preset in
		// this file has ever done and all four of them got away with.
		//
		// gitd_pc_shape forces coverage, falloff and intensity on ALL FOUR
		// lanes to the gitd_pc_* working set for any preset above zero
		// (GlowHandler.zs:2200). It does not care that the palette is literal
		// or generated, and it does not care that twelve lines of argument
		// were just written above it. Left inherited from the Customise page,
		// every number in the block above becomes 32 / Sharp / 1.6 and the
		// entire lighting plan collapses into one uniform lane -- silently,
		// with the menu still reading exactly what was intended.
		//
		// The other four presets survive this only because nobody has flipped
		// that switch while one of them was selected. Cold War is the first
		// preset whose whole argument is the DIFFERENCE between the four
		// lanes, so it is the first that cannot afford to find out.
		B("gitd_pc_shape", false);

		// ---- four service intervals that were never meant to line up ------
		//
		// Black and White uses coprime totals so the four lanes never agree.
		// This does the same arithmetic for the opposite reason. There the
		// point is that you can never learn the rhythm; here each lane is
		// PERFECTLY regular -- eight equal holds, a metronome, the most
		// institutional thing a clock can be -- and the four metronomes are
		// simply running at different rates because nobody ever specified
		// that the lighting circuits in a building should agree with each
		// other. They were commissioned in different decades by different
		// contractors and they have all been correct ever since.
		//
		// THE FOUR RATES WERE 34 / 26 / 30 / 22 AND ALL FOUR WERE EVEN, which
		// quietly undid the paragraph above: every changeover in the building
		// landed on an even second, so the four "unrelated" circuits shared a
		// two-second grid and pairs of them re-aligned constantly. Four PRIMES
		// have no shared grid at all, which is the property the comment was
		// claiming and never had.
		//
		// 34 was also above the lane hold slider's own 0-30 ceiling, so the
		// shipped ceiling lane was a value a player could see, lose, and never
		// get back from the menu. All four below are inside it.
		//
		//   ceiling  8 x 29 = 232s      wall top  8 x 19 = 152s
		//   wall bot 8 x 23 = 184s      floor     8 x 13 = 104s
		//
		// Long, still. Twenty-nine seconds on the key light is a slot you stop
		// noticing, which is what makes the changeover land: you were not
		// waiting for it. The floor lane is the fast one at 13 because it is
		// the dimmest surface in the plan (intensity 0.55) and therefore the
		// cheapest place to buy the room a pulse -- across all four lanes
		// something in the room now changes about every five seconds instead
		// of every seven, without the key light ever becoming restless.
		//
		// None of the four divides the scan's 85-second leg or its 171-second
		// out-and-back, and that is checked rather than asserted: 17 was the
		// obvious fourth prime and was rejected because 85 is 5 x 17, which
		// would have locked the floor lane to the sweep for minutes at a time.
		// Red Alert locks its palette to its sweep because an alarm is one
		// procedure. This building is running five procedures that have never
		// been introduced.
		HoldFor("gitd_cg", 29, 29, 29, 29, 29, 29, 29, 29);
		HoldFor("gitd_wt", 19, 19, 19, 19, 19, 19, 19, 19);
		HoldFor("gitd_wb", 23, 23, 23, 23, 23, 23, 23, 23);
		HoldFor("gitd_fg", 13, 13, 13, 13, 13, 13, 13, 13);

		// AND THE THREE SWITCHES THAT WOULD THROW ALL THIRTY-TWO OF THEM AWAY.
		//
		// gitd_rnd_times is not a roll, it is a MODE: GITD_Lane.Step reads it
		// at every slot arrival and replaces that slot's hold with
		// frandom(0, 6) seconds. Twenty-nine becomes three, the metronome
		// becomes a stutter, and the thirty lines above describing four
		// perfectly regular service intervals describe nothing. It is the
		// single cvar in this mod that can delete a preset's central argument
		// without touching one of the cvars that preset wrote.
		//
		// gitd_rnd_patterns does the same to the snap -- each lane picks its
		// own transition from a map hash, so the contactor becomes a fade on
		// whichever lanes the hash felt like.
		//
		// gitd_rnd_colors is written for completeness and honesty rather than
		// for effect, and the honesty is the point. GITD_Lane.Step line 272
		// reads `toCol = (preset > 0) ? GITD_Presets.SlotColor(...) :
		// SlotColor(nextSlot)`, and every path that consults gitd_rnd_colors
		// lives inside the branch a preset never takes. Under any preset above
		// zero it is currently incapable of doing anything at all. Written
		// false so that the day the lane code is fixed to honour it, this
		// preset is already protected instead of newly broken.
		//
		// None of the four shipping presets states any of them, which is
		// survivable for a preset whose look does not rest on its rhythm.
		// This one's does.
		B("gitd_rnd_colors", false);
		B("gitd_rnd_times", false);
		B("gitd_rnd_patterns", false);

		// gitd_rnd_governor is deliberately NOT written, and the reason this
		// file used to give was false. It said the governor "only constrains
		// gitd_rnd_colors, which is now off". It does not: GITD_Palette
		// .RandomColor reads it directly, and Flashlight.SlotColor calls
		// RandomColor under fl_random with no preset gate whatsoever
		// (Flashlight.zs:88). The governor is live under any preset with a
		// random torch. The correct protection is not to pin the governor --
		// which decides what a random colour MEANS and belongs to whoever
		// switched randomness on -- but to state that this preset's torch is
		// not random at all. That is fl_random, written down with the rest of
		// the torch, and it is a safety interlock as well as a look. See there.

		// ---- NO WAVE, and it was the last thing cut ----------------------
		//
		// What this preset wanted from the wave was MAINS HUM: the hundred
		// hertz shimmer off a fluorescent bank that you only catch at the
		// edge of vision and cannot see when you look straight at it. The
		// dial cannot reach it -- speed caps at 8 rad/s, four orders of
		// magnitude short, and what you get up there is a throb. Red Alert
		// already owns the throb.
		//
		// Everything the wave CAN say is wrong here. Slow and deep is a
		// supply sagging, which is Low Power's entire preset. Slow and sharp
		// is Black and White's etched edge, which is a hand-cut composition.
		// Both of those are the light being INTERESTING, and the thesis of
		// this preset is that the light is correct and indifferent.
		//
		// So: off, explicitly, rather than left to inherit whichever of those
		// two the player last had running. The hum is not abandoned, it has
		// moved -- the glow texture block below is where it went, and the
		// reason it works there is that the wave varies a lane's EDGE while
		// the texture layer varies what is inside it.
		NoWave();

		// SEAMLESS OFF, EXPLICITLY, and this is a gap all four shipping
		// presets have. Only Wave() ever writes gitd_seamless, as a side
		// effect of the two being exclusive, so a preset that calls NoWave()
		// inherits it -- and seamless FORCES the flats to take the wall's
		// coverage, falloff and intensity (GITD_Handler.Apply).
		//
		// That would discard the ceiling-versus-floor difference set fifty
		// lines above, which is not a cosmetic loss here: it IS the lighting
		// plan. A seamless corner is beautiful and it is a room lit evenly
		// from everywhere, and a room lit evenly from everywhere has no
		// fixtures in it.
		B("gitd_seamless", false);

		// ---- the floor it stands on --------------------------------------
		//
		// COMPRESS, not Crush. Compress is proportional, so what the map
		// already lit stays relatively lit and what it did not stays dark --
		// which is exactly a building with working fixtures and no ambient
		// bounce. Crush would flatten the two together and lose the fixtures,
		// and the fixtures are the whole subject.
		//
		// Oppressive rather than Dismal, because "the lights work" is a claim
		// about the FIXTURES and not about the room. A facility lit only by
		// what is directly overhead is a dark facility; it is simply dark for
		// an administrative reason rather than a dramatic one.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 2);       // Compress
		I("ddz_preset", 4);     // Oppressive

		// A LIGHT FLOOR, AND IT IS THE ONLY ONE IN THE FILE.
		//
		// Blackout and Low Power both set this to 0 and argue for it: where
		// it goes dark it goes dark. This preset argues the reverse and needs
		// to, because a minlight of 10 is the single cheapest way to say the
		// power has never been off. There is no room in this building that
		// is genuinely black. Somebody is paying for that, and has been for
		// thirty years, and nobody has been in here to see it.
		I("ddz_minlight", 10);

		// AND VANILLA'S OWN LIGHT THINKERS STAY ON, which is also the only
		// yes in the file. Blackout kills them because a blinking sector in a
		// crushed map shoves a room back to its authored brightness several
		// times a minute and reads as the void switching itself off.
		//
		// Under Compress that failure does not occur -- the thinker's value
		// goes through the same proportional curve every tic, so a blinking
		// sector blinks WITHIN the darkened range instead of escaping it. And
		// what a blinking sector is, in this preset, is a tube with a failing
		// starter. That is the one flaw the maintenance contract permits.
		//
		// ONE-WAY, THOUGH, AND WORTH KNOWING BEFORE IT LOOKS LIKE A BUG. The
		// off state does not suppress the Lighting thinkers, it DESTROYS them,
		// every tic. Writing true back cannot rebuild what is already gone, so
		// arriving here directly from Blackout on the same map gives a
		// perfectly still building and the failing starter does not appear
		// until the next map load. That is a cost of Blackout's choice, not of
		// this one, and the only alternative is to not make the claim at all.
		B("ddz_lighting", true);

		// Sky sectors take the full adjustment. There is no daylight relief
		// in this preset: whatever is outside this facility is as cold as
		// what is inside it, and a bright doorway would promise otherwise.
		F("ddz_skymode", 1.0);

		// ---- THE COLOUR THAT IS LEFT, AND WHICH COLOUR IT IS -------------
		//
		// 150 is a hard drain but not a total one, and the number matters
		// less than what survives it.
		//
		// KEEP HUE 3 -- BLUE ONLY. Blackout and Black and White both keep red
		// so the blood stays; this keeps blue so the LIGHT stays, and the
		// blood comes out grey with everything else. That is the coldest
		// sentence available in this system and it is worth the whole preset:
		// the only thing in the building permitted to have a colour is the
		// building's own lighting.
		//
		// And it is what makes the sodium work. The keep weights the drain by
		// each pixel's own hue, so the blue-white tubes and the arctic purple
		// lanes come through at nearly full strength while an emergency
		// sodium lamp -- vivid, warm, and nowhere near the blue gate -- takes
		// the full 150 and arrives as a washed, weak, apologetic orange.
		// A warm lamp that is visibly LOSING, which is the brief, and it
		// falls straight out of one cvar rather than needing a lane spent
		// on it.
		//
		// AND THE THRESHOLD HAS TO BE SET AGAINST WHAT ARRIVES AT THE SHADER,
		// NOT AGAINST WHAT PARAMS SAYS. This is the trap in the whole block.
		//
		// The keep gate is smoothstep(lo, lo+soft, sat) on the pixel's own
		// HSV saturation, measured after everything upstream of it. Params
		// case 4 generates sat = 0.78 +/- 0.20, so the low slots are already
		// 0.58 -- and then Lanes("_saturation", 0.72) forty lines above runs
		// GITD_Palette.Saturate on the colour BEFORE it is ever pushed, which
		// pulls the whole range down again. What actually reaches the gate is
		// roughly 0.46 at the bottom of the variance and 0.84 at the top.
		//
		// A threshold of 0.68 would therefore have drained most of the
		// palette to grey and kept only the two or three brightest slots per
		// lane -- a building whose own light goes colourless for two thirds
		// of every service interval and blue for the rest, which is a flicker
		// nobody asked for and the exact "nearly grey is worse than either"
		// failure this preset is trying to avoid. 0.30 with a narrow 0.10
		// edge clears the dimmest slot with room to spare.
		//
		// It costs nothing on the sodium, because the sodium never reaches
		// the saturation test at all: the hue gate is by dominant channel and
		// a warm lamp is red-dominant, so it fails gate 3 and takes the full
		// drain whatever its saturation is. The threshold guards the lanes;
		// the gate is what makes the lamp lose. Two separate jobs, and only
		// the first one was set wrong.
		I("ddz_desat", 150);
		KeepColor(0.30, 0.10, 3);

		// PER PIXEL, SHALLOW AND LONG. 0.42 over 3400 units is the gentlest
		// distance falloff of the four presets that use one, and gentle is
		// the point: this room is legible. Low Power uses 0.86 over 1000 to
		// make a corridor STOP being visible, which is concealment and which
		// is drama. Here the far end of a hall is simply further away than
		// the near end, the way it is in a correctly lit building.
		//
		// NO HEIGHT POOLING AT ALL. Dark gathering on the floor is what
		// happens when light is running out, and light is not running out.
		// It is also the term that would fight the fog layer directly below,
		// and two systems darkening the same ankle-height band is how you get
		// a black stripe nobody asked for.
		DeepDark(0.42, 3400.0, 0.0, 0.0, 256.0);

		// ---- the air, which is cold rather than dirty --------------------
		//
		// THIN, AND NOT SMOKE. Density 0.45 is the lightest layer in the file
		// by a distance -- Low Power runs 1.10, Black and White 0.7. Anything
		// heavier reads as something BURNING or something ROTTING, and both
		// of those are events. Cold is not an event. It is a condition, and a
		// condition should be barely visible and completely inescapable.
		//
		// Top 36 with a very soft 30-unit edge. That puts the surface just
		// under the eyeline at 41, so you can still look down the length of a
		// corridor and see it lying there -- go above 41 and the layer stops
		// being a thing in the room and becomes a filter on the lens, which
		// is the single easiest way to lose this whole system. The soft edge
		// is nearly as deep as the layer itself on purpose: cold air does not
		// have a waterline.
		//
		// PICKUP 0.20, AND THIS IS THE OTHER HALF OF THE SODIUM ARGUMENT.
		// Every other preset with fog turns pickup up so the air takes colour
		// from what is behind it and the two systems stop reading as separate
		// layers. This one refuses almost all of it, so a warm lamp lights
		// the air within a few feet of itself and then the room takes it
		// straight back. The lamps are islands. Nothing they warm stays warm,
		// which is why they are losing.
		//
		// AND THE WAKE IS ZERO, WHICH IS THE LAST TWO ARGUMENTS OF THE CALL
		// AND THE MOST IMPORTANT NUMBER IN IT.
		//
		// The wake is not part of reactive fog and NoReactive() below does not
		// reach it: GITD_Handler.PushFogWake checks gitd_fog_enabled and
		// gitd_fog_wake and nothing else, so a layer with a wake carves a
		// channel behind the player whether or not gitd_fog_react is set. It
		// is the mist responding to a body moving through it -- the single
		// most direct statement in the entire mod that the room has noticed
		// you -- and it would have run underneath four hundred lines arguing
		// that nothing here does. All three other presets take it (0.7, 0.5,
		// 0.35) and all three are entitled to. This one cannot have it at any
		// strength, so it is 0 rather than small.
		//
		// Size and lag still have to be passed and are inert at strength 0
		// (PushFogWake returns before it reads them). They are left at
		// unremarkable values rather than zeroed, because a zero there would
		// read as a number somebody meant.
		Fog(36, 0.45, 30, 0x8FA6B4,
		    1.0,      // the torch carves a clean shaft and nothing more
		    0.20,     // and almost nothing tints it
		    0.0, 100, 0.08);

		// CONSTANT DEPTH, AND IT IS THE OPPOSITE OF EVERY OTHER PRESET HERE.
		//
		// The other three sag their layer into low ground -- 0.3, 0.1, and
		// Black and White's deliberate 0.0 level plane -- because mist that
		// pools reads as weather and a flat one reads as a printed tone.
		// Neither of those is what cold is. Cold does not arrive, settle and
		// find the lowest point in the room; it comes out of the concrete,
		// so it is the same depth on the landing as it is in the stairwell
		// and it climbs every step with you.
		//
		// 0.85 rather than 1.0 leaves just enough sag that a sunken room is
		// fractionally deeper than the corridor feeding it, which is the only
		// concession to physics the preset makes and it stops the layer
		// reading as a decal stuck to the geometry.
		Follow(0.85, 0.0);

		// AND THREE MORE OF THE LAYER'S OWN SHAPE, WHICH Fog() DOES NOT TOUCH
		// AND NO PRESET IN THIS FILE HAS EVER WRITTEN.
		//
		// Fog() sets ten cvars and none of these is one of them, so all three
		// arrive from wherever the menu or the last preset left them -- and
		// every one of them contradicts something argued above.
		//
		//   roll     scrolls the whole layer sideways at so many units a
		//            second. That is air being moved, which is the exact
		//            thing NoSurface() below refuses on the same grounds. A
		//            leftover here would slide the slab under a preset whose
		//            claim is that nothing in it goes anywhere.
		//   period   repeats the layer up the room. One slab at ankle height
		//            is cold coming off the floor; a stack of them every N
		//            units is an effect. 0 is one layer.
		//   bottom   the shipped -32768 means "no bottom" and is deliberately
		//            outside its own slider, so once a designer has touched
		//            that slider they cannot get back to it from the menu.
		//            A layer that follows the floor at 0.85 and then stops at
		//            some fixed world height would tear apart on the first
		//            staircase, which is precisely where this preset is
		//            making its point.
		F("gitd_fog_roll", 0.0);
		F("gitd_fog_period", 0.0);
		F("gitd_fog_bottom", -32768.0);

		// AND THE TOP DOES NOT MOVE. Every other preset with fog gives the
		// surface a swell, on the correct reasoning that a flat top reads as
		// a sheet of card. This one accepts the card.
		//
		// A rolling surface is air being MOVED -- Red Alert's is fast because
		// the handling is running, Low Power's is slow because the air is
		// settling. Both of those are the air doing something. Still air that
		// is merely cold is not doing anything, and putting a swell on it
		// would be the one lie in the preset. Follow 0.85 above already gives
		// the layer all the shape it needs, from the floor rather than from
		// a wave, which is where a cold layer's shape actually comes from.
		NoSurface();

		// Barely banked, and deliberately barely. Uniform density is a filter
		// applied to the screen rather than a substance in the room, so it
		// cannot be zero -- but 0.45 or 0.55 is a substance with WEATHER in
		// it, and this has none. 0.18 over hall-sized banks drifting at half
		// a unit a second is a room whose air is very slightly not the same
		// everywhere, which is true of every real room and reads as nothing
		// at all until you look for it.
		FogBanks(0.18, 0.0018, 0.5);

		// NOTHING RISES OFF IT. Tendrils are convection -- warm air lifting
		// off a warm surface -- and Low Power is welcome to them because a
		// dead plant is still warmer than its corridors. There is nothing in
		// this building warm enough to make one, and a wisp here would be the
		// preset contradicting its own title.
		NoTendrils();

		// AND NOTHING DISTURBS IT. This is the largest refusal in the preset
		// and the one the whole thing rests on.
		//
		// Red Alert pushes the mist with gunfire and death because a building
		// on alert is a building REACTING. Black and White takes the ring off
		// the gun because a geometric front in a still composition is the one
		// motion it can afford. Blackout takes ignite because in a black room
		// an explosion carving out the shape of the space is the only light
		// there is.
		//
		// Cold War refuses all three, and refuses them for the same reason it
		// refuses the heatmap below: this installation does not respond to
		// you. It was running before you came in and it will be running after,
		// at exactly this temperature, and the moment the air recoils from
		// your muzzle the building has acknowledged you. That single frame of
		// acknowledgement is worth more than every other system in the mod,
		// and it is why nothing here gets to have it.
		//
		// NoReactive() also clears gitd_fog_displace, which matters more than
		// it looks: displace carves the mist around nearby actors, so an
		// inherited value would have the air outlining monsters through a
		// wall of fog in the preset that just spent nine lines refusing to
		// notice them.
		NoReactive();

		// NO BOW WAVE, and this is the only preset with a travelling band
		// that has one to refuse. The bow is mist shouldered aside by a sweep
		// band, which requires the band to be a physical object; the scan
		// below is a line of LIGHT crossing a room and light has no mass. Red
		// Alert's klaxon can push air because a pressure wave is genuinely
		// what it depicts. A sensor sweep that parted the fog would be the
		// facility's instruments having a body, which is a different and much
		// sillier film.
		Bow(0.0, 64.0, 0.6);

		// THE PICKER, AND NOTHING ELSE. Mode 0 means the layer is exactly the
		// grey-blue set above and takes its colour from no other system.
		//
		// This matters more here than anywhere. Low Power leaves the mode on
		// 4 (the nearest liquid) and Red Alert on 1 (match a lane), so a
		// preset selected after either of those and not stating a position
		// gets its air tinted by a nukage sump or by the floor glow. Black
		// and White is the standing example of that fault: it argues at length
		// for a layer that nothing can tint and then never writes the mode.
		//
		// gitd_fog_color_lane and gitd_fog_color_blend are deliberately NOT
		// written. Mode 0 does not read either of them, and a preset that
		// writes dead values leaves the next reader working out whether the
		// mode was meant to be 1.
		I("gitd_fog_color_mode", 0);

		// One gradient through the layer's own thickness, paler at the top.
		// It is a small thing and it does one specific job: the air nearest
		// the ceiling is the air nearest the tubes, so the layer is very
		// slightly brighter where the light is and the whole slab reads as
		// being lit from above like everything else in the preset. Mix 0.22,
		// because two blues is already a colour decision.
		FogGradient(0xC2D2DC, 0.22);

		// ---- NO LATTICE, and it was the obvious idea ---------------------
		//
		// "Hardened installation, still watched" wants a laser grid so badly
		// that it was in the first draft. It is wrong, and it is wrong for a
		// reason worth writing down: a laser lattice is ADDRESSED TO YOU. It
		// says do not cross this, which means somebody put it there expecting
		// somebody else, which makes the building a trap and you its subject.
		// The preset is built on the opposite claim -- that the facility is
		// running a routine it would run into an empty room.
		//
		// NoGrid() only clears gitd_ss_fill_air, which is the lattice hanging
		// in the AIR. The per-band fill modes it does not touch, so a preset
		// following one that called Grid() still has a painted lattice on
		// every band. All four shipping presets call NoGrid() and none of
		// them states the fill modes. This one does, all eight of them, even
		// though only two bands run below -- because a band table is the one
		// place in this file where an inherited value is invisible until
		// somebody raises the count.
		NoGrid();
		for (int i = 1; i <= 8; i++) I("gitd_ss_fill" .. i, 0);

		// ---- THE MAINS HUM, WHICH IS THE ONE SYSTEM THIS PRESET OWNS -----
		//
		// This block used to be five zeroes and a paragraph about how an
		// institutional surface is EVEN. The paragraph was half right and it
		// cost the preset its only image. Cold War's problem was never that
		// it was restrained; it was that after every refusal was honoured
		// there was nothing left in the frame but four flat rectangles of
		// blue changing colour on a slow clock. Restraint is a choice about
		// what carries the image. It is not the absence of one.
		//
		// So the fifth paragraph of NO WAVE above gets what it asked for.
		// The wave varies a lane's EDGE and had no way to make a hundred-hertz
		// shimmer; the texture layer varies what is INSIDE the lit area and is
		// sampled in world space (Render.PushGlowTexture), which is a
		// completely different mechanism and can. Three of the five terms are
		// on, at the smallest weights in the file, and the two that would make
		// the building notice you stay at zero.
		//
		// NOISE -- the fitting has an age. Scale is inverted (cvarinfo:1314,
		// "smaller = larger patches"), so 0.06 against the 0.02 default is a
		// FINER grain, which is staining in the diffuser rather than weather
		// on the wall. Drift 0 because a stain is a property of the fitting
		// and does not travel through it. Contrast at the neutral 1.0; above
		// that the mottle becomes plasma and this is a light fixture.
		F("gitd_gtex_noise", 0.10);
		F("gitd_gtex_scale", 0.06);
		F("gitd_gtex_drift", 0.0);
		F("gitd_gtex_contrast", 1.0);

		// FLOW -- the hum itself, and the only fast thing in the preset.
		// Spacing 16 against the 64 default is four times finer, and sharp
		// 4.0 makes them lines rather than a swell: what crosses the surface
		// is a comb, not a wave.
		//
		// SPEED 2.4 AND NOT THE 4.0 THE DIAL ALLOWS, and this is a safety
		// number as much as a taste one. A fine high-contrast pattern at 20%
		// depth crossing a lit surface at the dial's ceiling is a flicker, and
		// a flicker is exactly the failure mode of the fixture this preset is
		// depicting -- the one place in the mod where "it looks like a broken
		// tube" is a hazard rather than a compliment. 2.4 is a shimmer you
		// catch at the edge of vision, which was the specification.
		//
		// AND THE HONEST LIMITATION, because it will look like a bug
		// otherwise. The axis comes from the surface normal (cvarinfo:1332):
		// vertical on a wall, along world X on a floor or ceiling. In a
		// north-south corridor the ceiling's shimmer therefore runs ACROSS
		// the tubes rather than along them. There is no cvar that fixes this
		// and it is worth the term anyway -- on walls, which is most of the
		// lit surface you look at, the axis is right everywhere.
		F("gitd_gflow", 0.20);
		F("gitd_gflow_spacing", 16.0);
		F("gitd_gflow_speed", 2.4);
		F("gitd_gflow_sharp", 4.0);

		// CELLS -- frost in the glass. Scale 192 against the 96 default is
		// cells twice the size, so it is a structure rather than a texture;
		// width 0.03 against 0.08 is hairlines; and crawl 0.2 against 1.2 is
		// nearly still, because frost does not crawl and a cell network that
		// visibly moves is the single most organic thing this mod can draw.
		// At 0.15 it is the faintest term in the preset and you should not be
		// certain you saw it.
		F("gitd_gcell", 0.15);
		F("gitd_gcell_scale", 192.0);
		F("gitd_gcell_speed", 0.2);
		F("gitd_gcell_width", 0.03);

		// AND THE TWO THAT STAY AT ZERO, which is where the restraint went.
		//
		// greact rides the same eight disturbance slots as reactive fog and
		// puts a ring through the lit surfaces of a room off every shot. It
		// is free here in the sense that NoReactive() above has already
		// emptied the array -- and that is exactly why it is written rather
		// than left: free today, live the moment anything else fills those
		// slots.
		//
		// gpulse is the loud one and the refusal that matters. It is the only
		// term in this system that makes the light carry INFORMATION -- driven
		// by monsters near you or by your health -- and cvarinfo:1360 calls it
		// "the one thing none of the four above can do however good they look".
		// That is true, and it is the sentence four hundred lines of this
		// function exist to refuse. A building that brightens when something
		// is near you has noticed you. The four sub-terms (src, range, count,
		// level) are deliberately unwritten: the shader reads them inside the
		// gpulse > 0 branch, and writing dead numbers leaves the next reader
		// working out whether the pulse was meant to be on.
		F("gitd_greact", 0.0);
		F("gitd_gpulse", 0.0);

		// ---- the torch ---------------------------------------------------
		//
		// HARD, LONG, AND COLD, and every number in it is the brief's "sharp
		// shadows instead of soft".
		//
		// Inner 13 against outer 18 is a five-degree penumbra, by some way
		// the tightest in the file -- the others run gaps of thirteen, sixteen
		// and ten. A wide gap is a soft-edged pool, which is a hand torch. A
		// five-degree gap is a defined disc with an edge you could measure,
		// which is a service lamp issued to somebody who has to inspect
		// things, and it is what throws a shadow with a border on it.
		//
		// FALLOFF 0.6, and it is the only value below 1.2 in the file. Above
		// 1 the beam concentrates near the lens and dies with range, which is
		// a battery. Below 1 it holds its strength the whole way out, so at
		// 1800 units the far end of a corridor is lit as hard as your feet.
		// That is not a torch, it is a searchlight, and it is deliberate: the
		// light in this preset does not fall off with distance, it stops.
		//
		// Density 0.9 and dust low and nearly still. Low Power's cone is a
		// solid object full of hanging motes because nobody has swept the
		// place; this one is a clean shaft with a little very fine dust in it
		// that is barely moving, because the air is not moving.
		B("fl_enabled", true);
		I("fl_range", 1800);
		F("fl_intensity", 1.00);
		F("fl_inner", 13.0);
		F("fl_outer", 18.0);
		F("fl_falloff", 0.6);
		F("fl_density", 0.9);
		F("fl_dust", 0.25);
		F("fl_dust_scale", 0.10);   // fine. Frost, not sawdust.
		F("fl_dust_drift", 0.02);   // and it is going nowhere
		B("fl_bounce", false);      // no omnidirectional fill. A torch is a cone.
		I("fl_slots", 1);
		I("fl_pattern", 0);

		// FL_RANDOM FALSE, AND IT IS AN INTERLOCK RATHER THAN A PREFERENCE.
		//
		// This preset runs fl_slots 1, which takes the short-circuit at
		// Flashlight.CurrentColor line 106: `if (count <= 1) return
		// SlotColor(0);`. That line runs EVERY FRAME, and SlotColor's first
		// statement under fl_random is `return GITD_Palette.RandomColor()`
		// (Flashlight.zs:88). One slot plus a random torch is therefore a
		// full-saturation colour strobe at frame rate, six inches from the
		// eye, with no error, no warning and nothing in the menu suggesting
		// it. No preset in this file states fl_random, so any player who has
		// ever switched it on carries it into here.
		//
		// It is written false because inheriting true is a photosensitivity
		// hazard, and it is written HERE, next to fl_slots 1, so that anyone
		// who later raises the slot count can see what the pairing was for.
		// A preset that wants a random torch must have two slots or more.
		B("fl_random", false);

		// AND THE LIGHT DOES NOT WAKE WHAT IT LANDS ON. fl_agitate makes
		// pointing the beam at a monster alert it -- a genuinely good idea and
		// the sharpest sentence in the whole flashlight rig, in a preset where
		// the torch is the only way to see. It is the exact opposite of this
		// one. Here the building is indifferent and so is everything in it;
		// a torch that provokes is the player's light making the room react,
		// which is the same refusal as the wake, the ring and the pulse.
		// No preset states it, so it is inherited by all eight today.
		B("fl_agitate", false);

		// AND THE THING YOU CARRY IS COLD TOO. Every other preset leaves the
		// torch its shipped halogen white -- warm, and correct for them,
		// because a warm object in your hands against a cold room is a
		// comfort and three of the four want you to have it. This preset
		// takes it away. Whatever you brought in here has been in here as
		// long as you have.
		I("fl_c1", 0xE8F2FF);

		// ---- THE SCAN ----------------------------------------------------
		//
		// THE ARITHMETIC WAS WRONG AND THE COMMENT ABOVE IT WAS WORSE. It
		// shipped as range 8192 at speed1 55, and it described that as "the
		// bar passes any given spot once every two and a half minutes". Two
		// things were false about that sentence.
		//
		// First, 8192 is TRAVEL and not map size. Shape 2 compares the band's
		// position against abs(dx) from the origin, so on a map of half-extent
		// 2000 the bar was inside the geometry for 2000/55 = 36 seconds of
		// each 149-second leg. A 24 PER CENT DUTY CYCLE: three quarters of the
		// preset's headline system was happening outside the level.
		//
		// Second, under pingpong the interval at a fixed point is not uniform
		// and never was. A point at distance d from the origin is crossed once
		// per leg, so the intervals ALTERNATE 2d/v and 2(range-d)/v. At d=1000
		// that shipped as 36 seconds and then 261 seconds. The player saw the
		// scan twice in half a minute and then not again for four minutes, and
		// "once every two and a half minutes" was an average nobody ever
		// experienced.
		//
		// SO: RANGE 2560 AND SPEED1 30. One leg is 85.3 s, the out-and-back is
		// 170.7 s, and the duty cycle on that same 2000-unit map is 78 per
		// cent. The alternating intervals become 67 s / 104 s at d=1000 and
		// 33 s / 137 s at d=500 -- still alternating, because pingpong cannot
		// do otherwise and pretending it can is what produced the old comment,
		// but the long half has come down from four and a half minutes to
		// under two. 2560 is on the range slider's own 128-unit step and 30 is
		// on the per-band speed slider's 5-unit step, which 48 never was.
		//
		// AND SPEED2 HAD TO MOVE WITH IT, WHICH IS NOT OPTIONAL.
		// WaveBandSpeedScale (GlowHandler.zs:1047) is speedN / speed1, so the
		// crush band's rate is expressed as a RATIO of the line's. Leaving 48
		// against a new speed1 of 30 would make that ratio 1.6 and the crush
		// band would overtake the line it is supposed to be a consequence of.
		// 25/30 keeps the old 0.87 relationship almost exactly.
		//
		// DIRECTION 2, OUT AND BACK, and it is the first use of it in this
		// file. Low Power and Red Alert both run outward and then silence,
		// because both are depicting an EVENT that happened somewhere and
		// propagated. This is not an event, it is a head on a rail, and a
		// head on a rail comes back. That is the whole difference between a
		// scan and an alarm and it costs one integer.
		//
		// It also takes the trigger and the train logic out of the path
		// entirely -- Step returns inside the pingpong branch before it ever
		// consults loop or TrainClear -- so gitd_ss_trigger below is written
		// as a statement of position rather than as a mechanism this preset
		// relies on. Nothing stops the bar. That is the point of it.
		//
		// SHAPE 2, a bar. A ring says the thing originated at a point and is
		// spreading, which is what a breach does. A flat plane crossing the
		// map at a constant rate is what a machine does, and the machine does
		// not care that the map has a centre.
		//
		// SOFTNESS 1.2, the hardest edge in the file. Low Power's 3.2 is a
		// wave of power and Red Alert's 2.4 is a lamp; both want a leading
		// edge you cannot quite locate. This one wants a line. TRAIL 0 for
		// the same reason -- a wake is the band being tired, and instruments
		// are not tired.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 2);
		I("gitd_ss_shape", 2);        // a bar, travelling E/W
		I("gitd_ss_origin", 0);       // map centre, and it is only a rail
		                              // origin -- the scan is not aimed at you
		I("gitd_ss_direction", 2);    // out, and back
		I("gitd_ss_trigger", 0);      // free-running. It ran before you came in.
		I("gitd_ss_drive", 0);        // time, not kills and not your health.
		                              // Nothing in this preset is driven by you.
		I("gitd_ss_range", 2560);
		F("gitd_ss_softness", 1.2);   // a line, not a front
		F("gitd_ss_intensity", 1.0);  // and no brighter than the room it crosses
		I("gitd_ss_thickness", 24);   // the shared fallback, set to match the
		                              // line below so the menu's Thickness row
		                              // describes the band you actually see
		I("gitd_ss_trail", 0);
		B("gitd_ss_underlay", true);  // the lanes keep running underneath;
		                              // the room is not put on hold for this
		F("gitd_ss_drift", 0.0);      // no spread. Two bands, both on rails.
		F("gitd_ss_health_speed", 0.0);
		F("gitd_ss_spin", 0.0);
		F("gitd_ss_spin_radius", 0.0);
		I("gitd_ss_spin_colors", 0);
		B("gitd_ss_drop", false);
		B("gitd_ss_actors", false);

		// THE PER-SECTOR LIGHT PATH IS OFF, AND SO IS ITS BACK DOOR.
		//
		// gitd_ss_light false stops fx 1 and fx 2 -- and ONLY those two. With
		// per-band off, every band's effect comes from gitd_ss_light_mode
		// instead (GlowHandler.zs:1149), and modes 3 through 7 are not gated
		// by gitd_ss_light at all: an inherited 4 would run a sonar reveal on
		// both bands, 5 would wake every monster the scan crossed, 6 would
		// mark them. A scanning routine that wakes the building is a
		// completely different preset and it would arrive here by inheritance
		// with no line of this file mentioning it.
		//
		// perband false has a second job as well: WaveBandAction resolves
		// gitd_ss_scriptN whenever perband is true, so leaving it inherited
		// would let a class name somebody typed on the Edit One Band page fire
		// on every band of this preset. Off here means the eight script slots
		// cannot be reached and do not need writing.
		B("gitd_ss_light", false);
		B("gitd_ss_perband", false);
		I("gitd_ss_light_mode", 0);

		// Five seconds of the line's own travel between it and what follows.
		// The gap is in TICS, which is why it survived the speed change
		// untouched: 175 tics is 5 s of leader travel whatever the leader's
		// rate, so the crush band still arrives about six seconds behind the
		// line at the origin plane. It is chosen to be a gap you read as
		// CONSEQUENCE rather than as a second band -- long enough that the
		// first has left the part of the room you are in before the second
		// arrives.
		I("gitd_ss_gap1", 175);

		// The line itself. Thickness 24 is 48 units wide (a band is twice its
		// thickness) and at 30 units a second that is 1.6 seconds to cross
		// you: quick, clean, and gone. It was 40 thick at 55, which was the
		// same 1.5 seconds -- halving the speed without thinning the band
		// would have made the one sharp object in the preset take nearly three
		// seconds to pass, which is not a line any more, it is a wall.
		F("gitd_ss_speed1", 30.0);  I("gitd_ss_shape1", 2);
		I("gitd_ss_thick1", 24);    I("gitd_ss_draw1", 1);

		// AND WHAT IT LEAVES BEHIND. Draw 3 is crush -- a per-pixel multiply
		// down, travelling. 140 thick is 280 units, and at 25 a second that is
		// 11 seconds to pass, so it is not a band at all, it is the room
		// getting fractionally colder for ten seconds after the scan and then
		// recovering. Thickness came down from 260 for the same reason the
		// line's did: at the new rate 520 units would have taken 21 seconds
		// and the crush would have stopped being an event and become the
		// weather.
		//
		// Slower than the line, so over a leg the two drift further apart
		// rather than staying a pair -- six seconds behind at the origin
		// plane, thirteen at a thousand units out. Nothing overtakes and
		// nothing catches up, which is what a routine looks like when it has
		// been running unattended for long enough.
		//
		// THE COST OF THAT, STATED RATHER THAN DISCOVERED: a band expressed as
		// a ratio of the leader's speed also has a shorter REACH. Band 2's
		// furthest position is range x 0.833 minus the 150-unit gap lag, which
		// is 1983 units against the line's 2560. On a map wider than about
		// four thousand units the crush band does not quite reach the far
		// walls that the line does. That is the price of the drift and it is
		// worth it; a uniform train would cover the whole range and hold
		// formation forever, which is a different and more mechanical claim.
		F("gitd_ss_speed2", 25.0);  I("gitd_ss_shape2", 2);
		I("gitd_ss_thick2", 140);   I("gitd_ss_draw2", 3);

		// The line is the coldest white in the preset; the crush band carries
		// no light of its own and its colour is only what the menu shows, so
		// it gets a truthful near-black rather than a swatch that lies.
		//
		// Bands 3 to 8 are not written. Count 2 never reads them, and six
		// dead speed/shape/thick/draw records in the backup are six things
		// Restore has to put back that the player never had touched. The fill
		// loop above is the deliberate exception, and it is deliberate
		// because fill is the one band field with a documented inheritance
		// asymmetry.
		I("gitd_ss_c1", 0xD6E4F0);
		I("gitd_ss_c2", 0x0A0E14);

		// ---- what this preset refuses, and why ---------------------------

		// NO TORNADO. A funnel is weather with a personality, and this
		// building has neither. It is also the most expensive thing in the
		// shader and the last thing a preset about restraint should spend on.
		NoTornado();

		// NO HEATMAP, and this is the refusal that costs the most.
		//
		// Blackout takes it because in a black room the floor is the only
		// thing that can remember anything. Black and White takes it in grey
		// because a room you walk back into is not the room you left. Red
		// Alert takes it because an alert with no trace afterwards is a light
		// show. All three are right, and all three are making the same claim:
		// that this place is changed by what you did in it.
		//
		// That claim is the exact one Cold War cannot make. The whole preset
		// is a facility that will be at this temperature, on this schedule,
		// under these fixtures, whether or not anything happened in it today.
		// A floor that keeps score is a floor that cares.
		NoHeat();

		// AND THE OTHER THING THAT WRITES ON THE FLOOR, which is a separate
		// system with a separate switch and makes the identical claim.
		//
		// gitd_shape_enabled gates twenty-one cvars that stamp a signed
		// distance mark where a monster died -- gitd_shape_on_death ships
		// TRUE, so the moment that master is on the marks appear with nothing
		// else asked for. Refusing the heatmap in nine lines and then leaving
		// this inherited would be refusing to keep score in one ledger while
		// keeping it in the other. No shipping preset states it and there is
		// no helper, so it is written flat.
		B("gitd_shape_enabled", false);

		// AND THE THIRD LEDGER, WHICH SHIPS ON. gitd_neon_enabled defaults to
		// TRUE (cvarinfo:444) -- it is the only master in this family that
		// does -- so the Numeric Violence Engine is armed under every preset
		// in this file and is drawing nothing only because its two payload
		// switches happen to default off. A player who has ever turned on the
		// kill counter gets floating numerals stamped where each body fell,
		// in the preset whose entire thesis is that the building does not
		// notice you. A score is a score whether it is painted on the floor
		// or set in a font above it.
		B("gitd_neon_enabled", false);

		// AND THE COLOUR LAW, which is the only system in the mod where the
		// room's colour changes the FIGHT rather than the picture. It is off
		// by default, so this write only bites a player who configured it --
		// but Cold War was the one preset of eight that never said so, and a
		// preset that spends four hundred lines refusing to be addressed to
		// you cannot leave a rule in force that makes the lighting a combat
		// modifier. A lighting menu is not consent to a gameplay change.
		B("gitd_law_enabled", false);

		// LIGHTS WHERE THE MAP SAYS THERE ARE LIGHTS, AND NOWHERE ELSE.
		//
		// Detail 1 lights only the fixtures the map already implies -- lit
		// ceiling flats, wall light textures, teleport pads. Detail 2 adds
		// the flavour tier: glowing slime, computer banks, the face. Red
		// Alert takes 2 because a building at full alert has every panel it
		// owns switched on. This building is not at alert, it is at rest, and
		// a facility at rest runs its lighting and its plant and nothing
		// decorative. Scale 0.55 because they are the same aged tubes.
		//
		// PARTICLES AT ZERO. Every particle this layer emits is warm or wet:
		// embers, drips, steam off slime. There is nothing in this building
		// hot enough to spark and nothing liquid enough to drip, and a single
		// ember would undo four hundred lines of argument. Off by passing 0,
		// which is a stated position rather than the blanket NoAmbienceLight
		// -- the lights are wanted here, and only the particles are not.
		Ambience(1, 0.55, 0.0);

		// AND THE RADIUS, WHICH NoAmbienceLight'S OWN COMMENT DEMANDS AND NO
		// PRESET HAS EVER GIVEN IT. fw_range is the per-emitter audibility
		// radius, so every preset in this file has so far sounded identical
		// no matter what it argued about acoustics.
		//
		// 1024, half the shipped default, and it is the same claim Occlude
		// makes below rather than a second one: if a metre of reinforced
		// concrete means an emitter with no sight line all but disappears,
		// then an emitter three rooms away should not be audible through the
		// open doors either. Halving the radius is what makes "a series of
		// small silences" true of the ambience layer and not only of the
		// geometry. It is the shortest range in the file and it should be.
		F("fw_range", 1024.0);

		// FOOTSTEPS, RAISED A LITTLE. Concrete, steel and a lot of empty
		// volume: you are the loudest thing in here, and that is worth
		// hearing. Not Blackout's 1.25 though -- there your feet are the map,
		// because you cannot see. Here you can see perfectly well, so they
		// are only company.
		Steps(1.1);

		// AND THE MOST MUFFLED SETTING IN THE FILE, for a literal reason
		// rather than a mood one. This is a HARDENED installation. The walls
		// are a metre of reinforced concrete and sound does not go through a
		// metre of reinforced concrete. 0.15 means an emitter with no sight
		// line all but disappears, so every room is acoustically sealed from
		// the one next to it, and the building is a series of small silences
		// rather than one large sound.
		Occlude(0.15);
	}

	// FLUORESCENT BLOOM, WHICH MEANS A LINE RATHER THAN A POINT.
	//
	// Threshold 0.55 is the middle of the file, and middle is right: Blackout
	// puts it at 0.82 so that only what is genuinely past white blooms, Low
	// Power at 0.22 so that the little light there is smears rather than sits.
	// This preset has plenty of light and none of it is hot, so a low
	// threshold would haze the entire room and a high one would find nothing
	// at all. 0.55 finds the tubes, the scan line and the muzzle, and leaves
	// the walls matte.
	//
	// Amount 1.10, the lowest in the file and lower than the engine's own
	// default. A bloom that is doing a lot is a lens being expressive. This
	// one is barely present -- just enough that a fixture reads as a light
	// source rather than as a bright rectangle. Knee 0.25 so it crosses
	// hard: a tube is on or it is not.
	//
	// ANAMORPHIC, AND LOW POWER GOT HERE FIRST WITH A DIFFERENT ARGUMENT.
	// It draws a horizontal streak off a dying fixture seen side on, and
	// there the streak is a FAULT. Here it is simply what a four-foot tube
	// looks like -- the smear reads as the SHAPE of the source rather than as
	// something wrong with it -- and since the gate cannot express "weaker",
	// the whole difference has to live in the ratio. See the block below.
	//
	// It is also the lens agreeing with the surfaces for once: the glow flow
	// term now runs fine lines along the lit area at 16-unit spacing, and a
	// bloom that stretches a highlight along one axis is the same statement
	// made by the optics. That was an accident of two systems arriving a year
	// apart and it is worth keeping on purpose.
	//
	// Chromatic explicitly zero. Fringing is a lens failing to agree with
	// itself, which is the right artefact for a room that is telling you
	// something has gone wrong. Nothing here is wrong. The lens is in focus,
	// the fixtures are lit, the schedule is being kept.
	clearscope static void ColdWarBloom()
	{
		Bloom(1.10, 0.55, 0.25, 0.86, 0.94, 1.0);
		// 0.28 WAS NOT A STRENGTH, it was a full streak wearing one. See the
		// note in LowPowerBloom: the cvar is a bool the engine tests as a gate,
		// so 0.28 and 1.0 are the same picture, and the ratio is the only lever.
		//
		// So the intent moves to where it can be honoured. 4.5 was chosen while
		// believing it would be scaled down to roughly a quarter; ungated it is
		// the widest streak in the file, on the one preset whose entire thesis
		// is that nothing here is dramatic. 1.6 is a streak you notice on a
		// fixture and not on a wall, which is what a cold institutional room
		// with tube lighting should give you. This preset has never shipped, so
		// nothing is being taken away from anyone by fixing it now.
		EF("gl_bloom_anamorphic", 1.0);
		EF("gl_bloom_anamorphic_ratio", 1.6);
		EF("gl_bloom_chromatic", 0.0);

		// AN EXPOSURE THAT DOES NOT DRAMATISE, which is harder to specify
		// than one that does.
		//
		// AND THE SPEED DIAL IS NOT SECONDS. gl_exposure_speed is handed to
		// the exposure combine pass as the SOURCE ALPHA of an alpha-blended
		// one-pixel draw (hw_postprocess.cpp, PPCameraExposure::Render), so it
		// is a per-FRAME lerp factor between 0 and 1 and the engine's own
		// default is 0.05. Above 1.0 the destination factor 1-src goes
		// NEGATIVE and the accumulator stops converging on anything; it is not
		// a slow eye, it is an unstable one. Low Power's 0.6 and Red Alert's
		// 3.0 read as three seconds and half a second and are neither, which
		// is why this is spelled out here rather than copied from them.
		//
		// 0.02 WAS RIGHT ARITHMETIC AGAINST THE WRONG REFERENCE. It was picked
		// as "roughly a second at sixty frames", and 1/(0.02 x 60) is indeed
		// 0.83 s -- but Exposure()'s own derivation, and every other call site
		// in this file, reckons the time constant at the tic rate of 35, where
		// 0.02 is 1.4 s. Two conventions in one file is how a number stops
		// meaning anything.
		//
		// 0.03 IS 1/(0.03 x 35) = 1.0 SECOND on the house convention, which is
		// the specification this block already stated: a second is the value at
		// which nobody notices. Worth saying once and not repeating: because
		// the blend is per FRAME, there is no value that is one second on every
		// machine -- 0.03 is 1.0 s at 35 fps and 0.55 s at 60. The convention
		// is the tic rate, and the fastest this preset's eye can be on any
		// hardware is still slower than the scan crossing you.
		//
		// BASE 1.0 IS WHAT ACTUALLY PROTECTS THE DARKNESS, and not min. The
		// pass computes 1 / max(base + light*scale, min), so the adjustment
		// can only exceed 1 when base + light*scale drops below 1 -- at base
		// 1.0 with scale 1.0 it never does, and the auto-exposure is
		// therefore incapable of lifting this room at all. It can only pull a
		// bright one down.
		//
		// Which makes min INERT here, and it is left at the engine's own 0.35
		// for exactly that reason: min is the floor on that denominator, so a
		// LOW min permits more lift, not less, and every preset in this file
		// that argued the opposite argued it backwards. Nothing is asked of
		// it, so nothing is claimed for it.
		Exposure(1.0, 0.35, 1.0, 0.03);
	}

	// =====================================================================
	// 6. NEON UNISON -- a room somebody lit on purpose
	//
	// WHAT IT IS, AND WHAT YOU SEE IN ONE FRAME. A cool room with warm light
	// travelling through it. The architecture -- ceiling, walls, floor, the
	// air itself -- sits in one cool family, cyan through violet, and
	// everything that MOVES across it is amber. Those two families are
	// complements. Standing still, before anything has had time to happen,
	// the room reads as composed: teal and orange, the oldest deliberate
	// colour scheme there is, applied by someone who chose it.
	//
	// THAT IS THE AXIS AGAINST ITS SISTER, and it is the only one that
	// survives a still frame. Neon Chaos is a room full of cheap party lights
	// that were never coordinated. This one is a room lit by a designer with a
	// key light, two fills and an accent, on one circuit. Tempo is what the
	// two presets used to be sorted by, and tempo is a thirty-second read that
	// nobody was ever going to make. Colour relationship is a two-second one.
	//
	// THE HIERARCHY, WHICH IS THE OTHER HALF OF "DESIGNED".
	//
	//   ceiling      KEY      coverage 208, intensity 1.70 -- the source
	//   wall bottom  FILL     144 / 1.20 -- the light standing on the floor
	//   wall top     FILL     120 / 0.95 -- further from the source, dimmer
	//   floor        ACCENT    72 / 1.85 -- narrow, hot, a strip
	//
	// No lighting designer has ever lit a room with four surfaces at equal
	// weight, and this preset used to: one coverage and one intensity written
	// four times over, on the argument that identical lanes make a corner read
	// as one body of light. That argument produced a WASH, which is the exact
	// word this preset's own header used for the thing it must not be. Unison
	// is a claim about TIME -- everything strikes on the same tic -- and it
	// costs nothing to make the four strike at four deliberate weights. Equal
	// weights are not unison, they are an absence of decision.
	//
	// THE BEAT IS 140 TICS. It is the mechanism, not the thesis:
	//
	//   140 tics          =  4.000 s   one slot, one band, one bar line
	//   127 tics hold  + 13 tics of phase clock at speed 0.080 = 140
	//   8 slots x 140    = 32.00 s     one bar
	//   4096 / 128       = 32.00 s     one sweep revolution -- the same bar
	//   gap 140 x 7      = seven beats, so band 8 leaves one beat before
	//                      band 1 comes round again and the bar closes
	//
	// Change any one of those and the others have to move with it. It is what
	// makes the room feel like one organism rather than eight systems, and it
	// is invisible in a still frame, which is why it is no longer the pitch.
	//
	// WHERE THE COOL FAMILY COMES FROM. Params(6) is baseHue 180, spread 140,
	// and SlotColor hands each lane its own quarter -- lanes at 180, 215, 250
	// and 285, cyan through violet, walking about thirty degrees across their
	// eight slots. So the four surfaces are four neighbours of one family
	// rather than four arbitrary colours, and the fog takes lane 0 on top of
	// that. Nothing in this function fights it; everything this function owns
	// outright -- the eight sweep bands, the lattice, the torch -- goes warm,
	// and that is where the complement comes from. It needs no Params change.
	//
	// WHAT IT REFUSES, AND WHY THAT IS STILL MOST OF THE DESIGN. Every system
	// in this mod that keeps its OWN time is off: reactive fog, tendrils, the
	// tornado, density banks, the heatmap, glow texture, floor shapes,
	// particles, band drift, fill flicker. Not because they look bad -- Low
	// Power's tendrils are the best thing in that preset -- but because each
	// introduces a second tempo, and a second tempo is the one thing that
	// cannot survive here. The refusals below are longer than the selections
	// and they should be.
	// =====================================================================
	clearscope static void NeonUnison()
	{
		// ---- the four voices, at four weights ----------------------------
		//
		// SNAP. At a four second beat a crossfade means the colour is in
		// transit for a tenth of the bar, and a beat you cannot locate to the
		// tic is not a beat. The cut IS the downbeat.
		//
		// Speed 0.080 is not a taste decision either. Under Snap the fade is
		// never drawn, but the phase clock is still what advances the slot,
		// and at 0.080 that costs 13 tics on top of every hold. 127 + 13 is
		// 140, and 140 is the beat. At the shipped default of 0.004 it would
		// cost 250 tics and a four second beat would run at eleven.
		LanesI("_enabled", 1);
		LanesI("_pattern", 0);        // Snap
		LanesI("_anim", 0);           // per-sector pulse OFF: it is a second
		                              // clock, running per room, and this
		                              // preset has exactly one clock
		LanesI("_slots", 8);
		LanesI("_falloff", 1);        // Smooth on all four -- a defined band
		                              // with a shoulder. The WEIGHTS differ
		                              // below; the CURVE must not, or the four
		                              // stop reading as one scheme and start
		                              // reading as four fittings from four
		                              // suppliers, which is the sister preset
		Lanes("_saturation", 1.00);   // hot, all four, no exceptions
		Lanes("_speed", 0.080);

		// KEY, TWO FILLS AND AN ACCENT. Four numbers a lighting plan would
		// carry, and the reason this preset now reads as lit rather than as
		// switched on.
		//
		// The ceiling is the key because that is where a room's light comes
		// from and because it is the surface you cannot avoid seeing. 208 is
		// well past the shipped 128: it is meant to reach across the room and
		// be the thing everything else is measured against.
		//
		// The two walls are fills at 144 and 120, and wall TOP is the dimmer
		// of the two on purpose -- it is the surface furthest from the floor
		// the light is bouncing off, and a fill that outshines the surface it
		// is filling is not a fill.
		//
		// The floor is the accent: 72 units of reach, the narrowest thing in
		// the preset, at the highest intensity in it. Narrow and hot is a
		// STRIP -- a bright seam along the base of the walls rather than a lit
		// floor -- and an accent is supposed to be the brightest thing in the
		// room and the smallest. It is also Params(6)'s violet-magenta lane,
		// the far end of the cool family, so the hottest thing in the room is
		// also the furthest from the fog's cyan. That contrast is deliberate.
		I("gitd_cg_coverage", 208); F("gitd_cg_intensity", 1.70);   // KEY
		I("gitd_wb_coverage", 144); F("gitd_wb_intensity", 1.20);   // fill
		I("gitd_wt_coverage", 120); F("gitd_wt_intensity", 0.95);   // fill
		I("gitd_fg_coverage",  72); F("gitd_fg_intensity", 1.85);   // ACCENT

		// AND THE SWITCH THAT FLATTENS THE HIERARCHY BACK TO A WASH.
		//
		// gitd_pc_shape lives on the colour customiser page and does not stay
		// in the colour half: GlowHandler.zs:2200 gates it on `preset > 0`,
		// not on WHICH preset, so with it set all four coverages become
		// gitd_pc_coverage and all four intensities gitd_pc_intensity. The
		// eight numbers above are read, discarded and replaced by two.
		//
		// This preset used to leave it alone, and the note explaining why was
		// honest at the time: no lane difference was load-bearing, so
		// overruling a player's explicit customisation of this preset would
		// have been a worse fault than the one it fixed. That is no longer
		// true. The lane difference IS the design now, and flattening it is
		// not a degraded Unison, it is the wash this preset exists to refuse.
		// Cold War, Chaos and Lovecraft all force it off for the same reason.
		B("gitd_pc_shape", false);

		// BLEED OFF, and this is the line that protects the cool FAMILY
		// rather than the beat.
		//
		// Bleed is on by default and no preset in this file has ever said a
		// word about it, which is survivable for the other four because their
		// four lanes are near neighbours already -- Low Power's are eight
		// shades of the same dying sodium, and averaging them changes nothing
		// you could point at. This preset is the case where it bites:
		// BleedToward pulls each lane 35% toward the MEAN of its two
		// neighbours (GlowHandler.zs:890), and the four lanes here are four
		// deliberately separated hues, 35 degrees apart out of Params(6)'s
		// 140. Bled, cyan and violet both walk a third of the way to the blue
		// between them, and a designed spread closes into one colour.
		//
		// The cost is real and it is worth naming: a corner where two lanes
		// meet is now two colours meeting rather than one blend. Seamless
		// would have answered that and the wave has already taken it (below).
		// So the corners are hard here. Four related colours with hard edges
		// is a scheme; one soft average of them is a puddle.
		LanesI("_bleed", 0);

		// 3.63 s is 127 tics. Written to all thirty-two slots, which is the
		// single most load-bearing line in the function: Hold() rather than
		// four HoldFor() rows is what makes the four surfaces strike together.
		Hold(3.63);

		// ---- THE ONE THING THAT CAN DELETE THIS PRESET SILENTLY -----------
		//
		// gitd_rnd_times replaces every _holdN with frandom(0, 6) seconds on
		// arrival. Not once -- on arrival, every map, and it is read in
		// GITD_Lane.Step with no preset gate at all (GlowHandler.zs:280). A
		// preset whose whole argument is thirty-two identical holds, applied
		// with that switch left on by somebody's earlier session, is
		// thirty-two different random holds and reads as its own sister.
		//
		// gitd_rnd_patterns is the same door one step narrower: also read in
		// Step, also ungated, and it overrides the Snap this preset argued for
		// with a per-map hash offset by lane index -- four lanes crossfading
		// on four different transitions, which is the one thing Snap was
		// bought to prevent.
		//
		// gitd_rnd_colors CANNOT reach a preset and is written anyway. Every
		// path that reads it is inside GITD_Lane.SlotColor, and Step only
		// calls that when preset <= 0 -- under a preset the colours come from
		// GITD_Presets.SlotColor and the lane's own _random is on the same
		// dead branch. It is stated because the discipline is to state a
		// position, not because it can bite; saying so here is cheaper than
		// the next author re-deriving it. If that branch is ever fixed, this
		// line starts doing real work and needs no edit.
		B("gitd_rnd_times", false);
		B("gitd_rnd_colors", false);
		B("gitd_rnd_patterns", false);

		// ---- THE PULSE ITSELF ---------------------------------------------
		//
		// The wave is the metronome made visible, and every parameter here is
		// chosen against the tic table at the top.
		//
		// SPEED 1.5708 IS 2*pi/4. One full cycle every four seconds -- the
		// same four seconds as one slot -- so the swell peaks on the beat the
		// lanes cut on. That is the whole reason this preset has a wave.
		//
		// DETUNE ZERO AND SEED ZERO, and both are the opposite of what every
		// other preset here wants. Detune is a second sine that stops the
		// period ever resolving; Low Power turns it to 0.75 precisely so you
		// cannot count it. Counting it is the point here. Seed 0 is the
		// bigger one: it takes away the per-room scatter, so every room in
		// the map is at the SAME phase and the whole level swells as one
		// object. A building on one circuit does not stagger by room.
		//
		// CLIMB 0 for the same reason and a different mechanism: no phase
		// step between the four surfaces, so floor, walls and ceiling peak
		// on the same tic. Red Alert uses 90 to make the throb travel upward
		// like a turning beacon; travel is exactly what this must not have.
		//
		// COLOUR SLIDE ZERO. It would put a second hue on one surface at a
		// distance, which is a fifth colour nobody chose in a preset whose
		// entire claim is that all of them were chosen.
		//
		// Long wavelength -- 640 units is most of a room, so a room is mostly
		// in one phase rather than showing three crests at once. Sharp 2.0 is
		// a defined attack without being a spike; a spike is an alarm.
		Wave(640.0, 1.5708, 2.0, 1,   // ring: it comes from one place
		     0.25,                    // the edge moves a little
		     0.55,                    // the light moves more -- this is a
		                              // BEAT, and a beat is loudness
		     0.0,                     // no colour slide: the scheme holds
		     0.0,                     // it MUST repeat exactly
		     0.0,                     // and every room on the same phase
		     0);
		I("gitd_wave_origin", 0);     // map centre. Origin 2 follows you, and
		                              // a building's clock is not centred on
		                              // the player

		// Wave() forces gitd_seamless off, and that is a real cost here: this
		// is the preset that would most like its corners to ramp rather than
		// meet. The two are exclusive in GITD_Render.PushWave, the beat is
		// worth more than the join, and identical FALLOFF on all four lanes
		// above is the consolation. Not restated below -- Wave owns it.

		// ---- the floor it stands on ---------------------------------------
		//
		// Compress rather than Crush, and Dismal rather than Stygian. This is
		// the brightest preset in the file and it still has to be dark enough
		// that neon is the only light -- but Crush at Stygian flattens the
		// gap between the key and the fills, and that gap is now the design.
		// Compress keeps proportion, so a 1.70 ceiling stays measurably
		// brighter than a 0.95 wall top instead of both pinning to the same
		// crushed value.
		//
		// DESAT ZERO, said out loud. Every other preset here drains something.
		// A preset whose whole pitch is a colour relationship, inheriting
		// Black and White's 255, is a grey room -- and the bug would look like
		// the palette rather than like the drain.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 2);        // Compress
		I("ddz_preset", 3);      // Dismal
		I("ddz_desat", 0);
		I("ddz_minlight", 0);
		F("ddz_skymode", 1.0);
		B("ddz_lighting", true); // vanilla's blink and strobe thinkers stay.
		                         // Blackout destroys them because they shove a
		                         // crushed room back to full brightness; under
		                         // Compress they survive as what they are, and
		                         // a map's own flashing sectors are the one
		                         // rhythm in the world that predates this one

		// PER PIXEL, and moderately. 0.55 over 2400 units is enough that the
		// far end of a hall is dim and a band arrives OUT of something --
		// depth for the sweep to come out of. Push it to Low Power's 0.86 and
		// the bands appear from nowhere mid-corridor, which reads as pop-in.
		//
		// NO HEIGHT POOLING. Dark gathering on the floor would swallow the
		// accent, and the accent is the brightest thing in the scheme.
		DeepDark(0.55, 2400.0, 0.0, 0.0, 256.0);

		// Nothing drains, so there is nothing to rescue from the drain.
		// Colour keep weights a desaturation that is set to zero eight lines
		// up; leaving it inherited from Black and White's 0.82 would do
		// nothing visible today and something baffling the moment anyone
		// touched the desat slider.
		NoKeepColor();

		// ---- the air, WHICH IS ON THE COOL SIDE ---------------------------
		//
		// THIN, AND IT CHANGES COLOUR ON THE BEAT.
		//
		// This is the cheapest way this mod has to make the air part of the
		// ensemble, and it costs one cvar: colour mode 1 takes the layer's
		// tint from a lane, so when that lane cuts, the air cuts with it. No
		// new system, no second clock -- the fog is simply another surface
		// wired to the same circuit, and it is one more member of the cool
		// family the warm bands are crossing.
		//
		// LANE 0, wall bottom, and the choice is physical before it is
		// compositional: wall bottom is the glow lit upward off the floor,
		// which is the light actually standing in this layer. It is also
		// Params(6)'s hue 180, the cyan end -- so the air is the COOLEST thing
		// in the room and the amber bands read against it hardest. Taking the
		// floor lane instead would put the violet-magenta accent in the air
		// and leave the cyan reading as the odd one out, which inverts the
		// scheme and throws away the complement.
		//
		// Density 0.6 and top 28: shin deep and barely there. A dense layer
		// would soften the leading edge of every band, and the leading edges
		// are the beats.
		//
		// AND THE WAKE IS NEARLY NOTHING. Every other preset opens a channel
		// behind you and lets it hang; Low Power drags one for several
		// seconds on purpose. 0.15 at lag 0.5 closes almost as fast as you
		// make it. The room is running a schedule and you are not on it --
		// a corridor-long hole cut by the player is the single most
		// off-clock thing the fog can do.
		Fog(28, 0.60, 16, 0x0E3038,
		    1.0,      // the torch carves it
		    0.90,     // and it takes its colour from the room, hard
		    0.15, 80, 0.5);
		I("gitd_fog_color_mode", 1);     // match a lane
		I("gitd_fog_color_lane", 0);     // wall bottom -- the cyan end
		F("gitd_fog_color_blend", 0.80); // most of the way, never all

		// THE THREE FOG CVARS Fog() DOES NOT TOUCH, and one of them is the
		// worst inheritance in this whole function.
		//
		// ROLL IS A SECOND CLOCK. It scrolls the entire layer sideways at a
		// fixed rate in units per second -- a tempo, in the one system this
		// preset went to the most trouble to wire INTO the beat. Anyone who
		// has ever nudged that slider leaves this preset with air that keeps
		// its own time while changing colour on somebody else's. Zero, said
		// out loud, and it is the reason this block exists.
		//
		// PERIOD 0 is one layer. Non-zero repeats the layer up the room at
		// that spacing, which turns shin-deep mist into a stack of shelves and
		// puts three of them between you and every band.
		//
		// BOTTOM back to the sentinel. -32768 is "no bottom", and it is the
		// declared default precisely because that is what a ground layer
		// means; it is also outside its own slider range, so a designer who
		// moved that slider once cannot get back here from the menu at all.
		// A real bottom would make this a floating slab with a lit underside.
		F("gitd_fog_roll", 0.0);
		F("gitd_fog_period", 0.0);
		F("gitd_fog_bottom", -32768.0);

		// A little sag, not a lot. Level would be the graphic answer and
		// Black and White has already made that argument for a preset made of
		// flat compositions. This one is architectural: the layer should know
		// the building is there without climbing its stairs.
		Follow(0.2, 0.0);

		// A SURFACE THAT REPEATS, which is the inverse of every other use of
		// this helper. Cross swell is what makes two waves interfere and
		// never resolve -- Low Power runs 0.65, Black and White 0.7, because
		// a surface you can predict looks like a texture. 0.25 here lets it
		// very nearly repeat, so the top of the layer keeps time too.
		// Wavelength 48 is a visible period of about 300 units, one room.
		Surface(2.5, 48.0, 0.50, 0.25);

		// ---- and now the refusals, which are the other half of it ---------
		//
		// DENSITY BANKS OFF. Uneven air is a composition -- it puts weight in
		// one corner and lifts another -- and it does it on a drift clock of
		// its own that agrees with nothing. Even air is what lets eight
		// identical bands read as eight identical bands.
		FogBanks(0.0, 0.004, 0.0);

		// TENDRILS OFF. Wisps rise on their own schedule. They are the best
		// thing in Low Power and they would be a crowd of soloists here.
		NoTendrils();

		// NOTHING REACTS, and this is the preset's temperament rather than a
		// performance saving. Reactive fog is the room ANSWERING you: a ring
		// off every shot, mist recoiling from a death. This room is not
		// listening. It was keeping this time before you arrived and it will
		// keep it after. That indifference is most of why unison is unnerving
		// rather than merely pretty.
		//
		// NoReactive() also zeroes displace and wake stretch, so the two
		// remaining ways the player could dent the air are covered here.
		NoReactive();

		// NO BOW WAVE, and this is the only preset with eight travelling
		// bands that could plausibly want one. A bow wave is a band shoving
		// the air in front of it, which is Red Alert's argument -- the alarm
		// does not merely light the room, it pushes it. Here the bands are
		// metronome ticks, and a tick that displaces the atmosphere is a tick
		// with mass. Zeroed rather than left, because Red Alert sets 0.7 and
		// this preset would inherit it.
		Bow(0.0, 64.0, 0.6);

		// ONE COLOUR THROUGH THE LAYER. Mix 0 is the position, not an
		// oversight: the air is whatever wall bottom currently is, top to
		// bottom, so it changes as one thing on the beat. A gradient through
		// its thickness is a fifth hue nobody picked, in the preset whose
		// pitch is that every hue in it was picked, and Black and White leaves
		// 0.30 behind.
		FogGradient(0x123A4A, 0.0);

		// A funnel is a soloist. It stands in one place turning at its own
		// rate and takes the eye off everything that is keeping time.
		NoTornado();

		// ---- THE LATTICE, USED AS A RULER ---------------------------------
		//
		// Both Neon presets now draw this lattice and they draw OPPOSITE
		// statements with it, which makes it the sharpest two-second
		// separator in the pair. Here it is MEASURED: ruled diamonds, every
		// fourth line bolder, nothing drifting, nothing missing, painted on
		// the surfaces. In Chaos it is squares with the spacing knocked out of
		// true, sliding, and hanging in the air. Same eleven cvars, same
		// system, and you can tell which room you are in from one frame.
		//
		// Rotate 45 turns squares into diamonds, gap 0 lights only the lines
		// so you see the surface between them, and spacing 96 is about two
		// paces -- ruled widely enough that a wall reads as marked rather than
		// as fenced off.
		//
		// AND EVERY FOURTH LINE IS BOLDER. fill_major 4 is what makes this a
		// ruler rather than a mesh. It is not counting the beat -- it cannot,
		// it is spacing in world units and the beat is tics, and drift is
		// zeroed below precisely so the two never pretend to be coupled. What
		// it does is rhyme: a player who never works out that the room is on a
		// clock still sees, inside the band that arrives on that clock, a
		// thing that has been MEASURED rather than a thing that is merely
		// dense. Same argument, different axis.
		//
		// THE COLOUR IS WARM, and that is the change. It used to be 0x8CFDFF,
		// the same cyan as lane 0 -- so the ruler was invisible against the
		// wall it was ruling and the one piece of structure in the preset read
		// as more wall. 0xFFD08A puts it on the warm side with the bands it
		// lives inside, so the lattice belongs to the LIGHT rather than to the
		// architecture. That is also what a real gobo does: it is a property
		// of the lamp, not of the surface.
		//
		// AIR STRENGTH ZERO, AND IT IS NOT A TASTE DECISION. SweepAirLattice
		// solves a ray against a plane and cases shapes 2, 3 and 5, then
		// `else continue` -- ring and shell need a quadratic nobody wrote.
		// Every band here is shape 1. Any air value would therefore be a
		// number on this preset's Customise page that reads as doing something
		// and does nothing, which is the fault this file exists to not ship.
		// Chaos's bands are shapes 1, 2, 3 and 5, which is why the air lattice
		// belongs to that preset and can never belong to this one.
		//
		// The painted lattice is what draws, and for a ring it is drawn in arc
		// length and height -- constant spacing in world units as the ring
		// grows, so 96 stays about two paces however far out the band is.
		Grid(96.0, 2.5, 0.9, 0xFFD08A, 45.0, 0.0);
		F("gitd_ss_fill_major", 4.0);
		F("gitd_ss_fill_major_boost", 2.2);

		// The four dials that would make the lattice lie. Drift slides the
		// pattern along the band at its own rate; jitter breaks it into
		// emitters; flicker drops individual lines out; the gradient fades it
		// along one axis so the far half of a bar line is not the same weight
		// as the near half. All four are ways of saying "this is not a
		// measured thing", which is the one statement the lattice is here to
		// contradict -- and all four are exactly what Chaos turns UP. Grid()
		// touches none of them and they persist from whatever anyone rolled
		// last, so with the pair now sharing this system, stating them is what
		// stops Unison's ruler arriving pre-broken. Grad axis is left alone
		// deliberately: the shader reads it only inside `if (grad > 0)`, so
		// zeroing the amount already answers it and a second write would be
		// noise.
		F("gitd_ss_fill_drift", 0.0);
		F("gitd_ss_fill_jitter", 0.0);
		F("gitd_ss_fill_flicker", 0.0);
		F("gitd_ss_fill_grad", 0.0);

		// ---- the torch, ON THE SAME CLOCK AND ON THE WARM SIDE ------------
		//
		// The most literal reading of the brief and the one that took the
		// most restraint. Every light in the building is on one clock -- and
		// the torch in your hand is a light in the building.
		//
		// So it runs eight slots at the same 3.63 second hold and the same
		// 0.080 phase speed as the four lanes, and it cuts on the same tic
		// they do. What it does NOT do is change colour, because a torch that
		// changes colour is a torch you cannot read a room with, and this
		// mod's darkness makes reading the room the torch's actual job.
		//
		// THE EIGHT ARE WARM NEAR-WHITES NOW, a few percent off neutral,
		// walking out to the warmest at slot 4 and back to nearly neutral at
		// slot 8 -- the same arch the eight bands walk, one octave quieter.
		// They used to be COOL near-whites tracking the lanes, which put the
		// only light you control on the same side as the architecture and left
		// the warm family belonging entirely to things you cannot touch.
		// Warm puts the light in your hand on the ACCENT side of the scheme:
		// what you point at goes momentarily amber against a cool room, which
		// is the whole preset restated in the one system the player operates.
		// You will not name the colour. You will notice that the beam belongs.
		//
		// Beam wide-ish and dust modest: this is a lit room, not Low Power's
		// dead one, and heavy dust in air that is already carrying a lattice
		// is two textures fighting.
		B("fl_enabled", true);
		I("fl_range", 1400);
		F("fl_intensity", 1.15);
		F("fl_inner", 8.0);
		F("fl_outer", 22.0);
		F("fl_falloff", 1.4);
		F("fl_density", 1.2);
		F("fl_dust", 0.30);
		F("fl_dust_scale", 0.05);
		F("fl_dust_drift", 0.10);
		B("fl_bounce", false);      // a torch is a cone, not a lantern
		I("fl_slots", 8);
		I("fl_pattern", 0);         // Snap, with everything else
		B("fl_random", false);      // random would be the one light in the
		                            // building off the schedule, and it is the
		                            // one thing Chaos gives its torch
		B("fl_agitate", false);     // pointing the light at a monster does not
		                            // wake it. This room does not notice you
		                            // and the torch is part of this room --
		                            // Blackout owns that switch, where the
		                            // torch is the only way to see anything
		                            // and making it dangerous means something
		F("fl_speed", 0.080);
		I("fl_c1", 0xFFF6E8); I("fl_c2", 0xFFF0DC);
		I("fl_c3", 0xFFEAD0); I("fl_c4", 0xFFE4C4);
		I("fl_c5", 0xFFE8CE); I("fl_c6", 0xFFEEDA);
		I("fl_c7", 0xFFF4E6); I("fl_c8", 0xFFF8EE);
		for (int i = 1; i <= 8; i++) F("fl_hold" .. i, 3.63);

		// ---- THE BAR, AND IT IS THE WARM HALF OF THE SCHEME ---------------
		//
		// Eight bands, one per beat, all at the same speed, evenly spaced,
		// forever. Nothing overtakes, nothing stretches apart, nothing
		// arrives early. Low Power's four bands each run slower than the last
		// so the failure drags; that is the same machinery saying the exact
		// opposite thing.
		//
		//   range 4096 / speed 128   = 32.0 s, one revolution
		//   gap 140 tics             = 4.0 s, one beat, seven times
		//   band 8 leaves at 28 s, band 1 comes round at 32 s
		//
		// Rings from the map centre, outward only. Direction 2 (out and back)
		// would make alternate beats arrive backwards, and a metronome that
		// alternates direction is a pendulum -- which is a different and much
		// weaker idea, because you stop being able to tell beat 3 from beat 5.
		//
		// Softness 1.6 is crisp. A tick needs an edge; Low Power's 3.2 is a
		// wave of power arriving, and that is weather.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 8);
		I("gitd_ss_shape", 1);
		I("gitd_ss_origin", 0);       // the map centre, which does not move.
		                              // Origin 2 follows you and the whole
		                              // premise is a clock you do not own
		I("gitd_ss_direction", 0);
		I("gitd_ss_trigger", 0);      // free-running. Trigger 1 fires on
		                              // kills, and a beat you cause is not a
		                              // beat, it is a response
		I("gitd_ss_drive", 0);        // time, not kills and not your health
		I("gitd_ss_range", 4096);
		F("gitd_ss_softness", 1.6);
		F("gitd_ss_intensity", 1.30);
		I("gitd_ss_thickness", 110);  // the shared value; every band states
		                              // its own below, so this is what the
		                              // menu reads rather than what draws
		I("gitd_ss_trail", 60);       // a short decay behind each tick, the
		                              // way a struck note has a tail
		B("gitd_ss_underlay", true);  // the lanes keep running underneath.
		                              // Off calls ClearAll() and the whole
		                              // cool half of the scheme goes with it
		F("gitd_ss_drift", 0.0);      // DRIFT IS THE LITERAL ENEMY HERE. It
		                              // spreads the per-band speeds apart,
		                              // which is the one edit that would turn
		                              // this preset into its sister
		F("gitd_ss_health_speed", 0.0); // the tempo does not follow your health
		F("gitd_ss_spin", 0.0);         // NO RIG. A swung origin rakes the room
		F("gitd_ss_spin_radius", 0.0);  // from a moving centre, which is a
		                                // lighting RIG and is exactly what
		                                // Chaos now owns. Eight bands leaving
		                                // one fixed place is a building's
		                                // installation; four leaving a turning
		                                // one is a hired-in truss
		I("gitd_ss_spin_colors", 0);  // and above 1 the rolodex OVERRIDES all
		                              // eight band colours by spin phase,
		                              // which would delete the warm half of
		                              // the scheme in one cvar
		B("gitd_ss_drop", false);
		B("gitd_ss_actors", false);

		// PER PIXEL ONLY. The per-sector light channel is the coarse path --
		// it arrives a room at a time, and a beat that lands on your room a
		// quarter second after the room next door is not unison, it is lag.
		// perband off as well, so the fx table is never read and cannot
		// contribute a stray sonar or a monster effect from whoever set it
		// last; light_mode zeroed for the same reason.
		B("gitd_ss_light", false);
		B("gitd_ss_perband", false);
		I("gitd_ss_light_mode", 0);

		for (int i = 1; i <= 7; i++) I("gitd_ss_gap" .. i, 140);
		for (int i = 1; i <= 8; i++) F("gitd_ss_speed" .. i, 128.0);
		for (int i = 1; i <= 8; i++) I("gitd_ss_shape" .. i, 1);

		// THE DOWNBEAT IS WIDE AND THE REST ARE TICKS.
		//
		// A band is twice its thickness wide, so at 128 units a second the
		// 110s take about 1.7 s to cross you and band 1 takes about 4 -- it
		// is still passing when beat 2 launches. That overlap is what makes
		// the bar feel sustained underneath rather than pecked out.
		//
		// AND BAND 5 IS 150 RATHER THAN 110, which is the rest being made
		// legible. 110 crosses you in 1.7 s; a 1.7 s absence inside a 4 s beat
		// is short enough to read as the lights glitching. 150 is 2.3 s, over
		// half the beat, which is long enough that you register it as a thing
		// that was SUPPOSED to happen. It is still well under band 1's 260,
		// because a rest that outweighs the downbeat is not a rest, it is the
		// bar being about the darkness.
		I("gitd_ss_thick1", 260);
		I("gitd_ss_thick2", 110); I("gitd_ss_thick3", 110);
		I("gitd_ss_thick4", 110); I("gitd_ss_thick5", 150);
		I("gitd_ss_thick6", 110); I("gitd_ss_thick7", 110);
		I("gitd_ss_thick8", 110);

		// AND BEAT 5 IS A HOLE.
		//
		// Draw mode 3 crushes the finished pixel instead of adding to it, so
		// on the fifth beat of every bar a front of darkness crosses the room
		// in the same place the light did. It is the only band that is not
		// light, and it is the reason the other seven read as beats: eight
		// equal flashes at four second spacing is a strobe you stop hearing
		// after a bar. Take one out and the bar has a shape.
		//
		// Halfway is deliberate. Earlier and the bar limps; later and it
		// reads as the cycle ending rather than as a rest inside it.
		I("gitd_ss_draw1", 1); I("gitd_ss_draw2", 1);
		I("gitd_ss_draw3", 1); I("gitd_ss_draw4", 1);
		I("gitd_ss_draw5", 3);
		I("gitd_ss_draw6", 1); I("gitd_ss_draw7", 1);
		I("gitd_ss_draw8", 1);

		// ---- AND HERE IS THE COMPLEMENT ----------------------------------
		//
		// The bands used to walk the same cyan-to-magenta arc as the lanes --
		// 0xB6FBFF, 0x2FE6FF, 0x2FA8FF, 0x5A78FF, 0xA355FF, 0xE23CFF,
		// 0xFF3AC8. That was wrong twice. A band arriving on a wall was
		// within a few degrees of the colour of the wall, so eight events an
		// eye could not separate from the surface they crossed; and the whole
		// preset was then ONE hue family, which is not a scheme, it is a
		// filter. What a lighting designer does with a cool room is put warm
		// light through it, because complements are the one pair of colours
		// that make each other louder rather than averaging.
		//
		// So the eight are amber, and they are an ARCH rather than a walk:
		// near-white on the downbeat, down through gold to the deepest orange
		// at beat 4, the rest at beat 5, and back up through amber to warm
		// cream at beat 8 -- which hands off to beat 1 with no jump, so the
		// bar closes on colour as well as on time. A walk would have band 8
		// and band 1 as far apart as the arc is wide, and you would hear the
		// seam once a bar.
		//
		// Band 1 is near white because a downbeat is LOUDER, not different.
		// Band 5 crushes and ignores its rgb entirely, but keeps a truthful
		// near-black swatch so the menu shows what it is rather than a
		// leftover -- and it is the one band left at its old value, because a
		// hole has no colour to warm.
		I("gitd_ss_c1", 0xFFF2D8);   // the downbeat
		I("gitd_ss_c2", 0xFFC24A);
		I("gitd_ss_c3", 0xFFA020);
		I("gitd_ss_c4", 0xFF7A12);   // the far point of the arch
		I("gitd_ss_c5", 0x07131C);   // the rest
		I("gitd_ss_c6", 0xFF8C1E);
		I("gitd_ss_c7", 0xFFB43A);
		I("gitd_ss_c8", 0xFFD86E);   // and back, to hand off to band 1

		// ---- the systems with no helper, refused by hand ------------------
		//
		// THE GLOW TEXTURE TERMS. Five cvars, no helper in this file, and
		// every one is a texture sampled in world space on its own rate:
		// veining that crawls, a current running along a surface, a cell
		// network, rings off gunfire, a global alarm swell. Five separate
		// tempos laid over a preset that has exactly one, and five separate
		// textures laid over a scheme whose whole argument is that the
		// surfaces are flat fields of chosen colour.
		//
		// Cold War owns the first three and Red Alert owns gitd_greact, so
		// these zeroes are now live protection rather than hygiene: leaving
		// Cold War for this preset would otherwise carry a mains shimmer onto
		// every surface here. gitd_gpulse is the one that would hurt most,
		// because it is a pulse and this preset already has a pulse -- a
		// second one, driven by how many monsters are near you, reads as the
		// building's clock stuttering.
		F("gitd_gtex_noise", 0.0);
		F("gitd_gflow", 0.0);
		F("gitd_gcell", 0.0);
		F("gitd_greact", 0.0);
		F("gitd_gpulse", 0.0);

		// SHAPES ON THE FLOOR OFF. Marks stamped where things died, each
		// fading on its own life timer. That is a record of the fight, which
		// is a clock the player writes; the heatmap below is refused for the
		// same reason and the two would have been refused together if they
		// shared a helper.
		B("gitd_shape_enabled", false);

		// THE NUMBERS IN THE WORLD, OFF. gitd_neon_enabled ships TRUE, so
		// this is an inheritance that arrives switched on rather than one that
		// has to be turned on -- and the payloads under it (killcount, damage)
		// default off, so it only fires for a player who went and enabled one.
		// That is exactly the player who then cannot work out where the
		// floating figures came from. They are unowned colour with a font on
		// it, in a room where every colour was chosen. Black and White is the
		// one preset that takes this system, and takes it deliberately.
		B("gitd_neon_enabled", false);

		// THE FLOOR DOES NOT KEEP SCORE. Blackout, Red Alert and Black and
		// White all take the heatmap and all three are right: a room that
		// remembers is a room with a history. This one has no history. It is
		// a machine running a loop, identical on your first pass and your
		// fifth, and a stain in the corner is the map admitting that time
		// passed -- and it is a colour nobody in this scheme chose.
		NoHeat();

		// THE COLOUR LAW STAYS OFF. It is the one system that would make the
		// unison literal -- the conductor lane's slot becoming a game phase,
		// monsters tougher on beat 3 -- and it is genuinely tempting. It is
		// refused because a look should not silently change the fight. A
		// player choosing a lighting preset from a lighting menu has not
		// asked for a difficulty modifier, and if they want one it is two
		// rows away on its own page.
		B("gitd_law_enabled", false);

		// LIGHTS ON EVERYWHERE, PARTICLES OFF, and the split is the preset in
		// one line. Detail 2 lights every fixture the scan can find, which is
		// the literal claim in the name: every light in the building. But
		// FancyWorld's particles drift on their own emitter timers, and a
		// room full of embers wandering across a beat is the exact soup this
		// is trying not to be.
		Ambience(2, 0.90, 0.0);

		// AND THE EMITTER RADIUS, STATED AT THE SHIPPED VALUE. NoAmbienceLight
		// says out loud that a preset wanting silence has to say so with the
		// range, and no preset in this file ever has -- so FancyWorld's ambient
		// sound has been identical under all eight, whatever each of them
		// argued. This one wants it exactly where it ships: a building running
		// one circuit throughout should sound like one building, carrying from
		// room to room, which is the audio restatement of the whole preset.
		// Cold War halves it because its rooms are sealed; Black and White
		// extends it because hearing carries more there. Here 2048 is a
		// choice that happens to match the default.
		F("fw_range", 2048.0);

		// FOOTSTEPS DOWN, which is the only preset here that turns them down.
		// Blackout runs 1.25 because in the dark your feet are the map. Here
		// they are a second tempo -- an irregular one, set by how you walk --
		// laid directly over a four second beat. 0.8 keeps them present
		// enough to place you and quiet enough not to argue.
		Steps(0.8);

		// And sound carries between rooms. 0.6 is most of the way open, short
		// of Red Alert's 0.75, which was an alarm's job.
		Occlude(0.6);

		// NOTE FOR WHOEVER EDITS THIS NEXT. Preset 6 is a GENERATED palette,
		// not a literal table -- SlotColor special-cases 1, 2, 3 and 11 and
		// falls through to the gitd_pc_* working set for this one. So the four
		// cool hues come from Params(6) via LoadWorkingSet, and writing
		// gitd_wb_c3 here would be dead weight while preset 6 is selected.
		//
		// WHICH MEANS HALF THE SCHEME LIVES IN A FILE THIS ONE DOES NOT OWN,
		// and it is worth being precise about which half. The COOL family is
		// Params(6)'s -- baseHue 180, spread 140. The WARM family is entirely
		// here: eight band colours, the lattice, eight torch colours. The
		// complement therefore holds only while Params(6) stays in the blues.
		// Anyone moving that baseHue has to move all seventeen warm values
		// with it or the preset silently stops being about anything.
		//
		// And LoadWorkingSet reads gitd_p6_custom FIRST. A player who ever
		// pressed Save on this slot gets their own stored palette under these
		// warm bands, with every menu row reading correctly and no indication
		// why the room no longer agrees with itself. That is a fault in
		// GlowHandler and is recorded there.
	}

	// NEON WITHOUT BLOOM IS NOT NEON. It is a coloured stripe on a wall.
	// The bleed off the edge is what makes a tube read as a tube, so this is
	// the one engine half in the file that is doing something structural
	// rather than atmospheric.
	//
	// THRESHOLD IN THE MIDDLE, at 0.45. Low Power goes to 0.22 because there
	// is almost nothing bright enough to find; Blackout goes to 0.82 because
	// only the things you brought should bloom. Here the glow itself is well
	// past 0.45 and the crushed walls are nowhere near it, so the pass finds
	// the neon and nothing else -- which is what stops "bright preset" from
	// becoming "everything hazed".
	//
	// KNEE WIDE at 0.65, and it is the beat again. A tight knee crosses hard,
	// which is right for an alarm; here the brightness swings continuously
	// through the wave cycle, and a soft knee means the bloom SWELLS with it
	// rather than snapping on at a threshold. The lens breathes with the room.
	//
	// TINT WHITE, EXPLICITLY, AND THE REASON HAS CHANGED. It used to be "this
	// palette spans cyan to magenta and all four voices are equal, so tinting
	// picks one of them". The four voices are no longer equal -- there is a
	// key and an accent now -- but the preset has TWO families, cool surfaces
	// and warm light, and a tint votes for exactly one of them at the last
	// stage of the pipeline, where it cannot see which it is tinting. A warm
	// tint would fold the bands into the walls; a cool one would grey the
	// bands. White is the only setting that leaves the complement standing.
	//
	// AND THE CLEAN LENS IS NOW A STATED CONTRAST. Anamorphic and chromatic
	// are both zero here and Chaos takes the fringing, so the pair differ in
	// the optics as well as in the palette: a room that was composed is shot
	// through glass that agrees with itself. A streak has an AXIS and nothing
	// in a room lit from a key and an accent points one way; fringing is a
	// lens failing to resolve, which is the last thing a deliberate image
	// wants. Anamorphic is a bare gate in the engine -- any non-zero value is
	// fully on -- so 0.0 is the whole statement, and its RATIO is left
	// unwritten because a zero gate makes it unobservable and RestoreEngine
	// puts it back to the engine's 3.0 on the way out.
	clearscope static void NeonUnisonBloom()
	{
		Bloom(1.90, 0.45, 0.65, 1.0, 1.0, 1.0);
		EF("gl_bloom_anamorphic", 0.0);
		EF("gl_bloom_chromatic", 0.0);

		// THE EXPOSURE IS THE LAST VOICE, and it is the only one that can act
		// on the whole frame at once.
		//
		// SPEED 0.03 IS ROUGHLY ONE SECOND, and both halves of that sentence
		// have to be here because the number is not seconds. It is the source
		// alpha of a per-FRAME alpha blend, so the time constant is
		// 1 / (speed * 35) -- 0.03 gives 0.95 s, a quarter of the beat. The
		// lanes cut, the wave peaks, and the frame swells a beat-quarter
		// behind them and settles before the next cut. That lag is what turns
		// four synchronised systems into something that reads as BREATHING
		// rather than as flashing.
		//
		// This shipped as 1.6 with a comment claiming "roughly a second".
		// Above 1.0 the destination factor (1 - speed) goes NEGATIVE and the
		// meter oscillates instead of converging -- so the loudest preset in
		// the file, hard-cutting four surfaces on one beat under a low bloom
		// threshold, had an eye that never settled. Faster than 0.03 (Red
		// Alert's territory) and the eye keeps perfect pace, which cancels
		// the pulse instead of carrying it; slower (Low Power's ~3 s) and it
		// averages the bar into one brightness and the beat disappears.
		//
		// Min 0.35 -- the engine's own floor, above Low Power's, because this
		// room is meant to be legible and well under a value that would lift
		// the darkness the neon is being read against. Base 1.0 with scale
		// 1.0 means base + light*scale never drops below 1, so this exposure
		// is incapable of LIFTING the room at all; it can only pull a bright
		// one down. That is what actually protects the dark, not min.
		Exposure(1.00, 0.35, 1.0, 0.03);
	}

	// =====================================================================
	// 7. NEON CHAOS -- cheap party lights that nobody ever coordinated
	//
	// WHAT IT IS, AND WHAT YOU SEE IN ONE FRAME. A room somebody hired a rig
	// for and never dressed. Eight colours that were bought separately and do
	// not belong together, a truss turning slowly overhead throwing them
	// around, a floor grid with the spacing knocked out of true and lasers
	// hanging in the air above it, and a torch in your hand that picks its own
	// colour and will not tell you which. Nothing agrees with anything. It is
	// a disco, and a disco is not a design failure -- it is the one room where
	// refusing to choose is the correct answer.
	//
	// THAT IS THE AXIS AGAINST ITS SISTER. Neon Unison is a cool room crossed
	// by warm light, a key and two fills and an accent, chosen by somebody
	// with taste. This is the same hardware with nobody in charge. Both
	// presets used to argue that the axis was TEMPO -- one clock against five
	// mutually-prime clocks -- and that is a thirty-second read at minimum
	// which no player was ever going to make. Colour relationship is a
	// two-second one and it is visible in a still frame.
	//
	// THE FAILURE MODE HAS A NAME AND IT IS EPILEPSY. A preset called Chaos
	// invites exactly one mistake: getting the chaos from RATE. Turn every
	// clock up, let the lanes strobe, and what you have built is not
	// unpredictable, it is a hazard -- and it is also boring, because a room
	// changing five times a second reads as one texture rather than as a
	// sequence of rooms. So every individual clock in here is SLOW. The
	// shortest colour hold is seven seconds, the fastest undulation is one
	// every three and a quarter, and the rig overhead takes seventy-two
	// seconds to come round. NOTHING IN THIS FUNCTION BLINKS, and the one
	// place a party preset would obviously reach for a blink is refused by
	// name below with the reason spelled out.
	//
	// The chaos is not rate. It is that five slow clocks are mutually prime
	// and therefore never line up:
	//
	//   wall bottom   151 s of holds   snap        travels east/west
	//   wall top      157 s            fade        travels north/south
	//   ceiling       163 s            breathe     ripples from the centre
	//   floor         167 s            ping-pong   travels by height
	//   your torch    131 s            fade        a colour it rolls itself
	//
	// All five totals are prime, so the five come back into agreement about
	// once every two and a half thousand years of continuous play.
	//
	// AND THE COLOUR IS FREE, ON THE SURFACES. Params(7) gives slot 7 hue
	// spread 360, and SlotColor hands each lane its own QUARTER: wall bottom
	// in the reds, wall top in the yellow-greens, the ceiling in the cyans,
	// the floor in the violets, each walking about eighty degrees of its own
	// quarter across eight slots. The four surfaces of a room are structurally
	// incapable of being the same colour. That costs this function nothing, so
	// the budget goes on the three things Params cannot do: the RIG, the FLOOR
	// and the TORCH.
	// =====================================================================
	clearscope static void NeonChaos()
	{
		// ---- the baseline ------------------------------------------------
		//
		// Eight slots, always -- a preset walks all eight regardless, and the
		// palette above only means anything if it gets to finish the lap.
		LanesI("_enabled", 1);
		LanesI("_slots", 8);

		// THE HARMONISER, OFF, AND A DEAD SWITCH STATED ANYWAY.
		//
		// _bleed pulls each lane 35% toward the average of its two neighbours.
		// It is the mod's one dial whose entire job is making the four
		// surfaces agree, it is ON by default, and leaving it unstated would
		// have quietly averaged the red wall and the cyan ceiling toward each
		// other at every junction in the map. This was the first thing that
		// had to go.
		//
		// _random is stated beside it and is currently INCAPABLE of doing
		// anything: GITD_Lane.Step takes colours from GITD_Presets.SlotColor
		// whenever preset > 0, and every path that reads _random lives inside
		// GITD_Lane.SlotColor on the other branch. So the one preset that
		// actually wants a rolled colour cannot get one from the lanes. It
		// gets one from the torch instead (below), which is the only live
		// randomiser in the mod. This zero is a stated position, not a
		// defence; if that branch is ever fixed it should be reconsidered
		// here first, because this is the preset the switch was built for.
		LanesI("_random", 0);
		LanesI("_bleed", 0);

		// Saturation is the ONE thing all four are allowed to agree on,
		// because it is what makes this neon rather than noise. The palette
		// already sits at 0.95; 1.0 here refuses to pull any of it back.
		Lanes("_saturation", 1.0);

		// ---- four different ways of changing colour -----------------------
		//
		// Every other preset in this file picks one transition and gives it to
		// all four lanes. This gives each lane a different one, so the four do
		// not merely change at different TIMES, they change by different
		// MEANS -- a cut, a dissolve, a dip and a bounce, happening in the
		// same room and never in the same second.
		//
		//   wall bottom  Snap      the cut. Hard, and the only hard thing here
		//   wall top     Fade      a dissolve you can watch cross
		//   ceiling      Breathe   dips through darkness at the halfway point,
		//                          so the ceiling goes out for a moment and
		//                          comes back a different colour
		//   floor        Ping-Pong walks the slot order backwards half the
		//                          time, so the floor revisits colours the
		//                          walls have already left behind
		//
		// FLASH (pattern 2) IS THE ONE PATTERN REFUSED, and not for the
		// obvious reason -- read the code and it is a rush-and-hold, not a
		// strobe. It is refused because on a lane that then sits for twenty
		// seconds it reads as Snap with a smear on it, which is a fourth way
		// of saying "cut" when one lane is already saying it cleanly.
		I("gitd_wb_pattern", 0);
		I("gitd_wt_pattern", 1);
		I("gitd_cg_pattern", 3);
		I("gitd_fg_pattern", 4);

		// THE SPEEDS ARE TRANSITION LENGTHS, NOT RATES OF CHANGE, and that
		// distinction is the safety margin of this whole preset.
		//
		// Snap never draws its crossfade, so wall bottom's 0.080 is only there
		// to keep the phase clock honest -- the same reason Red Alert and Low
		// Power raise theirs. The other three are DELIBERATELY SLOW, which is
		// the opposite of what the word chaos suggests: 0.012 on the ceiling
		// is a two-and-a-half second dissolve. The room is never still and
		// nothing in it is ever quick.
		//
		// The cost is honest and worth stating: eight transitions add three
		// seconds to wall bottom's cycle and nineteen to the ceiling's, so the
		// true periods are near 154, 168, 182 and 176 seconds rather than the
		// prime totals below. No two of those are integer multiples either,
		// and the prime holds are what guarantee rounding cannot make them so.
		F("gitd_wb_speed", 0.080);
		F("gitd_wt_speed", 0.020);
		F("gitd_cg_speed", 0.012);
		F("gitd_fg_speed", 0.026);

		// ---- four different shapes of light ------------------------------
		//
		// Falloff is a per-lane choice here for the same reason pattern is:
		// four surfaces meeting at a corner, each with a different curve on
		// its own gradient, cannot be read as one lighting scheme. Coverage
		// spreads over four to one, so the ceiling wash and the wall seam are
		// not even the same ORDER of thing.
		//
		// Unison now spreads its four as well, and the two spreads are
		// opposite statements: Unison's is a HIERARCHY -- a key, two fills and
		// an accent, four weights a lighting plan would carry. This is four
		// unrelated numbers, four different curves, no relationship at all.
		// Same twelve cvars; one of them was planned and one of them was not.
		//
		// The floor gets the widest reach and Linear, the flattest curve, so
		// it is the one surface that stays legible while everything above it
		// argues. You have to be able to see the ground.
		I("gitd_wb_falloff", 2);  I("gitd_wb_coverage",  88); F("gitd_wb_intensity", 1.5);
		I("gitd_wt_falloff", 1);  I("gitd_wt_coverage", 232); F("gitd_wt_intensity", 0.9);
		I("gitd_cg_falloff", 3);  I("gitd_cg_coverage", 160); F("gitd_cg_intensity", 1.8);
		I("gitd_fg_falloff", 0);  I("gitd_fg_coverage", 320); F("gitd_fg_intensity", 1.2);

		// AND THE ONE SWITCH THAT DELETES EVERY LINE ABOVE.
		//
		// gitd_pc_shape lives on the colour customiser page and does not stay
		// in the colour half. GlowHandler.zs:2200 gates it on `preset > 0` --
		// not on WHICH preset -- so with it set, all four coverages become
		// gitd_pc_coverage, all four falloffs become gitd_pc_falloff, and all
		// four intensities become gitd_pc_intensity. The twelve numbers in the
		// table above are read, discarded and replaced by three, and the four
		// surfaces come out identically shaped.
		//
		// That is not a degraded version of this preset, it is the specific
		// thing this section exists to prevent, arriving from a checkbox on
		// another page with no menu row anywhere reading wrong. It defaults
		// off, which is exactly why an unstated position on it is a trap: it
		// only bites the player who went looking.
		B("gitd_pc_shape", false);

		// ---- AND THE ROOM ITSELF IS NOT EVENLY LIT ------------------------
		//
		// The lane animation offsets each SECTOR's phase by where that sector
		// sits, so a crest travels through the map rather than the whole map
		// pulsing at once. Four lanes on four different axes means the room's
		// brightest region is somewhere different for each of the four
		// surfaces, and those four somewheres move independently:
		//
		//   wall bottom  east/west        along X
		//   wall top     north/south      along Y
		//   ceiling      ripple           out from the map centre
		//   floor        by height        up through the level's own storeys
		//
		// THE NUMBERS ARE WHERE THE EPILEPSY LIVES, so they are the most
		// conservative in the file. Speed is cycles per SECOND: 0.31 is the
		// fastest and that is one undulation every three and a quarter
		// seconds. Depth 0.45 means the swing is between 55% and 100% of the
		// lane's brightness -- it never reaches zero, so nothing here can
		// blink. And sharpness stays at 1.0, a plain sine: above 1 the crest
		// narrows into the EKG spike the cvar note describes, and a narrow
		// bright spike travelling past you at speed is precisely the thing
		// this preset must not produce.
		//
		// The four speeds are close but not equal, which is deliberate -- they
		// BEAT against each other over a couple of minutes rather than
		// separating cleanly, so even the disagreement is not periodic.
		I("gitd_wb_anim", 2); F("gitd_wb_anim_speed", 0.17); F("gitd_wb_anim_length",  900.0); F("gitd_wb_anim_phase", 0.00);
		I("gitd_wt_anim", 3); F("gitd_wt_anim_speed", 0.23); F("gitd_wt_anim_length", 1400.0); F("gitd_wt_anim_phase", 0.37);
		I("gitd_cg_anim", 1); F("gitd_cg_anim_speed", 0.29); F("gitd_cg_anim_length",  512.0); F("gitd_cg_anim_phase", 0.62);
		I("gitd_fg_anim", 4); F("gitd_fg_anim_speed", 0.31); F("gitd_fg_anim_length",  700.0); F("gitd_fg_anim_phase", 0.83);

		Lanes("_anim_depth", 0.45);
		Lanes("_anim_sharp", 1.0);

		// ---- the five clocks, and why they are prime ----------------------
		//
		// Each row sums to a prime number of seconds, and the five primes are
		// distinct, so the only common multiple the five cycles have is their
		// product. That is not a flourish -- it is the cheapest possible way
		// to guarantee what the preset promises. Any two rows that shared a
		// factor would re-sync on that factor and the room would acquire a
		// beat, and a beat is a thing you learn. It is also the exact property
		// the sister preset spends its entire function BUYING, which is worth
		// noticing: these two functions run the same machine in reverse.
		//
		// The holds inside each row are deliberately uneven, so a lane is not
		// merely on a long cycle, it is on a long cycle with no internal
		// rhythm: a colour that sits for thirty-one seconds followed by one
		// that sits for eleven.
		//
		// It is the row TOTALS that have to be prime, not the individual
		// holds. Most of the holds are prime as well, but only because small
		// odd numbers mostly are -- the last entry in each row is simply
		// whatever makes the sum come out right, which is why every row ends
		// on a composite and wall top carries a nine in the middle of it.
		//
		// SEVEN SECONDS IS THE FLOOR and among the lanes it appears exactly
		// twice -- the torch row further down carries a third. That number
		// is the humane-rate constraint written down: no surface in this room
		// is ever asked to change more than once every seven seconds.
		//
		// (The menu's hold slider stops at 30. Anything above that is
		// preset-only, so a player who opens the lane page cannot reach these
		// from it -- which also means they cannot be restored from it.)
		HoldFor("gitd_wb", 19, 31, 11, 23, 13, 29, 17,  8);   // 151
		HoldFor("gitd_wt", 23, 13, 37, 11, 19,  9, 29, 16);   // 157
		HoldFor("gitd_cg", 11, 41, 17,  7, 23, 13, 31, 20);   // 163
		HoldFor("gitd_fg", 29, 13, 19, 37, 11, 23,  7, 28);   // 167

		// ---- THE WAVE, ON THE ONE AXIS NOTHING ELSE USES -----------------
		//
		// Shape 5, rising. Everything else in this preset moves horizontally
		// -- two bars, a ring, four lane animations that all resolve to a
		// distance across the floor. The wave is the only vertical motion in
		// the room, so it can never be mistaken for any of them.
		//
		// AND IT IS THE ONLY PRESET TO USE THE COLOUR SLIDE. It slides the
		// near/far colour boundary along the wave, which means one wall is two
		// colours at two distances and the join between them crawls. That is
		// colour chaos bought with no rate at all -- it changes what a surface
		// IS without changing how often it changes -- which makes it the most
		// on-brief dial in the mod for this preset. Unison sets it to zero for
		// exactly the same reason inverted: a second hue at a distance is a
		// colour nobody chose, and over there every colour was chosen.
		//
		// BRIGHTNESS DEEPEST OF THE THREE TERMS, DELIBERATELY LOW. Reach and
		// colour move the shape and the hue; brightness moves the LEVEL, and
		// level moving is what a viewer reads as the room pulsing. Low Power
		// wants that -- it is depicting a supply sagging. Here it is the exact
		// symptom being avoided, so it sits at 0.18: enough that the wave is
		// not purely a shape trick, far too little to throb.
		//
		// Detune and seed both at maximum, which no other preset does. Detune
		// 1.0 means the period never resolves into anything countable; seed
		// 1.0 means every room in the map is cut by a different hand. Climb
		// 210 is chosen for what it is NOT: 90 makes the throb visibly travel
		// floor-to-ceiling, which is a rotating beacon and belongs to Red
		// Alert. 210 puts the four surfaces at 0, 210, 60 and 270 degrees --
		// four phases that never assemble into a front in either direction.
		// (PushWave hands the ceiling 0 and the floor three times climb, so
		// 630 folds back to 270 -- that is where the fourth number comes from.)
		//
		// The first three arguments are the ones with no prose above them, so:
		// length 1100 is over four times the default because a SHORT wavelength
		// on a rising shape is a LADDER -- evenly spaced rungs climbing a wall,
		// which is a regular pattern and belongs to the sister preset's ruler.
		// One long swell up the whole wall is not. Speed 0.45 rad/s is a
		// fourteen-second period, slower than every clock above it so it can
		// never be mistaken for one of them. Sharp 2.0 is barely off the plain
		// sine: the crest is allowed to be a little defined and no more, for
		// exactly the reason anim_sharp is pinned to 1.0 above.
		Wave(1100.0, 0.45, 2.0, 5,   // shape 5: rising, the only vertical thing here
		     0.30,                   // edge: the shape is wrong and stays wrong
		     0.18,                   // level: kept LOW. This is the throb dial.
		     0.55,                   // the colour slide -- this preset owns it
		     1.0,                    // detune at maximum: no countable period
		     1.0,                    // seed at maximum: no two rooms agree
		     210);

		// The wave's origin, stated because Wave() does not write it. 0 is the
		// map centre. Origin 2 follows you, and a wave centred on the player
		// is the one arrangement in the whole system that is never surprising
		// -- you would carry the crest with you and the room would look the
		// same from everywhere.
		I("gitd_wave_origin", 0);

		// Wave() forces gitd_seamless off, and that is fortunate rather than a
		// cost: seamless corners force the flat's coverage, falloff and
		// intensity to MATCH the wall they meet, which would delete the
		// per-lane table forty lines above.

		// ---- the floor it stands on --------------------------------------
		//
		// Compress rather than Crush. Crush is an exponential curve and it
		// flattens the midtones out of the room; this preset needs midtones,
		// because a hue you can only see at full brightness is a hue you can
		// only see for the two seconds a band is on it. Inky rather than
		// Stygian for the same reason -- dark enough that neon is the light
		// source, not so dark that the palette is a rumour.
		//
		// AND THE COLOUR DRAIN IS ZERO, WHICH IS THE LOUDEST NUMBER HERE.
		// Every other preset in the file takes some: 235, 78, 15, 255. This
		// one is the only preset whose entire subject IS colour, so any drain
		// at all is the preset arguing with itself. It has to be written, not
		// left alone -- inheriting Black and White's 255 would render Neon
		// Chaos in greyscale with every dial reading correctly.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 2);        // Compress -- proportional, keeps the midtones
		I("ddz_preset", 5);      // Inky
		I("ddz_desat", 0);       // none. This preset is made of hue.
		I("ddz_minlight", 0);    // no floor: the black between the neon is the point
		F("ddz_skymode", 1.0);

		// AND VANILLA'S OWN LIGHT EFFECTS GO, and this is the safety decision
		// of the preset rather than a look decision.
		//
		// Doom's blink, flicker and strobe sectors are thinkers that rewrite
		// sector light every tic from the map's authored value. They are the
		// one light source in the room this preset does not compose, they run
		// at map-author rates rather than mine -- a vanilla strobe is a couple
		// of tics on and a couple off -- and in a preset whose whole promise
		// is that nothing here flickers, an inherited FLICKER1 sector makes a
		// liar of every number above.
		//
		// The cost is real and one-way: switching this off destroys the
		// thinkers for the rest of the map, so Restore() writing true back
		// cannot un-destroy them and the room needs a reload to get its
		// blinking lights again. That is an acceptable price for the one
		// preset that cannot afford strobes.
		B("ddz_lighting", false);

		// PER PIXEL, and moderate. Distance falloff is what gives the room
		// depth -- so the far end of a hall is a different colour AND a
		// different brightness from your feet, which doubles the amount of
		// disagreement visible in one glance for free.
		//
		// 0.55 over 2600 is deliberately gentler than Low Power's 0.86 over
		// 1000: this preset needs you to SEE the far end of the room, because
		// the far end is where the other three lanes are doing something you
		// are not expecting.
		//
		// No height pooling at all. Dark gathering on the floor is a settling
		// effect -- it is what a still room does -- and it would also bury the
		// floor lane, which is the one surface here that has to stay readable.
		DeepDark(0.55, 2600.0, 0.0, 0.0, 256.0);

		// The drain is zero above, so there is nothing for a colour keep to
		// rescue. Said out loud because it is a leftover hazard rather than a
		// design choice: Black and White's 0.82 red-only keep, inherited into
		// a preset with no drain, weights every colour in the world by its own
		// saturation for no reason at all.
		NoKeepColor();

		// ---- NO AIR. THE AIR IS THE THING THIS PRESET CANNOT HAVE --------
		//
		// This is the biggest refusal in the function and it is not a budget
		// decision, it is arithmetic. A fog layer with any pickup at all takes
		// its colour from what is behind it and MIXES it. This preset's four
		// lanes sit at four opposed quarters of the colour wheel; the mix of
		// four opposed hues is grey. Every metre of mist between you and a
		// wall is a metre of the preset's argument being averaged away, and
		// the denser the layer the greyer the room.
		//
		// Pickup 0 would dodge that and buy something worse: a single flat
		// tint laid over four disagreeing surfaces is a unison, applied last,
		// by a system that does not know what it is covering. The sister
		// preset does exactly that on purpose and it is right to -- over there
		// the air is another member of the family. Here it is a veto.
		//
		// So the layer is off -- and everything that rides on it is written
		// down anyway. The renderer already forces tendrils, banks, the bow
		// and the gradient to zero while the layer is off, so these writes buy
		// exactly one thing: a player who switches the fog on from the menu
		// while this preset holds gets a clean layer rather than Low Power's
		// tendrils and Red Alert's bow wave. That is the difference between a
		// preset and a leftover.
		NoFog();
		NoSurface();
		Follow(0.0, 0.0);
		FogBanks(0.0, 0.004, 0.0);
		NoTendrils();
		Bow(0.0, 64.0, 0.6);
		FogGradient(0x808080, 0.0);

		// The three the layer owns that no helper touches, for the same reason
		// as the six above: Lovecraftian Fog stacks the layer up a room with a
		// period and puts a roll on it, and neither of those goes away when
		// the layer is switched off. A player who re-enables fog here would
		// get somebody else's repeating strata.
		//
		// -32768 is not an arbitrary number. It is the cvar's own default and
		// its sentinel for "no bottom", and its slider stops at -512, so this
		// is the one value in the whole fog API that the menu cannot get back
		// to once it has been moved. Writing it is the only way to restore it.
		F("gitd_fog_bottom", -32768.0);
		F("gitd_fog_period", 0.0);
		F("gitd_fog_roll", 0.0);

		// NOTHING REACTS, and that is a position rather than an omission.
		// A mist that recoils from your gun is a system that answers YOU, and
		// every answer is a thing you can predict. This preset's contract is
		// that the room owes you nothing and is not about you. (NoReactive
		// also zeroes the displacers and the wake stretch, so both are stated
		// here and must not be written again below.)
		NoReactive();

		// Back to the colour picker. Mode 4 takes the layer's colour from the
		// nearest liquid and mode 1 from a lane -- both are live inheritances
		// from Low Power, Red Alert and Unison, and all would fire the moment
		// anyone turned the layer back on. Lane and blend are inert under
		// mode 0 and are left where the player had them.
		I("gitd_fog_color_mode", 0);

		// ---- THE DANCE FLOOR ---------------------------------------------
		//
		// THE LATTICE IS BACK, AND IT IS BROKEN. This preset used to refuse it
		// outright, on the argument that a laser grid is a REGULAR pattern --
		// evenly spaced lines on a fixed rotation, the most predictable thing
		// this mod can draw -- and that a preset promising you cannot predict
		// the room has no business drawing one. That argument was correct
		// about a RULED lattice and it is the sister preset's, which now draws
		// exactly that: diamonds at 96, every fourth line bolder, nothing
		// moving, painted flat on the surfaces, in a warm amber that belongs
		// to the light it lives in.
		//
		// This is the same eleven cvars saying the opposite thing. Squares
		// rather than diamonds, at 64 rather than 96 so it is denser and
		// cheaper-looking. NO RULER -- fill_major stays at zero, because a
		// bold line every fourth one is the single gesture that says a person
		// measured this, and nobody measured this. The spacing is knocked out
		// of true by the jitter, the whole pattern slides, and it hangs in the
		// AIR as well as landing on the walls.
		//
		// One frame tells them apart, which is the entire point of putting the
		// same system in both.
		//
		// THE AIR LATTICE IS THIS PRESET'S ALONE, AND IT IS NOT A PREFERENCE.
		// SweepAirLattice solves a ray against a plane and cases shapes 2, 3
		// and 5, then `else continue` -- ring and shell need a quadratic
		// nobody wrote. Unison's eight bands are ALL shape 1, so its air value
		// is honestly zero and can never be anything else. Three of the four
		// bands here are shapes 2, 3 and 5. This is the only preset in the
		// file that can put lasers in the air at all.
		//
		// 0.4 out of a possible 4.0. The console demo runs 3.0 and that is a
		// screen door; a tenth of it is beams you can see standing in the band
		// and walk through, which is a party rig, not a security cage.
		//
		// AND THE AIR LATTICE IGNORES DRAW MODE. The shader adds it for any
		// band whose mode is non-zero, so band 3 -- the travelling SHADOW --
		// carries lit lines through the darkness it is casting. That is not a
		// bug to route around, it is what a real beam does: the air is lit and
		// the floor is not. Stated so the next reader does not "fix" it.
		//
		// WHITE, and it is the one colour decision in the preset that is a
		// refusal rather than a clash. Everything else here belongs to a
		// family that argues with three others; the lattice is the only thing
		// drawing STRUCTURE, and structure in a colour would be a fifth
		// opinion about a room that already has four too many. White is also
		// what an untinted projector throws, which is what the cheap end of a
		// hire rig actually looks like, and it stays legible over all eight
		// rolodex hues below.
		Grid(64.0, 3.0, 1.0, 0xFFFFFF, 0.0, 0.4);

		// NO FLICKER, AND THIS IS THE MOST IMPORTANT REFUSAL IN THE FUNCTION.
		//
		// "A third of the lines are out at any moment" is the obvious way to
		// make a grid read as broken, and it is the one thing in this system
		// that can hurt somebody. SweepLineAxis re-rolls the drop-out hash on
		// `floor(t * 8.0)` -- EIGHT TIMES A SECOND, per line, forever. Every
		// number above this line was chosen to keep the room under three
		// changes a second, and one call to fill_flicker would have put an
		// 8 Hz modulation across whatever fraction of the screen the lattice
		// covers, arriving from a cvar that has nothing to do with the lanes
		// and would never have been looked at again. Guarded, silent, and a
		// photosensitivity hazard. Zero, and the reason is written down so
		// nobody re-derives it as a good idea.
		//
		// The broken read is bought from the two dials that have no rate at
		// all instead:
		//
		// JITTER 0.55 pushes each line off the lattice by a stable hash of its
		// own index -- up to about seventeen units on a 64 spacing, so lines
		// nearly touch in places and yawn apart in others. It is computed once
		// per line and never changes, so it is a broken grid rather than a
		// blinking one. Unison's is zero, because a ruler with wandering
		// graduations is not a ruler.
		//
		// DRIFT 20 slides the whole pattern along the band at twenty units a
		// second -- one 64-unit cell every three and a quarter seconds, the
		// same order as the slowest lane animation and comfortably inside the
		// budget. This shipped in the plan as 0.6, which on a slider that runs
		// to 400 is indistinguishable from off: a number that reads as motion
		// and produces none.
		//
		// AND THE DRIFT CLOCK IS NOT ACTUALLY MINE. The shader's `timer` is
		// the material's own elapsed time scaled by that material's shader
		// speed, so the lattice drifts at a slightly different rate depending
		// on which texture is behind it. In any other preset that would be a
		// defect worth routing around. Here it is free chaos and it is kept,
		// stated rather than discovered.
		//
		// GRADIENT ZERO. A fade along one axis is a COMPOSITION -- it says
		// somebody decided which end mattered. Nobody decided anything here.
		// (Grad axis is left unwritten: the shader reads it only inside
		// `if (grad > 0)`, so zeroing the amount already answers it.)
		//
		// MAJOR ZERO and its BOOST left alone, on the same rule -- the boost
		// is unread while major is zero, and a second write would be noise.
		F("gitd_ss_fill_flicker", 0.0);
		F("gitd_ss_fill_jitter", 0.55);
		F("gitd_ss_fill_drift", 20.0);
		F("gitd_ss_fill_grad", 0.0);
		F("gitd_ss_fill_major", 0.0);

		// ---- the torch, WHICH PICKS ITS OWN COLOUR -----------------------
		//
		// THE ONLY LIVE RANDOMISER IN THE MOD, IN THE ONE PRESET THAT WANTS
		// ONE. gitd_rnd_colors and the per-lane _random cannot reach a preset
		// at all (see the note at the top of this function), so the mod ships
		// a randomiser page that four presets solemnly switch off and nothing
		// has ever been able to use. Flashlight.SlotColor has no preset gate:
		// under fl_random it calls GITD_Palette.RandomColor() directly. That
		// is the one door, and a disco is the one room where "roll it" is the
		// correct answer rather than a failure to choose.
		//
		// GOVERNOR 3, NEON ONLY -- full saturation, value between 0.85 and
		// 1.0, any hue. It is the governor's first user in the file's history,
		// and it answers this preset's own long-standing objection that "a
		// deep blue or a bottle green would make the torch unplayable": the
		// unconstrained roll is three independent channels, which averages to
		// mud, and mode 3 cannot produce a dark or a muddy colour at all.
		//
		// THE COST IS REAL AND IT IS AFFORDABLE HERE SPECIFICALLY. Full
		// saturation means a hue near 240 lights the room in blue only, and
		// you will read a wall badly for a few seconds. That would be
		// unshippable in Blackout, where the torch is the only light there is.
		// This room is LIT -- four lanes at intensity 0.9 to 1.8 under a
		// gentle Compress -- so the torch is a colour you are adding to a lit
		// room rather than the only way to see it. That is why this preset can
		// afford the roll and no other one can.
		//
		// HARD CONSTRAINT, AND IT IS THE REASON fl_slots SITS FOUR LINES
		// ABOVE fl_random RATHER THAN ANYWHERE ELSE: fl_random is only safe
		// because fl_slots is 8. Flashlight.CurrentColor short-circuits at
		// `count <= 1` and returns SlotColor(0) -- and that path runs EVERY
		// FRAME. Under fl_random that is a fresh RandomColor() at 35 Hz, six
		// inches from the eye, guarded and silent and never once erroring.
		// ANY EDIT THAT DROPS fl_slots HERE MUST CLEAR fl_random IN THE SAME
		// EDIT. With eight slots SlotColor is called only at slot transitions,
		// so it is a fresh colour every 7 to 29 seconds, crossfaded over two.
		//
		// FADE, NOT SNAP, and it is the one place the choice is not about
		// composition. A torch that hard-cuts colour is a strobe held six
		// inches from your face and pointed wherever you are looking. Speed
		// 0.014 is a two-second crossfade, so the beam is always mid-journey
		// between two hues and never once cuts.
		B("fl_enabled", true);
		I("fl_range", 1400);
		F("fl_intensity", 1.15);
		F("fl_inner", 9.0);
		F("fl_outer", 24.0);
		F("fl_falloff", 1.4);
		F("fl_density", 1.1);      // a visible cone, but this is not a fog preset
		F("fl_dust", 0.25);        // a little grain, so the beam is in a room
		F("fl_dust_scale", 0.05);
		F("fl_dust_drift", 0.12);
		B("fl_bounce", false);     // no omnidirectional fill. A torch is a cone.
		I("fl_slots", 8);          // EIGHT, and the next line depends on it
		B("fl_random", true);      // the mod's only reachable randomiser
		I("gitd_rnd_governor", 3); // neon only: never dark, never muddy
		I("fl_pattern", 1);        // Fade. Never a cut, six inches from your eye.
		F("fl_speed", 0.014);      // ~2s crossfade; also the slot clock
		B("fl_agitate", false);    // pointing the light at a monster does not
		                           // wake it. Blackout owns that switch, where
		                           // the torch is the only way to see and
		                           // making it dangerous is a real trade. Here
		                           // it would be a combat modifier arriving
		                           // from a lighting menu

		// The eight chosen hues are now the FALLBACK rather than what draws:
		// under fl_random SlotColor never reads them. They stay written for
		// the same reason every other unused position in this file is stated
		// -- the moment a player turns the roll off on the Flashlight page
		// they are what the torch becomes, and inheriting Cold War's eight
		// near-whites or Blackout's single halogen at that moment is the
		// leftover this whole file exists to prevent. Eight hues evenly around
		// the wheel, so the fallback is still a torch that agrees with nothing.
		I("fl_c1", 0xFF3020);   // ember red
		I("fl_c2", 0xFFB000);   // amber
		I("fl_c3", 0xC8FF00);   // lime
		I("fl_c4", 0x20FF50);   // green
		I("fl_c5", 0x00FFD0);   // aqua
		I("fl_c6", 0x00A0FF);   // azure
		I("fl_c7", 0x6030FF);   // violet
		I("fl_c8", 0xFF20C0);   // magenta

		// 131 seconds, prime, and uneven inside itself so the torch does not
		// acquire a rhythm you could time a corridor against. HoldFor takes a
		// bare prefix, and the flashlight's holds are fl_hold1..8, so the lane
		// helper fits it exactly. These are also what pace the random roll:
		// seven seconds at the shortest, twenty-nine at the longest.
		HoldFor("fl", 13, 19, 11, 23, 17, 29, 7, 12);   // 131

		// ---- THE RIG: FOUR BANDS ON A TURNING TRUSS ----------------------
		//
		// THIS IS THE PRESET'S BIGGEST SINGLE ADDITION AND IT IS THE USER'S
		// OWN SPECIFICATION. The note at the end of SECTOR_SWEEP.md reads:
		// "The rotating effect isn't great, it's too much chaos. It should be
		// like, standing in the middle of a ferris wheel." That is not an
		// argument against the spin. It is a spec for it: SLOW and LARGE.
		//
		//   spin 5 deg/s      one revolution every 72 seconds
		//   radius 1024       the slider's ceiling, half a large map
		//
		// GITD_Wave.BandOrigin fans the bands to 360/count apart around that
		// orbit, so with four bands you get four origins at ninety degrees --
		// four lights on a truss, raking the room from a centre that is
		// turning. At 1024 and 5 deg/s the origin travels about 89 units a
		// second, which sits inside the band speeds below rather than
		// swamping them: the rake and the travel are comparable and neither
		// reads as the whole story. Faster or tighter is the "too much chaos"
		// the note rejects -- a small quick orbit reads as WOBBLE, which is
		// what the previous comment here was really objecting to.
		//
		// Band 4 is the rising sheet and BandOrigin passes z through
		// untouched, so it alone does not orbit. Three lights turn and one
		// stays put. That is what a real rig looks like and it is free.
		//
		// AND THE PALETTE IS ON THE TRUSS. spin_colors 8 hands WaveBandColor
		// the rolodex: the band's colour is chosen by where the spin currently
		// is rather than by which band it is, cross-faded between neighbours
		// so it never clicks. At 72 seconds a revolution that is one colour
		// step every nine seconds -- SLOWER than the seven-second lane floor,
		// and a crossfade rather than a cut, so it costs nothing against the
		// rate budget. It is a rig thumbing through its gels.
		//
		// THE CONSEQUENCE, STATED BECAUSE IT IS EASY TO MISS: with
		// spin_colors > 1 the rolodex OVERRIDES every band's own colour, and
		// it reads all EIGHT gitd_ss_cN even though only four bands run. The
		// previous version of this preset wrote four colours and set
		// spin_colors 0 with a comment explaining that anything above 1 would
		// delete them. All eight are written below and the four-colour
		// argument is gone with the four colours.
		F("gitd_ss_spin", 5.0);
		F("gitd_ss_spin_radius", 1024.0);
		I("gitd_ss_spin_colors", 8);

		// ---- and the four bands themselves -------------------------------
		//
		// THERE IS NO PER-BAND DIRECTION CVAR. gitd_ss_direction is one value
		// for the whole train, so "bands going different ways" cannot be built
		// the obvious way. What stands in for it is per-band SHAPE, and it is
		// a stronger statement than the sign flip would have been: a ring
		// leaves its origin radially, an east/west bar runs along X, a
		// north/south bar along Y, and a rising band climbs. Four bands on
		// four different axes genuinely cross each other. Four bands on one
		// axis with the sign flipped would only have passed through.
		//
		// Direction 2, out and back, so each band returns -- at its own speed,
		// which means the return trip scrambles the order they arrived in.
		//
		// ORIGIN 0, THE MAP CENTRE, which is now the centre the TRUSS orbits
		// rather than where the bands leave from. Origin 2 follows you, which
		// sounds like the chaotic choice and is the most predictable setting
		// in the list: every band would be centred on you, so every band would
		// look identical from where you stand no matter where you go.
		//
		// THE SPEEDS ARE PRIME AND THEY ARE INTEGERS. Prime for the same
		// reason the holds are. Integers because the sweep working set moves
		// per-band speed with GetI/SetI, so a fractional speed written here is
		// silently truncated the next time the menu's band view commits -- and
		// 23.0 survives that trip as 23, which is the only reason these are
		// safe to write from a profile at all.
		//
		// THE DRIFT THEN BREAKS THE PRIMES AND THAT IS FINE. WaveBandPos
		// multiplies band i by (1 + drift * i), so at 0.35 what actually runs
		// is 23, 96, 90 and 76 rather than 23, 71, 53 and 37. The table is the
		// seed, not the answer. What survives the multiply is the property
		// that was wanted: no two equal, and none an integer multiple of
		// another.
		//
		// And nothing here is fast. The narrowest band is 90 units thick,
		// which the shader draws twice as wide, so even at its drifted 96
		// units a second it takes nearly two seconds to cross you. The widest
		// takes fourteen. There is no snap anywhere in this train.
		B("gitd_ss_enabled", true);
		I("gitd_ss_count", 4);
		I("gitd_ss_shape", 1);        // the shared shape; all four override it
		I("gitd_ss_origin", 0);       // a place, not you -- and now the hub
		I("gitd_ss_direction", 2);    // out and back, at four different speeds
		I("gitd_ss_trigger", 0);      // free-running: the room is not about you
		I("gitd_ss_drive", 0);        // time, not kills and not your health
		I("gitd_ss_range", 6144);     // 6144 / 23 = ~267s for the slowest band
		F("gitd_ss_softness", 2.6);
		F("gitd_ss_intensity", 1.3);
		I("gitd_ss_thickness", 160);  // shared; every band overrides it
		I("gitd_ss_trail", 120);
		B("gitd_ss_underlay", true);  // MANDATORY here: with underlay off a
		                              // live wave clears the lanes outright,
		                              // and the lanes are the preset
		F("gitd_ss_drift", 0.35);     // per-band speed spread ON TOP of the
		                              // table, so even the table is not the
		                              // whole story
		F("gitd_ss_health_speed", 0.0);// the sweep does not react to you. Red
		                               // Alert owns the alternate drive, where
		                               // a system reading your vitals is the
		                               // whole idea
		B("gitd_ss_drop", false);
		B("gitd_ss_actors", false);

		// Gaps are in tics, cap at 210, and ACCUMULATE -- WaveBandPos sums
		// gap1..gapN to get band N's lag, it does not read one gap per band --
		// so 97, 149 and 191 put the four launches at 0, 2.8, 7.0 and 12.5
		// seconds into a 267-second traverse. All four inside the first
		// thirteen seconds, which is fine and is the point: they leave
		// together and then come apart. By the time the ring is halfway out,
		// the east/west bar has been out and come back.
		I("gitd_ss_gap1",  97);
		I("gitd_ss_gap2", 149);
		I("gitd_ss_gap3", 191);

		// Band 1 -- the ring. Slow, thick, the closest thing to a clock.
		// Shape 1, so it is the one band with no lasers in the air.
		F("gitd_ss_speed1", 23.0); I("gitd_ss_shape1", 1);
		I("gitd_ss_thick1", 160);  I("gitd_ss_draw1", 1);   // add

		// Band 2 -- the east/west bar. The fast one, and thin.
		F("gitd_ss_speed2", 71.0); I("gitd_ss_shape2", 2);
		I("gitd_ss_thick2",  90);  I("gitd_ss_draw2", 1);   // add

		// Band 3 -- the north/south bar, and it is DARKNESS. Crush multiplies
		// the finished pixel down per fragment, so this is a wide travelling
		// shadow running at right angles to the bright bar above it. Where
		// they cross is the image of this preset: light and dark arriving on
		// the same wall from two directions at once -- and the air lattice
		// still draws inside it, so the shadow has beams standing in it.
		F("gitd_ss_speed3", 53.0); I("gitd_ss_shape3", 3);
		I("gitd_ss_thick3", 300);  I("gitd_ss_draw3", 3);   // crush

		// Band 4 -- rising, and a reveal. It pulls the dark aside rather than
		// adding light, so what it exposes is whatever the lanes happen to be
		// doing underneath -- a different room every pass, composed by nobody.
		// It is also the band that does not orbit.
		F("gitd_ss_speed4", 37.0); I("gitd_ss_shape4", 5);
		I("gitd_ss_thick4", 520);  I("gitd_ss_draw4", 2);   // reveal

		// THE PER-SECTOR LIGHT PATH IS OFF, AND SO IS THE MODE BEHIND IT.
		//
		// Every band above does its work per pixel through its draw mode.
		// The sector path would arrive a room at a time, which reads as a
		// lighting bug rather than as a band -- and running it alongside the
		// crush band would darken band 3 twice.
		//
		// gitd_ss_light_mode has to be said as well. gitd_ss_light gates fx 1
		// and fx 2 ONLY; fx 3 and fx 4 run whatever it is set to, and with
		// perband off every band takes its effect from light_mode. So an
		// inherited light_mode of 3 would have all four bands recolouring the
		// glow they cross -- overwriting the lane colours, which are the
		// preset. perband off also means WaveBandAction never resolves
		// gitd_ss_scriptN, so no inherited script name can fire here.
		B("gitd_ss_light", false);
		B("gitd_ss_perband", false);
		I("gitd_ss_light_mode", 0);

		// ---- EIGHT COLOURS NOBODY WOULD PUT IN A ROOM TOGETHER ------------
		//
		// This is the palette half of the disco and it is deliberately not a
		// scheme. Magenta, acid green, cyan, gold, orange-red, violet, white
		// and spring green: no two of them are complements, no three of them
		// are a family, and there is no arc through the list. That is the
		// point -- the sister preset's eight bands are an ARCH in one hue
		// family, chosen so band 8 hands off to band 1 with no seam. These
		// were chosen so that any two adjacent ones clash, because the truss
		// is going to cross-fade between neighbours and the fade should be
		// through a colour nobody wanted either.
		//
		// All eight are live because the rolodex reads all eight regardless of
		// band count -- WaveBandColor indexes gitd_ss_c(N) by spin phase, not
		// by band. Bands 3 and 4 crush and reveal and ignore rgb entirely, and
		// under the rolodex even that is moot; the swatches stay truthful so
		// the menu shows what the rig is loaded with.
		I("gitd_ss_c1", 0xFF1090);   // hot magenta
		I("gitd_ss_c2", 0x60FF20);   // acid green
		I("gitd_ss_c3", 0x00D8FF);   // cyan
		I("gitd_ss_c4", 0xFFC400);   // gold
		I("gitd_ss_c5", 0xFF3A18);   // orange-red
		I("gitd_ss_c6", 0x8A2BFF);   // violet
		I("gitd_ss_c7", 0xFFFFFF);   // white
		I("gitd_ss_c8", 0x00FF88);   // spring green

		// ---- the systems this preset refuses ------------------------------
		//
		// Its fog, its colour keep and its per-pixel darkness are all stated
		// further up and are NOT restated here. What follows is only what has
		// not been mentioned yet.

		// A funnel standing on one axis, doing the same thing forever, is the
		// most predictable object in the mod and also the most expensive term
		// in the shader. It is the wrong system for this preset twice over.
		NoTornado();

		// THE FLOOR MUST NOT REMEMBER. Every other preset that takes the
		// heatmap takes it because a room you walk back into should carry the
		// mark of what happened there -- which is a good idea and it is this
		// preset's exact opposite. A heatmap accumulates, so the longer you
		// play the MORE predictable the floor becomes, until it is the one
		// surface in the map you can picture before you enter. The one system
		// here that gets worse with time.
		NoHeat();

		// SHAPES ON THE FLOOR, OFF, AND THIS REVERSES A DECISION.
		//
		// This preset used to leave the floor shapes and the numeric engine
		// alone on the grounds that they are event MARKS -- something died
		// here -- rather than room composition, and that the preset has no
		// opinion about how a player wants their own feedback drawn. That is
		// sound for the NUMBERS and wrong for the SHAPES: gitd_shape_on_death
		// ships TRUE, so an enabled master paints straight-sided geometry on
		// the floor of the preset that just refused a straight-sided lattice
		// for being straight-sided -- and it paints it in a colour nobody
		// here composed, on a fade timer nobody here set.
		B("gitd_shape_enabled", false);

		// AND THE NUMBERS, OFF TOO, AND THIS ONE IS NOT A REVERSAL SO MUCH AS
		// A CORRECTION. gitd_neon_enabled ships TRUE. Its payloads default
		// off, so a clean install draws nothing -- but a player who ever
		// switched on the kill counter gets floating figures in a preset whose
		// own argument two hundred lines up is that unowned colour is noise
		// rather than chaos. A number with a font on it is unowned colour that
		// also holds still. Black and White is the one preset that takes this
		// system and it takes it on purpose.
		B("gitd_neon_enabled", false);

		// Light and particles off. The ambience layer colours emitters from
		// what the map's own texture names imply -- green on slime, orange on
		// fire -- which is a fifth colour source this preset does not compose
		// and cannot make disagree on purpose. Unowned colour in a preset
		// about colour is not chaos, it is noise, and the difference between
		// those two words is this entire function. The scan and its SOUND stay
		// on: the ears are the one channel here that is telling the truth.
		NoAmbienceLight();

		// AND THE SOUND'S REACH, STATED, BECAUSE THE LINE ABOVE CLAIMS IT.
		// NoAmbienceLight's own comment says a preset that wants silence has
		// to say so with the range -- and this preset says the opposite, that
		// the audio is the fixed reference the eye gets to measure against.
		// fw_range is the per-emitter audibility radius; 2048 is the shipped
		// value, chosen.
		F("fw_range", 2048.0);

		// Footsteps at par and occlusion near the default. Deliberately the
		// most ordinary numbers in the file. The eye is being asked to do a
		// great deal in this preset, and the audio is the fixed reference it
		// gets to measure against -- a room that sounds normal is what makes
		// the room that looks abnormal legible rather than disorienting.
		Steps(1.0);
		Occlude(0.5);

		// ---- THE RANDOMISE MODES, AND WHY TWO OF THEM STAY OFF -----------
		//
		// A preset named Chaos and a page of switches labelled Randomise are
		// going to end up in the same room eventually, so this has to be
		// written down rather than assumed -- and the answer is no longer a
		// flat no. The torch above takes the roll. These three do not, and
		// each for its own reason.
		//
		// gitd_rnd_times is the dangerous one and it is dangerous SPECIFICALLY
		// to this preset. It overrides every one of the thirty-two holds above
		// with frandom(0, 6) seconds, re-rolled on arrival. That deletes the
		// prime cycles, deletes the seven-second floor, and leaves four lanes
		// each changing colour every nought to six seconds with NO LOWER
		// BOUND -- which is the epilepsy failure mode this whole design is
		// built around avoiding, arriving through a switch on another page.
		// The torch's roll is safe because its holds are fixed at 7 to 29
		// seconds; this one rolls the holds themselves, which is the entire
		// difference and the reason one is taken and one is refused.
		//
		// gitd_rnd_patterns overrides the four chosen transitions with a hash
		// keyed on lane index, which can hand every lane the same one. Four
		// lanes changing by four different MEANS is half of what this preset
		// is; collapsing them to one is a loss with nothing bought.
		//
		// gitd_rnd_colors is written false and cannot currently do anything at
		// all -- see the lane note at the top. If GITD_Lane.Step is ever
		// taught to honour it under a preset, THIS is the preset that should
		// turn it on first, and the governor three lines up in the torch block
		// is already the right constraint for it.
		B("gitd_rnd_colors", false);
		B("gitd_rnd_times", false);
		B("gitd_rnd_patterns", false);

		// ---- the five glow-texture terms, off -----------------------------
		//
		// Five cvars with no helper, so every preset inherits them, and Cold
		// War and Red Alert now own four of the five between them -- which
		// makes these zeroes live protection rather than hygiene.
		//
		// gitd_gpulse is the one that would break the preset outright: a
		// global alarm swell driven by how many monsters are near you, applied
		// to EVERY lane at once. That is a synchroniser. It is Neon Unison,
		// switched on underneath Neon Chaos, on a clock the preset does not
		// own. gitd_greact rides the fog disturbance slots, which NoReactive
		// above has already emptied, so it would be a dial pointing at nothing
		// -- Red Alert is the only preset where those slots are full.
		//
		// The other three -- veining, a current along the surface, a crawling
		// cell network -- are DETAIL inside a band, and Cold War's whole image
		// is built from them. This preset's chaos is at room scale, and detail
		// added on top of it does not make it more unpredictable, only busier.
		// Busy is the thing that gets called chaotic by people who mean
		// unreadable.
		F("gitd_gpulse", 0.0);
		F("gitd_greact", 0.0);
		F("gitd_gtex_noise", 0.0);
		F("gitd_gflow", 0.0);
		F("gitd_gcell", 0.0);

		// ---- and the colour law, off --------------------------------------
		//
		// The colour law makes the conductor lane's current slot into a game
		// phase: cyan means the monsters are tougher, amber means they are
		// faster. It is a rule you are meant to LEARN, and it is the only
		// system in the mod that a player is supposed to be able to predict.
		//
		// Here the conductor lane holds a colour for between seven and
		// forty-one seconds on a cycle that never repeats, alongside three
		// other lanes doing the same -- so the rule would be real, in force,
		// and completely unlearnable. A difficulty modifier you cannot see
		// coming is not a mechanic, it is variance. Off, and stated, because
		// inheriting it from a preset that had designed for it would silently
		// rebalance the fight.
		B("gitd_law_enabled", false);
	}

	// NEON CHAOS'S BLOOM IS WHITE AND ITS LENS DOES NOT AGREE WITH ITSELF.
	//
	// Every other bloom in this file is tinted, and every one of them is right
	// to be: a tint is the lens agreeing with the preset. Low Power's is
	// sodium, Red Alert's is red, and in both cases the tint is a fifth vote
	// for the one colour the preset is about.
	//
	// This preset is about eight colours that refuse to agree, so a tint of
	// any kind is a unison applied at the last stage of the pipeline, by a
	// system that cannot see what it is tinting. Pure 1/1/1 is the only honest
	// setting: whatever bleeds off a surface bleeds in that surface's own
	// colour, and the magenta wall and the cyan ceiling smear past each other
	// still arguing.
	//
	// Threshold 0.30 and amount 1.8, both moderate. High threshold would find
	// only the sweep bands and let the lanes stay matte, which throws away the
	// slow half of the preset; low threshold and high amount would smear
	// opposed hues into each other and MIX them, which is the same failure the
	// fog was refused for -- bloom is just fog made of light.
	//
	// CHROMATIC FRINGING, AND THIS PRESET IS THE ONLY PLACE IT BELONGS.
	// It shipped at zero with the reasoning that "in the one preset where
	// colour is composed to the degree, invented colour contradicts the
	// design". That is the SISTER preset's argument wearing this one's name.
	// Over there every colour was chosen and a lens inventing more of them is
	// vandalism. Here nothing was chosen by anybody, the truss is already
	// thumbing through eight gels nobody coordinated, and a lens that cannot
	// decide what colour an edge is belongs in exactly this room. Unison's
	// clean glass is now a stated contrast rather than a coincidence.
	//
	// 0.06 AND NOT MORE, AND THE CEILING IS NOT THE SLIDER'S. gl_bloom_chromatic
	// is a CUSTOM_CVAR that clamps itself to 0.1 in the engine
	// (hw_postprocess_cvars.cpp:79), so anything larger written here would be
	// silently reduced and the file would carry a number that is not the
	// number that runs -- the exact class of fault this project keeps
	// shipping. bloomcombine.fp offsets red and blue radially by dir *
	// Chromatic, and dir reaches 0.5 at a corner, so 0.06 separates the
	// channels by three percent of the screen width at the edges and by
	// nothing at all in the middle. That is a visible break-up on the bright
	// edges out at the sides and a clean centre you can still aim with.
	//
	// NO STREAK. An anamorphic streak has an AXIS, and an axis is an agreement
	// imposed on a room built to have none. It is a bare gate in the engine --
	// any non-zero value is fully on, and the only strength lever is its
	// separate ratio -- so 0.0 is the whole statement, and the ratio is left
	// unwritten because a zero gate makes it unobservable and RestoreEngine
	// puts it back to the engine's 3.0 on the way out.
	clearscope static void NeonChaosBloom()
	{
		Bloom(1.80, 0.30, 0.50, 1.0, 1.0, 1.0);
		EF("gl_bloom_anamorphic", 0.0);
		EF("gl_bloom_chromatic", 0.06);

		// THE SLOWEST EYE IN THE FILE, and it is a safety decision before it
		// is an aesthetic one.
		//
		// SPEED 0.007 IS ROUGHLY FOUR SECONDS, and both halves of that have to
		// be here because the number is not seconds. It is the source alpha of
		// a per-FRAME alpha blend, so the time constant is 1 / (speed * 35) --
		// 0.007 gives 4.08 s. Red Alert runs 0.03 territory and the room
		// PUMPS; that is correct there and it is precisely the nausea failure
		// mode here, in a room already changing on five clocks with a truss
		// turning over it. At four seconds the eye AVERAGES this room instead
		// of chasing it: the bands cross, the lanes cut, the rig comes round,
		// and the exposure barely moves -- so all the motion you see is motion
		// that was composed.
		//
		// This shipped as 0.45, which is 63 milliseconds. Not merely wrong but
		// actively against the preset: this is the one that has no shared
		// clock, and an exposure that fast hands the whole screen a luminance
		// pump at the sweep rate. The preset audited every clock in the room
		// for exactly that and then let the exposure pass run one it never
		// looked at. It is also the reason the fringing above is affordable --
		// a lens artefact on top of a pumping frame would be unreadable.
		//
		// Min 0.20 keeps the adaptation from lifting the black back out from
		// between the neon, which is where the whole palette gets its
		// contrast. Base 1.0 with scale 1.0 means base + light*scale never
		// drops below 1, so this exposure cannot lift the room at all, only
		// pull a bright one down. This room is lit; it is simply lit by things
		// that do not agree.
		Exposure(1.0, 0.20, 1.0, 0.007);
	}

	// =====================================================================
	// 9. LOVECRAFTIAN FOG -- the air is the antagonist
	//
	// WHAT IT IS. Every other preset in this file treats the air as a medium:
	// something for light to hang in, something for a band to cross, something
	// to give the torch a beam. Here the air is the SUBJECT and everything else
	// is lighting for it. The room is a place the mist happens to be standing
	// in, and it was standing there before you opened the door.
	//
	// WHY IT IS NOT A FOG MACHINE. A horror-movie fog is thick, white, level
	// and inert -- it is a filter over the lens with a smell of theatre about
	// it. Three things separate this from that, and they are the only three
	// systems this preset spends anything on:
	//
	//   IT HAS A SURFACE, and the surface is above your chin. You are not
	//   walking through fog, you are wading in something, and four steps down
	//   a stairwell puts your head under it.
	//
	//   IT HAS A GRAIN. Banks the size of a hall, wisps standing off it in a
	//   thin forest, and a top that swells on a period longer than any room --
	//   so it is a substance occupying the level rather than a value applied
	//   to the frame.
	//
	//   IT IS STANDING OVER SOMETHING. One wide, slow, leaning column of the
	//   same stuff, anchored where the last thing died. Not weather. A
	//   presence, with a shape, that was interested in a specific place.
	//
	// THE RESTRAINT IS THE DESIGN. Dread is quiet, and quiet is expensive:
	// every system switched on is a second thing asking to be watched, and two
	// things asking at once is a funhouse. So the sweep is off, the lattice is
	// off, the glow textures are off, and the flashlight has no dust in it --
	// not because they would look bad but because each of them would put a
	// second texture in an image that already has one, and the one it has is
	// the point.
	//
	// AND IT DOES NOT RECORD YOU. The wake closes almost instantly behind you,
	// the mist does not part for gunfire, and nothing is displaced by anyone
	// walking through it. Low Power drags a channel you can look back down,
	// because that preset is about a place you are the first person into in
	// years. This one is the opposite claim: you are not significant enough to
	// leave a mark on it. The only thing that disturbs this air is something
	// dying in it, and the only thing that remembers is the floor.
	//
	// THE PALETTE IS NOT IN THIS FUNCTION, AND IT IS NOT GREEN. Slot 9's lane
	// colours are generated from GITD_Presets.Params, which is teal through
	// deep blue with no green anywhere in it (GlowHandler.zs, case 9). That is
	// correct and it should stay that way: the lanes are the WATER. The green
	// this preset is named for arrives from two other systems and both of them
	// are stated below -- the fog gradient puts a sick pale green through the
	// thin part at the surface, and the colour keep brings the map's own
	// nukage back to full while everything around it drains. So the blue is
	// what the mist is and the green is what is in it, and anyone retuning
	// Params for this slot should push it toward the blue end, not the green.
	// This function is the weather, the shape and the timing; the palette and
	// the timing only mean anything read together.
	// =====================================================================
	clearscope static void LovecraftianFog()
	{
		// ---- the baseline ------------------------------------------------
		//
		// FADE, AND IT IS THE ONLY PRESET HERE THAT DOES NOT SNAP.
		//
		// All four shipping presets cut, and each of them is right to: a
		// klaxon changes state, a grid drops out, a black and white film is
		// made of cuts. A cut is an EVENT -- there is a frame before and a
		// frame after and you can point at the join. This preset must not
		// have a join anywhere, because the moment you can point at when the
		// room changed, the room is a machine with a schedule and you are
		// safe. Nothing here is allowed a moment.
		//
		// Speed 0.006 is about a hundred and sixty tics, so a crossfade takes
		// roughly five seconds and is never once visible as a transition. The
		// same number is the slot clock, so every row below runs about forty
		// seconds longer than its holds add up to. That does not matter: it
		// adds the SAME forty to all four rows, and what keeps the four
		// surfaces from ever agreeing again is the differences between them,
		// which an equal addition leaves exactly alone.
		LanesI("_enabled", 1);
		LanesI("_pattern", 1);       // Fade -- see above; the only one
		LanesI("_anim", 0);          // no per-sector pulse. The wave breathes,
		                             // and one thing breathing is enough
		LanesI("_slots", 8);
		LanesI("_falloff", 1);       // Smooth. Sharp is an edge, and an edge is
		                             // an object; this light has no object in it
		Lanes("_saturation", 0.75);  // sickly rather than vivid -- a colour that
		                             // has been in water too long
		Lanes("_speed", 0.006);

		// ---- lit from underneath ------------------------------------------
		//
		// THE FLOOR IS THE BRIGHTEST LANE AND THE CEILING IS BARELY THERE,
		// which is upside down compared with every other preset here and is
		// the single decision that makes the mist read as a body of water
		// rather than as haze.
		//
		// Light entering a layer of mist from BELOW is the thing you have
		// never seen in a Doom map and have seen in every photograph of
		// anything under water: the surface glows from the far side, the
		// wisps standing off it are backlit, and the top of the layer becomes
		// visible as a surface instead of as the place the fog stops. The
		// floor lane is doing all of that, at 220 units of reach so it fills
		// the slab rather than fringing it.
		//
		// The ceiling gets forty units of reach and a SEVENTH of the floor's
		// intensity, which is another way of saying there is no ceiling.
		// Whatever is above the mist is not part of this.
		I("gitd_wb_coverage", 140); F("gitd_wb_intensity", 0.85); // the waterline
		I("gitd_wt_coverage",  64); F("gitd_wt_intensity", 0.30); // above it, faint
		I("gitd_cg_coverage",  40); F("gitd_cg_intensity", 0.20); // no ceiling
		I("gitd_fg_coverage", 220); F("gitd_fg_intensity", 1.40); // the deep, lit

		// AND THE CUSTOMISER IS NOT ALLOWED TO FLATTEN THEM.
		//
		// gitd_pc_shape lives on the colour page and reaches well past colour:
		// with it set, Apply forces ONE coverage, ONE falloff and ONE intensity
		// onto all four lanes for any preset above zero (GlowHandler.zs:2200),
		// discarding the eight numbers directly above. It does not special-case
		// the presets with literal palettes and it will not special-case this
		// one. The consequence is not a different look -- it is that the whole
		// argument this section is built on stops existing, while every menu
		// row still reads back exactly what was written here. No shipping
		// preset states it, because no shipping preset depends on the four
		// lanes disagreeing. This one is nothing but that.
		B("gitd_pc_shape", false);

		// ---- four clocks, none of them yours ------------------------------
		//
		// The holds sum to 197, 181, 211 and 167 seconds. All four are prime,
		// so the four surfaces of a room drift apart on the first cycle and
		// never re-lock -- there is no state to wait out and no beat to learn.
		//
		// The values inside each row are deliberately lumpy: a forty-second
		// stare, then three changes inside a minute, then another long
		// nothing. An even row is a metronome, and a metronome is machinery
		// working correctly.
		//
		// KNOWN AND DELIBERATE: the menu's own Duration slider (gitd_ln_hold1,
		// MENUDEF:1559) stops at 30, and eleven of the thirty-two values below
		// are above it. Restore() hands the player's numbers back untouched, so
		// nothing is damaged -- but a player who opens that page while this
		// preset is holding cannot reproduce or even reach half of this rhythm,
		// and dragging the row once snaps a 52 down to 30. That is a menu
		// defect rather than a preset one and it is reported as such; the
		// alternative is capping the preset's own design at the widest value
		// the UI happens to offer, which is the tail wagging the dog.
		HoldFor("gitd_wb", 41, 12, 33,  8, 27, 19, 44, 13);   // 197
		HoldFor("gitd_wt",  9, 36, 14, 22,  7, 31, 46, 16);   // 181
		HoldFor("gitd_cg", 52,  6, 38, 11, 29, 18, 43, 14);   // 211
		HoldFor("gitd_fg", 24, 17, 39,  6, 28, 13, 32,  8);   // 167

		// AND THE THREE LIVE RANDOMISERS ARE OFF, which no preset in this file
		// has ever said and which is the only thing keeping the two paragraphs
		// above true.
		//
		// They are MODES rather than rolls: each re-decides every time it is
		// asked, so nothing written here can be tuned while one of them runs.
		// gitd_rnd_patterns hands every lane a per-map transition and takes the
		// Fade decision at the top of this function with it -- the one thing
		// this preset is not allowed to have is a cut, and that switch puts the
		// cuts back. gitd_rnd_times replaces every hold above with a roll of
		// nought to six seconds on arrival, so four prime clocks become four
		// flickers. gitd_rnd_colors is written for completeness and is the one
		// of the three that currently does NOTHING to a preset at all:
		// GITD_Lane.Step takes the preset branch (GlowHandler.zs:272) and every
		// path that reads gitd_rnd_colors lives inside GITD_Lane.SlotColor,
		// which that branch never calls. It is stated anyway, because the day
		// that branch is fixed is the day this preset needs the protection and
		// nobody will remember to come back for it.
		//
		// This is not confiscating a toy. F/I/B capture the player's value, so
		// Restore() hands all three back the moment the preset is switched off:
		// they lose the mode for exactly as long as they have asked for this
		// room and not a tic longer.
		B("gitd_rnd_patterns", false);
		B("gitd_rnd_times", false);
		B("gitd_rnd_colors", false);

		// ---- SOMETHING BREATHING, ON A PERIOD LONGER THAN THE ROOM --------
		//
		// Wavelength at the ceiling of the range and speed at almost nothing:
		// one cycle takes minutes and the crest is wider than any space you
		// will stand in. That is the entire trick. A wave you can see travel
		// is weather and you learn its period in thirty seconds; a wave whose
		// wavelength exceeds the room never presents itself as a wave at all.
		// What you get instead is a corridor that is not as bright as it was
		// when you came down it, with no moment where it changed.
		//
		// Shape 4, a shell, so it has a centre in three dimensions rather
		// than being a plane crossing the map. Reach and brightness both
		// modest and both present, which is the opposite of the choice Low
		// Power argues for: there the whole point was to separate the supply
		// moving from something moving, because a dying grid is a supply. This
		// preset wants exactly the ambiguity that separation removes.
		//
		// Detune 0.9, higher than anything else in the file. Red Alert keeps
		// its detune low because a warning must repeat. Nothing here is
		// warning you about anything, and a rhythm you could anticipate would
		// be a promise that the room is governed.
		//
		// Climb 0: the four surfaces share one phase, so the swell is
		// continuous where a wall meets a floor rather than stepping at the
		// join. The mist is one body and the light in it has to be one body
		// too.
		Wave(2048.0, 0.09, 1.0, 4,   // shell: it has a centre, and depth
		     0.25,                   // the edge moves
		     0.30,                   // and so does the light, and you cannot
		                             // tell which of the two you are watching
		     0.0,                    // no colour slide; the palette is slow enough
		     0.9,                    // and it never once repeats
		     0.4,                    // rooms mostly agree -- one thing, one map
		     0);

		// THE WAVE HAS AN ORIGIN AND NO PRESET HAS EVER SAID WHAT IT IS.
		//
		// gitd_wave_origin takes the same seven values the sweep's does and is
		// written by nothing in this file -- Wave() does not touch it -- so
		// every shipping preset inherits whichever anchor was last set from
		// the menu. Here it is 0, the map centre: the swell comes from a fixed
		// place that is not you, does not follow you, and does not care which
		// way you walked. Origin 2 would make the room breathe around your own
		// head, which is comforting in the precise way this must not be.
		//
		// 0 is also the only one of the seven that is SAFE in this preset, and
		// the reason is worth stating once here because it decides the tornado
		// as well. OriginFor is shared, and mode 1 -- "where you spawned" --
		// reads ambient.origin, which is only ever assigned inside
		// RefreshAmbient AFTER the gitd_ss_enabled check (GlowHandler.zs:1282,
		// early return). This preset switches the sweep off, so that assignment
		// never runs, ambient.origin stays (0,0,0) for the whole map, and the
		// guard at GlowHandler.zs:1223 returns the PLAYER'S POSITION every tic
		// instead. Under this preset mode 1 is mode 2 wearing another name.
		I("gitd_wave_origin", 0);

		// ---- the floor it stands on ---------------------------------------
		//
		// Compress rather than Crush. Crush is an exponential and it flattens
		// the midtones out of a room, which is correct for Blackout and for
		// Black and White because both of those are arguments about contrast.
		// This preset needs the midtones intact, because the mist IS a
		// midtone -- crush it and the layer stops having a lit side and a dark
		// side and becomes one grey mass.
		//
		// Inky rather than Oppressive: one notch darker than Low Power, which
		// is as far as this can go before the fog's own density starts
		// double-counting and the far wall is black before there is any mist
		// between you and it.
		B("gitd_dd_enabled", true);
		I("ddz_mode", 2);       // Compress -- proportional, keeps the midtones
		I("ddz_preset", 5);     // Inky
		I("ddz_desat", 110);    // see below; the drain is half the palette

		// NO LIGHT FLOOR, and vanilla's own light thinkers LEFT ALONE.
		//
		// Blackout switches ddz_lighting off because a blinking sector shoves
		// a room back to its authored brightness several times a minute and in
		// a pure void that is the void failing. Here it is not worth the
		// price: switching it off DESTROYS the Lighting thinkers for the rest
		// of the map and only a reload brings them back, so Restore() can
		// write the cvar back and cannot undo the damage. A room that flickers
		// is also not wrong in this preset -- it is one more thing behaving
		// without reference to you. Stated as true rather than left alone,
		// because inheriting a one-way switch is how a preset breaks the next
		// preset.
		I("ddz_minlight", 0);
		B("ddz_lighting", true);
		F("ddz_skymode", 1.0);  // the sky darkens with everything else. There
		                        // is no outside in this preset

		// ---- AND THE PITS GO BLACK ----------------------------------------
		//
		// Distance falloff DELIBERATELY MODEST at 0.40 over 3000 units, which
		// is the lowest of any preset that uses it. Low Power sets 0.86 over
		// 1000 to make a corridor stop being visible -- but that preset has
		// almost no fog by comparison, so the distance term is the only thing
		// it has to hide with. Here the mist is already doing that job, at
		// density 2.0, and stacking a hard distance curve on top of it means
		// the far end of a hall is black before there is any air in the way.
		// Then the fog is not hiding anything: the darkness got there first,
		// and the whole preset is a black corridor with green fringing.
		//
		// THE HEIGHT TERM IS WHERE THIS PRESET SPENDS ITS DARKNESS. 0.90 is
		// the deepest pooling in the file by a wide margin, and it is the
		// answer to the one thing a fog layer cannot say on its own: what is
		// UNDER the surface. Mist obscures at a constant rate per unit
		// travelled, so a sump twelve feet down looks exactly like the floor
		// you are standing on, only further away. This makes down mean
		// something.
		//
		// THE REFERENCE IS ABSOLUTE WORLD Z AND NOT A HEIGHT ABOVE THE FLOOR,
		// which is worth writing down once because nothing else in this
		// project does. The shader computes (ref - pixel Z) / range, so 32
		// with a range of 224 means ground level at Z=0 takes a barely visible
		// fourteen percent and anything sunk two hundred units below it is
		// gone. On a map whose floors all sit at Z=400 it does nothing at all,
		// which is the honest cost of a world-space term and the reason the
		// reference is set low rather than at some average floor: the failure
		// mode should be "no pooling" and never "the whole level is black".
		//
		// The fog top (36) and the tornado's two ends (-96 and 1100) are the
		// same kind of number and take the same cost. This preset is calibrated
		// for maps whose walkable floors sit near Z=0, which is most of them,
		// and degrades toward doing nothing rather than toward doing damage on
		// the ones where they do not.
		DeepDark(0.40, 3000.0, 0.90, 32.0, 224.0);

		// ---- WHAT SURVIVES THE DRAIN --------------------------------------
		//
		// 110 is a deliberate half-measure and the only value in this preset
		// that is a compromise rather than a commitment. Full drain would make
		// the fog's green the only colour in the world, which sounds right and
		// is not: with nothing else coloured, the green stops reading as WRONG
		// and starts reading as the art direction. Wrongness needs something
		// correct beside it. At 110 the map's browns and greys go most of the
		// way to neutral and keep enough of themselves to be recognisably a
		// Doom level, and the mist is then the thing that does not belong.
		//
		// GREEN ONLY, and this is the one that took an argument. Red is the
		// obvious keep -- Blackout and Black and White both take it, both for
		// blood, both correctly. Blood is not what this preset is about, and
		// keeping it would put a second saturated colour in a frame that has
		// exactly one. Hue 2 keeps green, which means the map's own nukage,
		// slime and toxic pools come back up to full while everything around
		// them drains -- so the level turns out to have been full of the same
		// substance all along, and the mist is where it has got to.
		//
		// The threshold is 0.70 rather than Black and White's 0.82 because
		// Doom's liquids are less saturated than its blood. The 0.12 edge is
		// tight for the reason that preset gives: a colour that is nearly grey
		// is worse than either.
		KeepColor(0.70, 0.12, 2);

		// ---- THE AIR, WHICH IS THE PRESET ---------------------------------
		//
		// TOP 36, AND THE NUMBER IS THE WHOLE DESIGN. gitd_fog_top is a world
		// Z and the player's view sits around 41 above a floor at zero, so 36
		// puts the surface five units under your eyeline on flat ground. You
		// can see across the room. You can also see the top of the mist, which
		// is the point -- everything below your chin is in it and you are
		// looking out over it like someone standing chest-deep in a lake.
		//
		// Four steps down and you are under. That is not a metaphor; the
		// layer's top is nearly a level (see Follow below), so descending is
		// genuinely submerging, and the sensible thing to do about a sunken
		// room stops being obvious.
		//
		// Anything above 41 was tried and is wrong: with the surface over your
		// head there is no surface, only a filter, and the preset collapses
		// into the fog machine it is defined against.
		//
		// DENSITY 2.0, nearly twice Low Power's, because this layer is not
		// atmosphere for something else to happen in. SOFT 18: the top edge
		// fades over eighteen units, enough that it is not a lid and not so
		// much that it stops being a surface.
		//
		// PICKUP 0.15, AND THIS IS THE COLOUR ARGUMENT. Every other preset
		// with fog turns pickup up -- Low Power to 0.75, Red Alert to 0.85 --
		// because mist taking its colour from what is behind it is what stops
		// it reading as a filter laid over the room. That is exactly the
		// property this preset does not want. The mist is not lit by this
		// building and is not part of it; it is the wrong colour BECAUSE it
		// came from somewhere else. Zero was too far -- Black and White proves
		// zero reads as a printed tone -- so 0.15 leaves it faintly aware of
		// the room without ever belonging to it.
		//
		// AND THE WAKE ALL BUT REFUSES YOU. Amount 0.12 over a 70-unit radius
		// with lag 0.85, which closes almost the instant you have passed. Low
		// Power's slow wake drags a channel you can look back down, and that
		// is a record that you were there. This preset will not keep one. You
		// displace a hand's width of it and it is gone before you have turned
		// round.
		Fog(36, 2.0, 18, 0x102A30,
		    1.3,      // the torch carves it, and that is the only reveal here
		    0.15,     // and it takes almost nothing from the room it is in
		    0.12, 70, 0.85);

		// A TRUE LEVEL, VERY NEARLY. Two presets sit lower -- Black and White
		// at a flat zero and Red Alert at 0.1 -- and neither means by it what
		// this means. Black and White is flat because it is describing an
		// image. Red Alert is nearly flat because its air handling is still
		// running, which is a claim about a building that works. This one is
		// nearly flat because it is describing WATER. A level
		// surface is what makes low ground fill and a staircase rise out of
		// it, and what makes walking down into a sump an act with a consequence
		// rather than a change of scenery.
		//
		// Not zero. Zero is absolute world Z and a map whose floors all sit
		// two hundred units up would have no mist in it at all; 0.18 sags the
		// surface toward the ground under it just enough to survive that
		// without ever climbing a stair with you.
		Follow(0.18, 0.0);

		// AND THE SURFACE MOVES, on a swell four times anything else in this
		// file. Amplitude 7 is the top rising and falling seven units -- small
		// against the room and enormous against your chin, since you are
		// standing in it. Wavelength 90 is world units per radian, so the
		// visible period is about 565 units: longer than most rooms, which
		// means it does not present as a pattern. Speed 0.28 is a slow ocean
		// swell, and the cross swell at 0.9 is the highest in the file -- half
		// again the default, against Low Power's 0.65, Black and White's 0.7
		// and Red Alert's 0.5. It stops well short of the slider's own ceiling
		// of 2.0, where the second wave is stronger than the first and what
		// you get is chop. Two waves at an angle interfering is the difference
		// between a surface rolling and a texture scrolling, and this is the
		// one preset where you will be looking straight along that surface for
		// minutes at a time.
		Surface(7.0, 90.0, 0.28, 0.9);

		// ONE LAYER, NO REPEAT, NO BOTTOM.
		//
		// Fog() sets ten cvars and none of these three, so all three inherit,
		// and each is capable of destroying this preset on its own. A bottom
		// anywhere but the sentinel turns the slab into a floating band and
		// there is nothing under it; a period turns it into a stack of
		// horizontal bars, which is a genuinely good effect belonging to a
		// completely different preset; a roll slides that stack. -32768 is the
		// "no bottom" value, and it is OUTSIDE the menu slider's own range, so
		// writing it here is the only way anyone who has touched that slider
		// gets a floor layer back.
		F("gitd_fog_bottom", -32768.0);
		F("gitd_fog_period", 0.0);
		F("gitd_fog_roll", 0.0);

		// THE AIR HAS MASSES IN IT. Depth 0.70 is the heaviest banking in the
		// file, at 0.0012 -- larger than room-sized, so a bank is not a
		// feature you can see the edges of, it is a stretch of the level where
		// the air is simply thicker.
		//
		// DRIFT 0.9 IS VERY NEARLY STANDING STILL, and that is the number
		// doing what the sentence above says. It is world units per second,
		// added straight to the sample point before the scale is applied, so
		// at this bank size a mass takes the better part of a quarter of an
		// hour to move its own width. Low Power runs 1.4 and Red Alert 4.0
		// because in both of those the air is going somewhere. Here the
		// thickness is a property of the PLACE: the bank over the sunken half
		// of the room was there when you arrived and will still be there when
		// you come back through it.
		//
		// Uniform density is a value applied to the screen. This is a
		// substance that is not the same everywhere, which is the difference
		// between fog and weather, and at this density it is also the only
		// thing stopping the layer reading as one flat wash.
		FogBanks(0.70, 0.0012, 0.9);

		// ---- AND THINGS STAND UP OUT OF IT --------------------------------
		//
		// Low Power takes tendrils and is sparse about it -- 0.20 at 150-unit
		// spacing, one every few paces, wisps off standing air in a building
		// nobody has ventilated. This is nearly three times the amount at half
		// the spacing and forty units taller: a thin forest of them, tall
		// enough that they stand well above the surface and well above your
		// head, so you are looking through them rather than down at them.
		//
		// LEAN 22, WHICH IS FOUR TIMES LOW POWER'S AND IS THE WHOLE READING.
		// A vertical wisp is steam and steam is thermodynamics. A wisp leaning
		// hard and consistently, in air with no wind in it and a wake that
		// proves nothing is moving, is being PULLED, and there is nothing in
		// the room to pull it. That is the cheapest cosmic-horror sentence
		// available in this engine and it costs one float.
		//
		// Rise 0.25 and taper 2.6 are set here because Tendrils() does not
		// touch either and both invert the effect if inherited. Rise is how
		// fast they climb: at the default 0.6 they read as boiling, and
		// something rising slowly is looking around. Taper 2.6 thins them
		// hard toward the top, so they end in nothing rather than in a flat
		// cut, and a shape that ends in nothing is one you cannot resolve.
		//
		// Affordable at this density because the lattice is a fract(): four
		// hundred of them cost what one costs.
		Tendrils(0.55, 84.0, 16.0, 150.0, 22.0);
		F("gitd_fog_tendril_rise", 0.25);
		F("gitd_fog_tendril_taper", 2.6);

		// SICKLY GREEN AT THE TOP, ABYSS UNDERNEATH. The base colour is a
		// near-black blue-teal, which is what the body of the layer is made
		// of; the gradient puts a paler, sicklier green through the thin part
		// near the surface. Measured against the layer's own thickness, so it
		// means the same thing in a room where you are chin deep as in one
		// where it is round your ankles.
		//
		// Two colours is a colour decision and Black and White is right to be
		// nervous of it. Here it is the brief: the surface is the sick thing
		// and the depth is the frightening thing, and one colour cannot say
		// both.
		FogGradient(0x468C68, 0.55);

		// THE PICKER, AND NOTHING FROM THE MAP.
		//
		// Mode 0 is the only defensible source for this preset and it has to
		// be written down, because Low Power ships mode 4 -- the mist takes
		// the colour of the nearest liquid -- and Red Alert ships mode 1.
		// Selecting this preset after either of those without stating a mode
		// would hand the entire palette above to whatever sump you happen to
		// be standing near. At mode 0 the lane and blend cvars are not read at
		// all, which is why they are deliberately left alone rather than
		// written to values that would mean nothing.
		I("gitd_fog_color_mode", 0);

		// ---- WHAT DISTURBS IT, WHICH IS ALMOST NOTHING --------------------
		//
		// GOUT, ON DEATH ONLY. Mode 3 billows mist outward from the event, and
		// the event is exclusively something dying: shot disturbance is zero,
		// so emptying a magazine into the air does nothing to it whatsoever.
		// That asymmetry is the point. Your gun is not interesting to this
		// air. A body is.
		//
		// Speed 90 is the slowest in the file -- Black and White's ring runs
		// at 190 and calls that slow -- so the billow does not pop, it swells
		// out over several seconds and is still spreading long after you have
		// stopped looking at it. Life 5.0 keeps it there. A death here is not
		// punctuated, it is absorbed.
		//
		// Stretch 0 completes the argument the wake started upstairs: nothing
		// trails behind you, because you are not the thing this air responds
		// to.
		Reactive(3, 0.0, 1.4, 90.0, 5.0, 0.0);
		F("gitd_fog_react_death_size", 260.0);   // wide -- it swallows the spot

		// IGNITE OFF, AND THIS ONE IS A TRAP RATHER THAN A TASTE.
		//
		// gitd_fog_react_ignite does NOT go through the react mode. It fires
		// from WorldThingDestroyed on any missile, always mode 2, gated on
		// gitd_fog_react alone -- so switching reactive fog on at all arms it,
		// and its default is 1.4. Every rocket, every plasma ball, every
		// imp fireball hitting a wall would light a flash in this mist. In
		// Blackout that is the preset; here it is a firework display in a
		// preset whose entire claim is that nothing happens quickly. Reactive()
		// does not set it and no shipping preset states it.
		F("gitd_fog_react_ignite", 0.0);

		// AND NOTHING IS DISPLACED BY WALKING THROUGH IT. Displacers carve a
		// hole in the mist around each nearby actor, and a hole in fog moving
		// toward you before you can see what is making it is, on paper, the
		// most Lovecraftian thing in the engine. It is refused because it
		// points at things that are ALIVE. The mist here answers exactly one
		// event -- something dying -- and it answers it twice, with the gout
		// above and the column below, which is defensible because both are
		// describing an aftermath. A displacer describes a present threat, and
		// a mist that reliably tells you where the danger is has stopped
		// hiding anything. Reactive() does not clear this and only NoReactive()
		// does, so it is written directly -- the same reason Black and White
		// writes it directly.
		F("gitd_fog_displace", 0.0);

		// NO BOW WAVE, because a bow wave is mist shouldered aside by a
		// travelling sweep band and there is no sweep in this preset. Written
		// as zero rather than skipped: Red Alert ships 0.7 and a leftover bow
		// with no band to belong to is a rippling artefact with no visible
		// cause, which in a preset like this one would be read as intentional
		// and would be the only dishonest thing in it.
		Bow(0.0, 64.0, 0.6);

		// ---- THE COLUMN ---------------------------------------------------
		//
		// One tornado, and it is not weather. Everything about the numbers is
		// chosen to stop it reading as a funnel: 180 units across at the base
		// widening to 560, density 0.5, spin 0.30 -- the shader turns a
		// three-armed density field at a third of that in radians per second,
		// so one full revolution takes about a minute and the pattern repeats
		// every twenty seconds -- and a twist of 3 against the default 8, so
		// the sides are near enough vertical that there is no corkscrew to
		// read. What is left is a standing column of the same mist as the
		// floor, wider than a corridor, turning slowly enough that you are
		// never certain it is turning at all.
		//
		// SWIRL 0.85 FIRST. At low swirl no spin value makes it look like it
		// rotates -- the swirl is what puts structure in the wall for the spin
		// to move. This is the cvar that decides whether the column is an
		// object or a smudge, and the spin is a distant second.
		//
		// It starts at -96, below the floor, so it comes up OUT of the ground
		// rather than resting on it, and runs to 1100, well through most
		// ceilings, so it has no top either. A column with two visible ends is
		// an object in the room. A column with neither is passing through the
		// room on its way somewhere. Both are absolute world Z -- the origin's
		// own Z is discarded by PushTornado, which only takes x and y -- so
		// this shares the calibration and the failure mode written down in the
		// DeepDark paragraph above.
		//
		// ORIGIN 4, WHERE THE LAST THING DIED. IT IS THE LEAST BAD OF SEVEN
		// AND IT IS NOT CLEAN, SO HERE IS THE WHOLE TABLE RATHER THAN AN
		// ARGUMENT FOR THE WINNER.
		//
		//   0  a fixed world x/y. Absolute coordinates on an arbitrary map, so
		//      on most levels the column stands somewhere you never go and on
		//      many it stands outside the geometry entirely. That is this
		//      project's signature failure -- guarded, never erroring, silently
		//      not happening -- and it is the worst option here, not the safest.
		//   1  where you spawned. THE RIGHT ANSWER AND IT DOES NOT WORK HERE.
		//      OriginFor reads ambient.origin, which RefreshAmbient only ever
		//      assigns AFTER its gitd_ss_enabled check (GlowHandler.zs:1282
		//      returns early). This preset switches the sweep off, so that
		//      assignment never runs on any map, ambient.origin stays (0,0,0)
		//      for the whole level, and the "not set yet" guard at
		//      GlowHandler.zs:1223 hands back the player's own position every
		//      tic. Under this preset mode 1 IS mode 2. Fixing that is one
		//      line in GlowHandler and is reported; until it lands, this is a
		//      tornado worn on the head.
		//   2  follows you. A tornado on your head is a grey screen, and the
		//      engine's own comment on mode 6 says so.
		//   3  your last shot. It relocates on the trigger, which is the most
		//      frequent event in the game.
		//   4  the last thing that died.
		//   5  the nearest live monster. Re-found EVERY TIC, and when the area
		//      is clear it falls through to the player's position -- so it
		//      hunts until you win and then lands on you.
		//   6  in front of you at arm's length, recomputed as you turn. Worn.
		//
		// SO ORIGIN 4, AND ITS TWO COSTS STATED RATHER THAN BURIED. Before the
		// first kill it stands at the map's geometric centre, which is often
		// inside rock and which means the level can open with the column not
		// visible at all. And it HARD-CUTS: PushTornadoAnchor reads the origin
		// and calls PushTornado with it (GlowHandler.zs:2354-2362) with no
		// easing of any kind, so every death anywhere on the map moves a
		// 560-wide volume instantly.
		//
		// What makes that survivable rather than a bug is that the cut has
		// cover, and the cover is deliberate. The gout above fires from the
		// same WorldThingDied, at the same position, on the same frame, at 260
		// units and swelling for five seconds. So the column does not appear
		// beside a corpse out of nothing -- it appears inside a billow that is
		// blooming there anyway, and the two together are one sentence: the
		// mist gathers over what has died, and it is still there when you come
		// back. The departure from the previous body is the residual cost and
		// there is no lever in the shader that softens it.
		//
		// This is also why the displacers stay refused above. Two systems on
		// one event is one too many when they are two ANSWERS; these are a
		// moment and an aftermath.
		Tornado(4, -96.0, 1100.0,
		        180.0, 560.0,       // wide at the base, wider at the top
		        0.5,                // thin enough to see the room through
		        0x1A3C58,           // colder than the floor layer: from deeper
		        0.85,               // swirl first -- this is what makes it turn
		        0.30,               // and then almost no spin at all
		        110.0);             // and it does not stand straight

		// Tornado() sets eleven cvars and leaves five, every one of which
		// changes what it reads as. Twist near zero for the reason above;
		// a 22-second lean period so the sway is slower than your patience;
		// scatter 1.5 so the torch picks it out, which needs saying because
		// the tornado's scatter is a SEPARATE cvar from the layer's and is the
		// only one that applies when you are looking at the column from
		// outside the mist. X and Y are an offset from the anchor when origin
		// is not 0, so a leftover from someone placing a fixed funnel from the
		// menu would stand this one several hundred units away from the corpse
		// it is supposed to be over.
		F("gitd_tornado_twist", 3.0);
		F("gitd_tornado_lean_period", 22.0);
		F("gitd_tornado_scatter", 1.5);
		F("gitd_tornado_x", 0.0);
		F("gitd_tornado_y", 0.0);

		// ---- WHAT THE GROUND KEEPS ----------------------------------------
		//
		// The heatmap is the memory this preset needs and the only system in
		// it that accumulates. Both colours are inside the fog's own palette
		// -- a stain you can barely see for one death, a sickly luminous green
		// for a lot of them -- so it reads as the same substance having soaked
		// into the floor rather than as blood.
		//
		// SIZE 56, DOWN FROM 120, AND THE OLD NUMBER WAS DEFEATED BY AN
		// ARGUMENT ALREADY WRITTEN IN THE FILE IT READS FROM. cvarinfo's own
		// note on gitd_heat_size (lines 1240-1244) settles on 48 and rejects 96
		// by name: "two kills in a corridor merged into one wash and the map
		// lost the ability to say WHERE the fighting was, which is the only
		// thing it is for." This preset shipped 120. Deposit area goes as the
		// square, so 120 was painting five and a half times the ground per
		// corpse that the cvar's author had already decided was too much, and
		// on a long map the floor genuinely does trend to a uniform green --
		// which destroys this preset's own claim that the blue is the mist and
		// the green is what is in it. 56 is fractionally wider than the
		// shipped default, so it still pools rather than marking a point,
		// which is the one thing this preset wanted from the extra width.
		//
		// CEILING 4.0, DOWN FROM 6.0, AND IT HAS TO MOVE WITH THE RADIUS.
		// The ceiling is the summed total that reaches the high colour, and
		// the sum at any point is driven by how many deposits OVERLAP there.
		// At radius 120 two bodies five paces apart overlapped heavily and a
		// firefight climbed fast; at 56 they do not overlap at all. Left at
		// 6.0 the floor would need six bodies dying in nearly the same spot to
		// reach the high colour and would in practice never get there, so the
		// preset would have swapped an over-painted map for a dead system. 4.0
		// is a doorway somebody defended.
		//
		// Hurt 0.0. It remembers what died, not what happened to you. You are
		// not the subject of this preset and the floor is not keeping your
		// score.
		Heat(0.7, 0x14281E, 0x64C08A, 4.0, 56.0, 0.0);

		// Three cvars Heat() does not set and all three matter here.
		//
		// DECAY STAYS AT ZERO, AND IT WAS RECONSIDERED RATHER THAN INHERITED.
		// Bounding the accumulation with a slow decay is the obvious fix and
		// it was rejected twice over. First on the mechanism: HeatDecay is
		// units of intensity lost per second, subtracted linearly and clamped
		// (hw_drawinfo.cpp:921-923), so retiring one full deposit over the
		// several hundred seconds this preset would want means a value around
		// 0.0025 -- and the menu's own Forgets row runs 0.0 to 2.0 in steps of
		// 0.05 at two decimal places, so that number cannot be reached from the
		// menu, cannot be restored after it, and READS AS 0.00 on the page
		// while it is quietly draining the map. A shipped value that the UI
		// displays as off is the exact fault this project keeps finding in
		// itself. Second on the design: "it never forgets" is this preset's own
		// sentence, and the radius above is where the runaway actually came
		// from. Fix the cause, not the symptom, and leave the sentence true.
		//
		// Amount 1.0 is what GATES RECORDING -- at zero nothing is written down
		// at all and the map stays clean while every dial reads correctly.
		// Tolerance 96 is the Z difference that counts as another storey, and
		// it is stated because this is the preset built around sunken ground:
		// without it a stain in a sump would bleed onto the walkway above it
		// and the pit would stop being a separate place.
		F("gitd_heat_decay", 0.0);
		F("gitd_heat_amount", 1.0);
		F("gitd_heat_tolerance", 96.0);

		// AND IT KEEPS IT AS A STAIN AND NOT AS A DIAGRAM.
		//
		// The shape system stamps a signed-distance figure -- a ring, a cross,
		// a hexagon -- at the feet of everything that dies, and gitd_shape_on_death
		// is on by default, so the only thing standing between this preset and
		// a floor full of geometry is a master switch nobody states. It is
		// default-off, which is precisely why no preset states it and why a
		// player who turned it on once still has it on under all four.
		//
		// Two systems marking the same event is one too many, and of the two
		// only the heatmap belongs here: it accumulates rather than counting,
		// it has no edge, and it does not draw a figure with straight sides on
		// the floor of a preset whose lattice section argues that nothing in
		// it should have a straight line anywhere.
		B("gitd_shape_enabled", false);

		// AND NO FLOATING NUMBERS. The Neon Numeric engine draws a kill count
		// and a damage readout in the world, and gitd_neon_enabled is its
		// master. Both payloads default off so a clean install draws nothing,
		// which is exactly why it has never been stated and exactly why it has
		// to be: a player who ever switched the counter on carries it into
		// every preset afterwards. A number in a font, hanging over a corpse,
		// is the room reporting your performance back to you -- and this whole
		// preset is an argument that nothing here is keeping score or has
		// noticed you at all. Black and White owns this system; nobody else
		// should be able to inherit it.
		B("gitd_neon_enabled", false);

		// ---- NO SWEEP, AND NO LATTICE -------------------------------------
		//
		// A sweep is a schedule and a schedule is a promise. Low Power's four
		// beats every three and a half minutes and Red Alert's five-minute
		// procedure both work because both are about MACHINERY, and machinery
		// keeps time. The claim this preset is making is that whatever is here
		// is not operating a system, and a band arriving on a timetable
		// contradicts that more completely than any colour choice could.
		//
		// Switched off rather than left unconfigured, for the reason Black and
		// White gives: a preset that inherits whatever band the last one left
		// running is not a preset, it is a leftover.
		B("gitd_ss_enabled", false);

		// And the lattice with it. NoGrid() clears the AIR lattice only --
		// gitd_ss_fill1..8, the painted one, stay wherever Grid() last left
		// them, which is a documented asymmetry that no shipping preset states
		// and which would put a laser grid on every band the moment anyone
		// switched the sweep back on. Nothing here should ever have a straight
		// line in it.
		NoGrid();
		for (int i = 1; i <= 8; i++) I("gitd_ss_fill" .. i, 0);

		// AND THE THREE SWEEP CVARS THAT REACH BACK OUT OF THE SWEEP.
		//
		// The rule above -- state what a re-enabled sweep would inherit -- is
		// not a licence to write sixty cvars, so here is the line and the
		// reason for it. These three are the ones that do not stay inside the
		// sweep: gitd_ss_light_mode 3 RE-COLOURS THE FOUR GLOW LANES to shades
		// of the crossing band's colour (cvarinfo:197), which would erase the
		// upside-down lane hierarchy that is the most-argued section of this
		// function; gitd_ss_light is the gate on it; and gitd_ss_perband
		// bypasses that gate entirely and drives every band off the fx table
		// instead. Anything that only decides WHERE or HOW FAST a band runs --
		// gitd_ss_drop, the speeds, the gaps -- is the player's business and
		// stays theirs.
		B("gitd_ss_light", false);
		B("gitd_ss_perband", false);
		I("gitd_ss_light_mode", 0);

		// ---- ONE WRONG THING ON THE SURFACES ------------------------------
		//
		// Five glow-texture terms -- veining, a current along the surface, a
		// crawling cell network, rings off gunfire, and a global alarm pulse
		// -- and no preset in this file had ever stated one of them, so all
		// five inherited whatever was last set. Two of them are actively
		// dangerous here and stay at zero for that reason: gitd_greact rides on
		// gitd_fog_react, which this preset switches ON, so a leftover value
		// would put expanding rings through every glow in the map off every
		// shot -- and this preset has already decided at length that gunfire
		// is not interesting to the air. gitd_gpulse counts monsters near you
		// and brightens the room accordingly, which is a HUD element wearing a
		// costume, and it is the one term in the mod that says the building has
		// noticed you.
		//
		// gitd_gtex_noise and gitd_gflow stay at zero on taste. Noise ages a
		// material and nothing here is old; flow is a current running along the
		// surface, and Cold War owns that read, where it is mains hum in a
		// fluorescent bank. Two presets making the same statement with the same
		// cvar is how a system stops meaning anything.
		//
		// AND THE VEINS GO ON, AT A FIFTH OF COLD WAR'S WEIGHT AND IN A
		// DIFFERENT VOLUME.
		//
		// This was refused for three drafts on a one-texture rule -- the image
		// already has banked mist, a moving surface and a forest of wisps, and
		// a second texture means the eye has two things to resolve and settles
		// on neither. That rule is right about VOLUME and wrong about
		// SURFACES. All three of those things are in the AIR and the eye
		// resolves them as one substance; the walls and the floor have nothing
		// on them at all, and they are where you spend most of a frame looking.
		// The preset was carrying its whole argument in the air and leaving the
		// room it stands in blank.
		//
		// Lovecraft is geometry that should not exist, on something you are
		// standing next to. A hairline vein network is the only thing in this
		// mod that draws that. Scale 256 makes the cells larger than a doorway,
		// so it is a structure rather than a texture and you cannot see enough
		// of it at once to work out the pattern. Speed 0.2 against the default
		// 1.2 crawls it slower than you walk, so it is never moving when you
		// look at it and is not where it was when you look back. Width 0.03 is
		// hairlines against the default 0.08.
		//
		// Amount 0.20 -- the lowest setting the menu's own step will reach
		// above nothing -- is deliberately at the edge of visible. The floor
		// lane is the brightest in this preset, so the veins land mostly on the
		// ground and the lower walls, seen through the mist rather than over
		// it, which is the correct place for something you are not sure you
		// saw. If it ever competes with the air, it is too strong.
		F("gitd_gtex_noise", 0.0);
		F("gitd_gflow", 0.0);
		F("gitd_gcell", 0.20);
		F("gitd_gcell_scale", 256.0);   // larger than a doorway: a structure
		F("gitd_gcell_speed", 0.2);     // slower than you walk
		F("gitd_gcell_width", 0.03);    // hairlines
		F("gitd_greact", 0.0);
		F("gitd_gpulse", 0.0);

		// AND THE COLOUR LAW IS OFF, and it was weighed rather than skipped.
		//
		// It is the only system in the mod where the room's colour is a rule in
		// force rather than a picture, and on theme alone it is the most
		// Lovecraftian thing available: a house rule you did not agree to,
		// running while you fight. It is refused on a principle that costs
		// something here. A player choosing an entry from a LIGHTING menu has
		// not consented to a combat modifier, and Neon Unison and Neon Chaos
		// both turn it away on exactly that ground. A rule that only holds when
		// it is cheap is not a rule.
		//
		// It also has to be said out loud rather than left alone. The law reads
		// the conductor lane's hold times as game phases -- and the holds above
		// run to fifty-two seconds. Left on, a player who had it configured
		// would get monsters buffed or debuffed in fifty-second blocks by a
		// preset that never mentioned combat, and every symptom of it would
		// look like a balance bug.
		B("gitd_law_enabled", false);

		// ---- the torch ----------------------------------------------------
		//
		// SHORT. 900 units against Low Power's 1500, and the range is doing
		// the opposite of its usual job: at this density the beam is extinct
		// well before its nominal end anyway, and a long range only makes the
		// far half a faint smear. Cutting it puts the end of the light inside
		// the mist, where you can see it stop.
		//
		// Density 2.4 is the highest in the file. The cone has to be a solid
		// object here -- in a layer this thick the beam is not illumination,
		// it is a shape you push ahead of you, and the lit volume tells you
		// more about the air than the lit surface at the end tells you about
		// the room.
		//
		// NO DUST, AND IT COSTS SOMETHING TO REFUSE. Motes in the beam are
		// lovely and Low Power is right to run them at 0.80. But dust is a
		// third texture on top of banks and tendrils, and all three are
		// sampled in world space at similar scales, so what they produce
		// together is noise rather than depth. The mist is the particulate in
		// this preset. Adding more of it is the funhouse this whole design is
		// written against.
		//
		// Bounce off. A point light at the lens fills the room omnidirectionally
		// and would light the mist from inside your own head.
		B("fl_enabled", true);
		I("fl_range", 900);
		F("fl_intensity", 1.35);
		F("fl_inner", 8.0);
		F("fl_outer", 22.0);
		F("fl_falloff", 1.4);
		F("fl_density", 2.4);   // the cone is an object you carry
		F("fl_dust", 0.0);      // the air already has everything in it
		B("fl_bounce", false);
		I("fl_slots", 1);       // one colour. A torch is not a mood ring
		I("fl_pattern", 0);

		// AND THE COLOUR IS STATED, AT THE SHIPPED DEFAULT, BECAUSE ONE SLOT
		// MEANS IT IS THE ONLY COLOUR IN THE FRAME THAT IS NOT THE MIST.
		// fl_slots 1 reads fl_c1 and nothing else, and nothing here has ever
		// written fl_c1 -- so selecting this preset after Neon Chaos (0xFF3020,
		// its ember red) put a red cone in the water, and after Cold War or
		// Neon Unison an arctic blue-white one. 0xFFF1E0 is the cvar's own
		// shipped default, a plain warm human white, and
		// it is doing the same job ddz_desat 110 is doing: wrongness needs one
		// correct thing beside it, and the correct thing is the torch you
		// brought.
		I("fl_c1", 0xFFF1E0);

		// AND fl_random IS FALSE, WHICH IS A SAFETY REQUIREMENT IN THIS PRESET
		// AND NOT A PREFERENCE. Flashlight.CurrentColor short-circuits at
		// fl_slots <= 1 and returns SlotColor(0) directly (Flashlight.zs:106),
		// and SlotColor under fl_random returns a fresh RandomColor() on every
		// single call (Flashlight.zs:88). With one slot there is no hold and no
		// crossfade between them to slow it down, so fl_random inherited into
		// this preset is a full-rate colour strobe six inches from the eye --
		// guarded, never erroring, and a photosensitivity hazard. Any future
		// edit that wants a coloured torch here must raise fl_slots in the same
		// block.
		//
		// AGITATE FALSE. Pointing the light at a monster waking it is the
		// sharpest sentence in the flashlight rig and it belongs to Blackout,
		// where the torch is the only way to see anything and using it is
		// therefore a cost. Here the torch is one reveal among several and the
		// preset's entire claim is that what is in this room is not reacting to
		// you. A beam that wakes things is the room paying attention.
		B("fl_random", false);
		B("fl_agitate", false);

		// LIGHTS ON, PARTICLES OFF, and the split is deliberate.
		//
		// Detail 1 lights only what the map already implies is a light source
		// -- a wall torch, a lit ceiling flat, a lavafall -- and this is the
		// one preset that genuinely needs them. Mist is not visible; mist that
		// something is shining through is. Turn every source in the level off
		// and the layer has nothing to be lit by except your torch, and then
		// the only interesting air in the game is the ten degrees in front of
		// you. Detail 2 goes too far the other way: flavour glow on slime and
		// computer banks puts a cheerful little light in every corner of a
		// preset whose argument is that the room is indifferent.
		//
		// Scale 0.55 so the sources are present rather than helpful.
		//
		// Particles at zero for the same reason the torch has no dust: the fog
		// is this preset's particle system and a second one competes with it.
		Ambience(1, 0.55, 0.0);

		// AND THE EMITTER RADIUS IS STATED, AT THE SHIPPED 2048.
		// NoAmbienceLight's own comment says a preset that wants the ambience
		// layer silent "has to say so with the range", and no preset in this
		// file has ever said anything about it -- so FancyWorld's scan sounds
		// and reaches identically under all eight, which is a system nobody has
		// ever made a decision about. This preset's decision is to keep it
		// where it ships: the ambient sound is the one layer here that is
		// honestly reporting the room, and Occlude(0.55) below is already
		// making it arrive from slightly the wrong place. Cutting the radius as
		// well would silence the map, and a silent map is a different preset.
		F("fw_range", 2048.0);

		// LOUD FEET, because in a layer this deep you cannot see them. Your
		// own footsteps are the only confirmation that the ground under the
		// mist is the ground you think it is, and the material changing under
		// you is the only warning you get that it is not.
		Steps(1.2);

		// AND SOUND ARRIVES FROM SLIGHTLY THE WRONG PLACE. 0.55 is the middle
		// of the range and it is chosen against both ends. Blackout muffles
		// hard at 0.2 because there sound IS the map and a wall has to be
		// audible as a wall. Red Alert runs 0.75 because alarms are built to
		// carry. Half-occluded is the least useful setting of the three and
		// that is what it is for: things through walls are clearly audible and
		// no longer clearly located, so you hear something and cannot say
		// where, which is the correct amount of information for this preset to
		// give you.
		Occlude(0.55);
	}

	// BLOOM AS DIFFUSION, NOT AS GLARE.
	//
	// Every other bloom in this file is about a light source: Blackout's high
	// threshold finds the laser core and nothing else, Red Alert's low one
	// makes the klaxon bleed off the wall. Neither is what this needs, because
	// this preset does not really have light sources -- it has a lit MEDIUM,
	// and the brightest pixel in a typical frame is a patch of mist somewhere
	// under half white.
	//
	// So: threshold 0.18, low enough that a lit bank of fog is above it, with
	// the knee at 0.75 -- five times Blackout's, whose own comment calls 0.15
	// tight, and the widest anything in this file asks for -- so there is no
	// line to cross. A tight knee is
	// a hard edge and every hard edge in this preset has been argued away; a
	// wide one means the bloom fades in over most of the range and what it
	// produces is not a glow around anything, it is the whole image very
	// slightly failing to hold its edges. Amount 1.9 is enough to see and not
	// enough to notice.
	//
	// TINTED COLD GREEN, which is the one place the engine half is allowed to
	// state the palette outright. Anything bright enough to bleed here bleeds
	// the colour of the air, so even a muzzle flash comes back wrong.
	//
	// No anamorphic streak and no chromatic fringing, both stated. The streak
	// is a gate rather than a dial -- any non-zero value is fully on, and the
	// only strength lever is the separate ratio -- so 0.0 is the whole of that
	// decision. Fringing is a lens failing to agree with itself, and Neon Chaos
	// earns it because there nothing in the room agrees with anything. Here it
	// would blame the CAMERA, and the entire preset depends on the wrongness
	// being in the room rather than in the equipment.
	clearscope static void LovecraftianFogBloom()
	{
		Bloom(1.90, 0.18, 0.75, 0.62, 1.0, 0.86);
		EF("gl_bloom_anamorphic", 0.0);
		EF("gl_bloom_chromatic", 0.0);

		// AN EYE THAT ADAPTS AT A PERFECTLY ORDINARY RATE AND STILL CANNOT SEE.
		//
		// Low Power owns the slow eye -- the three-second blackout on stepping
		// out of a lit doorway is the best thing in that preset -- and taking
		// it here would be borrowing its idea and blunting both. This wants
		// something else.
		//
		// AND THE SPEED CVAR IS NOT A DURATION, WHICH IS WORTH WRITING DOWN
		// ONCE BECAUSE TWO SHIPPING PRESETS HAVE IT BACKWARDS. gl_exposure_speed
		// is the source alpha of an alpha-blended one-pixel accumulate against
		// last frame's exposure (hw_postprocess.cpp, PPCameraExposure::Render
		// -> SetAlphaBlend; exposurecombine.fp puts it in FragColor.a). So it
		// is a per-frame WEIGHT in 0..1: bigger means FASTER, 1.0 snaps in a
		// frame, and anything above 1 drives the destination factor negative
		// so the meter overshoots and rings instead of converging. The engine's
		// own default is 0.05 and the slider stops at 1.0.
		//
		// 0.02 IS ABOUT ONE AND A HALF SECONDS: the time constant is
		// 1 / (speed * framerate), which at the file's 35 fps convention is
		// 1 / (0.02 * 35) = 1.43 s. That is what the sentence below wants and
		// it is deliberately unremarkable. Nothing about your vision is
		// impaired, nothing takes a dramatic moment to arrive, and you adapt to
		// each room about as fast as you would in life. And the room is still
		// illegible, because what is between you and it is not an absence of
		// light, it is a substance. That is a worse feeling than blindness and
		// a quieter one, which is the whole preset.
		//
		// Base 0.72, under one, so a fully adapted eye still reads this place
		// as underlit. Min 0.20, low, because the exposure pass is perfectly
		// capable of lifting a dark room back up and undoing everything above
		// it -- the floor is what stops the auto-exposure arguing with the
		// darkness curve.
		Exposure(0.72, 0.20, 1.0, 0.02);
	}

	// BLACKOUT'S BLOOM IS NOT "NO BLOOM" ANY MORE, AND THE LASER SIGHT IS WHY.
	//
	// The old reasoning was sound on its own terms: there is nothing ambient to
	// bleed in a black room, and a threshold low enough to find something would
	// only find the thing this preset is defined by not having. So it set
	// gl_bloom 0 and was done.
	//
	// That was written before anything in the world was EMISSIVE. The laser
	// sight's core is drawn deliberately past white so the bloom pass picks it
	// up -- that is the entire mechanism by which it glows without costing a
	// dynamic light, and the same trick carries the muzzle flash and an Ignite
	// burst. Switching bloom off in the one preset built around "only what you
	// carry lights the room" silenced precisely the things that were supposed
	// to light it.
	//
	// So: bloom ON, threshold HIGH. In a room crushed to black nothing ambient
	// comes anywhere near 0.8, so the pass finds only what is genuinely past
	// white -- your laser, your muzzle, an explosion. Amount high because when
	// something does cross that line it should be the brightest thing you have
	// seen in ten minutes. Knee tight so it crosses hard rather than easing in.
	//
	// This is the preset's own thesis restated in the bloom stage: the only
	// light is the light you brought.
	clearscope static void BlackoutBloom()
	{
		Bloom(2.40, 0.82, 0.15, 1.0, 1.0, 1.0);
		EF("gl_bloom_anamorphic", 0.0);
		EF("gl_bloom_chromatic", 0.0);
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
		// The drain itself is set further down, where there is room to say why
		// it is 235 and not 255. Setting it twice in one function is how the
		// first draft of this ended up contradicting its own comment.

		// NO FLOOR. Low Power sets this to 0 and Blackout never did, so the
		// darkest preset in the mod was inheriting whatever light floor was
		// left behind -- and a floor of even 16 means it never actually
		// reaches black, which is the one thing it is for.
		I("ddz_minlight", 0);

		// AND VANILLA'S OWN LIGHT EFFECTS HAVE TO GO. No preset had ever said
		// anything about this either.
		//
		// Doom's blinking and pulsing sectors are thinkers that rewrite light
		// every tic from the map's authored value. They do not know anything
		// has been darkened, so in a crushed map they periodically shove a
		// room back up to its original brightness -- the "washout" the cvar
		// note describes. Everywhere else that is a flicker; here it is the
		// void switching itself off several times a minute.
		B("ddz_lighting", false);

		// PER SECTOR, EXPLICITLY, and it is the only preset of the four that
		// wants it that way.
		//
		// The other three use DeepDark for its distance falloff -- a corridor
		// that stops being visible rather than ending. That is precisely wrong
		// here: this preset's whole premise is a UNIFORM void, so that a glow
		// reads identically in every room and the only variable is what you
		// did to light it. Distance falloff would make the dark itself
		// interesting, and the dark is supposed to be nothing.
		//
		// It also has to be said out loud rather than left alone. The sector
		// path switches itself off when per-pixel is set, so inheriting it
		// from whichever preset ran last would leave Blackout with no
		// darkening whatsoever -- a black-canvas preset rendering a lit map,
		// with every dial reading correctly.
		NoDeepDark();

		// AND NOTHING IN THE AIR EITHER.
		//
		// Fog and a laser grid both add something you can SEE, and this
		// preset is defined by there being nothing to see. Switched off
		// explicitly rather than left alone: a preset that inherits the
		// previous one's knee-deep red mist is not Blackout, it is Low Power
		// with the lights off.
		NoFog();
		NoGrid();

		// ---- the systems that postdate this preset ------------------------
		//
		// The paragraph above is the whole argument and it now has to be made
		// against six more systems than existed when it was written.
		NoTendrils();
		NoTornado();
		NoKeepColor();

		// TWO EXCEPTIONS, and they are the preset rather than departures from
		// it.
		//
		// IGNITE works with no fog at all -- it adds LIGHT rather than mist.
		// In a room defined by having nothing to see, an explosion briefly
		// carving the shape of the space out of the dark is exactly the thing
		// this preset is about. Shot and death disturbance stay at zero:
		// there is no mist for them to push.
		Reactive(2, 0.0, 0.0, 190.0, 2.2, 1.0);

		// THE FLOOR REMEMBERS, because in a black room it is the only thing
		// that can. Every other preset can show you where you have been by
		// lighting it; this one can only show you where you have KILLED.
		Heat(0.9, 0x0A0000, 0xFF2810, 0.85, 80.0, 0.25);

		// Nothing passive glows -- that is the entire preset -- so the
		// ambience layer keeps its sound and loses its light and particles.
		NoAmbienceLight();

		// AND YOU NAVIGATE BY EAR. Footsteps up, because in the dark they are
		// how you know what you are standing on, and occlusion strong, because
		// a sound you can hear through a wall tells you the wall is not there.
		// In this preset that is not flavour, it is the map.
		Steps(1.25);
		Occlude(0.2);

		// ---- what is left of colour ---------------------------------------
		//
		// Full drain, and it costs nothing now: this used to be a walk over
		// every sector in the map, so a preset either did it or did not. It is
		// one number a frame, so it can be a considered value rather than a
		// switch.
		//
		// Not quite full. 235 rather than 255 leaves the faintest trace of hue
		// in the few things bright enough to have any -- your muzzle flash, an
		// ignite, the laser core -- so the only colour in the world is the
		// colour you brought into it. At 255 even those come out grey and the
		// preset loses the one contrast it has.
		I("ddz_desat", 235);

		// And what survives the drain is red, which needs no explanation in a
		// preset where the floor is keeping score in blood.
		KeepColor(0.5, 0.2, 1);
	}
}
