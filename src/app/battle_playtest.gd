class_name BattlePlaytest
extends P0D02APlaytest
## Real main/UI verification. A rendered frame accompanies every fixed world step in movies.

var _case: String = "first"
var _map: int = 0
var _victim: int = 1
var _stop: String = ""
var _events: Array[Dictionary] = []
var _reports: Array[Dictionary] = []
var _initial: Dictionary = {}


func _run() -> void:
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\","/").to_lower():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--battle-case="):
			_case = arg.trim_prefix("--battle-case=")
		if arg == "--battle-map=market":
			_map = 1
		if arg == "--battle-victim=2":
			_victim = 2
		if arg.begins_with("--battle-stop="):
			_stop = arg.trim_prefix("--battle-stop=")
		if arg.begins_with("--p0d-barrier="):
			_barrier = arg.trim_prefix("--p0d-barrier=")
	if app.progress_session != null:
		app.progress_session.fault_hook = _fault
	await _settle()
	match _case:
		"first", "single": await _play()
		"ended":
			await _enter()
			_expect(app._battle_meta.state=="FAILED" and app.phase==app.Phase.RESULT,"fresh process restores terminal UI, never a playable old camp")
			await _capture("terminal-reopened.png")
			await _tap(app.get_node("Interface/Screen/Result/Continue"))
			_expect(app._camp_backdrop.visible_member_ids.is_empty() and not app.get_node("Interface/Screen/Title/Start").visible, "zero living people in archived camp, no sortie entry")
			await _capture("ended-camp-history.png")
			await _hold(45)
		"observe":
			_expect(app._progress_blocked and not app._requires_continue,"missing/unfinished/corrupt journey is blocked before camp application")
			var original: String = _digest()
			app.open_expedition()
			_expect(app.expedition==null and original==_digest(),"blocked journey cannot mutate or reenter a sortie")
			await _capture("recovery-blocked.png")
		"new": await _enter()
		"resume":
			await _enter()
			_initial = app.camp_snapshot()
			_expect(not app._progress_blocked and app.progress_session.inspect().state=="CAMP","fresh Continue acknowledges the exact frozen battle camp")
		"preview-single":
			await _enter()
			var before: Dictionary = app.camp_snapshot()
			await _open_map(_map)
			_expect(not app.expedition.battle_drill and app.expedition.drill_panel.buttons.is_empty(),"ordinary isolated Continue does not silently enable nearby enemy rehearsal")
			_expect(app.expedition.survivors.size()==1 and app.expedition.survivors[0].health==SurvivorRoster.member(before.crew,app.expedition.survivors[0].member_id).health and app.food==before.food,"Continue restores original single-member HP and food without reseeding")
		"locked":
			_expect(app._requires_continue,"READY offers explicit recovery Continue")
			await _tap(app._continue_button)
			_expect(app._progress_blocked and app._progress_dirty,"real file refusal blocks recovery and offers same-result retry")
		"hold":
			_write(output_dir.path_join("barrier.json"),{"pid":OS.get_process_id()})
			var deadline: int = Time.get_ticks_msec()+45000
			while not FileAccess.file_exists(output_dir.path_join("release")) and Time.get_ticks_msec()<deadline:
				await get_tree().create_timer(0.05).timeout
		"legacy":
			_expect(app.progress_session==null and app._requires_continue,"legacy v5 remains an ordinary explicit Continue")
			var original: String = FileAccess.get_sha256(app.run_save.path)
			await _tap(app._continue_button)
			_expect(FileAccess.get_sha256(app.run_save.path)==original and app.crew[0].condition=="down" and app.crew[0].health==0,"old zero HP remains down without migration, healing or formal death")
		"restart": await _restart()
		_:
			_expect(false,"known battle verification case")
	await _hold(8)
	var state: Dictionary = app.progress_session.inspect() if app.progress_session != null else {"state":"LEGACY","reason":""}
	_write(output_dir.path_join("report.json"),{"checks":_checks,"failures":_failures,"case":_case,
		"pid":OS.get_process_id(),"display":DisplayServer.get_name(),"camp":app.camp_snapshot(),"state":state.get("state"),
		"blocked":app._progress_blocked,"reason":state.get("reason",""),"initial":_initial,"events":_events,"reports":_reports,
		"snapshots":_snapshots,"frame":Engine.get_frames_drawn(),"window_size":DisplayServer.window_get_size(),
		"visible_member_ids":app._camp_backdrop.visible_member_ids,
		"input_layer":"native viewport mouse/keyboard events and explicit world intentions; not OS input",
		"drill":"explicit initial4HP/food12 and user-visible nearby original enemy; not a natural-spawn risk estimate"})
	print("BH_BATTLE_VERIFY case=%s checks=%d failures=%d" % [_case,_checks.size(),_failures])
	app.audio.shutdown()
	OS.delay_msec(150)
	get_tree().quit(0 if _failures==0 else 1)


