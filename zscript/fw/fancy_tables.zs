// ============================================================================
//  Environmental FancyWorld -- what the texture table still does.
// ============================================================================
//
//  This used to also build the wall, floor and ceiling emitter tables and the
//  one-row thing-emitter matcher -- the lookup behind the whole ambience scan.
//  That scan is gone. Two readings of the map's textures earned their keep
//  independently of it and stay:
//
//  BuildFog() is what lets the mist take its colour from the liquid you are
//  standing in (fw_scan.zs's IndexLiquids reads it at load, GlowHandler.zs's
//  fog colour mode 4 reads the result every frame). BuildSteps() is what
//  fancy_steps.zs asks per footfall to know what you just stepped on. Neither
//  needs a scanner, a lattice or an emitter -- both are answered by a single
//  array read against the same lookup machinery, which is the part worth
//  keeping this class for.
//
// ============================================================================

class FancyTexTable play
{
	// One row per distinct (emitter, tint) pair.
	//
	// Named emitClass/emitTint rather than rowClass/rowTint because ZScript
	// identifiers are CASE-INSENSITIVE: a field rowClass and an accessor
	// RowClass() are the same name to the compiler, and it rejects the second
	// as a redefinition of the first.
	private Array<Name>	emitClass;
	private Array<int>	emitTint;

	// texture index -> row + 1. Zero means "nothing happens here", which is
	// the answer for the overwhelming majority of textures in any map, and is
	// why this wants to be the cheapest possible check.
	private Array<int>	lookup;

	// ---- building -------------------------------------------------------

	// tint 0 means "the class picks its own colour". Only the wall lights
	// really need per-texture tints, since the map names them by colour.
	private int AddRow(Name cls, int tint)
	{
		emitClass.Push(cls);
		emitTint.Push(tint);
		return emitClass.Size();   // 1-based on purpose; 0 is the "none" value
	}

	private void Bind(int row, string names)
	{
		Array<String> parts;
		names.Split(parts, " ", TOK_SKIPEMPTY);

		for (int i = 0; i < parts.Size(); i++)
		{
			TextureID t = TexMan.CheckForTexture(parts[i], TexMan.Type_Any);
			if (!t.IsValid()) continue;

			int idx = t.GetIndex();
			if (idx < 0) continue;

			if (idx >= lookup.Size())
			{
				int old = lookup.Size();
				lookup.Resize(idx + 1);
				for (int k = old; k <= idx; k++) lookup[k] = 0;
			}
			lookup[idx] = row;
		}
	}

	private void Define(Name cls, int tint, string names)
	{
		Bind(AddRow(cls, tint), names);
	}

	// ---- reading --------------------------------------------------------

	// The hot path. One bounds check and one array read.
	int Find(TextureID t) const
	{
		if (!t.IsValid()) return 0;
		int idx = t.GetIndex();
		return (idx >= 0 && idx < lookup.Size()) ? lookup[idx] : 0;
	}

	Name RowClass(int row) const { return emitClass[row - 1]; }
	int RowTint(int row) const { return emitTint[row - 1]; }

	// ---- fog ------------------------------------------------------------
	//
	// Which flats are liquid, and what colour mist should sit over them.
	// fw_scan.zs reads this once at load to build its liquid index; the row's
	// "class" is a KIND rather than an actor here, and the tint is the mist
	// colour.
	static FancyTexTable BuildFog()
	{
		let t = new("FancyTexTable");

		t.Define('nukage', 0x4FC022, "NUKAGE1 NUKAGE2 NUKAGE3 NUKAGE4");

		t.Define('slime', 0x3E8C24,
			"SLIME01 SLIME02 SLIME03 SLIME04 SLIME05 SLIME06 SLIME07 SLIME08 "
			"SLUDGE01 SLUDGE02 SLUDGE03 SLUDGE04");

		t.Define('blood', 0x7A1414, "BLOOD1 BLOOD2 BLOOD3 BLOOD4");

		t.Define('lava', 0xFF6A18,
			"LAVA1 LAVA2 LAVA3 LAVA4 QLAVA1 QLAVA2 QLAVA3 QLAVA4");

		t.Define('hot', 0x8A5A3A, "SLIME09 SLIME10 SLIME11 SLIME12");

		t.Define('water', 0x8FB8D8,
			"FWATER1 FWATER2 FWATER3 FWATER4 XWATER1 XWATER2 XWATER3 XWATER4");

		return t;
	}

