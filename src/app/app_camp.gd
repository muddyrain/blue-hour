class_name AppCamp
extends RefCounted

var app: AppMain


func _init(owner: AppMain) -> void:
	app = owner


func _update_camp() -> void:
	app._status.text = app._progress_message
	app.get_node("Interface/Screen/Title/Camp").text = "第 %d 天   /   货币 %d   /   队员生命 %d · %d" % [app.day, app.cash, ceili(app.crew_health[0]), ceili(app.crew_health[1])]
	var daily: Dictionary = CampEconomy.rations(app.day, app.camp_snapshot().crew, app.food, app.camp_rules)
	var ration_text: String = "今日口粮 %d（队员%s，每人%d）" % [daily.required, str(daily.member_ids), daily.per_member]
	ration_text += " · 缺%d，建议选择超市" % daily.shortage if daily.shortage > 0 else " · 库存足够"
	var change: String = "初始库存为样板值；出击前可选搜集或超市。"
	if not app.last_day.is_empty():
		change = "上次归航：食物 %d +%d −%d = %d；货币 +%d；缺口%d" % [app.last_day.food_before, app.last_day.food_stored, app.last_day.food_consumed, app.last_day.food_after, app.last_day.cash_gained, app.last_day.food_shortage]
	if not app.last_day.is_empty() and app.last_day.food_shortage > 0:
		change += "；损失候选%d人，未应用" % HungerOutcome.candidate(app.last_day).loss_count
	app.get_node("Interface/Screen/Title/Camp").text = "第 %d 天 / 货币 %d / 食物 %d / 队员生命 %d · %d\n%s\n%s" % [app.day,app.cash,app.food,ceili(app.crew_health[0]),ceili(app.crew_health[1]),ration_text,change]
	var eligible: bool = (app._battle_meta.get("state") == "ACTIVE" and not CampaignState.ended(app.camp_snapshot()))
	app.get_node("Interface/Screen/Title/Start").disabled = app._requires_continue or app._progress_blocked or not eligible
	app._loadout_button.disabled = app._requires_continue or app._progress_blocked
	app._roster_button.disabled = app._requires_continue or app._progress_blocked
	app._continue_button.visible = app._requires_continue
	app._backup_button.visible = app._progress_blocked and not app._backup_save.is_empty()
	app._retry_button.visible = app._progress_dirty
	if app._requires_continue and app._pending_save.is_empty():
		app.get_node("Interface/Screen/Title/Camp").text = "已有未完成的出击暂存；请继续原战场。暂存没有回营、结算、扣粮或推进日期。"
	elif app._requires_continue:
		app.get_node("Interface/Screen/Title/Camp").text = "已保存：第 %d 天 / 货币 %d / 食物 %d\n点击“继续游戏”恢复营地；旧档不会自动改写。" % [int(app._pending_save.day), int(app._pending_save.cash), int(app._pending_save.food)]
	elif app._progress_blocked:
		app.get_node("Interface/Screen/Title/Camp").text = "存档未加载；出击已锁定。原文件保留，可选有效备份或确认新游戏。"
	else:
		app.get_node("Interface/Screen/Title/Camp").text += "\n武器 %d 件 / 已装备 %d / 闲置 %d" % [app.weapons.size(), app.loadout.size(), app.weapons.size() - app.loadout.size()]

	app._refresh_presentation()


func open_roster() -> void:
	if app.phase != app.Phase.TITLE or app._settings_open() or app._requires_continue or app._progress_blocked:
		return
	if not is_instance_valid(app.roster_panel):
		app.roster_panel = RosterPanel.new()
		app._screen.add_child(app.roster_panel)
		app.roster_panel.call_sign_requested.connect(app.rename_survivor)
		app.roster_panel.equipment_requested.connect(app._roster_equipment)
		app.roster_panel.growth_requested.connect(app.open_growth)
		app.roster_panel.training_requested.connect(func(id: int) -> void:
			if app._guard_camp_editor(func() -> void: app._roster_training(id)): return
			app._roster_training(id)
		)
		app.roster_panel.closed.connect(app.close_roster)
		app.roster_panel.navigation_requested.connect(app._leave_roster_for)
	if SurvivorRoster.member(app.crew, app.roster_panel.selected_member_id).is_empty():
		app.roster_panel.selected_member_id = int(app.crew[0].id)
	app._title.hide()
	app.roster_panel.show()
	app.roster_panel.death_equipment = app.progress_session.death_equipment(app.camp_snapshot())
	app.roster_panel.refresh(app.camp_snapshot())
	app.roster_panel.buttons_by_id[app.roster_panel.selected_member_id].grab_focus()
	app._request_audio(&"ui_confirm")


