class_name RosterPlaytest
extends RescuePoolPlaytest
## Explicit109 acceptance intentions; never fabricates camp identities or deaths.

var journey_stages: Array[Dictionary] = []


func _task_path() -> String:
	return "/.local/m5-roster-ux-01/"


func _trait_problem(data: Dictionary) -> String:
	return RosterState.problem(data)


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--camp-case="): camp_case = arg.trim_prefix("--camp-case=")
		if arg.begins_with("--camp-expected="): expected_path = arg.trim_prefix("--camp-expected=")
	if not output_dir.is_absolute_path() or _task_path() not in output_dir.replace("\\","/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	await _settle()
	await get_tree().create_timer(0.3).timeout
	if camp_case in ["resume","resave","same-resave"]:
		await _restore_pool()
		await _finish_camp()
		return
	await _enter()
	_initial = app.camp_snapshot()
	_expect(RosterState.problem(_initial).is_empty(),"strict109 initial camp: "+RosterState.problem(_initial))
	if not expected_path.is_empty():
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		_expect(TransactionReceipt.same(_initial,expected.camp),"new PID exactly restores all five historical identities and four living")
	await _camp_ui("camp-before")
	if camp_case=="terminal-view":
		var digest: String = _digest()
		var view: Dictionary = _initial.duplicate(true)
		view.journey.state = "FAILED" # View-only terminal geometry fixture, never submitted.
		app._show_battle_result(view,true)
		await _settle()
		var button: Button = app._battle_new_button
		_expect(get_viewport().get_visible_rect().encloses(button.get_global_rect()),"terminal new-journey button stays inside actual viewport")
		button.grab_focus()
		_expect(get_viewport().gui_get_focus_owner()==button,"terminal button can receive native keyboard focus")
		await _tap(button)
		_expect(app._new_game_confirmation.visible,"terminal new-journey action opens explicit confirmation")
		await _tap(app._new_game_confirmation.get_cancel_button())
		_expect(digest==_digest(),"view-only terminal fixture and cancel leave real saved camp unchanged")
	elif camp_case=="continue":
		await _profiles()
	elif camp_case.begins_with("train") or camp_case.begins_with("kill-"):
		await _train_member(int(_initial.journey.active_member_ids[-1]))
	elif camp_case=="death-replace":
		_expect(_initial.crew.size()==4 and RosterState.living_count(_initial)==4,"death starts with four legitimate historical living members")
		await _train_member(3)
		await _long_names()
		await _tap(app.camp_scene.hotspots[&"weapons"])
		var swapped: String = WeaponInventory.for_member(app.camp_snapshot(),2).instance_id
		_select_item(app.loadout_panel,swapped)
		await _tap(app.loadout_panel.equip_by_id[3])
		await _key_battle(KEY_ESCAPE)
		_initial = app.camp_snapshot()
		app.survival_pilot = false
		await _open_map(1)
		var death_world: Expedition = _watch_world()
		await _field_death(death_world,3)
		await _field_search(death_world)
		await _field_bus(death_world)
		var before_replace: Dictionary = app.camp_snapshot()
		_expect(before_replace.crew.size()==4 and RosterState.living_count(before_replace)==3 and SurvivorRoster.member(before_replace.crew,3).condition=="dead","real AI death saved; identity3 permanently retained")
		_expect(app.progress_session.death_equipment(before_replace).get(3,{}).get("instance_id","")==swapped,"dead member with no kills in death sortie retains actual swapped gun via original receipts")
		_write(output_dir.path_join("death-camp.json"),before_replace)
		journey_stages.append({"stage":"real-death","camp":before_replace,"reports":_reports.duplicate(true)})
		_reports.clear()
		_initial = before_replace
		app.survival_pilot = true
		await _rescue_outing()
		var after: Dictionary = app.camp_snapshot()
		_expect(after.crew.size()==5 and RosterState.living_count(after)==4,"replacement forms five history and four living")
		_expect(TransactionReceipt.same(SurvivorRoster.member(before_replace.crew,3),SurvivorRoster.member(after.crew,3)),"dead identity alias XP Trait training service and action remain exactly unchanged")
		_expect(TransactionReceipt.same({"v":before_replace.journey.deaths},{"v":after.journey.deaths}),"replacement does not erase or mutate confirmed death provenance")
		await _profiles()
	elif camp_case=="next":
		await _profiles()
		await _maintenance()
		await _train_member(int(_initial.journey.active_member_ids[-1]))
		_initial = app.camp_snapshot()
		await _open_map(1)
		var world: Expedition = _watch_world()
		_expect(world.survivors.size()==4 and world.survivors.all(func(a: FieldActor) -> bool: return a.member_id!=3),"only four living IDs depart; archived3 never respawns")
		await _capture("four-hud.png")
		await _field_search(world)
		await _field_bus(world)
		_expect(app.camp_snapshot().last_day.food_required==4,"next normal meal consumes four rations")
	else:
		await _rescue_outing()
	await _finish_camp()


func _finish_camp() -> void:
	_write(output_dir.path_join("journey-stages.json"),{"stages":journey_stages})
	await super._finish_camp()


func _camp_ui(label: String) -> void:
	await super._camp_ui(label)
	for id: int in app.camp_scene.world.visible_member_ids:
		await _tap(app.camp_scene.member_buttons[id])
		_expect(app.roster_panel.selected_member_id==id and get_viewport().gui_get_focus_owner()==app.roster_panel.buttons_by_id[id],"actual sparse camp hotspot opens and focuses stable ID%d" % id)
		await _key_battle(KEY_ESCAPE)


func _profiles() -> void:
	await super._profiles()
	await _tap(app.camp_scene.hotspots[&"crew"])
	for member: Dictionary in app.crew:
		if member.health>0: continue
		var button: Button = app.roster_panel.buttons_by_id[int(member.id)]
		button.grab_focus()
		await _settle()
		await _tap(button)
		_expect(app.roster_panel.save_button.disabled and app.roster_panel.equipment_button.disabled and not app.roster_panel.name_edit.editable,"dead historical profile cannot rename equip or revive")
		_expect(not app.roster_panel.death_equipment.get(int(member.id),{}).is_empty() and app.roster_panel._equipment.text.contains("阵亡时装备"),"new PID historical profile displays actual death equipment reference")
		await _capture("dead-history.png")
	await _key_battle(KEY_ESCAPE)


func _long_names() -> void:
	await _tap(app.camp_scene.hotspots[&"crew"])
	for member: Dictionary in app.crew:
		if member.health<=0: continue
		var button: Button = app.roster_panel.buttons_by_id[int(member.id)]
		button.grab_focus()
		await _settle()
		await _tap(button)
		app.roster_panel.name_edit.text = "一二三四五六七八九十天地"
		await _tap(app.roster_panel.save_button)
		_expect(SurvivorRoster.member(app.crew,int(member.id)).call_sign.length()==12,"full12 Chinese call sign saved by original camp edit")
	await _key_battle(KEY_ESCAPE)


func _capture(label: String) -> void:
	if label=="field-result.png":
		var scroll: ScrollContainer = app.get_node("Interface/Screen/Result/Scroll")
		var button: Button = app.get_node("Interface/Screen/Result/Continue")
		var viewport: Rect2 = get_viewport().get_visible_rect()
		_expect(viewport.encloses(scroll.get_global_rect()) and viewport.encloses(button.get_global_rect()),"result scroll and fixed confirmation remain inside logical viewport")
		_expect(not scroll.get_global_rect().intersects(button.get_global_rect()),"scroll content cannot cover result confirmation")
		for tick: int in range(16):
			await _click_at(scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
		_expect(scroll.scroll_vertical>0 or scroll.get_child(0).size.y<=scroll.size.y,"complete result accessible via real viewport wheel")
		button.grab_focus()
		await _settle()
		_expect(get_viewport().gui_get_focus_owner()==button,"result confirmation keyboard focus reachable after scrolling")
		await super._capture("result-bottom.png")
		scroll.scroll_vertical = 0
		await _settle()
	await super._capture(label)


func _rescue_outing() -> void:
	await _open_map(2)
	var world: Expedition = _watch_world()
	if world.rescue_target==null:
		_expect(false,"eligible rescue has one frozen candidate")
		return
	candidate = world.candidate_id()
	original_npc = world.rescue_target.npc.get_instance_id()
	await _capture("candidate.png")
	await _tap(world.rescue_target.button)
	for frame: int in range(1800):
		if world.rescue_target.progress >= (9.5 if camp_case=="save-before" else 10.0): break
		await _step(world)
	if camp_case=="save-before":
		await _save_field(world)
		return
	await _verify_join(world)
	_expect(world.living_count()<=4,"join never creates a fifth living actor")
	await _field_search(world)
	if camp_case=="save-after":
		await _save_field(world)
	else:
		await _field_bus(world)
