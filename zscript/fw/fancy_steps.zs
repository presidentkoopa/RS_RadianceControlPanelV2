// ============================================================================
//  Environmental FancyWorld -- footsteps.
// ============================================================================
//
//  Doom has never had them. Not quiet ones, not generic ones -- the player
//  makes no sound at all when walking, and has not since 1993.
//
//  On a flat screen you do not notice, because you are not walking. In VR you
//  physically are, and your own feet being the only silent thing in a room
//  full of ambience is the loudest hole in this mod.
//
//  The lookup is nothing: the flat under you, through the same table
//  machinery every other part of this uses. The reason it was not done sooner
//  is that there were no samples to point it at.
//
// ============================================================================

class FancyFootsteps : EventHandler
{
	private FancyTexTable stepTable;

	// How far you have walked since the last footfall. Distance rather than a
	// timer, so the rate follows your actual speed for free -- walking,
	// running and being shoved by a blast all come out right without any of
	// them being special-cased.
	private double	strideRun;

	// Last flat we resolved, so a step does not repeat the table lookup when
	// nothing under you has changed.
	private int		lastRow;
	private Name	lastKind;

	override void WorldLoaded(WorldEvent e)
	{
		stepTable = FancyTexTable.BuildSteps();
		strideRun = 0;
		lastRow = -1;
		lastKind = 'hard';
	}

	override void WorldTick()
	{
		if (!FancySettings.GetBool("gitd_steps", true)) return;
		if (!playeringame[consoleplayer]) return;

		let pmo = players[consoleplayer].mo;
		if (!pmo || pmo.health <= 0) return;

		// AIRBORNE FEET MAKE NO SOUND. Also covers flying, noclip and being
		// launched, all of which otherwise produce a run of steps out of
		// nothing while you sail across the room.
		if (pmo.pos.z > pmo.floorz + 2.0) { strideRun = 0; return; }
		if (pmo.bNoGravity || pmo.bFly) { strideRun = 0; return; }

		// Horizontal only. Riding a lift is not walking.
		double moved = pmo.vel.xy.Length();
		if (moved < 0.35) { strideRun = max(0.0, strideRun - 0.6); return; }

		strideRun += moved;

		double stride = max(16.0, FancySettings.GetFloat("gitd_steps_stride", 52.0));
		if (strideRun < stride) return;
		strideRun -= stride;

		Step(pmo);
	}

	// 0..1, varying per step. Mixes the tic with where the foot landed, so two
	// steps in the same spot at different times differ and two steps at the
	// same time in different places differ. Multipliers are odd primes that
	// fit in a signed 32-bit int; the wrap on overflow is the point.
	private double StepJitter(Actor pmo)
	{
		int h = level.maptime * 1103515245
		      + int(pmo.pos.x) * 12345
		      + int(pmo.pos.y) * 6789;
		return ((h >> 9) & 1023) / 1023.0;
	}

	private void Step(Actor pmo)
	{
		let sec = pmo.cursector;
		if (!sec) return;

		int row = stepTable.Find(sec.GetTexture(Sector.floor));
		if (row != lastRow)
		{
			lastRow = row;
			// Row 0 means the flat is not in the table at all, which is most
			// of them. Concrete is the right guess for a game built out of
			// tech bases.
			lastKind = (row == 0) ? 'hard' : stepTable.RowClass(row);
		}

		double vol = clamp(FancySettings.GetFloat("gitd_steps_volume", 1.0), 0.0, 2.0);
		if (vol <= 0.01) return;

		// Pitch spread per step, for the same reason the emitters are detuned:
		// the same sample twice in a row is a sample, three times is a loop.
		// 'flesh' has exactly one sample, so it gets a wider spread to carry
		// the variety the others get from having six.
		double lo = (lastKind == 'flesh') ? 0.82 : 0.93;
		double hi = (lastKind == 'flesh') ? 1.18 : 1.07;

		// NOT frandom. random()/frandom() are Actor-scope intrinsics -- there
		// is no use of either from an EventHandler anywhere in this engine's
		// own ZScript or in this mod, and they are not declared in base.zs.
		// This is an EventHandler, so the spread comes from a cheap hash of
		// the tic and the position instead. For a footstep that is
		// indistinguishable from random, and it cannot fail to compile.
		double pitch = lo + (hi - lo) * StepJitter(pmo);

		// Switched rather than built by concatenation. A Name pasted onto a
		// string is not a Sound, and the compiler is right to say so.
		switch (lastKind)
		{
		case 'metal':  pmo.A_StartSound("world/step/metal",  CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		case 'grate':  pmo.A_StartSound("world/step/grate",  CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		case 'wood':   pmo.A_StartSound("world/step/wood",   CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		case 'dirt':   pmo.A_StartSound("world/step/dirt",   CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		case 'gravel': pmo.A_StartSound("world/step/gravel", CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		case 'rock':   pmo.A_StartSound("world/step/rock",   CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		case 'tile':   pmo.A_StartSound("world/step/tile",   CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		case 'carpet': pmo.A_StartSound("world/step/carpet", CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		case 'snow':   pmo.A_StartSound("world/step/snow",   CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		case 'flesh':  pmo.A_StartSound("world/step/flesh",  CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		case 'splash': pmo.A_StartSound("world/step/splash", CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		default:       pmo.A_StartSound("world/step/hard",   CHAN_AUTO, 0, vol, ATTN_NORM, pitch); break;
		}
	}
}
