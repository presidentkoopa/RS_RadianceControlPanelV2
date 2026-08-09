// ===========================================================================
// AMBUSH SETPIECES.
//
// The thing this file exists for: a wave sweeps a LOCKDOWN over wherever you
// are standing -- the room darkens and tints, things appear inside it sized to
// the room you are actually in, optionally what already lived there is
// promoted -- and killing everything sweeps the level back to what it was.
// A change you cannot undo is not a setpiece, it is damage, so all of this
// rides GITD_Setpiece's journal; nothing here writes light or colour directly,
// it declares through GITD_Composite like everything else does now.
//
// Three parts, in order of reuse value:
//
//   GITD_RoomSense   measures the room around a point. A flood across sector
//                    boundaries, honest about being an estimate. Static
//                    utility -- anything else that wants to know "how big is
//                    the space the player is in" should call this, not
//                    reinvent it.
//
//   GITD_Ambush      the framework. Extends GITD_Setpiece; adds the room
//                    measurement, a spawn BUDGET scaled by room class, spawn
//                    placement at flood-visited sector centerspots, win
//                    tracking, and a phase machine the controller can read.
//                    Authoring a new ambush is a subclass with a Configure()
//                    override and nothing else -- see GITD_Ambush_Blackout.
//
//   GITD_AmbushControl  the one EventHandler. Triggers (netevent + ambient
//                    roll, all cvar-gated, all DEFAULT OFF), the win/timer/
//                    flee/death watchdog, and the victory badge.
//
// LIFECYCLE RULE LEARNED FROM READING SweepEngine.zs, WORTH STATING LOUDLY:
// GITD_Setpiece.SweepOut cancels any wave still carrying the setpiece INWARD
// before it fires the return wave -- but the cancelled wave's OnFinish fires
// on the next cull, AFTER `reverting` has been set, and takes the "outbound
// finished" branch with the outbound wave barely out of the gate. So this
// file NEVER calls SweepOut while the inbound wave is still travelling. While
// sweeping in, the only exits are (a) let it finish, or (b) the blunt
// AbortHard: Cancel + RestoreEverything, no return wave. The controller
// enforces that; keep it true if you change the state machine.
// ===========================================================================


// ---------------------------------------------------------------------------
// GITD_RoomSense -- how big is the room this point is in?
//
// A breadth-first flood across sector boundaries, starting from the sector
// under the point. It crosses a shared line only when the opening is
// PASSABLE: a ceiling-to-floor gap a player fits through (> 56) and a floor
// step something can walk up (<= 24). Blocking flags stop it, closed doors
// stop it (their gap is zero), line portals stop it. It gives up at a radius
// and at a sector count, because "the room" on an open plain is a lie at any
// size and the cap is the honest answer.
//
// The step rule means a big drop-off ends the room even though a PLAYER could
// jump down it. That is deliberate: this measures the space a fight happens
// in, and something that spawns on the far side of a 128-unit ledge is not in
// your fight.
//
// AREA IS AN OVERESTIMATE and says so. Each visited sector contributes the
// area of its bounding box -- an L-shaped sector counts its notch, and two
// diagonal neighbours count their overlap twice. Good enough to tell a closet
// from an arena, which is all it claims. Doing it properly means triangulating
// every sector, which is the engine's job, not a mod's.
// ---------------------------------------------------------------------------
class GITD_RoomInfo : Object play
{
	Array<int> secIdx;      // visited sectors, in flood order
	Array<bool> inRoom;     // level-sized membership mask, O(1) Contains
	int startIdx;           // the sector the flood started from
	Vector3 origin;         // where the measurement was taken
	double area;            // sum of sector bbox areas -- an OVERESTIMATE
	double spanX, spanY;    // extents of the whole region's bounding box
	double maxDist;         // farthest visited centerspot from the origin
	int roomClass;          // GITD_RoomSense.RC_*

	bool Contains(int idx)
	{
		return idx >= 0 && idx < inRoom.Size() && inRoom[idx];
	}

	string ClassLabel()
	{
		return GITD_RoomSense.LabelFor(roomClass);
	}
}

class GITD_RoomSense play abstract
{
	enum ERoomClass
	{
		RC_CLOSET = 0,
		RC_ROOM   = 1,
		RC_HALL   = 2,
		RC_ARENA  = 3,
	}

	const PASS_GAP  = 56.0;   // a player's height; less is a crawlspace
	const PASS_STEP = 24.0;   // max walkable step; more ends the room

	static string LabelFor(int c)
	{
		if (c == RC_CLOSET) return "closet";
		if (c == RC_HALL)   return "hall";
		if (c == RC_ARENA)  return "arena";
		return "room";
	}

	// Can the flood cross this line? Tested at the line's midpoint so sloped
	// planes answer for the actual crossing, not for the sector generally.
	static bool Passable(Line l, bool monsterReach)
	{
		if (!l.frontsector || !l.backsector) return false;
		if (l.flags & (Line.ML_BLOCKING | Line.ML_BLOCKEVERYTHING)) return false;
		if (monsterReach && (l.flags & Line.ML_BLOCKMONSTERS)) return false;
		if (l.isLinePortal()) return false;   // the far side is not adjacent space

		Vector2 mid = l.v1.p + l.delta * 0.5;
		double ff = l.frontsector.floorplane.ZatPoint(mid);
		double bf = l.backsector.floorplane.ZatPoint(mid);
		double top = min(l.frontsector.ceilingplane.ZatPoint(mid),
		                 l.backsector.ceilingplane.ZatPoint(mid));
		double bot = max(ff, bf);

		if (top - bot < PASS_GAP) return false;    // closed door, window slit
		if (abs(ff - bf) > PASS_STEP) return false; // ledge, pit edge
		return true;
	}

