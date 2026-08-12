// ===========================================================================
// LASER GRID -- real beams, standing across a corridor.
//
// The sweep band fill already draws a lattice, and it is the wrong tool for
// this. A fill is a SURFACE effect: it patterns the band where the band
// touches a wall, so the "lasers" are painted onto geometry and there is
// nothing in the air between them. Walk into it and you walk through a
// picture of a laser grid.
//
// This is the other half. Each line of the grid is an actual beam -- a
// segment lit per pixel by distance from it, visible hanging in the air,
// depth-correct, and blooming on its own. See FORK_CHANGES.md section 13.
//
// THE TWO ARE MEANT TO BE USED TOGETHER. The fill gives you the lattice
// painted across every surface the band crosses, continuous around corners
// and up walls, which beams cannot do because a beam is straight. The beams
// give you the lines standing in the air between those surfaces, which the
// fill cannot do because a fill has no volume. Run both and the grid is
// drawn on the room AND present in it.
//
// EIGHT LINES, because that is the beam budget and a grid wants them all.
// Four across and four up is a convincing lattice; more would be a screen
// door, and fewer stops reading as a grid.
//
// IT RIDES THE SWEEP. With the sweep running, the grid sits at band 1's
// current distance and travels with it -- so the lattice comes down the hall
// at you. With the sweep off it stands at a fixed offset ahead of the map
// centre, which is what you want for a static tripwire.
// ===========================================================================
class GITD_LaserGrid abstract
{
	clearscope static double F(string n, double d) { let c = CVar.FindCVar(n); return c ? c.GetFloat() : d; }
	clearscope static int    I(string n, int d)    { let c = CVar.FindCVar(n); return c ? c.GetInt()   : d; }
	clearscope static bool   B(string n, bool d)   { let c = CVar.FindCVar(n); return c ? c.GetBool()  : d; }

	// Called from the play tic, because it needs the sweep's position and the
	// map's geometry to know where to stand.
	static void Push(Vector3 centre, double travelAngle)
	{
		// OFF HAS TO TELL THE ENGINE IT IS OFF.
		//
		// Returning early here left whatever beam count was last pushed still
		// set, so eight beams kept being evaluated for every fragment of every
		// draw, at stale positions, forever -- drawing garbage AND costing the
		// full per-pixel price of a feature that was switched off.
		//
		// A cvar that reads Off while the thing it names is still running is
		// the same fault as one that reads On while nothing happens, and this
		// one costs frames as well as trust.
		if (!B("gitd_lgrid_enabled", false))
		{
			level.SetBeamCount(0, 0.0, 0.0);
			return;
		}

		int across = clamp(I("gitd_lgrid_across", 4), 0, 8);
		int up     = clamp(I("gitd_lgrid_up", 4), 0, 8);
		if (across + up <= 0) { level.SetBeamCount(0, 0.4, 1.0); return; }

		// Trim to the beam budget rather than silently dropping the tail --
		// the vertical lines go first, because a grid missing its uprights
		// still reads as a grid and one missing its rungs does not.
		int total = across + up;
		if (total > 8) { up = max(0, 8 - across); total = across + up; }

		double halfW = F("gitd_lgrid_width", 128.0) * 0.5;
		double halfH = F("gitd_lgrid_height", 128.0) * 0.5;
		double thick = F("gitd_lgrid_thick", 1.2);
		double soft  = F("gitd_lgrid_soft", 2.5);
		double inten = F("gitd_lgrid_intensity", 1.6);

		int pk = I("gitd_lgrid_color", 0xFF1810);
		Color col = Color(255, (pk >> 16) & 255, (pk >> 8) & 255, pk & 255);

		// The grid stands ACROSS the direction of travel. Right is the axis
		// the horizontal rungs run along; up is world up. A grid built on the
		// travel axis instead would be a set of lines pointing at you, which
		// is invisible -- every one of them end-on.
		double a = travelAngle;
		Vector3 right = (cos(a + 90), sin(a + 90), 0);
		Vector3 upv   = (0, 0, 1);

		int slot = 0;

		// Rungs: horizontal, stacked up the opening.
		for (int i = 0; i < across && slot < 8; i++)
		{
			double t = (across == 1) ? 0.5 : double(i) / double(across - 1);
			double z = -halfH + 2.0 * halfH * t;
			Vector3 c = centre + upv * z;
			level.SetBeam(slot, c - right * halfW, c + right * halfW,
				thick, soft, col, inten);
			slot++;
		}

		// Uprights: vertical, spaced across it.
		for (int i = 0; i < up && slot < 8; i++)
		{
			double t = (up == 1) ? 0.5 : double(i) / double(up - 1);
			double x = -halfW + 2.0 * halfW * t;
			Vector3 c = centre + right * x;
			level.SetBeam(slot, c - upv * halfH, c + upv * halfH,
				thick, soft, col, inten);
			slot++;
		}

		level.SetBeamCount(slot, F("gitd_lgrid_glow", 0.5), 1.0);

		// The grid's own look. Scroll runs along each line, so energy travels
		// outward from the middle of every rung at once -- which reads as a
		// powered emitter array rather than eight static sticks.
		level.SetBeamLook(
			F("gitd_lgrid_air", 1.0),
			F("gitd_lgrid_scroll", 4.0),
			F("gitd_lgrid_scroll_depth", 0.20),
			0.0,                              // no taper: a grid line is even
			0.0);                             // and no impact flare, it has no impact
	}
}
