// ===========================================================================
// Sector Sweep: the extension points.
//
// The sweep started as "a travelling band that brightens rooms". That framing
// was too small. What it actually computes, every tic, is:
//
//     for every sector -- and now every monster -- how close is it to which
//     band, and how strongly
//
// That is a general spatial query with a wavefront attached, and brightening
// is only one thing you can hang off it. This file is the part that lets
// anything else hang off it too: recolouring, marking, alerting, re-tiering
// an enemy, whatever a mod invents later. GlowHandler.zs owns the geometry
// and the timing; this owns what happens when the band arrives.
//
// Three ways in, in increasing order of power:
//
//   1. Per-band effect cvars (gitd_ss_fx1..8) -- pick from the built-in list
//      in the menu. Band 1 darkens, band 2 brightens, band 3 darkens: the
//      room breathes as the train passes.
//   2. GITD_Sweep.Fire(...) -- any actor can throw a sweep from its own
//      position, once, with its own colour and speed. An elite calls a wave.
//   3. GITD_SweepEffect -- subclass it, register it, and you get called for
//      every sector and every monster a band touches, with the band index and
//      the strength. This is the one with no ceiling.
//
// ===========================================================================

// ---------------------------------------------------------------------------
// The hook.
//
// Subclass, override what you care about, and register an instance:
//
//     class RS_EliteRetier : GITD_SweepEffect
//     {
//         override void ActorPass(Actor a, int band, double strength)
//         {
//             if (band == 0 && strength > 0.6) RS_Tier.Promote(a);
//         }
//     }
//     // from any handler's WorldLoaded:
//     GITD_Sweep.Register(new("RS_EliteRetier"));
//
// Registration lasts for the map. Register again in WorldLoaded and the list
// is rebuilt each time, which is deliberate -- an effect holding pointers into
// a level that no longer exists is the classic way to crash on map change.
// ---------------------------------------------------------------------------
class GITD_SweepEffect : Object play abstract
{
	// Called once per tic before any Pass, so an effect can reset accumulators.
	virtual void BeginPass() {}

	// A band is over this sector. strength is 1.0 at the band's centre and
	// falls to 0 at its edge. idx is the sector's index, which is stable and
	// cheap to use as an array key.
	virtual void SectorPass(Sector sec, int idx, int band, double strength) {}

	// No band is near this sector any more. Put back whatever you changed --
	// nothing else will do it for you, and a sweep that leaves a trail of
	// permanently altered sectors reads as the level corrupting.
	virtual void SectorRest(Sector sec, int idx) {}

	// A band is over this monster. Only called when the actor pass is on,
	// because walking the thinker list every tic is not free.
	virtual void ActorPass(Actor a, int band, double strength) {}

	// Return true to make the handler do the actor walk at all.
	virtual bool WantsActors() { return false; }
}


// ---------------------------------------------------------------------------
// A mark left on a monster a band has touched.
//
// Deliberately dumb: it records which band and how hard, and expires. It exists
// so that a mod which does NOT want to write a GITD_SweepEffect can still ask
// "has the sweep hit this thing recently, and with which band" from anywhere --
// a damage function, a spawn check, a tier system.
// ---------------------------------------------------------------------------
class GITD_SweepMark : Inventory
{
	int band;
	double strength;
	int stamp;

	Default
	{
		Inventory.MaxAmount 1;
		+INVENTORY.UNDROPPABLE;
		+INVENTORY.UNTOSSABLE;
		+INVENTORY.QUIET;
	}

	// How many tics ago the mark was set, or -1 if there is no mark.
	static int Age(Actor a)
	{
		if (!a) return -1;
		let m = GITD_SweepMark(a.FindInventory("GITD_SweepMark"));
		if (!m) return -1;
		return level.maptime - m.stamp;
	}

	static int BandOf(Actor a)
	{
		if (!a) return -1;
		let m = GITD_SweepMark(a.FindInventory("GITD_SweepMark"));
		return m ? m.band : -1;
	}

	static void Set(Actor a, int band, double strength)
	{
		if (!a) return;
		let m = GITD_SweepMark(a.FindInventory("GITD_SweepMark"));
		if (!m)
		{
			a.GiveInventory("GITD_SweepMark", 1);
			m = GITD_SweepMark(a.FindInventory("GITD_SweepMark"));
			if (!m) return;
		}
		// Strongest hit in a pass wins, so a band's centre beats its edge
		// rather than whichever happened to be evaluated last.
		if (level.maptime - m.stamp > 4 || strength > m.strength)
		{
			m.band = band;
			m.strength = strength;
		}
		m.stamp = level.maptime;
	}
}


