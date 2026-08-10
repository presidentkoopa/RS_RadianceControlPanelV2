// ===========================================================================
// Muzzle flash -- a real light on whatever just fired.
//
// WHY IT EXISTS. Vanilla has no muzzle light. It has player.extralight, which
// lifts the brightness of the whole VIEW while a weapon is in its flash state
// -- a screen-wide flicker that casts nothing and is ruinous in a mod this
// dark, which is why gitd_dd_noflash kills it. Killing it left a hole: firing
// a shotgun in a black room should light the black room.
//
// ---------------------------------------------------------------------------
// THIS IS A REWRITE OF TWO WORKING PROTOTYPES, and three things in them were
// better than what was here first, so they are kept:
//
//   A_AttachLight, not a spawned light actor. The light rides its host for
//   free -- no positioning, no drift, no cleanup actor.
//
//   THE VR CRASH. The prototype's own comment records that spawning an actor
//   mid-ThinkerIterator re-enters the thinker/psprite system and crashes
//   VanillaVRPlus offhand weapons when a shotgunner fires while you are
//   holding the trigger. It solved that by deferring spawns until after the
//   loop. This file spawns NOTHING AT ALL, so the crash has no way back in.
//
//   OffhandWeapon. VR has two hands and both of them can fire.
//
// AND TWO THINGS ARE DONE DIFFERENTLY, both at the points the prototypes
// themselves called weak.
//
//   FULL AUTO. The prototype matched the chaingun BY CLASS and forced an
//   every-other-tic on/off strobe. That breaks on any weapon mod whose autos
//   are not named Chaingun, and the rate is invented rather than the gun's.
//
//   The real signal was already there. A_GunFlash sets the PSP_FLASH layer to
//   the FIRST state of the weapon's flash sequence on every shot -- so during
//   full auto the layer never drops, but its state keeps RESTARTING, and each
//   restart is one bullet. Watching for that gives a pulse per shot at the
//   weapon's own cadence, with no weapon table and no invented rhythm.
//
//   MONSTER FIRING FRAMES. The prototype carried a hand-verified table --
//   POSS F, SPOS F, TROO G, SKEL K -- and skipped anything not in it, so
//   modded monsters never flashed at all. But every frame in that table is a
//   frame the artist marked FULLBRIGHT, because that is how a muzzle flash
//   painted into a sprite is made to stop being shaded. Reading bFullbright
//   gets the same answer for all thirteen vanilla monsters with no table, and
//   gets a right answer for mods as well. The prototype's table is what
//   confirmed the flag lines up.
// ===========================================================================

class GITD_MuzzleFlashHandler : EventHandler
{
	// Everything currently lit. Parallel arrays rather than a carrier actor
	// each, because the light is attached to its host and the only thing that
	// needs remembering is when to take it away again.
	private Array<Actor> lit;
	private Array<int> litEnd;      // maptime it expires
	private Array<int> litRad;      // radius it started at, for the falloff
	private Array<int> litCol;      // packed rgb

	// Per player: the flash state seen last tic, for detecting a restart.
	private Array<State> lastFlashState;
	private Array<int> lastShotTic;

	// Monsters showing a fullbright attack frame last tic, so a frame lasting
	// four tics lights the room once rather than four times.
	private Array<Actor> wasBright;

	// Per CLASS: does its Missile sequence contain a fullbright frame at all?
	// That is a property of the actor definition and cannot change, so it is
	// answered once and kept -- walking a state chain per monster per tic
	// would be absurd.
	private Array<Class<Actor> > brightCls;
	private Array<bool> brightHas;

	private int shotCount;          // drives the colour rotation

	const LIGHTID = "gitd_muzzle";

	static bool CvB(string n, bool d) { let c = CVar.FindCVar(n); return c ? c.GetBool() : d; }
	static int  CvI(string n, int d)  { let c = CVar.FindCVar(n); return c ? c.GetInt()  : d; }
	static double CvF(string n, double d) { let c = CVar.FindCVar(n); return c ? c.GetFloat() : d; }

