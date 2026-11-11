extends "res://tests/m48_runtime_effects.gd"
## Runtime parameter fixtures are ephemeral and carry no claimed journey qualification.
## Optional --component-camp=/absolute/.local/...json reads a real camp, then tests
## CampEdit proposals on independent in-memory forks. It never writes a profile.

var component_rows: Array[Dictionary] = []
var source_rows: Array[Dictionary] = []

func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(2)
		return
	for gun: String in EconomyBuildV1.GUNS:
		_magazine_matrix(gun)
		_basic_matrix(gun)
		_pierce_matrix(gun)
		_refund_matrix(gun)
	_heal_and_blast()
	var source: String = "NOT_TESTED_NO_REAL_CAMP_INPUT"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--component-camp="):
			source = argument.trim_prefix("--component-camp=")
			_source_matrix(source)
	observations = {"scope":"DIRECTED_EPHEMERAL_RUNTIME_AND_OPTIONAL_REAL_SOURCE_PROPOSALS","checks":checks,"failures":failures,
		"runtime":component_rows,"source_proposals":source_rows,"source_camp":source,"disk_writes":"NONE","normal_campaign":"NOT_TESTED"}
	print("M48_COMPONENTS " + JSON.stringify(observations))
	quit(0 if failures == 0 else 1)

func _configured(gun: String,basic: String = "",combat: String = "",mod: String = "") -> Dictionary:
	var item: Dictionary = EconomyBuildV1.craft_instance("0123456789abcdef0123456789abcdef:edit:88888888888888888888888888888888",gun)
	item.economy.basic = basic
	item.economy.combat = combat
	item.economy.magazine = mod
	item.affixes = EconomyBuildV1.components(item.economy)
	_check(WeaponModifiers.problem(item).is_empty(), "explicit ephemeral configuration has a valid instance shape")
	return item

func _armed(world: ClockWorld,item: Dictionary) -> FieldActor:
	var actor: FieldActor = _actor(world)
	actor.weapon_instance_id = item.instance_id
	actor.weapon_definition = WeaponModifiers.combat_definition(item)
	actor.magazine = WeaponMagazine.new(item.instance_id,item.weapon_id,item.economy.magazine)
	actor.visual.set_weapon(actor.weapon_definition.presentation)
	world.apply_build(actor)
	if world._effects == null:
		world._effects = Node2D.new()
		world.add_child(world._effects)
	return actor

func _target(world: ClockWorld,point: Vector2,identity: int = 21,health: float = 10000.0) -> FieldActor:
	var target: FieldActor = _enemy(world,point)
	target.actor_id = identity
	target.health = health
	target.max_health = health
	return target

func _fire(world: ClockWorld,actor: FieldActor,target: FieldActor) -> void:
	if actor.weapon_definition.id == &"shotgun_v1":
		world.combat.attack(world,actor,0.0)
	else:
		var decision: AttackRules.Decision = world.evaluate_attack(actor,target)
		if decision.can_fire:
			actor.aim = target.position-actor.position
			world._fire_ranged(actor,target,decision)

func _magazine_matrix(gun: String) -> void:
	var options: Dictionary = {"carbine":{"extended_mag":[16,2.20],"quick_mag":[9,1.05]},
		"long_rifle":{"extended_mag":[7,2.55],"quick_mag":[3,1.85]},"shotgun_v1":{"extended_mag":[6,3.00],"quick_mag":[3,1.80]}}
	for mod: String in [WorkshopV1.EXTENDED,WorkshopV1.QUICK]:
		var world: ClockWorld = _world()
		var actor: FieldActor = _armed(world,_configured(gun,"quick_v1","",mod))
		var target: FieldActor = _target(world,actor.position+Vector2(70,0))
		var gun_state: WeaponMagazine = actor.magazine
		var expected: Array = options[gun][mod]
		_check(gun_state.capacity() == expected[0], "configured actual capacity " + gun + ":" + mod)
		for shot: int in range(gun_state.capacity()):
			if shot > 0:
				actor.advance(actor.cooldown,false,false)
			_fire(world,actor,target)
		_check(gun_state.rounds == 0 and gun_state.reloading and target.health < target.max_health, "actual attacks empty configured magazine " + gun + ":" + mod)
		var elapsed: float = 0.0
		while gun_state.reloading and elapsed < 5.0:
			gun_state.advance(STEP)
			elapsed += STEP
		_check(_near(elapsed,float(expected[1]),0.002) and gun_state.rounds == gun_state.capacity(), "actual reload clock and capacity refill " + gun + ":" + mod)
		component_rows.append({"kind":"magazine","gun":gun,"mod":mod,"capacity":gun_state.capacity(),"reload_sim_seconds":elapsed,"target_hp_lost":target.max_health-target.health})
		world.free()

