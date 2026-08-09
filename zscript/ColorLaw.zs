// ===========================================================================
// Colour law: the room's colour is the rule in force.
//
// The glow lanes already cycle through eight colours, and per-slot hold times
// give each colour a DURATION. This makes the colour mean something: one lane
// is the CONDUCTOR, and whichever colour slot it is currently wearing can
// carry a law -- monsters tougher, monsters faster, health raining onto a
// grid -- that holds exactly as long as the colour does.
//
// The player never reads a HUD for this. The room IS the readout: walls gone
// red and everything is angrier; gone green and the floor blooms with health.
// Set colour 3's hold to ten seconds and its law to "faster" and you have
// built a recurring danger phase with two menu rows.
//
// LAWS APPLY ON THE PHASE EDGE, NOT PER TIC. Entering a slot walks the
// monsters once and applies; leaving it walks once and reverts. Monsters that
// spawn mid-phase are missed on purpose -- a per-tic walk is the cost this
// deliberately avoids, and a half-populated law reads fine in play. The
// pickup rains tick on their own timer while their phase holds.
//
// Reverts are exact inverses (multiply, then divide), so a monster that
// lived through three phases carries nothing away. Health floors at 1 rather
// than killing -- a law may weaken, never execute.
// ===========================================================================
class GITD_ColorLaw : StaticEventHandler
{
	int lastSlot;
	int rainCountdown;

	// What we applied, so the exit revert undoes exactly what the enter did
	// even if the cvars moved mid-phase.
	int appliedFx;
	double appliedStrength;

	// Rained pickups awaiting expiry.
	Array<Actor> rained;
	Array<int> rainedUntil;

	// Map bounds for the rain grid, measured once per map.
	Vector2 bmin, bmax;

	override void WorldLoaded(WorldEvent e)
	{
		lastSlot = -1;
		appliedFx = 0;
		rainCountdown = 0;
		rained.Clear();
		rainedUntil.Clear();

		bmin = ( 1e9,  1e9);
		bmax = (-1e9, -1e9);
		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			Vector2 c = level.Sectors[i].centerspot;
			bmin = (min(bmin.x, c.x), min(bmin.y, c.y));
			bmax = (max(bmax.x, c.x), max(bmax.y, c.y));
		}
	}

	GITD_Lane Conductor()
	{
		let h = GITD_Handler(StaticEventHandler.Find("GITD_Handler"));
		if (!h) return null;
		int which = CVar.FindCVar("gitd_law_lane").GetInt();
		if (which == 0) return h.wb;
		if (which == 1) return h.wt;
		if (which == 2) return h.cg;
		return h.fg;
	}

	override void WorldTick()
	{
		ExpireRain();

		if (!CVar.FindCVar("gitd_law_enabled").GetBool())
		{
			// Switched off mid-phase: lift whatever law is standing.
			if (appliedFx != 0) RevertLaw();
			lastSlot = -1;
			return;
		}

		let lane = Conductor();
		if (!lane) return;

		int slot = lane.slotIndex;
		if (slot != lastSlot)
		{
			if (appliedFx != 0) RevertLaw();
			lastSlot = slot;
			int fx = CVar.FindCVar("gitd_law_fx" .. (slot + 1)).GetInt();
			ApplyLaw(fx);
			rainCountdown = 0;   // a rain phase rains immediately on entry
		}

		// Rain ticks while its phase holds.
		if (appliedFx == 5 || appliedFx == 6)
		{
			if (rainCountdown-- <= 0)
			{
				rainCountdown = int(max(CVar.FindCVar("gitd_law_rain_every").GetFloat(), 1.0) * 35.0);
				Rain(appliedFx == 5 ? "HealthBonus" : "ArmorBonus");
			}
		}
	}

	// ---- monster laws ---------------------------------------------------

	void ApplyLaw(int fx)
	{
		appliedFx = fx;
		appliedStrength = max(CVar.FindCVar("gitd_law_strength").GetFloat(), 1.05);
		if (fx < 1 || fx > 4) return;

		double s = appliedStrength;
		ThinkerIterator it = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bISMONSTER || a.health <= 0) continue;
			if (fx == 1) a.A_SetHealth(max(int(a.health * s), 1));
			else if (fx == 2) a.A_SetHealth(max(int(a.health / s), 1));
			else if (fx == 3) a.Speed = a.Speed * s;
			else if (fx == 4) a.Speed = a.Speed / s;
		}
	}

	void RevertLaw()
	{
		int fx = appliedFx;
		double s = appliedStrength;
		appliedFx = 0;
		if (fx < 1 || fx > 4) return;

		ThinkerIterator it = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bISMONSTER || a.health <= 0) continue;
			if (fx == 1) a.A_SetHealth(max(int(a.health / s), 1));
			else if (fx == 2) a.A_SetHealth(max(int(a.health * s), 1));
			else if (fx == 3) a.Speed = a.Speed / s;
			else if (fx == 4) a.Speed = a.Speed * s;
		}
	}

	// ---- pickup rain ----------------------------------------------------
	//
	// A grid across the whole map's footprint, each point dropped onto the
	// floor of whatever sector it lands in. Points inside walls fail
	// TestMobjLocation and are discarded, so irregular maps just get an
	// irregular rain -- which looks intentional, because it is.

	void Rain(string cls)
	{
		int gx = clamp(CVar.FindCVar("gitd_law_rain_x").GetInt(), 1, 16);
		int gy = clamp(CVar.FindCVar("gitd_law_rain_y").GetInt(), 1, 16);
		int life = int(max(CVar.FindCVar("gitd_law_rain_life").GetFloat(), 1.0) * 35.0);
		if (bmax.x <= bmin.x || bmax.y <= bmin.y) return;

		for (int ix = 0; ix < gx; ix++)
		{
			for (int iy = 0; iy < gy; iy++)
			{
				Vector2 p = (
					bmin.x + (ix + 0.5) * (bmax.x - bmin.x) / gx,
					bmin.y + (iy + 0.5) * (bmax.y - bmin.y) / gy);
				Sector sec = level.PointInSector(p);
				if (!sec) continue;
				Vector3 at = (p.x, p.y, sec.floorplane.ZatPoint(p));
				let a = Actor.Spawn(cls, at, ALLOW_REPLACE);
				if (!a) continue;
				if (!a.TestMobjLocation()) { a.Destroy(); continue; }
				rained.Push(a);
				rainedUntil.Push(level.maptime + life);
			}
		}
	}

	void ExpireRain()
	{
		for (int i = rained.Size() - 1; i >= 0; i--)
		{
			let a = rained[i];
			if (!a)
			{
				// Collected, or otherwise gone. Either way, done tracking.
				rained.Delete(i); rainedUntil.Delete(i);
				continue;
			}
			if (level.maptime >= rainedUntil[i])
			{
				a.Destroy();
				rained.Delete(i); rainedUntil.Delete(i);
			}
		}
	}
}