	// Measure the room around a point. Returns null only when the point is in
	// no sector at all. monsterReach (the default) treats ML_BLOCKMONSTERS as
	// a wall, which is what an ambush wants -- a spawn beyond one cannot
	// reach the fight.
	static GITD_RoomInfo Measure(Vector3 from, double maxRadius = 1024.0,
		int maxSectors = 96, bool monsterReach = true)
	{
		let start = level.PointInSector(from.xy);
		if (!start) return null;

		let info = new("GITD_RoomInfo");
		info.origin = from;
		info.startIdx = start.Index();

		int n = level.Sectors.Size();
		for (int i = 0; i < n; i++) info.inRoom.Push(false);

		// Region bounds, grown as sectors join.
		double rx0 = 1e30, rx1 = -1e30, ry0 = 1e30, ry1 = -1e30;

		Array<int> queue;
		int head = 0;
		queue.Push(info.startIdx);
		info.inRoom[info.startIdx] = true;

		while (head < queue.Size())
		{
			int idx = queue[head];
			head++;
			Sector sec = level.Sectors[idx];
			info.secIdx.Push(idx);

			// This sector's bbox, from its linedefs' vertices.
			double bx0 = 1e30, bx1 = -1e30, by0 = 1e30, by1 = -1e30;
			for (int li = 0; li < sec.lines.Size(); li++)
			{
				let l = sec.lines[li];
				bx0 = min(bx0, min(l.v1.p.x, l.v2.p.x));
				bx1 = max(bx1, max(l.v1.p.x, l.v2.p.x));
				by0 = min(by0, min(l.v1.p.y, l.v2.p.y));
				by1 = max(by1, max(l.v1.p.y, l.v2.p.y));
			}
			if (bx1 > bx0 && by1 > by0)
			{
				info.area += (bx1 - bx0) * (by1 - by0);
				rx0 = min(rx0, bx0); rx1 = max(rx1, bx1);
				ry0 = min(ry0, by0); ry1 = max(ry1, by1);
			}

			double d = (sec.centerspot - from.xy).Length();
			if (d > info.maxDist) info.maxDist = d;

			// Stop GROWING at the cap; what is already queued still gets its
			// area counted, so the cap rounds the estimate down rather than
			// truncating it mid-room.
			if (queue.Size() >= maxSectors) continue;

			for (int li = 0; li < sec.lines.Size(); li++)
			{
				let l = sec.lines[li];
				int fi = -1, bi = -1;
				if (l.frontsector) fi = l.frontsector.Index();
				if (l.backsector)  bi = l.backsector.Index();
				int oi = (fi == idx) ? bi : fi;
				if (oi < 0 || info.inRoom[oi]) continue;
				if (!Passable(l, monsterReach)) continue;
				if ((level.Sectors[oi].centerspot - from.xy).Length() > maxRadius)
					continue;

				info.inRoom[oi] = true;
				queue.Push(oi);
				if (queue.Size() >= maxSectors) break;
			}
		}

		if (rx1 > rx0) { info.spanX = rx1 - rx0; info.spanY = ry1 - ry0; }

		info.roomClass = Classify(info);
		return info;
	}

	// The thresholds are tuned by eye against Doom-scale maps and say so.
	// They are constants of this function on purpose -- a room classifier
	// with ten cvars is a room classifier nobody can reason about.
	private static int Classify(GITD_RoomInfo info)
	{
		double shortSide = min(info.spanX, info.spanY);
		double longSide  = max(info.spanX, info.spanY);
		double elong = longSide / max(shortSide, 1.0);

		// A closet is small however you slice it.
		if (info.area < 160.0 * 160.0) return RC_CLOSET;
		if (info.secIdx.Size() <= 2 && info.area < 192.0 * 192.0) return RC_CLOSET;

		// A hall is long, narrow, and not merely a big room with a bay.
		if (elong >= 2.6 && shortSide <= 384.0) return RC_HALL;

		// An arena is simply large -- by footprint, or by sprawl.
		if (info.area >= 800.0 * 800.0) return RC_ARENA;
		if (info.secIdx.Size() >= 40 && info.area >= 640.0 * 640.0) return RC_ARENA;

		return RC_ROOM;
	}
}


// ---------------------------------------------------------------------------
// GITD_Ambush -- the framework.
//
// Extends GITD_Setpiece, so the journal, the tint republish, the music swap
// and the travelling revert all come from the base. What this adds:
//
//   - the room is MEASURED when the ambush starts, and everything downstream
//     is scoped to it: only room sectors are journalled and tinted (the
//     visible band still sweeps past them -- light travels, lockdowns do not)
//   - a spawn BUDGET from the room class, scaled by cvar, spent on a spawn
//     PLAN built up front: which sector, which class. Each entry fires when
//     the wavefront reaches its sector, so things appear IN the wave rather
//     than all at once; whatever the band somehow missed is spawned when the
//     wave finishes, so the budget is honest
//   - win tracking, journal-style: every actor this conjured (and every
//     pre-existing monster it promoted) is remembered, and the controller
//     asks LiveTracked() until the answer is none
//   - a phase field (APH_*) the controller reads instead of polling wave
//     state, flipped from OnFinish -- the engine tells us when a wave dies,
//     so there is nothing to poll
//
// AUTHORING A NEW AMBUSH is a subclass and a Configure() override:
//
//     class RS_Ambush_Meltdown : GITD_Ambush
//     {
//         override void Configure()
//         {
//             Super.Configure();          // cvar-fed defaults first -- keep this line
//             envColor = Color(255, 120, 40, 10);
//             envLight = -100;
//             aSonar = false;
//             aSpawnCls.Clear(); aSpawnWt.Clear();
//             AddSpawn("HellKnight", 2);
//             AddSpawn("DoomImp", 5);
//         }
//     }
//
// then point gitd_ambush_class at it. Configure() runs at every ambush start
// (and once more from the base's EnsureConfigured; it converges, being a
// straight assignment both times), so cvar changes land on the NEXT ambush
// without a map reload. Super.Configure() first is the contract: it loads the
// player's menu choices, and what you write after it is what your ambush
// refuses to let the menu change.
// ---------------------------------------------------------------------------
class GITD_Ambush : GITD_Setpiece
{
	enum EPhase
	{
		APH_IDLE = 0,
		APH_IN   = 1,   // inbound wave travelling, lockdown being laid
		APH_HOLD = 2,   // lockdown holding; the fight
		APH_OUT  = 3,   // return wave travelling, level un-becoming it
	}