func _basic_matrix(gun: String) -> void:
	for basic: String in ["quick_v1","reach_v1"]:
		var world: ClockWorld = _world()
		var actor: FieldActor = _armed(world,_configured(gun,basic))
		var target: FieldActor = _target(world,actor.position+Vector2(70,0))
		_fire(world,actor,target)
		_check(target.health < target.max_health and _near(actor.cooldown,WeaponInventory.definition(gun).interval*(0.90 if basic == "quick_v1" else 1.0)), "actual shot recovery follows installed basic component " + gun + ":" + basic)
		component_rows.append({"kind":"basic","gun":gun,"component":basic,"actual_cooldown":actor.cooldown,"damage":target.max_health-target.health})
		world.free()
	for extended: bool in [false,true]:
		var world: ClockWorld = _world()
		var actor: FieldActor = _armed(world,_configured(gun,"reach_v1" if extended else ""))
		var target: FieldActor = _target(world,actor.position+Vector2(WeaponInventory.definition(gun).shot_range*1.05,0))
		_fire(world,actor,target)
		_check((target.health < target.max_health) == extended, "installed reach changes a real out-of-base-range hit " + gun)
		world.free()

func _pierce_matrix(gun: String) -> void:
	for blocked: bool in [false,true]:
		var world: ClockWorld = _world()
		var actor: FieldActor = _armed(world,_configured(gun,"",WeaponModifiers.PIERCE))
		var primary: FieldActor = _target(world,actor.position+Vector2(70,0))
		var second_point: Vector2
		if gun == "shotgun_v1":
			second_point = actor.position+Vector2(110,0)
		else:
			var decision: AttackRules.Decision = world.evaluate_attack(actor,primary)
			second_point = decision.hit_to+decision.shot_from.direction_to(decision.hit_to)*40.0+Vector2.DOWN*AttackRules.HIT_HEIGHT
		var secondary: FieldActor = _target(world,second_point,22)
		if blocked:
			world.shot_obstacles.append(ShotObstacle.new(&"component-wall",Rect2(Vector2(490,350),Vector2(6,100)),true))
		_fire(world,actor,primary)
		var first_damage: float = primary.max_health-primary.health
		var second_damage: float = secondary.max_health-secondary.health
		_check(first_damage > 0.0 and (second_damage == 0.0 if blocked else second_damage > 0.0), "actual piercing respects the wall behind the primary " + gun)
		if not blocked:
			_check(_near(second_damage,first_damage*0.50), "actual aligned secondary receives one-half of the same firing rays " + gun)
		_check(actor.magazine.rounds == actor.magazine.capacity()-1, "multi-target pierce consumes one round " + gun)
		component_rows.append({"kind":"pierce","gun":gun,"blocked":blocked,"primary_damage":first_damage,"secondary_damage":second_damage,"rounds":actor.magazine.rounds})
		world.free()

func _refund_matrix(gun: String) -> void:
	for lethal: bool in [false,true]:
		var world: ClockWorld = _world()
		var actor: FieldActor = _armed(world,_configured(gun,"",WeaponModifiers.REFUND))
		var primary: FieldActor = _target(world,actor.position+Vector2(90,0),21,1.0 if lethal else 10000.0)
		if gun == "shotgun_v1" and lethal:
			_target(world,actor.position+Vector2(95,-20),22,1.0)
			_target(world,actor.position+Vector2(95,20),23,1.0)
		var before: int = actor.magazine.rounds
		_fire(world,actor,primary)
		var killed: int = actor.confirmed_kills
		var refund: int = actor.magazine.rounds-(before-1)
		_check(refund == (1 if lethal else 0) and actor.magazine.rounds <= actor.magazine.capacity(), "only an actual defeat refunds at most one firing round " + gun)
		_check((killed > 0) == lethal, "refund is linked to the actual hit result " + gun)
		if gun == "shotgun_v1" and lethal:
			_check(killed >= 2 and refund == 1, "one shotgun firing with multiple pellet defeats refunds exactly once")
		var accepted_rounds: int = actor.magazine.rounds
		_fire(world,actor,primary)
		_check(actor.magazine.rounds == accepted_rounds and actor.confirmed_kills == killed, "same-frame repeat cannot duplicate the firing refund " + gun)
		component_rows.append({"kind":"refund","gun":gun,"lethal":lethal,"kills":killed,"rounds_refunded":refund,"rounds":actor.magazine.rounds,"capacity":actor.magazine.capacity()})
		world.free()

