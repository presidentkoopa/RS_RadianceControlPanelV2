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
		int s = cv ? cv.GetInt() : 1;
		if (s <= 0) return LevelLocals.BB_TEXT;
		if (s == 1) return LevelLocals.BB_SEGMENT;
		return LevelLocals.BB_SEGLCD;
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
	int floorTag, aboveTag;

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
