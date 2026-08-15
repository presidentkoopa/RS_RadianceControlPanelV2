// ============================================================================
//  Environmental FancyWorld -- walls.
// ============================================================================
//
//  This file used to be 489 lines of the same class written fourteen times.
//  Every one of them: a CountProximity() dedup, one looping A_PlaySound, then
//  APLS A -1 forever. The only thing that differed between any two of them was
//  the sound name.
//
//  They are declarations now. The dedup moved to the scanner, which can do it
//  in constant time; the timing and range culling moved to FancyEmitter, which
//  does it once for everybody. What is left in each class is the part that was
//  ever actually unique -- plus, now, what it looks like.
//
//  Particle offsets are RELATIVE, and the scanner sets each emitter's angle to
//  point out of the wall it was found on. So "velx" below means "away from the
//  wall" and everything throws into the room instead of into the geometry.
//
// ============================================================================

// ---- Falling things --------------------------------------------------------

// Plutonia waterfalls.
class FancyWallWaterfall : FancyEmitter
{
	override Sound FancySound() { return "world/waterfall"; }
	override int FancyPuffRate() { return 150; }

	override void FancyPuff()
	{
		// Mist, not droplets. It wants to be a soft mass that grows and
		// thins as it falls, which is the sizestep and the fade doing the
		// work rather than any one particle being visible on its own.
		A_SpawnParticle(0xC8DCFF, SPF_RELATIVE | SPF_FULLBRIGHT,
			45, frandom(2.5, 5.0), 0,
			frandom(0, 6), frandom(-40, 40), frandom(-24, 40),
			frandom(0.10, 0.60), frandom(-0.3, 0.3), frandom(-2.4, -1.2),
			0, 0, -0.05,
			0.40, 0.009, 0.12);
	}
}

class FancyWallBloodfall : FancyEmitter
{
	override Sound FancySound() { return "world/bloodfall"; }
	override int FancyPuffRate() { return 120; }

	override void FancyPuff()
	{
		A_SpawnParticle(0x8C1010, SPF_RELATIVE,
			50, frandom(2.5, 4.5), 0,
			frandom(0, 5), frandom(-36, 36), frandom(-24, 40),
			frandom(0.05, 0.45), frandom(-0.25, 0.25), frandom(-2.2, -1.0),
			0, 0, -0.05,
			0.55, 0.011, 0.10);
	}
}

class FancyWallSlimefall : FancyEmitter
{
	override Sound FancySound() { return "world/slimefall"; }

	// Doom's slime has always been the stuff that glows in a dark room, so it
	// gets a light -- but a flavour one, off by default at low detail.
	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x3CD824; }
	override int FancyLightRadius() { return 56; }
	override int FancyLightRadius2() { return 40; }
	override double FancyLightParam() { return 2.4; }
	override int FancyLightTier() { return 2; }

	override int FancyPuffRate() { return 120; }

	override void FancyPuff()
	{
		A_SpawnParticle(0x50E028, SPF_RELATIVE | SPF_FULLBRIGHT,
			50, frandom(2.0, 4.0), 0,
			frandom(0, 5), frandom(-36, 36), frandom(-24, 40),
			frandom(0.05, 0.45), frandom(-0.25, 0.25), frandom(-2.0, -0.9),
			0, 0, -0.05,
			0.50, 0.010, 0.10);
	}
}

class FancyWallLavafall : FancyEmitter
{
	override Sound FancySound() { return "world/lavafall"; }

	override int FancyLightType() { return DynamicLight.FlickerLight; }
	override Color FancyLightColor() { return 0xFF6410; }
	override int FancyLightRadius() { return 136; }
	override int FancyLightRadius2() { return 96; }
	override double FancyLightParam() { return 0.25; }
	override int FancyLightTier() { return 1; }

	override int FancyPuffRate() { return 170; }

	override void FancyPuff()
	{
		// Embers rise off it and then lose to gravity, which is the accelz.
		// A lavafall that only ever threw things downward read as a curtain;
		// the ones going up are what make it look hot.
		A_SpawnParticle(0xFF9628, SPF_RELATIVE | SPF_FULLBRIGHT,
			60, frandom(1.0, 2.2), 0,
			frandom(0, 5), frandom(-32, 32), frandom(-40, 40),
			frandom(0.20, 0.90), frandom(-0.4, 0.4), frandom(0.5, 1.8),
			0, 0, -0.06,
			1.0, 0.016, -0.010);
	}
}

class FancyWallSlimedrip : FancyEmitter
{
	override Sound FancySound() { return "world/slimedrip"; }

	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x34B01C; }
	override int FancyLightRadius() { return 32; }
	override int FancyLightRadius2() { return 22; }
	override double FancyLightParam() { return 3.0; }
	override int FancyLightTier() { return 2; }

	// A drain drips. It does not spray -- the low rate is the effect.
	override int FancyPuffRate() { return 26; }

	override void FancyPuff()
	{
		A_SpawnParticle(0x60FF40, SPF_RELATIVE | SPF_FULLBRIGHT,
			55, frandom(1.5, 2.5), 0,
			frandom(0, 4), frandom(-8, 8), frandom(-4, 12),
			frandom(0.05, 0.25), 0, frandom(-0.6, -0.2),
			0, 0, -0.12,
			0.85, 0.012, 0);
	}
}

