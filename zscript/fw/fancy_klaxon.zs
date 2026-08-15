// ============================================================================
//  The sweep band, out loud.
// ============================================================================
//
//  Red Alert's ring of light crosses the map every few seconds and has never
//  made a sound. This mounts a klaxon on it, so the alarm sweeps the building
//  audibly the way its light already does -- and mounts it at a PLACE: the
//  ceiling of whichever room the band is currently over. You hear it arrive in
//  the next room, then in yours, then leave.
//
//  It is not a new system and it is not a new cvar. gitd_voice == 3 is the same
//  "the world is on alarm" switch the emitter dialect reads; this is its third
//  clause, and the only one that makes a sound the map's textures did not ask
//  for. It earns that by riding something that already has a position.
//
//  WHY NOT ROUTE IT THROUGH THE MAP'S OWN WALL LIGHTS, which is the more
//  poetic answer -- the alarm literally coming out of the light fittings: it
//  needs a walk over every emitter in the map on each fire to find the ones in
//  the winning sector, and it creates a load-order dependency between two
//  handlers' WorldLoaded, for an outcome the player cannot tell apart from a
//  sound at the ceiling of the same room.
//
//  WHY NOT THE FOG TORNADO, which has an origin and would be the better story:
//  GITD_Handler.PushTornadoAnchor computes its position and throws it away on
//  the next line -- there is no field holding it. Reaching it means writing to
//  GlowHandler.zs and running a persistent actor under SetOrigin every tic. One
//  cached Vector3 in PushTornadoAnchor is all that stands between today and
//  that, and the value is already being computed.
//
// ============================================================================

// A sound at a point, for as long as the sound lasts, and then gone.
class FancySoundSpot : Actor
{
	Default
	{
		-SOLID
		+NOCLIP
		+DONTSPLASH
		+NOTELEPORT
		+NOINTERACTION
		RenderStyle "None";
		radius 1;
		height 1;
	}

	// THE LIFETIME IS NOT TIDY-UP. Destroying an actor stops its channels, so
	// this number is how long the klaxon is ALLOWED to last, not how long the
	// corpse hangs around -- too short and the alarm is cut off mid-blast.
	// 105 tics is three seconds against a 1.75s sample, with room to spare for
	// a pitch this does not currently use.
	//
	// The arithmetic, since a bound nobody checked is a bound nobody can fix:
	// Fire() runs at most once per 36 tics, so at 105 there are at most THREE
	// of these alive at once (t=0, 36, 72; the first is gone before t=108).
	// Only two can ever be SOUNDING, because the sample is 61 tics -- the
	// third spot is an actor holding a channel that already finished. That is
	// the intended ceiling: an alarm passing you should overlap itself once at
	// the edges, not build into a chord.
	States
	{
	Spawn:
		TNT1 A 105;
		stop;
	}
}

class GITD_KlaxonSweep : GITD_SweepEffect
{
	private bool	armed;
	private int		bestIdx;
	private double	bestStr;
	private int		cool;

	override void BeginPass()
	{
		// FIRE FIRST, THEN RESET. There is no EndPass hook -- BeginPass is the
		// only per-tic call this interface offers -- so the winning sector of
		// tic N is first knowable at the top of tic N+1. One tic of latency on
		// a sound that is rate-limited to one per second is not a cost worth a
		// new hook in somebody else's file.
		if (cool > 0)
			cool--;
		else if (armed && bestIdx >= 0 && bestIdx < level.Sectors.Size()
			&& bestStr >= 0.5)
			Fire();

		bestIdx = -1;
		bestStr = 0.0;

		// Read ONCE per tic, not once per sector. SectorPass is called for every
		// sector under every live band, which on a wide wave through a detailed
		// map is hundreds of calls a tic, and CVar.FindCVar is a hash lookup
		// each time.
		armed = FancySettings.GetInt("gitd_voice", 0) == 3;
	}

	// Keep the strongest sector seen this tic. The 0.5 floor in BeginPass is a
	// real threshold and not a nicety: strength falls to 0 at the band's edge,
	// so without it the klaxon would fire from whichever room the band happened
	// to be merely clipping, which is usually not the room it is crossing.
	override void SectorPass(Sector sec, int idx, int band, double strength)
	{
		if (!armed || strength <= bestStr) return;
		bestStr = strength;
		bestIdx = idx;
	}

	private void Fire()
	{
		let sec = level.Sectors[bestIdx];
		Vector2 c = sec.centerspot;
		double cz = sec.ceilingplane.ZAtPoint(c);
		double fz = sec.floorplane.ZAtPoint(c);

		// On the ceiling, where alarms are mounted, but never below head height
		// in a crawlspace -- max() rather than a bare subtraction because a
		// 32-unit-tall duct would otherwise put the klaxon under the floor.
		let s = Actor.Spawn("FancySoundSpot", (c.x, c.y, max(fz + 32.0, cz - 24.0)));

		// ATTN_NORM, deliberately, and it is the whole design. The engine's
		// global rolloff is 200/1200 (wadsrc/static/sndinfo.txt:51), so this is
		// inaudible past 1200 units -- which is what makes it an alarm you hear
		// ARRIVE and hear LEAVE rather than a siren over the whole level. An
		// alarm audible across the map would be an ambience bed with extra
		// steps, which is the one thing this layer must never become.
		if (s) s.A_StartSound("gitd/sweep/klaxon", CHAN_BODY, 0, 1.0, ATTN_NORM);

		cool = 35;
	}
}
