// ============================================================================
//  Universal Map Enhancements -- decorative props.
// ============================================================================
//
//  First slice: every vanilla decoration that already animates BRIGHT in its
//  own IWAD sprite -- a torch, a tech lamp, the burning barrel -- and so was
//  already telling the map it is a light source without ever being one.
//  Same idea GITD already applies to lit ceiling flats and wall light
//  textures, aimed at standalone props instead. Chosen over columns, skulls
//  and candles that do NOT animate bright in vanilla: those read as plain
//  scenery, not an implied light, and giving them one would be inventing a
//  fact about the map rather than completing one it already stated.
//
//  Each class below is a `replaces` for a real vanilla actor and changes
//  nothing about its Default block or its Spawn state -- same sprite, same
//  size, same idle flicker, straight from the IWAD. All that is added is
//  +SHOOTABLE, 1 HP, and a Death state: one hit breaks it. No new sprite
//  exists for "broken" in any of these -- none of the vanilla sets have one
//  -- so breaking is a flash and a scatter of debris (UMEDecorFX.Shatter),
//  then the actor is gone, the same beat a vanilla explosive barrel already
//  has minus the explosion.
//
//  Health is 1 and not a real pool on purpose: this is a decoration getting
//  a reaction, not a destructible fixture with a fight attached to it.
//
// ============================================================================

// ---- Torches -----------------------------------------------------------

class UMEBlueTorch : BlueTorch replaces BlueTorch
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0x5090FF, 56.0, 1.4);
	}
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
			UMEDecorFX.Shatter(self, 0x5090FF, 56.0);
		}
		Stop;
	}
}

class UMEShortBlueTorch : ShortBlueTorch replaces ShortBlueTorch
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0x5090FF, 48.0, 1.3);
	}
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
			UMEDecorFX.Shatter(self, 0x5090FF, 48.0);
		}
		Stop;
	}
}

class UMEGreenTorch : GreenTorch replaces GreenTorch
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0x50E060, 56.0, 1.4);
	}
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
			UMEDecorFX.Shatter(self, 0x50E060, 56.0);
		}
		Stop;
	}
}

class UMEShortGreenTorch : ShortGreenTorch replaces ShortGreenTorch
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0x50E060, 48.0, 1.3);
	}
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
			UMEDecorFX.Shatter(self, 0x50E060, 48.0);
		}
		Stop;
	}
}

class UMERedTorch : RedTorch replaces RedTorch
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0xFF4030, 56.0, 1.4);
	}
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
			UMEDecorFX.Shatter(self, 0xFF4030, 56.0);
		}
		Stop;
	}
}

class UMEShortRedTorch : ShortRedTorch replaces ShortRedTorch
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0xFF4030, 48.0, 1.3);
	}
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
			UMEDecorFX.Shatter(self, 0xFF4030, 48.0);
		}
		Stop;
	}
}

// ---- Tech lamps ----------------------------------------------------------
//
// Same warm-white this mod already picked for FancyWallLights (GlowHandler's
// own wall-light emitter) -- a tech lamp and a wall light fixture are the
// same kind of thing wearing different geometry.

class UMETechLamp : TechLamp replaces TechLamp
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0xFFE8B0, 64.0, 1.3);
	}
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
			UMEDecorFX.Shatter(self, 0xFFE8B0, 64.0);
		}
		Stop;
	}
}

class UMETechLamp2 : TechLamp2 replaces TechLamp2
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0xFFE8B0, 56.0, 1.3);
	}
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
			UMEDecorFX.Shatter(self, 0xFFE8B0, 56.0);
		}
		Stop;
	}
}

// ---- Burning barrel --------------------------------------------------------
//
// The biggest and brightest of this slice on purpose -- an open flame in a
// steel drum throws more light than a wall sconce, and shooting it already
// reads as dangerous in a way a torch does not.

