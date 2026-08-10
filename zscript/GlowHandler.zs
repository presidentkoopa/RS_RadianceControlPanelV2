// === GLOW IN THE DARK ===
//
// Four lanes, one implementation. Everything a lane can do lives in
// GITD_Lane; the handler owns four of them and never special-cases any one,
// so they cannot drift into behaving differently.
//
//   wb = wall bottom, lit from the floor    Sector.SetGlow*(Sector.floor)
//   wt = wall top, lit from the ceiling     Sector.SetGlow*(Sector.ceiling)
//   cg = the ceiling surface itself         Sector.SetFlatGlow*(Sector.ceiling)
//   fg = the floor surface itself           Sector.SetFlatGlow*(Sector.floor)
//
// A lane's position argument is which PLANE drives it, not where the light
// lands: wb is driven by the floor and appears at the bottom of the wall.

class GITD_Palette : Object
{
	static Color RandomColor()
	{
		// The GOVERNOR decides what "random" is allowed to mean. Unconstrained
		// RGB is the honest default but it produces mud as often as neon --
		// three independent channels average to grey. The other modes work in
		// hue space instead, where "random" still lands somewhere deliberate.
		let g = CVar.FindCVar("gitd_rnd_governor");
		int mode = g ? g.GetInt() : 0;

		if (mode == 1)
		{
			// One hue family: a narrow wedge, re-rolled per map so a session
			// is not always the same colour. maptime/rounds to a stable base.
			double base = double((level.maptime / 2100) * 53 % 360);
			return FromHSV(base + frandom(-25, 25), frandom(0.75, 1.0), frandom(0.7, 1.0));
		}
		if (mode == 2)
		{
			// Complementary: one of two opposed hues, so a room reads as two
			// colours arguing rather than eight colours mumbling.
			double base = double((level.maptime / 2100) * 53 % 360);
			if (random(0, 1) == 1) base += 180;
			return FromHSV(base + frandom(-12, 12), frandom(0.8, 1.0), frandom(0.75, 1.0));
		}
		if (mode == 3)
		{
			// Neon only: full saturation, high value, any hue. Never muddy.
			return FromHSV(frandom(0, 360), 1.0, frandom(0.85, 1.0));
		}
		return Color(255, random(0, 255), random(0, 255), random(0, 255));
	}

	// Kept for anything that still wants a named colour by index. Lane and
	// flashlight slots no longer use this -- they hold real 32-bit colours
	// chosen from a picker, because restricting a glow mod to 26 preset
	// colours was never defensible.
	static Color Get(int idx)
	{
		if (idx < 0) return RandomColor();
		switch (idx)
		{
			case 0:  return Color(255,   0,   0,   0); // Black
			case 1:  return Color(255, 255, 255, 255); // White
			case 2:  return Color(255, 220,  10,  10); // Red
			case 3:  return Color(255, 255, 100,   0); // Orange
			case 4:  return Color(255, 220, 200,   0); // Yellow
			case 5:  return Color(255,  80, 255,  30); // Lime
			case 6:  return Color(255,   0, 180,  20); // Green
			case 7:  return Color(255,   0, 200, 160); // Teal
			case 8:  return Color(255,   0, 220, 255); // Cyan
			case 9:  return Color(255,  40, 140, 255); // Sky
			case 10: return Color(255,  10,  40, 220); // Blue
			case 11: return Color(255,  60,   0, 200); // Indigo
			case 12: return Color(255, 140,   0, 255); // Violet
			case 13: return Color(255, 255,   0, 200); // Magenta
			case 14: return Color(255, 255,  80, 160); // Pink
			case 15: return Color(255, 255,  20,  80); // Rose
			case 16: return Color(255, 255, 250, 230); // Warm White
			case 17: return Color(255, 255, 241, 224); // Halogen
			case 18: return Color(255, 255, 214, 170); // Incandescent
			case 19: return Color(255, 160,   0, 255); // UV Purple
			case 20: return Color(255, 180,   0,   0); // Blood Red
			case 21: return Color(255,   0, 220,  40); // Toxic Green
			case 22: return Color(255, 160, 220, 255); // Ice Blue
			case 23: return Color(255, 220, 170,   0); // Gold
			case 24: return Color(255, 255,  80,  10); // Ember
			default: return Color(255,   0,  10,  80); // Deep Navy
		}
	}

	static Color Lerp(Color a, Color b, double t)
	{
		return Color(255,
			int(a.r + (b.r - a.r) * t),
			int(a.g + (b.g - a.g) * t),
			int(a.b + (b.b - a.b) * t));
	}

	static Color Scale(Color c, double m)
	{
		return Color(255,
			clamp(int(c.r * m), 0, 255),
			clamp(int(c.g * m), 0, 255),
			clamp(int(c.b * m), 0, 255));
	}

	// Saturation is distance from grey, so pulling toward the luminance grey
	// desaturates and pushing past it oversaturates. Values above 1 head
	// toward pure white, which is a glow worth having.
	static Color Saturate(Color c, double s)
	{
		double grey = c.r * 0.299 + c.g * 0.587 + c.b * 0.114;
		return Color(255,
			clamp(int(grey + (c.r - grey) * s), 0, 255),
			clamp(int(grey + (c.g - grey) * s), 0, 255),
			clamp(int(grey + (c.b - grey) * s), 0, 255));
	}
}

// One lane's state and behavior. Four of these exist; nothing in here knows
// or cares which one it is.
class GITD_Lane : Object
{
	string prefix;      // "gitd_wb" etc -- used to find this lane's cvars
	int laneIndex;      // 0..3, so a preset can give each lane its own hue range

	int slotIndex;
	Color fromCol, toCol;
	double phase;       // 0..1 through the current colour transition
	int holdLeft;       // tics left parked on the current colour
	double animClock;   // this lane's own animation clock

	// Resolved once per tic, read by the handler when applying.
	Color outColor;
	double outIntensity;

	// AnimFactor's settings, resolved once per tic in Step(). They used to be
	// looked up inside AnimFactor itself, which runs per SECTOR -- and every
	// lookup built the cvar name by string concatenation first, so the mod's
	// DEFAULT mode (lanes on, sweep off) was doing four to twenty
	// string-built CVar.FindCVar calls per sector per tic. Tens of thousands
	// of allocations and hash lookups a tic to fetch five numbers that cannot
	// change between sectors. This is the same disease PrepareWave already
	// cured for the sweep, and the same cure.
	int animMode;
	double animLength, animDepth, animSharp, animPhase;

	void Init(string p, int idx)
	{
		prefix = p;
		laneIndex = idx;
		slotIndex = 0;
		phase = 0;
		animClock = 0;
		int preset = CVar.FindCVar("gitd_preset").GetInt();
		fromCol = (preset > 0) ? GITD_Presets.SlotColor(preset, laneIndex, 0) : SlotColor(0);
		toCol   = (preset > 0) ? GITD_Presets.SlotColor(preset, laneIndex, 1) : SlotColor(1);
	}

	int GetInt(string suffix) { return CVar.FindCVar(prefix .. suffix).GetInt(); }
	double GetFloat(string suffix) { return CVar.FindCVar(prefix .. suffix).GetFloat(); }
	bool GetBool(string suffix) { return CVar.FindCVar(prefix .. suffix).GetBool(); }

