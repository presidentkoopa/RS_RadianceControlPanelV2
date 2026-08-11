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

		// Always, not just on reopen -- a save made before the second
		// flashlight was removed still has its lights in it.
		let iterator = ThinkerIterator.Create("DarkDoomZ_Spotlight");
		for (Thinker mo; (mo = iterator.Next());) { mo.Destroy(); }
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

		// Settings poll, replacing the UiTick netevent -- see the note above
		// NetworkProcess. Cheap: a handful of cvar reads, and the fog pass
		// only runs when something actually changed.
		ChangeLighting();

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

	// [GITD] THE SECOND FLASHLIGHT IS GONE.
	//
	// DarkDoomZ shipped its own CustomInventory torch driving two
	// DynamicLights, and GITD_Flashlight already does everything it did and
	// more -- GITD_FlashlightSpot for surface light, GITD_FlashlightBounce for
	// the spill, and Level.SetVolumetricBeam for the cone you can actually
	// see in the air. Both ran at once, on separate menu pages, so setting
	// "Position" on one and "Mounted on" the other configured two different
	// lights that did not agree.
	//
	// The key still works: ddz_toggleflashlight now toggles fl_enabled rather
	// than using an inventory item that no longer exists.
	override void PlayerEntered(PlayerEvent e) {
		// Nothing to give any more. Kept as an override so it is obvious this
		// was removed rather than never written.
	}

	// [GITD] The per-tic network event is gone. Upstream DarkDoomZ sent
	// "UpdateLights" from UiTick EVERY TIC just so NetworkProcess could call
	// ChangeLighting -- a settings poll dressed as a net message, which in
	// multiplayer was a message per client per tic and padding in every demo.
	// The netevent bought nothing here: ChangeLighting only reads server
	// cvars, which the playsim can do directly, and it already carries its
	// own change detection. So WorldTick just calls it. The NetworkProcess
	// hook stays for anything external that still sends the event by name.
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
			// Fog only. The old ApplyLightLevels, which rewrote every
			// sector's Lightlevel in place, is GONE -- it had had no caller
			// for some time, and it is now actively dangerous: light belongs
			// to GITD_Composite, and a second writer stamping raw values
			// would resurrect the 35Hz wall flicker this mod already paid for
			// once. ddz_mode still selects the darkness CURVE; see
			// DarknessMul.
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


	// Darkness is now a TINT DECLARATION, not a paint job.
	//
	// This used to call SetColor on every sector every tic. That worked right
	// up until anything else wanted a say, and then it silently won every
	// argument by virtue of running last -- a sweep setpiece could tint a room
	// red and be erased before the frame was drawn. Handing the multiplier to
	// GITD_Composite instead means darkness composes with everything else
	// rather than overwriting it, and the ordering of names in mapinfo.txt
	// stops deciding what the player sees.
	//
	// The one-time LightLevel repair went with it. GITD_Composite snapshots
	// the map's own levels at WorldLoaded and is the only thing that writes
	// them now, so there is nothing left to repair.
	void ApplyDarkness() {
		int desat = clamp(ddz_desat, 0, 255);

		// NOTHING TO SAY? DO NOT WALK THE MAP. Added 2026-08-11.
		//
		// The enabled/mode test used to live inside DarknessMulFor, i.e. inside
		// the loop, so switching darkness off still paid a full per-sector pass
		// plus a string cvar lookup per sector to declare a no-op tint. Both
		// conditions are level-wide, so they are answered once, here.
		//
		// Tint(1,1,1) and Desaturate(0) are both identities, so skipping the
		// loop entirely is exactly equivalent to running it -- the compositor
		// resets its accumulators every tic regardless.
		bool on = CVar.FindCVar("gitd_dd_enabled").GetBool();
		if ((!on || ddz_mode == 0) && desat == 0) return;

		// Per sector, because three of the four curves read the sector's own
		// starting brightness. Sky handling lives inside DarknessMulFor, where
		// it scales the adjustment the way the original did.
		for (int i = 0; i < Level.Sectors.Size(); i++) {
			int v = on ? clamp(int(DarknessMulFor(i) * 255.0), 0, 255) : 255;
			GITD_Composite.Tint(i, Color(255, v, v, v));
			GITD_Composite.Desaturate(i, desat);
		}
	}

	// The old mode zoo -- subtract, compress, clamp, gamma -- existed because
	// there was no multiply available. There is one now, so every mode
	// collapses into "how much light survives", which is the only thing any
	// of them was ever expressing.
	// THE FOUR CURVES ARE REAL AGAIN.
	//
	// They were collapsed into one when the old ApplyLightLevels was deleted:
	// that function held the actual per-mode maths, and without it every mode
	// from 1 to 4 folded to the same linear ramp. Four names for one behaviour
	// is a lying menu, so at the time they were honestly relabelled "Use the
	// How dark dial" -- but the right fix was always to bring the curves back,
	// not to rename around their absence.
	//
	// They are restored VERBATIM from the original (commit d0cee20,
	// ApplyLightLevels), with one necessary change of frame: the original
	// wrote sector light levels directly, and nothing may do that any more.
	// So each curve is evaluated against the sector's OWN map light level and
	// returned as the ratio between what the curve wants and what the map had.
	// The compositor multiplies that in as a tint, which reproduces the curve
	// without a second writer -- and, unlike the original, without fighting
	// Doom's own blinking sectors.
	//
	// This is why it is per sector rather than one number for the level: three
	// of the four curves depend on how bright the sector already was. Only
	// Compress does not.
	double DarknessMulFor(int idx) {
		if (!CVar.FindCVar("gitd_dd_enabled").GetBool()) return 1.0;

		int mode = ddz_mode;
		if (mode == 0) return 1.0;

		double base = double(GITD_Composite.BaseLight(idx));
		if (base <= 0.0) return 1.0;   // already black; nothing to scale

		// PreGain lifts the input before the curve, exactly as it did.
		double L = base + double(PreGain);

		bool sky = (Level.Sectors[idx].GetTexture(0) == skyflatnum ||
					Level.Sectors[idx].GetTexture(1) == skyflatnum);

		// The original scaled the ADJUSTMENT for sky sectors, not the result.
		double A = 32.0 * clamp(ddz_preset, 0, 8);
		if (sky) A *= SkyMode;

		double outL;
		switch (mode) {
			case 1:  // Subtract -- raw light level, a simple fade
				outL = L - A;
				break;
			case 2:  // Compress -- linear, the one curve that ignores base
				outL = L * (1.0 - A / 256.0);
				break;
			case 3:  // Cap brightest -- clamp the ceiling, leave dark rooms
				outL = min(L, 256.0 - A);
				break;
			case 4:  // Deepen shadows -- exponential gamma
				if (A <= 0.0) { outL = L; break; }
				outL = (256.0 - (A ** (A / 256.0)))
					 * ((L / 256.0) ** (1.0 + (A / (33.0 - (A / 8.0)))));
				break;
			case 10: outL = L - 96.0;  break;   // DarkDoom Lite
			case 11: outL = L - 128.0; break;   // DarkDoom Classic
			case 12: outL = L - 256.0; break;   // DarkDoom Black
			default: return 1.0;
		}

		// MinLight is a floor, PostGain a lift after the curve -- both as they
		// were, and both live again now that a curve exists to apply them to.
		outL = max(outL, double(MinLight));
		outL += double(PostGain);

		return clamp(outL / base, 0.0, 1.0);
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
		// Was the Off sound in both branches -- turning the torch ON clicked
		// like turning it off. DDZ_Flashlight_On has sat in sndinfo.txt,
		// defined and never referenced, the whole time.
		if(Active) { Active = false; owner.A_StartSound("DDZ_Flashlight_Off", CHAN_AUTO, 0, 0.5); }
		else { Active = true; owner.A_StartSound("DDZ_Flashlight_On", CHAN_AUTO, 0, 0.5); }
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

	// [GITD] THE PRESET HAS TO TAKE HOLD WHILE YOU ARE STILL LOOKING AT IT.
	//
	// Every GITD menu turns off the dim and the blur so the room behind is the
	// room you are adjusting. That promise breaks for presets specifically,
	// because applying one is playsim work and the playsim is not running: the
	// menu pauses the game in single player, and choosing a preset from the
	// title screen has no playsim to run at all. So the choice sat in the cvar
	// and the room only changed once you backed out -- or, from the title
	// screen, never.
	//
	// A menu tic is the one clock still running, and menu code may write
	// cvars, so it asks the same question the playsim asks. Sync is idempotent
	// and derived from state, so both asking costs nothing and neither has to
	// know about the other.
	override void Ticker() {
		super.Ticker();
		let c = CVar.FindCVar("gitd_preset");
		if (c) GITD_PresetProfile.Sync(c.GetInt());
	}
}