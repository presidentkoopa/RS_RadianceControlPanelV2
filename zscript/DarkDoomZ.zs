// === DarkDoomZ ===
// Sector light darkening + flashlight, from DarkDoomZ by Sterling Parker
// ("Caligari87"), zlib licensed. Altered for Glow In The Dark: the
// version directive was removed so this can be #included, and the menu
// lives in this mod's MENUDEF rather than its own.
//
// Original credits: inspired by "Dark Doom" by Josh771 (no code used).
// Code from Kinsie, Gutawer, FishyClockwork, phantombeta, Marisa Kirisame,
// Accensus. Flashlight sounds by mshahen (CC BY 3.0). Logo by Accensus.
//
// This darkens Sector.LightLevel, which is entirely separate from the glow
// lanes -- glow is added on top of the base lighting, so floor and ceiling
// glow stay visible even in a room this has crushed to near black.


//Courtesy FishyClockwork, with modifications by Caligari87
class DarkDoomZ_Handler : EventHandler {
	Array<int> BaseLightLevels;
	int Mode, Preset, PreGain, PostGain, FogDensity, MinLight;
	int OldMode, OldPreset, OldPreGain, OldPostGain, OldFogDensity, OldMinLight;
	double SkyMode, OldSkyMode;
	int BaseAdjustment, FinalAdjustment;
	bool IsSky;

	override void WorldLoaded(WorldEvent e) {
		if(!ddz_lighting) {
			ThinkerIterator it = ThinkerIterator.Create ("Lighting");
			Lighting effect;
			while (effect = Lighting (it.Next ())) { effect.Destroy (); }
		}

		BaseLightLevels.Clear();
		for(int i = 0; i < Level.Sectors.Size(); i++) {
			BaseLightlevels.Push(Level.Sectors[i].LightLevel);
		}

		ChangeLighting();

		if(e.isReopen) {
			let iterator = ThinkerIterator.Create("DarkDoomZ_Spotlight");
			for (Thinker mo; (mo = iterator.Next());) { mo.Destroy(); }
		}
	}

	// [GITD] REASSERT EVERY TIC.
	//
	// ChangeLighting only wrote sector light when one of ITS OWN settings
	// changed. Anything that wrote a light level afterwards therefore won
	// permanently -- and Doom's Lighting thinkers (blink, flicker, glow,
	// strobe) do exactly that, every tic, in the handful of sectors a mapper
	// marked. Those sectors climbed back to full brightness and stayed there
	// while everything around them stayed dark, which is why it was PARTICULAR
	// walls rather than all of them.
	//
	// Re-applying costs one pass of integer arithmetic over the sector list at
	// 35Hz. Fog is deliberately NOT reapplied here -- SetFogDensity is the
	// expensive part and nothing else competes for it, so it stays on the
	// settings-changed path.
	override void WorldTick() {
		// Toggling Sector Effects off used to need a map reload, because the
		// thinkers were only destroyed in WorldLoaded. Do it here and it takes
		// effect at once. Turning it back ON still needs a reload -- a
		// destroyed thinker cannot be un-destroyed, and that is worth saying
		// out loud rather than pretending the toggle is symmetric.
		if (!ddz_lighting) {
			ThinkerIterator it = ThinkerIterator.Create("Lighting");
			Lighting effect;
			while (effect = Lighting(it.Next())) { effect.Destroy(); }
		}

		ApplyDarkness();

		// PER-TIC REASSERT REVERTED. It fought Doom's own Lighting thinkers --
		// blink, flicker, glow, strobe write their sector every tic from their
		// own state, and this wrote the darkened snapshot every tic on top.
		// Two writers, one value, 35 times a second: the walls flickered.
		//
		// The original bug it was meant to fix is still real -- those sectors
		// climb back to full brightness and stay there -- but a steady wrong
		// brightness beats a strobing one, so this goes back until it can be
		// done without a fight. The correct shape is to darken from the
		// thinker's CURRENT output for those sectors, after it has run, rather
		// than from the load-time snapshot; that needs ordering guarantees
		// this had none of.

		// [GITD] KILL THE MUZZLE FLASH BRIGHTENING.
		//
		// Vanilla Doom raises player.extralight while a weapon is in its flash
		// state, which lifts the light level of the WHOLE VIEW. Firing
		// continuously keeps re-entering that state, so it never decays -- the
		// scene just sits brighter for as long as you hold the trigger, which
		// is why it looked like it "stopped after 30 shots" when what actually
		// stopped was the ammo.
		//
		// It is invisible in a normally lit game and enormous here: going from
		// near-black to lit is a far bigger jump than from lit to lighter, so
		// the darker the mod makes the level the more the flash wrecks it.
		//
		// Nothing in the engine gates it, so it is zeroed here every tic.
		//
		// INT_MIN IS LEFT ALONE. The renderer uses that exact value as the
		// sentinel for the inverse colormap -- hw_drawinfo.cpp:339 -- so
		// clobbering it would break the invulnerability sphere.
		let nf = CVar.FindCVar("gitd_dd_noflash");
		if (!nf || nf.GetBool())
		{
			for (int i = 0; i < MAXPLAYERS; i++)
			{
				if (!playeringame[i]) continue;
				if (players[i].extralight > 0) players[i].extralight = 0;
			}
		}
	}