	// ---- footsteps -------------------------------------------------------
	//
	// What it sounds like to walk on a flat. Doom ships no footstep sounds at
	// all, so every one of these is silence without this table.
	//
	// THIS TABLE IS A STARTING POINT AND IS MEANT TO BE ARGUED WITH. Doom's
	// flat names say almost nothing about material -- FLOOR4_8 could be
	// anything -- so most of these are judgement calls from what the texture
	// actually looks like, and some will be wrong. That is exactly why the
	// table is one line per material: fixing one is moving a name from one
	// string to another.
	//
	// Flats not listed here fall back to 'hard', which is the safe answer for
	// a game that is mostly concrete and metal.
	static FancyTexTable BuildSteps()
	{
		let t = new("FancyTexTable");

		// Bare metal plate. Doom's stair and lift flats.
		t.Define('metal', 0, "STEP1 STEP2 CEIL5_1 CEIL5_2 FLAT23 FLOOR4_8");

		// Hollow, with a drop underneath -- catwalks and gratings. The one
		// material where the sound is telling you the floor is not solid.
		t.Define('grate', 0, "SLIME13 SLIME14 SLIME15 SLIME16 GRATE1");

		// Teleport pads read as metal, not stone.
		t.Define('metal', 0,
			"GATE1 GATE2 GATE3 GATE4 GATE3TN GATE4BL GATE4GN GATE4OR GATE4RD GATE4YL");

		t.Define('wood', 0, "FLAT5_1 FLAT5_2 CEIL1_1");

		// Loose ground. MFLR8 is Doom's dirt, RROCK the broken rock.
		t.Define('dirt', 0, "MFLR8_1 MFLR8_2 MFLR8_3 MFLR8_4 RROCK09 RROCK10");
		t.Define('gravel', 0, "RROCK11 RROCK12 RROCK13 RROCK14 GRNROCK");
		t.Define('rock', 0,
			"RROCK01 RROCK02 RROCK03 RROCK04 RROCK15 RROCK16 RROCK17 RROCK18 "
			"RROCK19 RROCK20 CRACKLE2 CRACKLE3 ASHWALL");

		// Polished. The marble and the clean tech floors.
		t.Define('tile', 0, "FLOOR7_1 FLOOR7_2 FLAT1 FLAT4 CEIL4_1 CEIL4_2 CEIL4_3");

		// Hell's meat floors, and the only material with a single sample --
		// the driver leans harder on pitch variation for these.
		t.Define('flesh', 0,
			"DEM1_1 DEM1_2 DEM1_3 DEM1_4 DEM1_5 DEM1_6 "
			"SFLR6_1 SFLR6_4 SFLR7_1 SFLR7_4");

		// CARPET AND SNOW SHIP BUT ARE NOT BOUND, deliberately, and this note
		// is here so the next person does not conclude the samples are junk.
		//
		// fancy_steps.zs has switch arms for both and sndinfo.txt declares
		// both $random groups, but vanilla Doom has no carpet flat and no snow
		// flat, so there is nothing honest to bind them to. They are here for
		// texture packs that do -- Eviternity, Ancient Aliens, anything with a
		// winter set. Adding one is a single Define line:
		//
		//     t.Define('carpet', 0, "SOMEFLAT ANOTHERFLAT");
		//
		// Nine lumps sit unused until someone does. That is a few kilobytes
		// against having the material ready the day a WAD needs it.

		// Everything liquid. Wading is its own sound whatever is in the pool.
		t.Define('splash', 0,
			"NUKAGE1 NUKAGE2 NUKAGE3 NUKAGE4 "
			"FWATER1 FWATER2 FWATER3 FWATER4 XWATER1 XWATER2 XWATER3 XWATER4 "
			"BLOOD1 BLOOD2 BLOOD3 BLOOD4 "
			"SLIME01 SLIME02 SLIME03 SLIME04 SLIME05 SLIME06 SLIME07 SLIME08 "
			"SLUDGE01 SLUDGE02 SLUDGE03 SLUDGE04 "
			"LAVA1 LAVA2 LAVA3 LAVA4 QLAVA1 QLAVA2 QLAVA3 QLAVA4");

		return t;
	}
}
