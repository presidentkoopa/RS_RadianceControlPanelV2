// ============================================================================
// GITD Death-Ping -- DRAFT. Not wired into zscript.txt, not loaded by anything.
//
// The engine's half is BB_DEATHPING (see design/death-ping.md section 2): a
// one-quad radar ring transcribed from GITD v1's wgType 3, progress-driven,
// fade belongs to the caller. This file is the caller: when a ping exists,
// what its ring touches, and what touching escalates into.
//
// NOTHING HERE SPAWNS AN ACTOR FOR A PING. Billboards are level-owned; the
// driver is plain Objects in the handler's arrays, which is the kill
// counter's own pattern. The only actors this file ever touches are monsters
// that already exist -- and one that gets to exist AGAIN, through the seam.
//
// THE LADDER OF ESCALATION, all cvar-gated, all off by default past rung 1:
//   1. every corpse pings                        (gitd_ping_enabled)
//   2. a ping fires a sector sweep               (gitd_ping_sweep)
//   3. the ring pings the living it touches      (gitd_ping_sonar)
//   4. the ring re-pings corpses it touches      (gitd_ping_chain)
//   5. N links tear open a seam and the last
//      monster comes back promoted               (gitd_ping_seam_links)
// ============================================================================

// [DRAFT] Until the engine lands, LevelLocals.BB_DEATHPING does not exist.
// This mirrors the planned value (doombase.zs enum, after BB_WG13 = 10) and
// must be DELETED in favour of the real constant when it does.
const GITD_BB_DEATHPING = 11;

// ----------------------------------------------------------------------------
// One live ping. A record, not a thinker: the handler owns the tick.
// ----------------------------------------------------------------------------
class GITD_PingRecord : Object play
{
	int    bbid;         // the BB_DEATHPING billboard's handle
	double x, y;         // where (corpse position; the corpse may be gone)
	double reach;        // full radius, map units
	int    born;         // level.maptime at start of the CURRENT cycle
	int    lifeTics;
	Color  baseCol;      // undimmed; the fade multiplies this down each tic
	int    echoesLeft;   // re-runs remaining; each starts dimmer
	double echoDim;      // brightness of the current cycle, 1.0 for the first
	double prevR;        // ring radius last tic, for crossing tests
	int    link;         // chain depth: 0 = a kill, 1+ = relayed
	int    chainId;      // which chain this ping belongs to (0 = none)
	int    tier;         // the dead thing's toughness tier, 0..3
}

// ----------------------------------------------------------------------------
// GITD_DeathPing -- cvar reads, colour, tiering, and the one way to fire a
// ping. Static and stateless; the handler is the state.
// ----------------------------------------------------------------------------
class GITD_DeathPing play abstract
{
	static bool Enabled()
	{
		let cv = CVar.FindCVar('gitd_ping_enabled');
		return cv ? cv.GetBool() : true;
	}

	static int    CInt(string n, int def)    { let c = CVar.FindCVar(n); return c ? c.GetInt() : def; }
	static double CFlt(string n, double def) { let c = CVar.FindCVar(n); return c ? c.GetFloat() : def; }
	static bool   CBool(string n, bool def)  { let c = CVar.FindCVar(n); return c ? c.GetBool() : def; }

	// Toughness tier, 0..3 by spawn health. The original resolved tier on the
	// handler from monster toughness; standalone GITD has only health to read.
	static int TierOf(Actor mo)
	{
		if (mo == null) return 0;
		int h = mo.SpawnHealth();
		if (h <= 150)  return 0;   // fodder
		if (h <= 500)  return 1;   // demon / cacodemon class
		if (h <= 1000) return 2;   // baron class
		return 3;                  // the big ones
	}

	// The original's tier reach: size x (1 + 0.35 x tier), the 0.35 now a cvar.
	static double ReachFor(int tier)
	{
		return double(CInt('gitd_ping_size', 160))
			* (1.0 + CFlt('gitd_ping_tier_scale', 0.35) * tier);
	}

