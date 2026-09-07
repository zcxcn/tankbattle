class_name CombatEnums
extends RefCounted

## Shared, engine-independent combat identifiers.
enum Faction {
	NEUTRAL = 0,
	PLAYER = 1,
	ENEMY = 2,
}

enum DamageKind {
	KINETIC = 0,
	EXPLOSIVE = 1,
	ENERGY = 2,
	MINE = 3,
}


static func are_hostile(left: Faction, right: Faction) -> bool:
	return (
		left != Faction.NEUTRAL
		and right != Faction.NEUTRAL
		and left != right
	)
