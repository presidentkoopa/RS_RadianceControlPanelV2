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