func close_roster(discard_pending: bool = false) -> void:
	if not discard_pending and app._guard_camp_editor(app.close_roster.bind(true)):
		return
	app.roster_panel.hide()
	app._title.show()
	if is_instance_valid(app.camp_scene) and app.camp_scene.is_visible_in_tree():
		app.camp_scene.restore_focus()
	else:
		app._roster_button.grab_focus()
	app._request_audio(&"ui_back")


func _leave_roster_for(action: StringName, discard_pending: bool = false) -> void:
	if not discard_pending and app._guard_camp_editor(app._leave_roster_for.bind(action, true)):
		return
	app.close_roster(true)
	if action != &"camp":
		app._camp_action(action, 0)


func open_growth(member_id: int, discard_pending: bool = false) -> void:
	if app.phase != app.Phase.TITLE or not is_instance_valid(app.roster_panel) or not app.roster_panel.visible or SurvivorRoster.member(app.crew,member_id).is_empty():
		return
	if not discard_pending and app._guard_camp_editor(app.open_growth.bind(member_id, true)):
		return
	app.roster_panel.hide()
	if not is_instance_valid(app.growth_panel):
		app.growth_panel = GrowthPanel.new()
		app._screen.add_child(app.growth_panel)
		app.growth_panel.closed.connect(app.close_growth)
	app.growth_panel.selected_member_id = member_id
	app.growth_panel.show()
	app.growth_panel.refresh(app.camp_snapshot())
	app.growth_panel.buttons_by_id[member_id].grab_focus()
	app._request_audio(&"ui_confirm")


func close_growth() -> void:
	app.roster_panel.selected_member_id = app.growth_panel.selected_member_id
	app.growth_panel.hide()
	app.open_roster()


func rename_survivor(member_id: int, value: String) -> void:
	if app.phase != app.Phase.TITLE or not is_instance_valid(app.roster_panel) or not app.roster_panel.visible:
		return
	var problem: String = SurvivorRoster.name_problem(value)
	var entry: Dictionary = SurvivorRoster.member(app.crew, member_id)
	if entry.is_empty():
		problem = "队员身份无效。"
	if not problem.is_empty():
		app.roster_panel.refresh(app.camp_snapshot(), problem)
		return
	if entry.call_sign == value:
		app.roster_panel.refresh(app.camp_snapshot(), "呼号未改变，未重复保存。")
		return
	if app._accept_transaction(app.progress_session.edit(app.camp_snapshot(),{"kind":"rename","member_id":member_id,"value":value}),true):
		app._request_audio(&"ui_confirm")
	app.roster_panel.refresh(app.camp_snapshot(),app._progress_message)
	return


func _roster_equipment(member_id: int, discard_pending: bool = false) -> void:
	if not discard_pending and app._guard_camp_editor(app._roster_equipment.bind(member_id, true)):
		return
	app.close_roster(true)
	app._return_roster_member = member_id
	app.open_loadout()
	app.loadout_panel.select_for_member(member_id)


func open_loadout(workshop: bool = false) -> void:
	if app.phase != app.Phase.TITLE or app._settings_open() or app._requires_continue or app._progress_blocked:
		return
	if not is_instance_valid(app.loadout_panel):
		app.loadout_panel = LoadoutPanel.new()
		app._screen.add_child(app.loadout_panel)
		app.loadout_panel.equip_requested.connect(app.equip_weapon)
		app.loadout_panel.build_requested.connect(app.equip_build_item)
		app.loadout_panel.power_requested.connect(app.equip_power)
		app.loadout_panel.power_panel.second_requested.connect(app.equip_power.bind(1))
		app.loadout_panel.power_panel.third_requested.connect(app.equip_power.bind(2))
		app.loadout_panel.build_investment_requested.connect(app.invest_build)
		app.loadout_panel.power_panel.investment_requested.connect(app.invest_power)
		app.loadout_panel.power_panel.retry_requested.connect(app.retry_power_edit)
		app.loadout_panel.repair_requested.connect(app.repair_weapon)
		app.loadout_panel.workshop_requested.connect(app.install_workshop_mod)
		app.loadout_panel.economy_requested.connect(app.confirm_economy_edit)
		app.loadout_panel.closed.connect(app.close_loadout)
		app.loadout_panel.navigation_requested.connect(app._leave_loadout_for)
	app._title.hide()
	app.loadout_panel.show()
	app.loadout_panel.refresh(app.camp_snapshot())
	if workshop:
		app.loadout_panel.show_workshop()
	else:
		app.loadout_panel.show_inventory()
	app._request_audio(&"ui_confirm")


