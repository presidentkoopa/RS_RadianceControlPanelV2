// ============================================================================
//  Universal Map Enhancements -- keys you can find in the dark.
// ============================================================================
//
//  THIS ONE IS NOT A PORT. Universal Map Enhancements does touch the six
//  vanilla keys, but only with a cosmetic shim that spawns the real key on
//  top of itself and then sits inert -- it adds no light. The reason to do
//  something here is this mod's own: the front page of the README promises a
//  map "crushed toward black", and a keycard is a small flat sprite lying on
//  a floor. Under Blackout the intended experience is navigating by ear; a
//  key you cannot see is not atmosphere, it is a softlock you have to
//  console your way out of.
//
//  So the key carries its own light, in its own colour, and the colour is
//  the point -- a blue glow across a dark room IS the information "the blue
//  key is over there", which is exactly what the locked door was going to
//  ask you for anyway. Nothing about the pickup, the message, the icon or
//  the lock is touched; each class below subclasses the real vanilla key and
//  changes nothing but whether it is visible in the dark.
//
//  Its own cvar, and not folded into ume_decorations: this is the one thing
//  in this component that can affect whether a map is completable, and it
//  deserves an off switch that does not also take the torches with it.
//
//  WHY A SUBCLASS AND NOT UME'S SHIM: subclassing inherits every bit of the
//  key's own pickup behaviour for free -- the message, the icon, the lock
//  identity, deathmatch respawn -- where a shim has to keep that in sync by
//  hand. This is one of the few places where doing it differently from the
//  pack is strictly simpler rather than a matter of taste.
//
// ============================================================================

// The glow is created and released by STATE, not by event, and that is what
// makes pickup, deathmatch respawn and Thing_Remove all work without any of
// them being special-cased.
//
// bSpecial is the flag that means "lying in the world, touch me to pick me
// up". It is set on a key waiting on the floor and cleared the moment it is
// taken or hidden, so it answers exactly the question this needs answered --
// and answers it again, correctly, if the item respawns.
//
// Same create-when-wanted/release-when-not shape FancyEmitter's own light
// arm uses (fancy_common.zs), for the same reason: a Shape slot is not
// actor-lifetime-aware, so something has to hand it back.
class UMEKeyGlow abstract play
{
	static int Update(Actor from, int slot, Color c, double radius)
	{
		bool wanted = UMESettings.GetBool("ume_key_glow", true)
			&& from.bSpecial && !Inventory(from).owner;

		if (wanted && slot < 0)
		{
			return level.AddShape(1, 2,
				from.pos.x, from.pos.y, from.pos.z + 8.0,
				radius, 0.0, 3.0, c, 1.5, 0.0);
		}

		if (!wanted && slot >= 0)
		{
			level.RemoveShape(slot);
			return -1;
		}

		return slot;
	}
}

// ---- Key cards -------------------------------------------------------------

class UMEBlueCard : BlueCard replaces BlueCard
{
	private int umeSlot;
	override void PostBeginPlay() { Super.PostBeginPlay(); umeSlot = -1; }
	override void Tick()
	{
		Super.Tick();
		umeSlot = UMEKeyGlow.Update(self, umeSlot, 0x4070FF, 40.0);
	}
	override void OnDestroy()
	{
		if (umeSlot >= 0) level.RemoveShape(umeSlot);
		Super.OnDestroy();
	}
}

class UMEYellowCard : YellowCard replaces YellowCard
{
	private int umeSlot;
	override void PostBeginPlay() { Super.PostBeginPlay(); umeSlot = -1; }
	override void Tick()
	{
		Super.Tick();
		umeSlot = UMEKeyGlow.Update(self, umeSlot, 0xFFD030, 40.0);
	}
	override void OnDestroy()
	{
		if (umeSlot >= 0) level.RemoveShape(umeSlot);
		Super.OnDestroy();
	}
}

class UMERedCard : RedCard replaces RedCard
{
	private int umeSlot;
	override void PostBeginPlay() { Super.PostBeginPlay(); umeSlot = -1; }
	override void Tick()
	{
		Super.Tick();
		umeSlot = UMEKeyGlow.Update(self, umeSlot, 0xFF3830, 40.0);
	}
	override void OnDestroy()
	{
		if (umeSlot >= 0) level.RemoveShape(umeSlot);
		Super.OnDestroy();
	}
}

// ---- Skull keys ------------------------------------------------------------
//
// Same colours as the cards -- the colour is the lock, not the object, and a
// blue skull opens exactly what a blue card does.

class UMEBlueSkull : BlueSkull replaces BlueSkull
{
	private int umeSlot;
	override void PostBeginPlay() { Super.PostBeginPlay(); umeSlot = -1; }
	override void Tick()
	{
		Super.Tick();
		umeSlot = UMEKeyGlow.Update(self, umeSlot, 0x4070FF, 40.0);
	}
	override void OnDestroy()
	{
		if (umeSlot >= 0) level.RemoveShape(umeSlot);
		Super.OnDestroy();
	}
}

class UMEYellowSkull : YellowSkull replaces YellowSkull
{
	private int umeSlot;
	override void PostBeginPlay() { Super.PostBeginPlay(); umeSlot = -1; }
	override void Tick()
	{
		Super.Tick();
		umeSlot = UMEKeyGlow.Update(self, umeSlot, 0xFFD030, 40.0);
	}
	override void OnDestroy()
	{
		if (umeSlot >= 0) level.RemoveShape(umeSlot);
		Super.OnDestroy();
	}
}

class UMERedSkull : RedSkull replaces RedSkull
{
	private int umeSlot;
	override void PostBeginPlay() { Super.PostBeginPlay(); umeSlot = -1; }
	override void Tick()
	{
		Super.Tick();
		umeSlot = UMEKeyGlow.Update(self, umeSlot, 0xFF3830, 40.0);
	}
	override void OnDestroy()
	{
		if (umeSlot >= 0) level.RemoveShape(umeSlot);
		Super.OnDestroy();
	}
}
