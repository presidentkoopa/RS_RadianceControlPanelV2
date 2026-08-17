// ============================================================================
//  Environmental FancyWorld -- the map scan.
// ============================================================================
//
//  RESTORED after removal. Walls, floors, ceilings and things are all back:
//  the claim lattice, all texture tables and all four scan passes work as
//  they did before. Only the klaxon (and gitd_voice, which fed it and the
//  wall/floor dialects) stays out, held on a separate decision.
//
//  IndexLiquids() is NOT gated on fw_enabled here, unlike before removal --
//  that was a deliberate call, not an oversight, made when footsteps and the
//  liquid fog tint were kept on their own. It stays that way through this
//  restoration: the fog reading survives however much of the rest comes back.
//
// ============================================================================

class GITD_LiquidIndex : EventHandler
{
	private FancyTexTable floorTable, ceilTable, wallTable;

	// The claim lattice. One bit per emitter kind per cell, so an emitter of a
	// DIFFERENT kind may still share a cell -- a wall light and a computer hum
	// on the same stretch of wall are both wanted. See ClaimCell.
	private Array<int>	claim;
	private double		claimStep;
	private int			claimW, claimH;
	private double		originX, originY, spanX, spanY;

	override void WorldLoaded(WorldEvent e)
	{
		IndexLiquids();

		if (!FancySettings.GetBool("fw_enabled", true)) return;

		MeasureMap();

		floorTable = FancyTexTable.BuildFloors();
		ceilTable  = FancyTexTable.BuildCeilings();
		wallTable  = FancyTexTable.BuildWalls();

		SpawnFloorActors();
		SpawnCeilingActors();
		SpawnWallActors();
		SpawnThingActors();

		// Nothing below needs it again, and on a big map it is the largest
		// thing this handler ever allocated.
		claim.Clear();
	}

	// ---- the liquid index ------------------------------------------------
	//
	// Which sectors hold liquid, and what colour mist belongs over each.
	private Array<int> liqSec;
	private Array<int> liqTint;

