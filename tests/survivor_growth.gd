extends SceneTree
## Factual-input/save engineering. No fixture here proves a playable level-up rule.

const MAIN: PackedScene = preload("res://src/app/main.tscn")
var _results: Array[Dictionary] = []
var _failures: int = 0
var _path: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			_path = argument.trim_prefix("--bh-progress=")
	root.size = Vector2i(1280,720)
	var app: Node = MAIN.instantiate()
	root.add_child(app)
	await process_frame
	var before: Dictionary = app.camp_snapshot()
	_expect(before.schema_version == 5 and before.crew[0].growth == SurvivorGrowth.empty_state(), "fresh v5 stores unknown character and trait values, not XP zero or level one")
	app.open_expedition()
	var sortie: Expedition = app.expedition
	sortie.set_physics_process(false)
	sortie.elapsed = 49.3833333333318
	sortie._spawn_clock = INF
	sortie._ai_clock = INF
	var first: FieldActor = sortie.survivors[0]
	var second: FieldActor = sortie.survivors[1]
	first.position = Vector2(688,1120)
	second.position = Vector2(736,1120)
	var target: FieldActor = sortie._make_actor(true,80,Vector2(808,1120))
	sortie.enemies.append(target)
	var inputs: Array[Dictionary] = []
	sortie.growth_input_recorded.connect(func(event: Dictionary) -> void: inputs.append(event.duplicate(true)))
	sortie._update_combat()
	_expect(target.health == 18.0 and inputs.is_empty(), "two real nonfatal shots do not produce two growth inputs")
	first.cooldown = 0.0
	second.cooldown = 0.0
	sortie._update_combat()
	_expect(inputs.size() == 1 and inputs[0].member_id == 1 and inputs[0].receipt.enemy_id == 80 and first.confirmed_kills == 1 and second.confirmed_kills == 0, "actual fatal shot credits only its stable member, not the enemy actor field")
	_expect(inputs[0].receipt.instance_id == first.weapon_instance_id and inputs[0].receipt.weapon_id == String(first.weapon_definition.id), "input references actual equipped instance and definition")
	_expect(sortie.growth_inputs.accept_defeat(second,target,0.0).is_empty(), "second gun and duplicate target callback cannot credit the same corpse twice")
	var healthy: FieldActor = sortie._make_actor(true,81,Vector2(808,1120))
	_expect(sortie.growth_inputs.accept_defeat(first,healthy,0.0).is_empty(), "healthy/hit-only target cannot enter death input adapter")
	healthy.queue_free()
	sortie._finish(true)
	var proposal: Dictionary = app._pending_settlement.duplicate(true)
	_expect(not proposal.is_empty() and app.camp_snapshot() == before and proposal.crew[0].growth.last_action.total == 1, "preview has one journal proposal but camp is unchanged")
	var callback: Callable = app._finish_callback
	callback.call({})
	_expect(app._pending_settlement == proposal and app.camp_snapshot() == before, "duplicate result cannot bank a second input")
	app.return_to_title()
	_expect(app.camp_snapshot() == proposal and app.run_save.load_save() == OK and app.run_save.snapshot == proposal, "normal return commits one real journal through existing save boundary")
	callback.call({})
	_expect(app.camp_snapshot() == proposal, "post-commit duplicate cannot repeat service or journal")
	_reject_bad_states(proposal)
	var invalid: Dictionary = {"evacuated":true,"loot":0,"food":0,"health":[200.0,200.0],"kills":0,
		"elapsed":0.0,"member_records":[{"id":1,"kills":0,"damage_received":0.0},{"id":2,"kills":0,"damage_received":0.0}],
		"growth_inputs":{"sortie_id":before.profile_id+":1","map_id":"market_loop","duration_ms":0.0,
			"members":[{"member_id":1,"total":0,"recent":[]},{"member_id":2,"total":0,"recent":[]}]}}
	_expect(CampEconomy.preview(proposal,invalid,before.profile_id+":2",app.camp_rules).is_empty(), "old sortie envelope cannot be reused for a new settlement")
	app.open_roster()
	app.rename_survivor(1,"成长观察员")
	var renamed: Dictionary = app.camp_snapshot()
	_expect(renamed.crew[0].growth == proposal.crew[0].growth and renamed.crew[0].definition_id == proposal.crew[0].definition_id, "renaming alias cannot rekey or reset recorded inputs")
	app.open_growth(1)
	await process_frame
	_expect(app.growth_panel.visible and app.growth_panel.training_button.disabled and app.growth_panel.records.get_child_count() == 1, "usable camp page shows actual journal, with training unavailable")
	var digest: String = FileAccess.get_sha256(_path)
	app.growth_panel.training_button.pressed.emit()
	app.open_expedition()
	_expect(app.camp_snapshot() == renamed and FileAccess.get_sha256(_path) == digest and app.phase == app.Phase.TITLE, "disabled training and background entry cannot consume resources or write through the panel")
	app.growth_panel.selected_member_id = 2
	app.close_growth()
	_expect(app.roster_panel.visible and app.roster_panel.selected_member_id == 2, "back returns to the selected immutable member profile")
	app.close_roster()
	app.open_expedition()
	app.expedition.set_physics_process(false)
	_expect(app.expedition.crew_snapshot == renamed.crew and app.expedition.survivors[0].max_health == 200.0, "next ordinary sortie reads journal snapshot without inventing health or damage bonuses")
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	var store: RunSave = RunSave.new(_path)
	_expect(store.load_save() == OK and store.snapshot == renamed and FileAccess.get_sha256(_path) == digest, "independent reader restores exact v5 state without writes")
	await _rolling_tail(renamed)
	_migrate_v4()
	var folder: String = _path.get_base_dir()
	var file: FileAccess = FileAccess.open(folder.path_join("survivor-growth-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":_results.size(),"failures":_failures,"results":_results,
		"scope":"Factual inputs and migration/UI engineering; formal XP/levels/traits/training remain closed."},"\t") + "\n")
	file.close()
	print("BH_SURVIVOR_GROWTH checks=%d failures=%d" % [_results.size(),_failures])
	quit(0 if _failures == 0 else 1)


