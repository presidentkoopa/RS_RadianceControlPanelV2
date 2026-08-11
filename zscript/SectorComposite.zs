// ===========================================================================
// One writer for sector light and colour.
//
// THE PROBLEM THIS EXISTS TO KILL.
//
// Three separate systems wanted to change how a sector looks, and all three
// did it the obvious way -- by calling SetColor and SetLightLevel on the
// sector, every tic:
//
//     DarkDoomZ       dims every sector in the map
//     Sector Sweep    brightens or darkens the ones under a band
//     a setpiece      tints the ones a wave has passed
//
// Whichever ran LAST won, so the visible result was decided by the order of
// names in mapinfo.txt. That is not a bug you fix once. It reappears every
// time anything new wants a say, and it had already bitten twice: the sweep's
// brighten was being erased by the darkness pass, and a setpiece's tint
// vanished within a frame of being applied and looked like it had never run.
//
// THE FIX. Nothing writes to a sector any more. Everything declares what it
// wants into a channel, and this flushes once per tic:
//
//     colour  =  the map's own colour  x  every tint, multiplied together
//     light   =  the map's own level   +  every delta, added together
//
// Multiplied tints and added deltas both commute, so ORDER STOPS MATTERING.
// Darkness and a red setpiece compose into a dark red room instead of one
// deleting the other. Two systems brightening the same sector agree on the
// sum rather than the last word.
//
// WHY LIGHT AND COLOUR ARE HANDLED DIFFERENTLY. Nothing in Doom animates a
// sector's COLOUR, so colour can be rewritten every tic for every sector and
// nobody minds. Doom animates LIGHT constantly -- every blinking, pulsing,
// flickering sector is a thinker writing lightlevel at up to 35Hz. Writing
// light unconditionally would fight all of them and the walls would strobe;
// that exact bug cost an evening once already. So light is only written for
// sectors something actually asked about, and released back to the engine the
// moment nothing does, which lets vanilla's own light effects keep running
// everywhere else.
// ===========================================================================
class GITD_Composite : StaticEventHandler
{
	// The map's own values, captured before anything touches them.
	//
	// NOT named baseLight/baseColor/addLight: ZScript identifiers are
	// case-insensitive, so a private field baseLight and the public method
	// BaseLight() below are the same symbol and the class refuses to compile.
	private Array<int> mapLight;
	private Array<int> mapColor;
	private Array<int> baseDesat;

	// This tic's accumulated wants.
	private Array<double> mulR, mulG, mulB;
	private Array<int> deltaLight;
	private Array<int> ovrLight;     // -1 = nobody is overriding
	private Array<int> wantDesat;

	// Sectors whose light WE last wrote, so we know which ones to hand back.
	private Array<bool> held;

	// The colour+desat we last actually wrote, packed. SetColor is not free --
	// the engine walks the sector's 3D-floor lightlist behind every call -- and
	// under a still preset the composed result is identical tic after tic. -1
	// means "never written", so the first tic always writes.
	private Array<int> lastWritten;

	private bool ready;

	static GITD_Composite Get()
	{
		return GITD_Composite(StaticEventHandler.Find("GITD_Composite"));
	}

	override void WorldLoaded(WorldEvent e)
	{
		int n = level.Sectors.Size();
		mapLight.Clear(); mapColor.Clear(); baseDesat.Clear();
		mulR.Clear(); mulG.Clear(); mulB.Clear();
		deltaLight.Clear(); ovrLight.Clear(); wantDesat.Clear(); held.Clear();
		lastWritten.Clear();

		for (int i = 0; i < n; i++)
		{
			Sector s = level.Sectors[i];
			Color c = s.ColorMap.LightColor;
			mapLight.Push(s.lightlevel);
			mapColor.Push((c.r << 16) | (c.g << 8) | c.b);
			baseDesat.Push(s.ColorMap.Desaturation);
			mulR.Push(1.0); mulG.Push(1.0); mulB.Push(1.0);
			deltaLight.Push(0); ovrLight.Push(-1); wantDesat.Push(0);
			held.Push(false);
			lastWritten.Push(-1);
		}
		ready = (n > 0);
	}

