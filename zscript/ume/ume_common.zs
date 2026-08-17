// ============================================================================
//  Universal Map Enhancements -- the third component.
// ============================================================================
//
//  Radiance Control Panel is an umbrella over three things: GITD, FancyWorldV3
//  and this. GITD and the original FancyWorld were merged into one codebase
//  once, and that merge is exactly what most of FancyWorld's restoration this
//  session was spent undoing -- cross-coupled tint, cvars threaded through
//  every preset, a maintenance burden nobody had actually chosen. So this
//  component gets its own settings helper rather than reusing FancySettings,
//  even though the two are ten identical lines: independence here is the
//  point, not an accident of not noticing the duplication.
//
//  CONCEPT ONLY, credited, not copied. The idea that Doom's already-bright
//  decorative props (torches, tech lamps, the burning barrel) deserve a real
//  light and deserve to be breakable comes from looking at Universal Map
//  Enhancements (a Brutal Doom v21 companion pack, BROS_ETT_311), which
//  reskins the same vanilla actors for the same reason. Nothing here is
//  copied from its DECORATE or its assets -- every class below replaces a
//  vanilla actor and inherits ONLY that actor's own IWAD sprite, and the
//  light/break behaviour is GITD's own Shape system, already built and
//  proven this session for exactly this kind of "give the map's own bright
//  things a real light" problem. See README.md for the full credit.
//
// ============================================================================

class UMESettings abstract play
{
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

// ---- shared behaviour for the decoration replacers -------------------------
//
// Static, not a base class: the vanilla actors these replace (TechLamp,
// BurningBarrel, GreenTorch...) share no common ancestor closer than Actor
// itself, and ZScript has no mixins -- a replaces-subclass already spends its
// one inheritance slot on the vanilla class it is replacing, which is the
// whole point (it is what keeps that actor's own IWAD sprite and dimensions).
// So every concrete class below calls into this instead of inheriting from
// it, the same shape FancyLiquidFlourish already uses in fancy_liquids.zs.
class UMEDecorFX abstract play
{
	// A permanent Shape (life 0) at the prop's own light height, tracking it
	// exactly the way FancyEmitter's own fwShapeSlot does since the
	// DynamicLight swap -- one slot, moved rather than re-added, so it keeps
	// its identity (and its place in the eviction order) for as long as the
	// prop stands. Returns the slot so the caller can hold and release it.
	static int Glow(Actor from, Color c, double radius, double intensity)
	{
		if (!UMESettings.GetBool("ume_decorations", true)) return -1;
		if (radius <= 0.0) return -1;

		return level.AddShape(1, 2,
			from.pos.x, from.pos.y, from.pos.z + from.height * 0.6,
			radius, 0.0, 3.0, c, intensity, 0.0);
	}

	// The moment of breaking: the permanent glow above is the caller's to
	// release (it knows its own slot), this only adds the flourish on top --
	// a brightening flash that outgrows and fades the glow it is replacing,
	// plus a small burst of debris. No new sprite: none of these props have
	// a "broken" frame in the IWAD, so the honest thing is a flash and a
	// scatter, then the actor is gone, the same beat as a vanilla explosive
	// barrel minus the explosion.
	static void Shatter(Actor from, Color c, double radius)
	{
		int slot = level.AddShape(1, 2,
			from.pos.x, from.pos.y, from.pos.z + from.height * 0.6,
			radius, 0.0, 3.0, c, 2.4, 0.35);
		if (slot >= 0) level.SetShapeMotion(slot, 0.0, 0.0, radius * 2.5);

		for (int i = 0; i < 10; i++)
		{
			from.A_SpawnParticle(c, SPF_RELATIVE | SPF_FULLBRIGHT,
				30, frandom(2.0, 4.0), 0,
				frandom(-6, 6), frandom(-6, 6), frandom(0, from.height),
				frandom(-1.2, 1.2), frandom(-1.2, 1.2), frandom(0.8, 2.4),
				0, 0, -0.10,
				0.8, 0.016, 0.05);
		}
	}
}