func _play() -> void:
	await _enter()
	if app._progress_blocked:
		return
	var before: Dictionary = app.camp_snapshot()
	_initial = before.duplicate(true)
	_expect(SurvivalState.extended_problem(before).is_empty() and not RunSave.validate(before).is_empty(),"isolated schema validates and is rejected as ordinary v5")
	if _case=="first":
		var imported: bool = SurvivalState.is_state(before) and not before.origin.is_empty() and before.food == 12 and before.crew.all(func(row: Dictionary) -> bool: return row.health == 4)
		_expect(before.journey.active_member_ids==[1,2] and (before.journey.seed=="LOW_HP_4_FOOD_12" or imported),"real confirmed rehearsal or explicit imported4HP/food12 fixture; no silent reseeding")
	else:
		_expect(before.journey.active_member_ids==[3-_victim] and before.journey.deaths.size()==1,"new process exactly restores one original identity and death")
	await _capture("camp-before.png")
	await _hold(30)
	await _open_map(_map)
	if app.expedition==null:
		return
	var sortie: Expedition = app.expedition
	sortie.combat_feedback.connect(func(event: Dictionary) -> void:
		var value: Dictionary = event.duplicate(true)
		value.frame = Engine.get_frames_drawn()
		_events.append(value))
	sortie.finished.connect(func(report: Dictionary) -> void: _reports.append(report.duplicate(true)))
	_expect(sortie.survivors.size()==before.journey.active_member_ids.size(),"actual actor count equals live roster, no resurrected actor")
	if _case=="single":
		_expect(sortie.survivors[0].member_id==3-_victim and String(sortie.survivors[0].definition_id)==SurvivorRoster.member(before.crew,3-_victim).definition_id,"single actor preserves stable ID and original appearance")
	await _ui_checks(sortie)
	# Every accepted command below is the same gameplay intent the normal mouse path invokes.
	sortie.request_search(&"cash")
	for frame: int in range(3600):
		if sortie.searched and sortie.kills>0 or sortie.phase==Expedition.Phase.FINISHED:
			break
		await _step(sortie)
	_expect(sortie.searched and sortie.kills>0,"real search, navigation, original safe spawns, gunfire and defeats before lethal drill")
	await _capture("search-complete.png")
	if sortie.phase==Expedition.Phase.FINISHED:
		return
	if _case=="first":
		await _tap(sortie._hud.view._bus_button)
		_expect(sortie.phase==Expedition.Phase.ENGINE,"real engine starts without automatically gathering")
	var target_id: int = _victim if _case=="first" else 3-_victim
	var target: FieldActor = _actor(sortie,target_id)
	if target==null:
		_expect(false,"target identity exists")
		return
	var fail: bool = "--battle-fail-lethal" in OS.get_cmdline_user_args()
	if fail:
		_fault_point = "before_record_write"
	var fail_terminal: bool = _case=="single" and "--battle-fail-terminal" in OS.get_cmdline_user_args()
	if fail_terminal:
		_fault_point = "before_camp_write"
	var contact: Button
	for button: Button in sortie.drill_panel.buttons:
		if int(button.get_meta("member_id"))==target_id:
			contact = button
	await _tap(contact)
	for frame: int in range(180):
		if target.health==0 or sortie.is_paused:
			break
		await _step(sortie)
	if fail:
		_expect(sortie.is_paused and target.health==4 and target.damage_received==0,"failed real lethal checkpoint pauses before HP, hit and damage are published")
		await _capture("lethal-write-blocked.png")
		await _hold(30)
		_fault_point = ""
		await _key_battle(KEY_SPACE)
		for frame: int in range(180):
			if target.health==0:
				break
			await _step(sortie)
	_expect(target.health==0 and target.permanent_death and target.damage_received==4,"same original AI melee publishes exactly one confirmed permanent death")
	_expect(_events.filter(func(e: Dictionary) -> bool: return e.kind=="hit" and e.member_id==target_id).size()==1,"one lethal hit and no duplicate damage feedback")
	await _capture("battle-death.png")
	if _stop=="death":
		return
	if _case=="first":
		for frame: int in range(180):
			if sortie.phase==Expedition.Phase.BOARDING:
				break
			await _step(sortie)
		_expect(sortie.boarding_status().required==1 and sortie.living_count()==1,"dead member is excluded from real required evacuation count")
		sortie.toggle_pause()
		var clock: float = sortie.elapsed
		await _key_battle(KEY_TAB)
		sortie._hud.view._bus_button.grab_focus()
		await _key_battle(KEY_ENTER)
		_expect(sortie.is_paused and sortie.boarding_status().ordered and sortie.elapsed==clock,"keyboard gather works under pause without changing clock")
		sortie._hud.view._bus_button.release_focus()
		await _key_battle(KEY_SPACE)
		for frame: int in range(3600):
			if sortie.phase==Expedition.Phase.FINISHED:
				break
			await _step(sortie)
		_expect(_reports.size()==1 and _reports[0].evacuated and app._pending_settlement.journey.active_member_ids==[3-_victim],"one survivor truly evacuates into one complete frozen after")
		if app._pending_settlement.is_empty():
			return
		var packet: Dictionary = app.progress_session.packet
		_expect(FrozenSettlement.validate(packet).is_empty(),"real battle result passes full C frozen validation")
		_write(output_dir.path_join("packet.json"),packet)
		await _capture("survivor-result.png")
		await _hold(45)
		if _stop=="ready":
			return
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_expect(not app._progress_blocked and SurvivorRoster.member(app.crew,_victim).condition=="dead" and app.food==11,"actual return records death and consumes only survivor ration")
		await _camp_edits(3-_victim)
		_snapshots.append(app.camp_snapshot())
		await _capture("survivor-camp.png")
		await _hold(45)
	else:
		for frame: int in range(120):
			if app.phase==app.Phase.RESULT:
				break
			await _step(sortie)
		if fail_terminal:
			_expect(not app._pending_settlement.is_empty() and app._battle_new_button.disabled and app.progress_session.inspect().state=="RECOVERY_READY","failed terminal save retains READY and disables new journey")
			await _capture("terminal-save-blocked.png")
			await _hold(45)
			_fault_point = ""
			await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_expect(app._battle_meta.state=="FAILED" and app._pending_settlement.is_empty() and app.progress_session.inspect().state=="ENDED","last real death automatically commits a durable failed journey")
		_expect(_reports.size()==1 and not _reports[0].evacuated and _reports[0].loot==0,"wipe is not extraction and cannot bank carried rewards")
		await _capture("journey-failed.png")
		await _hold(60)


