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
	// THE OPPOSITE HUE AT THE SAME BRIGHTNESS.
	//
	// Not 255-minus-each-byte, which is what "opposite colour" usually gets
	// implemented as and is wrong for this: inverting the bytes also inverts
	// VALUE, so a dark red glow hands back a pale cyan mist. Two things change
	// when only one was asked for, and the result reads as a different
	// brightness rather than a different colour.
	//
	// Rotating the hue 180 degrees and keeping saturation and value is what
	// "complement" means to an eye. It is what makes cyan light in orange air
	// read as two distances rather than as one wash and one glare.
	static Color Complement(Color c)
	{
		double r = c.r / 255.0, g = c.g / 255.0, b = c.b / 255.0;
		double mx = max(r, max(g, b)), mn = min(r, min(g, b));
		double d = mx - mn;

		// Grey has no hue to oppose, so there is nothing honest to return but
		// the same grey. Rotating an undefined hue would produce a colour out
		// of nothing and make the mode look broken on a monochrome preset.
		if (d < 0.0001) return c;

		double h;
		if (mx == r)      h = 60.0 * (((g - b) / d) % 6.0);
		else if (mx == g) h = 60.0 * (((b - r) / d) + 2.0);
		else              h = 60.0 * (((r - g) / d) + 4.0);
		h = (h + 180.0) % 360.0;
		if (h < 0) h += 360.0;

		double s = (mx <= 0.0) ? 0.0 : d / mx;
		double v = mx;

		double hh = h / 60.0;
		double ff = hh - floor(hh);
		double p = v * (1.0 - s);
		double q = v * (1.0 - s * ff);
		double t = v * (1.0 - s * (1.0 - ff));

		double nr, ng, nb;
		int i = int(floor(hh)) % 6;
		if      (i == 0) { nr = v; ng = t; nb = p; }
		else if (i == 1) { nr = q; ng = v; nb = p; }
		else if (i == 2) { nr = p; ng = v; nb = t; }
		else if (i == 3) { nr = p; ng = q; nb = v; }
		else if (i == 4) { nr = t; ng = p; nb = v; }
		else             { nr = v; ng = p; nb = q; }

		return Color(255, int(clamp(nr * 255.0, 0.0, 255.0)),
		                  int(clamp(ng * 255.0, 0.0, 255.0)),
		                  int(clamp(nb * 255.0, 0.0, 255.0)));
	}

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
			return GITD_Presets.FromHSV(base + frandom(-25, 25), frandom(0.75, 1.0), frandom(0.7, 1.0));
		}
		if (mode == 2)
		{
			// Complementary: one of two opposed hues, so a room reads as two
			// colours arguing rather than eight colours mumbling.
			double base = double((level.maptime / 2100) * 53 % 360);
			if (random(0, 1) == 1) base += 180;
			return GITD_Presets.FromHSV(base + frandom(-12, 12), frandom(0.8, 1.0), frandom(0.75, 1.0));
		}
		if (mode == 3)
		{
			// Neon only: full saturation, high value, any hue. Never muddy.
			return GITD_Presets.FromHSV(frandom(0, 360), 1.0, frandom(0.85, 1.0));
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

		// RED ALERT is written out slot by slot rather than generated,
		// because the thing it is trying to say cannot be said as a hue
		// range. A generated palette spreads eight related colours evenly
		// across a lane; this needs the CEILING to be pure black for four
		// minutes and then a lamp for forty seconds, which is a sequence,
		// not a spread. Same reason Blackout and Black and White are
		// literal: the generator is a good way to describe a scheme and no
		// way at all to describe an event.
		//
		// Read down a column and you get one surface's five minutes. Read
		// across and you get the room at one moment. The holds that pace it
		// are in GITD_PresetProfile.RedAlert, and the two tables have to be
		// read together -- a colour here means nothing without the seconds
		// it sits for.
		if (preset == 3)
		{
			static const int redAlert[] =
			{
				// wall bottom -- the corridor strip, and the whole story:
				// trip, three klaxon beats, sustain, decay, a long wait.
				0xFFE8C0, 0xFF1810, 0x380000, 0xFF1810,
				0x380000, 0xC81000, 0x6A1400, 0x2E1A00,

				// wall top -- the beacon's spill, deliberately three
				// seconds out of step with the ceiling so the two read as
				// one lamp turning rather than two lanes changing.
				0xFF3018, 0x200000, 0xFF3018, 0x200000,
				0xFF3018, 0x200000, 0x401008, 0x140800,

				// ceiling -- the beacon itself. Six alternating slots and
				// then black for four and a half minutes.
				0xFF0000, 0x0A0000, 0xFF0000, 0x0A0000,
				0xFF0000, 0x0A0000, 0x200000, 0x000000,

				// floor -- the deck. Everything the walls do, reflected,
				// darker and one beat slower.
				0xFFD0A0, 0x8A0800, 0xC01000, 0x8A0800,
				0x500400, 0x7A0C00, 0x3A0A00, 0x1A0E00
			};

			int packed = redAlert[clamp(lane, 0, 3) * 8 + clamp(slot, 0, 7)];
			return Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);
		}

		// LOW POWER. Not violet-for-mood: this is a facility, so the light it
		// has left is the light it was BUILT with. Dying sodium and
		// fluorescent go orange-grey as they fail, with one cold cast off the
		// emergency circuit that is still nominally alive. Nothing here is
		// saturated, because there is no energy left to be colourful with.
		//
		// The rolling glow does most of the work in this preset, so the
		// palette deliberately holds still underneath it -- eight near
		// neighbours rather than eight colours. What moves is the light, not
		// the hue, which is what a brownout actually looks like.
		if (preset == 2)
		{
			static const int lowPower[] =
			{
				// wall bottom -- the corridor strip, lowest and warmest
				0x4A3208, 0x3E2A06, 0x523A0C, 0x2E2004,
				0x463006, 0x38280A, 0x4E3608, 0x281C04,

				// wall top -- further from the floor lamps, colder
				0x2A2410, 0x221E0C, 0x302814, 0x1A160A,
				0x282210, 0x1E1A0C, 0x2C2612, 0x161208,

				// ceiling -- the emergency circuit, and the one cold thing
				0x141A26, 0x10141E, 0x18202C, 0x0C1018,
				0x121822, 0x0E1218, 0x161E28, 0x0A0C12,

				// floor -- what the walls spill onto, dimmest of all
				0x261A06, 0x1E1404, 0x2A1E08, 0x160E02,
				0x221806, 0x1A1204, 0x281C06, 0x120C02
			};

			int packed = lowPower[clamp(lane, 0, 3) * 8 + clamp(slot, 0, 7)];
			return Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);
		}

		// OMGWTF. Every lane in a different colour family, every slot a
		// different hue, nothing related to anything. This is the one preset
		// that exists because the system can, and the palette is written out
		// rather than generated for the same reason the others are: a hue
		// range produces eight RELATED colours, and relatedness is the one
		// thing this must not have.
		if (preset == 12)
		{
			static const int omg[] =
			{
				0xFF00E6, 0x00FF66, 0xFFD400, 0x6600FF,
				0x00E5FF, 0xFF3300, 0x99FF00, 0xFF0066,

				0x00FF66, 0xFFD400, 0x6600FF, 0x00E5FF,
				0xFF3300, 0x99FF00, 0xFF0066, 0xFF00E6,

				0x6600FF, 0x00E5FF, 0xFF3300, 0x99FF00,
				0xFF0066, 0xFF00E6, 0x00FF66, 0xFFD400,

				0xFF3300, 0x99FF00, 0xFF0066, 0xFF00E6,
				0x00FF66, 0xFFD400, 0x6600FF, 0x00E5FF
			};

			int packed = omg[clamp(lane, 0, 3) * 8 + clamp(slot, 0, 7)];
			return Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);
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

		return GITD_Presets.FromHSV(hue, sat, val);
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

	// The fog wake's lagging point -- see PushFogWake. haveWake exists so the
	// first tic of a map snaps it to the player instead of springing it in
	// from the origin, which would drag a channel across the whole level.
	Vector3 wakePos;
	bool haveWake;

	// Every live wave. The cvar-driven sweep is waves[0] and is rebuilt from
	// the cvars each tic; everything a script fires joins the same list. See
	// the Waves section below for why the eight-band shader limit does not
	// cap this.
	Array<GITD_Wave> waves;

	// What the world last did, remembered so an origin can point at it.
	Vector3 lastShotPos, lastKillPos;
	bool lastFogShotDown;   // rising edge for the muzzle ripple
	// Which lane slot the random fog tint was last rolled on, and the colour it
	// rolled. Initialised in WorldLoaded, not here -- ZScript rejects an
	// initialiser on a class field and the error it gives points at the '='
	// rather than saying so.
	int lastTintSlot;
	Color tintRandom;
	double alarmLevel;      // eased toward the target, never snapped
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

		// -1 rather than 0, so the first slot the lane happens to be on still
		// counts as a change and rolls a colour. Starting at 0 would leave the
		// random fog tint black until the lane advanced.
		lastTintSlot = -1;
		haveWake = false;   // snap to the player on the first tic of the map
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

		// THE RENDER SETTINGS ARE NOT PART OF THE LANE ARGUMENT.
		//
		// These used to live inside Apply(), which meant a live sweep with
		// underlay off took the ClearAll() branch below and nothing pushed
		// them that tic -- so the fog, the tornado, the darkness curve and
		// the band fill all froze at whatever they last held, in exactly the
		// configuration a sweep user reaches for. Turning gitd_enabled off did
		// the same thing one line into Apply().
		//
		// Freezing is worse than clearing: the effect keeps costing its full
		// per-fragment price while every slider that names it does nothing,
		// which is the same fault that once left eight beams standing in a room
		// after the grid was switched off.
		//
		// So they are hoisted above the argument entirely. Whether the LANES
		// run under a sweep is a question about lanes; what the fragment shader
		// is holding is not, and it needs an answer every single tic.
		GITD_Render.PushAll();
		level.SetGlowWaveOrigin(OriginFor(GITD_Render.GetI("gitd_wave_origin", 0)));
		PushFogWake();
		PushTornadoAnchor();
		PushFogTint();
		PushFogShot();
		PushFogDisplacers();
		PushGlowAlarm();

		if (anyWave)
		{
			// UNDERLAY. A live sweep used to CLEAR the lanes unconditionally,
			// on the reasoning that the point of a sweep is a dark room with
			// nothing in it but the travelling lines.
			//
			// That is one good look, and it was wrong as a rule. It made the
			// two flagship systems mutually exclusive -- you could have the
			// 4x8 or you could have sweeps, never both -- and it silently
			// broke every preset built around "a baseline the sweeps travel
			// over", because the baseline was being deleted every tic and the
			// palette work never appeared at all.
			//
			// Underlay on: the lanes run normally and the bands ride over
			// them, which is what makes a sweep read as something happening
			// TO a room rather than as the room's only content. Off restores
			// the original bare-lines look in one toggle.
			if (Underlay()) Apply();
			else ClearAll();
			ApplySectorSweepEffects();
		}
		else
		{
			Apply();
		}
	}

	// Do the glow lanes keep running underneath a live sweep? Defaults ON:
	// two systems that cannot coexist is the stranger arrangement, and it is
	// what every preset assumes.
	bool Underlay()
	{
		let cv = CVar.FindCVar("gitd_ss_underlay");
		return cv ? cv.GetBool() : true;
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

		// No far colours: an override is a claim on one sector's exact look,
		// so its glows stay the single colour the caller asked for. The
		// signature is left alone deliberately -- it is the documented entry
		// point for other mods.
		ApplyOne(sec,
			wbOn, wbCol, Color(0,0,0,0), wbCov, wbFall, wbInten,
			wtOn, wtCol, Color(0,0,0,0), wtCov, wtFall, wtInten,
			cgOn, cgCol, Color(0,0,0,0), cgCov, cgFall, cgInten,
			fgOn, fgCol, Color(0,0,0,0), fgCov, fgFall, fgInten);
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
	// This is a controller-side approximation: it moves whole lanes closer
	// together, which is a different thing from a gradient across the join.
	// Seamless corners does that part now -- both surfaces agree on a colour
	// AT the line and ramp away to their own. Bleed still earns its place
	// above it, because it decides how far apart the two lanes are before
	// anything is blended between them.
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
		w.bandShape.Clear(); w.bandThick.Clear(); w.bandDraw.Clear();
		for (int i = 0; i < w.subBands; i++)
		{
			w.bandPos.Push(WaveBandPos(w, i));
			w.bandFx.Push(WaveBandFx(w, i));
			Color c = WaveBandColor(w, i);
			w.bandCol.Push((c.r << 16) | (c.g << 8) | c.b);
			w.bandAct.Push(WaveBandAction(w, i));
			w.bandAmt.Push(WaveBandAmount(w, i));
			w.bandShape.Push(WaveBandShape(w, i));
			w.bandThick.Push(int(WaveBandThickness(w, i)));
			w.bandDraw.Push(WaveBandDraw(w, i));
		}
	}

	int BandShape(GITD_Wave w, int i)
	{
		return (i >= 0 && i < w.bandShape.Size()) ? w.bandShape[i] : w.shape;
	}

	int BandThick(GITD_Wave w, int i)
	{
		return (i >= 0 && i < w.bandThick.Size()) ? w.bandThick[i] : int(w.thickness);
	}

	int BandDraw(GITD_Wave w, int i)
	{
		return (i >= 0 && i < w.bandDraw.Size()) ? w.bandDraw[i] : 1;
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
		if (!w.cvarDriven) return 1.0;
		let lead = CVar.FindCVar("gitd_ss_speed1");
		let mine = CVar.FindCVar("gitd_ss_speed" .. (i + 1));
		if (!lead || !mine) return 1.0;
		double l = lead.GetFloat();
		if (l <= 0.0) return 1.0;
		return mine.GetFloat() / l;
	}

	double WaveBandPos(GITD_Wave w, int i)
	{
		if (!w.cvarDriven) return w.CalcBandPos(i);
		double lag = 0;
		for (int g = 0; g < i; g++)
			lag += CVar.FindCVar("gitd_ss_gap" .. (g + 1)).GetInt() * w.speed / 35.0;
		return w.pos * WaveBandSpeedScale(w, i) * (1.0 + w.drift * i) - lag;
	}

	// How hard band i pushes the light level. Per band, falling back to the
	// old single value for a scripted wave, which has no per-band table.
	// 1 add, 2 lift (reveal), 3 crush. A scripted wave adds, unless it says
	// otherwise, because that is what every existing caller expects.
	// 0 in the per-band slot means "use the wave's shared thickness", so a
	// preset that does not care sets nothing and behaves as it always did.
	double WaveBandThickness(GITD_Wave w, int i)
	{
		if (!w.cvarDriven) return w.thickness;
		let cv = CVar.FindCVar("gitd_ss_thick" .. (i + 1));
		if (!cv) return w.thickness;
		int t = cv.GetInt();
		return (t > 0) ? double(t) : w.thickness;
	}

	// 0 means "use the wave's shared shape". The engine has carried a per-band
	// shape since independence landed; this is what finally sets it to
	// anything, and it is what lets a ring and a rising plane share one train.
	int WaveBandShape(GITD_Wave w, int i)
	{
		if (!w.cvarDriven) return w.shape;
		let cv = CVar.FindCVar("gitd_ss_shape" .. (i + 1));
		if (!cv) return w.shape;
		int s = cv.GetInt();
		return (s > 0) ? s : w.shape;
	}

	int WaveBandDraw(GITD_Wave w, int i)
	{
		if (!w.cvarDriven) return 1;
		let cv = CVar.FindCVar("gitd_ss_draw" .. (i + 1));
		return cv ? clamp(cv.GetInt(), 1, 4) : 1;
	}

	int WaveBandAmount(GITD_Wave w, int i)
	{
		if (!w.cvarDriven)
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
			// CROSS-FADED, not stepped. Picking the nearest colour by phase
			// snaps at every segment boundary, and a rolodex that clicks is a
			// slideshow -- the colour has to arrive before you notice it left.
			// So the phase indexes a CONTINUOUS position in colour space and
			// the two neighbours are blended by the fraction between them.
			int n = clamp(w.spinColors, 2, 8);
			double t = w.SpinPhase() * n + i;
			int ia = int(floor(t)) % n;
			int ib = (ia + 1) % n;
			double f = t - floor(t);

			int pa = CVar.FindCVar("gitd_ss_c" .. (ia + 1)).GetInt();
			int pb = CVar.FindCVar("gitd_ss_c" .. (ib + 1)).GetInt();
			Color ca = Color(255, (pa >> 16) & 255, (pa >> 8) & 255, pa & 255);
			Color cb = Color(255, (pb >> 16) & 255, (pb >> 8) & 255, pb & 255);
			return GITD_Palette.Lerp(ca, cb, f);
		}
		if (!w.cvarDriven) return w.col;
		// Color(int) does NOT convert on this engine -- it compiles and then
		// fails at load with "Return type Color mismatch with SInt4", which
		// leaves this returning nothing usable and the colour silently unset.
		int packed = CVar.FindCVar("gitd_ss_c" .. (i + 1)).GetInt();
		return Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);
	}

	int WaveBandFx(GITD_Wave w, int i)
	{
		if (!w.cvarDriven) return w.fx;
		if (!CVar.FindCVar("gitd_ss_perband").GetBool())
			return CVar.FindCVar("gitd_ss_light_mode").GetInt();
		return CVar.FindCVar("gitd_ss_fx" .. (i + 1)).GetInt();
	}

	GITD_SweepAction WaveBandAction(GITD_Wave w, int i)
	{
		if (!w.cvarDriven) return w.sweepAction;
		if (!CVar.FindCVar("gitd_ss_perband").GetBool()) return null;
		return GITD_SweepAction.Resolve(CVar.FindCVar("gitd_ss_script" .. (i + 1)).GetString());
	}

	// ---- The ambient wave, rebuilt from cvars ---------------------------

	static bool CvB(string n, bool d)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetBool() : d;
	}

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
		return OriginFor(CVar.FindCVar("gitd_ss_origin").GetInt());
	}

	// Was SSAmbientOrigin's whole body, with the cvar read inline. The glow
	// wave wants the same six origins from its own cvar, and two copies of
	// this would be two places for "follows you" to mean something slightly
	// different -- which is exactly the drift the shared distance function
	// exists to prevent.
	Vector3 OriginFor(int mode)
	{
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
		if (mode == 6 && pmo)
		{
			// IN FRONT OF YOU. "Follows you" is the wrong anchor for anything
			// large, because you end up standing inside it and never see the
			// shape you asked for -- a tornado on your own head is a grey
			// screen. This puts it at arm's length in the direction you are
			// facing, so it is a thing in the room rather than a thing you
			// are wearing.
			//
			// Recomputed every tic, so it swings as you turn. That is correct
			// for placing something and looking at it, and wrong for anything
			// you then want to walk around -- for that, place it with mode 6,
			// read the position, and switch to a fixed point.
			double d = GITD_Render.GetF("gitd_origin_ahead", 320.0);
			return pmo.pos + (cos(pmo.angle) * d, sin(pmo.angle) * d, 0);
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
			ambient.cvarDriven = true;
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

	// ---- Dropped sweeps -------------------------------------------------
	//
	// A sweep that HAPPENS WHERE IT WAS TRIGGERED and stays there. The ambient
	// wave's "follows you" origin drags the whole effect around with the
	// player, which is right for a beacon that is hunting you and wrong for
	// anything that should mark a place. Walk a corridor dropping these and
	// you leave a line of events behind you, each one still turning where you
	// left it.
	//
	// A drop is cvarDriven, so it looks exactly like the sweep configured in
	// the menu -- same colours, speeds, thicknesses, draw modes, spin. The
	// only thing it does differently is not move.

	int lastDropTic;

	void DropWave(Vector3 at)
	{
		if (!ambient) return;
		int cap = clamp(CVar.FindCVar("gitd_ss_drop_max") ?
			CVar.FindCVar("gitd_ss_drop_max").GetInt() : 8, 1, 32);

		// Count what is already down, and if we are at the cap retire the
		// oldest rather than refusing -- a trail that stops appearing looks
		// broken, a trail that fades from the back looks intended.
		int live = 0;
		GITD_Wave oldest = null;
		for (int i = 0; i < waves.Size(); i++)
		{
			let w = waves[i];
			if (!w || w.ambient || !w.alive || w.tag != "gitd_drop") continue;
			live++;
			if (!oldest || w.id < oldest.id) oldest = w;
		}
		if (live >= cap && oldest) oldest.alive = false;

		let w = NewWave();
		if (!w) return;

		w.cvarDriven = true;      // reads the same per-band tables
		w.tag        = "gitd_drop";
		w.origin     = at;        // and THIS is the whole point
		w.shape      = ambient.shape;
		w.speed      = ambient.speed;
		w.range      = ambient.range;
		w.thickness  = ambient.thickness;
		w.softness   = ambient.softness;
		w.intensity  = ambient.intensity;
		w.subBands   = ambient.subBands;
		w.drift      = ambient.drift;
		w.trail      = ambient.trail;
		w.spin       = ambient.spin;
		w.spinRadius = ambient.spinRadius;
		w.spinColors = ambient.spinColors;
		w.priority   = 5;         // above the weather, below a scripted wave
		w.loop       = false;     // one pass, then it is gone
		w.pos        = 0;
		w.dir        = 1;
		lastDropTic  = level.maptime;
	}

	// Drop at the player's feet, which is where every trigger means.
	void DropAtPlayer()
	{
		let pmo = players[consoleplayer].mo;
		if (pmo) DropWave(pmo.pos);
	}

	bool DropsEnabled()
	{
		let cv = CVar.FindCVar("gitd_ss_drop");
		return cv && cv.GetBool();
	}

	// A trigger fired: start the ambient wave over.
	void SSStartPass()
	{
		// With drops on, a trigger leaves a sweep WHERE IT FIRED instead of
		// restarting the one that follows you.
		if (DropsEnabled()) { DropAtPlayer(); return; }
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
					level.SetSweepBand(slot, pos, BandThick(w, band), w.softness,
						BandColor(w, band), w.intensity);
					// This band's OWN origin and shape.
					level.SetSweepBandAt(slot, w.BandOrigin(band), BandShape(w, band));
					level.SetSweepBandDraw(slot, BandDraw(w, band));
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
	// Per BAND, because bands no longer agree about shape OR origin. If this
	// and main.fp's smode disagree, the light lags the visible band and reads
	// as a renderer bug -- so this uses exactly the shape and origin pushed to
	// the shader.
	double WaveDistanceFor(GITD_Wave w, Vector3 c, int band)
	{
		int shape = BandShape(w, band);
		Vector3 o = w.BandOrigin(band);
		if (shape == 2)      return abs(c.x - o.x);
		else if (shape == 3) return abs(c.y - o.y);
		else if (shape == 4) return (c - o).Length();   // shell: 3D
		else if (shape == 5) return c.z - o.z;          // rising, signed
		return (c.xy - o.xy).Length();
	}

	// Nearest band of one wave, and how strongly it lands. ZScript cannot
	// forward a two-value return as an expression, so callers take both into
	// locals with [a, b] = -- a language limit, not a style choice.
	// Takes the POINT, not a precomputed distance: the bands no longer agree
	// about how distance is measured -- one may be a ring around the map
	// centre while the next is a plane climbing from your feet -- and one
	// number cannot describe both. Same restructuring main.fp took when its
	// distance moved inside the band loop, for the same reason.
	// REACH IS PER BAND, not per wave. Fixed 2026-08-11: the caller used to
	// pass one reach derived from w.thickness while the shader draws each band
	// at its OWN gitd_ss_thick<n>, so a band drawn thin changed light in a
	// band-width it was never drawn at -- exactly the light-lags-the-band
	// mismatch SECTOR_SWEEP.md names as a must-never. The `fallback` argument
	// is still taken because a wave with no per-band thickness set resolves
	// every band to its shared value anyway.
	int, double WaveNearestAt(GITD_Wave w, Vector3 c, double fallback)
	{
		double nearest = 1e9;
		double nearestReach = fallback;
		int which = -1;
		for (int b = 0; b < w.bandPos.Size(); b++)
		{
			double d = abs(WaveDistanceFor(w, c, b) - w.bandPos[b]);
			if (d < nearest)
			{
				nearest = d;
				which = b;
				nearestReach = max(max(BandThick(w, b), 1), 1.0) * 3.0;
			}
		}
		if (which < 0 || nearest > nearestReach) return -1, 0.0;
		return which, 1.0 - clamp(nearest / nearestReach, 0.0, 1.0);
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
				[band, strength] = WaveNearestAt(w, c, reach);
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
					// The far colours are cleared, not left alone: under
					// underlay the lanes may have set a junction colour this
					// tic, and a band's recolour ramping toward a junction
					// between two colours it just replaced is nobody's intent.
					Color bc = BandColor(w, band);
					int cov = int(96 * strength);
					sec.SetGlowColor(Sector.floor, GITD_Palette.Scale(bc, 0.55 * strength));
					sec.SetGlowColorFar(Sector.floor, Color(0,0,0,0));
					sec.SetGlowHeight(Sector.floor, cov);
					sec.SetGlowColor(Sector.ceiling, GITD_Palette.Scale(bc, 0.85 * strength));
					sec.SetGlowColorFar(Sector.ceiling, Color(0,0,0,0));
					sec.SetGlowHeight(Sector.ceiling, cov);
					sec.SetFlatGlowColor(Sector.floor, GITD_Palette.Scale(bc, 0.40 * strength));
					sec.SetFlatGlowColorFar(Sector.floor, Color(0,0,0,0));
					sec.SetFlatGlowHeight(Sector.floor, cov);
					sec.SetFlatGlowColor(Sector.ceiling, GITD_Palette.Scale(bc, 0.70 * strength));
					sec.SetFlatGlowColorFar(Sector.ceiling, Color(0,0,0,0));
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
				[band, strength] = WaveNearestAt(w, a.pos, reach);
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

		// Drop on a timer as well as on events, so "leave one behind me every
		// few seconds as I walk" needs no trigger at all.
		if (DropsEnabled())
		{
			let ev = CVar.FindCVar("gitd_ss_drop_every");
			double every = ev ? ev.GetFloat() : 0.0;
			if (every > 0 && level.maptime - lastDropTic >= int(every * 35))
				DropAtPlayer();
		}
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

		// The mist notices. A burst where something died is the cheapest
		// possible read on "that happened over there", and unlike a sound it
		// is still legible with six other things happening at once.
		FogEvent(e.Thing.pos,
			GITD_Render.GetF("gitd_fog_react_death", 0.8),
			GITD_Render.GetF("gitd_fog_react_death_size", 130.0));

		// And the ground remembers. Stamped whether or not the heatmap is
		// currently being DRAWN, because it is a record rather than an effect
		// -- switching the display on after a fight has to show you the fight
		// you just had, not an empty floor.
		if (GITD_Render.GetF("gitd_heat_amount", 1.0) > 0.0)
			level.HeatmapAdd(e.Thing.pos.x, e.Thing.pos.y, e.Thing.pos.z,
				max(GITD_Render.GetF("gitd_heat_size", 96.0), 1.0),
				GITD_Render.GetF("gitd_heat_amount", 1.0));

		DropShape(e.Thing.pos, "gitd_shape_on_death");
	}

	// ---- a mark on the floor ---------------------------------------------
	//
	// Placed at the thing's FEET rather than its centre, because a shape is a
	// flat decal and its height fade decides whether it lands on the floor or
	// hangs at chest height over it.
	//
	// The angle is randomised per mark. Sixteen identical squares all facing
	// the same way reads as a texture someone stamped; the same sixteen at
	// different angles reads as sixteen separate events, which is what they
	// are. Cheap, and it is most of the difference.
	void DropShape(Vector3 at, string gate)
	{
		if (!GITD_Render.GetB("gitd_shape_enabled", false)) return;
		if (!GITD_Render.GetB(gate, true)) return;

		int pk = GITD_Render.GetI("gitd_shape_color", 0xFF4010);

		int slot = level.AddShape(
			clamp(GITD_Render.GetI("gitd_shape_kind", 2), 1, 7),
			clamp(GITD_Render.GetI("gitd_shape_orient", 0), 0, 2),
			at.x, at.y, at.z,
			max(GITD_Render.GetF("gitd_shape_size", 64.0), 1.0),
			GITD_Render.GetF("gitd_shape_angle", 0.0) + random(0, 359),
			max(GITD_Render.GetF("gitd_shape_thick", 6.0), 0.1),
			Color(255, (pk >> 16) & 255, (pk >> 8) & 255, pk & 255),
			max(GITD_Render.GetF("gitd_shape_intensity", 1.6), 0.0),
			max(GITD_Render.GetF("gitd_shape_life", 4.0), 0.0));

		// The split is set separately because it is the ANIMATED half, and a
		// caller usually wants a mark and only sometimes wants it to open.
		if (slot >= 0)
		{
			level.SetShapeMotion(slot,
				clamp(GITD_Render.GetF("gitd_shape_seam", 0.0), 0.0, 1.0),
				GITD_Render.GetF("gitd_shape_seam_rate", 0.35),
				GITD_Render.GetF("gitd_shape_grow", 0.0));

			// And whether this one mark is actually a formation.
			level.SetShapeRepeat(slot,
				clamp(GITD_Render.GetI("gitd_shape_repeat", 0), 0, 2),
				max(GITD_Render.GetF("gitd_shape_rep_count", 6.0), 1.0),
				max(GITD_Render.GetF("gitd_shape_rep_space", 96.0), 1.0),
				GITD_Render.GetF("gitd_shape_rep_spin", 20.0));
		}
	}

	// ---- WHAT MAKES THE MIST REACT ---------------------------------------
	//
	// One call, because there is one primitive. Everything the fog does in
	// response to the world goes through here, and what varies is a mode and
	// a strength -- not a system.
	//
	// Gated on gitd_fog_react rather than on the fog being on, because the
	// slots are cheap to leave empty and a mapper may well want the mist to
	// react while a script is fading the layer in.
	void FogEvent(Vector3 pos, double strength, double size)
	{
		if (strength <= 0.0) return;
		if (!GITD_Render.GetB("gitd_fog_react", false)) return;

		level.FogDisturb(pos.x, pos.y, pos.z, size, strength,
			GITD_Render.GetF("gitd_fog_react_speed", 320.0),
			max(GITD_Render.GetF("gitd_fog_react_life", 1.6), 0.05),
			clamp(GITD_Render.GetI("gitd_fog_react_mode", 1), 0, 3));
	}

	// A ring recoiling from your own muzzle, and this is the one that sells
	// the whole idea -- it proves the mist is BETWEEN you and the wall rather
	// than painted over the picture. Fired on the rising edge of the trigger
	// for the same reason the sweep is: a chaingun would otherwise spend all
	// eight slots in a third of a second.
	void PushFogShot()
	{
		let pmo = players[consoleplayer].mo;
		if (!pmo || !pmo.player) return;

		// ONE EDGE, TWO CONSUMERS. The rising edge is read here and only here,
		// because two separate readers would each keep their own `was it down`
		// and drift apart the first time one of them was gated off -- so the
		// fog ring and the floor mark would stop agreeing about what a shot is.
		bool down = (pmo.player.cmd.buttons & BT_ATTACK) != 0;
		bool fired = down && !lastFogShotDown;
		lastFogShotDown = down;
		if (!fired) return;

		if (GITD_Render.GetB("gitd_fog_react", false))
			FogEvent(pmo.pos + (0, 0, 32),
				GITD_Render.GetF("gitd_fog_react_shot", 0.55),
				GITD_Render.GetF("gitd_fog_react_shot_size", 88.0));

		DropShape(pmo.pos, "gitd_shape_on_shot");
	}

	// MONSTERS SHOULDER THE MIST ASIDE. The nearest few only -- there are
	// eight slots and a busy room has forty actors, so the ones worth spending
	// them on are the ones close enough to see it happen.
	//
	// These are pushed as DISCS with a short life, refreshed every tic, so
	// they follow their owner without any slot ever being owned by anything.
	void PushFogDisplacers()
	{
		double amt = GITD_Render.GetF("gitd_fog_displace", 0.0);
		if (amt <= 0.0 || !GITD_Render.GetB("gitd_fog_enabled", false)) return;

		let pmo = players[consoleplayer].mo;
		if (!pmo) return;

		int want = clamp(GITD_Render.GetI("gitd_fog_displace_count", 4), 1, 6);
		double size = max(GITD_Render.GetF("gitd_fog_displace_size", 64.0), 8.0);

		// A single pass keeping the closest `want`, rather than sorting the
		// whole room. Insertion into a tiny list beats a sort when the list is
		// four long and the input is a hundred.
		Actor best[6];
		double bestd[6];
		for (int i = 0; i < 6; i++) bestd[i] = 1e9;

		ThinkerIterator it = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bISMONSTER || a.health <= 0) continue;
			double d = (a.pos.xy - pmo.pos.xy).Length();
			if (d > 1024) continue;
			for (int s = 0; s < want; s++)
			{
				if (d < bestd[s])
				{
					for (int k = want - 1; k > s; k--)
					{
						bestd[k] = bestd[k - 1];
						best[k] = best[k - 1];
					}
					bestd[s] = d; best[s] = a;
					break;
				}
			}
		}

		for (int s = 0; s < want; s++)
		{
			if (!best[s]) continue;
			// Life of two tics: long enough to survive a frame, short enough
			// that a monster which dies or teleports leaves nothing behind.
			level.FogDisturb(best[s].pos.x, best[s].pos.y, best[s].pos.z,
				size * (best[s].radius / 20.0), amt, 0.0, 0.06, 0);
		}
	}

	override void WorldThingDamaged(WorldEvent e)
	{
		if (!e.Thing || e.Damage <= 0) return;

		// WHERE YOU WERE HURT is a different map from where things died, and
		// the two together are the actual shape of a fight -- one shows what
		// you controlled and the other shows what controlled you.
		if (e.Thing.player)
		{
			double hurt = GITD_Render.GetF("gitd_heat_hurt", 0.0);
			if (hurt > 0.0)
				level.HeatmapAdd(e.Thing.pos.x, e.Thing.pos.y, e.Thing.pos.z,
					max(GITD_Render.GetF("gitd_heat_size", 96.0), 1.0),
					hurt * clamp(e.Damage / 20.0, 0.15, 4.0));
		}

		if (CVar.FindCVar("gitd_ss_trigger").GetInt() != 2) return;
		if (!e.Thing.player) return;
		SSStartPass();
	}

	void Apply()
	{
		if (!CVar.FindCVar("gitd_enabled").GetBool())
		{
			ClearAll();
			return;
		}

		// The render settings are pushed in WorldTick now, above the branch
		// that decides whether the lanes run -- see the note there. They used
		// to be here, which meant the early return above froze them.

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

		// SEAMLESS CORNERS.
		//
		// The gradient at a corner was never missing. The wall glow fades
		// UPWARD starting at the floor line, and the floor's edge glow fades
		// INWARD starting at the same line -- two gradients meeting nose to
		// nose, both at FULL strength exactly where they touch. The hard cut
		// is not an absence of blending. It is the two sides disagreeing
		// about what colour and brightness to be at the line they share.
		//
		// The first fix made both sides the SAME colour near the join. The
		// seam died and the two-colour transition died with it: a corner that
		// was meant to read floor-purple into wall-blue read as one flat
		// wash of the average.
		//
		// A glow now carries TWO colours and ramps between them by
		// attenuation, so it can agree at the join without giving up its own
		// colour. Both surfaces take the junction colour at the line and fade
		// to their own lane's colour going away from it -- one continuous
		// ramp, floor colour to blend to wall colour, with no flat region and
		// no seam. Off, the far colour goes unset and each glow is the single
		// flat colour it always was.
		//
		// BOTH junctions or neither. Floor/wall-bottom and ceiling/wall-top
		// are the same problem mirrored, and the eye reads the mismatch
		// immediately if only one of them ramps.
		//
		// Reach, falloff and brightness are forced to match too. A ramp that
		// changes width, curve or brightness halfway across the corner reads
		// as a seam even when the colour is continuous.
		// HOISTED ABOVE THE JOIN, 2026-08-11. These used to be read after the
		// seamless block, which meant the join could not consult them -- so a
		// lane with its partner switched off still ramped halfway toward that
		// partner's colour, agreeing with a surface that is not drawn.
		bool wbOn = wb.GetBool("_enabled");
		bool wtOn = wt.GetBool("_enabled");
		bool cgOn = cg.GetBool("_enabled");
		bool fgOn = fg.GetBool("_enabled");

		Color wbFar = Color(0,0,0,0), wtFar = Color(0,0,0,0);
		Color cgFar = Color(0,0,0,0), fgFar = Color(0,0,0,0);
		if (CvB("gitd_seamless", false))
		{
			// A corner needs BOTH of its surfaces to be drawn before there is
			// anything to agree with. With one side off the other keeps its own
			// flat colour, which is what it looked like before seamless existed.
			if (wbOn && fgOn)
			{
				Color floorJoin = GITD_Palette.Lerp(wbCol, fgCol, 0.5);
				wbFar = wbCol; wbCol = floorJoin;
				fgFar = fgCol; fgCol = floorJoin;
			}
			if (wtOn && cgOn)
			{
				Color ceilJoin = GITD_Palette.Lerp(wtCol, cgCol, 0.5);
				wtFar = wtCol; wtCol = ceilJoin;
				cgFar = cgCol; cgCol = ceilJoin;
			}
		}

		int wbCov = wb.GetInt("_coverage"), wbFall = wb.GetInt("_falloff");
		int wtCov = wt.GetInt("_coverage"), wtFall = wt.GetInt("_falloff");
		int cgCov = cg.GetInt("_coverage"), cgFall = cg.GetInt("_falloff");
		int fgCov = fg.GetInt("_coverage"), fgFall = fg.GetInt("_falloff");

		// A preset can carry shape as well as colour. Without this, something
		// like a Tron look could not be saved at all -- thin bright seams are
		// a coverage and falloff decision, and a colour-only preset would
		// leave them to whatever the lanes happened to be set to.
		bool seamless = CvB("gitd_seamless", false);

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

			double wbIA = wbI * wb.AnimFactor(sec, mapCentre);
			double wtIA = wtI * wt.AnimFactor(sec, mapCentre);
			double sfgI = fgI * fg.AnimFactor(sec, mapCentre);
			double scgI = cgI * cg.AnimFactor(sec, mapCentre);

			int sfgCov = fgCov, scgCov = cgCov, sfgFall = fgFall, scgFall = cgFall;
			if (seamless)
			{
				// Match the band's WIDTH, CURVE and BRIGHTNESS to the wall it
				// meets. Brightness can be handed over directly now: the
				// flat's Intensity scales its colour, the same quantity the
				// wall's always did. It used to scale REACH instead, so the
				// only way to match brightness was to pre-scale the flat's
				// colour by the wall's intensity -- a workaround for a slider
				// that meant two different things.
				//
				// Only from a wall that is actually drawn. Taking reach and
				// curve from a disabled lane silently gave the flat the shape
				// of a surface the user had switched off.
				if (wbOn && fgOn) { sfgCov = wbCov;  sfgFall = wbFall;  sfgI = wbIA; }
				if (wtOn && cgOn) { scgCov = wtCov;  scgFall = wtFall;  scgI = wtIA; }
			}

			ApplyOne(sec,
				wbOn, wbCol, wbFar, wbCov, wbFall, wbIA,
				wtOn, wtCol, wtFar, wtCov, wtFall, wtIA,
				cgOn, cgCol, cgFar, scgCov, scgFall, scgI,
				fgOn, fgCol, fgFar, sfgCov, sfgFall, sfgI);
		}
	}

	// THE TRAIL YOU KICK UP.
	//
	// One point that CHASES the player rather than sitting on them. That lag
	// is the entire effect: the disturbance is where you were a moment ago,
	// so walking drags a thinned channel through the mist behind you and it
	// closes up as the point catches back up. A wake pinned to the player
	// would just be a hole you carry around, which is not a wake at all.
	//
	// A spring rather than a history buffer, because a trail that settles IS
	// a point that follows you slowly, and one Vector3 costs nothing where a
	// ring buffer of positions would need a uniform array.
	//
	// Lives here and not in GITD_Render because it reads the player, and the
	// menu tic that drives everything else cannot.
	// A funnel that stands somewhere other than a fixed point on the map.
	//
	// Mode 0 is the fixed case and is already correct after PushAll, so it is
	// not re-pushed -- which also means the position sliders keep working from
	// the menu with the game stopped, since nothing here runs to overwrite them.
	//
	// Anchored to you it becomes a thing you carry rather than a thing you walk
	// into, which is worth having as a screen effect but is NOT what a tornado
	// is. Anchored to the nearest live monster it walks the room on its own,
	// which is.
	// ---- the mist takes its colour from the room -------------------------
	//
	// A fixed fog colour while four lanes cycle thirty-two around it reads as
	// two mods running at once. This re-pushes the fog with a tint taken from
	// a lane's LIVE colour, which only exists here -- PushFog runs from the
	// menu ticker too, and there is no lane object to ask from there.
	//
	// COMPLEMENT is the one worth trying first. Match makes the air agree with
	// the room, which is pleasant and quiet; complement puts the mist opposite
	// the glow in hue, and hue separation is what reads as depth. Cyan light
	// standing in orange air looks like two distances. Cyan light in cyan air
	// looks like one flat wash.
	//
	// Random re-rolls only when the lane CHANGES SLOT, not every tic -- a
	// colour that changes 35 times a second is not a colour, it is noise.
	void PushFogTint()
	{
		int mode = GITD_Render.GetI("gitd_fog_color_mode", 0);
		if (mode <= 0) return;
		if (!GITD_Render.GetB("gitd_fog_enabled", false)) return;

		int which = clamp(GITD_Render.GetI("gitd_fog_color_lane", 3), 0, 3);
		GITD_Lane src = (which == 0) ? wb : (which == 1) ? wt : (which == 2) ? cg : fg;
		if (!src) return;

		Color t = src.outColor;

		if (mode == 2)
		{
			// The opposite hue at the same brightness -- inverting the bytes
			// would also invert value, and a dark glow would hand back a pale
			// mist, which is a different effect and not the one asked for.
			t = GITD_Palette.Complement(t);
		}
		else if (mode == 3)
		{
			if (src.slotIndex != lastTintSlot)
			{
				lastTintSlot = src.slotIndex;
				tintRandom = GITD_Palette.RandomColor();
			}
			t = tintRandom;
		}

		GITD_Render.PushFog(true, t);
	}

	void PushTornadoAnchor()
	{
		if (!GITD_Render.GetB("gitd_tornado_enabled", false)) return;

		int mode = GITD_Render.GetI("gitd_tornado_origin", 0);
		if (mode <= 0) return;

		Vector3 o = OriginFor(mode);
		GITD_Render.PushTornado(true, o.x, o.y);
	}

	// HOW ALARMED THE ROOM IS, and the disturbance reach that goes with it.
	//
	// This is the term that makes the glow carry information rather than only
	// look good -- the other four textures are material, this one is a state
	// the player can read off the walls without a HUD element.
	//
	// Lives here rather than in GITD_Render because counting nearby monsters
	// is a playsim read. Same split as the glow wave's origin and the
	// tornado's anchor.
	//
	// The level is SMOOTHED toward its target rather than set. A count that
	// jumps from three to zero the instant the last monster dies would snap
	// the whole room's brightness in one tic, which reads as a bug; easing it
	// reads as the room settling.
	void PushGlowAlarm()
	{
		double depth = max(GITD_Render.GetF("gitd_gpulse", 0.0), 0.0);
		double react = max(GITD_Render.GetF("gitd_greact", 0.0), 0.0);

		if (depth <= 0.0 && react <= 0.0)
		{
			level.SetGlowReact(0, 0, 0);
			alarmLevel = 0;
			return;
		}

		int src = GITD_Render.GetI("gitd_gpulse_src", 1);
		double target = 0.0;

		let pmo = players[consoleplayer].mo;

		if (src == 0)
		{
			target = clamp(GITD_Render.GetF("gitd_gpulse_level", 0.0), 0.0, 1.0);
		}
		else if (pmo)
		{
			if (src == 1 || src == 3)
			{
				double range = max(GITD_Render.GetF("gitd_gpulse_range", 768.0), 1.0);
				int want = max(GITD_Render.GetI("gitd_gpulse_count", 6), 1);
				int near = 0;

				ThinkerIterator it = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
				Actor a;
				while (a = Actor(it.Next()))
				{
					if (!a.bISMONSTER || a.health <= 0) continue;
					if ((a.pos.xy - pmo.pos.xy).Length() > range) continue;
					near++;
					if (near >= want) break;   // saturated; counting on is waste
				}
				target = clamp(double(near) / double(want), 0.0, 1.0);
			}

			if (src == 2 || src == 3)
			{
				// Inverted: LOW health is high alarm.
				double hp = pmo.health / double(max(pmo.GetMaxHealth(true), 1));
				double hurt = clamp(1.0 - hp, 0.0, 1.0);
				target = (src == 3) ? max(target, hurt) : hurt;
			}
		}

		alarmLevel += (target - alarmLevel) * 0.06;
		level.SetGlowReact(react, depth, clamp(alarmLevel, 0.0, 1.0));
	}

	void PushFogWake()
	{
		if (!GITD_Render.GetB("gitd_fog_enabled", false))
		{
			level.SetFogWake((0, 0, 0), 0, 0);
			level.SetFogWakeMotion(0, 0, 0);
			return;
		}

		double strength = clamp(GITD_Render.GetF("gitd_fog_wake", 0.65), 0.0, 1.0);
		if (strength <= 0.0)
		{
			level.SetFogWake((0, 0, 0), 0, 0);
			level.SetFogWakeMotion(0, 0, 0);
			return;
		}

		let pmo = players[consoleplayer].mo;
		if (!pmo) return;

		double lag = clamp(GITD_Render.GetF("gitd_fog_wake_lag", 0.10), 0.01, 1.0);
		if (!haveWake) { wakePos = pmo.pos; haveWake = true; }
		wakePos += (pmo.pos - wakePos) * lag;

		level.SetFogWake(wakePos,
			double(GITD_Render.GetI("gitd_fog_wake_size", 110)), strength);

		// STRETCHED ALONG THE WAY YOU ARE GOING.
		//
		// Taken from the lag vector rather than from pmo.Vel, deliberately.
		// Vel is the velocity for THIS tic and jitters hard against walls and
		// on stairs; the gap between you and the point already chasing you is
		// the same direction, smoothed by the spring that is already there.
		// One number reused instead of a second one that has to be filtered.
		Vector2 drift = (pmo.pos.xy - wakePos.xy);
		level.SetFogWakeMotion(drift.x, drift.y,
			max(GITD_Render.GetF("gitd_fog_wake_stretch", 0.0), 0.0));
	}

	// THE LASER GRID MOVED INTO THE SWEEP, and this is what it left behind.
	//
	// It used to push eight real beam segments in a rectangle riding band 1.
	// Eight is a fence, not a screen door; the rectangle was a small panel
	// floating in a large room rather than a wall of light filling it; and
	// raising the count would have cost another segment solve per pixel for
	// every line added.
	//
	// The sweep already draws a lattice where the view ray crosses its band,
	// as a pattern rather than as objects, so density there is free. That is
	// the grid now -- see gitd_ss_fill_air. Nothing in GITD pushes beams any
	// more, which also means the beam budget belongs entirely to weapons.

	void ClearAll()
	{
		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			if (IsOverridden(i)) continue;
			ApplyOne(level.Sectors[i],
				false, Color(0,0,0,0), Color(0,0,0,0), 0, 0, 1.0,
				false, Color(0,0,0,0), Color(0,0,0,0), 0, 0, 1.0,
				false, Color(0,0,0,0), Color(0,0,0,0), 0, 0, 1.0,
				false, Color(0,0,0,0), Color(0,0,0,0), 0, 0, 1.0);
		}
	}

	// The single place any of this reaches the engine. Shared by the map
	// default and per-sector overrides so the two cannot drift.
	// The *Far colours are the far end of each glow's ramp -- see the
	// seamless-corners block above. Alpha 0 means unset and the glow is a
	// single flat colour, so passing Color(0,0,0,0) is the old behaviour
	// exactly.
	static void ApplyOne(Sector sec,
		bool wbOn, color wbCol, color wbFar, int wbCov, int wbFall, double wbInten,
		bool wtOn, color wtCol, color wtFar, int wtCov, int wtFall, double wtInten,
		bool cgOn, color cgCol, color cgFar, int cgCov, int cgFall, double cgInten,
		bool fgOn, color fgCol, color fgFar, int fgCov, int fgFall, double fgInten)
	{
		// wb -- wall bottom, driven by the floor plane
		if (wbOn)
		{
			sec.SetGlowColor(Sector.floor, wbCol);
			sec.SetGlowColorFar(Sector.floor, wbFar);
			sec.SetGlowHeight(Sector.floor, wbCov);
			sec.SetGlowFalloff(Sector.floor, wbFall);
			sec.SetGlowIntensity(Sector.floor, wbInten);
		}
		else
		{
			sec.SetGlowColor(Sector.floor, Color(0,0,0,0));
			sec.SetGlowColorFar(Sector.floor, Color(0,0,0,0));
			sec.SetGlowHeight(Sector.floor, 0);
		}

		// wt -- wall top, driven by the ceiling plane
		if (wtOn)
		{
			sec.SetGlowColor(Sector.ceiling, wtCol);
			sec.SetGlowColorFar(Sector.ceiling, wtFar);
			sec.SetGlowHeight(Sector.ceiling, wtCov);
			sec.SetGlowFalloff(Sector.ceiling, wtFall);
			sec.SetGlowIntensity(Sector.ceiling, wtInten);
		}
		else
		{
			sec.SetGlowColor(Sector.ceiling, Color(0,0,0,0));
			sec.SetGlowColorFar(Sector.ceiling, Color(0,0,0,0));
			sec.SetGlowHeight(Sector.ceiling, 0);
		}

		// cg -- ceiling's own surface
		if (cgOn)
		{
			sec.SetFlatGlowColor(Sector.ceiling, cgCol);
			sec.SetFlatGlowColorFar(Sector.ceiling, cgFar);
			sec.SetFlatGlowHeight(Sector.ceiling, cgCov);
			sec.SetFlatGlowFalloff(Sector.ceiling, cgFall);
			sec.SetFlatGlowIntensity(Sector.ceiling, cgInten);
		}
		else
		{
			sec.SetFlatGlowColor(Sector.ceiling, Color(0,0,0,0));
			sec.SetFlatGlowColorFar(Sector.ceiling, Color(0,0,0,0));
			sec.SetFlatGlowHeight(Sector.ceiling, 0);
		}

		// fg -- floor's own surface
		if (fgOn)
		{
			sec.SetFlatGlowColor(Sector.floor, fgCol);
			sec.SetFlatGlowColorFar(Sector.floor, fgFar);
			sec.SetFlatGlowHeight(Sector.floor, fgCov);
			sec.SetFlatGlowFalloff(Sector.floor, fgFall);
			sec.SetFlatGlowIntensity(Sector.floor, fgInten);
		}
		else
		{
			sec.SetFlatGlowColor(Sector.floor, Color(0,0,0,0));
			sec.SetFlatGlowColorFar(Sector.floor, Color(0,0,0,0));
			sec.SetFlatGlowHeight(Sector.floor, 0);
		}
	}
}