func _leave_loadout_for(action: StringName) -> void:
	app._return_roster_member = 0
	app.close_loadout()
	if not app.loadout_panel.visible and action != &"camp":
		app._camp_action(action, 0)


func close_loadout() -> void:
	if app._camp_commit_busy: return
	if not is_instance_valid(app.loadout_panel) or app.loadout_panel.confirmation.visible or app.loadout_panel.power_panel.confirmation.visible \
			or app.loadout_panel.workshop_confirmation.visible or app.loadout_panel.build_panel._confirmation.visible:
		return
	app.loadout_panel.hide()
	app._title.show()
	if is_instance_valid(app.camp_scene) and app.camp_scene.is_visible_in_tree():
		app.camp_scene.restore_focus()
	else:
		app._loadout_button.grab_focus()
	app._request_audio(&"ui_back")
	if app._return_roster_member > 0:
		app.roster_panel.selected_member_id = app._return_roster_member
		app._return_roster_member = 0
		app.open_roster()


func equip_weapon(member_id: int, identity: String) -> void:
	if app._camp_commit_busy: return
	if app.phase != app.Phase.TITLE or not is_instance_valid(app.loadout_panel) or not app.loadout_panel.visible or app._progress_blocked:
		return
	var before: Dictionary = app.camp_snapshot()
	if not app.loadout_panel.matches_equip(before, member_id, identity):
		app.loadout_panel.refresh(before, "配装或持有人已变化，请重新预览。", app._progress_dirty)
		return
	if EconomyBuildV1.enabled(before): await app._begin_camp_commit(before, "weapon_equip")
	if app._accept_transaction(app.progress_session.edit(before,{"kind":"equip","member_id":member_id,"value":identity}),true):
		app._request_audio(&"ui_confirm")
	app._camp_commit_busy = false
	app._camp_commit_label = ""
	app.loadout_panel.refresh(app.camp_snapshot(),app._progress_message,app._progress_dirty)
	if app._progress_dirty:
		app.loadout_panel.focus_retry()
	return


func repair_weapon(identity: String) -> void:
	if app._camp_commit_busy: return
	if app.phase != app.Phase.TITLE or not is_instance_valid(app.loadout_panel) or not app.loadout_panel.visible or app._progress_blocked:
		return
	var before: Dictionary = app.camp_snapshot()
	if EconomyBuildV1.enabled(before): await app._begin_camp_commit(before, "weapon_repair")
	if app._accept_transaction(app.progress_session.edit(before,{"kind":"repair","member_id":0,"value":identity}),true):
		app._request_audio(&"ui_confirm")
	app._camp_commit_busy = false
	app._camp_commit_label = ""
	app.loadout_panel.refresh(app.camp_snapshot(),app._progress_message,app._progress_dirty)
	if app._progress_dirty:
		app.loadout_panel.focus_retry()
	return


func install_workshop_mod(identity: String, mod: String) -> void:
	if app._camp_commit_busy: return
	if app.phase != app.Phase.TITLE or not is_instance_valid(app.loadout_panel) or not app.loadout_panel.visible \
			or app._progress_blocked:
		return
	var before: Dictionary = app.camp_snapshot()
	var issue: String = WorkshopV1.mod_problem(before, identity, mod)
	if not issue.is_empty():
		app.loadout_panel.refresh(before, issue, app._progress_dirty)
		return
	var saved: bool = app._accept_transaction(app.progress_session.edit(before, {"kind":mod, "member_id":0, "value":identity}), true)
	if saved:
		app._request_audio(&"ui_confirm")
	app.loadout_panel.refresh(app.camp_snapshot(), "已安装%s · 使用工具箱 ×1、8 币" % WorkshopV1.name_for(mod) if saved else app._progress_message, app._progress_dirty)
	if app._progress_dirty:
		app.loadout_panel.focus_retry()


