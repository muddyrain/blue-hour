extends SceneTree
## Isolated schema/ownership/combat fixtures. Native controls are verified separately.

const SortieScene: PackedScene = preload("res://src/features/expedition/expedition.tscn")
const MainScene: PackedScene = preload("res://src/app/main.tscn")
const Rules: CampRules = preload("res://src/features/camp/camp_rules.tres")

var _path: String = ""
var _results: Array[Dictionary] = []
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			_path = argument.trim_prefix("--bh-progress=")
	if not _path.contains(".local") or FileAccess.file_exists(_path):
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var definition_ids: Array[StringName] = []
	for weapon: WeaponDefinition in WeaponInventory.Definitions:
		_expect(not weapon.id in definition_ids and weapon.presentation != null and weapon.presentation.id == weapon.id
			and weapon.presentation.texture != null and weapon.damage > 0.0 and weapon.interval > 0.0 and weapon.shot_range > 0.0 and weapon.repair_cost >= 0,
			"unique valid static definition and matching existing presentation: " + String(weapon.id))
		definition_ids.append(weapon.id)
	var fresh: Dictionary = _state()
	_expect(RunSave.validate(fresh).is_empty(), "new inventory is a valid v3 camp with two distinct ready starter instances")
	var token: String = fresh.profile_id + ":1"
	var report: Dictionary = {"evacuated":true, "loot":4, "food":3, "health":[200.0,196.0], "weapons":[WeaponInventory.reward(token)]}
	var after: Dictionary = CampEconomy.preview(fresh, report, token, Rules)
	_expect(after.weapons.size() == 3 and fresh.weapons.size() == 2 and after.food == 3, "preview carries one damaged instance without mutating camp or changing food boundary")
	_expect(CampEconomy.preview(after, report, token, Rules).is_empty(), "same settlement cannot bank a second weapon")
	var duplicate: Dictionary = report.duplicate(true)
	duplicate.weapons.append(duplicate.weapons[0])
	_expect(CampEconomy.preview(fresh, duplicate, token, Rules).is_empty(), "duplicate source rewards reject the entire proposal")
	duplicate = report.duplicate(true)
	duplicate.weapons[0].instance_id += "-fake"
	_expect(CampEconomy.preview(fresh, duplicate, token, Rules).is_empty(), "fabricated reward instance cannot enter camp")
	duplicate = report.duplicate(true)
	duplicate.evacuated = false
	var failed: Dictionary = CampEconomy.preview(fresh, duplicate, token, Rules)
	_expect(failed.weapons.size() == 2 and failed.cash == 53 and failed.food == 0, "failed evacuation discards loot and preserves existing ration semantics")
	var identity: String = after.weapons.back().instance_id
	_expect(not WeaponInventory.equip(after, 1, identity).has("data"), "damaged loot cannot equip")
	var poor: Dictionary = after.duplicate(true)
	poor.cash = 9
	_expect(not WeaponInventory.repair(poor, identity).has("data"), "insufficient money rejects repair without mutation")
	var repaired: Dictionary = WeaponInventory.repair(after, identity).data
	_expect(repaired.cash == 47 and repaired.camp_spending == 10 and repaired.food == after.food and repaired.day == after.day and RunSave.validate(repaired).is_empty(),
		"repair has one accountable sample cost, no food or date change")
	_expect(not WeaponInventory.repair(repaired, identity).has("data"), "ready item cannot charge repair twice")
	var equipped: Dictionary = WeaponInventory.equip(repaired, 1, identity).data
	_expect(WeaponInventory.for_member(equipped, 1).instance_id == identity and WeaponInventory.owner(equipped, fresh.weapons[0].instance_id) == 0,
		"equipping idle loot releases exactly the previous instance")
	_expect(not WeaponInventory.equip(equipped, 1, identity).has("data"), "same-owner repeat is an explicit no-op")
	var swapped: Dictionary = WeaponInventory.equip(equipped, 2, identity).data
	_expect(WeaponInventory.owner(swapped, identity) == 2 and WeaponInventory.owner(swapped, fresh.weapons[1].instance_id) == 1
		and RunSave.validate(swapped).is_empty(), "equipping another member's instance swaps ownership without cloning")
	var captured: Array[Dictionary] = WeaponInventory.snapshot(swapped)
	var detached: Dictionary = swapped.duplicate(true)
	WeaponInventory.find(detached, captured[0].instance.instance_id).condition = "damaged"
	_expect(captured[0].instance.condition == "ready", "sortie snapshot is a deep copy independent of later inventory edits")
	for mutation: String in ["definition", "duplicate_instance", "shared_instance", "lost_instance", "dead_member", "unknown_member", "missing_loadout", "damaged_equipped", "source", "future", "spending", "unknown_field"]:
		var broken: Dictionary = swapped.duplicate(true)
		match mutation:
			"definition": broken.weapons[0].weapon_id = "missing"
			"duplicate_instance": broken.weapons.append(broken.weapons[0].duplicate(true))
			"shared_instance": broken.loadout[1].instance_id = broken.loadout[0].instance_id
			"lost_instance": broken.weapons.remove_at(1)
			"dead_member": broken.crew[0].health = 0.0
			"unknown_member": broken.loadout[0].member_id = 3
			"missing_loadout": broken.loadout.remove_at(0)
			"damaged_equipped": WeaponInventory.find(broken, broken.loadout[0].instance_id).condition = "damaged"
			"source": broken.weapons[0].origin = "invented"
			"future": broken.weapons.back().acquired_sortie = fresh.profile_id + ":9"
			"spending": broken.camp_spending = 11
			"unknown_field": broken.weapons[0].extra = 1
		_expect(not RunSave.validate(broken).is_empty(), "reject malformed v3 ownership: " + mutation)
	var deceased: Dictionary = report.duplicate(true)
	deceased.health = [0.0, 196.0]
	var casualty: Dictionary = CampEconomy.preview(fresh, deceased, token, Rules)
	_expect(casualty.loadout.size() == 1 and WeaponInventory.owner(casualty, fresh.weapons[0].instance_id) == 0, "fallen member's existing weapon is idle, never equipped to dead ID")
	_expect(not WeaponInventory.equip(casualty, 1, identity).has("data") and not WeaponInventory.equip(after, 9, identity).has("data"), "dead and unknown targets reject equip")
	var store: RunSave = RunSave.new(_path)
	_expect(store.save(swapped) == OK and store.load_save() == OK and store.snapshot == swapped, "v3 round trip preserves unique identities, condition, ownership and camp spending")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(_path)
	var corrupt: Dictionary = swapped.duplicate(true)
	corrupt.loadout[1].instance_id = corrupt.loadout[0].instance_id
	_write(_path + ".bak", bytes)
	_write(_path, JSON.stringify(corrupt).to_utf8_buffer())
	var corrupt_bytes: PackedByteArray = FileAccess.get_file_as_bytes(_path)
	_expect(store.load_save() != OK and store.snapshot.is_empty() and store.load_save(true) == OK and store.snapshot == swapped,
		"invalid shared-instance disk file is rejected; independently valid v3 backup remains usable")
	_expect(store.save(swapped) != OK and FileAccess.get_file_as_bytes(_path) == corrupt_bytes,
		"malformed weapon save cannot be overwritten without explicit recovery")
	_write(_path, bytes)
	var blocker: String = _path.get_base_dir().path_join("parent-file")
	_write(blocker, "file".to_utf8_buffer())
	_expect(RunSave.new(blocker.path_join("run.json")).save(swapped) != OK and FileAccess.get_file_as_bytes(_path) == bytes,
		"real filesystem obstruction cannot alter valid inventory bytes")
	await _migration()
	await _sortie_checks(swapped)
	await _app_checks()
	var file: FileAccess = FileAccess.open(_path.get_base_dir().path_join("weapon-fixture-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":_results.size(), "failures":_failures, "results":_results}, "\t"))
	file.close()
	print("BH_WEAPON_FIXTURES checks=%d failures=%d" % [_results.size(), _failures])
	quit(0 if _failures == 0 else 1)


