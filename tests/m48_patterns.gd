extends "res://tests/m48_runtime_effects.gd"
## DIRECTED_EPHEMERAL: real shotgun batches and geometry, no persistent campaign rewards.

func _run() -> void:
	var rows: Array[Dictionary] = [{"id":1,"foot":Vector2(30,0),"alive":true,"available":true},
		{"id":2,"foot":Vector2(55,0),"alive":true,"available":true},
		{"id":3,"foot":Vector2(90,0),"alive":true,"available":true}]
	var clear: Array[ShotObstacle] = []
	var muzzle: Vector2 = Vector2.UP * AttackRules.HIT_HEIGHT
	var plan: Dictionary = CombatPatternsV1.shotgun_plan(Vector2.ZERO,muzzle,Vector2.RIGHT,rows,clear,150.0,true)
	_check(_hits(plan,1) == 5.0 and _hits(plan,2) == 2.5 and _hits(plan,3) == 0.0,
		"five pellet first hits and five half-damage secondary hits stop after two targets")
	var wall: Array[ShotObstacle] = [ShotObstacle.new(&"between",Rect2(42,-40,1,80),true)]
	var blocked: Dictionary = CombatPatternsV1.shotgun_plan(Vector2.ZERO,muzzle,Vector2.RIGHT,rows,wall,150.0,true)
	_check(_hits(blocked,1) == 5.0 and _hits(blocked,2) == 0.0, "wall blocks every secondary pellet")
	rows.reverse()
	_check(CombatPatternsV1.shotgun_plan(Vector2.ZERO,muzzle,Vector2.RIGHT,rows,clear,150.0,true) == plan,
		"enemy iteration order leaves the exact pellet batch unchanged")
	var world: ClockWorld = _shotgun(WeaponModifiers.PIERCE)
	var first: FieldActor = _enemy(world,Vector2(430,400))
	var second: FieldActor = _enemy(world,Vector2(455,400))
	second.actor_id = 22
	var first_before: float = first.health
	var second_before: float = second.health
	var shooter: FieldActor = world.survivors[0]
	world.combat.attack(world,shooter,0.0)
	_check(_near(first_before-first.health,45.0) and _near(second_before-second.health,22.5) and shooter.magazine.rounds == 3,
		"real shotgun commits aggregated first and half-damage secondary HP and one round")
	observations.pierce = {"first_hp":first.health,"secondary_hp":second.health,"rounds":shooter.magazine.rounds}
	world.free()
	world = _shotgun(WeaponModifiers.REFUND)
	shooter = world.survivors[0]
	for index: int in range(3):
		var target: FieldActor = _enemy(world,Vector2(510,400 + (index - 1) * 24))
		target.actor_id = 21 + index
		target.health = 1.0
	world.combat.attack(world,shooter,0.0)
	_check(shooter.confirmed_kills == 3 and shooter.magazine.rounds == shooter.magazine.capacity(),
		"three real pellet kills refund exactly one round and respect the capacity ceiling")
	observations.refund = {"kills":shooter.confirmed_kills,"rounds":shooter.magazine.rounds,"capacity":shooter.magazine.capacity()}
	world.free()
	observations.checks = checks
	observations.failures = failures
	print("M48_PATTERNS " + JSON.stringify(observations))
	quit(0 if failures == 0 else 1)


func _hits(plan: Dictionary, id: int) -> float:
	for row: Dictionary in plan.targets:
		if row.id == id: return float(row.hits)
	return 0.0


func _shotgun(affix: String) -> ClockWorld:
	var world: ClockWorld = _world()
	var actor: FieldActor = _actor(world)
	actor.weapon_definition = WeaponInventory.definition("shotgun_v1").duplicate() as WeaponDefinition
	actor.weapon_definition.combat_affix = affix
	actor.magazine = WeaponMagazine.new(actor.weapon_instance_id,"shotgun_v1")
	world.growth_inputs.register_member(actor.member_id)
	world._effects = Node2D.new()
	world.add_child(world._effects)
	return world