func confirm_economy_edit(request: Dictionary) -> void:
	if app._camp_commit_busy: return
	if app.phase != app.Phase.TITLE or app._progress_blocked or app._progress_dirty:
		return
	var before: Dictionary = app.camp_snapshot()
	var frozen_request: Dictionary = request.duplicate(true)
	await app._begin_camp_commit(before,"economy")
	var saved: bool = app._accept_transaction(app.progress_session.edit(before, frozen_request), true)
	app._camp_commit_busy = false
	app._camp_commit_label = ""
	if saved:
		app._request_audio(&"ui_confirm")
	app._update_camp()
	if is_instance_valid(app.loadout_panel) and app.loadout_panel.visible:
		app.loadout_panel.refresh(app.camp_snapshot(), app._progress_message, app._progress_dirty)
		if app._progress_dirty:
			app.loadout_panel.focus_retry()
	app._refresh_supply_panel()


func _enter_camp() -> void:
	if app.phase != app.Phase.TITLE or app._settings_open() or app._requires_continue or app._progress_blocked:
		return
	if not app.run_save.has_files():
		app.reset_demo()
		return
	app._camp_open = true
	app._refresh_presentation()
	app.get_node("Interface/Screen/Title/Start").grab_focus()
	app._request_audio(&"ui_confirm")


func _setup_camp_scene() -> void:
	app._camp_leave_dialog = ConfirmationDialog.new()
	app._camp_leave_dialog.title = "呼号尚未保存"
	app._camp_leave_dialog.dialog_text = "当前呼号修改尚未确认。放弃修改并返回，还是继续编辑？"
	app._camp_leave_dialog.ok_button_text = "放弃修改并继续"
	app._camp_leave_dialog.cancel_button_text = "继续编辑"
	app._camp_leave_dialog.confirmed.connect(func() -> void: app._camp_leave_action.call_deferred())
	app._camp_leave_dialog.canceled.connect(func() -> void: app.roster_panel.name_edit.grab_focus.call_deferred())
	app._screen.add_child(app._camp_leave_dialog)
	var path: String = "res://src/features/camp_scene/camp_scene.tscn"
	var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed == null or not packed.can_instantiate():
		app._camp_scene_problem = "营地场景原型不可用；原营地功能保留。"
		return
	var candidate: Node = packed.instantiate()
	if not candidate is CampSceneView:
		candidate.free()
		app._camp_scene_problem = "营地场景未通过检查；原营地功能保留。"
		return
	app.camp_scene = candidate as CampSceneView
	app.camp_scene.player_mode = true
	if app.camp_scene.player_mode:
		app.camp_scene.theme = CampStyle.blue_hour_theme(app._screen.theme)
	app._title.add_child(app.camp_scene)
	app.camp_scene.input_allowed = app._camp_input_allowed
	app.camp_scene.action_requested.connect(app._camp_action)
	app.camp_scene.facility_requested.connect(app._offer_camp_facility)
	app._facility_confirmation = ConfirmationDialog.new()
	app._facility_confirmation.title = "确认营地建设"
	app._facility_confirmation.ok_button_text = "建设并保存"
	app._facility_confirmation.cancel_button_text = "暂不建设"
	app._facility_confirmation.confirmed.connect(app._confirm_camp_facility)
	app._facility_confirmation.canceled.connect(func() -> void:
		app._facility_choice = ""
		app._economy_request = {}
		app._restore_facility_focus.call_deferred())
	app._screen.add_child(app._facility_confirmation)
	app.camp_scene.hide()