	Color SlotColor(int n)
	{
		// Randomise is a lane switch rather than a magic value in a slot: a
		// colour picker has no way to express "surprise me", and hiding it in
		// one of the 16.7 million pickable values would be a trap.
		// The lane's own switch, OR the global one. Either says surprise me.
		let gr = CVar.FindCVar("gitd_rnd_colors");
		if (GetBool("_random") || (gr && gr.GetBool()))
			return GITD_Palette.RandomColor();

		int count = clamp(GetInt("_slots"), 1, 8);
		int which = (n % count) + 1;   // cvars are 1-based: _c1 .. _c8
		// Color(int) does NOT convert on this engine -- it compiles and then
		// fails at load with "Return type Color mismatch with SInt4", which
		// leaves this function returning nothing usable and the colour it was
		// asked for silently unset. Build the Color from its bytes instead;
		// that is unambiguous and needs no implicit conversion.
		int packed = CVar.FindCVar(prefix .. "_c" .. which).GetInt();
		return Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);
	}

	// Advances this lane one tic and resolves its base colour and intensity.
	// Presets, bleed and animation are applied by the handler afterwards --
	// this only handles what a lane can decide on its own.
	void Step(int preset)
	{
		int pattern = GetInt("_pattern");
		double speed = GetFloat("_speed");

		// Random patterns: this lane picks its own transition, stable for the
		// map rather than re-rolled per tic (a transition that changed every
		// frame would just look broken). laneIndex keeps the four disagreeing.
		let rp = CVar.FindCVar("gitd_rnd_patterns");
		if (rp && rp.GetBool())
			pattern = ((level.maptime / 2100) * 7 + laneIndex * 3) % 5;
		// A preset always walks all eight slots -- its 32 colours are the
		// point of it, so the lane's own slot count does not narrow them.
		int count = (preset > 0) ? 8 : clamp(GetInt("_slots"), 1, 8);

		// A colour may LINGER. Each slot has a hold time, and while it runs
		// the phase clock simply does not advance -- at phase 0 every pattern
		// outputs fromCol steadily, so no per-pattern casing is needed. Zero
		// hold (the default everywhere) is the old continuous cycling, bit
		// for bit.
		if (holdLeft > 0)
		{
			holdLeft--;
		}
		else
		{
			phase += speed;
		}
		if (phase >= 1.0)
		{
			phase -= 1.0;
			slotIndex = (slotIndex + 1) % count;
			fromCol = toCol;
			int nextSlot = (pattern == 4 && (slotIndex % 2) == 1)
				? (slotIndex + count - 1) % count
				: (slotIndex + 1) % count;
			toCol = (preset > 0) ? GITD_Presets.SlotColor(preset, laneIndex, nextSlot) : SlotColor(nextSlot);

			// We just ARRIVED on a colour (fromCol, slot slotIndex). Park on
			// it for its hold before the next transition may begin. Read at
			// the wrap, not per tic -- this path runs once per lane per
			// transition, not per sector.
			// Random times overrides the slot's own hold with a fresh roll
			// each time the colour is arrived at, so the rhythm never repeats.
			let rt = CVar.FindCVar("gitd_rnd_times");
			if (rt && rt.GetBool()) holdLeft = int(frandom(0.0, 6.0) * 35.0);
			else holdLeft = int(GetFloat("_hold" .. (slotIndex + 1)) * 35.0);
			if (holdLeft > 0) phase = 0.0;
		}

		// HALF A COSINE, NOT A WHOLE ONE. This is why the glows used to fade
		// nicely and then jump.
		//
		// cos(phase * 360) runs a FULL cycle as phase goes 0..1, so t went
		// 0 -> 1 -> 0 and the colour travelled A -> B -> back to A. But the
		// slot advance above assumes the transition ENDED on B: it does
		// fromCol = toCol and moves to C. So the lane arrived back at A, then
		// snapped to B to begin the next leg. Every cycle, on every lane.
		//
		// cos(phase * 180) goes 0 -> 1 across the phase and stops there, so
		// the last frame of one transition and the first frame of the next are
		// the same colour and nothing jumps. It keeps the ease in and out.
		switch (pattern)
		{
			default:
			case 0: // Snap -- discontinuous ON PURPOSE, holds then cuts.
				outColor = fromCol;
				break;
			case 1: // Fade
			case 4: // Ping-pong: same blend, different slot order
			{
				double t = 0.5 - 0.5 * cos(phase * 180.0);
				outColor = GITD_Palette.Lerp(fromCol, toCol, t);
				break;
			}
			case 2: // Flash -- rush to the new colour, then hold it
			{
				// Was max(0, 1 - phase*3), which started ON toCol and decayed
				// back to fromCol -- so it ended on the OLD colour and then
				// jumped to the next one, the same fault as the fade but
				// running backwards. Ramping to toCol and holding lands the
				// cycle where the next one begins.
				double t = min(1.0, phase * 3.0);
				outColor = GITD_Palette.Lerp(fromCol, toCol, t);
				break;
			}
			case 3: // Breathe -- dip through darkness between colours
			{
				double t = 0.5 - 0.5 * cos(phase * 180.0);
				outColor = GITD_Palette.Lerp(fromCol, toCol, t);
				// One dip per transition, at the halfway point. abs(cos(x*360))
				// gave TWO dips per cycle and neither of them lined up with
				// the colour change they were supposed to be hiding.
				outColor = GITD_Palette.Scale(outColor, 0.35 + 0.65 * abs(cos(phase * 180.0)));
				break;
			}
		}

		outColor = GITD_Palette.Saturate(outColor, GetFloat("_saturation"));
		outIntensity = GetFloat("_intensity");

		// The per-sector loop reads these as plain fields. The clamps live
		// here so they run once, not once per sector.
		animMode   = GetInt("_anim");
		animLength = max(GetFloat("_anim_length"), 1.0);
		animDepth  = clamp(GetFloat("_anim_depth"), 0.0, 1.0);
		animSharp  = max(GetFloat("_anim_sharp"), 1.0);
		animPhase  = GetFloat("_anim_phase");

		animClock = (animClock + GetFloat("_anim_speed") / 35.0) % 1.0;
	}

	// This lane's animation multiplier for one sector. The streak: each
	// sector's phase is offset by where it sits, so a crest travels through
	// the map rather than everything pulsing together. Sharpness narrows
	// that crest -- at 1 it is a smooth wave, high values give the EKG
	// spike through an otherwise dark lane.
	// Reads only fields Step() resolved this tic -- this runs per sector, and
	// per-sector cvar lookups were the single largest cost in the whole mod.
	double AnimFactor(Sector sec, Vector2 mapCentre)
	{
		if (animMode == 0) return 1.0;

		Vector2 c = sec.centerspot;
		double dist;
		if (animMode == 1)      dist = (c - mapCentre).Length();
		else if (animMode == 2) dist = c.x;
		else if (animMode == 3) dist = c.y;
		else                    dist = sec.floorplane.ZatPoint(c);   // travels by height

		double ph = (animClock + animPhase - dist / animLength) % 1.0;
		if (ph < 0) ph += 1.0;

		double wave = 0.5 + 0.5 * sin(ph * 360.0);
		if (animSharp > 1.0) wave = wave ** animSharp;   // narrows the crest into a streak

		return (1.0 - animDepth) + animDepth * wave;
	}
}

// Ten presets. A preset overrides every lane's colours while active; the
// player's own slot choices are untouched and return when it is switched off.
//
// A preset is NOT four flat colours. Each one defines a hue range and a
// swing in saturation and brightness; every lane takes a different quarter
// of that range and walks eight shades through it. That is 32 related but
// distinct colours per preset, and because brightness and saturation swing
// across the slots rather than sitting still, the result keeps moving
// instead of settling into a static wash.
class GITD_Presets : Object
{
	static string Name(int preset)
	{
		switch (preset)
		{
			case 1:  return "Blackout";
			case 2:  return "Low Power";
			case 3:  return "Red Alert";
			case 4:  return "Cold War";
			case 5:  return "Toxic";
			case 6:  return "Neon Unison";
			case 7:  return "Neon Chaos";
			case 8:  return "Ember";
			case 9:  return "Deep Sea";
			case 10: return "Monochrome";
			case 11: return "Black and White";
			default: return "Off";
		}
	}

	static Color FromHSV(double h, double s, double v)
	{
		h = h % 360.0;
		if (h < 0) h += 360.0;
		s = clamp(s, 0.0, 1.0);
		v = clamp(v, 0.0, 1.0);

		double c = v * s;
		double x = c * (1.0 - abs(((h / 60.0) % 2.0) - 1.0));
		double m = v - c;
		double r, g, b;
		if (h < 60)       { r = c; g = x; b = 0; }
		else if (h < 120) { r = x; g = c; b = 0; }
		else if (h < 180) { r = 0; g = c; b = x; }
		else if (h < 240) { r = 0; g = x; b = c; }
		else if (h < 300) { r = x; g = 0; b = c; }
		else              { r = c; g = 0; b = x; }

		return Color(255,
			clamp(int((r + m) * 255), 0, 255),
			clamp(int((g + m) * 255), 0, 255),
			clamp(int((b + m) * 255), 0, 255));
	}

	// Each preset: base hue, how much hue it spans, and the centre and swing
	// of saturation and brightness.
	static void Params(int preset, out double baseHue, out double hueSpread,
		out double satBase, out double satVar, out double valBase, out double valVar)
	{
		switch (preset)
		{
			default:
			case 2:  // Low Power -- dim, cold, failing
				baseHue = 220; hueSpread = 60;
				satBase = 0.55; satVar = 0.25; valBase = 0.22; valVar = 0.14; return;
			case 3:  // Red Alert -- red through orange, hard swings
				baseHue = 355; hueSpread = 45;
				satBase = 0.92; satVar = 0.08; valBase = 0.70; valVar = 0.30; return;
			case 4:  // Cold War -- blue through arctic purple
				baseHue = 210; hueSpread = 80;
				satBase = 0.78; satVar = 0.20; valBase = 0.62; valVar = 0.28; return;
			case 5:  // Toxic -- acid green into bile yellow
				baseHue = 90;  hueSpread = 60;
				satBase = 0.95; satVar = 0.05; valBase = 0.68; valVar = 0.28; return;
			case 6:  // Neon Unison -- cyan through magenta, everything hot
				baseHue = 180; hueSpread = 140;
				satBase = 0.95; satVar = 0.05; valBase = 0.85; valVar = 0.15; return;
			case 7:  // Neon Chaos -- the whole wheel, nothing repeats
				baseHue = 0;   hueSpread = 360;
				satBase = 0.95; satVar = 0.05; valBase = 0.85; valVar = 0.15; return;
			case 8:  // Ember -- banked fire, deep red to yellow
				baseHue = 10;  hueSpread = 45;
				satBase = 0.90; satVar = 0.10; valBase = 0.55; valVar = 0.40; return;
			case 9:  // Deep Sea -- teal through deep blue
				baseHue = 175; hueSpread = 70;
				satBase = 0.80; satVar = 0.18; valBase = 0.45; valVar = 0.30; return;
			case 10: // Monochrome -- saturation taken to zero, brightness does the work
				baseHue = 0;   hueSpread = 0;
				satBase = 0.0;  satVar = 0.0;  valBase = 0.55; valVar = 0.45; return;
		}
	}