// ---------------------------------------------------------------------------
// The public face. Everything a mod should need to touch is a static here.
// ---------------------------------------------------------------------------
class GITD_Sweep play abstract
{
	// Built-in per-band effects. These are what gitd_ss_fx1..8 select from,
	// and the numbers are the menu's -- do not renumber without MENUDEF.
	enum EFx
	{
		FX_NONE      = 0,
		FX_BRIGHTEN  = 1,
		FX_DARKEN    = 2,
		FX_RECOLOR   = 3,
		FX_SONAR     = 4,   // reveal, then fade back to dark behind the band
		FX_ALERT     = 5,   // wake the monsters it passes over
		FX_MARK      = 6,   // leave a GITD_SweepMark, change nothing else
		FX_SLOW      = 7,   // briefly halve the speed of what it touches
	}

	enum EShape
	{
		SHAPE_RING   = 1,
		SHAPE_EW     = 2,
		SHAPE_NS     = 3,
		SHAPE_SHELL  = 4,
		SHAPE_RISING = 5,   // climbs vertically -- needs the engine build with
		                    // smode 5 in main.fp
	}

	private static GITD_Handler Handler()
	{
		return GITD_Handler(StaticEventHandler.Find("GITD_Handler"));
	}

	// --- Scripted one-shot ---------------------------------------------
	//
	// Throw a single wave from a point and let it die on its own. This
	// OVERRIDES the cvar-driven sweep for as long as it runs, then hands
	// back -- so an elite's shockwave interrupts the ambient sweep rather
	// than fighting it for the same eight band slots.
	//
	//     GITD_Sweep.Fire(self.pos, GITD_Sweep.SHAPE_RING, 0xFF3020, 900, 1400);
	//
	static void Fire(Vector3 origin, int shape = 1, int col = 0x00DCFF,
		double speed = 600.0, double range = 1200.0, double thickness = 24.0,
		int bands = 1, double trail = 0.0, int fx = 1)
	{
		let h = Handler();
		if (!h) return;
		h.ssScripted     = true;
		h.ssScriptOrigin = origin;
		h.ssScriptShape  = shape;
		h.ssScriptColor  = Color(255, (col >> 16) & 255, (col >> 8) & 255, col & 255);
		h.ssScriptSpeed  = speed;
		h.ssScriptRange  = range;
		h.ssScriptThick  = thickness;
		h.ssScriptBands  = clamp(bands, 1, 8);
		h.ssScriptTrail  = trail;
		h.ssScriptFx     = fx;
		h.sweepPos       = 0;
		h.sweepDir       = 1;
	}

	// Convenience: fire from an actor, which is the common case.
	static void FireFrom(Actor a, int shape = 1, int col = 0x00DCFF,
		double speed = 600.0, double range = 1200.0, double thickness = 24.0,
		int bands = 1, double trail = 0.0, int fx = 1)
	{
		if (!a) return;
		Fire(a.pos, shape, col, speed, range, thickness, bands, trail, fx);
	}

	static void Cancel()
	{
		let h = Handler();
		if (h) h.ssScripted = false;
	}

	static bool IsScripted()
	{
		let h = Handler();
		return h ? h.ssScripted : false;
	}

	// --- Named band scripts ----------------------------------------------

	// Fire a wave that runs a named script as it travels.
	//
	//     GITD_Sweep.FireScript(self.pos, "RS_ArenaLockdown", 0xFF2000, 700, 2048);
	//
	static void FireScript(Vector3 origin, string actionName, int col = 0x00DCFF,
		double speed = 600.0, double range = 1200.0, int shape = 1,
		double thickness = 24.0, int bands = 1, double trail = 0.0)
	{
		let h = Handler();
		if (!h) return;
		let act = GITD_SweepAction.Resolve(actionName);
		if (!act) { Console.Printf("\c[Red]GITD sweep: no script class '%s'", actionName); return; }
		Fire(origin, shape, col, speed, range, thickness, bands, trail, 0);
		h.ssScriptAction = act;
		act.OnStart(h);
	}

	// --- Effect registry -------------------------------------------------

	static void Register(GITD_SweepEffect fx)
	{
		let h = Handler();
		if (!h || !fx) return;
		for (int i = 0; i < h.ssEffects.Size(); i++)
			if (h.ssEffects[i] == fx) return;
		h.ssEffects.Push(fx);
	}

