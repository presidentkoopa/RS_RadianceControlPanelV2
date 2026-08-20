// === FLASHLIGHT ===
//
// A volumetric flashlight: the beam is visible in the air, not just the disc
// where it lands. The cone itself is drawn by the engine as a postprocess
// pass (Level.SetVolumetricBeam) -- everything here decides where it points,
// what colour it is, and what else it lights.
//
// Four mounts. In VR each hand has its own tracked pose, so mainhand and
// offhand are genuinely different places rather than the same light nudged
// sideways. Head and chest hang off the view instead, which is what you want
// when both hands are busy.
//
// Nothing here is a pickup: you always have it. It cannot be dropped, taken,
// or run out.

class GITD_Flashlight : Thinker
{
	// The dynamic light doing the surface lighting. The volumetric cone is
	// the engine's; this is what actually brightens what the beam lands on.
	Actor beamLight;
	Actor bounceLight;

	// Colour cycling, same shape as a glow lane.
	int slotIndex;
	Color fromCol, toCol;
	double phase;
	int holdLeft;   // tics parked on the current colour, per-slot fl_holdN

	// ---- THE BEAM LAGS ---------------------------------------------------
	//
	// It used to snap. Position and direction were resolved from the mount and
	// published the same tic, so the cone was welded to your aim and arrived
	// wherever you were looking on the frame you looked there.
	//
	// That is correct for a laser and wrong for a torch. A real one has mass
	// and is held in a hand at the end of an arm: you turn, and it catches up.
	// Snapping reads as a light glued to the camera rather than a thing you
	// are carrying -- and in VR, where your head and the torch move
	// independently, it is the difference between holding a torch and wearing
	// one.
	//
	// Smoothed exponentially toward the target rather than sprung, and
	// deliberately so: a spring OVERSHOOTS, and a torch beam that swings past
	// what you aimed at and comes back is a torch on a rope. This only ever
	// approaches.
	//
	// Both ends lag, and they lag DIFFERENTLY. The origin is your hand and
	// barely moves relative to you, so it is nearly rigid; the far end sweeps
	// metres for the same wrist turn, which is where the whole sense of weight
	// lives. Lagging only the direction is what makes it read as the beam
	// bending rather than the whole torch sliding.
	private Vector3 smPos, smDir;
	private bool smPrimed;

	static GITD_Flashlight Get()
	{
		ThinkerIterator it = ThinkerIterator.Create("GITD_Flashlight");
		return GITD_Flashlight(it.Next());
	}

	static GITD_Flashlight Spawn()
	{
		// NO ChangeStatNum HERE, AND THAT LINE IS WHY THIS NEVER WORKED.
		//
		// It parked itself at STAT_STATIC, which is 5. RunThinkers only walks
		// statnums from STAT_FIRST_THINKING (32) upward, so STAT_STATIC is a
		// storage slot rather than a thinking one -- Tick() had never executed
		// a single time. No cone, no beam light, no bounce, and every control
		// on the Flashlight page adjusting nothing.
		//
		// It went unnoticed because DarkDoomZ shipped a SECOND flashlight that
		// did work, so there was always a torch. Removing that duplicate is
		// what exposed this.
		//
		// new() already places a Thinker in STAT_DEFAULT, which ticks. That
		// makes it map-local rather than persistent, which is correct anyway:
		// GITD_FlashlightHandler.WorldLoaded respawns it every map.
		let f = GITD_Flashlight(new("GITD_Flashlight"));
		f.slotIndex = 0;
		f.phase = 0;
		f.fromCol = f.SlotColor(0);
		f.toCol = f.SlotColor(1);
		return f;
	}

