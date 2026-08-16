// ============================================================================
//  What survives of Environmental FancyWorld.
// ============================================================================
//
//  This used to also hold FancyEmitter, the base class every ambience emitter
//  in zscript/fw/ inherited from -- the texture scan, the four emitter
//  families (walls, floors, ceilings, things), the klaxon and the gitd_voice
//  dialect all came out with it when that layer was removed.
//
//  What is left is the one thing two other systems still reach for: a null-
//  safe cvar read. fancy_steps.zs uses it for the footstep settings, and
//  fw_scan.zs no longer needs it at all now that it is just the liquid index
//  -- but this stays here rather than moving, because footsteps still count
//  as this corner of the mod and a second copy of the same three functions
//  elsewhere is not an improvement.
//
// ============================================================================

// CVar reads, wrapped so a missing cvar is a default and not a crash. Marked
// play because that is the only scope that ever calls it.
class FancySettings abstract play
{
	// The parameter is "cv" and not "name" on purpose -- identifiers here are
	// case-insensitive, so a parameter called name shadows the Name type for
	// the whole body.
	static int GetInt(string cv, int def)
	{
		let c = CVar.FindCVar(cv);
		return c ? c.GetInt() : def;
	}

	static bool GetBool(string cv, bool def)
	{
		let c = CVar.FindCVar(cv);
		return c ? c.GetBool() : def;
	}

	static double GetFloat(string cv, double def)
	{
		let c = CVar.FindCVar(cv);
		return c ? c.GetFloat() : def;
	}
}