	static void Unregister(GITD_SweepEffect fx)
	{
		let h = Handler();
		if (!h || !fx) return;
		for (int i = 0; i < h.ssEffects.Size(); i++)
		{
			if (h.ssEffects[i] == fx) { h.ssEffects.Delete(i); return; }
		}
	}

	// --- Queries ---------------------------------------------------------

	// Where the leading band is right now, in map units from the origin.
	static double Position()
	{
		let h = Handler();
		return h ? h.sweepPos : 0.0;
	}

	static Vector3 Origin()
	{
		let h = Handler();
		return h ? h.sweepOrigin : (0, 0, 0);
	}
}


// ===========================================================================
// Band scripts.
//
// A GITD_SweepEffect listens to everything. A GITD_SweepAction is the other
// shape: it is BOUND TO ONE BAND, by name, and only that band's arrivals reach
// it. That distinction is what makes a train of eight useful as a program
// rather than as decoration --
//
//     band 1  ->  "Blackout"       kills the lights
//     band 2  ->  "ArenaSpawn"     fills the dark with things
//     band 3  ->  "TierUp"         promotes what it passes
//     band 4  ->  "Restore"        puts the level back
//
// -- four waves crossing a room in sequence, each running its own script,
// with the spacing between them under your control in tics. The wavefront is
// the clock and the cursor at the same time.
//
// Bind from the menu (gitd_ss_script1..8) or from code:
//
//     GITD_Sweep.FireScript(boss.pos, "RS_ArenaLockdown", 0xFF2000, 700, 2048);
//
// ===========================================================================
class GITD_SweepAction : Object play abstract
{
	// Name -> instance, one instance per map. Instances are cached on the
	// handler because ZScript has no mutable statics, and rebuilt on every
	// map load so nothing holds a pointer into a level that is gone.
	static GITD_SweepAction Resolve(string name)
	{
		if (name == "" || name == "none") return null;
		let h = GITD_Handler(StaticEventHandler.Find("GITD_Handler"));
		if (!h) return null;

		for (int i = 0; i < h.ssActName.Size(); i++)
			if (h.ssActName[i] == name) return h.ssActObj[i];

		// A bad name is cached as null too, or a typo in a cvar means a failed
		// class lookup every tic for the rest of the map.
		class<GITD_SweepAction> cls = name;
		GITD_SweepAction obj = cls ? GITD_SweepAction(new(cls)) : null;
		h.ssActName.Push(name);
		h.ssActObj.Push(obj);
		if (!obj) Console.Printf("\c[Red]GITD sweep: '%s' is not a GITD_SweepAction", name);
		return obj;
	}

	// The wave carrying this script has been launched.
	virtual void OnStart(GITD_Handler h) {}

	// The wave has reached the end of its range and is about to be dropped.
	// A setpiece that means to stay put does nothing here; one that means to
	// clean up after itself reverts here.
	virtual void OnFinish(GITD_Handler h) {}

	// This band has arrived at a sector. strength is 1 at the band's centre.
	virtual void OnSector(GITD_Handler h, Sector sec, int idx, int band, double strength) {}

	// This band has arrived at a monster. Requires WantsActors.
	virtual void OnActor(GITD_Handler h, Actor a, int band, double strength) {}

	virtual bool WantsActors() { return false; }
}


// ===========================================================================
// A setpiece: a reversible transformation of the world, delivered by a
// wavefront and undone by another one.
//
// The hard part of "sweep in an arena, then sweep it back" is not the sweeping
// -- it is that a change you cannot undo is not a setpiece, it is damage. So
// this journals. Before a sector is altered it records what it was: light,
// colour, desaturation, both flats. Actors this spawned are remembered. Music
// is remembered. Revert walks that journal backwards.
//
// Subclass and override Transform(). Everything else is bookkeeping you do
// not have to think about:
//
//     class RS_BloodArena : GITD_Setpiece
//     {
//         override void Configure()
//         {
//             envColor   = "80 00 00";
//             envDesat   = 60;
//             music      = "D_E1M8";
//             spawnClass = "RS_ArenaImp";
//             spawnOdds  = 8;      // 1 sector in 8
//             tierBoost  = 1.5;    // health and speed of what it passes
//         }
//     }
//
//     // sweep it in
//     GITD_Sweep.FireScript(boss.pos, "RS_BloodArena", 0xFF2000, 700, 2048);
//     // ...later, sweep it back out
//     GITD_Setpiece.SweepOut("RS_BloodArena", boss.pos, 700, 2048);
//
// ===========================================================================
class GITD_Setpiece : GITD_SweepAction
{
	// --- what a subclass sets in Configure() ---
	Color  envColor;          // sector tint the wave paints on
	int    envDesat;          // and how much colour it drains
	int    envLight;          // light offset, applied on top of the tint
	string music;             // "" leaves the music alone
	string spawnClass;        // "" spawns nothing
	string envFloorTex;       // "" leaves the flats alone
	string envCeilTex;

