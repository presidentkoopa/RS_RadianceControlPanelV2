// ============================================================================
//  Environmental FancyWorld -- floors.
// ============================================================================
//
//  THE ACTOR COUNT PROBLEM, AND WHERE IT WENT.
//
//  The old floor scan placed something at every point on a 128-unit grid. For
//  nukage and lava that was one deduplicated "core" per 256 units plus a
//  bubble actor at EVERY point. For water, slime, hot surfaces and xwater
//  there was no dedup at all -- every single grid point got its own core, each
//  one holding its own live looping sound. A 2048x2048 lake of water was 256
//  permanent actors and 256 permanent looping sound channels, and the mixer
//  was being asked to sort that out every frame.
//
//  Now there is one core per fw_spacing (256 by default), and the surface
//  detail is spawned BY the core, as short-lived one-shots at random points
//  inside its own patch. Same bubbles in the same places at the same rate --
//  the sprites and sounds below are the originals, untouched -- but they exist
//  for twenty tics instead of for the whole map, and a quiet lake costs
//  nothing at all because the core stops spawning them when you walk away.
//
// ============================================================================

// Base for the liquids that scatter surface detail across their patch. The
// core knows how big its own patch is, because that is just the spacing the
// scanner used to place it.
class FancyLiquidCore : FancyEmitter
{
	// What to drop on the surface. None means the liquid is just a sound.
	virtual Name FancySurfaceItem() { return 'None'; }

	// Picks a point inside this core's patch and confirms it is still the
	// same sector, so a core sitting near the edge of a pool does not throw
	// bubbles onto the walkway next to it.
	void FancyScatter(Name what)
	{
		if (what == 'None') return;

		double r = max(64.0, FancySettings.GetFloat("fw_spacing", 256.0)) * 0.5;
		Vector2 p = (pos.x + frandom(-r, r), pos.y + frandom(-r, r));

		let sec = Sector.PointInSector(p);
		if (!sec || sec != cursector) return;

		Spawn((class<Actor>)(what), (p.x, p.y, sec.floorplane.ZAtPoint(p)));
	}

	override void FancyPuff() { FancyScatter(FancySurfaceItem()); }
}

// ---- Acid / nukage ---------------------------------------------------------

class FancySectorNukageCore : FancyLiquidCore
{
	override Sound FancySound() { return "world/acidloop"; }
	override Name FancySurfaceItem() { return 'FancySectorNukage'; }
	override int FancyPuffRate() { return 22; }

	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x58D820; }
	override int FancyLightRadius() { return 112; }
	override int FancyLightRadius2() { return 84; }
	override double FancyLightParam() { return 2.6; }
	override int FancyLightTier() { return 1; }
}

// One bubble, once. Was a permanent actor looping through idle states waiting
// for a random jump to fire; it is now spawned when the bubble is wanted and
// removed when it has finished being one.
class FancySectorNukage : Actor
{
	Default
	{
		-SOLID
		+DONTSPLASH
		+NOTELEPORT
		+NOINTERACTION
		+MOVEWITHSECTOR
		radius 1;
		height 1;
	}

	States
	{
	Spawn:
		NUBL A 0 A_StartSound("world/acid", CHAN_VOICE);
		NUBL ABCDE 4;
		stop;
	}
}

// ---- Water -----------------------------------------------------------------

class FancySectorWaterCore : FancyEmitter
{
	override Sound FancySound() { return "world/waterflow"; }
}

// ObAddon's XWATER.
class FancySectorXWaterCore : FancyEmitter
{
	override Sound FancySound() { return "world/xwater"; }

	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x2860A0; }
	override int FancyLightRadius() { return 72; }
	override int FancyLightRadius2() { return 52; }
	override double FancyLightParam() { return 4.0; }
	override int FancyLightTier() { return 2; }
}

// ---- Slime and blood -------------------------------------------------------

class FancySectorSlimeCore : FancyEmitter
{
	override Sound FancySound() { return "world/gooflow"; }

	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x38A020; }
	override int FancyLightRadius() { return 80; }
	override int FancyLightRadius2() { return 58; }
	override double FancyLightParam() { return 3.4; }
	override int FancyLightTier() { return 2; }
}