	int aPhase;
	Vector3 aOrigin;
	double aRadius;
	GITD_RoomInfo aRoom;
	int aWaveId;
	bool aSonar;            // put the built-in sonar reveal on the sweep band

	// Set per launch, not per class. The tier scales the spawn budget (and
	// past tier 2, forces some promotion) ON TOP of the room sizing; the
	// reward tag is an opaque string this ambush merely carries and hands
	// back at victory. Today it is printed. A future setpiece shop will hand
	// one in and listen for it -- see design/ambush.md, "later".
	int aTier;
	string aRewardTag;

	// The spawn table Configure() fills. Parallel arrays, same as everywhere
	// else in this codebase that is touched per tic or per event.
	Array<string> aSpawnCls;
	Array<int> aSpawnWt;

	// The plan: which sector gets what, decided up front, spent as the wave
	// arrives. aPlanDone is the journal of what has actually been placed.
	private Array<int> aPlanSec;
	private Array<string> aPlanCls;
	private Array<bool> aPlanDone;

	// Win tracking. aSpawned is what this conjured; aMarked is what already
	// lived here and got promoted. Destroyed actors read back as null, dead
	// ones as health <= 0, so counting the living is one walk.
	private Array<Actor> aSpawned;
	private Array<Actor> aMarked;

	// ---- cvar plumbing ----------------------------------------------------
	// Every read is defensive: this file can be compiled before the cvars are
	// wired into cvarinfo, and a missing cvar must degrade to the shipped
	// default rather than crash the tic.

