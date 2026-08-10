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
// MONSTERS have no such layer, so they are polled: a monster that was not in
// its Missile state last tic and is now has just started an attack. That is
// one flash per attack rather than one per frame of the animation, which is
// what you want, and it works for hitscan and projectile monsters alike
// without knowing anything about either.
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
		wasFiring.Clear();
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

	void DoMonsters()
	{
		int radius = CvI("gitd_mf_mon_radius", 96);
		int life = CvI("gitd_mf_life", 1);
		Color col = CvC("gitd_mf_mon_color", 0xFFB464);

		Array<Actor> nowFiring;

		ThinkerIterator it = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bISMONSTER || a.health <= 0) continue;
			if (!a.MissileState) continue;
			if (!a.InStateSequence(a.CurState, a.MissileState)) continue;

			nowFiring.Push(a);

			// Only the tic it STARTS on. Mid-animation is not a new shot.
			bool already = false;
			for (int i = 0; i < wasFiring.Size(); i++)
			{
				if (wasFiring[i] == a) { already = true; break; }
			}
			if (already) continue;

			double z = a.pos.z + a.height * 0.7;
			Vector2 fwd = (cos(a.angle), sin(a.angle)) * (a.radius + 6.0);
			GITD_MuzzleLight.Fire((a.pos.x + fwd.x, a.pos.y + fwd.y, z),
				col, radius, life);
		}

		// Destroyed actors read back as null, so the copy drops them for free.
		wasFiring.Copy(nowFiring);
	}
}
