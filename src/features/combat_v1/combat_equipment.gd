class_name CombatEquipment
extends RefCounted

const HAMMER_ID: String = CombatPatternsV1.HAMMER_ID


static func melee(id: String) -> bool:
	return id in [CombatPatternsV1.AXE_ID, HAMMER_ID]


static func melee_policy(id: String) -> Dictionary:
	return CombatPatternsV1.melee_policy(id)

static func policy() -> Dictionary:
	return {"version":1,"patterns":CombatPatternsV1.POLICY}


static func definition(id: String) -> WeaponDefinition:
	if id not in [CombatPatternsV1.AXE_ID, CombatPatternsV1.SHOTGUN_ID, HAMMER_ID]: return null
	return load("res://assets/combat_v1/weapons/"+id+".tres") as WeaponDefinition

static func magazine(id: String) -> Dictionary:
	return {"capacity":CombatPatternsV1.POLICY.shotgun.capacity,"seconds":CombatPatternsV1.POLICY.shotgun.reload_seconds} if id=="shotgun_v1" else WeaponDefinition.MAGAZINES.get(id,{})

static func shot_origin(foot: Vector2) -> Vector2:
	# A long cosmetic barrel cannot jump over close bodies or a wall.
	return foot+Vector2.UP*AttackRules.HIT_HEIGHT