	static bool CvB(string n, bool d)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetBool() : d;
	}
	static int CvI(string n, int d)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetInt() : d;
	}
	static double CvF(string n, double d)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetFloat() : d;
	}
	static string CvS(string n, string d)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetString() : d;
	}
	// Color cvars hand back a packed int, and Color(int) does not convert on
	// this engine -- build from bytes, same note as GlowHandler.zs.
	static Color CvTint(string n, int d)
	{
		let c = CVar.FindCVar(n);
		int p = c ? c.GetInt() : d;
		return Color(255, (p >> 16) & 255, (p >> 8) & 255, p & 255);
	}

	// ---- configuration ----------------------------------------------------

	void AddSpawn(string cls, int weight)
	{
		aSpawnCls.Push(cls);
		aSpawnWt.Push(max(weight, 1));
	}

	// The cvar-fed defaults. A subclass calls Super.Configure() and then
	// overrides whatever makes it itself.
	override void Configure()
	{
		envColor  = CvTint("gitd_ambush_tint", 0x6e2828);
		envLight  = CvI("gitd_ambush_light", -70);
		envDesat  = CvI("gitd_ambush_desat", 100);
		tierBoost = CvB("gitd_ambush_tierup", false)
			? clamp(CvF("gitd_ambush_tier", 1.35), 1.0, 3.0) : 0;

		// The base setpiece's odds-per-sector spawner stays OFF; the budgeted
		// plan below is this framework's replacement for it.
		spawnOdds = 0;
		revertOnFinish = false;
		markPayload = 0;
		music = "";
		aSonar = false;

		aSpawnCls.Clear(); aSpawnWt.Clear();
		AddSpawn("DoomImp", 1);

		// The launch tier's one overlay. Lives HERE, not in PrepareAmbush,
		// because the base's EnsureConfigured re-runs Configure() during the
		// first OnStart of a map and would wipe anything applied outside it.
		if (aTier >= 3 && tierBoost <= 0) tierBoost = 1.0 + 0.1 * aTier;
	}

	// A subclass hook for kills-it-wins logic beyond the badge. The reward
	// tag is whatever the launcher handed in; the base does nothing with it.
	virtual void OnCleared(string rewardTag) {}

	// Spawn count before the cvar scale. Override for an ambush that wants
	// its own economy.
	virtual int BudgetFor(GITD_RoomInfo room)
	{
		if (room.roomClass == GITD_RoomSense.RC_CLOSET)
		{
			// Nothing, or two imps breathing on your neck. A closet with a
			// proper wave in it is a softlock, not a setpiece.
			return (room.area < 150.0 * 150.0) ? 0 : 2;
		}
		if (room.roomClass == GITD_RoomSense.RC_HALL)  return 5;
		if (room.roomClass == GITD_RoomSense.RC_ARENA) return 14;
		return 7;
	}

	// ---- start ------------------------------------------------------------

	// THE ONE WAY IN. The console netevent and the ambient roll are just two
	// callers of this; a future setpiece shop is a third. Deliberately NOT
	// gated on gitd_ambush_enabled -- that cvar gates the TRIGGERS, and a
	// system that calls Launch directly has already made its own decision.
	//
	//   origin     where the lockdown lands (the player's feet, usually)
	//   tier       1 = as the menu says; each step adds half the budget
	//              again, and from 3 up some promotion even if the menu has
	//              tier-up off
	//   rewardTag  opaque; carried, then handed to OnCleared and printed at
	//              victory. "" = nothing
	//   clsName    which GITD_Ambush; "" = the gitd_ambush_class cvar
	//
	// Returns false and changes nothing if there is no controller wired in,
	// one is already running, the class is wrong, the room offers nothing,
	// or the wave ceiling is hit.
	static bool Launch(Vector3 origin, int tier = 1, string rewardTag = "",
		string clsName = "")
	{
		// The controller is the watchdog; an ambush nobody is watching can
		// never be won or reverted, so refuse rather than half-run.
		let ctl = GITD_AmbushControl(EventHandler.Find("GITD_AmbushControl"));
		if (!ctl)
		{
			Console.Printf("\c[Red]GITD ambush: GITD_AmbushControl is not in mapinfo's AddEventHandlers.");
			return false;
		}
		let running = ctl.Active();
		if (running && running.aPhase != APH_IDLE) return false;

		string wanted = (clsName != "") ? clsName
			: CvS("gitd_ambush_class", "GITD_Ambush_Blackout");
		let amb = GITD_Ambush(GITD_SweepAction.Resolve(wanted));
		if (!amb)
		{
			Console.Printf("\c[Red]GITD ambush: '%s' is not a GITD_Ambush", wanted);
			return false;
		}

		// Resolve() caches by the EXACT string, and the caller's spelling
		// may differ in case from the class's. Alias the canonical name to
		// the same instance, or the sweep-out would resolve a FRESH object
		// with an empty journal and restore nothing.
		string canon = amb.GetClassName();
		let h = GITD_Handler(StaticEventHandler.Find("GITD_Handler"));
		if (canon != wanted && h)
		{
			bool have = false;
			for (int i = 0; i < h.ssActName.Size(); i++)
				if (h.ssActName[i] == canon) { have = true; break; }
			if (!have) { h.ssActName.Push(canon); h.ssActObj.Push(amb); }
		}

		if (!amb.PrepareAmbush(origin, tier, rewardTag))
		{
			Console.Printf("\c[Gold]GITD ambush: nothing to ambush you with here.");
			return false;
		}

		int col = CvI("gitd_ambush_color", 0xFF2010);
		int id = GITD_Sweep.FireScript(origin, canon, col,
			CvF("gitd_ambush_speed", 700.0),
			amb.aRadius + 256.0, GITD_Sweep.SHAPE_RING, 32.0);
		if (id == 0)
		{
			// The wave ceiling, realistically. Un-arm rather than wedge.
			amb.ResetIdle();
			return false;
		}

		// FireScript leaves fx at 0 for scripted waves; the sonar reveal is
		// a per-band fx, so it is set on the wave after the fact.
		if (amb.aSonar && h)
		{
			let w = h.WaveById(id);
			if (w) w.fx = GITD_Sweep.FX_SONAR;
		}

		amb.aWaveId = id;
		ctl.Watch(canon);
		Console.Printf("\c[Red]AMBUSH \c[Gold]-- %s, %s (%d sectors), tier %d",
			canon, amb.aRoom.ClassLabel(), amb.aRoom.secIdx.Size(), amb.aTier);
		return true;
	}

	// Measure, budget, plan. Returns false when there is nothing this ambush
	// could do here -- no room under the player, or an empty plan with no
	// tier-up to fall back on -- in which case nothing was changed and no
	// wave should be fired.
	bool PrepareAmbush(Vector3 origin, int tier = 1, string rewardTag = "")
	{
		if (aPhase != APH_IDLE) return false;

		aSpawned.Clear(); aMarked.Clear();
		aPlanSec.Clear(); aPlanCls.Clear(); aPlanDone.Clear();
		aRoom = null;
		aWaveId = 0;

		// Before Configure(), which reads aTier for its promotion overlay.
		aTier = clamp(tier, 1, 5);
		aRewardTag = rewardTag;

		Configure();

		aOrigin = origin;
		aRadius = max(CvI("gitd_ambush_radius", 1024), 256);
		aRoom = GITD_RoomSense.Measure(origin, aRadius, 96);
		if (!aRoom) return false;

		int budget = int(BudgetFor(aRoom)
			* clamp(CvF("gitd_ambush_budget", 1.0), 0.0, 4.0)
			* (1.0 + 0.5 * (aTier - 1)));
		BuildPlan(budget);

		if (aPlanSec.Size() == 0 && tierBoost <= 0) return false;

		aPhase = APH_IN;
		return true;
	}

	// Called by the controller when a fired wave could not be created after
	// all (the wave ceiling, mostly), so a half-armed ambush does not wedge.
	void ResetIdle()
	{
		aPhase = APH_IDLE;
		aRoom = null;
		wallWaveId = 0;
		pillarA = -1;
		pillarB = -1;
	}

	// ---- the standing ring and its break ----------------------------------
	//
	// During the HOLD the lockdown boundary is VISIBLE: a stationary wave
	// parked at the radius (speed zero -- the wave system simply never
	// advances it). The break is a gap in that ring, marked by two glowing
	// pillar billboards, and it may drift around the perimeter. The RULE for
	// the break lives in the controller; this owns only the look.
	//
	// The pillars are pure billboards -- no actors. If a break ever needs to
	// be interactive beyond crossing it (touched, shot, closed), the engine's
	// Touch/Aim/SweepBillboard queries answer that without an actor too.

	int wallWaveId;
	int pillarA, pillarB;
	double gapAngle;        // centre of the break, degrees; unbounded, compare
	                        // with deltaangle so wrap never matters

	void StartWall()
	{
		if (!CvB("gitd_ambush_wall", true)) return;
		int col = CvI("gitd_ambush_color", 0xFF2010);
		wallWaveId = GITD_Sweep.Fire(aOrigin, 1, col, 0.0, aRadius, 20.0,
			1, 0.0, 0, 20, true, "gitd_ambush_wall");
		let h = GITD_Handler(StaticEventHandler.Find("GITD_Handler"));
		if (h && wallWaveId > 0)
		{
			let w = h.WaveById(wallWaveId);
			if (w) w.pos = aRadius;   // parked AT the boundary
		}
		gapAngle = frandom(0, 360);
		PlacePillars();
	}

	void StepWall()
	{
		if (CvF("gitd_ambush_gap", 0) <= 0) return;
		double drift = CvF("gitd_ambush_gap_drift", 10.0);
		if (drift == 0) return;
		gapAngle += drift / 35.0;
		// Re-seat the pillars once a second. The rule reads gapAngle live,
		// so the door itself is exact even between re-seats.
		if ((level.maptime % 35) == 0) PlacePillars();
	}

	void EndWall()
	{
		if (wallWaveId > 0)
		{
			GITD_Sweep.Cancel("gitd_ambush_wall");
			wallWaveId = 0;
		}
		RemovePillars();
	}

	private void PlacePillars()
	{
		RemovePillars();
		double gap = CvF("gitd_ambush_gap", 0);
		if (gap <= 0) return;
		int col = CvI("gitd_ambush_color", 0xFF2010);
		Color pc = Color(255, (col >> 16) & 255, (col >> 8) & 255, col & 255);
		pillarA = PlacePillar(gapAngle - gap * 0.5, pc);
		pillarB = PlacePillar(gapAngle + gap * 0.5, pc);
	}

	private int PlacePillar(double ang, Color pc)
	{
		Vector2 p = aOrigin.xy + (cos(ang), sin(ang)) * aRadius;
		Sector sec = level.PointInSector(p);
		if (!sec) return -1;
		double fz = sec.floorplane.ZatPoint(p);
		// A thin tall panel, glowing, facing the player: a gatepost.
		int id = level.AddBillboardPersistent((p.x, p.y, fz + 60), 14, 120,
			0, 0, 1, 0, 10 | (2 << 8), pc, 0, 0);
		if (id >= 0) level.SetBillboardGlow(id, 96, 1.4);
		return id;
	}

	private void RemovePillars()
	{
		if (pillarA >= 0) { level.RemoveBillboard(pillarA); pillarA = -1; }
		if (pillarB >= 0) { level.RemoveBillboard(pillarB); pillarB = -1; }
	}

	private void BuildPlan(int budget)
	{
		if (budget <= 0 || aSpawnCls.Size() == 0 || !aRoom) return;

		// Candidate sectors: the room, minus the player's immediate
		// surroundings -- an ambush materialising inside your hitbox is a
		// cheap shot, not a setpiece. In a closet there may be nowhere else,
		// and then the closet gets to be a closet.
		Array<int> cand;
		for (int i = 0; i < aRoom.secIdx.Size(); i++)
		{
			int idx = aRoom.secIdx[i];
			if ((level.Sectors[idx].centerspot - aOrigin.xy).Length() < 160.0)
				continue;
			cand.Push(idx);
		}
		if (cand.Size() == 0)
		{
			for (int i = 0; i < aRoom.secIdx.Size(); i++)
				cand.Push(aRoom.secIdx[i]);
		}
		if (cand.Size() == 0) return;

		for (int b = 0; b < budget; b++)
		{
			// Up to four rerolls to avoid piling more than two spawns into
			// one sector. After that, pile on -- a small room with a big
			// budget was asked for.
			int idx = -1;
			for (int t = 0; t < 4; t++)
			{
				int pick = cand[random[gitdAmbush](0, cand.Size() - 1)];
				int already = 0;
				for (int p = 0; p < aPlanSec.Size(); p++)
					if (aPlanSec[p] == pick) already++;
				if (already < 2) { idx = pick; break; }
				idx = pick;
			}
			aPlanSec.Push(idx);
			aPlanCls.Push(PickClass());
			aPlanDone.Push(false);
		}
	}

	private string PickClass()
	{
		int total = 0;
		for (int i = 0; i < aSpawnWt.Size(); i++) total += aSpawnWt[i];
		int r = random[gitdAmbush](1, max(total, 1));
		for (int i = 0; i < aSpawnCls.Size(); i++)
		{
			r -= aSpawnWt[i];
			if (r <= 0) return aSpawnCls[i];
		}
		return aSpawnCls[aSpawnCls.Size() - 1];
	}

	// ---- the wavefront arrives --------------------------------------------

	override void OnSector(GITD_Handler h, Sector sec, int idx, int band, double strength)
	{
		if (aPhase == APH_IDLE) return;
		if (aPhase == APH_OUT)
		{
			// The return trip. The base restores from its journal; the
			// journal only holds what we let in below, so no mask needed.
			Super.OnSector(h, sec, idx, band, strength);
			return;
		}

		// The lockdown claims the ROOM, not everything the light crosses.
		// The visible band sweeps on past; sectors beyond the room's walls
		// are never journalled, never tinted, never spawned into.
		if (aRoom && !aRoom.Contains(idx)) return;

		Super.OnSector(h, sec, idx, band, strength);

		if (strength < 0.5) return;   // the band's core does the work
		RunPlanAt(idx);
	}

	override void OnActor(GITD_Handler h, Actor a, int band, double strength)
	{
		// Promotion happens on the way in, never on the way out, never to
		// what this ambush itself conjured -- a fresh spawn promoted by the
		// very band that placed it is a compound-interest bug.
		if (aPhase != APH_IN) return;
		if (tierBoost <= 0 || !a || a.bFRIENDLY) return;
		if (IsOurs(a)) return;
		if (aRoom && a.CurSector && !aRoom.Contains(a.CurSector.Index())) return;

		Super.OnActor(h, a, band, strength);

		if (strength >= 0.5) TrackMarked(a);
	}

	// The engine calls this when a wave carrying this action dies -- inbound
	// or outbound, it cannot tell us which, but the phase can.
	override void OnFinish(GITD_Handler h)
	{
		Super.OnFinish(h);

		if (aPhase == APH_IN)
		{
			// The lockdown is fully laid. Spend whatever the band's core
			// somehow never crossed (a centerspot in a notch, mostly), so
			// the budget means what it says.
			for (int i = 0; i < aPlanDone.Size(); i++)
				if (!aPlanDone[i]) { aPlanDone[i] = true; TrySpawn(aPlanSec[i], aPlanCls[i]); }
			aPhase = APH_HOLD;
		}
		else if (aPhase == APH_OUT)
		{
			// The return wave has finished; the base has already walked its
			// journal back and despawned its own. Ours go with it.
			DespawnMine();
			aRoom = null;
			aPhase = APH_IDLE;
		}
	}

	// ---- spawning ---------------------------------------------------------

	private void RunPlanAt(int idx)
	{
		for (int i = 0; i < aPlanSec.Size(); i++)
		{
			if (aPlanDone[i] || aPlanSec[i] != idx) continue;
			aPlanDone[i] = true;
			TrySpawn(idx, aPlanCls[i]);
		}
	}

	private bool TrySpawn(int secIdx, string clsName)
	{
		class<Actor> cls = clsName;
		if (!cls)
		{
			Console.Printf("\c[Red]GITD ambush: no actor class '%s'", clsName);
			return false;
		}
		if (secIdx < 0 || secIdx >= level.Sectors.Size()) return false;
		Sector sec = level.Sectors[secIdx];
		Vector2 c = sec.centerspot;

		// Centerspot first, then four offsets -- a centerspot on a torch or
		// in a pillar is common enough that one try is not honest effort.
		static const double xo[] = { 0.0, 96.0, -96.0,  0.0,   0.0 };
		static const double yo[] = { 0.0,  0.0,   0.0, 96.0, -96.0 };

		for (int k = 0; k < 5; k++)
		{
			Vector2 p = (c.x + xo[k], c.y + yo[k]);
			let s2 = level.PointInSector(p);
			if (!s2) continue;
			if (aRoom && !aRoom.Contains(s2.Index())) continue;

			Vector3 at = (p.x, p.y, s2.floorplane.ZatPoint(p));
			let mon = Actor.Spawn(cls, at, ALLOW_REPLACE);
			if (!mon) continue;
			if (!mon.TestMobjLocation()) { mon.Destroy(); continue; }

			// It is an ambush: it arrives knowing where you are.
			let pmo = players[consoleplayer].mo;
			if (pmo && mon.bISMONSTER)
			{
				mon.target = pmo;
				if (mon.SeeState) mon.SetState(mon.SeeState);
			}
			Actor.Spawn("TeleportFog", at, ALLOW_REPLACE);
			mon.A_StartSound("misc/teleport");

			aSpawned.Push(mon);
			return true;
		}
		return false;
	}

	// ---- tracking ---------------------------------------------------------

	bool IsOurs(Actor a)
	{
		for (int i = 0; i < aSpawned.Size(); i++)
			if (aSpawned[i] == a) return true;
		return false;
	}

	private void TrackMarked(Actor a)
	{
		for (int i = 0; i < aMarked.Size(); i++)
			if (aMarked[i] == a) return;
		aMarked.Push(a);
	}

	// Did this ambush ever have anything to kill? Guards against a victory
	// declared over an empty room because every spawn attempt failed.
	bool HadTracked()
	{
		return aSpawned.Size() + aMarked.Size() > 0;
	}

	int LiveTracked()
	{
		int n = 0;
		for (int i = 0; i < aSpawned.Size(); i++)
		{
			let a = aSpawned[i];
			if (a && a.health > 0) n++;
		}
		for (int i = 0; i < aMarked.Size(); i++)
		{
			let a = aMarked[i];
			if (a && a.health > 0) n++;
		}
		return n;
	}

	// ---- endings ----------------------------------------------------------

	// The pretty exit: the level un-becomes the ambush from its origin
	// outward. ONLY legal from APH_HOLD -- see the lifecycle rule in the file
	// header for why sweeping out mid-inbound corrupts the ending.
	void BeginRevert()
	{
		if (aPhase != APH_HOLD) return;
		aPhase = APH_OUT;
		GITD_Setpiece.SweepOut(GetClassName(), aOrigin,
			CvF("gitd_ambush_speed", 700.0), aRadius + 256.0);
	}

	// The blunt exit: everything back at once, spawns gone, no wave. For a
	// player death, or an abandon while the inbound wave is still travelling.
	void AbortHard()
	{
		GITD_Sweep.Cancel(GetClassName());
		RestoreEverything();
		DespawnMine();
		aRoom = null;
		aPhase = APH_IDLE;
	}

	private void DespawnMine()
	{
		for (int i = 0; i < aSpawned.Size(); i++)
		{
			let a = aSpawned[i];
			// Corpses the player earned stay. The living leave with the
			// lockdown that conjured them -- counters cleared first so the
			// kill percentage is not inflated by monsters that ceased to be.
			if (a && a.health > 0)
			{
				a.ClearCounters();
				a.Destroy();
			}
		}
		aSpawned.Clear();
		// Promoted survivors stay promoted. On a victory there are none; on
		// a flee or a timeout, the room remembering what you did to it is
		// the point.
		aMarked.Clear();
		aPlanSec.Clear(); aPlanCls.Clear(); aPlanDone.Clear();
	}
}


