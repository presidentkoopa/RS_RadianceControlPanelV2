// ============================================================================
//  Environmental FancyWorld -- the texture table.
// ============================================================================
//
//  RESTORED after the ambience scan was removed and then asked back:
//  BuildWalls(), BuildFloors(), BuildCeilings() and FancyThingEmitter() all
//  work as they did before. BuildFog() (the liquid-colour reading for Fog's
//  mode 4) and BuildSteps() (footsteps) never left -- neither one needed the
//  scanner, only this class's lookup machinery.
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

	// ---- walls ------------------------------------------------------------
	//
	// RESTORED. Floors, ceilings and things are still pending.
	static FancyTexTable BuildWalls()
	{
		let t = new("FancyTexTable");

		// Plutonia waterfalls, plus the WADSMOOSH names for the same thing.
		t.Define("FancyWallWaterfall", 0,
			"WFALL1 WFALL2 WFALL3 WFALL4 PWFALL1 PWFALL2 PWFALL3 PWFALL4");

		t.Define("FancyWallBloodfall", 0, "BFALL1 BFALL2 BFALL3 BFALL4");
		t.Define("FancyWallSlimefall", 0, "SFALL1 SFALL2 SFALL3 SFALL4");

		// ObAddon lavafalls and the CC4 set.
		t.Define("FancyWallLavafall", 0,
			"LFALL1 LFALL2 LFALL3 LFALL4 LFAL21 LFAL22 LFAL23 LFAL24 "
			"LAVFALL1 LAVFALL2 LAVFALL3 LAVFALL4");

		t.Define("FancyWallSlimedrip", 0, "SLADRIP1 SLADRIP2 SLADRIP3");
		t.Define("FancyWallGargfont", 0, "GSTFONT1 GSTFONT2 GSTFONT3");

		// A wall that is a PICTURE of dripping blood, in doom.wad and
		// doom2.wad both, and named nowhere in this file until now. It sits
		// next to SLADRIP and GSTFONT because it is the same idea found in the
		// same place -- the difference is that this one fires one-shots rather
		// than holding a loop. See FancyWallBloodDrip.
		t.Define("FancyWallBloodDrip", 0, "BLODRIP1 BLODRIP2 BLODRIP3 BLODRIP4");

		t.Define("FancyWallCompstation", 0,
			"COMPSTA1 COMPSTA2 COMPSTA3 COMPSTA4 COMPSTA5 COMPSTA6 COMPTALR");

		t.Define("FancyWallFireblu", 0, "FIREBLU1 FIREBLU2");

		t.Define("FancyWallFirewall", 0,
			"FIREMAG1 FIREMAG2 FIREMAG3 FIREWALL FIREWALA FIREWALB "
			"FIRELAVA FIRELAV2 FIRELAV3");

		t.Define("FancyWallTechhum", 0,
			"COMPTALL COMP2 SPACEW3 COMPUTE1 PLANET1 "
			"COMPUTE4 COMPUTE7 COMPUTE8 COMPUTE9");

		// COMPFUZ1-4 ARE NOT IN doom.wad OR doom2.wad -- checked by reading
		// TEXTURE1/TEXTURE2 out of both -- but they are real: a texture set
		// that ships in Brutal Doom and a number of other community mods and
		// texture packs. Bind() no-ops on a name that doesn't resolve in
		// whatever WAD is actually loaded, so there is no cost to listing a
		// name that is only sometimes present, and real cost to leaving it
		// out for the WADs that do ship it.
		//
		// COMPOHSO, COMPWERD and COMPSPAN are the three garbled-screen
		// textures actually in the vanilla IWADs (COMPOHSO in doom1,
		// COMPWERD and COMPSPAN in both) and stay alongside COMPFUZ rather
		// than in place of it. COMPBLUE and COMPTILE were also considered and
		// are deliberately NOT here: COMPBLUE is a general-purpose tech wall
		// used across whole episodes of Doom 1, and a strobing broken monitor
		// on every one of them is the FLAT2 mistake with a sound attached --
		// that one is a real judgement call, not a name that might not
		// resolve.
		t.Define("FancyWallStatic", 0,
			"COMPOHSO COMPWERD COMPSPAN COMPFUZ1 COMPFUZ2 COMPFUZ3 COMPFUZ4");
		t.Define("FancyWallFaces", 0, "SP_FACE1");

		// WALL LIGHTS, SPLIT BY COLOUR.
		//
		// The old code had all eighteen of these in one array feeding one
		// class, which meant a blue light and a red light produced the same
		// nothing. The map has been telling us the colour the whole time --
		// it is right there in the texture name -- so each family gets its
		// own row and its own tint, and a corridor of LITERED now actually
		// runs red.
		t.Define("FancyWallLights", 0xFFE8B0,
			"LITE2 LITE3 LITE4 LITE5 LITE96 LITEMET LITESTON BRICKLIT BSTONE3");
		t.Define("FancyWallLights", 0x4080FF, "LITEBLU1 LITEBLU4");
		t.Define("FancyWallLights", 0xFF3828, "LITERED LITERED1 LITERED2");
		t.Define("FancyWallLights", 0x40FF60, "LITEGRN1");
		t.Define("FancyWallLights", 0xFFD040, "LITEYEL1 LITEYEL2 LITEYEL3");

		return t;
	}

	// ---- floors -----------------------------------------------------------
	//
	// RESTORED. Ceilings and things are still pending.
	static FancyTexTable BuildFloors()
	{
		let t = new("FancyTexTable");

		t.Define("FancySectorNukageCore", 0, "NUKAGE1 NUKAGE2 NUKAGE3 NUKAGE4");
		t.Define("FancySectorWaterCore", 0, "FWATER1 FWATER2 FWATER3 FWATER4");

		t.Define("FancySectorSlimeCore", 0,
			"SLIME01 SLIME02 SLIME03 SLIME04 SLIME05 SLIME06 SLIME07 SLIME08 "
			"SLUDGE01 SLUDGE02 SLUDGE03 SLUDGE04");

		// BLOOD IS NOT SLIME. It used to be on the row above, which lit it
		// green while the fog table gave the same four flats dark red. See
		// FancySectorBloodCore in fancy_floors.zs for why it is quieter than
		// everything else here.
		t.Define("FancySectorBloodCore", 0, "BLOOD1 BLOOD2 BLOOD3 BLOOD4");

		t.Define("FancySectorLavaCore", 0,
			"LAVA1 LAVA2 LAVA3 LAVA4 QLAVA1 QLAVA2 QLAVA3 QLAVA4");

		t.Define("FancySectorHotCore", 0, "SLIME09 SLIME10 SLIME11 SLIME12");
		t.Define("FancySectorXWaterCore", 0, "XWATER1 XWATER2 XWATER3 XWATER4");

		// Teleporter pads. These are the "old way" scan -- one emitter at the
		// sector's centre spot -- because a teleporter pad is a small square
		// and its centre is always inside it.
		t.Define("FancySectorTeleporterCore", 0,
			"GATE1 GATE2 GATE3 GATE4 "
			"GATE3TN GATE4BL GATE4GN GATE4OR GATE4RD GATE4YL");

		return t;
	}

	// ---- ceilings ---------------------------------------------------------
	//
	// RESTORED. Things are still pending.
	static FancyTexTable BuildCeilings()
	{
		let t = new("FancyTexTable");

		t.Define("FancySectorSky", 0, "F_SKY1");

		t.Define("FancySectorCeilingLite", 0,
			"CEIL1_2 CEIL1_3 CEIL3_6 FLAT2 FLAT17 GRNLITE1 "
			"TLITE6_1 TLITE6_4 TLITE6_5 TLITE6_6");

		// WET ROCK, AND ONLY ROCK. GRNROCK and the RROCK family are Doom II's
		// broken-stone flats, and a sector with one of them as its CEILING is
		// an enclosed cave -- an outdoor one would have F_SKY1 up there
		// instead.
		t.Define("FancyCeilingDrip", 0, "GRNROCK RROCK03 RROCK04 RROCK13");

		return t;
	}

	// ---- things ------------------------------------------------------------
	//
	// RESTORED. Not a FancyTexTable -- a thing has no texture, so `is` checks
	// against the actor class stand in for the Bind()/Find() lookup. Adding
	// the hanging bodies, the barrel or the EvilEye is one line here and one
	// class beside FancyThingTorch. None of them ship: each would cost a
	// manifest entry and an sndinfo block for a decoration that appears a
	// handful of times per megawad.
	static Name FancyThingEmitter(Actor a)
	{
		if (a is 'RedTorch'   || a is 'GreenTorch'   || a is 'BlueTorch'
		 || a is 'ShortRedTorch' || a is 'ShortGreenTorch' || a is 'ShortBlueTorch'
		 || a is 'BurningBarrel')
			return 'FancyThingTorch';

		return '';
	}

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
