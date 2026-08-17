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
	// THE WATER RUNS THICK, and it cost no asset at all.
	//
	// Under Lovecraftian Fog this fall borrows the map's own SLIME voice --
	// same wall, same emitter, same position, a sound already in the mod for
	// the pools thirty feet below it. A new recording could not have said it
	// more plainly than the map's own slime saying it.
	//
	// The particles are deliberately NOT switched with it. A green waterfall
	// would be the preset changing what the map IS; this preset changes what
	// the map sounds like, and the moment those two disagree the player
	// trusts their ears less, not more.
	override Sound FancySound()
	{
		if (FancyVoice() == 4) return "world/slimefall";
		return "world/waterfall";
	}

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

// BLODRIP1-4 -- the wall that is a PICTURE of dripping blood. It is in doom.wad
// and in doom2.wad both, and it was named nowhere in this mod until now: the
// scan has walked past a texture depicting exactly the thing this layer exists
// to find, on every map, for the mod's whole life.
//
// Its neighbour FancyWallSlimedrip is a loop; this one is not, and the
// difference is the point. A DRIP IS AN EVENT. The three samples are 0.36s,
// 0.84s and 0.45s, and looping any of them gives a metronome at two to three
// hertz, which is the one thing a drip is not. So FancySound() stays empty --
// a supported state, and how FancySectorHotCore has always worked -- and the
// sound is fired from FancyPuff on CHAN_VOICE, at a rate low enough that two
// of these in one room never fall into step.
//
// Rate arithmetic, because a number nobody can check is a number nobody can
// fix: a pass is 6 tics, so 5.83 of them a second. 5/256 of those is one
// audible drip every 8.8 seconds per emitter, and two of these in a room is
// one every four and a half -- a wet wall rather than a leaking tap.
//
// THE SOUND IS ON FancyOneShot, NOT FancyPuff, and that is the one place this
// class departs from its neighbours. FancyPuff sits behind fw_particles, which
// is right for a nukage bubble (no bubble, no pop) and wrong here, where the
// drip is the emitter's ONLY sound: a player who turned particles down would
// lose a whole voice and nothing would tell them why. The droplet and the
// splash are deliberately not the same roll either -- most real drips fall
// silently, and a wall of running blood has every right to make a noise
// without a droplet on screen at that instant.
//
// NO LIGHT. Blood does not glow, and there is no tier for "flavour that should
// not exist" -- FancyLightType() staying at its -1 default is the answer.
class FancyWallBloodDrip : FancyEmitter
{
	override int FancyOneShotRate() { return 5; }

	override void FancyOneShot()
	{
		// CHAN_VOICE, following FancySectorNukage and the hot-rock hiss: a
		// one-shot never goes on CHAN_BODY, so it can never cut a loop out
		// from under a neighbouring emitter that shares this actor's channel
		// discipline. This class holds no loop today, and that is exactly the
		// kind of thing that stops being true later.
		A_StartSound("world/blooddrip", CHAN_VOICE);
	}

	override int FancyPuffRate() { return 20; }

	override void FancyPuff()
	{
		A_SpawnParticle(0x8C1010, SPF_RELATIVE,
			60, frandom(1.5, 2.5), 0,
			frandom(0, 4), frandom(-10, 10), frandom(-6, 14),
			frandom(0.05, 0.25), 0, frandom(-0.7, -0.3),
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
	// COMPSTA1/2, colder. Cold War is the only preset with anything to say
	// about a terminal bank; the other four fall through to the map's own
	// voice, which is why there is no case 2, 3 or 4 here.
	override Sound FancySound()
	{
		if (FancyVoice() == 1) return "world/compstation/cold";
		return "world/compstation";
	}

	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x30C850; }
	override int FancyLightRadius() { return 56; }
	override int FancyLightRadius2() { return 38; }
	override double FancyLightParam() { return 2.0; }
	override int FancyLightTier() { return 2; }
}

class FancyWallTechhum : FancyEmitter
{
	// THE SAME WALLS, A DIFFERENT ROOM. No emitter is added by any of this and
	// no texture changes hands -- COMPTALL is still COMPTALL and the hum still
	// comes out of it. Cold War makes it a reactor field; Low Power makes it
	// labour. Anything not listed falls through to the map's own voice, which
	// is why there is no case 3 and no case 4: an alarm is a thing that
	// STARTS, and a room tone that was always different is not one.
	override Sound FancySound()
	{
		switch (FancyVoice())
		{
			case 1: return "world/techhum/cold";
			case 2: return "world/techhum/strain";
		}
		return "world/techhum";
	}

	override int FancyLightType() { return DynamicLight.PulseLight; }
	override Color FancyLightColor() { return 0x3898D0; }
	override int FancyLightRadius() { return 48; }
	override int FancyLightRadius2() { return 32; }
	override double FancyLightParam() { return 3.2; }
	override int FancyLightTier() { return 2; }
}

// The broken screen. RandomFlickerLight rather than FlickerLight because a
// dead monitor does not pulse, it stutters -- and until the table row behind
// this class was bound to a texture that EXISTS, none of it had ever run. It
// was keyed to COMPFUZ1-4, which are in neither IWAD; the class, its two
// lumps, its $random group and the mod's only RandomFlickerLight have been
// dead since they were written. See BuildWalls for the rebind.
//
// TWO THINGS ARE INVERTED FROM EVERY OTHER LIGHT IN THIS FILE, and both are
// forced by the engine rather than chosen:
//
//   RADIUS1 IS THE SMALL ONE HERE. a_dynlightdata.cpp computes this type's
//   flicker range as radius2 - radius1 and re-rolls whenever the current
//   radius exceeds radius2 -- a guard that assumes radius2 is the larger
//   value. With the old 64/30 the range came out NEGATIVE, the guard was true
//   on essentially every tic, and the interval below was bypassed entirely: a
//   35 Hz strobe, in a VR mod, from a class nobody could see.
//
//   PARAM IS TICS DIVIDED BY 360. AttachLightDirect stores param*360 for every
//   non-pulse type (a_dynlight.cpp:926) and this type compares its tick count
//   against that directly. The old `return 4; // tics between rolls` was 1440
//   tics -- forty-one seconds between rolls, on a light meant to stutter.
class FancyWallStatic : FancyEmitter
{
	override Sound FancySound() { return "world/static"; }

	override int FancyLightType() { return DynamicLight.RandomFlickerLight; }
	override Color FancyLightColor() { return 0x6098FF; }
	override int FancyLightRadius()  { return 30; }           // radius1 = SMALL
	override int FancyLightRadius2() { return 64; }           // radius2 = LARGE
	override double FancyLightParam() { return 8.0 / 360.0; } // 8 tics
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
	// LOVECRAFTIAN FOG: it stops breathing and starts speaking. This emitter
	// was built to be unnerving and has spent its life being a slow red glow
	// with a breath under it; voice 4 is that finally being used, out of the
	// one wall texture in Doom that is a face, and out of nothing else.
	override Sound FancySound()
	{
		if (FancyVoice() == 4) return "world/faces/wrong";
		return "world/faces";
	}

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
