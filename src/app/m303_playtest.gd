class_name M303Playtest
extends M302Playtest
## Opt-in real renderer proof; all gains come from normal searches and camp controls.

var _sequence: String = "first"
var _carried_id: String = ""


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m303-mode="):
			_sequence = argument.trim_prefix("--m303-mode=")
		if argument.begins_with("--m303-expected="):
			var saved: RunSave = RunSave.new(argument.trim_prefix("--m303-expected="))
			_expect(saved.load_save() == OK, "previous independent process snapshot validates")
			_expected = saved.snapshot
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path + ".bak")
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue), "world":world, "accepted":accepted, "frame":Engine.get_frames_drawn()})
	)
	await _wait(0.5)
	await _capture("m303-001-boot")
	if _sequence != "first":
		_expect(app._requires_continue and app._pending_save == _expected, "new process offers exact v3 inventory, loadout, food, cash, health and day")
		await _click_screen(app._continue_button.get_global_rect().get_center())
		app.continue_game()
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash, "Continue cannot duplicate loot or rewrite saved bytes")
	_before = app.camp_snapshot()
	_mode = "day1" if _sequence == "first" else "second"
	await _check_audio_preferences()
	await _capture("m303-002-continued-camp")
	if _sequence == "reopen":
		await _click_screen(app._loadout_button.get_global_rect().get_center())
		await _capture("m303-003-restored-inventory")
		await _key(KEY_ESCAPE)
		await _select_sortie(true)
		await _key(KEY_SPACE)
		await _capture("m303-004-third-process-equipped-sortie")
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash, "third process sortie and pause do not rewrite inventory or resources")
	else:
		# Food first in sortie two keeps member one outside, so the equipped gun
		# gets a real combat opportunity instead of spending the whole fight indoors.
		var kinds: Array[StringName] = [&"cash", &"food"]
		if _sequence == "second":
			kinds.assign([&"food", &"cash"])
		await _play_action(kinds)
		_expect(app.weapons.size() == _before.weapons.size() + 1, "one real northern search banks exactly one unique weapon")
		var reward: Dictionary = WeaponInventory.reward("%s:%d" % [app.profile_id, app.settled_sorties])
		_carried_id = reward.instance_id
		_expect(WeaponInventory.find(app.camp_snapshot(), _carried_id).condition == "damaged", "real loot enters camp damaged and unequipped")
		await _click_screen(app._loadout_button.get_global_rect().get_center())
		await _capture("m303-010-real-inventory")
		if _sequence == "first":
			await _configure_weapons()
		else:
			_expect(app.loadout == _before.loadout, "second complete sortie preserves prior ownership without resetting defaults")
			_expect(_feedback.any(func(event: Dictionary) -> bool: return event.get("kind") == "shot" and event.get("instance_id") == WeaponInventory.for_member(_before, 1).instance_id),
				"actual second-sortie combat fires the newly equipped loot instance")
		await _key(KEY_ESCAPE)
		await _capture("m303-015-equipped-saved-camp")
	_mode = _sequence
	await _finish_proof()


func _select_sortie(has_food: bool) -> void:
	await super._select_sortie(has_food)
	var sortie: Expedition = app.expedition
	for member_id: int in [1, 2]:
		var item: Dictionary = WeaponInventory.for_member(app.camp_snapshot(), member_id)
		var actor: FieldActor = sortie.survivors[member_id - 1]
		_expect(actor.weapon_instance_id == item.instance_id and String(actor.weapon_definition.id) == item.weapon_id
			and String(actor.visual.weapon_view.id) == item.weapon_id, "real sortie member %d uses saved instance, combat definition and presentation" % member_id)
	_expect(sortie.survivors[0].weapon_instance_id != sortie.survivors[1].weapon_instance_id, "two real actors never share one instance")
	await _capture("m303-005-actual-loadout-in-world")


func _choose(identity: String) -> void:
	var list: ItemList = app.loadout_panel.items
	for index: int in range(list.item_count):
		if list.get_item_metadata(index) == identity:
			# Rich v5 inventories can exceed one page. Scroll the requested native
			# row, then use its actual hit region; never click content coordinates
			# below the clipped list or change the inventory transaction directly.
			list.select(index)
			list.ensure_current_is_visible()
			await get_tree().process_frame
			var local: Vector2 = list.get_item_rect(index).get_center()
			local.y -= list.get_v_scroll_bar().value
			_expect(list.get_item_at_position(local,true) == index and Rect2(Vector2.ZERO,list.size).has_point(local),"requested inventory row is visible and hit-testable")
			# Programmatic view scrolling must not suppress the real selection signal.
			list.deselect_all()
			await _click_screen(list.get_global_rect().position + local)
			_expect(app.loadout_panel._selected_id == identity, "real inventory click selects " + identity)
			return
	_expect(false, "inventory instance exists: " + identity)