	override void PlayerEntered(PlayerEvent e) {
		PlayerInfo player = players[e.PlayerNumber];
		let FlashlightClass = (class<Inventory>)(Actor.GetReplacement("DarkDoomZ_Flashlight"));
		player.mo.GiveInventory(FlashlightClass, 1);
	}

	override void UiTick() {
		EventHandler.SendNetworkEvent("UpdateLights");
	}

	override void NetworkProcess(ConsoleEvent e) {
		if(e.Name == "UpdateLights") ChangeLighting();
	}

	void ChangeLighting() {
		// [GITD] Master switch. Mode 0 is this mod's own "disabled" value,
		// which restores original light levels -- so honouring the master
		// switch is just forcing that mode rather than adding a new path.
		Mode = CVar.FindCVar("gitd_dd_enabled").GetBool() ? ddz_mode : 0;
		Preset = ddz_preset;
		PreGain = ddz_pregain;
		PostGain = ddz_postgain;
		SkyMode = ddz_skymode;
		FogDensity = ddz_fog;
		MinLight = ddz_minlight;

		bool changed = (
			OldMode != Mode ||
			OldPreset != Preset ||
			OldPreGain != PreGain ||
			OldPostGain != PostGain ||
			OldSkyMode != Skymode ||
			OldFogDensity != FogDensity ||
			OldMinLight != MinLight);

		if (changed) {
			// ApplyLightLevels is deliberately NOT called any more -- see
			// ApplyDarkness. Kept below only so an older save or a mode that
			// wants the legacy behaviour has something to call.
			ApplyFog();
		}
		OldMode = Mode;
		OldPreset = Preset;
		OldPreGain = PreGain;
		OldPostGain = PostGain;
		OldSkyMode = SkyMode;
		OldFogDensity = FogDensity;
		OldMinLight = MinLight;
	}

	//========================================================================
	// DARKNESS BY TINT, NOT BY LIGHT LEVEL.
	//
	// This used to rewrite every sector's LightLevel. That is the same field
	// Doom's own Lighting thinkers write -- blink, flicker, glow, strobe --
	// so the two fought over one number. Apply once and the thinkers win
	// permanently, leaving lit sectors in a dark level. Apply every tic and
	// they alternate, and the walls strobe. There is no version of writing
	// that field that is not a fight.
	//
	// Sector COLOR is a different field entirely. It multiplies the sector's
	// rendering and NOTHING else writes it -- not the thinkers, not the
	// playsim. So it can be reasserted every tic forever without a conflict.
	//
	// It is also better behaviour, not just safer: a flickering sector keeps
	// flickering, because the thinker still moves LightLevel and the tint
	// scales whatever it produces. The old approach flattened those effects
	// by overwriting them; this one dims them.
	//========================================================================

	bool restoredLevels;

