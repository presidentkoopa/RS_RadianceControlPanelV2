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

// ===========================================================================
// The monster half, and why it is not a frame table.
//
// The obvious way to light a firing monster is to watch for the sprite frame
// its muzzle flash is painted on. GITD 3.2 did exactly that, with a
// hand-verified table -- ZombieMan frame 5, DoomImp 6, Revenant 10 -- and it
// is correct on the vanilla roster and quietly wrong on any other.
//
// RS_Main is the proof. Its RS_CommonZombie really does inherit ZombieMan, so
// an "is ZombieMan" test passes -- but it animates on SGAR, where frame 5 is
// the WIND-UP, one frame before the shot. Other variants use CYNT and never
// match at all. The result is a flash that fires early on some monsters and
// never on others, silently, with the guard clause ("modded monsters are
// skipped") failing to catch it because these ARE vanilla subclasses. 143
// variants, each with its own frame layout. A table cannot survive that.
//
// So: two sources, in order of how much they actually know.
//
// 1. RS_MonsterFiredMarker, when RS_Main is loaded. A one-tic inert actor
//    spawned at the MUZZLE at the moment the round leaves, carrying the
//    shooter as its target. Not a guess at where the barrel is -- the point
//    the projectile physically departed from. RS collapses volleys to one
//    marker, so a mancubus throwing three does not strobe.
//
//    Consumed BY STRING so there is no hard dependency: with RS_Main absent
//    the class lookup returns null and the branch never runs.
//
// 2. Otherwise, the fullbright frame of the monster's own Missile sequence.
//    A muzzle flash painted into a sprite is exactly the frame an artist
//    marks fullbright -- that is what the flag is FOR -- so reading it gets
//    all thirteen vanilla monsters with no table and gets a right answer on
//    mods too. Coarser than the marker, and it is the fallback for a reason.
//
// The moment a marker is seen, the fallback shuts off for the rest of the
// map. Both running would double-flash every monster RS converts.
// ===========================================================================
class GITD_MonsterFlash : Actor
{
	Actor host;
	Color mcol;
	int   mrad, mlife, mage;
	Vector3 anchor;     // used when there is no host to ride
	bool  pinned;

	Default { +NOINTERACTION; +NOGRAVITY; +NOBLOCKMAP; +DONTSPLASH; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	void Arm(Color c, int rad, int life)
	{
		mcol = c; mrad = rad; mlife = max(1, life); mage = 0;
	}

	override void Tick()
	{
		Super.Tick();

		// PINNED lights stay where the round left. A marker gives a real
		// muzzle position, and a muzzle does not follow the monster around
		// for the four tics the flash lasts -- the flash happened THERE.
		if (!pinned)
		{
			if (!host || host.health <= 0) { A_RemoveLight("gitd_mmflash"); Destroy(); return; }
			SetOrigin(host.pos + (0, 0, host.height * 0.6), true);
		}

		mage++;
		if (mage > mlife) { A_RemoveLight("gitd_mmflash"); Destroy(); return; }

		double fade = 1.0 - double(mage) / double(mlife + 1);
		fade = clamp(fade, 0.0, 1.0);

		// A little flicker so it reads as a flare rather than a lamp on a
		// timer. Seeded off position so two monsters firing together are not
		// in lockstep.
		int t = level.maptime + int(pos.x) + int(pos.y);
		double n = double((t * 1103515245 + 12345) & 0x7fffffff) / double(0x7fffffff);
		fade *= 0.70 + 0.30 * n;

		int finalRad = max(1, int(double(mrad) * fade));
		A_AttachLight("gitd_mmflash", 0, mcol, finalRad, 0, 8);   // 8 = attenuate
	}
}

class GITD_MonsterFlashHandler : EventHandler
{
	private Array<GITD_MonsterFlash> live;
	private Array<Actor> wasBright;
	private bool sawMarker;      // RS_Main is feeding us; stop guessing

	static int  CI(string n, int def)  { let c = CVar.FindCVar(n); return c ? c.GetInt()  : def; }
	static bool CB(string n, bool def) { let c = CVar.FindCVar(n); return c ? c.GetBool() : def; }

	override void WorldLoaded(WorldEvent e)
	{
		live.Clear(); wasBright.Clear(); sawMarker = false;
	}

