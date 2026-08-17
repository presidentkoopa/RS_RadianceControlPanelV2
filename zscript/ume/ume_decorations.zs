// ============================================================================
//  Universal Map Enhancements -- decorative props.
// ============================================================================
//
//  Every vanilla decoration that already animates BRIGHT in its own IWAD
//  sprite -- a torch, a tech lamp, the burning barrel -- and so was already
//  telling the map it is a light source without ever being one. Same idea
//  GITD already applies to lit ceiling flats and wall light textures, aimed
//  at standalone props instead. Chosen over columns, skulls and candles that
//  do NOT animate bright in vanilla: those read as plain scenery, not an
//  implied light, and giving them one would be inventing a fact about the
//  map rather than completing one it already stated. Those live in
//  ume_scenery.zs and get the breaking without the glow.
//
//  Each class is a `replaces` for a real vanilla actor and changes nothing
//  about its Spawn state -- same sprite, same size, same idle flicker,
//  straight from the IWAD. All that is added is the light, and that it can
//  be shot. No new sprite exists for "broken" in any of these, so breaking
//  is a flash and a scatter of debris, then the actor is gone -- the same
//  beat a vanilla explosive barrel already has minus the explosion.
//
//  ---- THE MIXIN, AND WHY --------------------------------------------------
//
//  This file was thirteen copies of the same thirty lines, because every
//  class here has to extend the specific vanilla actor it replaces (that
//  inheritance slot is what keeps the IWAD sprite and dimensions), so there
//  is no shared base class to hang the behaviour on.
//
//  That is what a mixin is for, and the copies were a real cost rather than
//  an aesthetic one: the range-culling fix a few commits ago was one bug
//  that had to be found and fixed in thirteen places, and the next one would
//  have been too. Everything shared now lives in UMEDecorGlow exactly once
//  -- the slot, the stagger clock, the tick, the release, the Death state --
//  and a class supplies only what is genuinely its own: the colour, the
//  radius, and how bright.
//
//  Those three are FIELDS set through UMEGlowInit(), not a virtual the class
//  overrides, and that is a constraint rather than a preference: a mixin is
//  inserted textually into the class, so a virtual declared in the mixin and
//  an override written in the same class are the same class trying to define
//  one name twice, which the compiler rejects. The class supplies its own
//  PostBeginPlay -- the one piece deliberately NOT in the mixin -- and calls
//  UMEGlowInit from it.
//
// ============================================================================

mixin class UMEDecorGlow
{
	private int umeSlot, umeClock;
	private Color umeCol;
	private double umeRadius, umeIntensity;

	// Called from the class's own PostBeginPlay. Sets what is genuinely per
	// prop, and the stagger phase, in one place.
	void UMEGlowInit(Color c, double radius, double intensity)
	{
		umeSlot = -1;
		umeCol = c;
		umeRadius = radius;
		umeIntensity = intensity;
		// Own starting phase, so a corridor of sixteen torches does not all
		// run their range check on the same tic.
		umeClock = random(1, UMEDecorFX.CHECK_PERIOD);
	}

	override void Tick()
	{
		Super.Tick();
		if (--umeClock > 0) return;
		umeClock = UMEDecorFX.CHECK_PERIOD;
		umeSlot = UMEDecorFX.GlowUpdate(self, umeSlot, umeCol, umeRadius,
			umeIntensity);
	}

	// A Shape slot is not actor-lifetime-aware -- something has to hand it
	// back, or the light outlives the prop and the slot is never reused.
	override void OnDestroy()
	{
		if (umeSlot >= 0) level.RemoveShape(umeSlot);
		Super.OnDestroy();
	}

	States
	{
	Death:
		TNT1 A 0
		{
			if (umeSlot >= 0) { level.RemoveShape(umeSlot); umeSlot = -1; }
			UMEDecorFX.Shatter(self, umeCol, umeRadius);
		}
		Stop;
	}
}

// One hit breaks it, and it is NOT an autoaim target.
//
// +NOTAUTOAIMED is the whole reason this Default block is worth sharing.
// P_AimLineAttack accepts any MF_SHOOTABLE actor as an aim candidate
// (p_map.cpp) and MF6_NOTAUTOAIMED is the only thing that excludes one --
// so without it every torch in a room competes with the monsters for your
// aim. Vanilla lives with that for the two barrels on a map; thirty
// shootable torches down one corridor is a different proposition, and it
// would read as the mod having broken aiming rather than as a decoration
// having become solid.
//
// Health is 1 and not a real pool on purpose: this is a decoration getting a
// reaction, not a destructible fixture with a fight attached to it.
mixin class UMEDecorShootable
{
	Default
	{
		Health 1;
		+SHOOTABLE
		+NOBLOOD
		+NOTAUTOAIMED
	}
}

// ---- Torches -----------------------------------------------------------

class UMEBlueTorch : BlueTorch replaces BlueTorch
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0x5090FF, 56.0, 1.4);
	}
}

