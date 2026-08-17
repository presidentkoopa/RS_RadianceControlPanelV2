// ============================================================================
//  Liquid splashes -- real physics, not a scan.
// ============================================================================
//
//  Everything else in this mod's ambience layer works by finding things:
//  the scan walks textures at load and decides what belongs where. A splash
//  is different in kind, not just in size -- it needs to know the instant
//  something crosses a liquid's surface, and that is a per-tic physics
//  question the scan was never built to answer.
//
//  It does not have to answer it. GZDoom's own TERRAIN lump already does --
//  see TERRAIN in the mod root -- and once a flat is named there, the
//  engine spawns these classes itself, the moment something actually
//  crosses the plane. Nothing here polls, nothing here scans; this file is
//  just the actors the terrain entries point at.
//
//  Complementary to, not a replacement for, the floor emitters' own ambient
//  bubbling (FancySectorNukageCore and friends, fancy_floors.zs) -- that is
//  the liquid existing over time, this is something breaking its surface.
//  Both are true of the same pool at once.
//
//  ASSETS: the splash and lava sprites (SPSH*/LVAS*) and sounds (DSWATER/
//  DSMUCK/DSLAVA) originate in Heretic and Hexen, by way of the small
//  freeware Environmental_MTOLiquids resource -- credited in full in
//  README.md. These classes and the terrain lump are written for this mod;
//  nothing here is a copy of that resource's own DECORATE.
//
// ============================================================================

class MTOSplashChunk : Actor
{
	Default
	{
		Radius 2;
		Height 4;
		+NOBLOCKMAP
		+MISSILE
		+DROPOFF
		+NOTELEPORT
		+LOWGRAVITY
		+CANNOTPUSH
		+DONTSPLASH
		+DONTBLAST
	}
	States
	{
	Spawn:
		SPSH ABC 8;
		SPSH D 16;
		Stop;
	Death:
		SPSH D 10;
		Stop;
	}
}

// Colour by translation, one sprite. Ranges are standard Doom palette
// facts (112-127 is the vanilla green band, 176-191 red, and so on), not
// anyone's creative work -- derived independently, not copied.
class MTOSplashChunkGreen  : MTOSplashChunk { Default { Translation "192:207=112:127"; } }
class MTOSplashChunkGunk   : MTOSplashChunk { Default { Translation "192:207=152:159"; } }
class MTOSplashChunkRed    : MTOSplashChunk { Default { Translation "192:207=176:191"; } }
class MTOSplashChunkBrown  : MTOSplashChunk { Default { Translation "192:207=136:151"; } }
class MTOSplashChunkMilk   : MTOSplashChunk { Default { Translation "192:207=192:199"; } }
class MTOSplashChunkPurple : MTOSplashChunk { Default { Translation "192:207=250:254"; } }
class MTOSplashChunkBlack  : MTOSplashChunk { Default { Translation "192:199=236:239", "200:207=5:8"; } }
class MTOSplashChunkYellow : MTOSplashChunk { Default { Translation "192:199=224:231", "200:207=160:167"; } }

// The flat ripple left where the chunk came from, not the chunk itself --
// TERRAIN spawns one of each per crossing (baseclass + chunkclass).
class MTOSplashBase : Actor
{
	Default
	{
		+NOBLOCKMAP
		+NOCLIP
		+NOGRAVITY
		+DONTSPLASH
		+DONTBLAST
	}
	States
	{
	Spawn:
		SPSH EFGHIJK 5;
		Stop;
	}
}

class MTOSplashBaseGreen  : MTOSplashBase { Default { Translation "192:207=112:127"; } }
class MTOSplashBaseGunk   : MTOSplashBase { Default { Translation "192:207=152:159"; } }
class MTOSplashBaseRed    : MTOSplashBase { Default { Translation "192:207=176:191"; } }
class MTOSplashBaseBrown  : MTOSplashBase { Default { Translation "192:207=136:151"; } }
class MTOSplashBaseMilk   : MTOSplashBase { Default { Translation "192:207=192:199"; } }
class MTOSplashBasePurple : MTOSplashBase { Default { Translation "192:207=250:254"; } }
class MTOSplashBaseBlack  : MTOSplashBase { Default { Translation "192:199=236:239", "200:207=5:8"; } }
class MTOSplashBaseYellow : MTOSplashBase { Default { Translation "192:199=224:231", "200:207=160:167"; } }

// Lava does not ripple, it flares -- BRIGHT, no translucency on the flare
// itself, a separate smoke class for what rises after.
class MTOLavaSplash : Actor
{
	Default
	{
		+NOBLOCKMAP
		+NOCLIP
		+NOGRAVITY
		+DONTSPLASH
		+DONTBLAST
	}
	States
	{
	Spawn:
		LVAS ABCDEF 5 Bright;
		Stop;
	}
}

class MTOLavaSplashYellow : MTOLavaSplash { Default { Translation "208:223=224:231"; } }

class MTOLavaSmoke : Actor
{
	Default
	{
		+NOBLOCKMAP
		+NOCLIP
		+NOGRAVITY
		+DONTSPLASH
		RenderStyle "Translucent";
	}
	States
	{
	Spawn:
		LVAS GHIJK 5 Bright;
		Stop;
	}
}
