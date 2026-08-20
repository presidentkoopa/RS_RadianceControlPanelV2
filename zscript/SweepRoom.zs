// ============================================================================
//  The room the sweep is allowed to stand in.
// ============================================================================
//
//  THE BUG THIS EXISTS FOR. The sweep's air lattice is built from an INFINITE
//  plane -- "perpendicular to X at o.x" is a plane that exists at every Y and
//  Z on the map. There is a radius on the band, but the plane itself has no
//  extent, so this was never a leak to patch: the primitive had no concept of
//  a room at all. Any window pointing anywhere near one showed lasers hanging
//  in a room the sweep had never entered.
//
//  So the engine grew a box (level.SetSweepRoom) and this decides what goes
//  in it.
//
//  WHY SCRIPT DECIDES. "Which sectors are one room" is a judgement, not a
//  fact the renderer could look up. A Doom room is almost never one sector --
//  steps, light panels, door tracks, alcoves and platforms are all their own
//  -- and where a room STOPS has no single right answer either. So the rule
//  lives here, in readable code, where it can be argued with.
//
//  THE RULE. Flood out from the sector you are standing in, crossing a line
//  only where a person could actually walk or see through at body height, and
//  stop at anything that reads as a wall between two spaces. That gets the
//  stairs, the alcove and the raised platform -- all obviously the same room
//  -- while stopping at the window, which is the case that started this.
//
//  Outdoors needs no special handling and gets none: a big open area floods
//  to a big box and the lattice fills it. If it is outdoor, it is outdoor.
//
// ============================================================================

class GITD_SweepRoom abstract play
{
	// A hard stop on the flood. A room is a room; a map is not. Without this
	// a single open-plan level floods to its own bounding box, which is the
	// unbounded behaviour this exists to remove, only slower.
	const MAX_SECTORS = 192;

	// How much taller than the player an opening has to be before it counts
	// as somewhere the room continues rather than a gap under a wall.
	const MIN_OPENING = 56.0;

	// Publishes the box around the room containing `from`. Returns false and
	// publishes nothing if there is no sector to stand in.
	static bool Publish(Vector3 from, double soft)
	{
		let start = Sector.PointInSector(from.xy);
		if (!start) return false;

		Array<Sector> open;
		Array<Sector> seen;
		open.Push(start);
		seen.Push(start);

		double lox = from.x, hix = from.x;
		double loy = from.y, hiy = from.y;
		double loz = from.z, hiz = from.z;

		while (open.Size() > 0 && seen.Size() < MAX_SECTORS)
		{
			let sec = open[open.Size() - 1];
			open.Pop();
			if (!sec) continue;

			// The sector's own extent, from its lines -- the only description
			// of a sector's shape ZScript exposes, and an exact one.
			for (int i = 0; i < sec.lines.Size(); i++)
			{
				let l = sec.lines[i];
				Vector2 a = l.v1.p, b = l.v2.p;
				lox = min(lox, min(a.x, b.x));  hix = max(hix, max(a.x, b.x));
				loy = min(loy, min(a.y, b.y));  hiy = max(hiy, max(a.y, b.y));
			}

			// Height at the sector's own centre. Using the planes rather than
			// a stored value keeps sloped floors honest.
			Vector2 c = sec.centerspot;
			loz = min(loz, sec.floorplane.ZAtPoint(c));
			hiz = max(hiz, sec.ceilingplane.ZAtPoint(c));

			// Spread through the openings.
			for (int i = 0; i < sec.lines.Size(); i++)
			{
				let l = sec.lines[i];
				if (!l || !l.backsector || !l.frontsector) continue;

				let nxt = (l.frontsector == sec) ? l.backsector : l.frontsector;
				if (!nxt || nxt == sec) continue;

				if (!Crossable(l)) continue;

				bool have = false;
				for (int s = 0; s < seen.Size(); s++)
				{
					if (seen[s] == nxt) { have = true; break; }
				}
				if (have) continue;

				seen.Push(nxt);
				open.Push(nxt);
			}
		}

		// A margin, so the lattice is not shaved flush against the walls it
		// is supposed to be filling the space between.
		lox -= 16; loy -= 16; loz -= 16;
		hix += 16; hiy += 16; hiz += 16;

		level.SetSweepRoom(lox, loy, loz, hix, hiy, hiz, max(soft, 1.0));
		return true;
	}