	private void IndexLiquids()
	{
		liqSec.Clear();
		liqTint.Clear();

		let fog = FancyTexTable.BuildFog();
		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			int row = fog.Find(level.Sectors[i].GetTexture(Sector.floor));
			if (row != 0)
			{
				liqSec.Push(i);
				liqTint.Push(fog.RowTint(row));
				continue;
			}

			// THE TERRAIN KNOWS THINGS THE TABLE DOES NOT.
			//
			// A TERRAIN lump marks flats `liquid`, and a liquid pack ships one
			// covering flats this table has never heard of -- FreeDoom's
			// SWATER, Eviternity's OBLODA and OSLUDG, whatever the next WAD
			// invents. Those sectors ARE liquid, authoritatively, and the fog
			// should tint over them.
			//
			// What the terrain cannot say is what COLOUR. It has a splash
			// class and a sound, not a hue. So these get the neutral slime
			// green rather than being guessed at from a name nobody here
			// recognises -- present and slightly wrong beats absent, and the
			// table still wins wherever it has an opinion, which is why this
			// is the second test and not the first.
			int tn = level.Sectors[i].terrainnum[Sector.floor];
			if (tn >= 0 && tn < Terrains.Size() && Terrains[tn].IsLiquid)
			{
				liqSec.Push(i);
				liqTint.Push(0x3E8C24);
			}
		}
	}

	// The nearest liquid to a point, and the colour its mist should take.
	//
	// Standing in it wins outright regardless of distance -- without that,
	// wading a narrow channel could hand the answer to a larger pool whose
	// CENTRE happens to be closer than the channel's is.
	//
	// Centre-spot distance for everything else, which is approximate and
	// deliberately so: this picks a hue for the air in a room, and a hue does
	// not need to know exactly where the edge of a pool is.
	bool, Color NearestLiquid(Vector2 p, double range)
	{
		let sec = Sector.PointInSector(p);
		if (sec)
		{
			for (int i = 0; i < liqSec.Size(); i++)
			{
				if (level.Sectors[liqSec[i]] != sec) continue;
				return true, liqTint[i];
			}
		}

		double best = range * range;
		int hit = -1;
		for (int i = 0; i < liqSec.Size(); i++)
		{
			double d2 = (level.Sectors[liqSec[i]].centerspot - p).LengthSquared();
			if (d2 >= best) continue;
			best = d2;
			hit = i;
		}

		if (hit < 0) return false, 0;
		return true, liqTint[hit];
	}

	// ---- the claim lattice ----------------------------------------------

	// Bounds from the geometry rather than from the format's theoretical
	// limits. A one-room map has no business allocating for a 64k square.
	private void MeasureMap()
	{
		double lox = 32768.0, loy = 32768.0, hix = -32768.0, hiy = -32768.0;

		for (int i = 0; i < level.Lines.Size(); i++)
		{
			let l = level.Lines[i];
			Vector2 a = l.v1.p, b = l.v2.p;
			lox = min(lox, min(a.x, b.x));
			loy = min(loy, min(a.y, b.y));
			hix = max(hix, max(a.x, b.x));
			hiy = max(hiy, max(a.y, b.y));
		}

		if (hix < lox || hiy < loy) { lox = loy = 0; hix = hiy = 1; }

		originX = lox - 256;
		originY = loy - 256;
		spanX = (hix + 256) - originX;
		spanY = (hiy + 256) - originY;
	}

	// Sized per pass, because different passes want different spacings and
	// neither should have to see the other's claims.
	private void ResetClaims(double step)
	{
		claimStep = max(16.0, step);

		claimW = int(spanX / claimStep) + 2;
		claimH = int(spanY / claimStep) + 2;

		int total = claimW * claimH;
		claim.Clear();
		claim.Resize(total);
		for (int i = 0; i < total; i++) claim[i] = 0;
	}

	// Returns false if this kind of emitter already owns the cell.
	//
	// One BIT per row rather than one value, so a cell can hold a wall light
	// and a computer hum at once without either evicting the other's claim --
	// storing the row number instead would let the second kind overwrite the
	// first, and then a third of the first kind could re-take the same cell.
	// No table here comes close to 32 rows; the guard is for the day one does.
	private bool ClaimCell(Vector2 p, int row)
	{
		int cx = int((p.x - originX) / claimStep);
		int cy = int((p.y - originY) / claimStep);
		if (cx < 0 || cy < 0 || cx >= claimW || cy >= claimH) return true;
		if (row > 32) return true;

		int i = cy * claimW + cx;
		int bit = 1 << (row - 1);
		if (claim[i] & bit) return false;
		claim[i] |= bit;
		return true;
	}

	// ---- floors ------------------------------------------------------------

	private void SpawnFloorActors()
	{
		double step = max(64.0, FancySettings.GetFloat("fw_spacing", 256.0));
		ResetClaims(step);

		for (int s = 0; s < level.Sectors.Size(); s++)
		{
			let sec = level.Sectors[s];

			// The whole speedup, in one line: sectors that are not liquid are
			// rejected here, before a single sample point exists.
			int row = floorTable.Find(sec.GetTexture(Sector.floor));
			if (row == 0) continue;

			Name cls = floorTable.RowClass(row);

			// Small sectors -- teleporter pads, the puddle in a corner -- get
			// one emitter at the centre and skip sampling entirely.
			Vector2 lo, hi;
			[lo, hi] = SectorBounds(sec);
			if (hi.x - lo.x <= step && hi.y - lo.y <= step)
			{
				Vector2 c = sec.centerspot;
				if (Sector.PointInSector(c) == sec)
				{
					if (ClaimCell(c, row)) PlaceFloor(cls, c, sec);
					continue;
				}
			}

			// Snapped to the global lattice, so neighbouring sectors of the
			// same liquid line up instead of interleaving.
			double sx = originX + floor((lo.x - originX) / step) * step;
			double sy = originY + floor((lo.y - originY) / step) * step;

			for (double y = sy; y <= hi.y; y += step)
			{
				for (double x = sx; x <= hi.x; x += step)
				{
					Vector2 p = (x, y);

					// Confirms the point is in THIS sector, which is what
					// makes concave and doughnut-shaped sectors behave.
					if (Sector.PointInSector(p) != sec) continue;
					if (!ClaimCell(p, row)) continue;

					PlaceFloor(cls, p, sec);
				}
			}
		}
	}

	private void PlaceFloor(Name cls, Vector2 p, Sector sec)
	{
		Actor.Spawn((class<Actor>)(cls), (p.x, p.y, sec.floorplane.ZAtPoint(p)));
	}

	// ---- ceilings ------------------------------------------------------

	private void SpawnCeilingActors()
	{
		// Ceiling emitters are lights and open sky, both of which read fine
		// at a coarser spacing than liquid does.
		double step = max(64.0, FancySettings.GetFloat("fw_spacing", 256.0)) * 1.5;
		ResetClaims(step);

		for (int s = 0; s < level.Sectors.Size(); s++)
		{
			let sec = level.Sectors[s];

			int row = ceilTable.Find(sec.GetTexture(Sector.ceiling));
			if (row == 0) continue;

			Name cls = ceilTable.RowClass(row);

			Vector2 lo, hi;
			[lo, hi] = SectorBounds(sec);
			if (hi.x - lo.x <= step && hi.y - lo.y <= step)
			{
				Vector2 c = sec.centerspot;
				if (Sector.PointInSector(c) == sec)
				{
					if (ClaimCell(c, row)) PlaceCeiling(cls, c, sec);
					continue;
				}
			}

			double sx = originX + floor((lo.x - originX) / step) * step;
			double sy = originY + floor((lo.y - originY) / step) * step;

			for (double y = sy; y <= hi.y; y += step)
			{
				for (double x = sx; x <= hi.x; x += step)
				{
					Vector2 p = (x, y);
					if (Sector.PointInSector(p) != sec) continue;
					if (!ClaimCell(p, row)) continue;
					PlaceCeiling(cls, p, sec);
				}
			}
		}
	}

	private void PlaceCeiling(Name cls, Vector2 p, Sector sec)
	{
		// Hung just under the ceiling rather than at it, so the light it
		// carries has somewhere to fall from.
		double z = sec.ceilingplane.ZAtPoint(p) - 12.0;
		double fz = sec.floorplane.ZAtPoint(p);
		Actor.Spawn((class<Actor>)(cls), (p.x, p.y, max(fz, z)));
	}

	// ---- shared --------------------------------------------------------
	//
	// A sector's own linedefs are the only description of its extent that
	// ZScript exposes, and they are exact.
	private Vector2, Vector2 SectorBounds(Sector sec)
	{
		double lox = 32768.0, loy = 32768.0, hix = -32768.0, hiy = -32768.0;

		for (int i = 0; i < sec.lines.Size(); i++)
		{
			let l = sec.lines[i];
			Vector2 a = l.v1.p, b = l.v2.p;
			lox = min(lox, min(a.x, b.x));
			loy = min(loy, min(a.y, b.y));
			hix = max(hix, max(a.x, b.x));
			hiy = max(hiy, max(a.y, b.y));
		}

		if (hix < lox) { Vector2 c = sec.centerspot; return c, c; }
		return (lox, loy), (hix, hiy);
	}

	// ---- walls -----------------------------------------------------------

	private void SpawnWallActors()
	{
		double step = max(16.0, FancySettings.GetFloat("fw_wall_spacing", 64.0));
		ResetClaims(step);

		for (int i = 0; i < level.Lines.Size(); i++)
		{
			Line l = level.Lines[i];

			double lineLen = l.delta.Length();
			if (lineLen <= 0) continue;

			Vector2 mid = level.Vec2Offset(l.v1.p, l.delta.Unit() * (lineLen * 0.5));

			// NOT named "side": ZScript identifiers are case-insensitive, so a
			// local called side shadows the Side struct and Side.top stops
			// resolving to anything.
			for (int sidx = 0; sidx < 2; sidx++)
			{
				let sd = l.sidedef[sidx];
				if (!sd) continue;

				Sector sec = (sidx == 0) ? l.frontsector : l.backsector;
				if (!sec) continue;

				double fz = sec.floorplane.ZAtPoint(mid);
				double cz = sec.ceilingplane.ZAtPoint(mid);

				// Facing out of the wall, so a subclass that throws particles
				// throws them into the room instead of into the geometry.
				double face = l.delta.Angle() + (sidx == 0 ? -90.0 : 90.0);

				TryWall(sd.GetTexture(Side.top),    mid, cz - 32.0,        face);
				TryWall(sd.GetTexture(Side.mid),    mid, (fz + cz) * 0.5,  face);
				TryWall(sd.GetTexture(Side.bottom), mid, fz,               face);
			}
		}
	}

	private void TryWall(TextureID tex, Vector2 p, double z, double face)
	{
		int row = wallTable.Find(tex);
		if (row == 0) return;
		if (!ClaimCell(p, row)) return;

		let a = Actor.Spawn((class<Actor>)(wallTable.RowClass(row)), (p.x, p.y, z));
		if (!a) return;

		a.angle = face;

		int tint = wallTable.RowTint(row);
		if (tint != 0)
		{
			let fe = FancyEmitter(a);
			if (fe)
			{
				fe.fwTint = tint;
				fe.fwHasTint = true;
			}
		}
	}

	// ---- things ----------------------------------------------------------
	//
	// The fourth pass, and the only one that does not read a texture. See
	// FancyTexTable.FancyThingEmitter for what it matches and why.

	private void SpawnThingActors()
	{
		double step = max(64.0, FancySettings.GetFloat("fw_spacing", 256.0));
		ResetClaims(step);

		// COLLECT, THEN SPAWN. Spawning inside the iteration inserts new
		// thinkers into the list the iterator is currently walking. The array
		// is a few dozen entries on any real map.
		//
		// IT HOLDS THE TORCHES, NOT THEIR POSITIONS: Array<Vector3> does not
		// compile (DetermineType rejects a dynamic array whose element needs
		// more than one VM register), and Array<Actor> takes the object
		// backing and works.
		Array<Actor> torches;

		ThinkerIterator it = ThinkerIterator.Create("Actor");
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (FancyTexTable.FancyThingEmitter(a) != 'FancyThingTorch') continue;

			// Row 1, and it is the only row this lattice will ever use until a
			// second thing emitter exists. This pass has its own ResetClaims,
			// so row 1 here cannot collide with row 1 of the wall pass.
			if (!ClaimCell(a.pos.xy, 1)) continue;

			torches.Push(a);
		}

		for (int i = 0; i < torches.Size(); i++)
		{
			let t = torches[i];
			if (!t) continue;

			// Mid-height rather than at the actor's feet: a torch's flame is at
			// the top of it, and these are tall.
			Actor.Spawn("FancyThingTorch",
				(t.pos.x, t.pos.y, t.pos.z + t.height * 0.5));
		}
	}
}