	Color SlotColor(int n)
	{
		if (CVar.FindCVar("fl_random").GetBool()) return GITD_Palette.RandomColor();

		int count = clamp(CVar.FindCVar("fl_slots").GetInt(), 1, 8);
		int which = (n % count) + 1;
		// Color(int) does NOT convert on this engine -- it compiles and then
		// fails at load with "Return type Color mismatch with SInt4", which
		// leaves this function returning nothing usable and the colour it was
		// asked for silently unset. Build the Color from its bytes instead;
		// that is unambiguous and needs no implicit conversion.
		int packed = CVar.FindCVar("fl_c" .. which).GetInt();
		return Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);
	}

	// One steady colour is the common case, so skip the whole transition
	// machine rather than crossfading a colour to itself every tic.
	Color CurrentColor()
	{
		int count = clamp(CVar.FindCVar("fl_slots").GetInt(), 1, 8);
		if (count <= 1) return SlotColor(0);

		int pattern = CVar.FindCVar("fl_pattern").GetInt();
		// Same hold mechanic as the glow lanes: while a hold runs the phase
		// clock stands still, and at phase 0 every pattern returns fromCol.
		if (holdLeft > 0) holdLeft--;
		else phase += CVar.FindCVar("fl_speed").GetFloat();
		if (phase >= 1.0)
		{
			phase -= 1.0;
			slotIndex = (slotIndex + 1) % count;
			fromCol = toCol;
			int nextSlot = (pattern == 4 && (slotIndex % 2) == 1)
				? (slotIndex + count - 1) % count
				: (slotIndex + 1) % count;
			toCol = SlotColor(nextSlot);
			holdLeft = int(CVar.FindCVar("fl_hold" .. (slotIndex + 1)).GetFloat() * 35.0);
			if (holdLeft > 0) phase = 0.0;
		}

		switch (pattern)
		{
			default:
			case 0: return fromCol;
			case 1:
			case 4:
			{
				double t = 0.5 - 0.5 * cos(phase * 180.0);
				return GITD_Palette.Lerp(fromCol, toCol, t);
			}
			case 2:
			{
				double t = min(1.0, phase * 3.0);
				return GITD_Palette.Lerp(fromCol, toCol, t);
			}
			case 3:
			{
				double t = 0.5 - 0.5 * cos(phase * 180.0);
				Color c = GITD_Palette.Lerp(fromCol, toCol, t);
				return GITD_Palette.Scale(c, 0.35 + 0.65 * abs(cos(phase * 180.0)));
			}
		}
	}

	// Where the light sits and which way it faces. The two hand mounts read
	// their own tracked pose; head and chest hang off the view.
	//
	// Flip: rolling your wrist far enough that the torch is upside-down means
	// you are almost certainly pointing it backwards over your shoulder, so
	// the beam is turned to follow the intent rather than the geometry.
	// MULTIPLE RETURN, NOT out PARAMS.
	//
	// `out Vector3` is not supported by this VM at all. The compiler tags it
	// REGT_FLOAT|REGT_ADDROF|REGT_MULTIREG3 and NOTHING handles that
	// combination: the JIT falls through to "Unknown REGT value passed to
	// EmitPARAM" (jit_call.cpp), and the interpreter it falls back to refuses
	// outright with "REGT_ADDROF not implemented for vectors" (vmexec.h).
	//
	// That JIT line at load was never the bug -- it was the WARNING. The
	// interpreter it announced would have hard-errored the first time this ran.
	// It never ran, so nobody found out. See the statnum note in Spawn().
	//
	// `out double` is fine, which is why GITD_Presets.Params gets away with it:
	// one register, no MULTIREG tag.
	//
	// THE HAND POSES ARE NOT WORLD SPACE, AND THAT IS THE WHOLE BUG.
	//
	// AttackAngle and OffhandAngle are stored as world yaw MINUS 90 degrees,
	// and AttackPitch/OffhandPitch are stored NEGATED. The engine says so in
	// its own words (g_game.cpp:1237) and writes them that way in both the VR
	// and the flatscreen path (hw_vrmodes.cpp:1170, :1192).
	//
	// Every other consumer converts on the way out -- hw_weapon.cpp:431 is the
	// canonical two lines, and hw_vrwheel.cpp and p_actionfunctions.cpp each
	// carry their own copy. This read them raw.
	//
	// So the cone was aimed ninety degrees to your RIGHT and flipped vertically
	// -- pointing where you would be looking if you turned your head a quarter
	// turn and then looked the other way up. It was never once pointed at what
	// you were looking at, at any pitch, on any frame.
	//
	// That is why it looked radial rather than directional. It is a real cone,
	// with a real 6-26 degree half-angle, aimed somewhere you never look: the
	// only part of it you ever saw was the wash at the apex, which sits exactly
	// at your eye with a thousand-unit reach. A lamp you are standing inside.
	//
	// Head and chest were always correct, because those two read pmo.angle and
	// pmo.pitch, which ARE world space. That is the proof the vector maths at
	// the bottom of this function was never the problem.
	//
	Vector3, Vector3 ResolveMount(PlayerPawn pmo)
	{
		Vector3 pos, dir;
		int mount = CVar.FindCVar("fl_mount").GetInt();
		double ang, pit, rol;

		if (mount == 1)          // offhand
		{
			pos = pmo.OffhandPos;
			ang = pmo.OffhandAngle + 90;
			pit = -pmo.OffhandPitch;
			rol = pmo.OffhandRoll;
		}
		else if (mount == 2)     // head
		{
			pos = (pmo.pos.x, pmo.pos.y, pmo.player.viewz);
			ang = pmo.angle;
			pit = pmo.pitch;
			rol = 0;
		}
		else if (mount == 3)     // chest -- below the eyes, so the beam sits
		{                        // where a chest rig would, not where you look
			pos = (pmo.pos.x, pmo.pos.y, pmo.player.viewz - 16);
			ang = pmo.angle;
			pit = pmo.pitch;
			rol = 0;
		}
		else                     // mainhand -- and this is the DEFAULT mount,
		{                        // so the misaim above was what everyone saw
			pos = pmo.AttackPos;
			ang = pmo.AttackAngle + 90;
			pit = -pmo.AttackPitch;
			rol = pmo.AttackRoll;
		}

		if (CVar.FindCVar("fl_allowflip").GetBool() && abs(rol) > 120)
		{
			ang -= 180;
			pit *= -1;
		}

		double cp = cos(pit);
		dir = (cos(ang) * cp, sin(ang) * cp, -sin(pit));
		return pos, dir;
	}

	override void Tick()
	{
		Super.Tick();

		let pmo = players[consoleplayer].mo;
		if (!pmo || !CVar.FindCVar("fl_enabled").GetBool())
		{
			level.ClearVolumetricBeam();
			if (beamLight) { beamLight.Destroy(); beamLight = null; }
			if (bounceLight) { bounceLight.Destroy(); bounceLight = null; }
			return;
		}

		Vector3 pos, dir;
		[pos, dir] = ResolveMount(PlayerPawn(pmo));
		[pos, dir] = Settle(pos, dir);

		Color col = CurrentColor();
		double range = CVar.FindCVar("fl_range").GetInt();
		double inner = CVar.FindCVar("fl_inner").GetFloat();
		double outer = CVar.FindCVar("fl_outer").GetFloat();
		double intensity = CVar.FindCVar("fl_intensity").GetFloat();

		// The visible cone.
		level.SetVolumetricBeam(pos, dir, col, inner, outer, range,
			CVar.FindCVar("fl_density").GetFloat() * intensity,
			CVar.FindCVar("fl_falloff").GetFloat(),
			CVar.FindCVar("fl_dust").GetFloat(),
			CVar.FindCVar("fl_dust_scale").GetFloat(),
			CVar.FindCVar("fl_dust_drift").GetFloat());

		// The surface lighting. Without this the beam would hang in the air
		// lighting nothing, which reads as fog rather than as a torch.
		if (!beamLight)
		{
			beamLight = Actor.Spawn("GITD_FlashlightSpot", pos);
		}
		if (beamLight)
		{
			beamLight.SetOrigin(pos, true);
			beamLight.angle = atan2(dir.y, dir.x);
			beamLight.pitch = -asin(clamp(dir.z, -1.0, 1.0));
			beamLight.args[0] = col.r;
			beamLight.args[1] = col.g;
			beamLight.args[2] = col.b;
			beamLight.args[3] = int(range * intensity);
			let sl = SpotLight(beamLight);
			if (sl)
			{
				sl.SpotInnerAngle = inner;
				sl.SpotOuterAngle = outer;
			}
		}

		// Bounce: a wide, dim, short-range light at the lens. A bare cone in
		// a black room reads as harsh and floating -- this puts a little
		// light back into the space around you, the way a real torch does off
		// whatever it is pointed at.
		if (CVar.FindCVar("fl_bounce").GetBool())
		{
			if (!bounceLight) bounceLight = Actor.Spawn("GITD_FlashlightBounce", pos);
			if (bounceLight)
			{
				bounceLight.SetOrigin(pos, true);
				bounceLight.args[0] = col.r * 0.35;
				bounceLight.args[1] = col.g * 0.35;
				bounceLight.args[2] = col.b * 0.35;
				bounceLight.args[3] = int(range * 0.18 * intensity);
			}
		}
		else if (bounceLight)
		{
			bounceLight.Destroy();
			bounceLight = null;
		}

		if (CVar.FindCVar("fl_agitate").GetBool()) AgitateLitMonsters(pmo, pos, dir, range, outer);
	}

	// Pointing the light at something wakes it. Deliberately cheap: a cone
	// test against monsters already near enough to matter, not a trace per
	// monster per tic.
	// Eases the published aim toward where the mount actually is.
	//
	// fl_lag is 0..1 as "how much it drags": 0 publishes the mount unchanged
	// and is the old behaviour exactly, 1 is treacle. The response is
	// FRAMERATE-INDEPENDENT in the only sense that matters here -- this runs
	// on the 35Hz tic, not per frame, so the same number means the same
	// settling time on any machine.
	//
	// The direction is renormalised after the blend. Lerping two unit vectors
	// gives a shorter one, and feeding an unnormalised direction to
	// SetVolumetricBeam scales the cone's own length term -- the beam would
	// visibly shorten while turning and stretch back as it settled.
	//
	// A jump cut has to arrive instantly. On the first tic, and any time the
	// mount moves further in one tic than a person could have (a teleport, a
	// map change, a level's opening frame), the smoothing is abandoned and the
	// target adopted whole -- otherwise the beam spends a second sweeping
	// across the map from wherever you used to be standing.
	private Vector3, Vector3 Settle(Vector3 pos, Vector3 dir)
	{
		double lag = clamp(CVar.FindCVar("fl_lag") ? CVar.FindCVar("fl_lag").GetFloat() : 0.55, 0.0, 0.95);

		if (!smPrimed || lag <= 0.001 || (pos - smPos).Length() > 192.0)
		{
			smPos = pos; smDir = dir; smPrimed = true;
			return pos, dir;
		}

		// The origin is nearly rigid -- it is your hand, and it does not move
		// much relative to you. Two thirds of the drag goes to the far end.
		double aPos = 1.0 - (lag * 0.35);
		double aDir = 1.0 - lag;

		smPos += (pos - smPos) * aPos;
		smDir += (dir - smDir) * aDir;

		double len = smDir.Length();
		if (len < 0.0001) { smDir = dir; }
		else smDir /= len;

		return smPos, smDir;
	}

	void AgitateLitMonsters(Actor pmo, Vector3 pos, Vector3 dir, double range, double outer)
	{
		double cosOuter = cos(outer);
		BlockThingsIterator it = BlockThingsIterator.Create(pmo, range);
		while (it.Next())
		{
			Actor mo = it.thing;
			if (!mo || !mo.bISMONSTER || mo.health <= 0) continue;
			if (mo.target == pmo) continue;

			Vector3 to = level.Vec3Diff(pos, mo.pos + (0, 0, mo.height * 0.5));
			double d = to.Length();
			if (d < 1 || d > range) continue;
			if ((to / d) dot dir < cosOuter) continue;

			if (mo.CheckSight(pmo))
			{
				mo.target = pmo;
				// Guarded: SetState(null) DESTROYS the actor, so a monster
				// with no See state would silently vanish when lit. The
				// sweep's wake effect already checks; this now matches it.
				if (mo.SeeState) mo.SetState(mo.SeeState);
			}
		}
	}
}

