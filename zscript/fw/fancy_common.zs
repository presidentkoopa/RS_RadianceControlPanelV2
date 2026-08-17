// ============================================================================
//  Environmental FancyWorld -- the shared emitter.
// ============================================================================
//
//  Every Fancy* actor in this mod used to be the same twenty lines pasted
//  again with one sound name changed: a CountProximity() dedup, a looping
//  A_PlaySound, and then APLS A -1 forever. Fourteen wall classes, ten floor
//  and ceiling classes, all identical.
//
//  They all live on this base now. A subclass says WHAT it is -- a sound, a
//  light, a puff of particles -- and this file decides WHEN any of that
//  happens. Adding a new kind of ambience is six lines instead of twenty, and
//  a fix to the timing is a fix everywhere at once.
//
//  Two things changed behaviourally, both on purpose:
//
//  1. THE WALL EMITTERS NOW CULL BY RANGE. They never did. Every waterfall,
//     computer and wall light in the map held a live looping sound channel
//     from the moment the map loaded, whether you were next to it or half a
//     kilometre away. The floor emitters always culled at 2048 -- the wall
//     ones just never got the same treatment. This is a straight win: fewer
//     live channels, and the mixer stops fighting for voices.
//
//  2. THEY EMIT LIGHT AND PARTICLES, not just noise. The scan that finds all
//     this is the expensive part and it was already being paid for -- the mod
//     knows every lavafall, every broken monitor, every lit ceiling flat in
//     the map. It was spending all of that on audio alone.
//
//  A THIRD THING CHANGED LATER (2026-08-17): the light stopped being a real
//  DynamicLight. A_AttachLight/A_RemoveLight put every lit emitter on the
//  engine's own dynamic-light budget -- exactly the cost Sector Sweep and
//  the beams stopped paying years ago by asking the fragment shader a
//  question instead of placing an object. level.AddShape is that same
//  question, already proven by kill marks and Standing Shapes: a slot in a
//  128-entry array read once a frame, not a live light every draw call has
//  to account for. See fwShapeSlot and the wantLight arm in FancyUpdate.
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

class FancyEmitter : Actor
{
	// Set by the scanner in the window between Spawn() and this actor's first
	// tick, for textures that carry their own colour. The LITE* family is the
	// whole reason this exists: the map already tells us LITEBLU1 is blue and
	// LITERED1 is red, so the light should not be one averaged compromise.
	Color	fwTint;
	bool	fwHasTint;

	private bool	fwAudible;
	private bool	fwLit;
	private int		fwClock;

	// [BB] THE WORLD'S DIALECT.
	//
	// gitd_voice adds no sound source anywhere. Every emitter it touches was
	// already in the room, at a place you could walk to; this changes only
	// what that place SAYS. Cold War does not put a hum in the air -- it
	// changes what the map's own computers sound like.
	//
	// These fields exist because of the trap, which is worth stating in full:
	// FancyUpdate starts a loop ONLY on the out-of-range -> in-range edge, so
	// returning a different name from FancySound() does nothing at all to an
	// emitter you are currently standing next to. It would re-read when you
	// walked fw_range away and came back. Guarded, never errors, silently
	// does not happen -- and the whole feature would have looked like it
	// worked, because walking away and back is exactly what testers do.
	//
	// fwVoiceSnd is the second half of that and it is not redundant with
	// fwVoice. It holds the sound this emitter is ACTUALLY playing, so the
	// swap below can ask "did my voice change" rather than "did the world's
	// voice change". Most emitters have nothing to say about gitd_voice, and
	// without this every one of them would eat a StopSound plus a StartSound
	// on every preset change -- including the genuinely silent ones, where
	// both calls are no-ops that only look like they mean something. See the
	// swap arm in FancyUpdate.
	private int		fwVoice;
	private Sound	fwVoiceSnd;

	// [BB] DETUNE, so a wall of waterfalls is a waterfall.
	//
	// A big fall or a long computer bank puts a dozen emitters within earshot
	// of each other, all playing the SAME lump at the SAME pitch. Identical
	// copies of one waveform do not sound like more of it -- they comb-filter,
	// and the result is a flat electronic drone that sits still while you move
	// your head. In VR that is the single most artificial thing the mod does.
	//
	// A few percent of pitch spread per emitter is enough to break it up: the
	// copies drift against each other instead of locking, and the same set of
	// loops reads as one large moving body of sound. The volume jitter stops
	// the ones behind you from being exactly as present as the ones in front.
	//
	// Chosen once at spawn, not per loop, or it would warble.
	private double	fwPitch;
	private double	fwVol;