	override void WorldLoaded(WorldEvent e)
	{
		lit.Clear(); litEnd.Clear(); litRad.Clear(); litCol.Clear();
		wasBright.Clear(); brightCls.Clear(); brightHas.Clear();
		lastFlashState.Clear(); lastShotTic.Clear();
		for (int i = 0; i < MAXPLAYERS; i++)
		{
			lastFlashState.Push(null);
			lastShotTic.Push(-1000);
		}
		shotCount = 0;
	}

	// ---- colour ----------------------------------------------------------
	//
	// Four slots that rotate per shot, or one picked at random. Brightness
	// scales the CHANNELS rather than the radius: reach and strength are two
	// different questions, the menu asks them separately, and answering both
	// with radius would make one of the two sliders a lie.

	Color PlayerColor()
	{
		int slot;
		if (CvB("gitd_mf_random", false)) slot = random(1, 4);
		else slot = (shotCount % 4) + 1;

		return Scale(CvI("gitd_mf_c" .. slot, 0xFFDC96), CvF("gitd_mf_bright", 1.0));
	}

	Color MonsterColor()
	{
		return Scale(CvI("gitd_mf_mon_color", 0xFFB464),
		             CvF("gitd_mf_mon_bright", 1.0));
	}

	static Color Scale(int packed, double b)
	{
		b = clamp(b, 0.05, 3.0);
		return Color(255,
			clamp(int(((packed >> 16) & 255) * b), 0, 255),
			clamp(int(((packed >> 8) & 255) * b), 0, 255),
			clamp(int((packed & 255) * b), 0, 255));
	}

	// ---- the light -------------------------------------------------------

	void Light(Actor host, Color c, int radius, int tics)
	{
		if (!host) return;

		// Already lit? RE-ARM rather than stack. Full auto re-arms on every
		// shot and must not accumulate lights on one actor.
		for (int i = 0; i < lit.Size(); i++)
		{
			if (lit[i] != host) continue;
			litEnd[i] = level.maptime + max(tics, 1);
			litRad[i] = radius;
			litCol[i] = (c.r << 16) | (c.g << 8) | c.b;
			return;
		}
		lit.Push(host);
		litEnd.Push(level.maptime + max(tics, 1));
		litRad.Push(radius);
		litCol.Push((c.r << 16) | (c.g << 8) | c.b);
	}

	// Re-attach each tic with a shrinking radius, and take it away at the end.
	// A light that outlives its shot is the whole failure this avoids.
	void StepLights()
	{
		int life = max(CvI("gitd_mf_life", 4), 1);
		for (int i = lit.Size() - 1; i >= 0; i--)
		{
			let a = lit[i];
			if (!a)
			{
				lit.Delete(i); litEnd.Delete(i); litRad.Delete(i); litCol.Delete(i);
				continue;
			}
			int left = litEnd[i] - level.maptime;
			if (left <= 0)
			{
				a.A_RemoveLight(LIGHTID);
				lit.Delete(i); litEnd.Delete(i); litRad.Delete(i); litCol.Delete(i);
				continue;
			}
			double fade = clamp(double(left) / double(life), 0.0, 1.0);
			int r = max(int(litRad[i] * fade), 1);
			int p = litCol[i];
			// Flag 8 is LF_ATTENUATE: realistic falloff, so it LIGHTS the wall
			// texture rather than flatly washing it out.
			a.A_AttachLight(LIGHTID, 0,
				Color(255, (p >> 16) & 255, (p >> 8) & 255, p & 255),
				r, 0, 8);
		}
	}

	override void WorldTick()
	{
		if (!CvB("gitd_mf_enabled", true))
		{
			// Switched off mid-flash: take back whatever is still attached,
			// or it hangs on the actor forever.
			for (int i = lit.Size() - 1; i >= 0; i--)
				if (lit[i]) lit[i].A_RemoveLight(LIGHTID);
			lit.Clear(); litEnd.Clear(); litRad.Clear(); litCol.Clear();
			return;
		}

		if (CvB("gitd_mf_player", true)) DoPlayers();
		if (CvB("gitd_mf_monsters", true)) DoMonsters();
		StepLights();
	}

	// ---- the player ------------------------------------------------------