	void ApplyDarkness() {
		// One-time repair. Any level whose LightLevel this mod already
		// stamped on stays wrong until it is put back, and the tint would
		// then be multiplying an already-damaged number.
		if (!restoredLevels) {
			restoredLevels = true;
			for (int i = 0; i < BaseLightLevels.Size() && i < Level.Sectors.Size(); i++)
				Level.Sectors[i].LightLevel = BaseLightLevels[i];
		}

		double m = DarknessMul();
		int desat = clamp(ddz_desat, 0, 255);

		for (int i = 0; i < Level.Sectors.Size(); i++) {
			double mm = m;
			bool sky = (Level.Sectors[i].GetTexture(0) == skyflatnum ||
						Level.Sectors[i].GetTexture(1) == skyflatnum);
			// SkyMode scaled the ADJUSTMENT before; here it scales how much
			// darkening the sky receives, which is the same intent.
			if (sky) mm = 1.0 - (1.0 - m) * SkyMode;

			int v = clamp(int(mm * 255.0), 0, 255);
			Level.Sectors[i].SetColor(Color(255, v, v, v), desat);
		}
	}

	// The old mode zoo -- subtract, compress, clamp, gamma -- existed because
	// there was no multiply available. There is one now, so every mode
	// collapses into "how much light survives", which is the only thing any
	// of them was ever expressing.
	double DarknessMul() {
		if (!CVar.FindCVar("gitd_dd_enabled").GetBool()) return 1.0;

		// A cvar reference is not assignable, so modes 1-4 are folded on READ
		// rather than written back. The menu shows the right thing either way
		// now that all four are labelled identically.
		int mode = ddz_mode;
		if (mode >= 1 && mode <= 4) mode = 2;

		switch (mode) {
			case 0:  return 1.0;
			case 10: return 0.62;   // DarkDoom Lite
			case 11: return 0.45;   // DarkDoom Classic
			case 12: return 0.16;   // DarkDoom Black
		}
		// Modes 1-4 all read the preset; the curves differed only in shape and
		// every one of them bottomed out at the same place.
		double t = clamp(ddz_preset, 0, 8) / 8.0;
		return clamp(1.0 - t * 0.92, 0.06, 1.0);
	}

	// Fog only moves when a setting moves, so it stays off the per-tic path.
	void ApplyFog() {
		for(int i = 0; i < BaseLightLevels.Size(); i++) {
			bool sky = (level.Sectors[i].GetTexture(0) == skyflatnum ||
						level.Sectors[i].GetTexture(1) == skyflatnum);
			double d = FogDensity;
			if (sky) { d *= SkyMode; }
			level.Sectors[i].SetFogDensity(int(d));
		}
	}

	void ApplyLightLevels() {
		{
			BaseAdjustment = 32 * Preset;
			for(int i = 0; i < BaseLightLevels.Size(); i++) {
				int BaseLightLevel = BaseLightLevels[i];
				BaseLightLevel += PreGain;

				IsSky = (level.Sectors[i].GetTexture(0) == skyflatnum ||
						 level.Sectors[i].GetTexture(1) == skyflatnum);

				FinalAdjustment = BaseAdjustment;
				if(IsSky) { FinalAdjustment = int(FinalAdjustment * SkyMode); }

				// Link to graphing calculator depiction of different modes
				// https://www.desmos.com/calculator/v1ni4wftcg
				switch(Mode) {
					case 1: //subtract raw light level (simple fade)
						Level.Sectors[i].Lightlevel = BaseLightLevel - FinalAdjustment;
						break;
					case 2: //linear compression
						Level.Sectors[i].Lightlevel = int(BaseLightLevel * (1.0 - FinalAdjustment / 256.0));
						break;
					case 3: //clamp max brightness level
						Level.Sectors[i].Lightlevel = clamp(BaseLightLevel, 0, 256 - FinalAdjustment);
						break;
					case 4: //apply exponential gamma curve
						Level.Sectors[i].Lightlevel = int((256 - (FinalAdjustment ** (FinalAdjustment / 256))) * (BaseLightLevel / 256.0) ** (1 + (FinalAdjustment / (33 - (FinalAdjustment / 8)))));
						break;
					case 10: //DarkDoom Lite (fixed subtract mode)
						Level.Sectors[i].Lightlevel = BaseLightLevel - 96;
						break;
					case 11: //DarkDoom Classic (fixed subtract mode)
						Level.Sectors[i].Lightlevel = BaseLightLevel - 128;
						break;
					case 12: //DarkDoom Black (fixed subtract mode)
						Level.Sectors[i].Lightlevel = BaseLightLevel - 256;
						break;
					default: //disable
						Level.Sectors[i].Lightlevel = BaseLightLevel; //reset lightlevels
						break;
				}

				Level.Sectors[i].Lightlevel = max(Level.Sectors[i].Lightlevel, MinLight);
				Level.Sectors[i].Lightlevel += PostGain;
			}
		}
	}
}