	// WHICH MONSTERS GET A FLASH.
	//
	// Scope 0 is everything that fires. Scope 1 -- the default -- is the
	// common rank only: the rank-and-file shooters you meet in every room,
	// not elites and not bosses.
	//
	// AND IT IS DELIBERATELY NOT BOUND TO A MOD'S TIER TAG. The obvious
	// implementation is to ask a gameplay mod what rank a monster is, and it
	// would be wrong here: that roster is being replaced, so a class list or a
	// tier field written against today's monsters is a list of names that will
	// not exist. Vanilla inheritance survives a roster swap -- a replacement
	// zombieman is still a ZombieMan -- so the test is written against the
	// four vanilla families every common shooter descends from, whoever
	// happens to be standing in for them.
	//
	// The cap in Light() is the other half of this: scope keeps the flashes
	// meaningful, the cap keeps a crowd from becoming a strobe.
	static bool InScope(Actor mo, int scope)
	{
		if (!mo) return false;
		if (scope <= 0) return true;

		return mo is "ZombieMan"
			|| mo is "ShotgunGuy"
			|| mo is "ChaingunGuy"
			|| mo is "DoomImp"
			|| mo is "WolfensteinSS";
	}

	Color FlashColor(Actor mo)
	{
		if (CB("gitd_mmf_custom", false))
		{
			let cc = CVar.FindCVar("gitd_mmf_color");
			if (cc)
			{
				int pk = cc.GetInt();
				return Color(255, (pk >> 16) & 255, (pk >> 8) & 255, pk & 255);
			}
		}
		if (!mo) return Color(255, 255, 200, 110);
		// Per-family, so a plasma volley does not look like buckshot.
		if (mo is "Arachnotron")                    return Color(255, 120, 170, 255);
		if (mo is "DoomImp" || mo is "BaronOfHell") return Color(255, 140, 220, 130);
		if (mo is "Cacodemon" || mo is "Revenant")  return Color(255, 180, 210, 255);
		if (mo is "Fatso")                          return Color(255, 255, 150,  70);
		return Color(255, 255, 200, 110);           // warm gunfire
	}

	void Light(Actor host, Vector3 at, bool pin)
	{
		int cap = CI("gitd_mmf_max", 12);
		for (int i = live.Size() - 1; i >= 0; i--) if (!live[i]) live.Delete(i);
		if (live.Size() >= cap) return;

		int rad  = CI("gitd_mmf_size", 120);
		int life = CI("gitd_mmf_life", 4);

		let nl = GITD_MonsterFlash(Actor.Spawn("GITD_MonsterFlash", at));
		if (!nl) return;
		nl.host = host;
		nl.pinned = pin;
		nl.Arm(FlashColor(host), rad, life);
		live.Push(nl);
	}

	// SOURCE 1 -- RS_Main's marker. Looked up by string every time rather
	// than cached, because a cached null from a load where RS_Main was absent
	// would be wrong for the rest of the session.
	override void WorldThingSpawned(WorldEvent e)
	{
		if (!CB("gitd_mmf_lights", true)) return;
		if (!e.Thing) return;

		Class<Actor> mk = "RS_MonsterFiredMarker";
		if (!mk || !(e.Thing is mk)) return;

		sawMarker = true;
		let shooter = e.Thing.target;
		if (!shooter || !shooter.bISMONSTER) return;
		if (!InScope(shooter, CI("gitd_mmf_scope", 1))) return;

		// The marker IS the muzzle. Pin the light there rather than riding
		// the shooter -- the flash happened at that point in space.
		Light(shooter, e.Thing.pos, true);
	}

	// SOURCE 2 -- the fullbright frame, for when nothing better is feeding us.
	override void WorldTick()
	{
		for (int i = live.Size() - 1; i >= 0; i--) if (!live[i]) live.Delete(i);

		if (!CB("gitd_mmf_lights", true)) { wasBright.Clear(); return; }
		if (sawMarker) { wasBright.Clear(); return; }   // RS_Main has it covered

		Array<Actor> nowBright;
		Array<Actor> toFlash;
		int scope = CI("gitd_mmf_scope", 1);

		ThinkerIterator it = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bISMONSTER || a.health <= 0) continue;
			if (!InScope(a, scope)) continue;
			if (!a.MissileState || !a.CurState) continue;
			if (!Actor.InStateSequence(a.CurState, a.MissileState)) continue;
			if (!a.CurState.bFullbright) continue;

			nowBright.Push(a);
			// ENTRY to the frame, not presence in it -- otherwise a
			// three-tic flash frame fires three times.
			if (wasBright.Find(a) == wasBright.Size()) toFlash.Push(a);
		}

		// SPAWN AFTER THE ITERATION, NEVER INSIDE IT. Spawning an actor while
		// walking the thinker list re-enters the thinker and psprite system,
		// and with a VR offhand weapon mid-fire that crashes. The prototype
		// this descends from documented the same crash and the same fix.
		for (int i = 0; i < toFlash.Size(); i++)
		{
			let m = toFlash[i];
			if (m) Light(m, m.pos + (0, 0, m.height * 0.6), false);
		}

		wasBright.Copy(nowBright);
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
