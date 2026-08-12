// ===========================================================================
// Muzzle flash -- a brief light on the player when they fire.
//
// WHY THIS VERSION. There have been three. The one that shipped in 3.2 was
// right and got lost; the one that replaced it was rewritten around
// A_AttachLight directly on the pawn; and RS_Main had its own, which spawned
// an UNATTENUATED point light with all three offsets at zero.
//
// That last one is the lesson. An actor's origin is at its FEET, so a light
// spawned at the pawn's position with no z offset sits on the floor -- and
// without LF_ATTENUATE a point light is near-full brightness across its whole
// radius rather than falling off. The result is not a muzzle flash. It is a
// lamp switched on under you, washing the floor in every direction, which is
// exactly what the owner kept seeing and what this file exists to not do.
//
// So the two things that matter here, and they are both one line each:
//
//   SetOrigin(host.pos + (0, 0, host.height * 0.6))   -- chest, not feet
//   A_AttachLight(..., 8)                             -- 8 = LF_ATTENUATE
//
// Everything else is timing.
//
// ONE LIGHT PER PLAYER, RE-ARMED. Full auto refreshes the same light rather
// than stacking a new one per shot, so holding the trigger is a single
// flickering flare instead of thirty overlapping lights.
//
// FIRED IS THE FLASH LAYER'S RISING EDGE. There is no clean "player shot"
// event. A_GunFlash sets the PSP_FLASH psprite layer on the shot and clears
// it otherwise, so the layer going from absent to present IS the bang. Not
// the button -- holding +attack fires before the gun does, and lighting the
// room a tic early reads as a bug.
// ===========================================================================

class GITD_MuzzleLight : Actor
{
	Actor host;
	Color mcol;
	int   mrad, mlife, mage;
	bool  strobe;

	Default { +NOINTERACTION; +NOGRAVITY; +NOBLOCKMAP; +DONTSPLASH; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	void Flash(Color c, int rad, int life)
	{
		mcol = c; mrad = rad; mlife = max(1, life); mage = -1;
	}

	void SetStrobe(bool s) { strobe = s; }

	override void Tick()
	{
		Super.Tick();

		// CHEST HEIGHT, NOT THE FLOOR. See the header -- this single line is
		// the difference between a muzzle flash and a lamp at your ankles.
		if (host)
			SetOrigin(host.pos + (0, 0, host.height * 0.6), true);

		mage++;
		if (mage > mlife) { A_RemoveLight("gitd_muzzle"); Destroy(); return; }

		double fade = 1.0 - double(mage) / double(mlife + 1);
		fade = clamp(fade, 0.0, 1.0);

		// The chaingun reads wrong as one long fade -- it is a string of
		// separate bangs, so it wants a hard on/off flicker on the level
		// clock rather than a decay. Steady regardless of when each shot
		// re-armed it, which is why it reads maptime and not mage.
		if (strobe)
			fade = ((level.maptime & 1) == 0) ? 1.0 : 0.15;

		int finalRad = max(1, int(double(mrad) * fade));

		// Flag 8 is LF_ATTENUATE: realistic falloff, so it LIGHTS a surface
		// rather than flatly washing everything inside the radius.
		A_AttachLight("gitd_muzzle", 0, mcol, finalRad, 0, 8);
	}
}

class GITD_MuzzleHandler : EventHandler
{
	private Array<GITD_MuzzleLight> mlights;
	private Array<int> wasFlashing;

	static int  CI(string n, int def)    { let c = CVar.FindCVar(n); return c ? c.GetInt()   : def; }
	static bool CB(string n, bool def)   { let c = CVar.FindCVar(n); return c ? c.GetBool()  : def; }

	override void WorldLoaded(WorldEvent e)
	{
		if (!e.IsSaveGame) mlights.Clear();
		wasFlashing.Clear();
	}

	Color MuzzleColor()
	{
		if (CB("gitd_muzzle_custom", false))
		{
			let cc = CVar.FindCVar("gitd_muzzle_color");
			if (cc)
			{
				int pk = cc.GetInt();
				return Color(255, (pk >> 16) & 255, (pk >> 8) & 255, pk & 255);
			}
		}
		return Color(255, 255, 190, 90);   // gunfire: golden-orange
	}

	override void WorldTick()
	{
		// Prune destroyed carriers before anything reads the list.
		for (int i = mlights.Size() - 1; i >= 0; i--)
			if (!mlights[i]) mlights.Delete(i);

		if (!CB("gitd_muzzle_lights", true))
		{
			// Switched off mid-flash: take back what is still attached, or it
			// rides the player forever with nothing left to remove it.
			for (int i = 0; i < mlights.Size(); i++)
				if (mlights[i]) { mlights[i].A_RemoveLight("gitd_muzzle"); mlights[i].Destroy(); }
			mlights.Clear();
			wasFlashing.Clear();
			return;
		}

		int rad  = CI("gitd_muzzle_size", 96);
		int life = CI("gitd_muzzle_life", 3);
		Color c  = MuzzleColor();
		bool wantStrobe = CB("gitd_muzzle_chaingun_strobe", true);

		while (wasFlashing.Size() < MAXPLAYERS) wasFlashing.Push(0);

		for (int pn = 0; pn < MAXPLAYERS; pn++)
		{
			if (!playeringame[pn]) continue;
			let p = players[pn];
			if (!p.mo || p.mo.health <= 0) continue;

			// THE BANG, not the trigger. Both hands set their flash on the
			// same PSP_FLASH layer, so one check covers main and offhand.
			int flashing = (p.FindPSprite(PSP_FLASH) != null) ? 1 : 0;
			bool newShot = (flashing == 1 && wasFlashing[pn] == 0);
			wasFlashing[pn] = flashing;

			// Only the player's OWN weapons can strobe. An enemy chaingunner
			// is a world actor and is never ReadyWeapon or OffhandWeapon, so
			// it cannot reach this.
			bool chaingunInHand =
				(p.ReadyWeapon   && (p.ReadyWeapon   is "Chaingun")) ||
				(p.OffhandWeapon && (p.OffhandWeapon is "Chaingun"));

			bool chaingunFiring = wantStrobe && chaingunInHand
				&& (p.refire > 0 || flashing == 1);

			bool keepAlive = newShot || chaingunFiring;

			GITD_MuzzleLight existing = null;
			for (int i = 0; i < mlights.Size(); i++)
				if (mlights[i] && mlights[i].host == p.mo) { existing = mlights[i]; break; }

			if (existing)
			{
				existing.SetStrobe(chaingunFiring);
				if (keepAlive) existing.Flash(c, rad, life);
				continue;
			}

			if (!keepAlive) continue;

			let nl = GITD_MuzzleLight(Actor.Spawn("GITD_MuzzleLight",
				p.mo.pos + (0, 0, p.mo.height * 0.6)));
			if (nl)
			{
				nl.host = p.mo;
				nl.SetStrobe(chaingunFiring);
				nl.Flash(c, rad, life);
				mlights.Push(nl);
			}
		}
	}
}