	// lane 0..3 (wb/wt/cg/fg), slot 0..7.
	static Color SlotColor(int preset, int lane, int slot)
	{
		// Blackout is complete blackness. It carried a hint of void purple
		// so it would not read as a rendering failure -- but the owner's
		// intent is the absence of light, full stop, to sit alongside
		// DarkDoom Black. A hint of anything is a different preset.
		// Black and white: exactly that. No shades, no generated range --
		// alternating pure black and pure white. It is deliberately not one
		// of the generated presets, because averaging it into greys is the
		// one thing that would ruin it.
		if (preset == 11)
		{
			return ((slot % 2) == 0) ? Color(255, 0, 0, 0) : Color(255, 255, 255, 255);
		}

		if (preset == 1)
		{
			return Color(255, 0, 0, 0);
		}

		// The working set, which the Preset Options menu edits. It is loaded
		// from this preset (saved version, or shipped default) whenever the
		// selection changes -- see GITD_PresetCustomiser.
		double baseHue  = CVar.FindCVar("gitd_pc_hue").GetFloat();
		double hueSpread= CVar.FindCVar("gitd_pc_spread").GetFloat();
		double satBase  = CVar.FindCVar("gitd_pc_sat").GetFloat();
		double satVar   = CVar.FindCVar("gitd_pc_satvar").GetFloat();
		double valBase  = CVar.FindCVar("gitd_pc_val").GetFloat();
		double valVar   = CVar.FindCVar("gitd_pc_valvar").GetFloat();

		// Each lane takes its own quarter of the hue range, so the four are
		// related without being the same colour. Slots then spread across
		// that quarter.
		double laneShare = hueSpread / 4.0;
		double laneHue = baseHue + lane * laneShare;
		double hue = laneHue + (slot - 3.5) * (laneShare / 8.0);

		// Saturation and brightness swing across the eight slots on
		// different periods, so the pair never lines up into an obvious
		// repeating cycle.
		double val = valBase + valVar * sin(slot * 45.0 + lane * 30.0);
		double sat = satBase + satVar * cos(slot * 67.5 + lane * 20.0);

		return FromHSV(hue, sat, val);
	}
}

class GITD_Handler : StaticEventHandler
{
	GITD_Lane wb, wt, cg, fg;

	// Array, NOT TArray. TArray is the engine's C++ name for this
	// container; ZScript spells it Array<T> (see player.zs:3338 and
	// screenjob.zs:210 in the engine's own scripts).
	//
	// Worth knowing because the error does not say "unknown type": the
	// parser reads TArray as an identifier, then hits '<' where it wanted
	// a variable name, and reports "Unexpected '<', expecting identifier"
	// -- which points at the syntax rather than at the wrong word.
	Array<int> overridden;
	Vector2 mapCentre;

	// Every live wave. The cvar-driven sweep is waves[0] and is rebuilt from
	// the cvars each tic; everything a script fires joins the same list. See
	// the Waves section below for why the eight-band shader limit does not
	// cap this.
	Array<GITD_Wave> waves;

	// What the world last did, remembered so an origin can point at it.
	Vector3 lastShotPos, lastKillPos;
	bool haveShot, haveKill;
	bool lastAttackDown;
	int lastSecrets;

	// Sonar keeps a per-sector reveal level that decays on its own, so a
	// room lit by a passing band dims back down over the next second or two
	// instead of snapping off the moment the band clears it.
	Array<double> sonarGlow;


	// Anything a mod hangs off the wavefront.
	Array<GITD_SweepEffect> ssEffects;

	// Band scripts are named, not typed, so a cvar or a preset can point
	// at one. Resolving a name to a class every tic for eight bands would
	// be absurd, so each name is instantiated once and kept.
	Array<string> ssActName;
	Array<GITD_SweepAction> ssActObj;


	override void WorldLoaded(WorldEvent e)
	{
		// BLOOM IS NO LONGER FORCED HERE, and taking it out was not a tidy-up
		// -- it was fatal. Setting an engine cvar from play scope throws
		// "Attempt to change CVAR 'gl_bloom' outside of menu code", which
		// ABORTS THIS ENTIRE FUNCTION. Everything below never ran: no lanes,
		// no map centre, no sweep. GITD was loading and then silently doing
		// nothing whatsoever.
		//
		// The premise had expired too. This existed because gl_bloom shipped
		// OFF, so a fresh default could never reach anyone who had already run
		// the engine. On this engine it ships ON --
		// hw_postprocess_cvars.cpp: CVAR(Bool, gl_bloom, true, CVAR_ARCHIVE)
		// -- so the block was fighting for something it had already been
		// given, and killing the mod to do it.
		//
		// gitd_bloom_forced stays declared and unused, so an existing config
		// carrying it does not start logging an unknown cvar.

		overridden.Clear();

		wb = new("GITD_Lane"); wb.Init("gitd_wb", 0);
		wt = new("GITD_Lane"); wt.Init("gitd_wt", 1);
		cg = new("GITD_Lane"); cg.Init("gitd_cg", 2);
		fg = new("GITD_Lane"); fg.Init("gitd_fg", 3);

		ComputeMapCentre();

		// Effects are dropped on every map load ON PURPOSE. An effect that
		// survived the transition would be holding Sectors and Actors from a
		// level that no longer exists, which is the standard way to crash on
		// a map change. Mods re-register from their own WorldLoaded.
		ssEffects.Clear();
		ssActName.Clear();
		ssActObj.Clear();
		waves.Clear();
		ambient = null;
		nextWaveId = 0;
		haveShot = false; haveKill = false; lastAttackDown = false;
		lastSecrets = level.found_secrets;
		sonarGlow.Clear();
		for (int i = 0; i < level.Sectors.Size(); i++) sonarGlow.Push(0.0);

		Apply();
	}

	// The snapshot of "what the map said this sector's light was" used to
	// live here, because the sweep needed a baseline to offset from or it
	// accumulated to 255 and stayed there. It is now GITD_Composite's, along
	// with the restore-when-released logic -- the sweep is one of three
	// systems that needed exactly that, and three copies of it was two too
	// many. See SectorComposite.zs.