// Gargoyle-head blood fountain. Shares the drip sound; the original did too.
class FancyWallGargfont : FancyEmitter
{
	override Sound FancySound() { return "world/slimedrip"; }
	override int FancyPuffRate() { return 40; }

	override void FancyPuff()
	{
		A_SpawnParticle(0x9C0C0C, SPF_RELATIVE,
			55, frandom(1.5, 3.0), 0,
			frandom(0, 4), frandom(-6, 6), frandom(-4, 10),
			frandom(0.20, 0.70), frandom(-0.1, 0.1), frandom(-0.9, -0.3),
			0, 0, -0.14,
			0.85, 0.012, 0);
	}
}

// ---- Burning things --------------------------------------------------------

class FancyWallFirewall : FancyEmitter
{
	override Sound FancySound() { return "world/firewall"; }

	override int FancyLightType() { return DynamicLight.FlickerLight; }
	override Color FancyLightColor() { return 0xFF7020; }
	override int FancyLightRadius() { return 112; }
	override int FancyLightRadius2() { return 78; }
	override double FancyLightParam() { return 0.30; }
	override int FancyLightTier() { return 1; }

	override int FancyPuffRate() { return 130; }

	override void FancyPuff()
	{
		A_SpawnParticle(0xFF8830, SPF_RELATIVE | SPF_FULLBRIGHT,
			55, frandom(1.0, 2.0), 0,
			frandom(0, 4), frandom(-28, 28), frandom(-32, 48),
			frandom(0.10, 0.55), frandom(-0.3, 0.3), frandom(0.7, 2.0),
			0, 0, -0.04,
			0.95, 0.018, -0.008);
	}
}

// FIREBLU. It has never been clear what it is meant to be, so it gets to be
// the one thing everyone agrees it looks like: something wrong and magenta.
class FancyWallFireblu : FancyEmitter
{
	override Sound FancySound() { return "world/fireblu"; }

	override int FancyLightType() { return DynamicLight.FlickerLight; }
	override Color FancyLightColor() { return 0xC030FF; }
	override int FancyLightRadius() { return 96; }
	override int FancyLightRadius2() { return 62; }
	override double FancyLightParam() { return 0.38; }
	override int FancyLightTier() { return 1; }

	override int FancyPuffRate() { return 90; }

	override void FancyPuff()
	{
		A_SpawnParticle(0xE050FF, SPF_RELATIVE | SPF_FULLBRIGHT,
			50, frandom(1.0, 2.0), 0,
			frandom(0, 4), frandom(-24, 24), frandom(-32, 44),
			frandom(0.10, 0.50), frandom(-0.3, 0.3), frandom(0.6, 1.8),
			0, 0, -0.04,
			0.90, 0.020, -0.008);
	}
}

// ---- Technology ------------------------------------------------------------

class FancyWallCompstation : FancyEmitter
{
	override Sound FancySound() { return "world/compstation"; }

	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x30C850; }
	override int FancyLightRadius() { return 56; }
	override int FancyLightRadius2() { return 38; }
	override double FancyLightParam() { return 2.0; }
	override int FancyLightTier() { return 2; }
}

class FancyWallTechhum : FancyEmitter
{
	override Sound FancySound() { return "world/techhum"; }

	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x3898D0; }
	override int FancyLightRadius() { return 48; }
	override int FancyLightRadius2() { return 32; }
	override double FancyLightParam() { return 3.2; }
	override int FancyLightTier() { return 2; }
}

// COMPFUZ -- the broken monitor. RandomFlickerLight rather than FlickerLight
// because a dead screen does not pulse, it stutters, and the random one picks
// a fresh interval each time instead of settling into a rhythm you can read.
class FancyWallStatic : FancyEmitter
{
	override Sound FancySound() { return "world/static"; }

	override int FancyLightType() { return DynamicLight.RandomFlickerLight; }
	override Color FancyLightColor() { return 0x6098FF; }
	override int FancyLightRadius() { return 64; }
	override int FancyLightRadius2() { return 30; }
	override double FancyLightParam() { return 4; }   // tics between rolls
	override int FancyLightTier() { return 1; }
}

// ---- Lights ----------------------------------------------------------------

// The colour is not in this file. The scanner reads it off the texture name --
// LITEBLU is blue, LITERED is red -- and hands it over before the first tick.
// See the wall-lights block in fancy_tables.zsc.
class FancyWallLights : FancyEmitter
{
	override Sound FancySound() { return "world/walllight"; }

	override int FancyLightType() { return DynamicLight.PointLight; }
	override Color FancyLightColor() { return 0xFFE8B0; }
	override int FancyLightRadius() { return 104; }
	override int FancyLightTier() { return 1; }
}

// ---- One-offs --------------------------------------------------------------

// SP_FACE1. A slow, dim red breath -- the point is that you are not sure it is
// doing anything until you have been looking at it for a second.
class FancyWallFaces : FancyEmitter
{
	override Sound FancySound() { return "world/faces"; }

	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x902018; }
	override int FancyLightRadius() { return 64; }
	override int FancyLightRadius2() { return 20; }
	override double FancyLightParam() { return 4.5; }
	override int FancyLightTier() { return 2; }
}

// Kept for debugging the scanner, as it always was.
class FancyWallTestSound : FancyEmitter
{
	override Sound FancySound() { return "world/test"; }
}
