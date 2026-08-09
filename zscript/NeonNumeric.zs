// ============================================================================
// GITD Neon Numeric Engine -- the "do this" over the engine's "that".
//
// The engine (E:\UZDXREMA) provides the capability: billboard payloads that
// draw text and numbers in the world. It has no opinion about when a number
// should appear or what colour it ought to be. This file is that opinion, and
// the menu over it is where a player changes it.
//
// THREE LOOKS, one call. The engine exposes them as separate payloads; here
// they are a single cvar, because to a player they are three settings of one
// thing rather than three features.
//
//   FONT     BB_TEXT     real typeface out of an SDF atlas. Arbitrary
//                        characters, any of the arcade fonts. Best for names
//                        and labels -- anything you read as words.
//   LED      BB_SEGMENT  sixteen-segment display, dark bed with glowing bars.
//                        No atlas at all; the glyphs are arithmetic. Best for
//                        numbers, which is what segment displays are for.
//   LCD      BB_SEGLCD   the same display inverted -- a lit face with the
//                        characters punched out dark. This is the look GITD's
//                        original wgType 13 had.
//
// COLOUR IS DELIBERATELY NOT DECIDED HERE. Every call takes an optional
// colour and falls back to the menu's when it is not given. GITD cannot reach
// into a gameplay mod to ask what tier something was -- and should not, since
// it has to work standalone -- so a mod that knows better passes its own.
// RS_Main should hand these RS_TierPalette.RGB(tier) and never touch the cvar.
//
// NOTHING HERE SPAWNS AN ACTOR. Billboards are level-owned with their own
// lifetimes, which is the whole reason the engine grew them; a number is a
// picture, not a thinker. Above() rides an actor that already exists rather
// than creating one.
// ============================================================================

class GITD_Neon
{
	// ---- menu-backed defaults -------------------------------------------

	static bool Enabled()
	{
		let cv = CVar.FindCVar('gitd_neon_enabled');
		return cv ? cv.GetBool() : true;
	}

	// Maps the single player-facing "style" onto whichever payload draws it.
	static int Payload()
	{
		let cv = CVar.FindCVar('gitd_neon_style');
		int s = cv ? cv.GetInt() : 3;
		if (s <= 0) return LevelLocals.BB_TEXT;
		if (s == 1) return LevelLocals.BB_SEGMENT;
		if (s == 2) return LevelLocals.BB_SEGLCD;
		return LevelLocals.BB_WG13;
	}

	// WG13 is not interchangeable with the others at the call site: it takes
	// the NUMBER in `data` where they take packed glow, and it needs its
	// progress driven every tic. Anything generic has to check.
	static bool IsWG13()
	{
		let cv = CVar.FindCVar('gitd_neon_style');
		return (cv ? cv.GetInt() : 3) >= 3;
	}

	// GITD's own sizing, which is what makes it a lozenge instead of a circle:
	// halfH is fixed and halfW grows with the digit count.
	static double, double BadgeSize(int digits, bool big = false)
	{
		if (digits < 1) digits = 1;
		double halfH = (big ? 46.0 : 34.0) * Scale();
		double halfW = halfH * (0.60 + digits * 0.42);
		return halfW * 2.0, halfH * 2.0;
	}