	// Hue-sextant HSV, the same maths every GITD colour path uses.
	static Color HSV(double h, double s, double v)
	{
		double c = v * s, hp = h / 60.0;
		double hp2 = hp - 2.0 * floor(hp / 2.0);
		double x = c * (1.0 - abs(hp2 - 1.0));
		double r = 0, g = 0, b = 0;
		if      (hp < 1.0) { r = c; g = x; }
		else if (hp < 2.0) { r = x; g = c; }
		else if (hp < 3.0) { g = c; b = x; }
		else if (hp < 4.0) { g = x; b = c; }
		else if (hp < 5.0) { r = x; b = c; }
		else               { r = c; b = x; }
		double m = v - c;
		return Color(255, int((r + m) * 255), int((g + m) * 255), int((b + m) * 255));
	}

	// Cyan for fodder down to red for the thing that nearly killed you --
	// the original tier ramp. `heat` pushes further along it per chain link.
	static Color TierColor(int tier, double heat = 0.0)
	{
		double f = clamp(tier / 3.0 + heat, 0.0, 1.0);
		return HSV(190.0 - 190.0 * f, 0.85, 1.0);
	}

	static Color PingColor(int tier, int seed, double heat)
	{
		int mode = CInt('gitd_ping_color_mode', 0);
		if (mode == 1)
		{
			// Byte-wise, never Color(cvar.GetInt()) -- that cast compiles and
			// then fails at LOAD. See the note in GlowHandler.zs.
			int p = CInt('gitd_ping_color', 0x00dcff);
			return Color(255, (p >> 16) & 255, (p >> 8) & 255, p & 255);
		}
		if (mode == 2)
		{
			int xx = seed * 374761393 + 668265263;
			xx = (xx ^ (xx >> 13)) * 1274126177; xx = xx ^ (xx >> 16);
			return HSV((xx & 0x7FFFFFFF) / double(0x7FFFFFFF) * 360.0, 0.9, 1.0);
		}
		if (mode == 3)
			return HSV((level.maptime * 6 + seed * 47) % 360, 0.9, 1.0);
		return TierColor(tier, heat);
	}

	static Color Dim(Color c, double k)
	{
		k = clamp(k, 0.0, 1.0);
		return Color(255, int(c.r * k), int(c.g * k), int(c.b * k));
	}

	// One tier up the vanilla bestiary, for gitd_ping_promote 1. A LADDER,
	// not a science: each rung is "the next thing you'd rather not fight".
	// Off the end (or a mod's monster) returns "", and the caller stat-boosts
	// instead -- reaching into a mod's own tier system is not GITD's job.
	static string TierUp(class<Actor> cls)
	{
		if (cls is "ZombieMan")       return "ShotgunGuy";
		if (cls is "ShotgunGuy")      return "ChaingunGuy";
		if (cls is "ChaingunGuy")     return "HellKnight";
		if (cls is "DoomImp")         return "Demon";
		if (cls is "Demon")           return "Cacodemon";
		if (cls is "Spectre")         return "Cacodemon";
		if (cls is "LostSoul")        return "Cacodemon";
		if (cls is "Cacodemon")       return "PainElemental";
		if (cls is "PainElemental")   return "Revenant";
		if (cls is "Revenant")        return "Mancubus";
		if (cls is "Mancubus")        return "Arachnotron";
		if (cls is "Arachnotron")     return "HellKnight";
		if (cls is "HellKnight")      return "BaronOfHell";
		if (cls is "BaronOfHell")     return "Archvile";
		return "";
	}
}

// ----------------------------------------------------------------------------
// The handler. Watches deaths, owns every record and ledger, drives every
// billboard, and is the only thing here that ticks.
// ----------------------------------------------------------------------------
class GITD_DeathPingHandler : EventHandler
{
	Array<GITD_PingRecord> pings;

	// The corpse ledger -- where recent deaths happened, for chains. Parallel
	// arrays, per-tic code. cchain is the last chain a corpse relayed for,
	// which is the rule that stops two adjacent corpses ping-ponging forever.
	Array<Actor>  cmo;      // the corpse (may go null; position survives below)
	Array<double> cx, cy;
	Array<int>    ctime;    // when it died
	Array<int>    cchain;   // last chainId this corpse served, 0 = never

