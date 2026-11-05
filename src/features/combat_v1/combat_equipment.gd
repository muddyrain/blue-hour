class_name CombatEquipment
extends RefCounted

static func melee(id: String) -> bool:
	return id=="fire_axe_v1"

static func policy() -> Dictionary:
	return {"version":1,"patterns":CombatPatternsV1.POLICY}


static func definition(id: String) -> WeaponDefinition:
	if id not in ["fire_axe_v1","shotgun_v1"]: return null
	return load("res://assets/combat_v1/weapons/"+id+".tres") as WeaponDefinition

static func magazine(id: String) -> Dictionary:
	return {"capacity":CombatPatternsV1.POLICY.shotgun.capacity,"seconds":CombatPatternsV1.POLICY.shotgun.reload_seconds} if id=="shotgun_v1" else WeaponDefinition.MAGAZINES.get(id,{})

static func shot_origin(foot: Vector2) -> Vector2:
	# A long cosmetic barrel cannot jump over close bodies or a wall.
	return foot+Vector2.UP*AttackRules.HIT_HEIGHT