// ---------------------------------------------------------------------------
// RESET: back to defaults, everything OFF except the four lanes.
//
// "Default" here does not mean "whatever each cvar's shipped value happens to
// be". It means A CLEAN ROOM: the 4x8 running, and nothing else on top of it.
// Somebody reaching for this button has a picture they cannot explain and
// wants a floor to stand on, and handing them back a default that still has
// three systems running is not a floor.
//
// So the values go back to their defaults AND every system is then explicitly
// switched off -- which is not the same operation, because several systems
// ship ON (the torch, the darkness curve, the numbers).
//
// THE ACTIVE PRESET SURVIVES, and is re-applied on top afterwards. A preset is
// a deliberate choice about the whole room, not a stray setting, and wiping it
// would make this button destroy work rather than clear it.
//
// WHY THE SWITCH LIST IS THE ONE THAT MATTERS. The value list below is long,
// hand-written and has gone stale repeatedly -- the sweep's behaviour set was
// missing from it for months, and before this change ELEVEN switches were
// absent entirely: the heatmap, all five glow-texture terms, the fog's noise,
// tendrils and bow wave, the desaturation keep, and the air lattice. A long
// list nobody can audit will always rot.
//
// The switch list cannot rot the same way, because it is one line per system
// and a system that is missing from it is visibly still running the moment the
// button is pressed. A stale VALUE on a system that is switched off is
// invisible and harmless; a missing SWITCH is the whole bug. Keep this list
// complete and the long one can be as imperfect as it likes.
// ---------------------------------------------------------------------------
class GITD_ResetHandler : EventHandler
{
	static void Rst(string name)
	{
		CVar c = CVar.FindCVar(name);
		if (c) c.ResetToDefault();
	}

