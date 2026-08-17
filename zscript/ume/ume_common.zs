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

	// Only ever used to read gitd_voice (see UMEDecorFX.Pulse) -- a plain
	// CVar read by name, not a call into any FancyWorld/GITD class, so it
	// costs this file nothing of the independence the header above insists
	// on. The active preset's voice is closer to shared world state than to
	// anyone's private variable.
	static int GetInt(string cv, int def)
	{
		let c = CVar.FindCVar(cv);
		return c ? c.GetInt() : def;
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
	// ---- THE SLOT BUDGET IS THE WHOLE DESIGN HERE --------------------------
	//
	// A prop's glow is a PERMANENT Shape (life 0), and permanent shapes are
	// deliberately protected from eviction by the engine's own allocator
	// (ShapeSlot in vmthunks.cpp) -- so a hundred torches would not gracefully
	// degrade, they would exhaust all 128 slots and then start overwriting
	// slot 0, stealing a light some other prop still believes it owns and
	// still intends to release.
	//
	// That budget is shared: kill marks, liquid rings and bubbles, FancyWorld's
	// own emitter lights and these all draw on the same 128. A big hell map can
	// hold sixty torches on its own.
	//
	// So a prop only holds a slot while a player is near enough to see it,
	// exactly as FancyEmitter does since the DynamicLight swap. Nothing is
	// lost by it -- a light nobody is close enough to see was not doing
	// anything with the slot it was holding.
	//
	// Called from the prop's own Tick with its current slot; returns the slot
	// it should hold now. Create-when-wanted, release-when-not, one call site
	// per prop.
	static int GlowUpdate(Actor from, int slot, Color c, double radius,
		double intensity)
	{
		bool wanted = UMESettings.GetBool("ume_decorations", true)
			&& radius > 0.0 && InRange(from);

		if (wanted && slot < 0)
		{
			return level.AddShape(1, 2,
				from.pos.x, from.pos.y, from.pos.z + from.height * 0.6,
				radius, 0.0, 3.0, c, intensity, 0.0);
		}

		if (!wanted && slot >= 0)
		{
			level.RemoveShape(slot);
			return -1;
		}

		return slot;
	}

	// Distance to the viewing player, against the same default FancyWorld uses
	// for its own emitters. Squared, so this never takes a square root -- it
	// runs on every lit prop in the map on the tics the stagger lets through.
	static bool InRange(Actor from)
	{
		if (!playeringame[consoleplayer]) return false;
		let pmo = players[consoleplayer].mo;
		if (!pmo) return false;

		double r = UMESettings.GetFloat("ume_light_range", 2048.0);
		return (pmo.pos - from.pos).LengthSquared() <= r * r;
	}

	// The range check is not worth running every tic on every prop, and a
	// light appearing a third of a second late at 2048 units away is not
	// something anyone can see. Each prop gets its own starting phase so a
	// corridor of sixteen torches does not do all of its checking on the
	// same tic.
	const CHECK_PERIOD = 15;

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

	// A BREATHING light rather than a steady one, for the two props that are
	// an ominous THING more than a light fixture (EvilEye, FloatingSkull).
	// There is no oscillating parameter on a Shape -- grow only ever moves
	// one direction -- so this fakes a pulse the same way a heartbeat reads
	// as continuous from discrete beats: the caller's own Tick() re-invokes
	// this every 12-20 tics with a life longer than that interval, so the
	// next swell starts before the last one has finished fading and the
	// light never actually goes dark between calls.
	//
	// Not tracked or released on destroy like Glow's slot is -- every pulse
	// is already short-lived and self-expiring, so there is nothing to leak.
	static void Pulse(Actor from, Color c, double radius, double intensity)
	{
		// Range-gated for the same reason the steady glow is, and it matters
		// MORE here, not less: a pulse spends a fresh slot every time it
		// fires, so an idol across the map would be churning the budget
		// several times a second for something nobody can see.
		if (!UMESettings.GetBool("ume_decorations", true)) return;
		if (!InRange(from)) return;

		int slot = level.AddShape(1, 2,
			from.pos.x, from.pos.y, from.pos.z + from.height * 0.6,
			radius, 0.0, 3.0, c, intensity, 1.15);
		if (slot >= 0) level.SetShapeMotion(slot, 0.0, 0.0, radius * 0.3);
	}
}
