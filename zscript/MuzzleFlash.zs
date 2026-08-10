// ===========================================================================
// Muzzle flash -- a real light, for one tic, whenever anything fires.
//
// WHY THIS EXISTS. Vanilla Doom has no muzzle light at all. What it has is
// player.extralight, which lifts the brightness of the WHOLE VIEW while a
// weapon is in its flash state -- a screen-wide flicker, not a light in the
// world. It casts nothing, illuminates nothing, and in a mod this dark it is
// actively ruinous, which is why gitd_dd_noflash exists to kill it.
//
// Killing it left a hole. Firing a shotgun in a black room should light the
// room. So this puts back what vanilla was gesturing at, properly: a point
// light at the muzzle, for a tic, that actually falls on the walls.
//
// HOW FIRING IS DETECTED, and it differs by who is shooting.
//
// The PLAYER is exact. GZDoom weapons call A_GunFlash, which puts a sprite on
// the PSP_FLASH layer -- that layer existing IS the muzzle flash, by
// definition, for any weapon mod that fires normally. No guessing at states
// and no per-weapon table.
//
// MONSTERS have no such layer, so the SPRITE is read instead -- because the
// artist already marked the answer. A vanilla monster's muzzle flash is drawn
// INTO one attack frame, and that frame is flagged fullbright so the engine
// stops shading it. POSS F, SPOS F, CPOS G: the flash is painted on and the
// brightness flag is how the artist said "this is the moment of firing". So
// the light goes on exactly that frame, for every vanilla monster and every
// mod following the same convention, with no per-monster table.
//
// Monsters that mark nothing fall back to the start of the Missile state --
// a few tics early, but never missing.
//
// SOUND WAS THE OTHER CANDIDATE and it is simply not available: GZDoom raises
// no script event when a sound plays, so there is nothing to hook. The frame
// is the better signal anyway. It is what the sprite is SHOWING, where a
// sound could as easily be a reload, a growl or a footstep.
//
// THE CHAINGUN PROBLEM. A fast weapon holds its flash layer up for most of
// its cycle, so "flash whenever the layer exists" is a light that never goes
// out -- which is not a muzzle flash, it is a lamp. The cooldown is the fix:
// a minimum gap between flashes, so a chaingun strobes at a readable rate
// instead of glowing continuously. It is a cvar because the right number
// depends on the weapon mod.
// ===========================================================================

class GITD_MuzzleLight : PointLight
{
	int life;

	Default
	{
		//$Title Muzzle flash light
		Args 255, 220, 150, 96;
		+DYNAMICLIGHT.ATTENUATE;
	}

	// Spawn one, configured, at a point. Returns nothing -- it manages its
	// own death, because a light that outlives its shot is the whole failure
	// mode this is trying to avoid.
	static void Fire(Vector3 at, Color c, int radius, int tics)
	{
		let l = GITD_MuzzleLight(Actor.Spawn("GITD_MuzzleLight", at, NO_REPLACE));
		if (!l) return;
		l.args[0] = c.r;
		l.args[1] = c.g;
		l.args[2] = c.b;
		l.args[3] = radius;
		l.life = max(tics, 1);
	}

	override void Tick()
	{
		Super.Tick();
		if (--life <= 0) Destroy();
	}
}


class GITD_MuzzleFlashHandler : EventHandler
{
	// Per player, the tic its last flash fired on -- the cooldown's memory.
	int lastFlash[MAXPLAYERS];

	// Monsters that were mid-attack last tic. Diffed each tic to find the
	// ones that have just STARTED, which is the only moment worth lighting.
	Array<Actor> wasFiring;

	// Monsters showing a fullbright attack frame last tic, so a four-tic
	// flash frame lights the room once rather than four times.
	Array<Actor> wasBright;
	Array<Actor> nowBright;

	// Per CLASS: does its Missile sequence contain a fullbright frame at all?
	// A property of the actor definition, so it is answered once and kept.
	Array<Class<Actor> > brightCls;
	Array<bool> brightHas;

	static bool CvB(string n, bool d) { let c = CVar.FindCVar(n); return c ? c.GetBool() : d; }
	static int  CvI(string n, int d)  { let c = CVar.FindCVar(n); return c ? c.GetInt()  : d; }

	static Color CvC(string n, int d)
	{
		let c = CVar.FindCVar(n);
		int p = c ? c.GetInt() : d;
		return Color(255, (p >> 16) & 255, (p >> 8) & 255, p & 255);
	}

	override void WorldLoaded(WorldEvent e)
	{
		for (int i = 0; i < MAXPLAYERS; i++) lastFlash[i] = -1000;
		wasFiring.Clear(); wasBright.Clear(); nowBright.Clear();
		brightCls.Clear(); brightHas.Clear();
	}

	override void WorldTick()
	{
		if (!CvB("gitd_mf_enabled", true)) return;
		if (CvB("gitd_mf_player", true)) DoPlayers();
		if (CvB("gitd_mf_monsters", true)) DoMonsters();
	}

	// ---- the player ------------------------------------------------------