class UMEShortBlueTorch : ShortBlueTorch replaces ShortBlueTorch
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0x5090FF, 48.0, 1.3);
	}
}

class UMEGreenTorch : GreenTorch replaces GreenTorch
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0x50E060, 56.0, 1.4);
	}
}

class UMEShortGreenTorch : ShortGreenTorch replaces ShortGreenTorch
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0x50E060, 48.0, 1.3);
	}
}

class UMERedTorch : RedTorch replaces RedTorch
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0xFF4030, 56.0, 1.4);
	}
}

class UMEShortRedTorch : ShortRedTorch replaces ShortRedTorch
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0xFF4030, 48.0, 1.3);
	}
}

// ---- Tech lamps ----------------------------------------------------------
//
// Same warm-white this mod already picked for FancyWallLights (GlowHandler's
// own wall-light emitter) -- a tech lamp and a wall light fixture are the
// same kind of thing wearing different geometry.

class UMETechLamp : TechLamp replaces TechLamp
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0xFFE8B0, 64.0, 1.3);
	}
}

class UMETechLamp2 : TechLamp2 replaces TechLamp2
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0xFFE8B0, 56.0, 1.3);
	}
}

// ---- Column ----------------------------------------------------------------
//
// COLU is BRIGHT in the IWAD exactly like the tech lamps, and belongs with
// them rather than with the other columns in ume_scenery.zs: the plain
// tech-base aesthetic reads as internally lit, not as carved stone.

class UMEColumn : Column replaces Column
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0xFFE8B0, 60.0, 1.3);
	}
}

// ---- Candles -----------------------------------------------------------

class UMECandlestick : Candlestick replaces Candlestick
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0xFFB050, 36.0, 1.1);
	}
}

class UMECandelabra : Candelabra replaces Candelabra
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0xFFB050, 44.0, 1.2);
	}
}

class UMEHeadCandles : HeadCandles replaces HeadCandles
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0xFFC868, 40.0, 1.2);
	}
}

// ---- Burning barrel --------------------------------------------------------
//
// The biggest and brightest of this slice on purpose -- an open flame in a
// steel drum throws more light than a wall sconce, and shooting it already
// reads as dangerous in a way a torch does not.

class UMEBurningBarrel : BurningBarrel replaces BurningBarrel
{
	mixin UMEDecorShootable;
	mixin UMEDecorGlow;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEGlowInit(0xFF8020, 88.0, 1.6);
	}
}

// ---- The ominous ones --------------------------------------------------
//
// EvilEye and FloatingSkull are BRIGHT too, but they aren't light fixtures --
// they're things watching you. A steady glow like the torches would flatten
// that into "another lamp"; a breathing pulse keeps it reading as alive, so
// these two take UMEDecorShootable but NOT UMEDecorGlow -- they hold no
// permanent slot, and every pulse expires on its own life.
//
// Both read gitd_voice directly -- see UMESettings.GetInt for why that one
// read doesn't compromise this component's independence -- and go a shade
// wronger and a beat faster under Lovecraftian Fog, the same move
// FancyWallFaces already makes on the SP_FACE1 wall texture.

mixin class UMEDecorPulse
{
	private int umePulseClock;
	private Color umeCalm, umeWrong;
	private double umePulseRadius, umePulseIntensity;

	// Same fields-plus-init shape as UMEDecorGlow, and for the same compiler
	// reason -- see the note at the top of this file.
	void UMEPulseInit(Color calm, Color wrongCol, double radius,
		double intensity)
	{
		umeCalm = calm;
		umeWrong = wrongCol;
		umePulseRadius = radius;
		umePulseIntensity = intensity;
		// Randomised start so a room with three of these doesn't breathe in
		// lockstep.
		umePulseClock = random(1, 20);
	}

	override void Tick()
	{
		Super.Tick();
		if (--umePulseClock > 0) return;

		bool wrong = UMESettings.GetInt("gitd_voice", 0) == 4;
		umePulseClock = wrong ? 12 : 20;

		UMEDecorFX.Pulse(self, wrong ? umeWrong : umeCalm, umePulseRadius,
			wrong ? umePulseIntensity * 1.3 : umePulseIntensity);
	}

	States
	{
	Death:
		TNT1 A 0 { UMEDecorFX.Shatter(self, umeCalm, umePulseRadius); }
		Stop;
	}
}

class UMEEvilEye : EvilEye replaces EvilEye
{
	mixin UMEDecorShootable;
	mixin UMEDecorPulse;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEPulseInit(Color(255, 160, 40, 210), Color(255, 130, 20, 60),
			60.0, 1.5);
	}
}

class UMEFloatingSkull : FloatingSkull replaces FloatingSkull
{
	mixin UMEDecorShootable;
	mixin UMEDecorPulse;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		UMEPulseInit(Color(255, 200, 216, 232), Color(255, 90, 200, 80),
			52.0, 1.3);
	}
}