	int nextChainId;
	int lastSeamTic;        // cooldown anchor; negative = never fired
	int pingCount;          // every ping ever, for every-Nth and colour seeds

	// A seam mid-delivery. One at a time -- it is minute-gated anyway.
	int    seamBB;
	int    seamOpenTic;
	double seamLen;
	Actor  seamCorpse;
	int    seamLink;

	override void OnRegister()
	{
		nextChainId = 1;
		lastSeamTic = -0x40000000;
		seamBB = 0;
	}

	// ---- birth ----------------------------------------------------------

	override void WorldThingDied(WorldEvent e)
	{
		if (!GITD_DeathPing.Enabled()) return;
		if (e.Thing == null || !e.Thing.bISMONSTER) return;

		// "Every corpse pings" is the point; infighting corpses included.
		// The kill counter's player-only rule is about SCORE -- this is the
		// world reacting, so the gate is opt-in the other way round.
		if (GITD_DeathPing.CBool('gitd_ping_playeronly', false))
		{
			if (e.Thing.target == null || !(e.Thing.target is "PlayerPawn")) return;
		}

		int tier = GITD_DeathPing.TierOf(e.Thing);
		FirePing(e.Thing.pos.x, e.Thing.pos.y, e.Thing.floorz, tier, 0, 0);

		// Into the ledger, chainable for the window.
		cmo.Push(e.Thing);
		cx.Push(e.Thing.pos.x); cy.Push(e.Thing.pos.y);
		ctime.Push(level.maptime);
		cchain.Push(0);

		// Rung 2: the corpse becomes a sweep origin.
		MaybeSweep(e.Thing.pos, tier);
	}

	// One ping, corpse or relay. link 0 is a kill; 1+ arrived down a chain.
	void FirePing(double x, double y, double floorz, int tier, int link, int chainId)
	{
		pingCount++;

		// The cap. Oldest out, early -- a slaughtermap must not starve the
		// rest of the frame for pictures (the impact ring-buffer lesson).
		int maxLive = GITD_DeathPing.CInt('gitd_ping_max', 12);
		while (pings.Size() >= maxLive && pings.Size() > 0)
		{
			if (pings[0].bbid != 0) level.RemoveBillboard(pings[0].bbid);
			pings.Delete(0);
		}

		double heat = link * GITD_DeathPing.CFlt('gitd_ping_chain_boost', 0.15);
		double reach = GITD_DeathPing.ReachFor(tier) * (1.0 + heat);
		Color col = GITD_DeathPing.PingColor(tier, pingCount, heat);

		// SQUARE, flat, floor-hugging, decoration. Square is the shader's
		// contract -- rectangular dimensions draw an ellipse the original
		// could not. +4 clears z-fighting without visibly hovering.
		int id = level.AddBillboardPersistent((x, y, floorz + 4),
			reach * 2.0, reach * 2.0, 0, 90,
			LevelLocals.BBF_FIXED, GITD_BB_DEATHPING, 0,
			col, LevelLocals.BBFL_NOHIT, 0);
		if (id == 0) return;
		level.SetBillboardProgress(id, 0.0);

		let r = new("GITD_PingRecord");
		r.bbid = id; r.x = x; r.y = y; r.reach = reach;
		r.born = level.maptime;
		r.lifeTics = int(clamp(GITD_DeathPing.CFlt('gitd_ping_life', 0.85), 0.3, 3.0) * 35.0);
		r.baseCol = col;
		r.echoesLeft = clamp(GITD_DeathPing.CInt('gitd_ping_echoes', 0), 0, 3);
		r.echoDim = 1.0;
		r.prevR = 0.0;
		r.link = link;
		r.chainId = chainId;
		r.tier = tier;
		pings.Push(r);

		// Optional ceiling mirror -- same record drives both? No: simpler to
		// let the mirror be fire-and-forget with the same life, driven as a
		// second record. Deliberately NOT chain-capable (link -1 sentinel
		// would be needed); the ceiling copy is a picture only.
		if (GITD_DeathPing.CBool('gitd_ping_ceiling', false))
		{
			let sec = level.PointInSector((x, y));
			if (sec != null)
			{
				double cz = sec.ceilingplane.ZatPoint((x, y)) - 4;
				int cid = level.AddBillboardPersistent((x, y, cz),
					reach * 2.0, reach * 2.0, 0, 90,
					LevelLocals.BBF_FIXED, GITD_BB_DEATHPING, 0,
					col, LevelLocals.BBFL_NOHIT, 0);
				if (cid != 0)
				{
					level.SetBillboardProgress(cid, 0.0);
					let cr = new("GITD_PingRecord");
					cr.bbid = cid; cr.x = x; cr.y = y; cr.reach = reach;
					cr.born = level.maptime; cr.lifeTics = r.lifeTics;
					cr.baseCol = col; cr.echoesLeft = 0; cr.echoDim = 1.0;
					cr.prevR = 0.0; cr.link = 0; cr.chainId = -1;  // -1: never chains
					cr.tier = tier;
					pings.Push(cr);
				}
			}
		}
	}