	void DoPlayers()
	{
		int cool = max(CvI("gitd_mf_cooldown", 3), 1);
		int radius = CvI("gitd_mf_radius", 128);
		int life = CvI("gitd_mf_life", 1);
		Color col = CvC("gitd_mf_color", 0xFFDC96);

		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playeringame[i]) continue;
			let pmo = players[i].mo;
			if (!pmo || pmo.health <= 0) continue;

			// The flash LAYER existing is the muzzle flash. Nothing else has
			// to be known about the weapon.
			if (!players[i].FindPSprite(PSprite.PSP_FLASH)) continue;
			if (level.maptime - lastFlash[i] < cool) continue;
			lastFlash[i] = level.maptime;

			// At the muzzle rather than at the feet: eye height, a little
			// below the view, pushed forward past the body so the light does
			// not sit inside the player and light nothing.
			double z = pmo.pos.z + pmo.player.viewheight - 6.0;
			Vector2 fwd = (cos(pmo.angle), sin(pmo.angle)) * (pmo.radius + 8.0);
			GITD_MuzzleLight.Fire((pmo.pos.x + fwd.x, pmo.pos.y + fwd.y, z),
				col, radius, life);
		}
	}

	// ---- everything else -------------------------------------------------

	// THE ARTIST ALREADY MARKED THE RIGHT FRAME.
	//
	// A vanilla monster's muzzle flash is not a separate effect -- it is drawn
	// INTO the attack sprite, on one specific frame, and that frame is marked
	// fullbright so the engine stops shading it. POSS F, SPOS F, CPOS G: the
	// flash is painted on and the brightness flag is how the artist said "this
	// is the moment of firing".
	//
	// So that flag is the detector. Not the start of the Missile state, which
	// is the wind-up and lands several tics early -- a zombieman raises its
	// rifle on POSS E and fires on POSS F, and lighting the room on E is
	// lighting it before the shot. Reading bFullbright inside the Missile
	// sequence puts the light on exactly the frame the sprite shows a flash,
	// for every vanilla monster and every mod that follows the same
	// convention, with no per-monster table anywhere.
	//
	// FALLBACK, because not every mod marks its frames. If a monster runs a
	// whole Missile sequence without one fullbright frame, the start of the
	// sequence is used instead -- early, but present. Which of the two fired
	// is remembered per monster so it cannot do both for one attack.
	//
	// SOUND WAS THE OTHER IDEA and it is not available: GZDoom raises no
	// script event when a sound plays, so there is nothing to hook. The
	// fullbright frame is the better signal anyway -- it is what the sprite
	// is actually SHOWING, where a sound could be a reload or a growl.
	void DoMonsters()
	{
		int radius = CvI("gitd_mf_mon_radius", 96);
		int life = CvI("gitd_mf_life", 1);
		Color col = CvC("gitd_mf_mon_color", 0xFFB464);
		bool useBright = CvB("gitd_mf_bright", true);

		Array<Actor> nowFiring;

		ThinkerIterator it = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bISMONSTER || a.health <= 0) continue;
			if (!a.MissileState || !a.CurState) continue;
			if (!Actor.InStateSequence(a.CurState, a.MissileState)) continue;

			nowFiring.Push(a);

			bool started = true;
			for (int i = 0; i < wasFiring.Size(); i++)
			{
				if (wasFiring[i] == a) { started = false; break; }
			}

			bool fire;
			if (useBright && a.CurState.bFullbright)
			{
				// The flash frame itself. Fire on the tic it is ENTERED --
				// a frame lasting four tics must not light four times.
				fire = !WasBright(a);
			}
			else if (useBright && SequenceHasBright(a))
			{
				// This monster does mark its frames; wait for the marked one.
				fire = false;
			}
			else
			{
				// No marked frame anywhere in the sequence: fall back to the
				// start of the attack.
				fire = started;
			}

			if (fire)
			{
				double z = a.pos.z + a.height * 0.7;
				Vector2 fwd = (cos(a.angle), sin(a.angle)) * (a.radius + 6.0);
				GITD_MuzzleLight.Fire((a.pos.x + fwd.x, a.pos.y + fwd.y, z),
					col, radius, life);
			}

			if (a.CurState.bFullbright) nowBright.Push(a);
		}

		// Destroyed actors read back as null, so the copy drops them for free.
		wasFiring.Copy(nowFiring);
		wasBright.Copy(nowBright);
		nowBright.Clear();
	}

	bool WasBright(Actor a)
	{
		for (int i = 0; i < wasBright.Size(); i++)
			if (wasBright[i] == a) return true;
		return false;
	}

	// Does this monster's attack contain a fullbright frame at all? Walked
	// once and remembered per CLASS, because it is a property of the actor
	// definition and never changes -- walking a state chain per monster per
	// tic would be absurd.
	bool SequenceHasBright(Actor a)
	{
		class<Actor> cls = a.GetClass();
		for (int i = 0; i < brightCls.Size(); i++)
			if (brightCls[i] == cls) return brightHas[i];

		bool found = false;
		State s = a.MissileState;
		for (int n = 0; s && n < 64; n++)
		{
			if (s.bFullbright) { found = true; break; }
			if (!s.NextState || !s.NextState.InStateSequence(a.MissileState)) break;
			s = s.NextState;
		}
		brightCls.Push(cls);
		brightHas.Push(found);
		return found;
	}
}