// The surface light. Range and angles are driven every tic from the cvars,
// so these defaults only matter for the frame it spawns on.
class GITD_FlashlightSpot : SpotLight
{
	Default
	{
		//$Title Flashlight beam light
		Args 255, 255, 255, 512;

		// ATTENUATE IS NOT OPTIONAL FOR A TORCH.
		//
		// Without it the shader skips the N.L term entirely, so every surface
		// inside the cone comes back at the SAME brightness no matter which
		// way it faces -- a wall you are square on to and a floor you are
		// grazing light identically. That is exactly the flat, sourceless
		// look of an ambient fill, which is the other half of why this read
		// as a lamp rather than a beam.
		//
		// DarkDoomZ's flashlight, the one that visibly worked, had this flag.
		// Ours was written without it.
		+DYNAMICLIGHT.ATTENUATE
	}
}

class GITD_FlashlightBounce : PointLight
{
	Default
	{
		//$Title Flashlight bounce light
		Args 255, 255, 255, 96;
	}
}

// The model, when shown. Offhand only, and that is not an arbitrary
// restriction: with any other mount there is no hand holding it, so a torch
// would hang in the air.
class GITD_FlashlightModel : Actor
{
	Default
	{
		+NOINTERACTION
		+NOGRAVITY
		+NOBLOCKMAP
		+BRIGHT
		+NOTONAUTOMAP
		Radius 1;
		Height 1;
		Scale 1.0;
	}