// ---------------------------------------------------------------------------
// GITD_Ambush_Blackout -- the authored one.
//
// The lights collapse to near-dark, swept inward over the room; the sweep
// line carries the sonar reveal, so the band is the only moment you see the
// room whole before it goes back under. What spawns is sized to the room by
// the framework. Victory pops the ambush count through the Neon engine.
// ---------------------------------------------------------------------------
class GITD_Ambush_Blackout : GITD_Ambush
{
	override void Configure()
	{
		Super.Configure();                      // menu choices first

		// What makes it a blackout: the tint multiplies sector colour to a
		// cold sliver, the light delta drags everything to the floor, and
		// the drain finishes the job -- colour vision fails in the dark.
		envColor = Color(255, 34, 38, 54);
		envLight = -220;
		envDesat = 190;

		// The band is the only light there is, so it does the revealing:
		// sonar lifts each sector to its natural brightness as the line
		// crosses it, then lets it sink back to near-black behind.
		aSonar = true;

		aSpawnCls.Clear(); aSpawnWt.Clear();
		AddSpawn("DoomImp", 5);
		AddSpawn("Demon", 3);       // a pinky in the dark is the whole genre
		AddSpawn("ShotgunGuy", 2);
	}
}


// ---------------------------------------------------------------------------
// GITD_AmbushControl -- triggers and the watchdog.
//
// MUST be listed in mapinfo's AddEventHandlers (before GITD_Composite) or
// none of this runs, silently -- see design/ambush-wiring.md for the exact
// lines. Everything here is gated on gitd_ambush_enabled, which ships OFF.
//
//   netevent gitd_ambush        start one at your feet; again = abandon it
//   netevent gitd_ambush_room   print what RoomSense makes of where you are
//
// The ambient roll is a coin toss every gitd_ambush_period seconds with
// gitd_ambush_chance percent odds, silenced for gitd_ambush_spacing seconds
// after each ambush ends (and the same grace at map start).
// ---------------------------------------------------------------------------
class GITD_AmbushControl : EventHandler
{
	string activeName;    // canonical class name of the running ambush
	int prevPhase;
	int holdStart;        // maptime when the lockdown finished arriving
	int lastEnd;          // maptime when the last ambush ended
	int fleeTics;         // how long the player has been outside the leash
	double prevDist;      // last tic's distance from the origin, for the break
	int wins;             // ambushes cleared this map -- the badge number