func _migration() -> void:
	for version: int in [1, 2]:
		var source: String = "res://tests/fixtures/m3-01/final-second/saved-run.json" if version == 1 else "res://tests/fixtures/worktree-return/day1/saved-run.json"
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
		var backup_source: String = "res://tests/fixtures/m3-01/final-first/saved-run.json" if version == 1 else "res://tests/fixtures/m3-02/day2/saved-run.json"
		var backup_bytes: PackedByteArray = FileAccess.get_file_as_bytes(backup_source)
		var legacy: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
		for member: Dictionary in legacy.crew:
			member.id = int(member.id)
		if version == 2 and not legacy.last_day.is_empty():
			for key: String in legacy.last_day:
				if legacy.last_day[key] is float:
					legacy.last_day[key] = int(legacy.last_day[key])
			for index: int in range(legacy.last_day.ration_member_ids.size()):
				legacy.last_day.ration_member_ids[index] = int(legacy.last_day.ration_member_ids[index])
		var target: String = _path + "-legacy%d" % version
		_write(target, bytes)
		_write(target + ".bak", backup_bytes)
		var legacy_backup_hash: String = FileAccess.get_sha256(target + ".bak")
		var store: RunSave = RunSave.new(target)
		_expect(store.load_save() == OK and store.migrated_from == version and store.snapshot.schema_version == RunSave.SCHEMA_VERSION, "actual archived v%d migrates in memory" % version)
		_expect(store.snapshot.weapons.size() == 2 and store.snapshot.weapons[0].origin == "migration-v%d" % version
			and store.snapshot.profile_id == legacy.profile_id and store.snapshot.crew[0].health == legacy.crew[0].health and store.snapshot.crew[1].health == legacy.crew[1].health and store.snapshot.cash == legacy.cash,
			"v%d migration preserves old identity, cash, health and initializes only documented starter gear" % version)
		if version == 2:
			_expect(store.snapshot.food == legacy.food and store.snapshot.last_day == legacy.last_day, "v2 migration retains exact food and ration history")
		_expect(FileAccess.get_file_as_bytes(target) == bytes and FileAccess.get_file_as_bytes(target + ".bak") == backup_bytes, "v%d read writes neither old primary nor backup" % version)
		_expect(store.save(store.snapshot) == OK and FileAccess.get_file_as_bytes(target + ".v%d-" % version + FileAccess.get_sha256(target + ".bak") + ".json") == bytes,
			"v%d first save keeps immutable byte-identical legacy original" % version)
		_expect(FileAccess.get_file_as_bytes(target + ".v%d-" % version + legacy_backup_hash + ".json") == backup_bytes,
			"v%d distinct legacy backup is independently retained before rotation" % version)
		_write(target, "{bad v3".to_utf8_buffer())
		_expect(store.load_save() != OK and store.load_save(true) == OK and FileAccess.get_file_as_string(target) == "{bad v3", "v%d checked backup survives invalid primary without silent replacement" % version)


