class_name RescuePlaytest
extends RecoveryPlaytest
## Explicit native/portable process proof; uses real UI and original gameplay intents.

var rescue_case: String = "first"


func _enter() -> void:
	if not app._requires_continue:
		await super._enter()
		return
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_expect(not app._progress_blocked and app._camp_open,"single Continue and explicit trial confirmation activate same camp")


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--rescue-case="): rescue_case = arg.trim_prefix("--rescue-case=")
		if arg.begins_with("--rescue-expected="): expected_path = arg.trim_prefix("--rescue-expected=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _settle()
	await get_tree().create_timer(0.3).timeout
	if rescue_case in ["save","resave","finish","three-save","three-resave","three-finish","blocked","first-write"]:
		await _recovery_case()
		await _finish_rescue()
		return
	await _enter()
	_initial = app.camp_snapshot()
	_expect(app.rescue_mode and _initial.schema_version == 103,"explicit independent103 trial, never modifies old v5/101/102")
	if rescue_case == "hold":
		_write(output_dir.path_join("holding.json"),{"pid":OS.get_process_id()})
		for frame: int in range(1000):
			if FileAccess.file_exists(output_dir.path_join("release")): break
			await get_tree().create_timer(0.03).timeout
		await _finish_rescue()
		return
	if rescue_case == "continue":
		_expect(_initial.crew.size() == 3 and _initial.recruits.size() == 1,"independent Continue keeps sole original recruit and three identities")
		_expect(app._camp_backdrop.visible_member_ids == _initial.journey.active_member_ids,"camp shows only actual survivors; dead members remain history")
		await _capture("continued-three.png")
	else:
		await _open_map(2 if rescue_case in ["first","skip","incomplete","danger","ready","ack"] else 0)
		var world: Expedition = app.expedition
		if world != null:
			world.set_physics_process(false)
			_expect(world.survivors.size() == _initial.journey.active_member_ids.size(),"all actual living members deployed")
			world.finished.connect(func(value: Dictionary) -> void: _reports.append(value.duplicate(true)))
			await _rescue_ui(world)
			if rescue_case in ["death3","sole2"]:
				await _real_death(world)
			if world.rescue_target != null:
				await _capture("rescue-visible.png")
				if rescue_case == "incomplete":
					for frame: int in range(1800):
						if world.elapsed >= world.tuning.bus_ready_seconds: break
						await _step(world)
					world.request_bus_action()
					await _tap(world.rescue_target.button)
					for frame: int in range(900):
						if world.rescue_target.progress > 1.0: break
						await _step(world)
					for frame: int in range(180):
						if world.phase == Expedition.Phase.BOARDING: break
						await _step(world)
					world.request_bus_gather()
					_expect(world.rescue_target.status == "AVAILABLE" and world.rescue_target.progress > 1.0,"boarding gather cancels partial assistance even if previous goal was already bus")
				elif rescue_case != "skip":
					await _tap(world.rescue_target.button)
					for frame: int in range(1800):
						if world.rescue_target.status == "RESCUED": break
						await _step(world)
					_expect(world.rescue_target.status == "RESCUED" and app.crew.size() == 2,"real arrival and ten seconds rescue do not add camp member early")
					await _capture("rescued-walking.png")
					if rescue_case == "danger":
						app.request_exit("home")
						await _settle()
						await _tap(app.pause_menu.buttons[1])
						_expect(app._progress_blocked and app.crew.size() == 2 and app._recruits.is_empty(),"completed assistance without real evacuation cannot grant or create READY")
						await _capture("danger-blocked.png")
						await _finish_rescue()
						return
			world.request_search(&"cash")
			for frame: int in range(3600):
				if world.searched: break
				await _step(world)
			if rescue_case in ["first","ready","ack"]:
				world.request_search(&"food")
				for frame: int in range(3600):
					if world._food_site.searched: break
					await _step(world)
			await _capture("search-combat.png")
			for frame: int in range(1800):
				if world.elapsed >= world.tuning.bus_ready_seconds: break
				await _step(world)
			world.request_bus_action()
			for frame: int in range(180):
				if world.phase == Expedition.Phase.BOARDING: break
				await _step(world)
			world.request_bus_gather()
			for frame: int in range(3600):
				if world.phase == Expedition.Phase.FINISHED: break
				await _step(world)
			_expect(_reports.size() == 1 and _reports[0].evacuated and not app._pending_settlement.is_empty(),"real all-member bus evacuation freezes exactly one original result")
			await _capture("frozen-result.png")
			if rescue_case != "ready" and not app._pending_settlement.is_empty():
				if rescue_case == "ack": app.progress_session.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point == "before_commit_receipt" else OK
				await _tap(app.get_node("Interface/Screen/Result/Continue"))
				if rescue_case == "ack":
					_expect(app._progress_dirty and app.camp_snapshot().crew.size() == 2,"ACK failure does not announce recruitment or apply camp early")
					await _capture("ack-failed.png")
					app.progress_session.fault_hook = Callable()
					await _tap(app._retry_button)
				var state: Dictionary = app.progress_session.inspect()
				_expect(state.error == OK and state.state == "CAMP","same transaction commits camp with acknowledged binding")
				var after: Dictionary = app.camp_snapshot()
				_expect(after.crew.size() == (2 if rescue_case in ["skip","incomplete"] else 3),"only completed rescue plus evacuation grants sole third member")
				_expect(after.last_day.food_required == _reports[0].member_results.filter(func(row: Dictionary) -> bool: return row.health > 0).size(),"rations follow actual post-battle participants; new recruit joins after first meal")
				var bytes: String = _digest()
				app.progress_session.activate()
				_expect(bytes == _digest(),"repeat activation cannot duplicate recruit, gun, food or date")
				await _capture("camp-after.png")
				if after.crew.size() == 3:
					app.open_roster()
					await _settle()
					await _tap(app.roster_panel.member_buttons[2])
					_expect(app.roster_panel.selected_member_id == 3,"third real profile is selectable without remapping original1/2")
					await _capture("third-profile.png")
					app.close_roster()
					app.open_loadout()
					await _settle()
					await _capture("third-equipment.png")
					if _initial.journey.active_member_ids.size() >= 2 and after.journey.active_member_ids.size() == 3:
						var original: String = WeaponInventory.for_member(after,3).instance_id
						var other: String = WeaponInventory.for_member(after,2).instance_id
						await _select_item(app.loadout_panel,other)
						await _tap(app.loadout_panel.equip_buttons[2])
						_expect(WeaponInventory.for_member(app.camp_snapshot(),3).instance_id == other,"third actual equip control exchanges unique existing instances")
						await _capture("third-long-rifle.png")
						await _select_item(app.loadout_panel,original)
						await _tap(app.loadout_panel.equip_buttons[2])
						_expect(WeaponInventory.for_member(app.camp_snapshot(),3).instance_id == original and app.food == after.food,"reversible camp exchange preserves identities and food")
					app.close_loadout()
	await _finish_rescue()


func _finish_rescue() -> void:
	_write(output_dir.path_join("report.json"),{"pid":OS.get_process_id(),"checks":_checks,"failures":_failures,"case":rescue_case,"initial":_initial,"camp":app.camp_snapshot(),"reports":_reports,"window_size":DisplayServer.window_get_size(),"input_layer":"native viewport / gameplay intents, NOT physical OS"})
	app.audio.shutdown()
	# Let the existing audio worker release pending UI one-shots before process exit.
	OS.delay_msec(150)
	await _settle()
	get_tree().quit(0 if _failures == 0 else 1)


func _rescue_ui(world: Expedition) -> void:
	await _key_battle(KEY_ESCAPE)
	await _layout("dynamic-roster")
	await _frozen(world,"dynamic-roster")
	await _key_battle(KEY_ESCAPE)
	await _tap(world._hud.view._help_button)
	await _key_battle(KEY_ESCAPE)
	_expect(not world._hud.view._help.visible and not app.pause_menu.root.visible,"help closes before Esc menu, actual dynamic HUD is accessible")
	if world.rescue_target != null:
		var target: RescueTarget = world.rescue_target
		await _tap(target.button)
		await _tap(target.button)
		_expect(target.status == "AVAILABLE" and target.worker == 0,"repeat click cancels sole assignment without duplicate target")
		await _tap(target.button)
		world.command_move(world.layout.bus_door)
		_expect(target.status == "AVAILABLE","ordinary movement cancels rescue assignment")
		await _tap(target.button)
		world.request_search(&"cash")
		_expect(target.status == "AVAILABLE" and world.search_actor != null,"search owns worker exclusively; rescue releases before indoor assignment")
		world.request_search(&"cash")
		await _settle()
		var rect: Rect2 = target.button.get_global_rect()
		_expect(get_viewport().get_visible_rect().encloses(rect) and not rect.intersects(world._hud.view._bus_button.get_global_rect()),"rescue action fits viewport and does not cover bus action")
		await _capture("rescue-ui.png")


func _save_world(world: Expedition) -> void:
	await _key_battle(KEY_ESCAPE)
	await _layout("rescue-suspend")
	captured = SortieSnapshot.capture(world)
	_write(output_dir.path_join("snapshot.json"),captured)
	await _capture("suspend-world.png")
	await _tap(app.pause_menu.buttons[4])
	var state: Dictionary = app.progress_session.inspect()
	_expect(app.expedition == null and state.get("state") == "SUSPENDED" and TransactionReceipt.same(captured,state.receipt.envelope.world),"ACK preserves full rescue/NPC/three-member world before leaving")
	_reject_replays("fresh-suspend")


func _recovery_case() -> void:
	if rescue_case == "blocked":
		_expect(app._progress_blocked and not app._requires_continue,"corrupt binding/journal or unfinished rescue blocks, never invents recruit")
		await _capture("blocked.png")
		return
	if rescue_case == "first-write":
		app.progress_session.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point == "before_foundation_write" else OK
		await _tap(app._home_button)
		await _tap(app._new_game_confirmation.get_ok_button())
		_expect(app._progress_blocked and app.expedition == null and not app.run_save.has_files(),"first foundation failure cannot enter or add a survivor")
		await _capture("first-write-failed.png")
		return
	if rescue_case in ["save","three-save"]:
		await _enter()
		_initial = app.camp_snapshot()
		await _open_map(2 if rescue_case == "save" else 0)
		var world: Expedition = app.expedition
		if world == null: return
		await _rescue_ui(world)
		if world.rescue_target != null:
			world.rescue_target.request()
			for frame: int in range(1200):
				if world.rescue_target.progress > 2.0: break
				await _step(world)
			_expect(world.rescue_target.status == "IN_PROGRESS" and world.rescue_target.progress > 2.0,"S1 captures partial real assistance rather than already granted member")
		else:
			world.request_search(&"cash")
			for frame: int in range(300): await _step(world)
		await _save_world(world)
		return
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
	_expect(app.expedition != null,"one Continue restores exact rescue world into fresh PID")
	if app.expedition == null: return
	var world: Expedition = app.expedition
	world.set_physics_process(false)
	_initial = app.camp_snapshot()
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	captured = SortieSnapshot.capture(world)
	_write(output_dir.path_join("restored.json"),captured)
	_expect(TransactionReceipt.same(captured,old),"all authoritative actors, rescue progress/NPC path and clock equal across processes")
	for record: String in DirAccess.get_directories_at(app.progress_path+".txn/journal"):
		var path: String = (app.progress_path+".txn/journal").path_join(record).path_join("record.json")
		if FileAccess.file_exists(path):
			var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)).payload
			if payload.phase == "SUSPEND_READY": replay_tokens.append({"token":RunTransaction.token_for(payload),"hash":payload.envelope.world_hash,"generation":payload.envelope.previous_head})
	_reject_replays("claimed-world")
	await _capture("restored-paused.png")
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused: await _key_battle(KEY_SPACE)
	if rescue_case in ["resave","three-resave"]:
		var start: float = world.elapsed
		for frame: int in range(1500):
			if world.elapsed >= start+12.0: break
			await _step(world)
		_expect(world.elapsed >= start+12.0,"claimed S1 truly advances twelve seconds before S2")
		if world.rescue_target != null: _expect(world.rescue_target.status == "RESCUED","S2 captures completed rescue/NPC walking after partial S1")
		await _save_world(world)
		return
	world.finished.connect(func(value: Dictionary) -> void: _reports.append(value.duplicate(true)))
	if world.search_actor == null and not world.searched: world.request_search(&"cash")
	for frame: int in range(3600):
		if world.searched: break
		await _step(world)
	if world.rescue_target != null:
		world.request_search(&"food")
		for frame: int in range(3600):
			if world._food_site.searched: break
			await _step(world)
	for frame: int in range(1800):
		if world.elapsed >= world.tuning.bus_ready_seconds: break
		await _step(world)
	world.request_bus_action()
	for frame: int in range(180):
		if world.phase == Expedition.Phase.BOARDING: break
		await _step(world)
	world.request_bus_gather()
	for frame: int in range(3600):
		if world.phase == Expedition.Phase.FINISHED: break
		await _step(world)
	_expect(not app._pending_settlement.is_empty(),"resumed rescue follows real bus to original READY")
	_reject_replays("RESULT_READY")
	await _capture("resumed-result.png")
	if not app._pending_settlement.is_empty():
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_expect(app.camp_snapshot().recruits.size() == 1 and app.camp_snapshot().crew.size() == 3,"S2 commit recruits exactly once, retains original crew")
		_reject_replays("COMMITTED")
		await _capture("resumed-camp.png")


func _real_death(world: Expedition) -> void:
	_expect(_initial.food == 12 and _initial.crew.all(func(row: Dictionary) -> bool: return row.health == 4),"explicit labelled low-HP fixture; not natural rescue difficulty")
	world.drill_panel.queue_free()
	world.battle_drill = true
	world.drill_panel = BattleDrillPanel.new()
	world.drill_panel.expedition = world
	world._hud.view.add_child(world.drill_panel)
	await _settle()
	# Explicit contact fixture: hold existing fire cooldowns until original AI can land its attack.
	for actor: FieldActor in world.survivors: actor.cooldown = 999.0
	for id: int in ([3,1] if rescue_case == "sole2" else [3]):
		var actor: FieldActor = world.drill_panel._member(id)
		await _tap(world.drill_panel.buttons[id-1])
		for frame: int in range(240):
			if actor.permanent_death: break
			await _step(world)
		_expect(actor.permanent_death and actor.health == 0,"real AI and original transaction confirm stable ID%d death" % id)
	_expect(world.boarding_status().required == (1 if rescue_case == "sole2" else 2),"bus denominator excludes confirmed deaths")
	for actor: FieldActor in world.survivors: actor.cooldown = 0.0
	await _capture("actual-death.png")