	void ComputeMapCentre()
	{
		if (level.Sectors.Size() == 0) { mapCentre = (0, 0); return; }
		double minx = 1e9, maxx = -1e9, miny = 1e9, maxy = -1e9;
		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			Vector2 c = level.Sectors[i].centerspot;
			minx = min(minx, c.x); maxx = max(maxx, c.x);
			miny = min(miny, c.y); maxy = max(maxy, c.y);
		}
		mapCentre = ((minx + maxx) * 0.5, (miny + maxy) * 0.5);
	}

	bool IsOverridden(int idx)
	{
		for (int i = 0; i < overridden.Size(); i++)
		{
			if (overridden[i] == idx) return true;
		}
		return false;
	}

	override void WorldTick()
	{
		SSRepublish();
		SSCheckTriggers();
		StepSectorSweep();

		// A wave is live if ANY wave is -- a script can fire one with the
		// ambient sweep switched off entirely, and it still has to run.
		bool anyWave = false;
		for (int i = 0; i < waves.Size(); i++)
		{
			let w = waves[i];
			if (w && w.alive && w.running) { anyWave = true; break; }
		}

		if (anyWave)
		{
			// Sweep takes over from the lanes while it runs. The point of it
			// is a dark room with nothing in it but the travelling lines, so
			// leaving the lanes lit underneath would defeat it.
			ClearAll();
			ApplySectorSweepEffects();
		}
		else
		{
			Apply();
		}
	}

	// ---- Per-sector override -------------------------------------------
	// Anything wanting ONE sector to differ -- a trap counting down, a
	// scripted moment -- claims it here. The handler will not touch that
	// sector again until ClearSectorOverride, so the claimer can animate it
	// freely without being fought.

	static void SetSectorOverride(Sector sec,
		bool wbOn, color wbCol, int wbCov, int wbFall, double wbInten,
		bool wtOn, color wtCol, int wtCov, int wtFall, double wtInten,
		bool cgOn, color cgCol, int cgCov, int cgFall, double cgInten,
		bool fgOn, color fgCol, int fgCov, int fgFall, double fgInten)
	{
		let handler = GITD_Handler(StaticEventHandler.Find("GITD_Handler"));
		if (!handler) return;

		int idx = sec.Index();
		if (!handler.IsOverridden(idx)) handler.overridden.Push(idx);

		ApplyOne(sec,
			wbOn, wbCol, wbCov, wbFall, wbInten,
			wtOn, wtCol, wtCov, wtFall, wtInten,
			cgOn, cgCol, cgCov, cgFall, cgInten,
			fgOn, fgCol, fgCov, fgFall, fgInten);
	}

	static void ClearSectorOverride(Sector sec)
	{
		let handler = GITD_Handler(StaticEventHandler.Find("GITD_Handler"));
		if (!handler) return;
		int idx = sec.Index();
		for (int i = 0; i < handler.overridden.Size(); i++)
		{
			if (handler.overridden[i] == idx)
			{
				handler.overridden.Delete(i);
				break;
			}
		}
	}

	// ---- Map-wide default ----------------------------------------------

	// Bleed pulls a lane's colour partway toward the lanes it physically
	// meets, so a corner reads as one light rather than two clashing ones.
	//
	// This is a controller-side approximation, and worth being honest about:
	// a true per-pixel blend at the corner would need the wall's shader to
	// sample the floor's glow, which it cannot do -- wall and flat are drawn
	// in separate passes with no knowledge of each other. Shifting the
	// colours toward each other gets the same read without engine work.
	Color BleedToward(Color base, Color a, Color b, bool enabled)
	{
		if (!enabled) return base;
		Color mixed = GITD_Palette.Lerp(a, b, 0.5);
		return GITD_Palette.Lerp(base, mixed, 0.35);
	}


	// ---- Sector Sweep ---------------------------------------------------
	//
	// A train of up to eight bands travelling through the world. Unlike a
	// lane this is not per-sector: the engine tests every pixel's world
	// position against each band, so a band stays thin and wraps across
	// floor, wall and ceiling as one continuous line. A per-sector effect
	// could never do this -- it would light whole rooms in sequence.
	//
	// While Sector Sweep is on it takes over from the lanes and presets
	// entirely. The point of it is a dark room with nothing in it but the
	// lines, so leaving the lanes lit underneath would defeat it.

	// Each band trails the one before it by that band's gap, and -- if drift
	// is on -- runs at its own slightly different speed, so a train that
	// started evenly spaced slowly pulls apart and folds back together.
	// ---- Waves ----------------------------------------------------------
	//
	// There is one list. The cvar-driven sweep is a wave like any other -- it
	// is rebuilt from the cvars each tic and marked ambient, which is the only
	// thing that distinguishes it. Everything a script fires joins the same
	// list, runs through the same per-sector and per-actor pass, and competes
	// for the same eight GPU slots.
	//
	// This replaces the previous arrangement, where a scripted sweep HIJACKED
	// the single sweep's state and the ambient one stopped existing for the
	// duration. That could never support two waves at once, which is exactly
	// what a setpiece wants: one wave laying the arena down while another
	// walks behind it doing something else.

	// A ceiling, not a design limit. Unlimited really means "until a runaway
	// script has spawned so many that the per-sector pass is the frame time",
	// and failing loudly at a round number beats dying mysteriously.
	const MAX_WAVES = 64;

	GITD_Wave ambient;
	int nextWaveId;

	GITD_Wave NewWave()
	{
		if (waves.Size() >= MAX_WAVES)
		{
			Console.Printf("\c[Red]GITD sweep: %d live waves, refusing more", MAX_WAVES);
			return null;
		}
		let w = new("GITD_Wave");
		w.id = ++nextWaveId;
		w.alive = true;
		w.running = true;
		w.dir = 1;
		w.subBands = 1;
		w.subGap = 20;
		w.softness = 2.0;
		w.intensity = 1.4;
		w.thickness = 24;
		w.priority = 10;
		w.visible = true;
		waves.Push(w);
		return w;
	}

	GITD_Wave WaveById(int id)
	{
		for (int i = 0; i < waves.Size(); i++)
			if (waves[i] && waves[i].id == id) return waves[i];
		return null;
	}

	// By tag, MOST RECENT first. A setpiece sweeping back out shares its tag
	// with the wave that swept it in, and if that one is still travelling the
	// oldest-first answer is the wrong wave.
	GITD_Wave FindWave(string tag)
	{
		for (int i = waves.Size() - 1; i >= 0; i--)
			if (waves[i] && waves[i].tag == tag) return waves[i];
		return null;
	}

	// ---- Per-band lookups -----------------------------------------------
	//
	// The ambient wave takes its colours, gaps and effects from the cvars, one
	// per band. A scripted wave carries its own and uses them for every band.
	// Keeping that difference here rather than inside GITD_Wave is what lets
	// the wave object stay dumb.

	// Resolve every per-band value for one wave, once for the tic. The inner
	// loops below then read arrays instead of parsing cvar names per sector.
	void PrepareWave(GITD_Wave w)
	{
		w.bandPos.Clear(); w.bandFx.Clear();
		w.bandCol.Clear(); w.bandAct.Clear(); w.bandAmt.Clear();
		for (int i = 0; i < w.subBands; i++)
		{
			w.bandPos.Push(WaveBandPos(w, i));
			w.bandFx.Push(WaveBandFx(w, i));
			Color c = WaveBandColor(w, i);
			w.bandCol.Push((c.r << 16) | (c.g << 8) | c.b);
			w.bandAct.Push(WaveBandAction(w, i));
			w.bandAmt.Push(WaveBandAmount(w, i));
		}
	}

	Color BandColor(GITD_Wave w, int i)
	{
		if (i < 0 || i >= w.bandCol.Size()) return Color(255, 0, 220, 255);
		int p = w.bandCol[i];
		return Color(255, (p >> 16) & 255, (p >> 8) & 255, p & 255);
	}

	int BandFx(GITD_Wave w, int i)
	{
		return (i >= 0 && i < w.bandFx.Size()) ? w.bandFx[i] : 0;
	}

	int BandAmount(GITD_Wave w, int i)
	{
		return (i >= 0 && i < w.bandAmt.Size()) ? w.bandAmt[i] : 48;
	}

	GITD_SweepAction BandAction(GITD_Wave w, int i)
	{
		return (i >= 0 && i < w.bandAct.Size()) ? w.bandAct[i] : null;
	}

	// Sweep 1 is the clock. w.pos is how far IT has travelled, so a band with
	// its own speed has covered pos * (its speed / sweep 1's speed) in the
	// same time. Expressing per-band speed as a ratio rather than giving every
	// band its own position keeps one clock for the whole train -- which is
	// what makes the gaps between them mean anything.
	//
	// Drift still applies on top, so "spread the train" remains a one-slider
	// way to get the same effect without setting eight numbers.
	double WaveBandSpeedScale(GITD_Wave w, int i)
	{
		if (!w.ambient) return 1.0;
		let lead = CVar.FindCVar("gitd_ss_speed1");
		let mine = CVar.FindCVar("gitd_ss_speed" .. (i + 1));
		if (!lead || !mine) return 1.0;
		double l = lead.GetFloat();
		if (l <= 0.0) return 1.0;
		return mine.GetFloat() / l;
	}

	double WaveBandPos(GITD_Wave w, int i)
	{
		if (!w.ambient) return w.CalcBandPos(i);
		double lag = 0;
		for (int g = 0; g < i; g++)
			lag += CVar.FindCVar("gitd_ss_gap" .. (g + 1)).GetInt() * w.speed / 35.0;
		return w.pos * WaveBandSpeedScale(w, i) * (1.0 + w.drift * i) - lag;
	}

	// How hard band i pushes the light level. Per band, falling back to the
	// old single value for a scripted wave, which has no per-band table.
	int WaveBandAmount(GITD_Wave w, int i)
	{
		if (!w.ambient)
		{
			let cv = CVar.FindCVar("gitd_ss_light_amount");
			return cv ? cv.GetInt() : 48;
		}
		let cv = CVar.FindCVar("gitd_ss_amount" .. (i + 1));
		return cv ? cv.GetInt() : 48;
	}

	Color WaveBandColor(GITD_Wave w, int i)
	{
		// THE ROLODEX. With spinColors set, the band's colour is chosen by
		// where the spin currently is rather than by the band index -- so as
		// the origin rakes around you the palette is thumbed through with it,
		// one colour per segment of the turn.
		if (w.spinColors > 1)
		{
			int n = clamp(w.spinColors, 2, 8);
			int pick = int(w.SpinPhase() * n + i) % n;
			int packed = CVar.FindCVar("gitd_ss_c" .. (pick + 1)).GetInt();
			return Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);
		}
		if (!w.ambient) return w.col;
		// Color(int) does NOT convert on this engine -- it compiles and then
		// fails at load with "Return type Color mismatch with SInt4", which
		// leaves this returning nothing usable and the colour silently unset.
		int packed = CVar.FindCVar("gitd_ss_c" .. (i + 1)).GetInt();
		return Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);
	}

	int WaveBandFx(GITD_Wave w, int i)
	{
		if (!w.ambient) return w.fx;
		if (!CVar.FindCVar("gitd_ss_perband").GetBool())
			return CVar.FindCVar("gitd_ss_light_mode").GetInt();
		return CVar.FindCVar("gitd_ss_fx" .. (i + 1)).GetInt();
	}

	GITD_SweepAction WaveBandAction(GITD_Wave w, int i)
	{
		if (!w.ambient) return w.sweepAction;
		if (!CVar.FindCVar("gitd_ss_perband").GetBool()) return null;
		return GITD_SweepAction.Resolve(CVar.FindCVar("gitd_ss_script" .. (i + 1)).GetString());
	}

	// ---- The ambient wave, rebuilt from cvars ---------------------------

	static double CvarF(string n, double d)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetFloat() : d;
	}

	static int CvarI(string n, int d)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetInt() : d;
	}

	double SSSpeed()
	{
		// Sweep 1 IS the clock -- see WaveBandSpeedScale. gitd_ss_speed stays
		// as the fallback for anything that predates the per-band table.
		let s1 = CVar.FindCVar("gitd_ss_speed1");
		double speed = s1 ? s1.GetFloat() : CVar.FindCVar("gitd_ss_speed").GetFloat();

		// Faster as you weaken. Nothing on screen says it, which is the
		// point -- the room starts hurrying and you feel it before you work
		// out why.
		double hs = CVar.FindCVar("gitd_ss_health_speed").GetFloat();
		if (hs > 0)
		{
			let pmo = players[consoleplayer].mo;
			if (pmo && pmo.health > 0)
			{
				int maxh = pmo.GetMaxHealth(true);
				if (maxh > 0)
					speed *= 1.0 + hs * (1.0 - clamp(double(pmo.health) / maxh, 0.0, 1.0));
			}
		}
		return speed;
	}

	Vector3 SSAmbientOrigin()
	{
		int mode = CVar.FindCVar("gitd_ss_origin").GetInt();
		let pmo = players[consoleplayer].mo;

		if (mode == 2 && pmo) return pmo.pos;
		if (mode == 1)
		{
			// Where you spawned. In E1M1 that is the door behind you, so a
			// ring expands outward from the way you came in.
			if (pmo && ambient && ambient.origin == (0, 0, 0)) return pmo.pos;
			return ambient ? ambient.origin : (mapCentre.x, mapCentre.y, 0);
		}
		if (mode == 3) return haveShot ? lastShotPos : (pmo ? pmo.pos : (mapCentre.x, mapCentre.y, 0));
		if (mode == 4) return haveKill ? lastKillPos : (mapCentre.x, mapCentre.y, 0);
		if (mode == 5)
		{
			// The nearest live monster. Re-found every tic, so the origin
			// walks from one to the next as they die and as you move.
			Actor best = null;
			double bestd = 1e9;
			if (pmo)
			{
				ThinkerIterator it = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
				Actor a;
				while (a = Actor(it.Next()))
				{
					if (!a.bISMONSTER || a.health <= 0) continue;
					double d = (a.pos.xy - pmo.pos.xy).Length();
					if (d < bestd) { bestd = d; best = a; }
				}
			}
			if (best) return best.pos;
			if (pmo) return pmo.pos;
		}
		return (mapCentre.x, mapCentre.y, 0);
	}

	void RefreshAmbient()
	{
		if (!ambient)
		{
			ambient = new("GITD_Wave");
			ambient.id = ++nextWaveId;
			ambient.ambient = true;
			ambient.alive = true;
			ambient.dir = 1;
			ambient.priority = 0;   // anything scripted outranks the weather
			waves.Push(ambient);
		}

		bool on = CVar.FindCVar("gitd_ss_enabled").GetBool();
		ambient.visible = on;
		if (!on) { ambient.running = false; return; }

		int dirMode = CVar.FindCVar("gitd_ss_direction").GetInt();
		int trigger = CVar.FindCVar("gitd_ss_trigger").GetInt();
		int drive   = CVar.FindCVar("gitd_ss_drive").GetInt();

		ambient.origin    = SSAmbientOrigin();
		ambient.shape     = CVar.FindCVar("gitd_ss_shape").GetInt();
		ambient.speed     = SSSpeed();
		ambient.range     = max(CVar.FindCVar("gitd_ss_range").GetInt(), 1);
		ambient.thickness = max(CVar.FindCVar("gitd_ss_thickness").GetInt(), 1);
		ambient.softness  = CVar.FindCVar("gitd_ss_softness").GetFloat();
		ambient.intensity = CVar.FindCVar("gitd_ss_intensity").GetFloat();
		ambient.drift     = CVar.FindCVar("gitd_ss_drift").GetFloat();
		ambient.trail     = CVar.FindCVar("gitd_ss_trail").GetInt();
		ambient.subBands  = clamp(CVar.FindCVar("gitd_ss_count").GetInt(), 1, 8);

		// TrainClear judges "has the whole train left" from subGap, but the
		// ambient wave's spacing lives in per-band gap cvars rather than the
		// uniform subGap a scripted wave carries. Left at zero, a wave with
		// followers ended the moment its LEADER left the range and cut the
		// rest off mid-room. The mean gap makes TrainClear's
		// subGap * (subBands - 1) exactly the sum of the real gaps.
		double gapSum = 0;
		for (int g = 1; g < ambient.subBands; g++)
			gapSum += CVar.FindCVar("gitd_ss_gap" .. g).GetInt();
		ambient.subGap = (ambient.subBands > 1) ? gapSum / (ambient.subBands - 1) : 0;

		ambient.spin        = CvarF("gitd_ss_spin", 0.0);
		ambient.spinRadius  = CvarF("gitd_ss_spin_radius", 0.0);
		ambient.spinColors  = CvarI("gitd_ss_spin_colors", 0);
		ambient.pingpong  = (dirMode == 2);
		ambient.loop      = (trigger == 0);
		ambient.driven    = false;

		if (drive != 0)
		{
			// The band stops being a clock and becomes a readout: its
			// position IS the number. Nothing else in the room has to say it.
			double frac = 0;
			if (drive == 1)
			{
				frac = clamp(double(level.killed_monsters) / max(level.total_monsters, 1), 0.0, 1.0);
			}
			else
			{
				let pmo = players[consoleplayer].mo;
				int maxh = pmo ? pmo.GetMaxHealth(true) : 100;
				double h = (pmo && maxh > 0) ? clamp(double(pmo.health) / maxh, 0.0, 1.0) : 1.0;
				frac = 1.0 - h;
			}
			ambient.pos = ambient.range * frac;
			ambient.dir = 1;
			ambient.running = true;
			ambient.driven = true;
			return;
		}

		if (trigger == 0)
		{
			// Free-running. Collapsing means starting at the far end.
			if (dirMode == 1 && ambient.dir > 0) { ambient.pos = ambient.range; ambient.dir = -1; }
			else if (dirMode == 0 && ambient.dir < 0) { ambient.pos = 0; ambient.dir = 1; }
			ambient.running = true;
			ambient.alive = true;
		}
	}

	// A trigger fired: start the ambient wave over.
	void SSStartPass()
	{
		if (!ambient) return;
		int dir = CVar.FindCVar("gitd_ss_direction").GetInt();
		if (dir == 1) { ambient.pos = ambient.range; ambient.dir = -1; }
		else          { ambient.pos = 0;             ambient.dir = 1;  }
		ambient.running = true;
		ambient.alive = true;
	}

	// ---- Step, cull, and allocate the eight -----------------------------

	void StepSectorSweep()
	{
		RefreshAmbient();

		for (int i = 0; i < waves.Size(); i++)
		{
			let w = waves[i];
			if (w) w.Step();
		}

		for (int i = 0; i < waves.Size(); i++)
		{
			let w = waves[i];
			if (w && w.alive && w.running) PrepareWave(w);
		}

		// Cull, giving each dying wave's script the chance to undo itself.
		// This is what makes "sweep a setpiece in, sweep it back out" one
		// call rather than bookkeeping the caller has to get right.
		for (int i = waves.Size() - 1; i >= 0; i--)
		{
			let w = waves[i];
			if (!w) { waves.Delete(i); continue; }
			if (w.alive) continue;
			if (w.sweepAction) w.sweepAction.OnFinish(self);
			if (w == ambient) ambient = null;
			waves.Delete(i);
		}

		PresentWaves();
	}

	// Eight slots, handed out by priority.
	//
	// The shader has ONE origin and ONE shape for all eight bands, so waves
	// that disagree about either cannot be drawn together -- that is a real
	// GPU constraint, not an oversight. Giving each band its own origin would
	// mean another vec4[8] in StreamData, which is a fixed 64KB uniform
	// buffer; it would cost about a tenth of the draw batching for every
	// frame of the game, to make simultaneous multi-origin waves visible. Not
	// a trade worth making silently.
	//
	// So: the highest-priority visible wave sets the origin and shape, and
	// any other visible wave that agrees with it shares the remaining slots.
	// Everything else stays logical -- still stepping, still firing scripts,
	// just not drawn.
	void PresentWaves()
	{
		GITD_Wave lead = null;
		for (int i = 0; i < waves.Size(); i++)
		{
			let w = waves[i];
			if (!w || !w.alive || !w.running || !w.visible) continue;
			if (!lead || w.priority > lead.priority) lead = w;
		}

		if (!lead) { level.ClearSweep(); return; }

		int slot = 0;
		level.SetSweepTrail(lead.dir >= 0 ? lead.trail : -lead.trail);

		// SEED FIRST. SetSweepOrigin writes the lead's origin into ALL EIGHT
		// per-band slots, so it has to run BEFORE the overrides below or it
		// erases every one of them. The count is corrected at the end once we
		// know how many slots were actually claimed.
		level.SetSweepOrigin(lead.shape, lead.origin, 8);

		for (int pass = 0; pass < 2 && slot < 8; pass++)
		{
			for (int i = 0; i < waves.Size() && slot < 8; i++)
			{
				let w = waves[i];
				if (!w || !w.alive || !w.running || !w.visible) continue;
				bool isLead = (w == lead);
				if (pass == 0 && !isLead) continue;
				// EVERY WAVE IS DRAWABLE NOW. The old rule here was that a
				// wave could only share the frame if it agreed with the lead
				// about origin AND shape, because the shader computed one
				// distance from one origin for all eight bands. It carries a
				// per-band origin now, so a ring from the map centre and a
				// column climbing out of a corner coexist. Priority still
				// decides who gets the slots when there are more than eight.
				if (pass == 1 && isLead) continue;

				for (int band = 0; band < w.subBands && slot < 8; band++)
				{
					double pos = (band < w.bandPos.Size()) ? w.bandPos[band] : 0;
					// A band that has not started yet is parked far away
					// rather than drawn sitting at the origin.
					if (pos < 0 && w.dir > 0) pos = -100000;
					level.SetSweepBand(slot, pos, w.thickness, w.softness,
						BandColor(w, band), w.intensity);
					// This band's OWN origin and shape.
					level.SetSweepBandAt(slot, w.BandOrigin(band), w.shape);
					slot++;
				}
			}
		}

		// Only the count -- SetSweepOrigin would re-seed the eight band
		// origins and erase every override made above.
		level.SetSweepCount(slot);
	}

	// How far a point is from a wave's origin, in whatever its shape
	// measures. Must agree with main.fp's smode -- if these two disagree the
	// light lags the visible band and it looks like a bug in the renderer.
	double WaveDistance(GITD_Wave w, Vector3 c)
	{
		if (w.shape == 2)      return abs(c.x - w.origin.x);
		else if (w.shape == 3) return abs(c.y - w.origin.y);
		else if (w.shape == 4) return (c - w.origin).Length();   // shell: 3D
		else if (w.shape == 5) return c.z - w.origin.z;   // rising, signed
		return (c.xy - w.origin.xy).Length();
	}

	// Nearest band of one wave, and how strongly it lands. ZScript cannot
	// forward a two-value return as an expression, so callers take both into
	// locals with [a, b] = -- a language limit, not a style choice.
	int, double WaveNearest(GITD_Wave w, double dist, double reach)
	{
		double nearest = 1e9;
		int which = -1;
		for (int b = 0; b < w.bandPos.Size(); b++)
		{
			double d = abs(dist - w.bandPos[b]);
			if (d < nearest) { nearest = d; which = b; }
		}
		if (which < 0 || nearest > reach) return -1, 0.0;
		return which, 1.0 - clamp(nearest / reach, 0.0, 1.0);
	}

	// ---- What arrival does ----------------------------------------------
	//
	// Per-sector by nature -- light level is a sector property -- so this is
	// necessarily coarser than the band itself, which is per-pixel.

	void ApplySectorSweepEffects()
	{
		// The master switch. Off, no band shifts light at all, whatever its
		// own effect says -- the sweep is then purely something you look at.
		let lightCv = CVar.FindCVar("gitd_ss_light");
		bool lightOn = lightCv ? lightCv.GetBool() : false;
		int sonarFloor = CVar.FindCVar("gitd_ss_sonar_floor").GetInt();
		double sonarFade = max(CVar.FindCVar("gitd_ss_sonar_fade").GetInt(), 1);

		bool anySonar = false;
		for (int i = 0; i < waves.Size(); i++)
		{
			let w = waves[i];
			if (!w || !w.alive || !w.running) continue;
			for (int b = 0; b < w.bandFx.Size(); b++)
				if (w.bandFx[b] == 4) { anySonar = true; break; }
		}

		for (int i = 0; i < ssEffects.Size(); i++) ssEffects[i].BeginPass();

		if (sonarGlow.Size() != level.Sectors.Size())
		{
			sonarGlow.Clear();
			for (int i = 0; i < level.Sectors.Size(); i++) sonarGlow.Push(0.0);
		}

		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			if (IsOverridden(i)) continue;
			Sector sec = level.Sectors[i];
			Vector2 c2 = sec.centerspot;
			Vector3 c = (c2.x, c2.y, sec.floorplane.ZatPoint(c2));

			bool touched = false;
			bool sonarHere = false;

			for (int wi = 0; wi < waves.Size(); wi++)
			{
				let w = waves[wi];
				if (!w || !w.alive || !w.running) continue;

				double reach = max(w.thickness, 1.0) * 3.0;
				int band;
				double strength;
				[band, strength] = WaveNearest(w, WaveDistance(w, c), reach);
				if (band < 0) continue;

				touched = true;
				int fx = BandFx(w, band);

				// Declared against the MAP's level, never the live one --
				// reading live and adding is what used to saturate every room
				// the sweep touched to 255 within four tics.
				int amount = BandAmount(w, band);
				if (fx == 1)
				{
					if (lightOn) GITD_Composite.AddLight(i, int(amount * strength));
				}
				else if (fx == 2)
				{
					if (lightOn) GITD_Composite.AddLight(i, -int(amount * strength));
				}
				else if (fx == 3)
				{
					// Shades of the band's own colour across the four lanes.
					Color bc = BandColor(w, band);
					int cov = int(96 * strength);
					sec.SetGlowColor(Sector.floor, GITD_Palette.Scale(bc, 0.55 * strength));
					sec.SetGlowHeight(Sector.floor, cov);
					sec.SetGlowColor(Sector.ceiling, GITD_Palette.Scale(bc, 0.85 * strength));
					sec.SetGlowHeight(Sector.ceiling, cov);
					sec.SetFlatGlowColor(Sector.floor, GITD_Palette.Scale(bc, 0.40 * strength));
					sec.SetFlatGlowHeight(Sector.floor, cov);
					sec.SetFlatGlowColor(Sector.ceiling, GITD_Palette.Scale(bc, 0.70 * strength));
					sec.SetFlatGlowHeight(Sector.ceiling, cov);
				}
				else if (fx == 4)
				{
					sonarHere = true;
					sonarGlow[i] = max(sonarGlow[i], strength);
				}

				let act = BandAction(w, band);
				if (act) act.OnSector(self, sec, i, band, strength);

				for (int e = 0; e < ssEffects.Size(); e++)
					ssEffects[e].SectorPass(sec, i, band, strength);
			}

			// Sonar decays whether or not a band is near, so it runs outside
			// the wave loop. It is an ABSOLUTE statement about what the room's
			// level is, not a nudge, so it takes the override channel.
			if (anySonar)
			{
				if (!sonarHere)
					sonarGlow[i] = max(sonarGlow[i] - 1.0 / sonarFade, 0.0);
				if (sonarGlow[i] > 0.0 || sonarHere)
				{
					int sbase = GITD_Composite.BaseLight(i);
					GITD_Composite.OverrideLight(i,
						int(sonarFloor + (sbase - sonarFloor) * sonarGlow[i]));
				}
			}

			if (!touched)
			{
				// Nothing to declare. The compositor hands the sector's light
				// back to the engine on its own, so there is no "put it back"
				// to do here.
				for (int e = 0; e < ssEffects.Size(); e++) ssEffects[e].SectorRest(sec, i);
			}
		}

		ApplySweepToActors();
	}

	// The band meets the monsters.
	//
	// Sectors are a coarse grid; a monster is a point, so this is the sharper
	// of the two passes and the one that can actually change a fight. Off by
	// default because it walks the thinker list every tic.
	void ApplySweepToActors()
	{
		bool want = CVar.FindCVar("gitd_ss_actors").GetBool();
		if (!want)
		{
			for (int e = 0; e < ssEffects.Size(); e++)
				if (ssEffects[e].WantsActors()) { want = true; break; }
		}
		if (!want)
		{
			for (int wi = 0; wi < waves.Size() && !want; wi++)
			{
				let w = waves[wi];
				if (!w || !w.alive || !w.running) continue;
				for (int b = 0; b < w.bandFx.Size(); b++)
				{
					let act = BandAction(w, b);
					if (act && act.WantsActors()) { want = true; break; }
					if (w.bandFx[b] >= 5 && w.bandFx[b] <= 7) { want = true; break; }
				}
			}
		}
		if (!want) return;

		let pmo = players[consoleplayer].mo;
		ThinkerIterator it = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bISMONSTER || a.health <= 0) continue;
			bool touched = false;

			for (int wi = 0; wi < waves.Size(); wi++)
			{
				let w = waves[wi];
				if (!w || !w.alive || !w.running) continue;

				double reach = max(w.thickness, 1.0) * 3.0;
				int band;
				double strength;
				[band, strength] = WaveNearest(w, WaveDistance(w, a.pos), reach);
				if (band < 0) continue;
				touched = true;

				int fx = BandFx(w, band);
				if (fx == 5)
				{
					// Wake it. The wave is a noise as far as the AI cares.
					if (!a.target && pmo)
					{
						a.target = pmo;
						if (a.SeeState) a.SetState(a.SeeState);
					}
				}
				else if (fx == 6)
				{
					GITD_SweepMark.Set(a, band, strength);
				}
				else if (fx == 7)
				{
					a.Speed = a.default.Speed * 0.5;
					GITD_SweepMark.Set(a, band, strength);
				}

				let act = BandAction(w, band);
				if (act) act.OnActor(self, a, band, strength);

				for (int e = 0; e < ssEffects.Size(); e++)
					ssEffects[e].ActorPass(a, band, strength);
			}

			// Restore anything a band did to it. A monster left at half speed
			// because the wave moved on is a bug you would spend an evening
			// chasing.
			if (!touched && a.Speed != a.default.Speed && GITD_SweepMark.Age(a) > 35)
				a.Speed = a.default.Speed;
		}
	}

	// Any setpiece holding sectors has to restate its tint this tic. See
	// GITD_Setpiece.Republish.
	void SSRepublish()
	{
		for (int i = 0; i < ssActObj.Size(); i++)
		{
			let sp = GITD_Setpiece(ssActObj[i]);
			if (sp) sp.Republish();
		}
	}

	// ---- Triggers -------------------------------------------------------
	//
	// An event trigger is the single biggest change to how the sweep reads.
	// Free-running, it is weather. Fired by a kill, it is the room reacting
	// to something you did.

	void SSCheckTriggers()
	{
		if (!CVar.FindCVar("gitd_ss_enabled").GetBool()) return;
		int trigger = CVar.FindCVar("gitd_ss_trigger").GetInt();
		if (trigger == 0) return;

		if (trigger == 3)
		{
			// The rising edge of the trigger pull, not the shot. GZDoom has
			// no "weapon fired" event, and an edge means one wave per pull
			// rather than a solid wall of them out of a chaingun.
			let pmo = players[consoleplayer].mo;
			bool down = pmo && pmo.player && (pmo.player.cmd.buttons & BT_ATTACK);
			if (down && !lastAttackDown)
			{
				if (pmo) { lastShotPos = pmo.pos; haveShot = true; }
				SSStartPass();
			}
			lastAttackDown = down;
		}
		else if (trigger == 4)
		{
			if (level.found_secrets > lastSecrets) SSStartPass();
			lastSecrets = level.found_secrets;
		}
	}

	override void WorldThingDied(WorldEvent e)
	{
		if (!e.Thing || !e.Thing.bISMONSTER) return;
		lastKillPos = e.Thing.pos;
		haveKill = true;
		if (CVar.FindCVar("gitd_ss_trigger").GetInt() == 1) SSStartPass();
	}

	override void WorldThingDamaged(WorldEvent e)
	{
		if (CVar.FindCVar("gitd_ss_trigger").GetInt() != 2) return;
		if (!e.Thing || !e.Thing.player) return;
		if (e.Damage <= 0) return;
		SSStartPass();
	}

	void Apply()
	{
		if (!CVar.FindCVar("gitd_enabled").GetBool())
		{
			ClearAll();
			return;
		}

		int preset = CVar.FindCVar("gitd_preset").GetInt();

		wb.Step(preset);
		wt.Step(preset);
		cg.Step(preset);
		fg.Step(preset);

		// Bleed: wall bottom meets the floor, wall top meets the ceiling,
		// and the two wall halves meet each other mid-wall.
		Color wbCol = BleedToward(wb.outColor, fg.outColor, wt.outColor, wb.GetBool("_bleed"));
		Color wtCol = BleedToward(wt.outColor, cg.outColor, wb.outColor, wt.GetBool("_bleed"));
		Color cgCol = BleedToward(cg.outColor, wt.outColor, wt.outColor, cg.GetBool("_bleed"));
		Color fgCol = BleedToward(fg.outColor, wb.outColor, wb.outColor, fg.GetBool("_bleed"));

		bool wbOn = wb.GetBool("_enabled");
		bool wtOn = wt.GetBool("_enabled");
		bool cgOn = cg.GetBool("_enabled");
		bool fgOn = fg.GetBool("_enabled");

		int wbCov = wb.GetInt("_coverage"), wbFall = wb.GetInt("_falloff");
		int wtCov = wt.GetInt("_coverage"), wtFall = wt.GetInt("_falloff");
		int cgCov = cg.GetInt("_coverage"), cgFall = cg.GetInt("_falloff");
		int fgCov = fg.GetInt("_coverage"), fgFall = fg.GetInt("_falloff");

		// A preset can carry shape as well as colour. Without this, something
		// like a Tron look could not be saved at all -- thin bright seams are
		// a coverage and falloff decision, and a colour-only preset would
		// leave them to whatever the lanes happened to be set to.
		double presetInten = -1;
		if (preset > 0 && CVar.FindCVar("gitd_pc_shape").GetBool())
		{
			int c = CVar.FindCVar("gitd_pc_coverage").GetInt();
			int f = CVar.FindCVar("gitd_pc_falloff").GetInt();
			presetInten = CVar.FindCVar("gitd_pc_intensity").GetFloat();
			wbCov = c; wtCov = c; cgCov = c; fgCov = c;
			wbFall = f; wtFall = f; cgFall = f; fgFall = f;
		}

		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			if (IsOverridden(i)) continue;

			Sector sec = level.Sectors[i];

			double wbI = (presetInten >= 0) ? presetInten : wb.outIntensity;
			double wtI = (presetInten >= 0) ? presetInten : wt.outIntensity;
			double cgI = (presetInten >= 0) ? presetInten : cg.outIntensity;
			double fgI = (presetInten >= 0) ? presetInten : fg.outIntensity;

			ApplyOne(sec,
				wbOn, wbCol, wbCov, wbFall, wbI * wb.AnimFactor(sec, mapCentre),
				wtOn, wtCol, wtCov, wtFall, wtI * wt.AnimFactor(sec, mapCentre),
				cgOn, cgCol, cgCov, cgFall, cgI * cg.AnimFactor(sec, mapCentre),
				fgOn, fgCol, fgCov, fgFall, fgI * fg.AnimFactor(sec, mapCentre));
		}
	}

	void ClearAll()
	{
		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			if (IsOverridden(i)) continue;
			ApplyOne(level.Sectors[i],
				false, Color(0,0,0,0), 0, 0, 1.0,
				false, Color(0,0,0,0), 0, 0, 1.0,
				false, Color(0,0,0,0), 0, 0, 1.0,
				false, Color(0,0,0,0), 0, 0, 1.0);
		}
	}

	// The single place any of this reaches the engine. Shared by the map
	// default and per-sector overrides so the two cannot drift.
	static void ApplyOne(Sector sec,
		bool wbOn, color wbCol, int wbCov, int wbFall, double wbInten,
		bool wtOn, color wtCol, int wtCov, int wtFall, double wtInten,
		bool cgOn, color cgCol, int cgCov, int cgFall, double cgInten,
		bool fgOn, color fgCol, int fgCov, int fgFall, double fgInten)
	{
		// wb -- wall bottom, driven by the floor plane
		if (wbOn)
		{
			sec.SetGlowColor(Sector.floor, wbCol);
			sec.SetGlowHeight(Sector.floor, wbCov);
			sec.SetGlowFalloff(Sector.floor, wbFall);
			sec.SetGlowIntensity(Sector.floor, wbInten);
		}
		else
		{
			sec.SetGlowColor(Sector.floor, Color(0,0,0,0));
			sec.SetGlowHeight(Sector.floor, 0);
		}

		// wt -- wall top, driven by the ceiling plane
		if (wtOn)
		{
			sec.SetGlowColor(Sector.ceiling, wtCol);
			sec.SetGlowHeight(Sector.ceiling, wtCov);
			sec.SetGlowFalloff(Sector.ceiling, wtFall);
			sec.SetGlowIntensity(Sector.ceiling, wtInten);
		}
		else
		{
			sec.SetGlowColor(Sector.ceiling, Color(0,0,0,0));
			sec.SetGlowHeight(Sector.ceiling, 0);
		}

		// cg -- ceiling's own surface
		if (cgOn)
		{
			sec.SetFlatGlowColor(Sector.ceiling, cgCol);
			sec.SetFlatGlowHeight(Sector.ceiling, cgCov);
			sec.SetFlatGlowFalloff(Sector.ceiling, cgFall);
			sec.SetFlatGlowIntensity(Sector.ceiling, cgInten);
		}
		else
		{
			sec.SetFlatGlowColor(Sector.ceiling, Color(0,0,0,0));
			sec.SetFlatGlowHeight(Sector.ceiling, 0);
		}

		// fg -- floor's own surface
		if (fgOn)
		{
			sec.SetFlatGlowColor(Sector.floor, fgCol);
			sec.SetFlatGlowHeight(Sector.floor, fgCov);
			sec.SetFlatGlowFalloff(Sector.floor, fgFall);
			sec.SetFlatGlowIntensity(Sector.floor, fgInten);
		}
		else
		{
			sec.SetFlatGlowColor(Sector.floor, Color(0,0,0,0));
			sec.SetFlatGlowHeight(Sector.floor, 0);
		}
	}
}