class UMEBurningBarrel : BurningBarrel replaces BurningBarrel
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0xFF8020, 88.0, 1.6);
	}
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
			UMEDecorFX.Shatter(self, 0xFF8020, 88.0);
		}
		Stop;
	}
}

// ---- Column ----------------------------------------------------------------
//
// Missed in the first pass -- Column (COLU) is BRIGHT in the IWAD exactly
// like the tech lamps, and belongs to the same family: the plain tech-base
// aesthetic reads as internally lit, not as carved stone.

class UMEColumn : Column replaces Column
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0xFFE8B0, 60.0, 1.3);
	}
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
			UMEDecorFX.Shatter(self, 0xFFE8B0, 60.0);
		}
		Stop;
	}
}

// ---- Candles -----------------------------------------------------------

class UMECandlestick : Candlestick replaces Candlestick
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0xFFB050, 36.0, 1.1);
	}
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
			UMEDecorFX.Shatter(self, 0xFFB050, 36.0);
		}
		Stop;
	}
}

class UMECandelabra : Candelabra replaces Candelabra
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0xFFB050, 44.0, 1.2);
	}
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
			UMEDecorFX.Shatter(self, 0xFFB050, 44.0);
		}
		Stop;
	}
}

class UMEHeadCandles : HeadCandles replaces HeadCandles
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umeSlot;
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umeSlot = UMEDecorFX.Glow(self, 0xFFC868, 40.0, 1.2);
	}
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
			UMEDecorFX.Shatter(self, 0xFFC868, 40.0);
		}
		Stop;
	}
}

// ---- The ominous ones --------------------------------------------------
//
// EvilEye and FloatingSkull are BRIGHT too, but they aren't light fixtures --
// they're things watching you. A steady glow like the torches would flatten
// that into "another lamp"; a breathing pulse (UMEDecorFX.Pulse) keeps it
// reading as alive. Both read gitd_voice directly -- see UMESettings.GetInt
// for why that one read doesn't compromise this component's independence --
// and go a shade wronger and a beat faster under Lovecraftian Fog, the same
// move FancyWallFaces already makes on the SP_FACE1 wall texture.
//
// No permanent slot to release on destroy: every pulse already expires on
// its own life, so there is nothing OnDestroy needs to clean up here.

class UMEEvilEye : EvilEye replaces EvilEye
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umePulseClock;

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		// Randomised start so a room with three of these doesn't breathe
		// in lockstep.
		umePulseClock = random(0, 19);
	}

	override void Tick()
	{
		Super.Tick();
		if (--umePulseClock > 0) return;

		bool wrong = UMESettings.GetInt("gitd_voice", 0) == 4;
		umePulseClock = wrong ? 12 : 20;

		Color c = wrong ? Color(255, 130, 20, 60) : Color(255, 160, 40, 210);
		UMEDecorFX.Pulse(self, c, 60.0, wrong ? 2.0 : 1.5);
	}

	States
	{
	Death:
		TNT1 A 0 { UMEDecorFX.Shatter(self, 0xA02838, 60.0); }
		Stop;
	}
}

class UMEFloatingSkull : FloatingSkull replaces FloatingSkull
{
	Default { Health 1; +SHOOTABLE; +NOBLOOD; }
	private int umePulseClock;

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		umePulseClock = random(0, 19);
	}

	override void Tick()
	{
		Super.Tick();
		if (--umePulseClock > 0) return;

		bool wrong = UMESettings.GetInt("gitd_voice", 0) == 4;
		umePulseClock = wrong ? 12 : 20;

		Color c = wrong ? Color(255, 90, 200, 80) : Color(255, 200, 216, 232);
		UMEDecorFX.Pulse(self, c, 52.0, wrong ? 1.8 : 1.3);
	}

	States
	{
	Death:
		TNT1 A 0 { UMEDecorFX.Shatter(self, 0xC8D8E8, 52.0); }
		Stop;
	}
}
