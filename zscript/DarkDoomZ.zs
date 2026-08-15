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
	int Mode, Preset, PreGain, PostGain, MinLight;
	int OldMode, OldPreset, OldPreGain, OldPostGain, OldMinLight;
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

		// Always, not just on reopen -- a save made before DarkDoomZ's own
		// flashlight was removed still has its lights in it, and the class is
		// gone now, so they would sit in the map forever with nothing left
		// that knows how to clear them.
		//
		// Looked up by NAME rather than by the class itself for exactly that
		// reason: the type no longer exists to be named in code, and
		// ThinkerIterator.Create takes a class that may legitimately resolve
		// to nothing on a fresh save.
		let iterator = ThinkerIterator.Create("DynamicLight");
		for (Thinker mo; (mo = iterator.Next());)
		{
			let dl = DynamicLight(mo);
			if (dl && dl.GetClassName() == 'DarkDoomZ_Spotlight') dl.Destroy();
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
	// 35Hz.
	//
	// [GITD] DarkDoomZ's sector fog is gone with its flashlight. It was a
	// distance tint written per sector with SetFogDensity, and this project
	// has its own fog -- a volumetric slab with a top you stand in, a surface,
	// noise, a wake and disturbances, driven from Render.zs. Two fog systems
	// on one screen is two answers to the same question, and the sector one
	// was the weaker answer.
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
		// NetworkProcess. Cheap: a handful of cvar reads, and the pass only
		// runs when something actually changed.
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
		MinLight = ddz_minlight;

		bool changed = (
			OldMode != Mode ||
			OldPreset != Preset ||
			OldPreGain != PreGain ||
			OldPostGain != PostGain ||
			OldSkyMode != Skymode ||
			OldMinLight != MinLight);

		if (changed) {
			// Fog only. The old ApplyLightLevels, which rewrote every
			// sector's Lightlevel in place, is GONE -- it had had no caller
			// for some time, and it is now actively dangerous: light belongs
			// to GITD_Composite, and a second writer stamping raw values
			// would resurrect the 35Hz wall flicker this mod already paid for
			// once. ddz_mode still selects the darkness CURVE; see
			// DarknessMul.
		}
		OldMode = Mode;
		OldPreset = Preset;
		OldPreGain = PreGain;
		OldPostGain = PostGain;
		OldSkyMode = SkyMode;
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
		// [GITD] THE COLOUR DRAIN LEFT THIS FUNCTION.
		//
		// It used to be declared per sector, right beside the tint, and the
		// comment below said it had to stay that way because a sector
		// desaturation is what makes it reach the TEXTURES rather than only
		// what this mod draws, and there was no per-fragment equivalent.
		//
		// There is one now. Level.SetDesatGlobal lands in the same
		// dodesaturate() every path already goes through -- textures,
		// sprites, glow, sweeps, brightmaps -- so it reaches exactly what the
		// sector byte reached. Render.zs pushes it; see the note there.
		//
		// Two things that buys, beyond one call replacing a walk over every
		// sector in the map:
		//
		//   Nothing is MUTATED. Turning the drain off is passing zero rather
		//   than writing 255 sectors back, so it cannot half-restore and a
		//   savegame does not carry a drained map around.
		//
		//   And the per-sector channel is FREE AGAIN for the things that
		//   should be local. A setpiece's envDesat (SweepEngine.zs) drains the
		//   rooms its wavefront has reached; it was competing with a map-wide
		//   drain for one accumulator, and a global one has no business being
		//   spent on that.

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

		// [GITD] PER-PIXEL DARKNESS TAKES THIS PASS'S JOB, NOT ITS PLACE.
		//
		// The shader term and this loop compute the same curve. Running both
		// applies it TWICE -- the sector is scaled down and then every
		// fragment in it is scaled down again by the same factor -- so the
		// room goes roughly twice as dark as either setting asked for and
		// every level on the dial reads wrong. Not a subtle failure, but a
		// confusing one, because both halves are behaving correctly.
		//
		// So exactly one of them runs. The colour drain used to be exempt from
		// that -- it was a sector desaturation and there was no per-fragment
		// equivalent -- so it stayed here in both modes. It has one now and it
		// has left this function entirely; see the note at the top.
		bool perPixel = GITD_Render.GetB("gitd_dd_perpixel", false);
		if (perPixel) on = false;

		if (!on || ddz_mode == 0) return;

		// Per sector, because three of the four curves read the sector's own
		// starting brightness. Sky handling lives inside DarknessMulFor, where
		// it scales the adjustment the way the original did.
		for (int i = 0; i < Level.Sectors.Size(); i++) {
			int v = clamp(int(DarknessMulFor(i) * 255.0), 0, 255);
			GITD_Composite.Tint(i, Color(255, v, v, v));
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


}

class DarkDoomZ_OptionMenu : OptionMenu {
	override void Init(Menu parent, OptionMenuDescriptor desc) {
		super.Init(parent, desc);
		DontDim = true;
		DontBlur = true;

		// [GITD] AND THE WORLD KEEPS RUNNING BEHIND IT.
		//
		// Turning off the dim and the blur was always a promise of a live
		// preview, and it was only ever half kept: a menu pauses the game in
		// single player, so the room you could suddenly see clearly was a
		// FROZEN one. Nothing re-evaluated, so a slider took effect when you
		// backed out rather than when you moved it.
		//
		// It could not be fixed on the menu's side alone. The lane colours,
		// the preset palette and the sweep's band positions are written to
		// SECTORS, and a sector write is playsim work that a paused game does
		// not do -- there is no scope trick that makes it happen. The only
		// thing that shows those live is letting the world run.
		//
		// So it runs. DMenu::DontPause is a fork addition for exactly this,
		// and the cost is worth saying out loud rather than hiding behind an
		// option nobody would find: monsters keep moving and you can be hurt
		// while this page is open. For a page whose entire purpose is to show
		// you the room you are adjusting, that is the right trade -- and a
		// lighting page you have to keep leaving to see is not one.
		DontPause = true;
		lastEnginePreset = -1;
	}

	// [GITD] The menu's clock, which keeps running while the playsim is
	// paused. Two jobs, both idempotent and both cheap enough to do every
	// menu tic rather than trying to detect a change:
	//
	//   - preset apply/recall, so choosing one takes hold while you are still
	//     looking at the room, and so a preset chosen at the title screen --
	//     where there is no playsim at all -- is not silently dropped
	//   - the render settings, so every slider on the waves and darkness
	//     pages moves the picture as you drag it
	//
	// Both call the same functions the playsim calls. Nothing here is a
	// second implementation, which is what stops the two drifting apart.
	override void Ticker() {
		super.Ticker();

		let c = CVar.FindCVar("gitd_preset");
		int preset = c ? c.GetInt() : 0;

		GITD_PresetProfile.Sync(preset);
		GITD_Render.PushAll();

		// [GITD] AND THE ENGINE HALF, LIVE, LIKE EVERYTHING ELSE.
		//
		// Bloom and exposure are gl_* -- engine cvars, which ZScript will only
		// write from menu code. That used to mean they could only ride a
		// keypress, so a preset chosen from the console arrived in two halves
		// at two different moments and the page's live preview was a lie for
		// the two settings that most decide how a scene reads.
		//
		// The fork now counts a menu's TICK as menu code (DMenu::CallTicker),
		// which it always should have, so the engine half applies here with
		// everything else.
		//
		// ON CHANGE, NOT EVERY TIC. These are the player's own settings when
		// no preset is holding them -- reapplying a profile's bloom 35 times a
		// second would make the Bloom page impossible to use while any GITD
		// menu was open, because every edit would be overwritten before it
		// could be seen.
		SyncEngine(preset);

		// AFTER SyncEngine, and the order is the whole point. If a preset
		// changed on this same tic, its bloom is the one the player asked for
		// and lands first; a roll pressed deliberately is newer intent and
		// lands second. Swap these two and pressing Randomise Bloom while a
		// preset row is moving throws the roll away on some tics and not
		// others, which is the worst kind of bug to be told about.
		SpendBloomRoll();
	}

	// [GITD] THE ROLLED BLOOM, SPENT.
	//
	// gitd_roll_bloom rolls its numbers in PLAY scope, where they cannot be
	// applied -- bloom is gl_*, and the netevent that carries the roll is not
	// menu code by any definition. So the roll leaves its result in
	// gitd_bloom_roll_* and raises _pending, and this spends it.
	//
	// It lives on the base class rather than on a subclass any page has to opt
	// into, because the button that fires it is on the FRONT page and the page
	// you want to see the result on is Bloom. Anything narrower means the roll
	// lands only if you happen to be standing somewhere specific, which is a
	// worse failure than not having the feature.
	void SpendBloomRoll() {
		let p = CVar.FindCVar("gitd_bloom_roll_pending");
		if (!p || !p.GetBool()) return;

		// Cleared BEFORE the writes, not after. A roll applies exactly once,
		// and clearing first keeps that true even if one of the gl_* names has
		// gone missing in some future engine and the write below quietly does
		// nothing -- otherwise the flag sits raised forever and re-pushes the
		// same numbers every tic, which would make the Bloom page impossible to
		// edit while it was open. That is the precise shape of the bug the
		// change guard in SyncEngine exists to prevent, and there is no reason
		// to reintroduce it eight lines later.
		p.SetInt(0);

		PushRolled("gl_bloom_amount",    "gitd_bloom_roll_amount");
		PushRolled("gl_bloom_threshold", "gitd_bloom_roll_threshold");
		PushRolled("gl_bloom_knee",      "gitd_bloom_roll_knee");
		PushRolled("gl_bloom_tint_r",    "gitd_bloom_roll_tint_r");
		PushRolled("gl_bloom_tint_g",    "gitd_bloom_roll_tint_g");
		PushRolled("gl_bloom_tint_b",    "gitd_bloom_roll_tint_b");
		// gl_bloom itself is deliberately absent. It is the master switch, and
		// no roll in this mod moves one.
	}

	// Guarded on both sides. gl_bloom_knee does not exist in every GZDoom that
	// could load this, and an unguarded FindCVar().SetFloat on a name that does
	// not resolve is a native dereference, not a catchable abort.
	private void PushRolled(string engineName, string rolledName) {
		let d = CVar.FindCVar(engineName);
		if (!d) return;
		let s = CVar.FindCVar(rolledName);
		if (!s) return;
		d.SetFloat(s.GetFloat());
	}

	// ONE PLACE THAT DECIDES, because the Ticker and MenuEvent both used to
	// call ApplyEngine and only one of them had the change guard -- so moving
	// the Preset row reapplied a profile's bloom on every keystroke.
	//
	// The transition OUT of a preset is the case that did not exist at all.
	// ApplyEngine's default arm returns without doing anything, so turning
	// OMGWTF off left amount 3.2 at threshold 0.05 with the streak and the
	// fringe still on, while the row read Off.
	//
	// `prev > 0` is what makes this safe for everyone else. lastEnginePreset
	// starts at -1, so the first tick after the page opens with no preset
	// selected sees prev = -1 and does nothing -- somebody who has never
	// touched a preset never has their own bloom written by this.
	void SyncEngine(int preset) {
		if (preset == lastEnginePreset) return;

		int prev = lastEnginePreset;
		lastEnginePreset = preset;

		if (preset > 0) GITD_PresetProfile.ApplyEngine(preset);
		else if (prev > 0 && GITD_PresetProfile.HasEngineHalf(prev))
			GITD_PresetProfile.RestoreEngine();
	}

	// Which preset's engine half was last applied. Reset to -1 in Init, so the
	// first tick after a page opens always applies -- which is what makes a
	// console-set preset catch its bloom up the moment you open the menu.
	private int lastEnginePreset;

	// [GITD] STILL HERE, BUT NO LONGER LOAD-BEARING.
	//
	// This override used to be the ONLY way a profile's bloom could apply, back
	// when InMenu was set around MenuEvent and not around Ticker, and the long
	// comment that used to sit here explained that bargain at length. The fork
	// closed that gap -- see the note in Ticker -- and this became a second
	// caller of a function that is already idempotent and already runs 35 times
	// a second.
	//
	// IT IS KEPT ANYWAY, and the reason is not sentiment. SyncEngine returns
	// immediately unless the preset actually changed, so the cost is a compare;
	// and a keypress is the one event that can change gitd_preset and be
	// followed by the menu closing before the next tick ever runs. Removing it
	// would reintroduce the half-apply on exactly the interaction the whole
	// system exists for.
	//
	// THE COMMENT THAT WAS HERE OUTLIVED THE TRUTH IT DESCRIBED, and an agent
	// working on the randomise buttons read it, believed it, and built a whole
	// opt-in menu subclass to work around a restriction that had already been
	// lifted. That subclass is gone. A stale comment is not a cosmetic problem;
	// it is a wrong answer sitting in the place people look for answers.
	override bool MenuEvent(int mkey, bool fromcontroller) {
		bool handled = super.MenuEvent(mkey, fromcontroller);
		let c = CVar.FindCVar("gitd_preset");
		if (c) SyncEngine(c.GetInt());
		return handled;
	}

}