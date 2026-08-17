// ============================================================================
//  Universal Map Enhancements -- scenery that breaks.
// ============================================================================
//
//  ume_decorations.zs took every vanilla prop that ALREADY animates BRIGHT and
//  gave it the light it was already claiming to have. This file is the other
//  half of that idea, and deliberately NOT the same treatment: columns, skulls
//  on sticks, trees and stalagmites are not lit in vanilla and never were, so
//  they get no glow. Handing one a light would be inventing a fact about the
//  map rather than completing one it already stated -- the same line drawn in
//  ume_decorations.zs, held here rather than quietly crossed to keep a pattern
//  going.
//
//  What they get instead is the shatter, on its own cvar. Breakable scenery is
//  a change to what the world DOES, not to how it is lit, and someone who
//  wants this mod's light without its physics should be able to say so -- so
//  ume_scenery is separate from ume_decorations rather than folded into it.
//
//  CONCEPT ONLY, credited: Universal Map Enhancements (BROS_ETT_311) makes the
//  same vanilla props shootable, which is where the idea of doing it at all
//  came from. Its own versions carry biome-detection branches (a tree becomes
//  a palm over sand, hell-growth over flesh), fire-propagation states, and a
//  spread of external classes and ACS this component does not have and does
//  not want. None of that is reproduced. Every class below is a `replaces`
//  that keeps the vanilla actor's own sprite, size and Spawn state untouched
//  and adds exactly two things: it can be shot, and when it dies it throws
//  debris in a colour that suits what it was made of.
//
// ============================================================================

// Debris colours, named rather than repeated as hex at nine call sites. Stone
// greys, bone whites and wood browns -- what the prop is made of, since these
// have no light of their own to throw.
class UMEScenery abstract play
{
	const RUBBLE = 0x9C9488;   // grey stone
	const BONE   = 0xD8D0BC;   // skull, bone
	const GREEN  = 0x5C8C4C;   // the green marble columns
	const RED    = 0x8C3C34;   // the red marble columns
	const MEAT   = 0x8C2020;   // the heart column
	const WOOD   = 0x6C4C2C;   // trees

	// One hit, a scatter, gone -- see UMEDecorFX.Shatter. Separate from the
	// decorations' own gate so light and breakability are independent.
	static void Shatter(Actor from, Color c, double spread)
	{
		if (!UMESettings.GetBool("ume_scenery", true)) return;
		UMEDecorFX.Shatter(from, c, spread);
	}
}

// It can be shot, and it is not an aim target.
//
// +NOTAUTOAIMED matters more here than anywhere: P_AimLineAttack takes any
// MF_SHOOTABLE actor as an aim candidate (p_map.cpp) and MF6_NOTAUTOAIMED is
// the only escape, so without it a hall of columns quietly competes with the
// monsters for every shot you fire. These are scenery -- they should be
// hittable when you aim at them and invisible to aiming when you do not.
//
// Only the Default block is shared. The Death state stays per class, because
// it is already one line there and the debris colour reads better sitting
// next to the prop it belongs to than routed through a field -- a mixin
// cannot declare a virtual that the same class then overrides (it is
// inserted textually, so both land in one class and collide), so sharing the
// state would mean adding a PostBeginPlay to every scenery class purely to
// set two values. Not worth it to save one line each.
mixin class UMEBreakable
{
	Default
	{
		Health 1;
		+SHOOTABLE
		+NOBLOOD
		+NOTAUTOAIMED
	}
}

// ---- Columns ---------------------------------------------------------------
//
// Column itself is NOT here -- it is BRIGHT in vanilla and so lives in
// ume_decorations.zs with the lamps, where it gets a glow as well.

class UMETallGreenColumn : TallGreenColumn replaces TallGreenColumn
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.GREEN, 40.0); } Stop; }
}

class UMEShortGreenColumn : ShortGreenColumn replaces ShortGreenColumn
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.GREEN, 32.0); } Stop; }
}

class UMETallRedColumn : TallRedColumn replaces TallRedColumn
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.RED, 40.0); } Stop; }
}

class UMEShortRedColumn : ShortRedColumn replaces ShortRedColumn
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.RED, 32.0); } Stop; }
}

class UMESkullColumn : SkullColumn replaces SkullColumn
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.BONE, 34.0); } Stop; }
}

// The one column that is meat rather than masonry, and the debris says so.
class UMEHeartColumn : HeartColumn replaces HeartColumn
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.MEAT, 34.0); } Stop; }
}

class UMETechPillar : TechPillar replaces TechPillar
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.RUBBLE, 48.0); } Stop; }
}

// ---- Impaled heads ---------------------------------------------------------

class UMEHeadOnAStick : HeadOnAStick replaces HeadOnAStick
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.BONE, 28.0); } Stop; }
}

class UMEHeadsOnAStick : HeadsOnAStick replaces HeadsOnAStick
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.BONE, 34.0); } Stop; }
}

// ---- Natural ---------------------------------------------------------------
//
// TorchTree is the burning tree (TRE1) and BigTree the plain one (TRE2).
// NEITHER is BRIGHT in vanilla, which is worth stating because the first
// reads as though it should be: it is a picture of a tree on fire that has
// never emitted a photon. Left dark anyway. The burning tree throwing embers
// on the way down is as far as this goes -- a light on it would be a real
// change to what the map looks like standing still, not just when shot.

class UMETorchTree : TorchTree replaces TorchTree
{
	mixin UMEBreakable;
	// Embers rather than woodchips -- this is the tree that is on fire.
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, 0xC86828, 36.0); } Stop; }
}

class UMEBigTree : BigTree replaces BigTree
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.WOOD, 44.0); } Stop; }
}

class UMEStalagtite : Stalagtite replaces Stalagtite
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.RUBBLE, 30.0); } Stop; }
}

class UMEStalagmite : Stalagmite replaces Stalagmite
{
	mixin UMEBreakable;
	States { Death: TNT1 A 0 { UMEScenery.Shatter(self, UMEScenery.RUBBLE, 30.0); } Stop; }
}