	States
	{
	Spawn:
		// [FIX] A REAL SPRITE FRAME, NOT TNT1.
		//
		// hw_sprites.cpp early-outs on `thing->sprite == 0`, and sprite 0 IS
		// TNT1 by construction -- 93 lines before it ever looks up a model
		// frame. So a model bound to TNT1 is discarded before the renderer
		// considers it, and this option could never have worked no matter
		// what the cvar said.
		//
		// FLSHA0 is a 1x1 fully transparent pixel: enough to get past the
		// sprite test, invisible in its own right, and the thing modeldef
		// hangs the real mesh on.
		FLSH A -1;
		Stop;
	}

	override void Tick()
	{
		Super.Tick();

		let pmo = players[consoleplayer].mo;
		bool wanted = pmo
			&& CVar.FindCVar("fl_enabled").GetBool()
			&& CVar.FindCVar("fl_model").GetBool()
			&& CVar.FindCVar("fl_mount").GetInt() == 1;

		if (!wanted)
		{
			// Hidden rather than destroyed, so toggling the model on and off
			// does not churn actors every time the menu is touched.
			bInvisible = true;
			return;
		}

		bInvisible = false;
		SetOrigin(pmo.OffhandPos, true);
		angle = pmo.OffhandAngle;
		pitch = pmo.OffhandPitch;
		roll = pmo.OffhandRoll;
	}
}