	static Color MenuColor()
	{
		let cv = CVar.FindCVar('gitd_neon_color');
		if (!cv) return Color(255, 40, 255, 255);
		// Byte-wise, not Color(int) -- see the note in GlowHandler.zs. The
		// implicit conversion does not exist and fails at LOAD, not compile.
		int packed = cv.GetInt();
		return Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);
	}

	static double Scale()
	{
		let cv = CVar.FindCVar('gitd_neon_scale');
		double s = cv ? cv.GetFloat() : 1.0;
		return clamp(s, 0.25, 4.0);
	}

	static double Life()
	{
		let cv = CVar.FindCVar('gitd_neon_life');
		return cv ? clamp(cv.GetFloat(), 0.2, 60.0) : 2.5;
	}

	// Packed once here so no caller does bit arithmetic, and so a menu change
	// reaches every future number without touching a call site.
	static int Glow()
	{
		let cr = CVar.FindCVar('gitd_neon_glow_reach');
		let cs = CVar.FindCVar('gitd_neon_glow_strength');
		double r = cr ? cr.GetFloat() : 0.6;
		double s = cs ? cs.GetFloat() : 0.75;
		return LevelLocals.BBGlow(r, s);
	}

	// A number wants a wider box than a word; both want to be readable from
	// across a room, so size follows the string rather than being fixed.
	// Unpacked and re-returned rather than forwarded directly: ZScript will
	// not pass a two-value return straight through as an expression -- it
	// counts that as returning one thing and rejects it.
	static double, double MeasureFor(string text)
	{
		double w, h;
		[w, h] = Extent(text, Scale());
		return w, h;
	}

	private static double, double Extent(string text, double scale)
	{
		int n = text.Length();
		if (n < 1) n = 1;
		double h = 22.0 * scale;
		double w = h * 0.78 * n;
		return w, h;
	}

	// ---- the three placements -------------------------------------------

	// Fire and forget, in the air, turning to face the player. Expires on its
	// own -- no handle, nothing to clean up, nothing to leak.
	static void Pop(Vector3 pos, string text, Color col = 0, double scale = 1.0)
	{
		if (!Enabled() || text.Length() == 0) return;
		double w, h;
		[w, h] = Extent(text, Scale() * scale);
		level.AddBillboard(pos, w, h, 0, 0,
			LevelLocals.BBF_CAMERAYAW, Payload(), Glow(),
			col == 0 ? MenuColor() : col,
			0, Life(), text);
	}

	// Burned into the ground. tilt 90 lays the quad flat, which is what makes
	// this a floor mark rather than a sign standing on the floor.
	//
	// It does NOT follow slopes or steps -- one quad is one plane. Put these
	// on level ground.
	static void Mark(Vector3 pos, string text, Color col = 0, double scale = 1.0, bool permanent = false)
	{
		if (!Enabled() || text.Length() == 0) return;
		double w, h;
		[w, h] = Extent(text, Scale() * scale);
		// Lifted clear of the floor: flush would z-fight, higher would visibly
		// hover.
		Vector3 p = (pos.x, pos.y, pos.z + 4);
		if (permanent)
			level.AddBillboardPersistent(p, w, h, 0, 90,
				LevelLocals.BBF_FIXED, Payload(), Glow(),
				col == 0 ? MenuColor() : col, 0, 0, text);
		else
			level.AddBillboard(p, w, h, 0, 90,
				LevelLocals.BBF_FIXED, Payload(), Glow(),
				col == 0 ? MenuColor() : col, 0, Life(), text);
	}

	// Rides an actor that already exists and dies with it. Returns a handle so
	// a live readout can be restrung with level.SetBillboardText().
	static int Above(Actor mo, string text, Color col = 0, double scale = 1.0)
	{
		if (!Enabled() || mo == null || text.Length() == 0) return 0;
		double w, h;
		[w, h] = Extent(text, Scale() * scale);
		return level.AttachBillboard(mo, (0, 0, mo.Height + 10), w, h, 0, 0,
			LevelLocals.BBF_CAMERAYAW, Payload(), Glow(),
			col == 0 ? MenuColor() : col, 0, text);
	}

	// ---- seam -----------------------------------------------------------

	// A glowing slit. Returns a handle; widen it with level.ResizeBillboard()
	// to open it -- the engine has no progress term on purpose, so the easing
	// belongs to whoever owns the effect.
	//
	// vertical: false lays it in the floor, true stands it up as a door.
	// hole: dark interior with a burning rim, for anything meant to come OUT.
	static int Seam(Vector3 pos, double length, bool vertical = false, bool hole = true, Color col = 0)
	{
		if (!Enabled()) return 0;
		int flags = hole ? LevelLocals.BBFL_VOID : 0;
		return level.AddBillboardPersistent(pos, 6, length, 0, vertical ? 0 : 90,
			LevelLocals.BBF_FIXED, LevelLocals.BB_SEAM, Glow(),
			col == 0 ? MenuColor() : col, flags, 0);
	}
}

// ============================================================================
// GITD_NeonKillCounter -- the readout, and the only thing here that watches
// the game.
//
// GITD_Neon above is a drawing library with no opinions. This is the one piece
// that decides a number should exist, which is why it is the only class in the
// file that is an EventHandler.
//
// PLACEMENT IS ONE SETTING, TWO ORIENTATIONS, and both are player-facing.
// BBF_CAMERAYAW overrides a billboard's yaw but PRESERVES its tilt, so the
// same flag that turns an upright readout toward you also spins a flat one on
// the ground to keep its text the right way up from where you are standing.
// A floor mark that reads backwards when you walk round it is the thing that
// makes floor text feel broken, and this is why it does not.
// ============================================================================

class GITD_NeonKillCounter : EventHandler
{
	int kills;

	// Live WG13 badges. They are one-shots that have to be OPENED and CLOSED
	// -- 12 tics out, hold, 14 tics back, then gone -- so unlike every other
	// payload here they need driving. Tracked as parallel arrays rather than
	// objects because there are never many and this is per-tic code.
	Array<int> bid;
	Array<int> bage;
	Array<int> blife;