	// A billboard payload stamped into every sector the wave passes -- the
	// same wgType machinery the kill badge uses, placed by the wavefront and
	// pulled by the return one. This is what makes a sweep able to draw a
	// setpiece into the world and then un-draw it.
	int    markPayload;       // GITD_Neon payload id; 0 = stamp nothing
	string markText;          // what the payload reads, if it reads anything
	double markSize;
	Color  markColor;
	bool   markOnFloor;       // flat on the ground, or standing up
	int    spawnOdds;         // spawn in 1 sector out of this many; 0 = never
	double tierBoost;         // 0 = leave monsters alone, 1.5 = half again
	bool   revertOnFinish;    // put it all back the moment the wave ends

	// --- journal ---
	// Only the index and the flats are journalled now. Light and colour used
	// to be recorded here too, but GITD_Composite snapshots the map's own
	// values at load and restores them the moment nothing declares otherwise,
	// so a second copy of the same record could only ever disagree with it.
	private Array<int> jIdx;
	// Sectors this setpiece is currently tinting. Re-declared every tic,
	// because the compositor forgets everything after each flush.
	private Array<int> tinted;
	// Flats are journalled BY NAME. TextureID is a struct with no way to
	// rebuild one from a stored index -- SetIndex is not callable on a local
	// -- and a name survives a texture list that changed underneath us.
	private Array<string> jFloor, jCeil;
	private Array<bool> jTouched;
	private Array<Actor> jSpawned;
	private Array<int> jBillboards;
	private string jMusic;
	private bool reverting, configured, started;

	virtual void Configure() {}

	private void EnsureConfigured()
	{
		if (configured) return;
		configured = true;
		envDesat = 0; envLight = 0; spawnOdds = 0; tierBoost = 0;
		revertOnFinish = false;
		markPayload = 0; markSize = 48.0; markOnFloor = true;
		envFloorTex = ""; envCeilTex = "";
		Configure();
	}

	override void OnStart(GITD_Handler h)
	{
		EnsureConfigured();
		if (reverting) return;

		// A second inbound sweep while one is already applied would journal
		// the ALTERED state as the original, and the level could never get
		// back. Refuse rather than corrupt.
		if (started) return;
		started = true;

		jMusic = level.Music;
		if (music != "") S_ChangeMusic(music);
	}

	override void OnFinish(GITD_Handler h)
	{
		if (reverting)
		{
			// The outbound wave has finished putting things back.
			reverting = false;
			started = false;
			jIdx.Clear(); jFloor.Clear(); jCeil.Clear();
			jTouched.Clear();
			tinted.Clear();
			DespawnAll();
			UnstampAll();
			if (music != "" && jMusic != "") S_ChangeMusic(jMusic);
		}
		else if (revertOnFinish)
		{
			RestoreEverything();
		}
	}

	override bool WantsActors() { return tierBoost > 0; }

	// Re-declare every tic. GITD_Composite deliberately forgets all
	// contributions after each flush -- that is what stops effects
	// accumulating -- so "still tinted" has to be said again every tic rather
	// than set once.
	void Republish()
	{
		if (envColor == 0) return;
		for (int i = 0; i < tinted.Size(); i++)
		{
			GITD_Composite.Tint(tinted[i], envColor);
			if (envDesat > 0) GITD_Composite.Desaturate(tinted[i], envDesat);
			if (envLight != 0) GITD_Composite.AddLight(tinted[i], envLight);
		}
	}