func _camp_edits(id: int) -> void:
	_expect(app._camp_backdrop.visible_member_ids == [id], "camp portrait uses sole original live ID; baked dead people concealed")
	await _tap(app._roster_button)
	await _tap(app.roster_panel.member_buttons[_victim-1])
	_expect(app.roster_panel.save_button.disabled and not app.roster_panel.name_edit.editable,"dead member remains visible as read-only history")
	await _capture("dead-history.png")
	await _tap(app.roster_panel.member_buttons[id-1])
	app.roster_panel.name_edit.text = "暮色归航试验同行者甲号员"
	await _tap(app.roster_panel.save_button)
	await _tap(app.roster_panel.equipment_button)
	var reward: String = app.last_settlement_id + ":weapon:north-cache"
	_select_item(app.loadout_panel,reward)
	await _tap(app.loadout_panel.repair_button)
	await _tap(app.loadout_panel.confirmation.get_ok_button())
	await _tap(app.loadout_panel.equip_buttons[id-1])
	_expect(app.cash==_initial.cash+_reports[0].loot-10 and WeaponInventory.for_member(app.camp_snapshot(),id).instance_id==reward,"survivor repairs and equips the same unique reward through camp coordinator")
	_expect(WeaponInventory.for_member(app.camp_snapshot(),_victim).is_empty() and app.weapons.size()==_initial.weapons.size()+1,"dead original weapon remains unique in inventory and unequipped")
	var bytes: String = _digest()
	var old: Dictionary = app.progress_session._transaction.commit(app.progress_session.token)
	_expect(old.error!=OK and _digest()==bytes,"old sortie token cannot overwrite camp edit receipts")
	await _tap(app.loadout_panel.back_button)
	if app.roster_panel.visible:
		await _tap(app.roster_panel.back_button)