	void DoPlayers()
	{
		int radius = CvI("gitd_mf_radius", 160);
		int life = CvI("gitd_mf_life", 4);
		int cool = max(CvI("gitd_mf_cooldown", 1), 1);

		while (lastFlashState.Size() < MAXPLAYERS) lastFlashState.Push(null);
		while (lastShotTic.Size() < MAXPLAYERS) lastShotTic.Push(-1000);

		for (int pn = 0; pn < MAXPLAYERS; pn++)
		{
			if (!playeringame[pn]) continue;
			let p = players[pn];
			if (!p.mo || p.mo.health <= 0) continue;

			let psp = p.FindPSprite(PSprite.PSP_FLASH);
			State now = psp ? psp.CurState : null;
			State was = lastFlashState[pn];
			lastFlashState[pn] = now;

			if (!now) continue;

			// A NEW SHOT is the flash chain STARTING: either the layer was not
			// there a tic ago, or it was and its state has jumped back to the
			// sequence's first frame -- which is exactly what A_GunFlash does
			// on every trigger pull, including the fortieth of a held burst.
			// No weapon has to be named for this to work.
			bool restarted = (was == null) || (now != was && IsFlashEntry(p, now));
			if (!restarted) continue;

			// A floor on the rate, for anything that re-flashes faster than
			// the eye resolves. Defaults to 1 -- every shot -- because with
			// restart detection the light already follows the gun's own
			// cadence and needs no throttling to look right.
			if (level.maptime - lastShotTic[pn] < cool) continue;
			lastShotTic[pn] = level.maptime;

			shotCount++;
			Light(p.mo, PlayerColor(), radius, life);
		}
	}

	// Is this state the first frame of either held weapon's flash sequence?
	// Both hands, because VR fires from either and the engine puts both on
	// the same PSP_FLASH layer.
	static bool IsFlashEntry(PlayerInfo p, State s)
	{
		if (p.ReadyWeapon)
		{
			let f = p.ReadyWeapon.FindState('Flash');
			if (f && s == f) return true;
			let af = p.ReadyWeapon.FindState('AltFlash');
			if (af && s == af) return true;
		}
		if (p.OffhandWeapon)
		{
			let f = p.OffhandWeapon.FindState('Flash');
			if (f && s == f) return true;
			let af = p.OffhandWeapon.FindState('AltFlash');
			if (af && s == af) return true;
		}
		return false;
	}

	// ---- everything else -------------------------------------------------

	void DoMonsters()
	{
		int radius = CvI("gitd_mf_mon_radius", 120);
		int life = CvI("gitd_mf_life", 4);
		Color col = MonsterColor();
		bool useBright = CvB("gitd_mf_bright_frame", true);

		Array<Actor> nowBright;

		// NOTHING IS SPAWNED IN HERE, and that is deliberate: the prototype
		// this replaces documented a crash from spawning mid-iteration with VR
		// offhand weapons. Attaching to the host sidesteps it entirely.
		ThinkerIterator it = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bISMONSTER || a.health <= 0) continue;
			if (!a.MissileState || !a.CurState) continue;
			if (!Actor.InStateSequence(a.CurState, a.MissileState)) continue;

			bool bright = a.CurState.bFullbright;
			if (bright) nowBright.Push(a);

			bool fire;
			if (useBright && bright)
			{
				// Entry to the flash frame, not presence in it.
				fire = (wasBright.Find(a) == wasBright.Size());
			}
			else if (useBright && SequenceHasBright(a))
			{
				fire = false;    // it does mark a frame; wait for the marked one
			}
			else
			{
				// Marks nothing anywhere: fall back to the start of the
				// attack. Early by a few tics, but present rather than absent.
				fire = (a.CurState == a.MissileState);
			}

			if (fire) Light(a, col, radius, life);
		}
		wasBright.Copy(nowBright);
	}

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


// The "set all four back to default" button on the menu page.
class GITD_MuzzleResetColors : EventHandler
{
	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.name != "gitd_mf_defaults") return;
		for (int i = 1; i <= 4; i++)
		{
			let c = CVar.FindCVar("gitd_mf_c" .. i);
			if (c) c.ResetToDefault();
		}
		Console.Printf("\c[Gold]Muzzle flash colours reset to default.");
	}
}