	// Marks that were told to stay. Tracked separately so the count can be
	// capped without touching the ones still animating.
	Array<int> perm;

	private static int Placement()
	{
		let cv = CVar.FindCVar('gitd_neon_kc_place');
		return cv ? cv.GetInt() : 1;		// 0 floor, 1 above, 2 both
	}

	private static bool Running()
	{
		let cv = CVar.FindCVar('gitd_neon_killcount');
		return cv && cv.GetBool() && GITD_Neon.Enabled();
	}

	// 0 close again (the original), 1 fade out, 2 stay put.
	private static int Linger()
	{
		let cv = CVar.FindCVar('gitd_neon_kc_linger');
		return cv ? clamp(cv.GetInt(), 0, 2) : 0;
	}

	private static int Digits()
	{
		let cv = CVar.FindCVar('gitd_neon_kc_digits');
		return cv ? clamp(cv.GetInt(), 1, 9) : 4;
	}

	// Zero-padded to a fixed width, because a readout that changes WIDTH as it
	// counts reads as a different object each time rather than as the same
	// display ticking over. This is why a segment font is the right choice for
	// it and a proportional typeface is not.
	private static string Pad(int n, int width)
	{
		string s = String.Format("%d", n);
		while (s.Length() < uint(width)) s = "0" .. s;
		return s;
	}

	override void WorldLoaded(WorldEvent e)
	{
		kills = 0;
		bid.Clear(); bage.Clear(); blife.Clear();
	}

	private void Spawn13(Vector3 pos, double w, double h, double tilt, int num, bool big)
	{
		int id = level.AddBillboardPersistent(pos, w, h, 0, tilt,
			LevelLocals.BBF_CAMERAYAW, LevelLocals.BB_WG13, num,
			GITD_Neon.MenuColor(), 0, 0);
		if (id == 0) return;
		level.SetBillboardProgress(id, 0.05);
		bid.Push(id); bage.Push(0); blife.Push(big ? 80 : 60);

		// Permanent marks accumulate, and billboards are a finite budget --
		// a long session would quietly fill it and start starving everything
		// else. Keep the most recent and retire the rest.
		if (Linger() == 2)
		{
			while (perm.Size() >= 64)
			{
				level.RemoveBillboard(perm[0]);
				perm.Delete(0);
			}
			perm.Push(id);
		}
	}

	// GITD_SeamBox's own curve: 12 tics to open, hold, 14 to close, then gone.
	override void WorldTick()
	{
		for (int i = bid.Size() - 1; i >= 0; i--)
		{
			int age = bage[i] + 1;
			bage[i] = age;
			int life = blife[i];

			int mode = Linger();

			// STAY: open, then stop being driven. Left at full and handed to
			// the permanent list, which caps itself.
			if (mode == 2)
			{
				double op = (age < 12) ? age / 12.0 : 1.0;
				level.SetBillboardProgress(bid[i], clamp(op, 0.05, 1.0));
				if (age >= 12) { bid.Delete(i); bage.Delete(i); blife.Delete(i); }
				continue;
			}

			if (age > life)
			{
				level.RemoveBillboard(bid[i]);
				bid.Delete(i); bage.Delete(i); blife.Delete(i);
				continue;
			}

			double prog;
			if (age < 12)             prog = age / 12.0;
			else if (age > life - 14) prog = (life - age) / 14.0;
			else                      prog = 1.0;

			// FADE: hold the plate open and take the alpha down instead of
			// closing it. Shutting AND fading at once reads as a glitch --
			// pick one exit, not both.
			if (mode == 1)
			{
				prog = (age < 12) ? age / 12.0 : 1.0;
				double a = (age > life - 20) ? (life - age) / 20.0 : 1.0;
				level.SetBillboardAlpha(bid[i], clamp(a, 0.0, 1.0));
			}

			level.SetBillboardProgress(bid[i], clamp(prog, 0.05, 1.0));
		}
	}