	// The victory badge, when the Neon style is wgType 13: that payload has
	// to be OPENED and CLOSED by whoever spawned it, so it is driven here.
	int badgeId;
	int badgeAge;

	const LEASH = 1.5;        // times the radius before "you left"
	const LEASH_TICS = 70;    // and for this long, so a doorway peek is free

	override void WorldLoaded(WorldEvent e)
	{
		activeName = "";
		prevPhase = 0;
		holdStart = 0;
		lastEnd = 0;      // spacing therefore also delays the FIRST ambient roll
		fleeTics = 0;
		wins = 0;
		badgeId = 0;
		badgeAge = 0;
	}

	GITD_Ambush Active()
	{
		if (activeName == "") return null;
		return GITD_Ambush(GITD_SweepAction.Resolve(activeName));
	}

	// Launch calls this once the wave is away: the named ambush is now the
	// one this watchdog owns.
	void Watch(string canon)
	{
		activeName = canon;
		prevPhase = GITD_Ambush.APH_IN;
		fleeTics = 0;
		prevDist = 0;
	}

	// ---- triggers ---------------------------------------------------------

	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.name == "gitd_ambush_room")
		{
			// Diagnostics only; changes nothing, so it is not gated.
			DebugRoom(e.Player);
			return;
		}
		if (e.name != "gitd_ambush") return;

		if (!GITD_Ambush.CvB("gitd_ambush_enabled", false))
		{
			Console.Printf("\c[Gold]GITD ambush: off. Set gitd_ambush_enabled 1 first.");
			return;
		}

		let amb = Active();
		if (amb && amb.aPhase != GITD_Ambush.APH_IDLE)
		{
			// Second pull = give up on this one.
			if (amb.aPhase == GITD_Ambush.APH_HOLD)
			{
				Console.Printf("\c[Gold]GITD ambush: abandoned. It sweeps back out.");
				amb.BeginRevert();
			}
			else if (amb.aPhase == GITD_Ambush.APH_IN)
			{
				// Mid-inbound there is no clean return wave -- see the
				// lifecycle rule in the file header. Blunt it.
				Console.Printf("\c[Gold]GITD ambush: aborted mid-sweep.");
				amb.AbortHard();
				lastEnd = level.maptime;
				activeName = "";
			}
			return;
		}

		// netevent gitd_ambush <tier> -- the first argument is the tier,
		// for testing what the shop will one day pay for. 0 or absent = 1.
		StartAmbush(e.Player, (e.Args[0] > 0) ? e.Args[0] : 1);
	}

	// A trigger is just a caller of GITD_Ambush.Launch, with the player's
	// feet as the origin and no reward on the line.
	void StartAmbush(int pnum, int tier)
	{
		if (pnum < 0 || pnum >= MAXPLAYERS || !playeringame[pnum]) return;
		let pmo = players[pnum].mo;
		if (!pmo || pmo.health <= 0) return;
		GITD_Ambush.Launch(pmo.pos, tier, "");
	}

	// ---- the watchdog -----------------------------------------------------

	override void WorldTick()
	{
		DriveBadge();
		AmbientRoll();

		let amb = Active();
		if (!amb) return;

		int ph = amb.aPhase;

		// Phase transitions are made by the ambush (from OnFinish); the
		// controller only OBSERVES them, here, once per tic.
		if (prevPhase == GITD_Ambush.APH_IN && ph == GITD_Ambush.APH_HOLD)
		{
			holdStart = level.maptime;
			Console.Printf("\c[Red]LOCKDOWN. \c[Gold]Clear it to lift it.");
			amb.StartWall();
		}
		if (prevPhase == GITD_Ambush.APH_OUT && ph == GITD_Ambush.APH_IDLE)
		{
			lastEnd = level.maptime;
			activeName = "";
			prevPhase = ph;
			return;
		}
		prevPhase = ph;

		if (ph == GITD_Ambush.APH_IDLE)
		{
			// Ended by some path that never travelled OUT (AbortHard).
			activeName = "";
			return;
		}

		// The standing ring exists only while the HOLD does. EndWall is
		// idempotent, so calling it on every non-HOLD tic (IN or OUT, since
		// IDLE already returned above) is the simplest way to cover victory,
		// abandonment, timers, leashes and aborts with one line.
		if (ph != GITD_Ambush.APH_HOLD) amb.EndWall();

		let pmo = players[consoleplayer].mo;

		// Death ends it bluntly, whatever phase it was in. A death screen
		// does not need the pretty version, and a corrupted journal on the
		// next attempt is the alternative. AbortHard is safe even mid-OUT:
		// tint and light are declarative, so clearing the journal restores
		// everything the return wave had not yet reached.
		if (!pmo || pmo.health <= 0)
		{
			amb.AbortHard();
			lastEnd = level.maptime;
			activeName = "";
			return;
		}

		if (ph != GITD_Ambush.APH_HOLD) return;

		amb.StepWall();

		// The break: crossing the boundary THROUGH the gap is the clean way
		// out. The ambush lets you go on the spot and puts the room back --
		// escape as a thing you steer for, not a thing you outwait. Any
		// other crossing falls through to the leash below, unchanged.
		double dNow = (pmo.pos.xy - amb.aOrigin.xy).Length();
		double gapDeg = GITD_Ambush.CvF("gitd_ambush_gap", 0.0);
		if (gapDeg > 0 && prevDist > 0
			&& prevDist <= amb.aRadius && dNow > amb.aRadius)
		{
			double ang = VectorAngle(pmo.pos.x - amb.aOrigin.x,
			                         pmo.pos.y - amb.aOrigin.y);
			// deltaangle is an ACTOR method, not a global function -- the
			// engine registers it that way (vmthunks_actors.cpp even asks
			// "should this be global?" next to the definition, and answers
			// no). Called on pmo, which is already in scope here.
			if (abs(pmo.deltaangle(ang, amb.gapAngle)) <= gapDeg * 0.5)
			{
				Console.Printf("\c[Gold]GITD ambush: you slipped the break. It lets you go.");
				amb.BeginRevert();
				prevDist = 0;
				return;
			}
		}
		prevDist = dNow;

		// Win: everything the ambush put up, or promoted, is down.
		if (amb.HadTracked() && amb.LiveTracked() == 0)
		{
			Victory(amb, pmo);
			return;
		}

		// A lockdown with nothing in it -- every spawn failed placement and
		// tier-up touched no one. Not a victory; just let the room go.
		if (!amb.HadTracked())
		{
			Console.Printf("\c[Gold]GITD ambush: the room came up empty. Standing down.");
			amb.BeginRevert();
			return;
		}

		// Timer: the ambush gives up before you do, if asked to.
		double tsec = GITD_Ambush.CvF("gitd_ambush_timer", 0.0);
		if (tsec > 0 && level.maptime - holdStart > int(tsec * 35))
		{
			Console.Printf("\c[Gold]GITD ambush: you held out. It withdraws.");
			amb.BeginRevert();
			return;
		}

		// Flee: leave the lockdown far enough, long enough, and it loses
		// interest -- the level restores, its conjured monsters leave with
		// it, and anything it promoted stays promoted. No badge.
		if ((pmo.pos.xy - amb.aOrigin.xy).Length() > amb.aRadius * LEASH)
		{
			fleeTics++;
			if (fleeTics > LEASH_TICS)
			{
				Console.Printf("\c[Gold]GITD ambush: you left it behind. It packs up.");
				amb.BeginRevert();
			}
		}
		else fleeTics = 0;
	}

	void Victory(GITD_Ambush amb, Actor pmo)
	{
		wins++;
		Console.Printf("\c[Red]AMBUSH CLEARED \c[Gold]x%d. The room comes back.", wins);
		// The reward tag rides through untouched. Today it is a console line
		// and a hook; a future setpiece shop listens here.
		if (amb.aRewardTag != "")
			Console.Printf("\c[Gold]GITD ambush: reward due -- %s", amb.aRewardTag);
		amb.OnCleared(amb.aRewardTag);
		if (GITD_Ambush.CvB("gitd_ambush_badge", true)) PopBadge(pmo, wins);
		amb.BeginRevert();
	}

	// ---- the ambient roll -------------------------------------------------

	void AmbientRoll()
	{
		if (!GITD_Ambush.CvB("gitd_ambush_enabled", false)) return;
		if (!GITD_Ambush.CvB("gitd_ambush_ambient", false)) return;

		let amb = Active();
		if (amb && amb.aPhase != GITD_Ambush.APH_IDLE) return;

		int period = max(int(GITD_Ambush.CvF("gitd_ambush_period", 30.0) * 35), 35);
		if (level.maptime == 0 || level.maptime % period != 0) return;

		int spacing = int(GITD_Ambush.CvF("gitd_ambush_spacing", 120.0) * 35);
		if (level.maptime - lastEnd < spacing) return;

		int chance = clamp(GITD_Ambush.CvI("gitd_ambush_chance", 15), 0, 100);
		if (random[gitdAmbush](1, 100) > chance) return;

		StartAmbush(consoleplayer, 1);
	}

	// ---- the badge --------------------------------------------------------

	// Victory pops the ambush count through the Neon engine. GITD ships that
	// engine, but a stripped build should degrade to a console line rather
	// than crash a victory, hence the class lookup.
	void PopBadge(Actor pmo, int n)
	{
		class<Object> neon = "GITD_Neon";
		if (!neon || !GITD_Neon.Enabled()) return;

		string txt = String.Format("%d", n);
		Vector3 p = pmo.pos + (0, 0, pmo.height + 24);

		// wgType 13 is not interchangeable with the text payloads: it takes
		// its number in `data` and needs its open/close driven -- same dance
		// as the kill counter, in miniature.
		if (GITD_Neon.IsWG13())
		{
			if (badgeId != 0) { level.RemoveBillboard(badgeId); badgeId = 0; }
			double w, h;
			[w, h] = GITD_Neon.BadgeSize(txt.Length(), true);
			badgeId = level.AddBillboardPersistent(p, w, h, 0, 0,
				LevelLocals.BBF_CAMERAYAW, LevelLocals.BB_WG13, n,
				GITD_Neon.MenuColor(), 0, 0);
			if (badgeId != 0)
			{
				level.SetBillboardProgress(badgeId, 0.05);
				badgeAge = 0;
			}
			return;
		}
		GITD_Neon.Pop(p, txt);
	}

	// 12 tics open, hold, 14 back -- the badge's own curve, borrowed from
	// the kill counter so the two cannot read as different objects.
	void DriveBadge()
	{
		if (badgeId == 0) return;
		badgeAge++;

		double prog;
		if (badgeAge < 12)        prog = badgeAge / 12.0;
		else if (badgeAge <= 96)  prog = 1.0;
		else if (badgeAge <= 110) prog = (110 - badgeAge) / 14.0;
		else
		{
			level.RemoveBillboard(badgeId);
			badgeId = 0;
			return;
		}
		level.SetBillboardProgress(badgeId, clamp(prog, 0.05, 1.0));
	}

	// ---- diagnostics ------------------------------------------------------

	void DebugRoom(int pnum)
	{
		if (pnum < 0 || pnum >= MAXPLAYERS || !playeringame[pnum]) return;
		let pmo = players[pnum].mo;
		if (!pmo) return;

		let info = GITD_RoomSense.Measure(pmo.pos,
			max(GITD_Ambush.CvI("gitd_ambush_radius", 1024), 256), 96);
		if (!info)
		{
			Console.Printf("\c[Red]GITD room: you appear to be nowhere.");
			return;
		}
		Console.Printf(
			"\c[Gold]GITD room: \c[Red]%s\c[Gold] -- %d sectors, ~%dk u2 (overestimate), span %d x %d, reach %d",
			info.ClassLabel(), info.secIdx.Size(), int(info.area / 1000.0),
			int(info.spanX), int(info.spanY), int(info.maxDist));
	}
}
