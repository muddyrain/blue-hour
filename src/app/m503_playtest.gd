class_name M503Playtest
extends M502Playtest
## Native factual-growth proof. Uses normal UI and real fatal shots, never injects XP.

var _growth_mode: String = ""
var _growth_events: Array[Dictionary] = []
var _journal_visits: Array[Dictionary] = []


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m402-mode="):
			_growth_mode = argument.trim_prefix("--m402-mode=")
	app.get_node("World").child_entered_tree.connect(_connect_growth)
	if _growth_mode not in ["legacy", "custom", "custom-reopen", "corrupt"]:
		await super._run()
		return
	_sequence = _growth_mode
	_identity_mode = _growth_mode
	_mode = _growth_mode
	DirAccess.make_dir_recursive_absolute(output_dir)
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path + ".bak")
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	await _capture("m503-legacy-home")
	if _growth_mode == "corrupt":
		_expect(app._progress_blocked and app._backup_button.visible, "bad primary requires explicit valid backup selection")
		_expected = app._backup_save.duplicate(true)
		await _click_screen(app._backup_button.get_global_rect().get_center())
	else:
		_expect(app._requires_continue, "native process offers existing campaign")
		_expected = app._pending_save.duplicate(true)
		await _click_screen(app._continue_button.get_global_rect().get_center())
	_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash
		and _hash(app.run_save.path + ".bak") == _initial_backup_hash, "read-only Continue migrates in memory without touching original primary or backup")
	var restored_source: RunSave = app.run_save
	if _growth_mode == "corrupt":
		# Main intentionally uses a separate reader for explicit backup selection.
		restored_source = RunSave.new(app.run_save.path)
		_expect(restored_source.load_save(true) == OK and restored_source.snapshot == _expected,"selected backup independently validates to the exact restored camp")
	_expect(restored_source.migrated_from == (0 if _growth_mode == "custom-reopen" else 4), "selected historical v4 source is explicitly migrated; reopened v5 needs none")
	_before = app.camp_snapshot()
	for member: Dictionary in _before.crew:
		_expect(member.growth == SurvivorGrowth.empty_state(), "v4 retains service but never backfills historical growth or journal")
	if _growth_mode == "legacy":
		await _locked_first_save()
	elif _growth_mode == "custom":
		await _rename(1,"蓝时归航观察员一号同行者")
		await _rename(2,"NorthStar_02")
		_expect(_hash(app.run_save.path + ".v4-" + _initial_save_hash + ".json") == _initial_save_hash
			and _hash(app.run_save.path + ".v4-" + _initial_backup_hash + ".json") == _initial_backup_hash, "first successful native v5 write archives both distinct original v4 files")
		var names_only: Dictionary = _before.duplicate(true)
		names_only.crew[0].call_sign = app.crew[0].call_sign
		names_only.crew[1].call_sign = app.crew[1].call_sign
		_expect(app.camp_snapshot() == names_only,"Chinese and English aliases change no preexisting service, weapon or resource fields")
	_before = app.camp_snapshot()
	await _profiles()
	await _key(KEY_ESCAPE)
	await _enter_task()
	await _key(KEY_SPACE)
	_expect(app.camp_snapshot() == _before,"legacy field entry adds no XP, healing or hypothetical traits")
	await _capture("m503-legacy-field")
	await _finish_proof()


func _locked_first_save() -> void:
	_write_json("hold-lock.request",{"reason":"native v4 first v5 write fails under actual Windows handle"})
	await _runner_signal("lock-held.json")
	await _click_screen(app._roster_button.get_global_rect().get_center())
	var panel: RosterPanel = app.roster_panel
	await _click_screen(panel.name_edit.get_global_rect().get_center())
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_A
	key.ctrl_pressed = true
	key.pressed = true
	get_viewport().push_input(key)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	get_viewport().push_input(key)
	for character: String in "LegacyPilot":
		var event: InputEventKey = InputEventKey.new()
		event.unicode = character.unicode_at(0)
		event.pressed = true
		get_viewport().push_input(event)
		event = event.duplicate() as InputEventKey
		event.pressed = false
		get_viewport().push_input(event)
	await _click_screen(panel.save_button.get_global_rect().get_center())
	_expect(app._progress_dirty and _hash(app.run_save.path) == _initial_save_hash
		and _hash(app.run_save.path + ".bak") == _initial_backup_hash,"locked first v5 write preserves both distinct v4 bytes and retryable in-memory edit")
	await _capture("m503-locked-first-write")
	_write_json("release-lock.request",{})
	await _runner_signal("lock-released.json")
	await _key(KEY_ESCAPE)
	await _click_screen(app._retry_button.get_global_rect().get_center())
	_expect(not app._progress_dirty and app.run_save.load_save() == OK and app.run_save.snapshot == app.camp_snapshot(),"unlocked real retry writes exact in-memory v5 once")
	_expect(_hash(app.run_save.path + ".v4-" + _initial_save_hash + ".json") == _initial_save_hash
		and _hash(app.run_save.path + ".v4-" + _initial_backup_hash + ".json") == _initial_backup_hash,"native retry preserves primary and distinct backup in separate byte-exact v4 archives")
	var edited: Dictionary = _before.duplicate(true)
	edited.crew[0].call_sign = "LegacyPilot"
	_expect(app.camp_snapshot() == edited,"failed-save retry changes only the requested alias plus in-memory v4 migration")


