class_name CampScenePlaytest
extends FieldJoinPlaytest
## Explicit isolated prototype acceptance; all business actions stay in main.

var camp_case: String = "rescue"
var _navigation: Array[Dictionary] = []
var _edit_before: Dictionary = {}
var _edit_after: Dictionary = {}


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--camp-case="):
			camp_case = arg.trim_prefix("--camp-case=")
		if arg.begins_with("--camp-expected="):
			expected_path = arg.trim_prefix("--camp-expected=")
	field_case = camp_case
	growth_case = camp_case
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\", "/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _settle()
	await get_tree().create_timer(0.3).timeout
	if camp_case == "blocked":
		_expect(app._progress_blocked and not app.camp_scene.is_visible_in_tree(),"original error gate hides the scene and all living actors")
		var digest: String = _digest()
		app._camp_action(&"bus",0)
		_expect(app.expedition == null and digest == _digest(),"scene route cannot bypass blocked writer/unfinished/bad save")
		await _capture("blocked.png")
		await _finish_camp()
		return
	app.camp_scene.action_requested.connect(func(action: StringName, id: int) -> void: _navigation.append({"action":String(action),"member_id":id}))
	if camp_case in ["resave","resume"]:
		_expect(not app.camp_scene.is_visible_in_tree(),"pending suspend never shows an invented camp")
		await _restore_field()
		if app.expedition == null and app.camp_scene.is_visible_in_tree():
			await _camp_ui("resumed-camp")
		await _finish_camp()
		return
	if camp_case == "backup":
		var damaged_sha: String = FileAccess.get_sha256(app.run_save.path)
		_expect(app._progress_blocked and not app.camp_scene.is_visible_in_tree(),"bad v5 main never enters prototype automatically")
		await _tap(app._backup_button)
		_initial = app.camp_snapshot()
		await _camp_ui("explicit-backup-camp")
		_expect(damaged_sha == FileAccess.get_sha256(app.run_save.path),"viewing explicit backup does not rewrite damaged primary")
		await _finish_camp()
		return
	await _enter()
	_initial = app.camp_snapshot()
	if not expected_path.is_empty():
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		_expect(TransactionReceipt.same(_initial,previous.camp),"new PID restores complete camp identity/XP/guns/economy/deaths before scene")
	if _initial.get("journey",{}).get("state") == "FAILED":
		_expect(not app.camp_scene.is_visible_in_tree() and app.camp_scene.world.visible_member_ids.is_empty(),"FAILED record shows no camp people or departure facility")
		await _capture("terminal.png")
		await _finish_camp()
		return
	await _camp_ui("camp-before")
	if camp_case == "new-root":
		await _profiles()
		var root_id: String = app._battle_meta.root_id
		await _tap(app.camp_scene.footer_buttons[&"home"])
		await _tap(app.get_node("Interface/Screen/Title/Reset"))
		await _tap(app._new_game_confirmation.get_cancel_button())
		_expect(app._battle_meta.root_id == root_id,"new-journey cancellation retains current three-person root")
		await _tap(app.get_node("Interface/Screen/Title/Reset"))
		await _tap(app._new_game_confirmation.get_ok_button())
		_expect(app._battle_meta.root_id != root_id and app.camp_scene.world.visible_member_ids == [1,2],"confirmed separate journey creates original two members and archives old root")
		await _tap(app.camp_scene.member_buttons[1])
		_expect(app.roster_panel.selected_member_id == 1,"old selected ID3 cannot dereference missing profile after new root")
		await _key_battle(KEY_ESCAPE)
		await _capture("new-root-two.png")
		await _finish_camp()
		return
	if camp_case in ["preview","continue"]:
		await _profiles()
		await _finish_camp()
		return
	await _open_map(1 if camp_case == "market" else (0 if camp_case == "repair" else 2))
	var world: Expedition = app.expedition
	if world == null:
		await _finish_camp()
		return
	world.set_physics_process(false)
	world.finished.connect(func(value: Dictionary) -> void: _reports.append(value.duplicate(true)))
	world.combat_feedback.connect(func(value: Dictionary) -> void: _battle_events.append(value.duplicate(true)))
	_expect(not app.camp_scene.is_visible_in_tree(),"battle owns input and camp is hidden")
	await _rescue_ui(world)
	if world.rescue_target != null:
		_npc_instance = world.rescue_target.npc.get_instance_id()
		await _tap(world.rescue_target.button)
		for frame: int in range(1600):
			if world.rescue_target.progress >= (9.5 if camp_case == "save-before" else 10.0):
				break
			await _step(world)
		if camp_case == "save-before":
			await _save_field(world)
			_expect(not app.camp_scene.is_visible_in_tree(),"suspend returns to original Continue, never camp")
			await _finish_camp()
			return
		_expect(world.field_joins.size() == 1 and world.rescue_target.npc.get_instance_id() == _npc_instance and world.survivors.has(world.rescue_target.npc),"real rescue still promotes same ID3, original world/XP/damage authority")
		_joined_at = int(world.field_joins[0].at_ms)
		await _capture("joined-in-field.png")
	if camp_case == "danger":
		app.request_exit("home")
		await _settle()
		await _tap(app.pause_menu.buttons[1])
		_expect(app.expedition == null and app._progress_blocked and not app.camp_scene.is_visible_in_tree(),"dangerous abandonment blocks camp instead of reverting to old state")
		await _capture("danger-blocked.png")
		await _finish_camp()
		return
	await _field_search(world)
	await _field_bus(world)
	if camp_case != "ready" and app.camp_scene.is_visible_in_tree():
		await _camp_ui("camp-returned")
		await _maintenance()
	await _finish_camp()