	// [BB] OCCLUSION.
	//
	// Until now the only thing between you and an emitter was DISTANCE. A
	// waterfall behind a sealed steel door was exactly as loud as one in open
	// air the same distance away, which is the single biggest reason the
	// ambience read as a layer over the game rather than as part of the room.
	//
	// A sight line is not the same as an acoustic path -- sound goes round
	// corners and under doors, which is why losing sight DUCKS this rather
	// than muting it. A waterfall down a bent corridor should still reach you,
	// just not as though it were in front of your face.
	//
	// EASED, not switched. The trace runs at the same slow rate as everything
	// else here, and a hard step between two volumes on a looping sound is a
	// click you cannot un-hear once you have noticed it. This walks.
	private double	fwOccl;      // where the volume actually is, 0..1
	private double	fwOcclTgt;   // where the sight test says it should be

	// [BB] THE LIGHT IS A SHAPE NOW, NOT A DYNAMICLIGHT.
	//
	// A_AttachLight was a real per-actor GZDoom dynamic light, and every one
	// of them competes for the engine's own dynamic-light budget -- the exact
	// thing Sector Sweep and the beams stopped doing years ago by asking the
	// fragment shader a question instead of placing an object. level.AddShape
	// is that same question, already proven (kill marks, Standing Shapes),
	// and it costs a slot in a 128-entry array read once a frame rather than
	// a live light some renderer has to account for every draw.
	//
	// -1 = no slot held. Tracked here rather than inferred from fwLit alone
	// because RemoveShape needs the actual slot number, and AddShape hands
	// that back once, at attach time.
	private int		fwShapeSlot;

	Default
	{
		-SOLID
		-NOCLIP
		+DONTSPLASH
		+NOTELEPORT
		+NOINTERACTION
		+MOVEWITHSECTOR
		RenderStyle "None";
		radius 1;
		height 1;
	}

	// ---- What this emitter IS. Subclasses answer; nothing else overrides. --

	// The looping ambience. Empty means silent.
	//
	// A subclass may answer differently depending on FancyVoice(). It is read
	// again on every voice change, not only at spawn -- see FancyUpdate.
	virtual Sound FancySound() { return ""; }

	// Which dialect the world is speaking. Read here rather than in five
	// separate FancySound() overrides so there is one spelling of the cvar
	// name in the whole layer.
	//
	//   0 the map's own voice, 1 cold, 2 labouring, 3 alarm, 4 wrong.
	//
	// Every value has a menu entry -- see OptionValue "GITDVoice". A value
	// reachable only from the console is a value nobody will ever see.
	int FancyVoice() { return FancySettings.GetInt("gitd_voice", 0); }

	// -1 for no light, any other value for one. USED ONLY AS A SIGN NOW.
	// Before the Shapes swap this selected a DynamicLight.ELightType
	// (PulseLight/FlickerLight/RandomFlickerLight/PointLight); FancyUpdate
	// no longer reads the value for that, only whether it is >= 0, because a
	// Shape has no equivalent "light type" -- it has one look, not four.
	// Subclasses returning a specific ELightType still compile and still
	// gate correctly; the distinction between which one just stopped
	// mattering.
	//
	// FancyLightRadius2 and FancyLightParam -- the old secondary radius and
	// GLDEFS third parameter -- are gone entirely, along with every
	// subclass override of them, now that a Shape has nothing to hand
	// either one to.
	virtual int FancyLightType() { return -1; }
	virtual Color FancyLightColor() { return 0xFFFFFF; }
	virtual int FancyLightRadius() { return 0; }

	// How much of a light this is, against fw_light_detail:
	//   1 = the map already implies a light source here. A lit ceiling flat,
	//       a wall light texture, a lavafall. Turning these on is closer to
	//       fixing an omission than to adding an effect.
	//   2 = flavour. Humming computers, glowing slime, the creepy face.
	virtual int FancyLightTier() { return 2; }

	// Chance out of 256, per ~6-tic pass, that FancyPuff() runs. 0 = never.
	virtual int FancyPuffRate() { return 0; }
	virtual void FancyPuff() { }

	// AN OCCASIONAL ONE-SHOT THAT IS NOT A PARTICLE, and it is a separate hook
	// for one reason: FancyPuff is gated on fw_particles.
	//
	// That gate is correct for everything that was using FancyPuff before now,
	// because for those classes the sound IS the particle -- a nukage bubble
	// pops, a lava bubble bursts, hot rock hisses under its own smoke. Turn
	// particles off and there is nothing there to make a noise.
	//
	// A dripping wall is not that. Its drip is the only sound it has, and
	// hanging it off FancyPuff would mean a player who turned particles down
	// lost an emitter's entire voice with nothing to tell them so -- guarded,
	// never errors, silently does not happen. That is this project's signature
	// bug and it is cheaper to not write it than to find it later.
	//
	// Same units as FancyPuffRate: chance out of 256 per ~6-tic pass. NOT
	// scaled by fw_particle_scale, because this is not a particle.
	virtual int FancyOneShotRate() { return 0; }
	virtual void FancyOneShot() { }

