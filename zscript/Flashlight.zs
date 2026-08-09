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
		phase += CVar.FindCVar("fl_speed").GetFloat();
		if (phase >= 1.0)
		{
			phase -= 1.0;
			slotIndex = (slotIndex + 1) % count;
			fromCol = toCol;
			int nextSlot = (pattern == 4 && (slotIndex % 2) == 1)
				? (slotIndex + count - 1) % count
				: (slotIndex + 1) % count;
			toCol = SlotColor(nextSlot);
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
	Vector3, Vector3 ResolveMount(PlayerPawn pmo)
	{
		Vector3 pos, dir;
		int mount = CVar.FindCVar("fl_mount").GetInt();
		double ang, pit, rol;

		if (mount == 1)          // offhand
		{
			pos = pmo.OffhandPos;
			ang = pmo.OffhandAngle;
			pit = pmo.OffhandPitch;
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
		else                     // mainhand
		{
			pos = pmo.AttackPos;
			ang = pmo.AttackAngle;
			pit = pmo.AttackPitch;
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
				mo.SetState(mo.SeeState);
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
		TNT1 A -1;
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