	override void WorldThingDied(WorldEvent e)
	{
		if (!Running()) return;
		if (e.Thing == null || !e.Thing.bISMONSTER) return;
		// Only kills the player earned; infighting is not a score.
		if (e.Thing.target == null || !(e.Thing.target is "PlayerPawn")) return;

		kills++;
		string txt = Pad(kills, Digits());
		int place = Placement();

		// The original: a lozenge badge that opens, shows the number, closes.
		// Digits only, and the number rides in `data`.
		if (GITD_Neon.IsWG13())
		{
			bool big = (kills % 10) == 0;			// milestone kills get the larger badge
			double w, h;
			[w, h] = GITD_Neon.BadgeSize(txt.Length(), big);

			if (place == 0 || place == 2)
				Spawn13((e.Thing.pos.x, e.Thing.pos.y, e.Thing.floorz + 4), w, h, 90, kills, big);
			if (place == 1 || place == 2)
				Spawn13(e.Thing.pos + (0, 0, e.Thing.Height + 12), w, h, 0, kills, big);
			return;
		}

		// Flat on the ground where it fell. Still yaw-tracks the player, so it
		// never reads upside down.
		if (place == 0 || place == 2)
		{
			Vector3 p = (e.Thing.pos.x, e.Thing.pos.y, e.Thing.floorz + 4);
			double w, h;
			[w, h] = GITD_Neon.MeasureFor(txt);
			level.AddBillboard(p, w, h, 0, 90,
				LevelLocals.BBF_CAMERAYAW, GITD_Neon.Payload(), GITD_Neon.Glow(),
				GITD_Neon.MenuColor(), 0, GITD_Neon.Life(), txt);
		}

		// In the air over the corpse.
		if (place == 1 || place == 2)
		{
			Vector3 p = e.Thing.pos + (0, 0, e.Thing.Height + 12);
			GITD_Neon.Pop(p, txt);
		}
	}
}

// ============================================================================
// GITD_SeamStrip -- a seam that survives stairs.
//
// A billboard is one flat plane, so a long seam laid across stepped ground
// clips into the high step and floats over the low one. That is not fixable in
// the shader and never was: the quad genuinely is flat.
//
// So this is not one seam. It is N short ones laid end to end along a line,
// each asking the floor UNDER ITSELF how high it is. Steps come out stepped
// and slopes come out faceted, and with enough segments a faceted slope is
// indistinguishable from a smooth one.
//
// Sampling is against the sector's FLOORPLANE rather than its floor height,
// so a sloped sector gives the height at that exact point rather than the
// height of the sector generally.
//
// NOT AN ACTOR, and not a thinker. It is a plain Object holding handles --
// whoever owns it calls Open() and Remove(). Billboards already have their own
// lifetimes; adding a thinker per seam would put load on the playsim for
// something that is a picture.
// ============================================================================

class GITD_SeamStrip
{
	Array<int> parts;
	Vector2 dir;			// along the seam
	double segLen;
	double width;			// full open width, per segment

	// centre/angle describe the LINE the seam runs along; length is how far it
	// runs; openWidth is how wide it gets when fully open.
	static GITD_SeamStrip Create(Vector3 centre, double length, double angle,
		double openWidth = 70, int segments = 8, bool hole = true, Color col = 0)
	{
		if (!GITD_Neon.Enabled()) return null;
		if (segments < 1) segments = 1;

		let st = new("GITD_SeamStrip");
		st.dir = (cos(angle), sin(angle));
		st.segLen = length / segments;
		st.width = openWidth;

		Color use = (col == 0) ? GITD_Neon.MenuColor() : col;
		int glow = GITD_Neon.Glow();
		int flags = hole ? LevelLocals.BBFL_VOID : 0;

		for (int i = 0; i < segments; i++)
		{
			// Centre of this segment along the line.
			double t = (i + 0.5) / segments - 0.5;
			Vector2 xy = centre.xy + st.dir * (t * length);

			// The whole point: this segment's OWN floor, not the strip's.
			double fz = centre.z;
			let sec = level.PointInSector(xy);
			if (sec) fz = sec.floorplane.ZatPoint(xy) + 4;

			// Starts closed -- a hairline. Open() widens it.
			int id = level.AddBillboardPersistent((xy.x, xy.y, fz),
				2, st.segLen * 1.04, angle, 90,
				LevelLocals.BBF_FIXED, LevelLocals.BB_SEAM, glow,
				use, flags | LevelLocals.BBFL_NOHIT, 0);
			if (id != 0) st.parts.Push(id);
		}
		return st;
	}

	// t 0..1. Segments overlap slightly (1.04 above) so the join between them
	// does not show as a dark seam in the seam.
	void Open(double t)
	{
		t = clamp(t, 0.0, 1.0);
		double w = 2 + (width - 2) * t;
		for (int i = 0; i < parts.Size(); i++)
			level.ResizeBillboard(parts[i], w, segLen * 1.04);
	}

	void Recolor(Color col, Color grad = 0)
	{
		for (int i = 0; i < parts.Size(); i++)
		{
			level.UpdateBillboard(parts[i], 0, col);
			if (grad != 0) level.SetBillboardGradient(parts[i], grad);
		}
	}

	void Remove()
	{
		for (int i = 0; i < parts.Size(); i++) level.RemoveBillboard(parts[i]);
		parts.Clear();
	}
}