func _enter() -> void:
	if app.transactional_mode and (app.survival_pilot or app._requires_continue):
		await super._enter()
	else:
		await _tap(app._continue_button if app._requires_continue else app._home_button)


func _open_map(choice: int) -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_expect(app.mission_select.visible,"scene bus opens original mission selection")
	await _tap(app.mission_select.choices[choice])
	_expect(app.expedition != null and app.phase == app.Phase.EXPEDITION,"original signed departure opens selected real map")


func _camp_ui(label: String) -> void:
	var scene: CampSceneView = app.camp_scene
	_expect(scene.is_visible_in_tree(),"real spatial camp visible: "+label)
	var before: Dictionary = app.camp_snapshot()
	var digest: String = _digest()
	var ids: Array[int] = []
	for member: Dictionary in before.crew:
		if member.health > 0:
			ids.append(int(member.id))
	_expect(scene.world.visible_member_ids == ids,"world people exactly match living stable IDs")
	for id: int in ids:
		_expect(scene.world.residents[id].get_meta("definition_id") == SurvivorRoster.member(before.crew,id).definition_id and scene.world.residents[id].position == CampSceneLayout.member_position(id),"sparse ID%d keeps original template/slot" % id)
	for id: int in ids:
		var caption: Label = scene.member_buttons[id].get_node("Caption") as Label
		for line: String in caption.text.split("\n"):
			var advance: float = caption.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
			_expect(advance + 12 <= scene.member_buttons[id].size.x,"actual CJK font/outline fits member label without neighbor collision")
	_expect(str(before.food) in scene.resource_text.text and str(before.cash) in scene.resource_text.text,"scene HUD reads actual camp resources")
	for button: Button in scene.hotspots.values():
		_expect(get_viewport().get_visible_rect().encloses(button.get_global_rect()),"facility fits actual viewport: "+String(button.name))
	await _capture(label+".png")
	await _tap(scene.hotspots[&"supplies"])
	_expect(scene.info_visible() and "今日口粮需求" in scene._info_body.text,"supply facility shows actual ration quote")
	var calls: int = _navigation.size()
	await _click_at(scene.hotspots[&"bus"].get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
	await _click_at(scene.hotspots[&"bus"].get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
	_expect(_navigation.size() == calls and app.expedition == null,"opaque info intercepts mouse and wheel over bus")
	await _capture(label+"-supplies.png")
	await _key_battle(KEY_ESCAPE)
	_expect(not scene.info_visible() and scene.is_visible_in_tree(),"Esc closes only supply layer")
	await _training_entry(scene,label)
	scene.hotspots[&"bus"].grab_focus()
	await _key_battle(KEY_TAB)
	_expect(get_viewport().gui_get_focus_owner() == scene.hotspots[&"crew"],"Tab moves from bus to crew facility")
	await _key_shift_tab()
	_expect(get_viewport().gui_get_focus_owner() == scene.hotspots[&"bus"],"Shift+Tab returns to bus facility")
	await _key_battle(KEY_SPACE)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_expect(app.mission_select.visible,"Space activates real bus facility")
	await _capture(label+"-missions.png")
	await _key_battle(KEY_ESCAPE)
	_expect(scene.is_visible_in_tree() and not app.mission_select.visible,"Esc returns mission choice to scene")
	await _tap(scene.hotspots[&"weapons"])
	_expect(app.loadout_panel.visible and not scene.is_visible_in_tree(),"weapon facility opens original inventory panel exclusively")
	calls = _navigation.size()
	await _click_at(scene.hotspots[&"bus"].get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
	_expect(calls == _navigation.size() and app.expedition == null,"inventory wheel cannot reach hidden camp")
	await _capture(label+"-weapons.png")
	await _key_battle(KEY_ESCAPE)
	_expect(scene.is_visible_in_tree() and not app.loadout_panel.visible,"Esc closes inventory to same camp")
	await _tap(scene.member_buttons[ids[0]])
	_expect(app.roster_panel.visible and app.roster_panel.selected_member_id == ids[0],"clicking living world member selects actual stable profile")
	app.roster_panel.name_edit.text = "尚未确认的呼号"
	await _key_battle(KEY_ESCAPE)
	_expect(app._camp_leave_dialog.visible and app.roster_panel.visible,"Esc protects unconfirmed name edit")
	app.request_exit("quit")
	_expect(app._camp_leave_dialog.visible and not app.pause_menu.root.visible,"window-close intent cannot stack exit under unsaved editor modal")
	await _tap(app._camp_leave_dialog.get_cancel_button())
	_expect(app.roster_panel.name_edit.text == "尚未确认的呼号","cancel leaving preserves editor text")
	await _key_battle(KEY_ESCAPE)
	await _tap(app._camp_leave_dialog.get_ok_button())
	_expect(scene.is_visible_in_tree() and not app.roster_panel.visible,"explicit discard returns without saving")
	await _tap(scene.footer_buttons[&"legacy"])
	_expect(not scene.visible and app._camp_legacy_return.is_visible_in_tree(),"same-owner legacy fallback stays available")
	await _capture(label+"-legacy.png")
	await _tap(app._camp_legacy_return)
	_expect(scene.is_visible_in_tree(),"fallback can return to real scene")
	await _tap(scene.footer_buttons[&"quit"])
	_expect(app.pause_menu.root.visible,"camp quit uses original safe exit confirmation")
	calls = _navigation.size()
	await _key_battle(KEY_TAB)
	_expect(app.pause_menu.root.is_ancestor_of(get_viewport().gui_get_focus_owner()),"exit confirmation owns Tab focus above camp")
	await _key_shift_tab()
	_expect(get_viewport().gui_get_focus_owner() == app.pause_menu.buttons[0],"Shift+Tab returns to original safe cancel")
	await _key_battle(KEY_SPACE)
	_expect(not app.pause_menu.root.visible and _navigation.size() == calls,"Space cancels original exit without activating background facility")
	await _tap(scene.footer_buttons[&"quit"])
	await _key_battle(KEY_ENTER)
	_expect(not app.pause_menu.root.visible,"Enter activates original focused exit cancellation")
	await _tap(scene.footer_buttons[&"quit"])
	await _key_battle(KEY_ESCAPE)
	_expect(not app.pause_menu.root.visible and scene.is_visible_in_tree(),"Esc cancels exit without leaving camp")
	await _key_battle(KEY_ESCAPE)
	_expect(scene.is_visible_in_tree(),"Esc already in camp does not exit journey")
	_expect(TransactionReceipt.same(before,app.camp_snapshot()) and digest == _digest(),"viewing/navigation/cancel never change camp/date/food/XP/guns/backup/head")


func _profiles() -> void:
	await _tap(app.camp_scene.hotspots[&"crew"])
	for member: Dictionary in app.crew:
		await _tap(app.roster_panel.member_buttons[int(member.id)-1])
		_expect(app.roster_panel._health.value == member.health and app.roster_panel._health.max_value == SurvivorGrowth.maximum(app.camp_snapshot(),member),"existing profile HP and max match ID%d" % int(member.id))
		await _capture("profile-%d.png" % int(member.id))
	await _tap(app.roster_panel.growth_button)
	_expect(app.growth_panel.visible and app.growth_panel.training_button.disabled,"existing growth/XP page, no Trait or training")
	await _capture("growth-detail.png")
	await _key_battle(KEY_ESCAPE)
	_expect(app.roster_panel.visible and not app.growth_panel.visible,"Esc growth returns one layer to profile")
	await _key_battle(KEY_ESCAPE)
	_expect(app.camp_scene.is_visible_in_tree(),"Esc profile returns to spatial camp")


func _maintenance() -> void:
	_edit_before = app.camp_snapshot()
	var reward: Dictionary = {}
	for item: Dictionary in app.weapons:
		if item.condition == "damaged":
			reward = item
	if reward.is_empty():
		return
	await _tap(app.camp_scene.hotspots[&"weapons"])
	_select_item(app.loadout_panel,reward.instance_id)
	await _tap(app.loadout_panel.repair_button)
	var digest: String = _digest()
	await _tap(app.loadout_panel.confirmation.get_cancel_button())
	_expect(digest == _digest(),"repair cancellation preserves actual bytes")
	await _tap(app.loadout_panel.repair_button)
	if camp_case == "edit-fail":
		app.progress_session.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point == "before_commit_receipt" else OK
	await _tap(app.loadout_panel.confirmation.get_ok_button())
	if camp_case == "edit-fail":
		_expect(app._progress_blocked and TransactionReceipt.same(_edit_before,app.camp_snapshot()),"unknown edit ACK never applies memory or opens scene")
		await _capture("edit-blocked.png")
		await _key_battle(KEY_ESCAPE)
		app.progress_session.fault_hook = Callable()
		await _tap(app._retry_button)
		await _tap(app.camp_scene.hotspots[&"weapons"])
	_expect(app.cash == int(_edit_before.cash)-10 and WeaponInventory.find(app.camp_snapshot(),reward.instance_id).condition == "ready","old repair transaction charges10 once and retains original instance")
	_select_item(app.loadout_panel,reward.instance_id)
	var id: int = app.camp_scene.world.visible_member_ids[0]
	await _tap(app.loadout_panel.equip_buttons[id-1])
	_expect(WeaponInventory.owner(app.camp_snapshot(),reward.instance_id) == id and app.weapons.size() == _edit_before.weapons.size(),"old equip uses unique reward gun, no duplicate instance")
	await _capture("repaired-equipped.png")
	await _key_battle(KEY_ESCAPE)
	await _tap(app.camp_scene.member_buttons[id])
	app.roster_panel.name_edit.text = "一二三四五六七八九十天地"
	await _tap(app.roster_panel.save_button)
	_expect(SurvivorRoster.member(app.crew,id).call_sign.length() == 12,"original rename saves full12 Chinese characters")
	digest = _digest()
	await _tap(app.roster_panel.save_button)
	_expect(digest == _digest(),"same name confirmation cannot write twice")
	await _key_battle(KEY_ESCAPE)
	_edit_after = app.camp_snapshot()
	_expect(_edit_after.day == _edit_before.day and _edit_after.food == _edit_before.food,"camp edits/view never advance day or consume rations")
	await _capture("camp-after-edits.png")
	_reject_persisted_suspends("CAMP_EDITS_COMMITTED")


func _click_at(point: Vector2, button: MouseButton) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = point
		get_viewport().push_input(event,true)
		await get_tree().process_frame
	await _settle()


func _key_shift_tab() -> void:
	for pressed: bool in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_TAB
		event.shift_pressed = true
		event.pressed = pressed
		get_viewport().push_input(event,true)
		await get_tree().process_frame
	await _settle()


func _finish_camp() -> void:
	_write(output_dir.path_join("report.json"),{"pid":OS.get_process_id(),"case":camp_case,"checks":_checks,"failures":_failures,"initial":_initial,"camp":app.camp_snapshot(),"reports":_reports,"battle_events":_battle_events,"navigation":_navigation,"edit_before":_edit_before,"edit_after":_edit_after,"visible_ids":app.camp_scene.world.visible_member_ids,"window_size":DisplayServer.window_get_size(),"input_layer":"native viewport/original intentions; NOT physical OS"})
	app.audio.shutdown()
	OS.delay_msec(150)
	await _settle()
	get_tree().quit(0 if _failures == 0 else 1)


func _training_entry(scene: CampSceneView, label: String) -> void:
	await _tap(scene.hotspots[&"training"])
	_expect("尚未开放" in scene._info_title.text,"training is an honest unavailable entrance")
	await _capture(label+"-training.png")
	await _key_battle(KEY_ENTER)
	_expect(not scene.info_visible(),"Enter closes focused read-only panel")