	override void OnSector(GITD_Handler h, Sector sec, int idx, int band, double strength)
	{
		EnsureConfigured();
		if (strength < 0.5) return;   // the band's core does the work, not its skirt

		if (reverting) { RestoreSector(sec, idx); return; }

		if (jTouched.Size() < level.Sectors.Size())
		{
			jTouched.Clear();
			for (int i = 0; i < level.Sectors.Size(); i++) jTouched.Push(false);
		}
		if (idx < jTouched.Size() && jTouched[idx]) return;
		if (idx < jTouched.Size()) jTouched[idx] = true;

		// Record before altering. This is the whole trick.
		jIdx.Push(idx);
		jFloor.Push(TexMan.GetName(sec.GetTexture(Sector.floor)));
		jCeil.Push(TexMan.GetName(sec.GetTexture(Sector.ceiling)));

		// Declared, not painted. See SectorComposite.zs -- calling SetColor
		// here is what made this look like it had never run.
		if (envColor != 0) tinted.Push(idx);
		if (envFloorTex != "")
			sec.SetTexture(Sector.floor, TexMan.CheckForTexture(envFloorTex, TexMan.Type_Flat));
		if (envCeilTex != "")
			sec.SetTexture(Sector.ceiling, TexMan.CheckForTexture(envCeilTex, TexMan.Type_Flat));

		if (spawnClass != "" && spawnOdds > 0 && (idx % spawnOdds) == 0)
			SpawnInSector(sec);

		if (markPayload != 0) StampSector(sec);
	}

	override void OnActor(GITD_Handler h, Actor a, int band, double strength)
	{
		EnsureConfigured();
		if (tierBoost <= 0 || strength < 0.5) return;
		if (reverting) return;

		// One promotion per monster. The mark is the record, so a monster the
		// wave clips twice does not end up with squared health.
		if (GITD_SweepMark.Age(a) >= 0 && GITD_SweepMark.BandOf(a) == band) return;
		GITD_SweepMark.Set(a, band, strength);

		a.A_SetHealth(int(a.health * tierBoost));
		a.Speed = a.default.Speed * tierBoost;
		a.SetShade(envColor != 0 ? envColor : Color(255, 255, 160, 160));
	}

	// --- the return trip ---------------------------------------------------

	// Sweep the setpiece back out. The restoration travels as a wave too, so
	// the room un-becomes itself from the origin outward rather than snapping.
	static void SweepOut(string name, Vector3 origin, double speed = 700.0,
		double range = 2048.0, int col = 0x3060FF, int shape = 1)
	{
		let sp = GITD_Setpiece(GITD_SweepAction.Resolve(name));
		if (!sp) return;
		sp.reverting = true;
		GITD_Sweep.FireScript(origin, name, col, speed, range, shape);
	}

	// The blunt version: no wave, everything back at once. For a map change,
	// a player death, or anything where the pretty version is not worth it.
	void RestoreEverything()
	{
		for (int i = 0; i < jIdx.Size(); i++)
		{
			int idx = jIdx[i];
			if (idx < 0 || idx >= level.Sectors.Size()) continue;
			RestoreRecord(level.Sectors[idx], i);
		}
		DespawnAll();
		UnstampAll();
		if (music != "" && jMusic != "") S_ChangeMusic(jMusic);
		jIdx.Clear(); jFloor.Clear(); jCeil.Clear();
		jTouched.Clear();
		tinted.Clear();
		started = false;
	}

	private void RestoreSector(Sector sec, int idx)
	{
		for (int i = 0; i < jIdx.Size(); i++)
		{
			if (jIdx[i] != idx) continue;
			RestoreRecord(sec, i);
			return;
		}
	}

	private void RestoreRecord(Sector sec, int i)
	{
		// Stop declaring a tint for this sector; the compositor puts the
		// map's own colour back on the next flush by itself. Light likewise.
		for (int t = 0; t < tinted.Size(); t++)
		{
			if (tinted[t] == jIdx[i]) { tinted.Delete(t); break; }
		}
		if (envFloorTex != "")
			sec.SetTexture(Sector.floor, TexMan.CheckForTexture(jFloor[i], TexMan.Type_Flat));
		if (envCeilTex != "")
			sec.SetTexture(Sector.ceiling, TexMan.CheckForTexture(jCeil[i], TexMan.Type_Flat));
	}

	// Drop a billboard on the sector floor. Persistent, because the wave that
	// placed it is long gone by the time you want it removed -- the id goes in
	// the journal and the return sweep pulls it.
	private void StampSector(Sector sec)
	{
		Vector2 c = sec.centerspot;
		Vector3 at = (c.x, c.y, sec.floorplane.ZatPoint(c) + (markOnFloor ? 1.0 : markSize * 0.5));
		int id = level.AddBillboardPersistent(at, markSize, markSize,
			0, markOnFloor ? 90.0 : 0.0, markOnFloor ? 0 : 1,
			markPayload, 0, markColor != 0 ? markColor : Color(255, 0, 220, 255),
			0, 0, markText);
		if (id >= 0) jBillboards.Push(id);
	}

