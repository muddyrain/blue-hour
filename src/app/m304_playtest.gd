class_name M304Playtest
extends M303Playtest
## Same renderer and ordinary controls as M3-03; no injected damage or XP.

var _injury_probe_done: bool = false


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m304-mode="):
			_sequence = argument.trim_prefix("--m304-mode=")
		if argument.begins_with("--m304-expected="):
			var store: RunSave = RunSave.new(argument.trim_prefix("--m304-expected="))
			_expect(store.load_save() == OK, "previous process snapshot validates")
			_expected = store.snapshot
	DirAccess.make_dir_recursive_absolute(output_dir)
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path + ".bak")
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue),"world":world,"accepted":accepted,"frame":Engine.get_frames_drawn()}))
	await _wait(0.5)
	await _capture("m304-001-boot")
	if _sequence != "first":
		_expect(app._requires_continue and app._pending_save == _expected, "independent process offers exact crew, equipment and resources")
		await _click_screen(app._continue_button.get_global_rect().get_center())
		app.continue_game()
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash, "Continue restores without writing or duplicating records")
	_before = app.camp_snapshot()
	_mode = "day1" if _sequence == "first" else "second"
	if _sequence == "first":
		await _rename(1, "Azure")
		await _rename(2, "Amber")
		_before = app.camp_snapshot()
	await _click_screen(app._roster_button.get_global_rect().get_center())
	await _capture("m304-002-roster")
	_expect(app.roster_panel._service.text.contains("等级与特性成长尚未启用"), "real profile never presents invented levels or abilities")
	if _sequence == "legacy":
		_expect(app.run_save.migrated_from == 3 and _before.camp_spending == 10, "real v3 repaired camp migrates without changing repair spending")
		for entry: Dictionary in _before.crew:
			_expect(entry.service.sorties == 0 and entry.service.kills == 0 and entry.service.damage_received == 0, "migration does not invent historical service or XP")
		await _key(KEY_ESCAPE)
		await _rename(1, "Veteran")
		_expect(_hash(app.run_save.path + ".v3-" + _initial_save_hash + ".json") == _initial_save_hash, "first migrated save retains byte-exact v3 original")
		_mode = _sequence
		await _finish_proof()
		return
	await _click_screen(app.roster_panel.equipment_button.get_global_rect().get_center())
	_expect(app.loadout_panel.visible and not app.roster_panel.visible, "profile opens the selected member's real equipment")
	await _capture("m304-003-profile-equipment")
	await _key(KEY_ESCAPE)
	_expect(app.roster_panel.visible, "equipment Escape returns to selected profile")
	await _key(KEY_ESCAPE)
	if _sequence in ["reopen", "legacy-reopen"]:
		if _sequence == "legacy-reopen":
			_expect(app.crew[0].call_sign == "Veteran" and app.crew[0].service.sorties == 0, "migrated rename and honest zero history survive another process")
		await _select_sortie(true)
		await _key(KEY_SPACE)
		await _capture("m304-004-restored-live-sortie")
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash, "unsettled reentry does not advance records or resources")
	else:
		await _check_audio_preferences()
		var kinds: Array[StringName] = [&"food", &"cash"]
		await _play_action(kinds)
		var kills: int = 0
		for entry: Dictionary in app.crew:
			var previous: Dictionary = SurvivorRoster.member(_before.crew, int(entry.id))
			_expect(entry.service.sorties == int(previous.service.sorties) + 1
				and is_equal_approx(entry.service.damage_received - previous.service.damage_received, previous.health - entry.health), "real member %d records one outing and exact received damage" % int(entry.id))
			kills += int(entry.service.kills) - int(previous.service.kills)
		_expect(kills == int(_sortie_reports[0].kills), "personal kills sum to actual sortie kills")
		if _sequence == "first":
			_expect(_feedback.any(func(event: Dictionary) -> bool: return event.get("kind") == "hit" and event.get("applied_damage", 0.0) > 0.0), "normal enemy combat produces a real injury")
			_carried_id = WeaponInventory.reward("%s:%d" % [app.profile_id, app.settled_sorties]).instance_id
			await _click_screen(app._loadout_button.get_global_rect().get_center())
			await _configure_weapons()
			await _key(KEY_ESCAPE)
		else:
			_expect(_feedback.any(func(event: Dictionary) -> bool: return event.get("kind") == "shot" and event.get("instance_id") == WeaponInventory.for_member(_before, 1).instance_id), "saved loot instance fires in the next real sortie")
		await _click_screen(app._roster_button.get_global_rect().get_center())
		await _capture("m304-010-saved-service")
		await _key(KEY_ESCAPE)
	_mode = _sequence
	await _finish_proof()


func _rename(member_id: int, value: String) -> void:
	await _click_screen(app._roster_button.get_global_rect().get_center())
	var panel: RosterPanel = app.roster_panel
	await _click_screen(panel.member_buttons[member_id - 1].get_global_rect().get_center())
	await _click_screen(panel.name_edit.get_global_rect().get_center())
	var select: InputEventKey = InputEventKey.new()
	select.keycode = KEY_A
	select.ctrl_pressed = true
	select.pressed = true
	get_viewport().push_input(select)
	select = select.duplicate() as InputEventKey
	select.pressed = false
	get_viewport().push_input(select)
	for index: int in range(value.length()):
		var event: InputEventKey = InputEventKey.new()
		event.unicode = value.unicode_at(index)
		event.pressed = true
		get_viewport().push_input(event)
		event = event.duplicate() as InputEventKey
		event.pressed = false
		get_viewport().push_input(event)
	await _click_screen(panel.save_button.get_global_rect().get_center())
	_expect(SurvivorRoster.member(app.crew, member_id).call_sign == value and not app._progress_dirty, "real name control saves member %d call sign" % member_id)
	var bytes: String = _hash(app.run_save.path)
	await _click_screen(panel.save_button.get_global_rect().get_center())
	_expect(_hash(app.run_save.path) == bytes and panel.message.text.contains("未重复"), "repeat rename leaves saved bytes unchanged")
	await _capture("m304-name-%d" % member_id)
	await _key(KEY_ESCAPE)


func _select_sortie(has_food: bool) -> void:
	await super._select_sortie(has_food)
	var sortie: Expedition = app.expedition
	for actor: FieldActor in sortie.survivors:
		var entry: Dictionary = SurvivorRoster.member(_before.crew, actor.actor_id + 1)
		_expect(actor.call_sign == entry.call_sign and actor.health == float(entry.health), "actual sortie restores saved identity and health")


func _until_inside(sortie: Expedition) -> void:
	await super._until_inside(sortie)
	if _sequence != "first" or _injury_probe_done:
		return
	_injury_probe_done = true
	# The outdoor guard waits at the east edge after a normal movement order.
	# Natural waves keep their original timings, health and combat parameters.
	sortie.command_move(Vector2(1776, 784))
	var attempts: int = 0
	while not _feedback.any(func(event: Dictionary) -> bool: return event.get("kind") == "hit") and attempts < 240:
		await _wait(0.1)
		attempts += 1
	await _capture("m304-005-real-combat-injury")