func _configure_weapons() -> void:
	var panel: LoadoutPanel = app.loadout_panel
	await _choose(app.profile_id + ":starter:2")
	await _click_screen(panel.equip_buttons[0].get_global_rect().get_center())
	_expect(WeaponInventory.for_member(app.camp_snapshot(), 2).weapon_id == "carbine"
		and WeaponInventory.for_member(app.camp_snapshot(), 1).weapon_id == "long_rifle", "owned weapon click swaps two existing instances, no cloning")
	var swapped: Dictionary = app.camp_snapshot()
	await _click_screen(panel.equip_buttons[0].get_global_rect().get_center())
	_expect(app.camp_snapshot() == swapped and panel.message.text.contains("未重复"), "repeated equip gives feedback without another mutation")
	await _capture("m303-011-swapped-existing-weapons")
	await _choose(_carried_id)
	_expect(panel.equip_buttons[0].disabled and not panel.repair_button.disabled, "damaged real loot visibly blocks equip before repair")
	await _click_screen(panel.repair_button.get_global_rect().get_center())
	_expect(panel.confirmation.visible, "repair opens cost confirmation before any cash change")
	await _capture("m303-012-repair-confirmation")
	await _key(KEY_ESCAPE)
	_expect(app.camp_snapshot() == swapped, "cancel repair changes neither cash nor weapon state")
	var saved_hash: String = _hash(app.run_save.path)
	var backup_hash: String = _hash(app.run_save.path + ".bak")
	_write_json("hold-lock.request", {"reason":"real repair save failure"})
	await _runner_signal("lock-held.json")
	await _click_screen(panel.repair_button.get_global_rect().get_center())
	await _click_dialog(panel.confirmation)
	_expect(app.cash == int(swapped.cash) - 10 and app.food == int(swapped.food) and app.day == int(swapped.day), "confirmed repair spends sample cost once, never food or date")
	_expect(app._progress_dirty and _hash(app.run_save.path) == saved_hash and _hash(app.run_save.path + ".bak") == backup_hash,
		"real Windows lock prevents repair save, preserves both bytes and keeps repaired state in memory")
	await _capture("m303-013-locked-repair-save")
	_write_json("release-lock.request", {"cash":app.cash})
	await _runner_signal("lock-released.json")
	await _key(KEY_ESCAPE)
	await _click_screen(app._retry_button.get_global_rect().get_center())
	_expect(not app._progress_dirty and app.cash == int(swapped.cash) - 10, "native retry persists repair without charging or granting again")
	await _click_screen(app._loadout_button.get_global_rect().get_center())
	await _click_screen(panel.equip_buttons[0].get_global_rect().get_center())
	_expect(WeaponInventory.for_member(app.camp_snapshot(), 1).instance_id == _carried_id
		and WeaponInventory.owner(app.camp_snapshot(), app.profile_id + ":starter:2") == 0, "loot goes to member one and previous weapon becomes idle")
	var configured: Dictionary = app.camp_snapshot()
	app.repair_weapon(_carried_id)
	app.equip_weapon(1, _carried_id)
	_expect(app.camp_snapshot() == configured and not app._progress_dirty, "duplicate camp requests cannot spend, clone or dirty a successful save")
	_expect(app.run_save.load_save() == OK and app.run_save.snapshot == configured, "real camp controls persist all ownership and repair state immediately")
	await _capture("m303-014-loot-equipped-and-saved")


func _runner_signal(file: String) -> void:
	var attempts: int = 0
	while not FileAccess.file_exists(output_dir.path_join(file)) and attempts < 200:
		await _wait(0.05)
		attempts += 1
	_expect(FileAccess.file_exists(output_dir.path_join(file)), "runner confirms " + file)


func _click_dialog(dialog: ConfirmationDialog) -> void:
	# Embedded windows receive root viewport input at their parent-relative position.
	var point: Vector2 = Vector2(dialog.position) + dialog.get_ok_button().get_global_rect().get_center()
	await _click_screen(point)
	_input_trace.append({"dialog":"repair", "point":point, "input":"root viewport at embedded window offset"})