// Restores every glow cvar to its default. Presets are left alone -- this
// resets the player's own choices, which is what "defaults" means here.
class GITD_ResetHandler : EventHandler
{
	static void Rst(string name)
	{
		CVar c = CVar.FindCVar(name);
		if (c) c.ResetToDefault();
	}

	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.name != "gitd_reset") return;

		static const string lanes[] = { "gitd_wb", "gitd_wt", "gitd_cg", "gitd_fg" };
		for (int i = 0; i < 4; i++)
		{
			string p = lanes[i];
			CVar.FindCVar(p .. "_enabled").ResetToDefault();
			for (int c = 1; c <= 8; c++) CVar.FindCVar(p .. "_c" .. c).ResetToDefault();
			CVar.FindCVar(p .. "_slots").ResetToDefault();
			CVar.FindCVar(p .. "_random").ResetToDefault();
			CVar.FindCVar(p .. "_pattern").ResetToDefault();
			CVar.FindCVar(p .. "_speed").ResetToDefault();
			CVar.FindCVar(p .. "_bleed").ResetToDefault();
			CVar.FindCVar(p .. "_coverage").ResetToDefault();
			CVar.FindCVar(p .. "_falloff").ResetToDefault();
			CVar.FindCVar(p .. "_intensity").ResetToDefault();
			CVar.FindCVar(p .. "_saturation").ResetToDefault();
			CVar.FindCVar(p .. "_anim").ResetToDefault();
			CVar.FindCVar(p .. "_anim_speed").ResetToDefault();
			CVar.FindCVar(p .. "_anim_length").ResetToDefault();
			CVar.FindCVar(p .. "_anim_depth").ResetToDefault();
			CVar.FindCVar(p .. "_anim_sharp").ResetToDefault();
			CVar.FindCVar(p .. "_anim_phase").ResetToDefault();
		}
		static const string sweeps[] = { "gitd_ss_enabled", "gitd_ss_shape",
			"gitd_ss_count", "gitd_ss_origin", "gitd_ss_light_mode",
			"gitd_ss_light_amount", "gitd_ss_intensity", "gitd_ss_thickness",
			"gitd_ss_softness", "gitd_ss_speed", "gitd_ss_range",
			"gitd_ss_pingpong" };
		for (int i = 0; i < 12; i++) CVar.FindCVar(sweeps[i]).ResetToDefault();
		for (int c = 1; c <= 8; c++) CVar.FindCVar("gitd_ss_c" .. c).ResetToDefault();
		for (int c = 1; c <= 8; c++) Rst("gitd_ss_speed" .. c);
		for (int c = 1; c <= 8; c++) Rst("gitd_ss_amount" .. c);
		Rst("gitd_ss_spin"); Rst("gitd_ss_spin_radius"); Rst("gitd_ss_spin_colors");
		Rst("gitd_ss_light");
		for (int g = 1; g <= 7; g++) CVar.FindCVar("gitd_ss_gap" .. g).ResetToDefault();

		// Darkness, flashlight, numbers, pickup cones.
		static const string rest[] = {
			"gitd_enabled", "gitd_preset",
			// The sweep's behaviour set arrived after the sweeps[] list above
			// and was never added to it -- so "Reset EVERYTHING" put the
			// geometry back and left the conduct: a sweep still firing on
			// every kill, still slowing monsters, still driven by health.
			"gitd_ss_direction", "gitd_ss_trigger", "gitd_ss_drive",
			"gitd_ss_health_speed", "gitd_ss_drift", "gitd_ss_trail",
			"gitd_ss_actors", "gitd_ss_sonar_floor", "gitd_ss_sonar_fade",
			"gitd_ss_perband", "gitd_ss_demo",
			"gitd_dd_enabled", "gitd_dd_noflash", "gitd_bloom_forced",
			"ddz_mode", "ddz_preset", "ddz_desat", "ddz_skymode", "ddz_lighting",
			"ddz_fog", "ddz_minlight", "ddz_pregain", "ddz_postgain",
			"ddz_fl_pos", "ddz_fl_quality", "ddz_fl_type",
			"fl_enabled", "fl_mount", "fl_range", "fl_intensity", "fl_inner",
			"fl_outer", "fl_falloff", "fl_density", "fl_dust", "fl_dust_scale",
			"fl_dust_drift", "fl_slots", "fl_random", "fl_pattern", "fl_speed",
			"fl_bounce", "fl_allowflip", "fl_agitate", "fl_model",
			"gitd_neon_enabled", "gitd_neon_style", "gitd_neon_scale",
			"gitd_neon_color", "gitd_neon_life", "gitd_neon_killcount",
			"gitd_neon_kc_digits", "gitd_neon_kc_linger", "gitd_neon_kc_place",
			"gitd_neon_damage", "gitd_neon_dmg_mode", "gitd_neon_dmg_window",
			"gitd_neon_glow_reach", "gitd_neon_glow_strength",
			"gitd_pc_shape", "gitd_pc_hue", "gitd_pc_sat", "gitd_pc_val",
			"gitd_pc_satvar", "gitd_pc_valvar", "gitd_pc_intensity",
			"gitd_pc_coverage", "gitd_pc_falloff", "gitd_pc_spread" };
		for (int i = 0; i < rest.Size(); i++) Rst(rest[i]);
		for (int c = 1; c <= 8; c++) Rst("fl_c" .. c);

		// Colour holds, the colour law, and the ambushes -- newer systems,
		// same promise: EVERYTHING means everything.
		static const string holdpre[] = { "gitd_wb", "gitd_wt", "gitd_cg", "gitd_fg", "fl" };
		for (int p = 0; p < holdpre.Size(); p++)
			for (int c = 1; c <= 8; c++) Rst(holdpre[p] .. "_hold" .. c);
		static const string rnd[] = { "gitd_rnd_colors", "gitd_rnd_governor",
			"gitd_rnd_times", "gitd_rnd_patterns", "gitd_neon_draw" };
		for (int i = 0; i < rnd.Size(); i++) Rst(rnd[i]);
		static const string law[] = { "gitd_law_enabled", "gitd_law_lane",
			"gitd_law_strength", "gitd_law_rain_x", "gitd_law_rain_y",
			"gitd_law_rain_every", "gitd_law_rain_life" };
		for (int i = 0; i < law.Size(); i++) Rst(law[i]);
		for (int c = 1; c <= 8; c++) Rst("gitd_law_fx" .. c);
		static const string amb[] = { "gitd_ambush_enabled", "gitd_ambush_ambient",
			"gitd_ambush_period", "gitd_ambush_chance", "gitd_ambush_spacing",
			"gitd_ambush_radius", "gitd_ambush_budget", "gitd_ambush_tierup",
			"gitd_ambush_tier", "gitd_ambush_timer", "gitd_ambush_color",
			"gitd_ambush_tint", "gitd_ambush_light", "gitd_ambush_desat",
			"gitd_ambush_speed", "gitd_ambush_badge", "gitd_ambush_class",
			"gitd_ambush_wall", "gitd_ambush_gap", "gitd_ambush_gap_drift" };
		for (int i = 0; i < amb.Size(); i++) Rst(amb[i]);
		for (int b = 1; b <= 8; b++) { Rst("gitd_ss_fx" .. b); Rst("gitd_ss_script" .. b); }

		// Bloom and exposure belong to the ENGINE, not to this mod, so they
		// survived every previous "reset to defaults" -- which is exactly how
		// you end up with a menu button that does not fix the thing you broke.
		// The page offers them, so the reset owes them.
		static const string engine[] = {
			"gl_bloom", "gl_bloom_threshold", "gl_bloom_knee", "gl_bloom_amount",
			"gl_bloom_anamorphic", "gl_bloom_anamorphic_ratio",
			"gl_bloom_chromatic", "gl_bloom_tint_r", "gl_bloom_tint_g",
			"gl_bloom_tint_b", "gl_exposure_scale", "gl_exposure_min",
			"gl_exposure_base", "gl_exposure_speed", "gl_fogmode" };
		for (int i = 0; i < engine.Size(); i++) Rst(engine[i]);

		Console.Printf("\c[Gold]All Glow In The Dark settings reset to defaults, bloom included.");
	}
}