class DarkDoomZ_Flashlight : CustomInventory {
	DarkDoomZ_Spotlight SelfLight1, SelfLight2;
	bool Active;
	int Quality,OldQuality;
	int Type,OldType;
	int Mount,OldMount;
	int R,G,B;
	int beamInner, beamOuter, beamRadius;
	int spillInner, spillOuter, spillRadius;
	double offsetAngle, offsetZ;
	int inertia;
	double spring, damping;

	default {
		+INVENTORY.PERSISTENTPOWER;
	}

	override void DoEffect() {
		super.DoEffect();
		Quality = CVar.GetCvar("ddz_fl_quality").GetInt();
		Type = CVar.GetCvar("ddz_fl_type").GetInt();
		Mount = CVar.GetCvar("ddz_fl_pos").GetInt();
		if(Active) {
			if(Quality != OldQuality ||
			   Type != OldType ||
			   Mount != OldMount) {

				if(SelfLight1) { SelfLight1.Destroy(); }
				if(SelfLight2) { SelfLight2.Destroy(); }
			}

			switch(Type) {
				case 0: //Incandescent
					R = 255;
					G = 214;
					B = 170;
					beamInner = 0;
					beamOuter = 25;
					beamRadius = 384;
					spillInner = 15;
					spillOuter = 45;
					spillRadius = 128;
					break;
				case 1: //Halogen
					R = 255;
					G = 241;
					B = 224;
					beamInner = 0;
					beamOuter = 20;
					beamRadius = 512;
					spillInner = 10;
					spillOuter = 60;
					spillRadius = 384;
					break;
				case 2: //LED
					R = 248;
					G = 255;
					B = 255;
					beamInner = 0;
					beamOuter = 15;
					beamRadius = 640;
					spillInner = 15;
					spillOuter = 75;
					spillRadius = 256;
					break;
				case 3: //Red filter
					R = 192;
					G = 36;
					B = 34;
					beamInner = 0;
					beamOuter = 20;
					beamRadius = 256;
					spillInner = 10;
					spillOuter = 60;
					spillRadius = 128;
					break;
			}

			switch(Mount) {
				case 0: //Handheld
					spring = 0.25;
					damping = 0.2;
					inertia = 4;
					offsetAngle = 0;
					offsetZ = -13;
					break;
				case 1: //Left Shoulder
					spring = 0.35;
					damping = 0.75;
					inertia = 2;
					offsetAngle = 80;
					offsetZ = -5;
					break;
				case 2: //Right Shoulder
					spring = 0.35;
					damping = 0.75;
					inertia = 2;
					offsetAngle = -80;
					offsetZ = -5;
					break;
				case 3: //Helmet
					spring = 1;
					damping = 1;
					inertia = 1;
					offsetAngle = 0;
					offsetZ = 4;
					break;
			}

			switch(Quality) {
				case 0:
					if(!SelfLight1) {
						SelfLight1 = DarkDoomZ_Spotlight(Spawn("DarkDoomZ_Spotlight",owner.pos,false));
						SelfLight1.FollowTarget = owner;
						SelfLight1.args[DynamicLight.LIGHT_RED] = R; //R
						SelfLight1.args[DynamicLight.LIGHT_GREEN] = G; //G
						SelfLight1.args[DynamicLight.LIGHT_BLUE] = B; //B
						SelfLight1.args[DynamicLight.LIGHT_INTENSITY] = (beamRadius + spillRadius) / 2; //Radius
						SelfLight1.SpotInnerAngle = (beamInner + spillInner) / 2;
						SelfLight1.SpotOuterAngle = (beamOuter + spillOuter) / 2;
						SelfLight1.angle = owner.angle;
						SelfLight1.pitch = owner.pitch;
						SelfLight1.spring = spring;
						SelfLight1.damping = damping;
						SelfLight1.inertia = inertia;
						SelfLight1.offsetAngle = offsetAngle;
						SelfLight1.offsetZ = offsetZ;
					}
					break;
				case 1:
					if(!SelfLight1) {
						SelfLight1 = DarkDoomZ_Spotlight(Spawn("DarkDoomZ_Spotlight",owner.pos,false));
						SelfLight1.FollowTarget = owner;
						SelfLight1.args[DynamicLight.LIGHT_RED] = R; //R
						SelfLight1.args[DynamicLight.LIGHT_GREEN] = G; //G
						SelfLight1.args[DynamicLight.LIGHT_BLUE] = B; //B
						SelfLight1.args[DynamicLight.LIGHT_INTENSITY] = beamRadius; //Radius
						SelfLight1.SpotInnerAngle = beamInner;
						SelfLight1.SpotOuterAngle = beamOuter;
						SelfLight1.angle = owner.angle;
						SelfLight1.pitch = owner.pitch;
						SelfLight1.spring = spring;
						SelfLight1.damping = damping;
						SelfLight1.inertia = inertia;
						SelfLight1.offsetAngle = offsetAngle;
						SelfLight1.offsetZ = offsetZ;
					}
					if(!SelfLight2) {
						SelfLight2 = DarkDoomZ_Spotlight(Spawn("DarkDoomZ_Spotlight",owner.pos,false));
						SelfLight2.FollowTarget = owner;
						SelfLight2.args[DynamicLight.LIGHT_RED] = int(R * 0.75); //R
						SelfLight2.args[DynamicLight.LIGHT_GREEN] = int(G * 0.75); //G
						SelfLight2.args[DynamicLight.LIGHT_BLUE] = int(B * 0.75); //B
						SelfLight2.args[DynamicLight.LIGHT_INTENSITY] = spillRadius; //Radius
						SelfLight2.SpotInnerAngle = spillInner;
						SelfLight2.SpotOuterAngle = spillOuter;
						SelfLight2.angle = owner.angle;
						SelfLight2.pitch = owner.pitch;
						SelfLight2.spring = spring;
						SelfLight2.damping = damping;
						SelfLight2.inertia = inertia;
						SelfLight2.offsetAngle = offsetAngle;
						SelfLight2.offsetZ = offsetZ;
					}
					break;
			}
		}
		else {
			if(SelfLight1) { SelfLight1.Destroy(); }
			if(SelfLight2) { SelfLight2.Destroy(); }
		}
		OldQuality = Quality;
		OldType = Type;
		OldMount = Mount;
	}

