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
	// COLD WAR: the same pools at the same emitters, read as a dose rate
	// rather than as something bubbling. The bubbles themselves are NOT
	// switched -- they are a picture of the liquid, and the liquid has not
	// changed. Only the room's reading of it has.
	override Sound FancySound()
	{
		if (FancyVoice() == 1) return "world/acidloop/cold";
		return "world/acidloop";
	}

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
	// THE CHEAPEST DIALECT IN THE DESIGN, and it needed no recording at all.
	//
	// Under Lovecraftian Fog the map's water speaks with the map's SLIME
	// voice, from the same pools, at the same emitters, using a lump that has
	// been in this mod since the merge. The water runs thick. A new file could
	// not have said it more plainly, and it would have cost a manifest entry,
	// a lump and a $volume to say it worse.
	//
	// gooflow is declared at $volume 0.005 and waterflow at 0.01 -- both are
	// floor FIELDS, both sit at the bottom of the ladder for the same reason
	// (dozens audible at once), so this is a change of character and not a
	// change of level. That is the rule every voice row here follows.
	override Sound FancySound()
	{
		if (FancyVoice() == 4) return "world/gooflow";
		return "world/waterflow";
	}
}

// ObAddon's XWATER.
class FancySectorXWaterCore : FancyEmitter
{
	// Same trade as FancySectorWaterCore above: under voice 4 it is the same
	// pool saying something wrong. Note this one drops from $volume 0.1 to
	// gooflow's 0.005 while it does it -- xwater is the one value in sndinfo
	// that does not fit its own ladder, so the preset is quieter here than the
	// default is. On the handful of ObAddon maps with large XWATER areas that
	// is a mercy rather than a bug.
	override Sound FancySound()
	{
		if (FancyVoice() == 4) return "world/gooflow";
		return "world/xwater";
	}

	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x2860A0; }
	override int FancyLightRadius() { return 72; }
	override int FancyLightRadius2() { return 52; }
	override double FancyLightParam() { return 4.0; }
	override int FancyLightTier() { return 2; }
}

// ---- Slime -----------------------------------------------------------------

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

// ---- Blood -----------------------------------------------------------------
//
// BLOOD1-4 USED TO BE FOLDED INTO SLIME, and the result was a blood pool lit
// bright green, pulsing, and gurgling like a sewer. The fog table two hundred
// lines away had it right the whole time -- 0x7A1414, dark red -- so a pool of
// blood under correctly red mist was throwing green light up onto it.
//
// The tell was that no other liquid shares a row. Nukage, water, xwater and
// lava each have their own class and their own colour, because the whole point
// of the rewrite was that the map has been telling us what the liquid is and
// the old code answered every question the same way. Blood was the one that
// got left in somebody else's bucket.
//
// SO IT IS ITS OWN, and it is deliberately the quietest liquid in the set.
// Blood does not flow, boil or bubble; a pool of it is still. The light is
// FlickerLight rather than Pulse -- the irregular one, not the breathing one,
// because a pulsing blood pool reads as alive and that is a different and much
// sillier idea. The radius is the smallest here, so in a room that also holds
// lava or nukage this is the light that yields.
//
// TIER 2, NOT 3. Tier is compared against fw_light_detail, and that cvar's
// menu offers 0, 1 and 2 with 2 labelled "Everything" -- so a tier 3 light is
// one no setting can reach, and it would sit dark behind an option promising
// the opposite. Blood is flavour, which is what tier 2 means, and it belongs
// with the slime and the computers it was wrongly filed under anyway.
class FancySectorBloodCore : FancyEmitter
{
	// Not gooflow. That is the sewer gurgle and it is what gave this away.
	// bloodfall is the wettest thing in the set that is not moving water, at a
	// tenth of its volume in sndinfo, which for a still pool is about right.
	override Sound FancySound() { return "world/bloodfall"; }

	override int FancyLightType() { return DynamicLight.FlickerLight; }
	override Color FancyLightColor() { return 0x7A1414; }  // matches the fog exactly
	override int FancyLightRadius() { return 56; }
	override int FancyLightRadius2() { return 40; }
	override double FancyLightParam() { return 0.18; }     // flicker chance, not a period
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

// SLIME09-12: hot rock rather than a liquid.
//
// IT NOW HAS THE LOOP IT NEVER HAD. This class overrode no FancySound() at
// all: it hissed 40/256 of the time and was otherwise a silent emitter with a
// light and some smoke, which made it the one liquid-adjacent flat in the mod
// that a player could stand on and hear nothing from. world/hotloop is a
// burning-coal bed at $volume 0.03 -- the floor-field rung, matching lavaflow,
// one below the workhorse band -- and the occasional hiss stays exactly as it
// was, on CHAN_VOICE, so it still punctuates rather than competing.
class FancySectorHotCore : FancyEmitter
{
	override Sound FancySound() { return "world/hotloop"; }

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