func _offer_camp_facility(choice: String, upgrade: bool = false) -> void:
	if not app._camp_input_allowed() or app._progress_dirty or not CampSupplyPanel.NAMES.has(choice):
		return
	var before: Dictionary = app.camp_snapshot()
	if EconomyBuildV1.enabled(before):
		if not upgrade and EconomyBuildV1.level(before, choice) > 0:
			app.open_supplies()
			return
		var op: String = "upgrade_facility" if upgrade else "build"
		var quote: Dictionary = EconomyBuildV1.offer(before, op, choice)
		if not quote.available:
			app._progress_message = quote.reason
			app._refresh_supply_panel()
			return
		var identity: String = String(before.profile_id) + ":edit:" + RunSave.new_profile_id()
		app._economy_request = EconomyBuildV1.request(before, op, choice, "", identity)
		app._facility_confirmation.dialog_text = quote.summary
		app._facility_confirmation.popup_centered(Vector2i(660, 260))
		return
	var offer: Dictionary = CampFacilities.upgrade_offer(before, choice) if upgrade else {}
	if (upgrade and not offer.available) or (not upgrade and not CampFacilities.can_build(before, choice)):
		return
	app._facility_choice = choice
	app._facility_upgrade = upgrade
	var label: String = CampSupplyPanel.UPGRADES[choice] if upgrade else CampSupplyPanel.NAMES[choice]
	var cost: int = int(offer.cost) if upgrade else CampFacilities.BUILD_COST
	var effect: String = CampSupplyPanel.UPGRADE_EFFECTS[choice] if upgrade else CampSupplyPanel.EFFECTS[choice]
	app._facility_confirmation.ok_button_text = "确认投资并保存"
	app._facility_confirmation.dialog_text = "%s · 花费 %d 币 · 保存后余 %d 币\n%s" % [label, cost, int(before.cash) - cost, effect]
	app._facility_confirmation.popup_centered(Vector2i(630, 200))


func _confirm_camp_facility() -> void:
	if not app._economy_request.is_empty():
		var request: Dictionary = app._economy_request
		app._economy_request = {}
		app.confirm_economy_edit(request)
		app._restore_facility_focus.call_deferred()
		return
	var choice: String = app._facility_choice
	app._facility_choice = ""
	if app.phase != app.Phase.TITLE or not app._camp_open or not CampSceneView.FACILITY_NAMES.has(choice):
		return
	var kind: String = "facility_upgrade" if app._facility_upgrade else "facility"
	if app._accept_transaction(app.progress_session.edit(app.camp_snapshot(), {"kind":kind, "member_id":0, "value":choice}), true):
		var label: String = CampSupplyPanel.UPGRADES[choice] if app._facility_upgrade else CampSupplyPanel.NAMES[choice]
		app._progress_message = "%s已建成，支出已保存。" % label
		app._request_audio(&"ui_confirm")
	app._update_camp()
	app._refresh_supply_panel()
	app._restore_facility_focus.call_deferred()


func _restore_facility_focus() -> void:
	if is_instance_valid(app.supply_panel) and app.supply_panel.visible:
		app.supply_panel.back_button.grab_focus()
	elif is_instance_valid(app.camp_scene):
		app.camp_scene.restore_focus()


func open_supplies() -> void:
	if app.phase != app.Phase.TITLE or app._settings_open() or app._requires_continue or app._progress_blocked:
		return
	if not is_instance_valid(app.supply_panel):
		app.supply_panel = CampSupplyPanel.new()
		app.supply_panel.theme = CampStyle.blue_hour_theme(app._screen.theme)
		app._screen.add_child(app.supply_panel)
		app.supply_panel.investment_requested.connect(app._offer_camp_facility)
		app.supply_panel.retry_requested.connect(app._retry_facility)
		app.supply_panel.navigation_requested.connect(app._leave_supplies_for)
	app._title.hide()
	app.supply_panel.show()
	app._refresh_supply_panel()
	app.supply_panel.back_button.grab_focus()
	app._request_audio(&"ui_confirm")


func _refresh_supply_panel() -> void:
	if is_instance_valid(app.supply_panel) and app.supply_panel.visible:
		var base: Dictionary = app.camp_snapshot()
		app.supply_panel.refresh(base, CampEconomy.rations(app.day, base.crew, app.food, app.camp_rules), app._progress_message, app._progress_dirty)


func _retry_facility() -> void:
	if app._camp_commit_busy: return
	if not app._progress_dirty:
		return
	app._accept_transaction(app.progress_session.retry(), true)
	app._refresh_supply_panel()