// ---------------------------------------------------------------------------
// Preset customisation.
//
// MENUDEF binds to fixed cvar names, so a menu cannot say "edit whichever
// preset happens to be selected". The way around that is a single working
// set the menu always edits, loaded from the selected preset each time the
// selection changes. Save copies the working set into that preset's own
// slots; restore drops your version and reloads the shipped one.
// ---------------------------------------------------------------------------

class GITD_PresetCustomiser : StaticEventHandler
{
	int lastPreset;

	override void WorldLoaded(WorldEvent e)
	{
		lastPreset = -1;   // force a load on the first tick
	}

	override void WorldTick()
	{
		int preset = CVar.FindCVar("gitd_preset").GetInt();
		if (preset != lastPreset)
		{
			lastPreset = preset;
			if (preset > 0)
			{
				LoadWorkingSet(preset);
				// And the rest of the environment -- rhythm, sweeps,
				// darkness. A preset with no profile writes nothing here and
				// stays colours-only, exactly as it was.
				GITD_PresetProfile.Apply(preset);
			}
		}
	}

	static void SetF(string name, double v) { CVar.FindCVar(name).SetFloat(v); }
	static void SetI(string name, int v) { CVar.FindCVar(name).SetInt(v); }

	// Pull a preset into the working set: your saved version if you have one,
	// otherwise whatever GITD_Presets ships.
	static void LoadWorkingSet(int preset)
	{
		string p = "gitd_p" .. preset;

		if (CVar.FindCVar(p .. "_custom").GetBool())
		{
			SetF("gitd_pc_hue",     CVar.FindCVar(p .. "_hue").GetFloat());
			SetF("gitd_pc_spread",  CVar.FindCVar(p .. "_spread").GetFloat());
			SetF("gitd_pc_sat",     CVar.FindCVar(p .. "_sat").GetFloat());
			SetF("gitd_pc_satvar",  CVar.FindCVar(p .. "_satvar").GetFloat());
			SetF("gitd_pc_val",     CVar.FindCVar(p .. "_val").GetFloat());
			SetF("gitd_pc_valvar",  CVar.FindCVar(p .. "_valvar").GetFloat());
			CVar.FindCVar("gitd_pc_shape").SetInt(CVar.FindCVar(p .. "_shape").GetBool() ? 1 : 0);
			SetI("gitd_pc_coverage",CVar.FindCVar(p .. "_coverage").GetInt());
			SetI("gitd_pc_falloff", CVar.FindCVar(p .. "_falloff").GetInt());
			SetF("gitd_pc_intensity",CVar.FindCVar(p .. "_intensity").GetFloat());
		}
		else
		{
			double h, sp, sb, sv, vb, vv;
			GITD_Presets.Params(preset, h, sp, sb, sv, vb, vv);
			SetF("gitd_pc_hue", h);
			SetF("gitd_pc_spread", sp);
			SetF("gitd_pc_sat", sb);
			SetF("gitd_pc_satvar", sv);
			SetF("gitd_pc_val", vb);
			SetF("gitd_pc_valvar", vv);
			CVar.FindCVar("gitd_pc_shape").SetInt(0);
		}
	}