	// ---- the tick -------------------------------------------------------

	override void WorldTick()
	{
		DrivePings();
		DriveSeam();
		PruneLedger();
	}

	void DrivePings()
	{
		bool actors = GITD_DeathPing.CBool('gitd_ping_actors', false);

		for (int i = pings.Size() - 1; i >= 0; i--)
		{
			let r = pings[i];
			int age = level.maptime - r.born;

			if (age >= r.lifeTics)
			{
				// Echo: the SAME billboard runs again, dimmer. Radar.
				if (r.echoesLeft > 0)
				{
					r.echoesLeft--;
					r.echoDim *= 0.55;
					r.born = level.maptime;
					r.prevR = 0.0;
					level.SetBillboardProgress(r.bbid, 0.0);
					continue;
				}
				level.RemoveBillboard(r.bbid);
				pings.Delete(i);
				continue;
			}

			// The original's animation, exactly: progress = t, brightness =
			// (1 - t). The fade lives HERE because it lived in script there
			// (GITD_FX_DeathPing.Tick01) -- the shader holds a still frame.
			double t = double(age) / double(max(1, r.lifeTics));
			level.SetBillboardProgress(r.bbid, t);
			level.UpdateBillboard(r.bbid, 0,
				GITD_DeathPing.Dim(r.baseCol, (1.0 - t) * r.echoDim));

			// The ring as a query: what did the wavefront CROSS this tic?
			double R = r.reach * t;
			if (R > r.prevR)
			{
				if (r.chainId >= 0) CrossCorpses(r, R);
				if (actors) CrossMonsters(r, R);
			}
			r.prevR = R;
		}
	}

	// ---- rung 2: ping -> sweep ------------------------------------------

	void MaybeSweep(Vector3 pos, int tier)
	{
		int mode = GITD_DeathPing.CInt('gitd_ping_sweep', 0);
		if (mode <= 0) return;
		if (mode == 2 && (pingCount % max(1, GITD_DeathPing.CInt('gitd_ping_sweep_every', 5))) != 0) return;
		if (mode == 3)
		{
			// Milestones are the kill counter's idea of special; borrow it.
			int ms = GITD_DeathPing.CInt('gitd_kill_milestone', 0);
			if (ms <= 0 || (pingCount % ms) != 0) return;
		}

		Color c = GITD_DeathPing.TierColor(tier);
		GITD_Sweep.Fire(pos, GITD_Sweep.SHAPE_RING,
			(c.r << 16) | (c.g << 8) | c.b,
			GITD_DeathPing.CFlt('gitd_ping_sweep_speed', 600.0),
			GITD_DeathPing.CFlt('gitd_ping_sweep_range', 1200.0));
	}

	// ---- rung 3: the ring pings the living ------------------------------