func _reject_bad_states(valid: Dictionary) -> void:
	for mutation: String in ["level","xp","trait_id","trait_level","trait_progress","training","kind","negative_time","late_time","foreign_instance","weapon","identity","map","duplicate","cross_member","field"]:
		var data: Dictionary = valid.duplicate(true)
		var growth: Dictionary = data.crew[0].growth
		match mutation:
			"level": growth.level = 1
			"xp": growth.experience = 0
			"trait_id": growth.trait.id = "mechanic"
			"trait_level": growth.trait.level = 3
			"trait_progress": growth.trait.progress = 10
			"training": growth.training_state = "enabled"
			"kind": growth.last_action.recent[0].kind = "shot"
			"negative_time": growth.last_action.recent[0].at_ms = -0.1
			"late_time": growth.last_action.recent[0].at_ms = growth.last_action.duration_ms + 1
			"foreign_instance": growth.last_action.recent[0].instance_id = "another-profile:weapon"
			"weapon": growth.last_action.recent[0].weapon_id = "unknown"
			"identity": growth.last_action.settlement_id = "practice:1"
			"map": growth.last_action.map_id = "unknown"
			"duplicate":
				data.crew[0].service.kills = 2
				growth.last_action.total = 2
				growth.last_action.recent.append(growth.last_action.recent[0].duplicate(true))
			"cross_member":
				data.crew[1].service.kills = 1
				data.crew[1].growth.last_action = growth.last_action.duplicate(true)
			"field": growth["guessed_bonus"] = 10
		_expect(not RunSave.validate(data).is_empty(), "reject unverified/invalid progression input: " + mutation)


func _rolling_tail(data: Dictionary) -> void:
	var recorder: GrowthInputs = GrowthInputs.new()
	var actor: FieldActor = FieldActor.new()
	actor.actor_id = 0
	var item: Dictionary = WeaponInventory.for_member(data,1)
	actor.weapon_instance_id = item.instance_id
	actor.weapon_definition = WeaponInventory.definition(item.weapon_id)
	root.add_child(actor)
	for index: int in range(SurvivorGrowth.RECENT_LIMIT + 5):
		var enemy: FieldActor = FieldActor.new()
		enemy.is_enemy = true
		enemy.actor_id = 1000 + index
		root.add_child(enemy)
		enemy.take_damage(enemy.health,Vector2.RIGHT)
		_expect(not recorder.accept_defeat(actor,enemy,float(index)).is_empty() and recorder.accept_defeat(actor,enemy,float(index)).is_empty(), "actual DOWN node accepts once and rejects repeated adapter input")
		enemy.queue_free()
	var result: Dictionary = recorder.snapshot(data.profile_id+":99",&"market_loop",100.0)
	_expect(result.members[0].total == 37 and result.members[0].recent.size() == 32 and result.members[0].recent[0].enemy_id == 1005, "bounded recent tail retains total actual inputs without calling them experience")
	result.members[0].recent.clear()
	_expect(recorder.snapshot(data.profile_id+":99",&"market_loop",100.0).members[0].recent.size() == 32, "exported input snapshot cannot mutate live recorder")
	actor.queue_free()
	await process_frame


func _migrate_v4() -> void:
	var primary: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/m5-02/market/saved-run.json")
	var backup: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/m5-02/scavenge/saved-run.json")
	var target: String = _path + "-v4"
	_write(target,primary)
	_write(target+".bak",backup)
	var original: Dictionary = JSON.parse_string(primary.get_string_from_utf8())
	var store: RunSave = RunSave.new(target)
	_expect(store.load_save() == OK and store.migrated_from == 4, "real M5-02 v4 archive is accepted as read-only in-memory migration")
	var stripped: Dictionary = store.snapshot.duplicate(true)
	stripped.schema_version = 4
	for member: Dictionary in stripped.crew:
		member.erase("growth")
	# JSON arrays decode as Variant/float; compare after the same serialization normalization.
	var comparable: Dictionary = JSON.parse_string(JSON.stringify(stripped,"",true,true))
	_expect(comparable == original and FileAccess.get_file_as_bytes(target) == primary and FileAccess.get_file_as_bytes(target+".bak") == backup, "v4 unknown initialization preserves every old JSON value and both original byte streams")
	_expect(store.snapshot.crew[0].growth.last_action.is_empty() and store.snapshot.crew[0].growth.level == null, "historical service totals never become fictitious XP or past journal events")
	var a: String = FileAccess.get_sha256(target)
	var b: String = FileAccess.get_sha256(target+".bak")
	_expect(store.save(store.snapshot) == OK, "first explicit v5 save succeeds after legacy preservation")
	_expect(FileAccess.get_file_as_bytes(target+".v4-"+a+".json") == primary and FileAccess.get_file_as_bytes(target+".v4-"+b+".json") == backup, "first v5 write retains distinct primary and backup v4 originals byte-for-byte")
	_expect(store.load_save() == OK and store.migrated_from == 0, "saved v5 reopens without a repeated migration")


func _write(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _expect(value: bool, label: String) -> void:
	_results.append({"passed":value,"label":label})
	if not value:
		_failures += 1
		push_error("BH_SURVIVOR_GROWTH " + label)