	// ---- When any of it happens ------------------------------------------

	// Cheap, and deliberately 2D. These are room-scale ambiences, not gunshots
	// -- a waterfall two floors up is still a waterfall you can hear, and
	// paying for a Z term to decide otherwise would be paying to be wrong.
	private bool FancyNearPlayer(double range)
	{
		double r2 = range * range;
		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playeringame[i]) continue;
			let mo = players[i].mo;
			if (!mo) continue;
			if ((mo.pos.xy - pos.xy).LengthSquared() <= r2) return true;
		}
		return false;
	}

	void FancyUpdate()
	{
		double range = FancySettings.GetFloat("fw_range", 2048.0);
		bool near = FancyNearPlayer(range);
		int voice = FancyVoice();

		if (near && !fwAudible)
		{
			// An empty sound here is a no-op, which is how the silent
			// emitters get away with not overriding FancySound at all --
			// the blood drips, for one, which fire one-shots on CHAN_VOICE
			// and have no loop to start.
			fwVoiceSnd = FancySound();
			A_StartSound(fwVoiceSnd, CHAN_BODY, CHANF_LOOPING,
				fwVol, ATTN_NORM, fwPitch);
		}
		else if (!near && fwAudible)
		{
			A_StopSound(CHAN_BODY);
		}
		else if (near && voice != fwVoice)
		{
			// Already singing, and the dialect changed underneath it.
			//
			// Re-issuing on the same channel replaces the loop in place --
			// s_sound.cpp:545 stops whatever CHAN_BODY held before starting
			// the new one -- so there is no destroy and no second voice. It
			// is a hard cut rather than a crossfade, and it stays that way:
			// a crossfade needs a second channel, and CHAN_BODY is the only
			// one an emitter owns.
			//
			// The name compare is the guard. Most emitters have nothing to
			// say about gitd_voice and return the same sound they already
			// hold, so for them this whole arm is one virtual call and one
			// int compare -- no channel is touched when nothing changed.
			Sound snd = FancySound();
			if (snd != fwVoiceSnd)
			{
				A_StopSound(CHAN_BODY);

				// fwVol * fwOccl, NOT fwVol. A_StartSound resets the channel
				// to whatever volume it was handed, and FancyEaseOcclusion
				// walks back at only 0.08 a pass, so starting at the un-ducked
				// value would give an occluded emitter half a second of
				// shouting through the wall it is behind. It is one multiply.
				if (snd != 0)
					A_StartSound(snd, CHAN_BODY, CHANF_LOOPING,
						fwVol * fwOccl, ATTN_NORM, fwPitch);

				fwVoiceSnd = snd;
			}
		}

		// Assigned on every pass, in range or not, so an emitter that was far
		// away when the preset changed comes back in the new voice by the
		// normal start path above and never fires a spurious swap.
		//
		// The half-second ripple this produces is a feature and not latency.
		// FancyUpdate runs at ~2Hz and every emitter was staggered 1-6 tics at
		// spawn, so a preset change crosses a room as a ragged wave of
		// machines changing note rather than as one hard cut on a single tic.
		fwVoice = voice;

		// Tracked whether or not there was a sound: it is also what gates
		// particles, so a silent emitter still needs it.
		fwAudible = near;

		// The trace only runs for things you can currently hear, which is what
		// keeps it affordable -- an emitter out of range costs nothing, and
		// the ones in range are a small set.
		fwOcclTgt = 1.0;
		if (near && FancySettings.GetBool("gitd_occlusion", true))
		{
			let ear = FancyEarPos();
			if (ear && !CheckSight(ear))
				fwOcclTgt = clamp(FancySettings.GetFloat("gitd_occlusion_amount", 0.45), 0.0, 1.0);
		}

		// The light follows the same range as the sound. Attaching and
		// removing rather than leaving hundreds of lights live across the map
		// is the entire reason this is affordable at all.
		int type = FancyLightType();
		bool wantLight = near
			&& type >= 0
			&& FancySettings.GetBool("fw_lights", true)
			&& FancySettings.GetInt("fw_light_detail", 2) >= FancyLightTier();

		if (wantLight && !fwLit)
		{
			Color c = fwHasTint ? fwTint : FancyLightColor();
			double scale = FancySettings.GetFloat("fw_light_scale", 1.0);

			// kind 1 (disc), orient 2 (any nearby surface) -- every emitter
			// this base serves is already sitting flush against real
			// geometry (a wall light is ON the wall, a liquid glow is ON
			// the floor), never floating free, so there is no case here
			// that needs Standing Shapes' full plane math. "Any" rather
			// than picking floor/wall/ceiling per class is a deliberate
			// simplification: it costs nothing extra and there is no
			// FancyEmitter subclass that sits at a boundary ambiguous
			// enough for it to matter.
			fwShapeSlot = level.AddShape(
				1, 2,
				pos.x, pos.y, pos.z,
				max(FancyLightRadius() * scale, 1.0),
				0.0, 4.0,
				c, 1.4, 0.0);
			fwLit = true;
		}
		else if (!wantLight && fwLit)
		{
			if (fwShapeSlot >= 0) level.RemoveShape(fwShapeSlot);
			fwShapeSlot = -1;
			fwLit = false;
		}
		else if (wantLight && fwLit && fwShapeSlot >= 0)
		{
			// Range didn't change but the map or a preset might have moved
			// the tint/colour under it (voice changes do not touch colour,
			// but a future FancyLightColor() override reasonably could) --
			// MoveShape is nearly free, so just re-assert position every
			// pass rather than add a second dirty flag nothing sets yet.
			level.MoveShape(fwShapeSlot, pos.x, pos.y, pos.z);
		}
	}

	// Whoever the sound is being mixed for. Same answer as the fog director's
	// viewer, and for the same reason -- there is one pair of ears.
	private Actor FancyEarPos()
	{
		if (!playeringame[consoleplayer]) return null;
		return players[consoleplayer].mo;
	}

	// Walks the volume toward whatever the last sight test asked for. Runs at
	// the state's own rate rather than the trace's, so the ramp is smooth even
	// though the test behind it is not.
	private void FancyEaseOcclusion()
	{
		if (!fwAudible) return;

		double was = fwOccl;
		fwOccl += clamp(fwOcclTgt - fwOccl, -0.08, 0.08);

		// Only touch the channel when it actually moved. A_SoundVolume on an
		// unchanged value every six tics is pure churn.
		if (abs(fwOccl - was) > 0.001)
			A_SoundVolume(CHAN_BODY, fwVol * fwOccl);
	}

	private void FancyTick()
	{
		FancyEaseOcclusion();

		// The range check is the only part with any real cost, so it runs at
		// about 2Hz rather than every pass. Ambience has no business reacting
		// faster than that anyway.
		if (--fwClock <= 0)
		{
			fwClock = 3;
			FancyUpdate();
		}

		if (!fwAudible) return;

		// Above the particle gate, deliberately. See FancyOneShotRate.
		int oneshot = FancyOneShotRate();
		if (oneshot > 0 && random(0, 255) < oneshot) FancyOneShot();

		int rate = FancyPuffRate();
		if (rate <= 0) return;
		if (!FancySettings.GetBool("fw_particles", true)) return;

		rate = int(rate * FancySettings.GetFloat("fw_particle_scale", 1.0));
		if (rate > 0 && random(0, 255) < rate) FancyPuff();
	}

	// A DynamicLight died with the actor it was attached to, automatically --
	// that guarantee does not exist here. A Shape slot is a plain array
	// entry on FLevelLocals with no idea an actor was ever involved, so an
	// emitter that gets Thing_Remove'd (or anything else that skips the
	// range-based release above) while lit would hold its slot forever.
	override void OnDestroy()
	{
		if (fwShapeSlot >= 0) level.RemoveShape(fwShapeSlot);
		fwShapeSlot = -1;
		Super.OnDestroy();
	}

	States
	{
	Spawn:
		TNT1 A 0;
		// Stagger. Without this every emitter in the map runs its range check
		// on the same tic, which is a visible hitch on a big map rather than
		// a cost spread across six of them.
		TNT1 A 0 A_SetTics(random(1, 6));
		// fwOccl starts open, not closed: a sound begins at the volume
		// A_StartSound was given and ducks from there if the sight test says
		// so. Starting it at zero would fade every emitter in from silence.
		TNT1 A 0
		{
			fwPitch = frandom(0.92, 1.08);
			fwVol   = frandom(0.85, 1.0);
			fwOccl  = 1.0;
			fwOcclTgt = 1.0;
			fwShapeSlot = -1;
		}
		TNT1 A 0 { FancyUpdate(); }
	Idle:
		TNT1 A 6 { FancyTick(); }
		loop;
	Remove:
		TNT1 A 0;
		stop;
	}
}