	void CrossMonsters(GITD_PingRecord r, double R)
	{
		int mode = GITD_DeathPing.CInt('gitd_ping_sonar', 0);
		if (mode <= 0) return;

		let it = BlockThingsIterator.CreateFromPos(r.x, r.y, 0, 32768, r.reach, false);
		while (it.Next())
		{
			let mo = it.thing;
			if (mo == null || !mo.bISMONSTER || mo.health <= 0) continue;
			double d = (mo.pos.xy - (r.x, r.y)).Length();
			if (d > R || d <= r.prevR) continue;   // must CROSS this tic

			// The return: a small upright ping riding the monster, dying with
			// it. Attached, camera-yawed, decoration.
			int id = level.AttachBillboard(mo, (0, 0, mo.Height * 0.5),
				48, 48, 0, 0, LevelLocals.BBF_CAMERAYAW,
				GITD_BB_DEATHPING, 0, r.baseCol, LevelLocals.BBFL_NOHIT);
			if (id != 0)
			{
				// Fire-and-forget record drives its one fast cycle.
				let sr = new("GITD_PingRecord");
				sr.bbid = id; sr.x = mo.pos.x; sr.y = mo.pos.y;
				sr.reach = 24;
				sr.born = level.maptime;
				sr.lifeTics = int(clamp(GITD_DeathPing.CFlt('gitd_ping_sonar_life', 0.6), 0.2, 2.0) * 35.0);
				sr.baseCol = r.baseCol; sr.echoesLeft = 0; sr.echoDim = 1.0;
				sr.prevR = 0.0; sr.link = 0; sr.chainId = -1;   // returns never chain
				sr.tier = 0;
				pings.Push(sr);
			}

			// Sonar works both ways -- that is what keeps it Doom.
			if (mode >= 2 && mo.target == null)
			{
				mo.target = players[0].mo;   // [DRAFT] nearest player, properly
				mo.SetState(mo.SeeState);
			}

			// Stamp for anyone who wants to know. RS tiering, damage buffs --
			// none of GITD's business, all of them can read the mark.
			if (mode >= 3)
			{
				let mk = GITD_SweepMark(mo.FindInventory("GITD_SweepMark"));
				if (mk == null)
				{
					mo.GiveInventoryType("GITD_SweepMark");
					mk = GITD_SweepMark(mo.FindInventory("GITD_SweepMark"));
				}
				if (mk != null) { mk.band = 0; mk.strength = 1.0; mk.stamp = level.maptime; }
			}
		}
	}

	// ---- rung 4: corpse-to-corpse ---------------------------------------

	void CrossCorpses(GITD_PingRecord r, double R)
	{
		if (!GITD_DeathPing.CBool('gitd_ping_chain', false)) return;
		int maxLinks = GITD_DeathPing.CInt('gitd_ping_chain_links', 8);
		if (r.link >= maxLinks) return;

		int window = GITD_DeathPing.CInt('gitd_ping_chain_window', 700);

		for (int i = 0; i < cx.Size(); i++)
		{
			if (level.maptime - ctime[i] > window) continue;
			double d = ((cx[i], cy[i]) - (r.x, r.y)).Length();
			if (d < 16.0) continue;                 // itself
			if (d > R || d <= r.prevR) continue;    // must CROSS this tic

			// One relay per chain per corpse, or two neighbours ring forever.
			int chain = (r.chainId != 0) ? r.chainId : nextChainId++;
			if (cchain[i] == chain) continue;
			cchain[i] = chain;
			if (r.chainId == 0) r.chainId = chain;

			int nlink = r.link + 1;

			// Rung 5 fires INSTEAD of the relay: the reveal is the final link.
			int seamAt = GITD_DeathPing.CInt('gitd_ping_seam_links', 0);
			if (seamAt > 0 && nlink >= seamAt && seamBB == 0
				&& level.maptime - lastSeamTic
					>= GITD_DeathPing.CInt('gitd_ping_seam_cooldown', 2100))
			{
				OpenSeam(i, nlink);
				return;
			}

			double fz = 0;
			let sec = level.PointInSector((cx[i], cy[i]));
			if (sec != null) fz = sec.floorplane.ZatPoint((cx[i], cy[i]));
			FirePing(cx[i], cy[i], fz, r.tier, nlink, chain);
		}
	}

	// ---- rung 5: the seam, and what comes back through it ---------------