func _heal_and_blast() -> void:
	for enhanced: bool in [false,true]:
		var world: Dictionary = _support_world("",enhanced,"medical_pack_v1")
		var component: BasicSupport = BasicSupport.new()
		component.restore(world.support)
		var plan: Dictionary = BuildAuthority.plan_heal(world)
		var after: Dictionary = BuildAuthority.propose(world,component.request("heal",plan))
		_check(not after.is_empty() and after.survivors[0].state.health == (90.0 if enhanced else 80.0), "medical pack changes actual authority HP by sixty or seventy")
		var planner: BasicSupport = BasicSupport.new()
		planner.configure(UI_BINDING_FOR_SUPPORT())
		var members: Array[Dictionary] = [{"member_id":1,"health":100.0,"present":true,"working":false,"position":Vector2.ZERO}]
		var enemies: Array[Dictionary] = [{"enemy_id":7,"health":100.0,"present":true,"position":Vector2(130,0)}]
		var factor: float = BuildItems.frozen_factors({"version":BuildItems.M48_CATALOG_POOL,"slots":["wide_blast_v1",""],"enhanced":["wide_blast_v1"] if enhanced else []}).blast
		var blast: Dictionary = planner.plan_airstrike(members,enemies,Vector2.ZERO,factor,func(_point: Vector2) -> bool: return true,func(_start: Vector2,_end: Vector2) -> bool: return true)
		_check(not blast.is_empty() and blast.radius == (135.0 if enhanced else 117.0) and blast.targets == ([7] if enhanced else []), "actual airstrike target plan includes the expanded-radius enemy only after enhancement")
		component_rows.append({"kind":"heal_and_blast","enhanced":enhanced,"healing_amount":plan.get("amount"),"blast_radius":blast.get("radius"),"blast_targets":blast.get("targets")})

func UI_BINDING_FOR_SUPPORT() -> Dictionary:
	return {"transaction_id":"directed-component-support"}

