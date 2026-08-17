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
		Gravity 0.125;   // was +LOWGRAVITY, deprecated since 4.13.0 -- same 1/8 value
		+NOBLOCKMAP
		+MISSILE
		+DROPOFF
		+NOTELEPORT
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

	// The flourish: a ring spreading across the surface, plus a couple of
	// bubbles. See FancyLiquidFlourish -- this class only asks.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		FancyLiquidFlourish.Splash(self);
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

	// A flare, not a ring -- lava does not ripple. See FancyLiquidFlourish.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		FancyLiquidFlourish.Flare(self);
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

// ============================================================================
//  Flourishes -- the ring wave and the bubbles.
// ============================================================================
//
//  CONCEPT ONLY, credited, not copied: Universal Map Enhancements (Brutal
//  Doom v21 companion pack, BROS_ETT_311) has a comparable pair of effects
//  in its own DECORATE (Splashes.txt/Water.txt) -- an actor that plays one
//  sprite through a manual A_SetScale ramp to fake a spreading ring, and a
//  swarm of 5-10 real, physics-bouncing Actor particles per underwater
//  explosion for the bubbles. It also ships a genuinely nicer version of the
//  ring, a real animated 3D splash mesh (MODELDEF-bound, Splash.md2), which
//  is not reproduced here: that is an actual asset, not a technique, UME
//  states no licence over it the way MTOLiquids does over its sprites, and
//  it costs a real Actor per splash on top of the model render itself.
//  Anyone who wants that exact look already has the free option this mod's
//  own README documents for any liquid pack: load UME after this mod and
//  normal TERRAIN/DECORATE priority does the rest.
//
//  What follows is neither of those techniques -- it is what a ring and a
//  handful of bubbles cost when GITD's own Shape system, built earlier this
//  session, is asked to do it instead of an Actor:
//
//  THE RING is one AddShape (kind 2, a ring) with a grow rate. Size and
//  fade are both resolved every frame from age, natively -- see SetShapeMotion
//  in vmthunks.cpp -- so this call fires once and the expansion and the
//  fade-out it is riding on both happen with no further ZScript involved.
//  UME needed eight discrete sprite frames and a manual scale call on each
//  to fake the same motion.
//
//  THE BUBBLES need to actually move over time, which nothing in the Shape
//  system resolves on its own (position only changes via MoveShape). That
//  is a real, if small, running cost -- FancyBubbleShape below is the
//  cheapest thing that can pay it: a bare Thinker, not an Actor, so it never
//  touches the blockmap, collision, or a sprite, just a slot index and two
//  vectors ticked for well under a second.
//
//  Standing (orient 3, not a floor decal) on purpose: a bubble is a point
//  drifting up THROUGH the liquid's volume, not a mark lying on whatever
//  surface happens to be under the camera's current fragment.
//
// ============================================================================

class FancyLiquidFlourish abstract play
{
	// Sector's own liquid tint if the world scan already knows this spot
	// (it does, for anything TERRAIN could have spawned a splash on -- see
	// GITD_LiquidIndex.NearestLiquid) -- water blue if it somehow does not.
	private static Color LiquidTint(Actor from)
	{
		let scan = GITD_LiquidIndex(EventHandler.Find("GITD_LiquidIndex"));
		if (scan)
		{
			bool found; Color tint;
			[found, tint] = scan.NearestLiquid(from.pos.xy, 256.0);
			if (found) return tint;
		}
		return Color(255, 143, 184, 216); // BuildFog's own 'water' fallback
	}

	static void Splash(Actor from)
	{
		if (!FancySettings.GetBool("fw_liquid_flourish", true)) return;

		Color tint = LiquidTint(from);
		Vector3 at = (from.pos.x, from.pos.y, from.pos.z + 1.0);

		int slot = level.AddShape(2, 0, at.x, at.y, at.z,
			8.0, 0.0, 4.0, tint, 1.3, 0.55);
		if (slot >= 0) level.SetShapeMotion(slot, 0.0, 0.0, 130.0);

		// A couple, not a swarm -- UME fires 5-10 real Actors per event for
		// this same beat.
		FancyBubbleShape.Rise(at, tint);
		FancyBubbleShape.Rise(at, tint);
	}

	static void Flare(Actor from)
	{
		if (!FancySettings.GetBool("fw_liquid_flourish", true)) return;

		// No grow, no bubbles: lava flares, it does not ripple or bubble --
		// same reasoning as the sprite flare already above this call.
		level.AddShape(1, 0, from.pos.x, from.pos.y, from.pos.z + 1.0,
			20.0, 0.0, 4.0, LiquidTint(from), 2.2, 0.25);
	}
}

class FancyBubbleShape : Thinker
{
	private int shapeSlot;
	private Vector3 bpos;
	private Vector3 bvel;
	private int ticsLeft;

	static void Rise(Vector3 at, Color tint)
	{
		double life = frandom(0.5, 0.9);

		// Lightened toward white -- a bubble is a highlight in the liquid,
		// not a patch of the liquid's own colour.
		Color bc = Color(255, min(255, tint.r + 80), min(255, tint.g + 80),
			min(255, tint.b + 80));

		// Standing, not a floor decal -- see the file header. Angle is
		// randomised because it costs nothing and a dozen bubbles all
		// facing the same way would read as one texture, not many events.
		int slot = level.AddShape(1, 3, at.x, at.y, at.z, 3.5,
			frandom(0.0, 359.0), 1.0, bc, 1.0, life);
		if (slot < 0) return;

		let b = FancyBubbleShape(new("FancyBubbleShape"));
		b.shapeSlot = slot;
		b.bpos = at;
		b.bvel = (frandom(-0.3, 0.3), frandom(-0.3, 0.3), frandom(1.2, 2.2));

		// Tied to the shape's OWN life, tic for tic, so this never outlives
		// its slot -- a Thinker that ticked past the shape's expiry would
		// start calling MoveShape on whatever unrelated shape got recycled
		// into that slot next.
		b.ticsLeft = int(life * TICRATE);
	}

	override void Tick()
	{
		Super.Tick();

		if (--ticsLeft <= 0)
		{
			level.RemoveShape(shapeSlot);
			Destroy();
			return;
		}

		bpos += bvel;
		level.MoveShape(shapeSlot, bpos.x, bpos.y, bpos.z);
	}
}