func _sortie_checks(data: Dictionary) -> void:
	var sortie: Expedition = SortieScene.instantiate() as Expedition
	sortie.loadout_snapshot = WeaponInventory.snapshot(data)
	sortie.sortie_id = data.profile_id + ":2"
	root.add_child(sortie)
	sortie.set_physics_process(false)
	_expect(sortie.survivors[1].weapon_instance_id == WeaponInventory.for_member(data, 2).instance_id
		and sortie.survivors[1].visual.weapon_view.id == &"long_rifle", "normal expedition binds configured stable member to actual weapon view")
	var shooter: FieldActor = sortie.survivors[0]
	var other: FieldActor = sortie.survivors[1]
	other.activity = FieldActor.Activity.SEARCHING
	shooter.position = Vector2(800, 650)
	shooter.weapon_definition.damage = 7.0
	shooter.weapon_definition.interval = 1.7
	shooter.weapon_definition.shot_range = 50.0
	var enemy: FieldActor = sortie._make_actor(true, 99, Vector2(900, 650))
	enemy.health = 100.0
	sortie.enemies.append(enemy)
	sortie._update_combat()
	_expect(enemy.health == 100.0, "isolated weapon config range excludes a target inside former global range")
	enemy.position = Vector2(840, 650)
	sortie._update_combat()
	_expect(enemy.health == 93.0 and shooter.cooldown == 1.7, "same combat algorithm injects per-instance definition damage and interval")
	_expect(WeaponInventory.Definitions[0].damage == 18.0 and other.weapon_definition.damage == 18.0, "runtime fixture edits cannot mutate shared static definitions or other actors")
	sortie.toggle_pause()
	sortie.step(5.0)
	_expect(shooter.cooldown == 1.7 and enemy.health == 93.0, "pause freezes weapon cooldown and attack timing")
	sortie.toggle_pause()
	other.clear_order()
	shooter.clear_order()
	shooter.position = sortie.layout.cash_door
	var collects: Array[int] = []
	sortie.search_completed.connect(func(amount: int) -> void: collects.append(amount))
	sortie.tuning.search_seconds = 0.2
	sortie.request_search()
	sortie._update_search(0.3)
	_expect(sortie.weapon_loot == [WeaponInventory.reward(sortie.sortie_id)] and collects.size() == 1, "real search completion creates one identified damaged sample with one existing collect event")
	sortie.request_search()
	sortie._update_search(1.0)
	_expect(sortie.weapon_loot.size() == 1 and collects.size() == 1, "completed source cannot generate another instance or sound")
	var reports: Array[Dictionary] = []
	sortie.finished.connect(func(report: Dictionary) -> void: reports.append(report))
	sortie._finish(false)
	sortie._finish(true)
	_expect(reports.size() == 1 and reports[0].weapons.is_empty(), "failed and repeated finish cannot emit or bank carried weapon")
	sortie.queue_free()
	await process_frame


func _app_checks() -> void:
	var app: Node = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	app.continue_game()
	app.open_loadout()
	_expect(app.loadout_panel.visible, "real app opens inventory only at validated camp")
	app.open_expedition()
	_expect(app.expedition == null, "inventory modal blocks underlying start action")
	app.close_loadout()
	app.open_expedition()
	app.expedition.set_physics_process(false)
	app.open_loadout()
	_expect(not app.loadout_panel.visible, "inventory cannot open over live or paused sortie")
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout


func _state() -> Dictionary:
	var data: Dictionary = {"schema_version":RunSave.SCHEMA_VERSION, "profile_id":"0123456789abcdef0123456789abcdef", "day":2,
		"cash":53, "food":2, "crew":[{"id":1,"health":200.0},{"id":2,"health":196.0}],
		"settled_sorties":0, "last_settlement_id":"", "last_day":{}}
	WeaponInventory.initialize(data, "initial")
	SurvivorRoster.initialize(data.crew)
	return data


func _write(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _expect(condition: bool, label: String) -> void:
	_results.append({"passed":condition, "label":label})
	if not condition:
		_failures += 1
		push_error("FAIL weapon: " + label)
	else:
		print("PASS weapon: " + label)