	States {
	Spawn:
		ROCK A -1;
		stop;
	Use:
		TNT1 A 1 { invoker.ToggleActive(); }
		loop;
	}

	virtual void ToggleActive() {
		if(Active) { Active = false; owner.A_StartSound("DDZ_Flashlight_Off", CHAN_AUTO, 0, 0.5); }
		else { Active = true; owner.A_StartSound("DDZ_Flashlight_Off", CHAN_AUTO, 0, 0.5); }
	}
}

class DarkDoomZ_Spotlight : DynamicLight {
	actor FollowTarget;
	double vela, velp;
	double spring, damping;
	double offsetAngle, offsetZ;
	vector3 targetPos;
	int inertia;

	default {
		DynamicLight.Type "Point";
		+DYNAMICLIGHT.ATTENUATE;
		+DYNAMICLIGHT.SPOT
	}
	override void Tick() {
		super.Tick();
		if(followTarget && followTarget.player) {
			if(inertia == 0) inertia = 1;
			targetpos = followTarget.vec3Angle(
				2 + (6 * abs(sin(offsetAngle))),
				followtarget.angle + offsetAngle,
				followtarget.player.viewheight + offsetZ,
				false);
			vel.x += DampedSpring(pos.x, targetpos.x, vel.x, 1, 1);
			vel.y += DampedSpring(pos.y, targetpos.y, vel.y, 1, 1);
			vel.z += DampedSpring(pos.z, targetpos.z, vel.z, 1, 1);
			vela  += DampedSpring(angle, followTarget.angle, vela, spring, damping);
			velp  += DampedSpring(pitch, followTarget.pitch, velp, spring, damping);
			setOrigin(pos + vel, true);
			A_SetAngle(angle + (vela / inertia), true);
			A_SetPitch(pitch + (velp / inertia), true);
		}
	}

	double DampedSpring(double p, double r, double v, double k, double d) {
		return -(d * v) - (k * (p - r));
	}
}

class DarkDoomZ_OptionMenu : OptionMenu {
	override void Init(Menu parent, OptionMenuDescriptor desc) {
		super.Init(parent, desc);
		DontDim = true;
		DontBlur = true;
	}
}