	void OpenSeam(int ledgerIdx, int link)
	{
		lastSeamTic = level.maptime;
		seamCorpse = cmo[ledgerIdx];
		seamLink = link;
		seamOpenTic = level.maptime;
		seamLen = 96;

		double sx = cx[ledgerIdx], sy = cy[ledgerIdx];
		double fz = 0;
		let sec = level.PointInSector((sx, sy));
		if (sec != null) fz = sec.floorplane.ZatPoint((sx, sy));

		// VERTICAL: tilt 0 stands it up, BBFL_VOID makes it a hole with a
		// burning rim rather than a lit slab -- something is coming OUT.
		// Starts a hairline; DriveSeam widens it (the seam shader has no
		// progress term on purpose; the easing is ours).
		Color c = GITD_DeathPing.TierColor(3, 0.0);   // seams burn red-hot
		seamBB = level.AddBillboardPersistent((sx, sy, fz + seamLen * 0.5 + 8),
			2, seamLen, 0, 0, LevelLocals.BBF_CAMERAYAW,
			LevelLocals.BB_SEAM, 0, c,
			LevelLocals.BBFL_VOID | LevelLocals.BBFL_NOHIT, 0);
		if (seamBB == 0) seamCorpse = null;
	}

	void DriveSeam()
	{
		if (seamBB == 0) return;
		int age = level.maptime - seamOpenTic;

		// 20 tics open, deliver, 15 hold, 20 close, gone.
		if (age <= 20)
		{
			double t = age / 20.0;
			level.ResizeBillboard(seamBB, 2 + 68 * (t * t), seamLen);
			return;
		}
		if (age == 21) Deliver();
		if (age >= 36 && age <= 56)
		{
			double t = (age - 36) / 20.0;
			level.ResizeBillboard(seamBB, 70 * (1.0 - t) + 2 * t, seamLen);
		}
		if (age > 56)
		{
			level.RemoveBillboard(seamBB);
			seamBB = 0;
			seamCorpse = null;
		}
	}

	void Deliver()
	{
		let corpse = seamCorpse;
		if (corpse == null) return;
		int promote = GITD_DeathPing.CInt('gitd_ping_promote', 1);

		Actor back = null;
		if (promote == 1)
		{
			// A tier higher. Off the ladder, fall through to the stat boost.
			string up = GITD_DeathPing.TierUp(corpse.GetClass());
			if (up != "")
			{
				back = Actor.Spawn(up, corpse.pos, ALLOW_REPLACE);
				if (back != null) corpse.Destroy();
			}
		}
		if (back == null)
		{
			// As it was -- raise the corpse; a gibbed one spawns fresh.
			if (corpse.RaiseActor(corpse)) back = corpse;
			else back = Actor.Spawn(corpse.GetClass(), corpse.pos, ALLOW_REPLACE);
		}
		if (back == null) return;

		if (promote >= 2 || (promote == 1 && back == corpse))
		{
			// Elite, or the ladder had no rung: same monster, harder. GITD
			// does stats only; a mod with a real elite system reads the
			// SweepMark below and does it properly.
			back.health = back.SpawnHealth() * 2;
			back.Speed = back.Speed * 1.25;
		}

		// Announce it the way everything here announces: a ping, hot.
		FirePing(back.pos.x, back.pos.y, back.floorz,
			GITD_DeathPing.TierOf(back), 0, 0);

		back.GiveInventoryType("GITD_SweepMark");
		let mk = GITD_SweepMark(back.FindInventory("GITD_SweepMark"));
		if (mk != null) { mk.band = seamLink; mk.strength = 1.0; mk.stamp = level.maptime; }
	}

	// ---- housekeeping ---------------------------------------------------

	void PruneLedger()
	{
		int window = GITD_DeathPing.CInt('gitd_ping_chain_window', 700);
		for (int i = cx.Size() - 1; i >= 0; i--)
		{
			if (level.maptime - ctime[i] > window + 35)
			{
				cmo.Delete(i); cx.Delete(i); cy.Delete(i);
				ctime.Delete(i); cchain.Delete(i);
			}
		}
	}
}