	private void UnstampAll()
	{
		for (int i = 0; i < jBillboards.Size(); i++) level.RemoveBillboard(jBillboards[i]);
		jBillboards.Clear();
	}

	private void SpawnInSector(Sector sec)
	{
		Vector2 c = sec.centerspot;
		Vector3 at = (c.x, c.y, sec.floorplane.ZatPoint(c));
		let a = Actor.Spawn(spawnClass, at, ALLOW_REPLACE);
		if (!a) return;
		if (!a.TestMobjLocation()) { a.Destroy(); return; }
		jSpawned.Push(a);
	}

	private void DespawnAll()
	{
		for (int i = 0; i < jSpawned.Size(); i++)
		{
			let a = jSpawned[i];
			// Anything the player already killed stays dead -- removing a
			// corpse the player earned is worse than leaving it.
			if (a && a.health > 0) a.Destroy();
		}
		jSpawned.Clear();
	}
}


// ===========================================================================
// A worked example, and the thing to copy.
//
// Everything below is ordinary mod code -- it uses only the public surface of
// this file, and nothing in the engine knows it exists. Fire it with
//
//     netevent gitd_setpiece
//
// and again to sweep it back out. Read it as the template: a setpiece is a
// Configure() and nothing else unless you want more.
// ===========================================================================
class GITD_DemoArena : GITD_Setpiece
{
	override void Configure()
	{
		envColor  = Color(255, 150, 20, 20);   // the room turns the colour of a warning
		envDesat  = 80;                        // and loses most of its own colour
		envLight  = -40;
		spawnOdds = 0;                         // spawns nothing by default: a demo
		tierBoost = 1.35;                      // that added monsters would be rude
		markPayload = 0;
		revertOnFinish = false;                // it STAYS until swept back out
	}
}

// The console hook. Two states, one command: sweep in, sweep out.
class GITD_SetpieceConsole : EventHandler
{
	bool applied;

	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.name != "gitd_setpiece") return;
		let pmo = players[e.Player].mo;
		if (!pmo) return;

		if (!applied)
		{
			GITD_Sweep.FireScript(pmo.pos, "GITD_DemoArena", 0xFF2000, 700, 2400);
			Console.Printf("\c[Gold]Setpiece sweeping IN. Run it again to sweep it back out.");
		}
		else
		{
			GITD_Setpiece.SweepOut("GITD_DemoArena", pmo.pos, 700, 2400);
			Console.Printf("\c[Gold]Setpiece sweeping OUT.");
		}
		applied = !applied;
	}
}

// Headless self-test. gitd_ss_demo 1 fires the setpiece in at two seconds and
// back out at six, with no input -- which is the only way to exercise the
// journal from a command line, since netevent needs a live player.
class GITD_SetpieceSelfTest : StaticEventHandler
{
	int t;
	override void WorldLoaded(WorldEvent e) { t = 0; }
	override void WorldTick()
	{
		if (!CVar.FindCVar("gitd_ss_demo").GetBool()) return;
		t++;
		let pmo = players[consoleplayer].mo;
		if (!pmo) return;
		if (t == 69 || t == 200 || t == 340) Report(t);
		if (t == 70)  GITD_Sweep.FireScript(pmo.pos, "GITD_DemoArena", 0xFF2000, 900, 2400);
		if (t == 210) GITD_Setpiece.SweepOut("GITD_DemoArena", pmo.pos, 900, 2400);
	}

	// Sample a few sectors so the log shows the setpiece actually landing and
	// actually coming back off, rather than just failing to crash.
	void Report(int t)
	{
		string tag = (t < 70) ? "BEFORE" : (t < 300 ? "APPLIED" : "REVERTED");
		int n = min(level.Sectors.Size(), 3);
		for (int i = 0; i < n; i++)
		{
			Sector s = level.Sectors[i];
			Color c = s.ColorMap.LightColor;
			Console.Printf("SWEEPTEST %s sec%d light=%d color=%02x%02x%02x desat=%d",
				tag, i, s.lightlevel, c.r, c.g, c.b, s.ColorMap.Desaturation);
		}
	}
}