func _actor(sortie: Expedition,id: int) -> FieldActor:
	for actor: FieldActor in sortie.survivors:
		if actor.member_id==id:
			return actor
	return null


func _ui_checks(sortie: Expedition) -> void:
	var goal: Vector2 = sortie.goal
	await _mouse_battle(sortie._hud.view._mission.get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
	_expect(sortie.goal==goal and sortie.search_actor==null,"opaque original HUD consumes a real viewport ground click")
	var zoom: Vector2 = sortie.camera.zoom
	await _mouse_battle(sortie.drill_panel._status.get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
	await _mouse_battle(sortie.drill_panel.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_UP)
	_expect(sortie.camera.zoom==zoom and sortie.goal==goal,"isolated opaque panel blocks scroll and click penetration")
	await _key_battle(KEY_SPACE)
	var clock: float = sortie.elapsed
	await _step(sortie)
	_expect(sortie.is_paused and sortie.elapsed==clock,"Space pauses actual world after UI mouse interaction")
	await _key_battle(KEY_TAB)
	_expect(get_viewport().gui_get_focus_owner()!=null,"Tab reaches HUD keyboard navigation")
	sortie._hud.view._pause_button.grab_focus()
	await _key_battle(KEY_ENTER)
	_expect(not sortie.is_paused,"Enter resumes through actual focused HUD control")
	sortie._hud.view._pause_button.release_focus()


func _mouse_battle(point: Vector2, button: MouseButton) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = pressed
		get_viewport().push_input(event,true)
		await get_tree().process_frame
	await _settle()


func _step(sortie: Expedition) -> void:
	sortie.step(1.0/30.0)
	await get_tree().process_frame


func _hold(frames: int) -> void:
	for frame: int in range(frames):
		await get_tree().process_frame


func _key_battle(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event,true)
		await get_tree().process_frame
	await _settle()


func _restart() -> void:
	await _enter()
	var before: Dictionary = app.camp_snapshot()
	var original: String = FileAccess.get_sha256(app.run_save.path)
	await _tap(app._battle_new_button)
	await _tap(app._new_game_confirmation.get_cancel_button())
	_expect(app._battle_meta.state=="FAILED" and app.phase==app.Phase.RESULT and FileAccess.get_sha256(app.run_save.path)==original,"cancel new journey returns to durable terminal without changing original bytes")
	await _tap(app._battle_new_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_expect(app.profile_id!=before.profile_id and app._battle_meta.root_id!=before.journey.root_id and app._battle_meta.state=="ACTIVE","explicit confirmation creates a different run and root after terminal")
	var retained: bool = false
	for name: String in DirAccess.open(app.run_save.path.get_base_dir()).get_files():
		retained = retained or FileAccess.get_sha256(app.run_save.path.get_base_dir().path_join(name))==original
	_expect(retained,"terminal original remains archived as exact bytes")
	await _capture("new-journey-confirmed.png")


func _fault(point: String) -> Error:
	if _barrier=="commit-published" and point=="after_record_publish":
		var current: Dictionary = ReceiptJournal.new(app.run_save.path+".txn/journal").read_all()
		if current.error==OK and current.receipt.phase=="COMMITTED":
			_write(output_dir.path_join("barrier.json"),{"pid":OS.get_process_id(),"point":_barrier})
			var deadline: int = Time.get_ticks_msec()+45000
			while Time.get_ticks_msec()<deadline:
				OS.delay_msec(10)
	return super._fault(point)
