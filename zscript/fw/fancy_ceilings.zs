// ============================================================================
//  Environmental FancyWorld -- ceilings.
// ============================================================================

// The great outdoors. Wind, and nothing else -- a sky sector's light is the
// map's own business and not something to start second-guessing from here.
class FancySectorSky : FancyEmitter
{
	override Sound FancySound() { return "world/fsky"; }
}

// TLITE6_1 and friends.
//
// This is the single best return in the mod for the least work, and it is
// worth being clear about why. Doom's lit ceiling flats are a PICTURE of a
// light. The sector around them is usually brightened by hand to sell it, but
// nothing is actually emitting anything -- walk under one with a torch and the
// flat is the darkest thing in the room.
//
// The scan already knew where every one of them was. It was using that to play
// a hum.
class FancySectorCeilingLite : FancyEmitter
{
	override Sound FancySound() { return "world/ceilite"; }

	override int FancyLightType() { return DynamicLight.PointLight; }
	override Color FancyLightColor() { return 0xFFF0C8; }
	override int FancyLightRadius() { return 144; }
	override int FancyLightTier() { return 1; }
}

// A WET CEILING.
//
// The cheapest row in the whole design: the scan already hangs an emitter 12
// units under every interesting ceiling flat -- see PlaceCeiling -- so this is
// a Define line and three overrides, and no new machinery of any kind.
//
// The loop is one variant where a hum would need three, and that is fine HERE
// rather than a corner cut. The comb-filtering the detune scheme in
// fancy_common.zs exists to fight is a TONAL effect: twenty copies of one
// drone lock into one drone, but twenty copies of a sparse transient recording
// stay twenty drips. The +/-8% pitch spread is doing enough on its own.
//
// NO LIGHT, and it is a decision rather than an omission. Wet rock emits
// nothing, and the one thing this mod must never do is add a glow because an
// emitter happened to already be there -- that is how a cave ends up lit by
// its own dampness. FancyLightType() staying at its -1 default is the answer.
class FancyCeilingDrip : FancyEmitter
{
	override Sound FancySound() { return "world/cavedrip"; }

	override int FancyPuffRate() { return 20; }

	override void FancyPuff()
	{
		// ABSOLUTE OFFSETS, not SPF_RELATIVE. SpawnCeilingActors does not set
		// an angle on what it places -- only the wall pass does -- so a
		// relative offset here would resolve against angle 0 and throw every
		// droplet due east across the cave.
		A_SpawnParticle(0xB0C8D8, 0,
			70, frandom(1.0, 2.0), 0,
			frandom(-40, 40), frandom(-40, 40), 0,
			0, 0, frandom(-1.6, -0.9),
			0, 0, -0.20,
			0.70, 0.010, 0);
	}
}