	// A master switch, forced off rather than reset -- several of these ship
	// ON, and this button means "off" and not "as it came".
	static void Off(string name)
	{
		CVar c = CVar.FindCVar(name);
		if (c) c.SetInt(0);
	}

	// The same, for the systems whose master is an amount rather than a bool.
	static void Zero(string name)
	{
		CVar c = CVar.FindCVar(name);
		if (c) c.SetFloat(0.0);
	}

	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.name != "gitd_reset") return;

		// Remembered across the wipe below, then put back and re-applied.
		int keepPreset = 0;
		let pc = CVar.FindCVar("gitd_preset");
		if (pc) keepPreset = pc.GetInt();

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
		for (int c = 1; c <= 8; c++) Rst("gitd_ss_draw" .. c);
		for (int c = 1; c <= 8; c++) Rst("gitd_ss_thick" .. c);
		for (int c = 1; c <= 8; c++) Rst("gitd_ss_shape" .. c);
		Rst("gitd_ss_spin"); Rst("gitd_ss_spin_radius"); Rst("gitd_ss_spin_colors");
		Rst("gitd_ss_drop"); Rst("gitd_ss_drop_every"); Rst("gitd_ss_drop_max");
		Rst("gitd_ss_underlay"); Rst("gitd_seamless");
		static const string wave[] = { "gitd_wave_enabled", "gitd_wave_length",
			"gitd_wave_speed", "gitd_wave_sharp", "gitd_wave_shape",
			"gitd_wave_origin", "gitd_wave_reach", "gitd_wave_bright",
			"gitd_wave_colour", "gitd_wave_detune", "gitd_wave_seed",
			"gitd_wave_climb", "gitd_dd_perpixel", "gitd_dd_dist",
			"gitd_dd_dist_range", "gitd_dd_height", "gitd_dd_height_ref",
			"gitd_dd_height_range" };
		for (int i = 0; i < wave.Size(); i++) Rst(wave[i]);
		Rst("gitd_ss_light");
		for (int g = 1; g <= 7; g++) CVar.FindCVar("gitd_ss_gap" .. g).ResetToDefault();

		// Darkness, flashlight, numbers, pickup cones.
		static const string rest[] = {
			// gitd_preset is NOT here. It is captured before this list runs
			// and put back after, because a preset is a deliberate choice
			// about the whole room rather than a stray setting -- this button
			// clears work, it does not destroy it.
			"gitd_enabled",
			// The sweep's behaviour set arrived after the sweeps[] list above
			// and was never added to it -- so "Reset EVERYTHING" put the
			// geometry back and left the conduct: a sweep still firing on
			// every kill, still slowing monsters, still driven by health.
			"gitd_ss_direction", "gitd_ss_trigger", "gitd_ss_drive",
			"gitd_ss_health_speed", "gitd_ss_drift", "gitd_ss_trail",
			"gitd_ss_actors", "gitd_ss_sonar_floor", "gitd_ss_sonar_fade",
			"gitd_ss_perband",
			"gitd_dd_enabled", "gitd_dd_noflash", "gitd_bloom_forced",
			"ddz_mode", "ddz_preset", "ddz_desat", "ddz_skymode", "ddz_lighting",
			"ddz_minlight", "ddz_pregain", "ddz_postgain",
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

		// Colour holds and the colour law -- newer systems, same promise:
		// EVERYTHING means everything.
		//
		// Ambush was here too, and is gone -- the system was removed, not
		// just disabled, so there is nothing left to reset. Rst is
		// null-guarded and would have no-op'd forever on cvars that no
		// longer exist, but a reset list naming a removed feature is the
		// kind of thing that outlives its reason and confuses the next
		// person who reads it wondering what "ambush" is.
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
		for (int b = 1; b <= 8; b++) { Rst("gitd_ss_fx" .. b); Rst("gitd_ss_script" .. b); }

		// BLOOM AND EXPOSURE ARE NOT RESET HERE, AND CANNOT BE. Fixed
		// 2026-08-11.
		//
		// This used to walk a list of gl_bloom_* / gl_exposure_* / gl_fogmode
		// and Rst() each one. Those belong to the ENGINE, and an engine cvar
		// cannot be written from play scope -- NetworkProcess runs in play,
		// so the first one threw and took the whole handler with it. The
		// abort landed PAST every mod reset above and BEFORE the confirmation
		// below, so the button half-worked and then died silently: the user
		// got an abort message instead of the line promising "bloom included",
		// and not one engine cvar was ever actually reset.
		//
		// The intent was right -- the page offers those sliders, so the reset
		// owes them. But it has to happen in MENU scope, where a cvar write is
		// legal. DarkDoomZ_OptionMenu (DarkDoomZ.zs:555) is the pattern: a
		// ZScript OptionMenu subclass whose MenuEvent does the work. Until
		// that exists, this says what is true rather than what was intended.
		// ---- and now everything OFF, except the four lanes ----------------
		//
		// ONE LINE PER SYSTEM. If you add a system, add its switch here, and
		// the test is trivial: press the button and look. A system missing
		// from this list is still running on a screen that was supposed to be
		// clear, which is the one failure a person can actually see.
		//
		// The four lanes are deliberately absent -- they are what is left.
		static const string masters[] = {
			"gitd_ss_enabled",        // sector sweep
			"gitd_wave_enabled",      // glow waves
			"gitd_fog_enabled",       // floor fog
			"gitd_tornado_enabled",   // the funnel
			"gitd_heat_enabled",      // the heatmap's display
			"gitd_fog_react",         // disturbances
			"gitd_neon_enabled",      // the numbers
			"gitd_law_enabled",       // colours change the fight
			"gitd_dd_perpixel",       // per-fragment darkness
			"fl_enabled",             // the torch -- ships ON
			"gitd_dd_enabled"         // the darkness curve -- ships ON
		};
		for (int i = 0; i < masters.Size(); i++) Off(masters[i]);

		// The same, where the master is an amount and 0 is its off.
		static const string zeros[] = {
			"gitd_ss_fill_air",       // the laser grid
			"gitd_fog_noise",         // mist banks
			"gitd_fog_tendril",       // wisps
			"gitd_fog_bow",           // the sweep shoulders the air
			"gitd_fog_displace",      // monsters push the mist
			"gitd_fog_color2_mix",    // the layer's second colour
			"gitd_fog_wake_stretch",
			"gitd_tornado_density",
			"gitd_dd_keep",           // selective desaturation
			"gitd_glowtex_noise",     // texture in the glow, all five
			"gitd_glowtex_flow",
			"gitd_glowtex_cell",
			"gitd_glowtex_react",
			"gitd_glowtex_alarm"
		};
		for (int i = 0; i < zeros.Size(); i++) Zero(zeros[i]);

		// ---- and the preset comes back ------------------------------------
		//
		// Re-applied rather than merely re-selected. The backup record is
		// cleared first so the profile re-captures against the FRESH defaults
		// -- otherwise Disable Preset would later hand back the settings that
		// were live before this button was pressed, which is the opposite of
		// what pressing it meant.
		if (keepPreset > 0)
		{
			let bk = CVar.FindCVar("gitd_preset_backup");
			if (bk) bk.SetString("");
			if (pc) pc.SetInt(keepPreset);
			if (GITD_PresetProfile.HasProfile(keepPreset))
				GITD_PresetProfile.Apply(keepPreset);
		}

		Console.Printf("\c[Gold]Glow In The Dark reset: the 4x8 lanes, and nothing else.");
		if (keepPreset > 0)
			Console.Printf("\c[DarkGray]Preset %d kept and re-applied on top. "
				.. "Its bloom is an engine setting and did not come with it -- "
				.. "reopen the menu to catch that up.", keepPreset);
		Console.Printf("\c[DarkGray]Bloom and exposure are engine settings and were not "
			.. "touched -- reset those from the Bloom page.");
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

	// freshMap is gone. It existed to tell a map LOAD apart from the player
	// CHOOSING a preset, because applying a profile was gated on having seen
	// the change. Nothing is gated on that any more -- see
	// GITD_PresetProfile.Sync -- and the two cases no longer need telling
	// apart, because "is a profile already holding the player's settings?"
	// answers both.
	override void WorldLoaded(WorldEvent e)
	{
		lastPreset = -1;    // force the working set to load on the first tick
		lastSweepSel = -1;  // and the sweep working set with it
	}

	// The menu offers 0..11. A console user can type anything, and every
	// preset path concatenates this number into a cvar name, so an unclamped
	// value resolves to nothing and the write dereferences null. Clamped at
	// both read sites rather than trusted.
	// Raised to 12 for OMGWTF. THIS NUMBER IS LOAD-BEARING AND SILENT: it
	// clamps, so a preset above it does not fail, it becomes a DIFFERENT
	// preset. Left at 11, choosing OMGWTF would quietly have selected Black
	// and White and every symptom would have pointed at the profile rather
	// than at a bound.
	const GITD_PRESET_MAX = 11;

	// ---- The sweep working set -------------------------------------------
	//
	// Eight bands x seven controls is forty-eight menu rows, which is already
	// past readable and left nowhere to put the per-band script. So the menu
	// edits ONE band and a selector says which. Exactly the trick the preset
	// customiser above uses, for exactly the same reason.
	//
	// The gitd_ss_*N cvars stay the storage. These are a view onto them, so
	// presets, the reset button and the engine see no change at all.

	int lastSweepSel;

	static string SwKey(string field, int band) { return "gitd_ss_" .. field .. band; }

	// Working set -> band N. Called before the selector moves away from N, so
	// edits are never silently dropped.
	void SaveSweep(int band)
	{
		if (band < 1 || band > 8) return;
		let c = CVar.FindCVar("gitd_sw_c");
		if (c) { let d = CVar.FindCVar(SwKey("c", band)); if (d) d.SetString(c.GetString()); }
		SetI(SwKey("speed",  band), GetI("gitd_sw_speed",  120));
		SetI(SwKey("shape",  band), GetI("gitd_sw_shape",  0));
		SetI(SwKey("draw",   band), GetI("gitd_sw_draw",   1));
		SetI(SwKey("thick",  band), GetI("gitd_sw_thick",  0));
		SetI(SwKey("fx",     band), GetI("gitd_sw_fx",     1));
		SetI(SwKey("amount", band), GetI("gitd_sw_amount", 48));
		// Band 8 has no "time to next" -- there is no ninth band.
		if (band < 8) SetI(SwKey("gap", band), GetI("gitd_sw_gap", 30));
		let s = CVar.FindCVar("gitd_sw_script");
		if (s) { let d = CVar.FindCVar(SwKey("script", band)); if (d) d.SetString(s.GetString()); }
	}

	// Band N -> working set.
	void LoadSweep(int band)
	{
		if (band < 1 || band > 8) return;
		let c = CVar.FindCVar(SwKey("c", band));
		if (c) { let d = CVar.FindCVar("gitd_sw_c"); if (d) d.SetString(c.GetString()); }
		SetI("gitd_sw_speed",  GetI(SwKey("speed",  band), 120));
		SetI("gitd_sw_shape",  GetI(SwKey("shape",  band), 0));
		SetI("gitd_sw_draw",   GetI(SwKey("draw",   band), 1));
		SetI("gitd_sw_thick",  GetI(SwKey("thick",  band), 0));
		SetI("gitd_sw_fx",     GetI(SwKey("fx",     band), 1));
		SetI("gitd_sw_amount", GetI(SwKey("amount", band), 48));
		SetI("gitd_sw_gap",    band < 8 ? GetI(SwKey("gap", band), 30) : 30);
		let s = CVar.FindCVar(SwKey("script", band));
		if (s) { let d = CVar.FindCVar("gitd_sw_script"); if (d) d.SetString(s.GetString()); }
	}

	// Live edits go straight through to the selected band, so the sweep you
	// are watching changes as you drag the slider rather than when you next
	// move the selector. The selector handler below covers the case where you
	// move away mid-edit.
	void CommitSweep()
	{
		SaveSweep(clamp(GetI("gitd_sw_sel", 1), 1, 8));
	}

	override void WorldTick()
	{
		// The sweep selector, before the preset block: moving it must write
		// the outgoing band before the incoming one overwrites the fields.
		int sel = clamp(GetI("gitd_sw_sel", 1), 1, 8);
		if (sel != lastSweepSel)
		{
			if (lastSweepSel >= 1 && lastSweepSel <= 8) SaveSweep(lastSweepSel);
			lastSweepSel = sel;
			LoadSweep(sel);
		}
		else CommitSweep();

		int preset = clamp(CVar.FindCVar("gitd_preset").GetInt(), 0, GITD_PRESET_MAX);
		if (preset != lastPreset)
		{
			lastPreset = preset;
			if (preset > 0) LoadWorkingSet(preset);
		}

		// Applying and recalling is state-derived and scope-free -- the menu
		// asks the same question every tic it is open. See PresetProfile.zs.
		GITD_PresetProfile.Sync(preset);
	}

	// GUARDED, like PresetProfile.zs:28-30. An unguarded FindCVar().Set* is a
	// native null dereference -- not a catchable VM abort -- the moment a name
	// does not resolve, and every caller below builds its name by concatenating
	// a preset number. One out-of-range number took the process down.
	static void SetF(string name, double v) { let c = CVar.FindCVar(name); if (c) c.SetFloat(v); }
	static void SetI(string name, int v)    { let c = CVar.FindCVar(name); if (c) c.SetInt(v); }

	// Reads need the same guard as writes -- GetBool() on a null CVar is the
	// same native dereference as SetInt().
	static bool GetB(string name)   { let c = CVar.FindCVar(name); return c ? c.GetBool()  : false; }
	static int  GetI(string name, int def) { let c = CVar.FindCVar(name); return c ? c.GetInt() : def; }

	// Pull a preset into the working set: your saved version if you have one,
	// otherwise whatever GITD_Presets ships.
	static void LoadWorkingSet(int preset)
	{
		string p = "gitd_p" .. preset;

		if (GetB(p .. "_custom"))
		{
			SetF("gitd_pc_hue",     CVar.FindCVar(p .. "_hue").GetFloat());
			SetF("gitd_pc_spread",  CVar.FindCVar(p .. "_spread").GetFloat());
			SetF("gitd_pc_sat",     CVar.FindCVar(p .. "_sat").GetFloat());
			SetF("gitd_pc_satvar",  CVar.FindCVar(p .. "_satvar").GetFloat());
			SetF("gitd_pc_val",     CVar.FindCVar(p .. "_val").GetFloat());
			SetF("gitd_pc_valvar",  CVar.FindCVar(p .. "_valvar").GetFloat());
			SetI("gitd_pc_shape", GetB(p .. "_shape") ? 1 : 0);
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
			SetI("gitd_pc_shape", 0);
		}
	}

	override void NetworkProcess(ConsoleEvent e)
	{
		int preset = clamp(CVar.FindCVar("gitd_preset").GetInt(), 0, GITD_PRESET_MAX);
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
			SetI(p .. "_shape", CVar.FindCVar("gitd_pc_shape").GetBool() ? 1 : 0);
			SetI(p .. "_coverage", CVar.FindCVar("gitd_pc_coverage").GetInt());
			SetI(p .. "_falloff",  CVar.FindCVar("gitd_pc_falloff").GetInt());
			SetF(p .. "_intensity",CVar.FindCVar("gitd_pc_intensity").GetFloat());
			SetI(p .. "_custom", 1);
			Console.Printf("Saved over preset: %s", GITD_Presets.Name(preset));
		}
		else if (e.name == "gitd_preset_restore")
		{
			SetI(p .. "_custom", 0);
			LoadWorkingSet(preset);
			Console.Printf("Restored preset defaults: %s", GITD_Presets.Name(preset));
		}
	}
}