func _leave_supplies_for(action: StringName) -> void:
	if app._camp_commit_busy: return
	if app._facility_confirmation.visible:
		return
	app.supply_panel.hide()
	app._title.show()
	app.camp_scene.restore_focus()
	app._request_audio(&"ui_back")
	if action != &"camp":
		app._camp_action(action, 0)


func _sync_camp_scene() -> void:
	if not app._camp_scene_problem.is_empty():
		app._status.text = app._progress_message + "\n" + app._camp_scene_problem
		app._status.visible = app._title.visible
	if not is_instance_valid(app.camp_scene):
		return
	var eligible: bool = app._camp_open and app.phase == app.Phase.TITLE and not app._requires_continue and not app._progress_blocked and app._pending_settlement.is_empty() and app._battle_meta.get("state", "ACTIVE") != "FAILED"
	app.camp_scene.visible = eligible
	if not app.camp_scene.visible:
		app.camp_scene.clear()
		return
	var data: Dictionary = app.camp_snapshot()
	app.camp_scene.refresh(data, CampEconomy.rations(app.day, app.crew, app.food, app.camp_rules), not app.get_node("Interface/Screen/Title/Start").disabled, "可以选择出击目标" if not app.get_node("Interface/Screen/Title/Start").disabled else ("当前旅程不能出击"), app._progress_message)
	for child: Node in app._title.get_children():
		if child is CanvasItem and child != app.camp_scene:
			child.hide()
	app._status.hide()


func _camp_action(action: StringName, member_id: int) -> void:
	if not is_instance_valid(app.camp_scene) or not app.camp_scene.is_visible_in_tree() or app._settings_open() or app._hunger_confirmation.visible or app._progress_blocked or app._requires_continue or not app._camp_input_allowed():
		return
	match action:
		&"bus": app.open_mission_select()
		&"crew":
			if member_id > 0 and is_instance_valid(app.roster_panel) and not SurvivorRoster.member(app.crew, member_id).is_empty():
				app.roster_panel.selected_member_id = member_id
			app.open_roster()
			if member_id > 0 and is_instance_valid(app.roster_panel):
				app.roster_panel.selected_member_id = member_id
				app.roster_panel.refresh(app.camp_snapshot())
				app.roster_panel.buttons_by_id[member_id].grab_focus()
		&"weapons", &"inventory": app.open_loadout()
		&"workshop": app.open_loadout(true)
		&"supplies":
			if app.camp_scene.player_mode:
				app.open_supplies()
			else:
				app.camp_scene.open_info(action)
		&"training":
			app.open_training()
		&"specialties": app._show_equipment_catalog(app.progress_session.refresh_catalog())
		&"sound": app.open_sound_settings()
		&"home":
			app._camp_open = false
			app._refresh_presentation()
		&"quit": app.request_exit("quit")


func _guard_camp_editor(action: Callable) -> bool:
	if app._camp_commit_busy: return true
	if not is_instance_valid(app._camp_leave_dialog) or not is_instance_valid(app.roster_panel) or not app.roster_panel.visible or not app.roster_panel.name_edit.editable:
		return false
	var member: Dictionary = SurvivorRoster.member(app.crew, app.roster_panel.selected_member_id)
	if member.is_empty() or app.roster_panel.name_edit.text == member.call_sign:
		return false
	app._camp_leave_action = action
	app._camp_leave_dialog.popup_centered(Vector2i(620, 230))
	return true


func _camp_escape() -> bool:
	if app._camp_commit_busy: return true
	if is_instance_valid(app.pause_menu) and app.pause_menu.root.visible:
		return false
	# LineEdit consumes ui_cancel before _unhandled_input, so this scope owns its back intent.
	if app.phase != app.Phase.TITLE or app._new_game_confirmation.visible or app._hunger_confirmation.visible or (is_instance_valid(app._camp_leave_dialog) and app._camp_leave_dialog.visible):
		return false
	if is_instance_valid(app._facility_confirmation) and app._facility_confirmation.visible:
		return false
	if is_instance_valid(app.supply_panel) and app.supply_panel.visible:
		app._leave_supplies_for(&"camp")
	elif is_instance_valid(app.training_panel) and app.training_panel.visible:
		if app.training_panel.confirmation.visible:
			return false
		app.close_training()
	elif is_instance_valid(app.camp_scene) and app.camp_scene.is_visible_in_tree():
		if app.camp_scene.info_visible():
			app.camp_scene.close_info()
		else:
			app.camp_scene.restore_focus()
	elif is_instance_valid(app.growth_panel) and app.growth_panel.visible:
		app.close_growth()
	elif is_instance_valid(app.roster_panel) and app.roster_panel.visible:
		app.close_roster()
	elif is_instance_valid(app.loadout_panel) and app.loadout_panel.visible:
		if app.loadout_panel.confirmation.visible or app.loadout_panel.power_panel.confirmation.visible \
			or app.loadout_panel.workshop_confirmation.visible or app.loadout_panel.build_panel._confirmation.visible:
			return false
		if not app.loadout_panel.cancel_swap_preview() and not app.loadout_panel.back_from_workshop():
			app.close_loadout()
	elif app.mission_select.visible:
		app.close_mission_select()
	elif is_instance_valid(app.sound_settings) and app.sound_settings.visible:
		app.sound_settings.close_panel()
	else:
		return false
	return true


