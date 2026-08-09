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
	double animClock;   // this lane's own animation clock

	// Resolved once per tic, read by the handler when applying.
	Color outColor;
	double outIntensity;

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
		if (GetBool("_random")) return GITD_Palette.RandomColor();

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
		// A preset always walks all eight slots -- its 32 colours are the
		// point of it, so the lane's own slot count does not narrow them.
		int count = (preset > 0) ? 8 : clamp(GetInt("_slots"), 1, 8);

		phase += speed;
		if (phase >= 1.0)
		{
			phase -= 1.0;
			slotIndex = (slotIndex + 1) % count;
			fromCol = toCol;
			int nextSlot = (pattern == 4 && (slotIndex % 2) == 1)
				? (slotIndex + count - 1) % count
				: (slotIndex + 1) % count;
			toCol = (preset > 0) ? GITD_Presets.SlotColor(preset, laneIndex, nextSlot) : SlotColor(nextSlot);
		}

		switch (pattern)
		{
			default:
			case 0: // Snap
				outColor = fromCol;
				break;
			case 1: // Fade
			case 4: // Ping-pong: same blend, different slot order
			{
				double t = 0.5 - 0.5 * cos(phase * 360.0);
				outColor = GITD_Palette.Lerp(fromCol, toCol, t);
				break;
			}
			case 2: // Flash -- snap to the new colour, decay back
			{
				double t = max(0.0, 1.0 - phase * 3.0);
				outColor = GITD_Palette.Lerp(fromCol, toCol, t);
				break;
			}
			case 3: // Breathe -- dip through darkness between colours
			{
				double t = 0.5 - 0.5 * cos(phase * 360.0);
				outColor = GITD_Palette.Lerp(fromCol, toCol, t);
				outColor = GITD_Palette.Scale(outColor, 0.35 + 0.65 * abs(cos(phase * 360.0)));
				break;
			}
		}

		outColor = GITD_Palette.Saturate(outColor, GetFloat("_saturation"));
		outIntensity = GetFloat("_intensity");

		animClock = (animClock + GetFloat("_anim_speed") / 35.0) % 1.0;
	}

	// This lane's animation multiplier for one sector. The streak: each
	// sector's phase is offset by where it sits, so a crest travels through
	// the map rather than everything pulsing together. Sharpness narrows
	// that crest -- at 1 it is a smooth wave, high values give the EKG
	// spike through an otherwise dark lane.
	double AnimFactor(Sector sec, Vector2 mapCentre)
	{
		int mode = GetInt("_anim");
		if (mode == 0) return 1.0;

		double wavelength = max(GetFloat("_anim_length"), 1.0);
		double depth = clamp(GetFloat("_anim_depth"), 0.0, 1.0);
		double sharp = max(GetFloat("_anim_sharp"), 1.0);

		Vector2 c = sec.centerspot;
		double dist;
		if (mode == 1)      dist = (c - mapCentre).Length();
		else if (mode == 2) dist = c.x;
		else if (mode == 3) dist = c.y;
		else                dist = sec.floorplane.ZatPoint(c);   // travels by height

		double ph = (animClock + GetFloat("_anim_phase") - dist / wavelength) % 1.0;
		if (ph < 0) ph += 1.0;

		double wave = 0.5 + 0.5 * sin(ph * 360.0);
		if (sharp > 1.0) wave = wave ** sharp;   // narrows the crest into a streak

		return (1.0 - depth) + depth * wave;
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
		// Blackout is the one preset that is deliberately not alive: it is
		// the absence of light, with only a hint of void purple so it does
		// not read as a rendering failure.
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
			int v = (slot % 4);
			if (v == 0) return Color(255, 0, 0, 0);
			if (v == 1) return Color(255, 6, 0, 10);
			if (v == 2) return Color(255, 0, 0, 4);
			return Color(255, 10, 0, 14);
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

	// Sweep: where the band currently sits, and which way it is going.
	double sweepPos;
	int sweepDir;
	Vector3 sweepOrigin;

	override void WorldLoaded(WorldEvent e)
	{
		// Turn bloom on the first time this mod is ever loaded. gl_bloom is
		// archived and ships off, so a fresh default alone never reaches
		// anyone who has run the engine before -- and without bloom the glow
		// looks flat and wrong out of the box. Done once, so if you turn it
		// off later it stays off.
		if (!CVar.FindCVar("gitd_bloom_forced").GetBool())
		{
			CVar.FindCVar("gl_bloom").SetInt(1);
			CVar.FindCVar("gitd_bloom_forced").SetInt(1);
		}

		overridden.Clear();

		wb = new("GITD_Lane"); wb.Init("gitd_wb", 0);
		wt = new("GITD_Lane"); wt.Init("gitd_wt", 1);
		cg = new("GITD_Lane"); cg.Init("gitd_cg", 2);
		fg = new("GITD_Lane"); fg.Init("gitd_fg", 3);

		ComputeMapCentre();
		sweepPos = 0;
		sweepDir = 1;
		sweepOrigin = (mapCentre.x, mapCentre.y, 0);
		Apply();
	}

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
		StepSectorSweep();

		// Sector Sweep takes over while it is on: the point of it is a dark
		// room with nothing in it but the travelling lines, so the lanes are
		// cleared rather than left glowing underneath.
		if (CVar.FindCVar("gitd_ss_enabled").GetBool())
		{
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

	double SSBandPos(int i)
	{
		// Each band trails the one before it by that band's gap, converted
		// from tics into distance at the current speed.
		double speed = CVar.FindCVar("gitd_ss_speed").GetFloat();
		double lag = 0;
		for (int g = 0; g < i; g++)
		{
			lag += CVar.FindCVar("gitd_ss_gap" .. (g + 1)).GetInt() * speed / 35.0;
		}
		return sweepPos - lag;
	}

	Color SSBandColor(int i)
	{
		// Color(int) does NOT convert on this engine -- it compiles and then
		// fails at load with "Return type Color mismatch with SInt4", which
		// leaves this function returning nothing usable and the colour it was
		// asked for silently unset. Build the Color from its bytes instead;
		// that is unambiguous and needs no implicit conversion.
		int packed = CVar.FindCVar("gitd_ss_c" .. (i + 1)).GetInt();
		return Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);
	}

	void StepSectorSweep()
	{
		if (!CVar.FindCVar("gitd_ss_enabled").GetBool())
		{
			level.ClearSweep();
			return;
		}

		int shape = CVar.FindCVar("gitd_ss_shape").GetInt();
		int count = clamp(CVar.FindCVar("gitd_ss_count").GetInt(), 1, 8);

		// Where the bands are measured from.
		int originMode = CVar.FindCVar("gitd_ss_origin").GetInt();
		if (originMode == 2 && players[consoleplayer].mo)
		{
			sweepOrigin = players[consoleplayer].mo.pos;
		}
		else if (originMode == 1)
		{
			// Where you spawned. In E1M1 that is the door behind you, so a
			// ring expands outward from the way you came in.
			let pmo = players[consoleplayer].mo;
			if (pmo && sweepOrigin == (0, 0, 0)) sweepOrigin = pmo.pos;
		}
		else
		{
			sweepOrigin = (mapCentre.x, mapCentre.y, 0);
		}

		double speed = CVar.FindCVar("gitd_ss_speed").GetFloat();
		double range = max(CVar.FindCVar("gitd_ss_range").GetInt(), 1);
		bool pingpong = CVar.FindCVar("gitd_ss_pingpong").GetBool();

		sweepPos += sweepDir * speed / 35.0;
		if (pingpong)
		{
			if (sweepPos >= range) { sweepPos = range; sweepDir = -1; }
			else if (sweepPos <= 0) { sweepPos = 0; sweepDir = 1; }
		}
		else if (sweepPos >= range)
		{
			// Wrap far enough back that the whole train clears before the
			// leader restarts, or bands would overlap at the origin.
			sweepPos = 0;
		}

		double thickness = CVar.FindCVar("gitd_ss_thickness").GetInt();
		double softness = CVar.FindCVar("gitd_ss_softness").GetFloat();
		double intensity = CVar.FindCVar("gitd_ss_intensity").GetFloat();

		level.SetSweepOrigin(shape, sweepOrigin, count);
		for (int i = 0; i < count; i++)
		{
			double pos = SSBandPos(i);
			// A band that has not started yet is parked far away rather than
			// drawn at the origin.
			if (pos < 0) pos = -100000;
			level.SetSweepBand(i, pos, thickness, softness, SSBandColor(i), intensity);
		}
	}

	// What the sweep does to the rooms it passes through. This is per-sector
	// by nature -- light level is a sector property -- so it is necessarily
	// coarser than the band itself, which is per-pixel.
	void ApplySectorSweepEffects()
	{
		int lightMode = CVar.FindCVar("gitd_ss_light_mode").GetInt();
		if (lightMode == 0) return;

		int shape = CVar.FindCVar("gitd_ss_shape").GetInt();
		int count = clamp(CVar.FindCVar("gitd_ss_count").GetInt(), 1, 8);
		double thickness = max(CVar.FindCVar("gitd_ss_thickness").GetInt(), 1);
		int amount = CVar.FindCVar("gitd_ss_light_amount").GetInt();

		// Re-colour mode: whichever band is nearest drives the four lanes to
		// shades of its own colour, so a green sweep leaves 32 cooperating
		// greens behind it.
		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			if (IsOverridden(i)) continue;
			Sector sec = level.Sectors[i];

			Vector2 c = sec.centerspot;
			double dist;
			if (shape == 1)      dist = (c - sweepOrigin.xy).Length();
			else if (shape == 2) dist = abs(c.x - sweepOrigin.x);
			else if (shape == 3) dist = abs(c.y - sweepOrigin.y);
			else                 dist = (c - sweepOrigin.xy).Length();

			// Find the closest band to this sector, if any is near enough.
			double nearest = 1e9;
			int nearestBand = -1;
			for (int b = 0; b < count; b++)
			{
				double d = abs(dist - SSBandPos(b));
				if (d < nearest) { nearest = d; nearestBand = b; }
			}

			if (nearestBand < 0 || nearest > thickness * 3.0) continue;

			// Strength falls off with distance from the band, so the effect
			// travels with it rather than switching on and off.
			double strength = 1.0 - clamp(nearest / (thickness * 3.0), 0.0, 1.0);

			if (lightMode == 1)
			{
				sec.SetLightLevel(clamp(sec.lightlevel + int(amount * strength), 0, 255));
			}
			else if (lightMode == 2)
			{
				sec.SetLightLevel(clamp(sec.lightlevel - int(amount * strength), 0, 255));
			}
			else if (lightMode == 3)
			{
				// Shades of the band's own colour across the four lanes.
				Color bc = SSBandColor(nearestBand);
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
		}
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
		for (int g = 1; g <= 7; g++) CVar.FindCVar("gitd_ss_gap" .. g).ResetToDefault();

		Console.Printf("Glow settings reset to defaults.");
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
			if (preset > 0) LoadWorkingSet(preset);
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
