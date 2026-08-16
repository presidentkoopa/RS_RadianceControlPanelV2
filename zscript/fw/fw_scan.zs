// ============================================================================
//  The liquid index.
// ============================================================================
//
//  What is left of Environmental FancyWorld's map scan, after the ambience
//  layer it existed to feed came out. This used to also place a texture-
//  matched emitter -- a sound, a light, particles -- on every liquid floor,
//  lit ceiling and interesting wall in the map, walking sectors and linedefs
//  through a claim lattice to do it cheaply. None of that reads a texture
//  for any reason anymore except this one:
//
//  Render.zs's fog can take its colour from whichever liquid you are nearest
//  -- green over nukage, dark red over blood, orange over lava -- and that
//  question is cheapest to answer by reading every sector's floor flat once,
//  at load, rather than per frame. This class still does exactly that read
//  and nothing else.
//
//  RENAMED from SpawnEnvActorHandler, which spawned nothing anymore. Update
//  mapinfo.txt's AddEventHandlers and GlowHandler.zs's EventHandler.Find
//  string together with this file if it moves again.
//
// ============================================================================

class GITD_LiquidIndex : EventHandler
{
	override void WorldLoaded(WorldEvent e)
	{
		IndexLiquids();
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
}