// Brings the flashlight into being and keeps it there. Nothing to pick up,
// nothing to lose.
class GITD_FlashlightHandler : StaticEventHandler
{
	override void WorldLoaded(WorldEvent e)
	{
		if (!GITD_Flashlight.Get()) GITD_Flashlight.Spawn();

		// [GITD] Riding this handler rather than adding a second one: both
		// are map-local thinkers that have to exist before the first tick,
		// and one WorldLoaded doing two spawns is cheaper to reason about
		// than two handlers racing to be first. See SweepRoom.zs.
		if (!GITD_SweepRoomTracker.Get()) GITD_SweepRoomTracker.Spawn();

		// [FIX] CLEAR THE OLD MAP'S ROOM BOX. FLevelLocals is reused between
		// levels and nothing in the engine resets these, so without this the
		// previous map's bounds stay live until the tracker's first publish --
		// up to half a second of the lattice being clipped to a room that is
		// not there any more, on geometry that has nothing to do with it.
		//
		// Cleared to unbounded rather than to something guessed: for the few
		// tics before the first publish, the old behaviour (no bound) is
		// wrong in a way you can see and understand, where a stale box is
		// wrong in a way that looks like a rendering bug.
		level.SetSweepRoom(0, 0, 0, 0, 0, 0, 0);
	}

	override void PlayerEntered(PlayerEvent e)
	{
		if (e.PlayerNumber != consoleplayer) return;
		let pmo = players[consoleplayer].mo;
		if (pmo && !GITD_ModelExists()) Actor.Spawn("GITD_FlashlightModel", pmo.pos);
	}

	bool GITD_ModelExists()
	{
		ThinkerIterator it = ThinkerIterator.Create("GITD_FlashlightModel");
		return it.Next() != null;
	}
}
