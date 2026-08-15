// ============================================================================
//  Environmental FancyWorld -- things.
// ============================================================================
//
//  The scan reads floors, ceilings and linedefs. It has never read THINGS, and
//  the map has been telling us about those just as loudly as about its
//  textures: a RedTorch is an object whose entire purpose is to be on fire in
//  the corner of a room. Doom places more of them than any other decoration and
//  every single one is a fire you can see and cannot hear.
//
//  This is a fourth pass in the same shape as the other three -- walk, match,
//  claim a lattice cell, spawn a FancyEmitter -- which is the whole reason it
//  is worth doing at all. It reuses the range gate, the occlusion duck, the
//  spawn stagger and the pitch detune without one line of new machinery.
//
//  WHY IT IS NOT A WorldThingSpawned HOOK, which is the obvious way to write
//  it and is wrong: WorldThingSpawned fires during level load, BEFORE
//  WorldLoaded has run MeasureMap. There is no claim lattice to dedup against
//  at that point, so a hall of twenty torches would be twenty live loops
//  stacked into one drone -- the exact thing the lattice exists to prevent, and
//  it would not have errored.
//
// ============================================================================

class FancyThingTorch : FancyEmitter
{
	override Sound FancySound() { return "world/torch"; }

	// NO LIGHT, and this is a decision rather than an omission -- the same
	// question as FancyCeilingDrip, with the opposite reasoning arriving at the
	// same answer. A torch obviously IS a light source. It is already lit:
	// GZDoom's own lights.pk3 attaches a flickerlight2 to every one of these
	// actors (wadsrc_lights/static/filter/doom.id/gldefs.txt:384-396 for
	// RedTorch alone). A light here would not be a lit torch, it would be a
	// torch lit twice -- double radius, two flickers beating against each
	// other, and a bloom nobody asked for on the most common decoration in the
	// game.
	//
	// FancyLightType() staying at its -1 default is the correct answer, and it
	// is written down because "why does the torch have no light" is the first
	// question the next person will ask, and the file otherwise looks like
	// someone forgot.
}