// ---- Lava ------------------------------------------------------------------

class FancySectorLavaCore : FancyLiquidCore
{
	override Sound FancySound() { return "world/lavaflow"; }
	override Name FancySurfaceItem() { return 'FancySectorLava'; }
	override int FancyPuffRate() { return 18; }

	override int FancyLightType() { return DynamicLight.FlickerLight; }
	override Color FancyLightColor() { return 0xFF5C10; }
	override int FancyLightRadius() { return 152; }
	override int FancyLightRadius2() { return 112; }
	override double FancyLightParam() { return 0.22; }
	override int FancyLightTier() { return 1; }

	override void FancyPuff()
	{
		super.FancyPuff();

		// Embers off the surface, independent of the pops. A lava lake wants
		// to be doing something everywhere all the time, not only where a
		// bubble happens to be bursting.
		double r = max(64.0, FancySettings.GetFloat("fw_spacing", 256.0)) * 0.5;
		A_SpawnParticle(0xFF9628, SPF_FULLBRIGHT,
			70, frandom(1.0, 2.0), 0,
			frandom(-r, r), frandom(-r, r), frandom(0, 6),
			frandom(-0.15, 0.15), frandom(-0.15, 0.15), frandom(0.5, 1.4),
			0, 0, -0.045,
			0.95, 0.014, -0.008);
	}
}

class FancySectorLava : Actor
{
	Default
	{
		-SOLID
		+DONTSPLASH
		+NOTELEPORT
		+NOINTERACTION
		+MOVEWITHSECTOR
		radius 1;
		height 1;
	}

	States
	{
	Spawn:
		LABL A 0 A_StartSound("world/lava", CHAN_VOICE);
		LABL A 0 A_SpawnItemEx("LavaSmoke", 0, 0, 2, 0, 0, frandom(0.2, 0.6));
		LABL ABCDE 4;
		stop;
	}
}

// ---- Hot surfaces ----------------------------------------------------------

// SLIME09-12: hot rock rather than a liquid. No loop -- the original only ever
// hissed occasionally, and the smoke is the main event.
class FancySectorHotCore : FancyEmitter
{
	override int FancyLightType() { return DynamicLight.FlickerLight; }
	override Color FancyLightColor() { return 0x883410; }
	override int FancyLightRadius() { return 72; }
	override int FancyLightRadius2() { return 48; }
	override double FancyLightParam() { return 0.20; }
	override int FancyLightTier() { return 2; }

	override int FancyPuffRate() { return 14; }

	override void FancyPuff()
	{
		double r = max(64.0, FancySettings.GetFloat("fw_spacing", 256.0)) * 0.5;
		A_SpawnItemEx("LavaSmoke",
			frandom(-r, r), frandom(-r, r), 2,
			0, 0, frandom(0.2, 0.5));

		if (random(0, 255) < 40) A_StartSound("world/hotsurface", CHAN_VOICE);
	}
}

// ---- Teleporter pads -------------------------------------------------------

class FancySectorTeleporterCore : FancyEmitter
{
	override Sound FancySound() { return "world/floortele"; }

	// A pad you can find from across the room by its glow. This is the one
	// place where the light is arguably a gameplay change rather than a
	// cosmetic one, which is why it is tier 1 and not on unconditionally.
	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0xB040FF; }
	override int FancyLightRadius() { return 104; }
	override int FancyLightRadius2() { return 64; }
	override double FancyLightParam() { return 1.2; }
	override int FancyLightTier() { return 1; }

	override int FancyPuffRate() { return 30; }

	override void FancyPuff()
	{
		A_SpawnParticle(0xC060FF, SPF_FULLBRIGHT,
			55, frandom(1.0, 2.0), 0,
			frandom(-28, 28), frandom(-28, 28), frandom(0, 4),
			0, 0, frandom(0.6, 1.6),
			0, 0, 0,
			0.9, 0.016, -0.010);
	}
}
