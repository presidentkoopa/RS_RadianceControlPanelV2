
// ============================================================================
//  Environmental FancyWorld -- the map scan.
// ============================================================================
//
//  todo.txt, entry two:
//
//      "Optimisation optimisations. The current method of deleting actors too
//       close together works and results in good framerates, but can result in
//       long load times, likely on account of CountProximity() being slow or
//       something."
//
//  It was CountProximity(), and it was also two other things. All three are
//  gone. What the scan does is unchanged -- find every liquid floor, lit
//  ceiling and interesting wall texture in the map and put an emitter there --
//  but it now arrives at the same answer without the three things that made
//  loading a big map take as long as it did.
//
//  1. THE GRID WAS SEARCHING THE WHOLE UNIVERSE.
//     The floor scan swept a fixed 128-unit grid across the full ±32448 map
//     space: 507 x 507, about 257,000 points, on every map. Each one did a
//     PointInSector() and an IsPointInMap(), and every point that landed
//     inside spawned an actor whose first act was forty string lookups.
//     It paid the full 64k x 64k price whether the map was Entryway or not.
//
//     Now the loop runs the other way round. It walks SECTORS -- of which
//     there are maybe two thousand, not 257,000 -- and asks each one once
//     whether its floor is interesting. The ~98% that are not cost a single
//     array read and are never sampled at all. Only the liquid ones get
//     points placed, and only inside their own bounding box.
//
//  2. CountProximity() IS O(EVERY ACTOR IN THE MAP), CALLED PER EMITTER.
//     Which makes the dedup pass quadratic, and it was running on both the
//     floor cores and all fourteen wall types. It is replaced by a claim
//     grid: positions snap to a fixed lattice and a cell is either taken or
//     it is not. One array read instead of a walk over every actor alive.
//
//     Snapping to a GLOBAL lattice rather than a per-sector one also fixes a
//     thing the old dedup could not: two adjacent nukage sectors used to
//     place their emitters on their own offsets and could end up with two
//     sitting a few units apart across the shared edge.
//
//  3. THE LATTICE ONLY COVERS THE MAP THAT EXISTS.
//     Bounds come from the vertices, so a small map allocates a small grid.
//
//  Net effect: the wall pass drops from ~500 string lookups per linedef to 6
//  array reads, the floor pass from 257,000 speculative points to a few
//  hundred real ones, and the dedup from quadratic to constant time.
//
// ============================================================================

class SpawnEnvActorHandler : EventHandler
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
		if (!FancySettings.GetBool("fw_enabled", true)) return;

		MeasureMap();

		floorTable = FancyTexTable.BuildFloors();
		ceilTable  = FancyTexTable.BuildCeilings();
		wallTable  = FancyTexTable.BuildWalls();

		SpawnFloorActors();
		SpawnCeilingActors();
		SpawnWallActors();

		// Nothing below needs it again, and on a big map it is the largest
		// thing this handler ever allocated.
		claim.Clear();
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

	// Sized per pass, because the floor lattice and the wall lattice want
	// different spacings and neither should have to see the other's claims.
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

	// ---- floors ----------------------------------------------------------

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
			// one emitter at the centre and skip sampling entirely. This is
			// the old "old way" path, kept because for a small convex sector
			// it is both correct and free.
			//
			// A centre spot outside its own sector is the exact case that path
			// always got wrong ("regardless of whether that center is actually
			// in the sector or not"). When it happens we now fall through and
			// sample properly rather than placing an emitter in the wall.
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

	// ---- ceilings --------------------------------------------------------

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

				// Six lookups for this linedef. It used to be about five
				// hundred, each one resolving a string.
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

	// ---- shared ----------------------------------------------------------

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
}