	// The map's own light level for a sector, whatever anyone has done to it
	// since. This is the number every effect should be working from -- reading
	// the LIVE level and adding to it is how the sweep once saturated every
	// room it touched to 255 in four tics and stayed there.
	static int BaseLight(int idx)
	{
		let c = Get();
		if (!c || idx < 0 || idx >= c.mapLight.Size()) return 0;
		return c.mapLight[idx];
	}

	static Color BaseColor(int idx)
	{
		let c = Get();
		if (!c || idx < 0 || idx >= c.mapColor.Size()) return Color(255, 255, 255, 255);
		int p = c.mapColor[idx];
		return Color(255, (p >> 16) & 255, (p >> 8) & 255, p & 255);
	}

	// --- the channels ----------------------------------------------------

	// Multiply this sector's colour by a tint. 255,255,255 is "no change".
	// Every caller's tint is multiplied in, so darkness at 65% and a red
	// setpiece land as a dark red room rather than as an argument.
	static void Tint(int idx, Color c)
	{
		let s = Get();
		if (!s || !s.ready || idx < 0 || idx >= s.mulR.Size()) return;
		s.mulR[idx] *= c.r / 255.0;
		s.mulG[idx] *= c.g / 255.0;
		s.mulB[idx] *= c.b / 255.0;
	}

	// Desaturation does not multiply sensibly, so the strongest request wins.
	static void Desaturate(int idx, int d)
	{
		let s = Get();
		if (!s || !s.ready || idx < 0 || idx >= s.wantDesat.Size()) return;
		if (d > s.wantDesat[idx]) s.wantDesat[idx] = d;
	}

	// Shift this sector's light, relative to what the MAP said it was.
	static void AddLight(int idx, int delta)
	{
		let s = Get();
		if (!s || !s.ready || idx < 0 || idx >= s.deltaLight.Size()) return;
		s.deltaLight[idx] += delta;
	}

	// Take the sector's light over completely for this tic. For effects that
	// are inherently absolute -- sonar decides what a room's level IS, it is
	// not nudging whatever the room happened to be.
	static void OverrideLight(int idx, int value)
	{
		let s = Get();
		if (!s || !s.ready || idx < 0 || idx >= s.ovrLight.Size()) return;
		s.ovrLight[idx] = clamp(value, 0, 255);
	}

	// --- the flush -------------------------------------------------------
	//
	// Registered LAST in mapinfo.txt, so every contributor has had its tick
	// before this runs. That is the only place ordering still matters, and it
	// matters in one direction only.

	override void WorldTick()
	{
		if (!ready) return;
		int n = min(level.Sectors.Size(), mulR.Size());

		for (int i = 0; i < n; i++)
		{
			Sector s = level.Sectors[i];

			// Colour: always safe to write, nothing else animates it -- but
			// only write when the composed result actually CHANGED. SetColor
			// walks the sector's 3D-floor lightlist internally, so on a still
			// preset this was paying that walk for every sector every tic to
			// write the bytes already there.
			int bp = mapColor[i];
			int br = (bp >> 16) & 255, bg = (bp >> 8) & 255, bb = bp & 255;
			int cr = clamp(int(br * mulR[i]), 0, 255);
			int cg = clamp(int(bg * mulG[i]), 0, 255);
			int cb = clamp(int(bb * mulB[i]), 0, 255);
			int ds = max(baseDesat[i], wantDesat[i]);

			int packed = (ds << 24) | (cr << 16) | (cg << 8) | cb;
			if (packed != lastWritten[i])
			{
				s.SetColor(Color(255, cr, cg, cb), ds);
				lastWritten[i] = packed;
			}

			// Light: only when asked, and handed straight back when not, so
			// Doom's own blinking and pulsing sectors keep working everywhere
			// this tic did not reach.
			if (ovrLight[i] >= 0)
			{
				s.SetLightLevel(ovrLight[i]);
				held[i] = true;
			}
			else if (deltaLight[i] != 0)
			{
				s.SetLightLevel(clamp(mapLight[i] + deltaLight[i], 0, 255));
				held[i] = true;
			}
			else if (held[i])
			{
				// Released. Put the map's own level back ONCE and stop
				// touching it -- keep writing and we are fighting thinkers.
				s.SetLightLevel(mapLight[i]);
				held[i] = false;
			}

			mulR[i] = 1.0; mulG[i] = 1.0; mulB[i] = 1.0;
			deltaLight[i] = 0;
			ovrLight[i] = -1;
			wantDesat[i] = 0;
		}
	}
}