func _source_matrix(path: String) -> void:
	var local_root: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	_check(path.is_absolute_path() and path.replace("\\", "/").begins_with(local_root) and FileAccess.file_exists(path), "real source camp path is isolated and exists")
	if not path.is_absolute_path() or not path.replace("\\", "/").begins_with(local_root) or not FileAccess.file_exists(path):
		return
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not document is Dictionary:
		_check(false,"source input is a real saved JSON evidence document")
		return
	if document.has("record_encoding"):
		var decoded: Dictionary = RecordEncoding.unpack(document)
		_check(decoded.error == OK,"real source exact record decodes without precision loss")
		if decoded.error != OK: return
		document = decoded.payload
		if document.has("phase"):
			_check(TransactionReceipt.problem(document).is_empty(),"real source receipt fully authenticates before extracting its confirmed camp")
			document = {"camp":TransactionReceipt.camp(document)}
	var candidate: Variant = document.get("camp")
	if not candidate is Dictionary:
		candidate = document.get("value",document)
	if not candidate is Dictionary:
		_check(false,"source evidence contains a full camp object")
		return
	var base: Dictionary = candidate
	var issue: String = TransactionReceipt.camp_problem(base)
	_check(issue.is_empty() and EconomyBuildV1.enabled(base), "actual source camp passes strict independent provenance: " + issue)
	if not issue.is_empty() or not EconomyBuildV1.enabled(base):
		return
	_check(EconomyBuildV1.level(base,"workshop") == 2 and int(base.cash) >= 28 and EconomyBuildV1.tools(base) >= 3, "source camp really funds the independent craft and two-install forks")
	if EconomyBuildV1.level(base,"workshop") != 2 or int(base.cash) < 28 or EconomyBuildV1.tools(base) < 3:
		return
	var base_hash: String = RecordEncoding.fingerprint(base)
	for gun: String in EconomyBuildV1.GUNS:
		var created: Dictionary = _source_edit(base,"craft",gun)
		if created.is_empty():
			continue
		var item: Dictionary = created.weapons.back()
		for operation: String in ["basic_component","combat_component","magazine"]:
			var branch: Dictionary = created.duplicate(true)
			var choices: Array = EconomyBuildV1.BASIC if operation == "basic_component" else EconomyBuildV1.COMBAT if operation == "combat_component" else [WorkshopV1.EXTENDED,WorkshopV1.QUICK]
			for choice: String in choices:
				branch = _source_edit(branch,operation,item.instance_id,choice)
				if branch.is_empty():
					break
				_check(WeaponInventory.find(branch,item.instance_id).instance_id == item.instance_id, "replacement preserves the original unique instance")
			if branch.is_empty():
				continue
			var installed: Dictionary = WeaponInventory.find(branch,item.instance_id).duplicate(true)
			var first: Dictionary = CampEdit.propose(branch,{"kind":"equip","member_id":1,"value":item.instance_id})
			var swapped: Dictionary = CampEdit.propose(first,{"kind":"equip","member_id":2,"value":item.instance_id}) if not first.is_empty() else {}
			_check(not swapped.is_empty() and WeaponInventory.owner(swapped,item.instance_id) == 2 and TransactionReceipt.same(WeaponInventory.find(swapped,item.instance_id),installed), "normal owner exchange carries installed configuration with the same instance")
			if not swapped.is_empty():
				_check(TransactionReceipt.camp_problem(swapped).is_empty(), "exchanged component and magazine history independently validates")
				var field: ClockWorld = _world()
				var holder: FieldActor = _armed(field,WeaponInventory.for_member(swapped,2))
				holder.member_id = 2
				var target: FieldActor = _target(field,holder.position+Vector2(70,0))
				_fire(field,holder,target)
				_check(holder.weapon_instance_id == installed.instance_id and holder.magazine.modification == WorkshopV1.mod_for(swapped,installed.instance_id)
					and holder.weapon_definition.combat_affix == WeaponModifiers.combat_affix(installed) and target.health < target.max_health,
					"the exchanged instance fires on its new owner with its original component and magazine")
				field.free()
			var forged: Dictionary = branch.duplicate(true)
			WeaponInventory.find(forged,item.instance_id).economy.basic = "reach_v1" if installed.economy.basic != "reach_v1" else "quick_v1"
			WeaponInventory.find(forged,item.instance_id).affixes = EconomyBuildV1.components(WeaponInventory.find(forged,item.instance_id).economy)
			_check(not TransactionReceipt.camp_problem(forged).is_empty(), "valid-shaped but unearned component replacement is rejected by source history")
			var invalid: Dictionary = EconomyBuildV1.request(branch,"basic_component",item.instance_id,WeaponModifiers.PIERCE,String(base.profile_id)+":edit:"+RunSave.new_profile_id())
			_check(CampEdit.propose(branch,invalid).is_empty(), "combat component cannot occupy the basic slot")
	_check(RecordEncoding.fingerprint(base) == base_hash, "source camp stays byte-value identical across every isolated proposal fork")

func _source_edit(before: Dictionary,operation: String,target_id: String,choice: String = "") -> Dictionary:
	var offer: Dictionary = EconomyBuildV1.offer(before,operation,target_id,choice)
	_check(offer.available,"real materials support " + operation + ":" + choice + " " + String(offer.reason))
	if not offer.available:
		return {}
	var request: Dictionary = EconomyBuildV1.request(before,operation,target_id,choice,String(before.profile_id)+":edit:"+RunSave.new_profile_id())
	var after: Dictionary = CampEdit.propose(before,request)
	_check(not after.is_empty(),"original camp authority accepts the source-bound pure proposal")
	if after.is_empty():
		return {}
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(after)))
	_check(decoded.error == OK and TransactionReceipt.camp_problem(decoded.payload).is_empty(), "independent exact round-trip authenticates component debit and history")
	_check(int(after.cash) == int(before.cash)-int(offer.cost) and EconomyBuildV1.tools(after) == EconomyBuildV1.tools(before)-int(offer.tools), "installation consumes only the quoted actual units")
	source_rows.append({"operation":operation,"choice":choice,"target":target_id,"before":RecordEncoding.fingerprint(before),"after":RecordEncoding.fingerprint(after),"cash_before":before.cash,"cash_after":after.cash,"tools_before":EconomyBuildV1.tools(before),"tools_after":EconomyBuildV1.tools(after),"request":request})
	return after