func _camp_input_allowed() -> bool:
	return not app._camp_commit_busy and not (is_instance_valid(app.training_panel) and app.training_panel.visible) and app.phase == app.Phase.TITLE and not app._new_game_confirmation.visible and not app._hunger_confirmation.visible and not (is_instance_valid(app.pause_menu) and app.pause_menu.root.visible) and not (is_instance_valid(app._camp_leave_dialog) and app._camp_leave_dialog.visible)


func _roster_training(id: int) -> void:
	if not is_instance_valid(app.roster_panel) or not app.roster_panel.visible: return
	app.roster_panel.hide()
	app.open_training()
	if is_instance_valid(app.training_panel) and app.training_panel.visible:
		app.training_panel.selected_member_id=id
		app.training_panel.refresh(app.camp_snapshot())


func open_training() -> void:
	if app.phase!=app.Phase.TITLE or not app._camp_open or app._settings_open() or app._requires_continue or app._progress_blocked or not app._pending_settlement.is_empty():
		return
	if not is_instance_valid(app.training_panel):
		app.training_panel = TrainingPanel.new()
		app._screen.add_child(app.training_panel)
		app.training_panel.closed.connect(app.close_training)
		app.training_panel.confirmed.connect(app.confirm_training)
		app.training_panel.retry_requested.connect(app.retry_training)
	app._title.hide()
	app.training_panel.show()
	app.training_panel.refresh(app.camp_snapshot())
	app.training_panel.back_button.grab_focus()
	app._request_audio(&"ui_confirm")


func close_training() -> void:
	if not is_instance_valid(app.training_panel) or app.training_panel.confirmation.visible:
		return
	app.training_panel.hide()
	app._title.show()
	app._update_camp()
	if is_instance_valid(app.camp_scene) and app.camp_scene.visible:
		app.camp_scene.hotspots[&"training"].grab_focus()


func confirm_training(request: Dictionary) -> void:
	if not request.get("kind") is String or request.kind!="train_trait":
		return
	if app.phase!=app.Phase.TITLE or not app._camp_open or not is_instance_valid(app.training_panel) or not app.training_panel.visible or app._requires_continue or app._progress_blocked or not app._pending_settlement.is_empty():
		return
	var accepted: bool = app._accept_transaction(app.progress_session.edit(app.camp_snapshot(),request),true)
	app.training_panel.refresh(app.camp_snapshot(),"训练已保存。粮食与本人Trait已同时确认；下次出击按新等级生效。" if accepted else app._progress_message,app._progress_blocked)
	if accepted:
		app._request_audio(&"ui_confirm")


func retry_training() -> void:
	if not is_instance_valid(app.training_panel) or not app.training_panel.visible or not app._progress_dirty:
		return
	var accepted: bool = app._accept_transaction(app.progress_session.retry(),true)
	app.training_panel.refresh(app.camp_snapshot(),"原训练已保存确认；没有再次扣粮或增加进度。" if accepted else app._progress_message,not accepted)


func _show_equipment_catalog(state: Dictionary) -> void:
	if app._equipment_catalog == null:
		app._equipment_catalog = EquipmentCatalog.new()
		app._equipment_catalog.theme = CampStyle.blue_hour_theme(app._screen.theme)
		app._screen.add_child(app._equipment_catalog)
		app._equipment_catalog.closed.connect(app._close_equipment_catalog)
		app._equipment_catalog.retry_requested.connect(func() -> void:
			app._equipment_catalog.present(app.progress_session.refresh_catalog()))
	app._title.hide()
	app._result.hide()
	app._equipment_catalog.show()
	app._equipment_catalog.present(state)