func _connect_growth(node: Node) -> void:
	if node is Expedition:
		var sortie: Expedition = node
		sortie.growth_input_recorded.connect(func(event: Dictionary) -> void:
			var sample: Dictionary = event.duplicate(true)
			sample["sortie_id"] = sortie.sortie_id
			sample["movie_frame"] = Engine.get_frames_drawn()
			_growth_events.append(sample))


func _profiles() -> void:
	await super._profiles()
	await _journal()


func _journal() -> void:
	var before: Dictionary = app.camp_snapshot()
	var primary: String = _hash(app.run_save.path)
	var backup: String = _hash(app.run_save.path + ".bak")
	await _click_screen(app.roster_panel.growth_button.get_global_rect().get_center())
	_expect(app.growth_panel.visible and not app.roster_panel.visible,"real roster button opens usable growth journal")
	var panel: GrowthPanel = app.growth_panel
	for member_id: int in [1,2]:
		await _click_screen(panel.member_buttons[member_id-1].get_global_rect().get_center())
		var member: Dictionary = SurvivorRoster.member(before.crew,member_id)
		var action: Dictionary = member.growth.last_action
		_expect(panel._identity.text == SurvivorRoster.definition(member_id).default_display_name
			and panel._alias.text == "呼号：" + String(member.call_sign),"journal keeps formal identity, gender and full saved call sign")
		_expect(panel.training_button.disabled and panel.training_button.pressed.get_connections().is_empty()
			and panel.status.text.contains("尚未开放"),"unknown growth and food training cannot be performed")
		await _click_screen(panel.training_button.get_global_rect().get_center())
		_expect(panel.records.get_child_count() == (1 if action.is_empty() or action.recent.is_empty() else action.recent.size()),"visible journal rows come only from this saved member's actual receipts")
		var screen: Rect2 = get_viewport().get_visible_rect()
		for control: Control in [panel,panel.training_button,panel.back_button,panel._alias,panel.scroll]:
			_expect(screen.encloses(control.get_global_rect()),"growth controls and alias remain within actual viewport")
		_journal_visits.append({"member_id":member_id,"action":action.duplicate(true),"movie_frame":Engine.get_frames_drawn(),"size":get_viewport().get_visible_rect().size})
		await super._capture("m503-journal-%d" % member_id)
		await _wait(1.0)
	await _key(KEY_ESCAPE)
	_expect(app.roster_panel.visible and app.roster_panel.selected_member_id == 2,"Escape returns to last selected member profile")
	_expect(app.camp_snapshot() == before and _hash(app.run_save.path) == primary and _hash(app.run_save.path + ".bak") == backup,"journal browsing and disabled training preserve all resources, health, equipment and both save bytes")


func _capture(file_name: String) -> void:
	await super._capture(file_name)
	if file_name == "m402-018-saved-service":
		await _journal()


func _enter_task() -> void:
	await super._enter_task()
	if not app.expedition.is_practice:
		_expect(app.expedition.crew_snapshot == app.crew,"new sortie receives exact persisted member state including previous factual journal")


func _finish_proof() -> void:
	for input: Dictionary in _growth_events:
		var receipt: Dictionary = input.receipt
		_expect(_feedback.any(func(shot: Dictionary) -> bool:
			return (shot.get("kind") == "shot" and shot.get("target_health") == 0.0
				and shot.get("target") == receipt.enemy_id and shot.get("member_id") == input.member_id
				and shot.get("instance_id") == receipt.instance_id and floori(float(shot.get("elapsed")) * 1000.0) == receipt.at_ms)),"every growth input matches a real fatal shot by the same member and actual equipped instance")
	for report: Dictionary in _sortie_reports:
		if not report.has("growth_inputs"):
			continue
		var total: int = 0
		for member: Dictionary in report.growth_inputs.members:
			total += int(member.total)
			_expect(member.total == _growth_events.filter(func(event: Dictionary) -> bool:
				return event.sortie_id == report.growth_inputs.sortie_id and event.member_id == member.member_id).size(),"settlement member totals equal real emitted fatal inputs")
		_expect(total == report.kills,"journal input sum equals actual sortie kills without XP conversion")
	for member: Dictionary in app.crew:
		_expect(member.growth.level == null and member.growth.experience == null
			and member.growth.trait == {"id":null,"level":null,"progress":null}
			and member.growth.training_state == "unavailable","no process invents a character level, XP, trait progress or trainable rule")
	_write_json("survivor-growth-report.json",{"mode":_growth_mode,"fatal_inputs":_growth_events,"journal_visits":_journal_visits,
		"scope":"Normal mission fatal shots only. Recent journal is factual engineering; formal levels, XP, trait effects and food training remain unavailable. Legacy v4 only gains empty unknown growth in memory."})
	await super._finish_proof()