	// IS THIS LINE A WAY ON, OR THE EDGE OF THE ROOM?
	//
	// The whole design sits in this one function, and it is deliberately a
	// question about the GAP rather than about flags: a doorway, an archway
	// and a staircase all leave a person-sized opening between the two
	// sectors, and a window, a vent and a parapet do not. That distinction is
	// exactly the one the eye makes, which is why it is the one used here.
	private static bool Crossable(Line l)
	{
		// A line you cannot see or walk through ends the room whatever its
		// geometry says.
		if (l.flags & Line.ML_BLOCKING) return false;
		if (l.flags & Line.ML_BLOCKEVERYTHING) return false;

		let f = l.frontsector, b = l.backsector;
		if (!f || !b) return false;

		// The opening is measured where the two sectors actually meet -- the
		// higher floor to the lower ceiling.
		Vector2 at = (l.v1.p + l.v2.p) * 0.5;
		double floorZ = max(f.floorplane.ZAtPoint(at), b.floorplane.ZAtPoint(at));
		double ceilZ  = min(f.ceilingplane.ZAtPoint(at), b.ceilingplane.ZAtPoint(at));
		if (ceilZ - floorZ < MIN_OPENING) return false;

		// AND THE OPENING HAS TO REACH THE FLOOR. This is the window test,
		// and it is the reason this whole file exists: a window has a real
		// opening, tall enough to walk through if it were at ground level,
		// and a sill under it. A doorway does not. Anything more than a tall
		// step up is a different space you are looking into rather than part
		// of this one.
		double stepUp = abs(b.floorplane.ZAtPoint(at) - f.floorplane.ZAtPoint(at));
		if (stepUp > 48.0) return false;

		return true;
	}
}

// Recompute only when the player changes sector. The flood is cheap for one
// room but it is not free, and standing still should cost nothing at all.
class GITD_SweepRoomTracker : Thinker
{
	private Sector lastSec;
	private int recheck;

	static GITD_SweepRoomTracker Get()
	{
		ThinkerIterator it = ThinkerIterator.Create("GITD_SweepRoomTracker");
		return GITD_SweepRoomTracker(it.Next());
	}

	// new() lands in STAT_DEFAULT, which ticks -- NOT ChangeStatNum, which is
	// the mistake that left GITD_Flashlight silently dead for a long time
	// (see the note on its own Spawn). Map-local is right anyway: the room
	// box means nothing across a level change.
	static GITD_SweepRoomTracker Spawn()
	{
		return GITD_SweepRoomTracker(new("GITD_SweepRoomTracker"));
	}

	override void Tick()
	{
		Super.Tick();

		// Twice a second is far more often than a person changes room, and
		// it means a door opening nearby is picked up without polling every
		// tic for something that changes on foot.
		if (--recheck > 0) return;
		recheck = 18;

		if (!playeringame[consoleplayer]) return;
		let pmo = players[consoleplayer].mo;
		if (!pmo) return;

		if (!GITD_Render.GetB("gitd_ss_room", true))
		{
			// Publishing soft 0 is what removes the bound, so turning this
			// off hands the old unbounded behaviour straight back.
			if (lastSec) { level.SetSweepRoom(0, 0, 0, 0, 0, 0, 0); lastSec = null; }
			return;
		}

		let sec = pmo.cursector;
		if (sec && sec == lastSec) return;
		lastSec = sec;

		GITD_SweepRoom.Publish(pmo.pos,
			GITD_Render.GetF("gitd_ss_room_soft", 96.0));
	}
}