func _close_equipment_catalog() -> void:
	app._equipment_catalog.hide()
	if app.phase == app.Phase.TITLE:
		app._title.show()
		if app._camp_open:
			app.camp_scene.restore_focus()
		else:
			app._refresh_blue_hour_title()
			app._catalog_button.grab_focus()
	elif app.phase == app.Phase.RESULT:
		app._show_battle_result(app.camp_snapshot(), true)
		if app._pump_victory != null and app._pump_victory.visible:
			app._pump_victory.new_journey_button.grab_focus()
		else:
			app._battle_new_button.grab_focus()


func equip_build_item(slot: int, item: String) -> void:
	if app._camp_commit_busy: return
	if app.phase!=app.Phase.TITLE or not app.loadout_panel.visible or app._progress_blocked or not BuildState.enabled(app.camp_snapshot()): return
	var before: Dictionary = app.camp_snapshot()
	if EconomyBuildV1.enabled(before): await app._begin_camp_commit(before, "build_slot")
	var saved: bool=app._accept_transaction(app.progress_session.edit(before,{"kind":"build_slot","member_id":slot,"value":item}),true)
	app._camp_commit_busy = false
	app._camp_commit_label = ""
	app.loadout_panel.refresh(app.camp_snapshot(),"本局道具配装已保存；下一行动生效。" if saved else app._progress_message,app._progress_dirty)
	if app._progress_dirty:
		app.loadout_panel.focus_retry()
	if not saved:
		var build: Dictionary = app.camp_snapshot().journey.build
		app.loadout_panel.build_panel.present(build.owned, build.slots, false, false,
			build.get("opening", {}).get("plan", ""), BuildState.pool(app.camp_snapshot()), app.camp_snapshot())


func equip_power(id: String, slot: int = 0) -> void:
	var camp: Dictionary = app.camp_snapshot()
	if not PowerState.enabled(camp):
		return
	var kind: String = "power_equip" if PowerState.progression(camp.journey.build.powers) else "power_slot"
	app._edit_power({"kind":kind,"member_id":slot,"value":id}, "特殊能力装配已保存；下次出击生效。")


func invest_power(choice: String) -> void:
	app._edit_power({"kind":"power_invest","member_id":0,"value":choice}, "能力投资已保存；余额与效果已更新。")


func invest_build(choice: String) -> void:
	app._edit_power({"kind":"build_invest","member_id":0,"value":choice}, "道具投资已保存；余额与效果已更新。")


func _edit_power(request: Dictionary, success: String) -> void:
	if app._camp_commit_busy: return
	if app.phase != app.Phase.TITLE or not is_instance_valid(app.loadout_panel) or not app.loadout_panel.visible or app._progress_blocked:
		return
	var before: Dictionary = app.camp_snapshot()
	var frozen_request: Dictionary = request.duplicate(true)
	if EconomyBuildV1.enabled(before): await app._begin_camp_commit(before,String(request.kind))
	var saved: bool = app._accept_transaction(app.progress_session.edit(before,frozen_request),true)
	app._camp_commit_busy = false
	app._camp_commit_label = ""
	app.loadout_panel.refresh(app.camp_snapshot(),success if saved else app._progress_message,app._progress_dirty)
	if app._progress_dirty:
		app.loadout_panel.focus_retry()


func retry_power_edit() -> void:
	if app._camp_commit_busy: return
	if app.phase != app.Phase.TITLE or not is_instance_valid(app.loadout_panel) or not app.loadout_panel.visible or not app._progress_dirty:
		return
	var before: Dictionary = app.camp_snapshot()
	if EconomyBuildV1.enabled(before): await app._begin_camp_commit(before, "retry_edit")
	var saved: bool = app._accept_transaction(app.progress_session.retry(),true)
	app._camp_commit_busy = false
	app._camp_commit_label = ""
	app.loadout_panel.refresh(app.camp_snapshot(),"本次整备已保存；余额与状态已更新。" if saved else app._progress_message,not saved)