	override void NetworkProcess(ConsoleEvent e)
	{
		int preset = CVar.FindCVar("gitd_preset").GetInt();
		if (preset <= 0)
		{
			if (e.name == "gitd_preset_save" || e.name == "gitd_preset_restore")
				Console.Printf("No preset selected.");
			return;
		}
		string p = "gitd_p" .. preset;

		if (e.name == "gitd_preset_save")
		{
			SetF(p .. "_hue",      CVar.FindCVar("gitd_pc_hue").GetFloat());
			SetF(p .. "_spread",   CVar.FindCVar("gitd_pc_spread").GetFloat());
			SetF(p .. "_sat",      CVar.FindCVar("gitd_pc_sat").GetFloat());
			SetF(p .. "_satvar",   CVar.FindCVar("gitd_pc_satvar").GetFloat());
			SetF(p .. "_val",      CVar.FindCVar("gitd_pc_val").GetFloat());
			SetF(p .. "_valvar",   CVar.FindCVar("gitd_pc_valvar").GetFloat());
			CVar.FindCVar(p .. "_shape").SetInt(CVar.FindCVar("gitd_pc_shape").GetBool() ? 1 : 0);
			SetI(p .. "_coverage", CVar.FindCVar("gitd_pc_coverage").GetInt());
			SetI(p .. "_falloff",  CVar.FindCVar("gitd_pc_falloff").GetInt());
			SetF(p .. "_intensity",CVar.FindCVar("gitd_pc_intensity").GetFloat());
			CVar.FindCVar(p .. "_custom").SetInt(1);
			Console.Printf("Saved over preset: %s", GITD_Presets.Name(preset));
		}
		else if (e.name == "gitd_preset_restore")
		{
			CVar.FindCVar(p .. "_custom").SetInt(0);
			LoadWorkingSet(preset);
			Console.Printf("Restored preset defaults: %s", GITD_Presets.Name(preset));
		}
	}
}
