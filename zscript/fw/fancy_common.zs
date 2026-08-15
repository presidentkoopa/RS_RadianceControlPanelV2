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
	virtual Sound FancySound() { return ""; }

	// -1 for no light. Otherwise a DynamicLight.ELightType.
	virtual int FancyLightType() { return -1; }
	virtual Color FancyLightColor() { return 0xFFFFFF; }
	virtual int FancyLightRadius() { return 0; }
	virtual int FancyLightRadius2() { return 0; }

	// Third GLDEFS parameter, and it means something different per type:
	// seconds for PulseLight, 0..1 chance for FlickerLight, tics for
	// RandomFlickerLight. Ignored by PointLight.
	virtual double FancyLightParam() { return 0.0; }

	// How much of a light this is, against fw_light_detail:
	//   1 = the map already implies a light source here. A lit ceiling flat,
	//       a wall light texture, a lavafall. Turning these on is closer to
	//       fixing an omission than to adding an effect.
	//   2 = flavour. Humming computers, glowing slime, the creepy face.
	virtual int FancyLightTier() { return 2; }

	// Chance out of 256, per ~6-tic pass, that FancyPuff() runs. 0 = never.
	virtual int FancyPuffRate() { return 0; }
	virtual void FancyPuff() { }

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

		if (near && !fwAudible)
		{
			// An empty sound here is a no-op, which is how the silent
			// emitters get away with not overriding FancySound at all --
			// hot rock, for one, which only hisses occasionally and has no
			// loop to start.
			A_StartSound(FancySound(), CHAN_BODY, CHANF_LOOPING,
				fwVol, ATTN_NORM, fwPitch);
		}
		else if (!near && fwAudible)
		{
			A_StopSound(CHAN_BODY);
		}

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
			A_AttachLight('fancy', type, c,
				int(FancyLightRadius() * scale),
				int(FancyLightRadius2() * scale),
				DynamicLight.LF_ATTENUATE,
				(0, 0, 0),
				FancyLightParam());
			fwLit = true;
		}
		else if (!wantLight && fwLit)
		{
			A_RemoveLight('fancy');
			fwLit = false;
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

		int rate = FancyPuffRate();
		if (rate <= 0) return;
		if (!FancySettings.GetBool("fw_particles", true)) return;

		rate = int(rate * FancySettings.GetFloat("fw_particle_scale", 1.0));
		if (rate > 0 && random(0, 255) < rate) FancyPuff();
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
