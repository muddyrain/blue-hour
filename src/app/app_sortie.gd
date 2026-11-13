class_name AppSortie
extends RefCounted

var app: AppMain


func _init(owner: AppMain) -> void:
	app = owner


func open_mission_select() -> void:
	if app.phase != app.Phase.TITLE or app._settings_open() or app.get_node("Interface/Screen/Title/Start").disabled:
		return
	if not app._hunger_consented:
		app._hunger_confirmation.popup_centered(Vector2i(700,260))
		return
	app._title.hide()
	if app.mission_select.review_enabled:
		app.mission_select.show()
		app._load_mission_cards()
	else:
		var base: Dictionary = app.camp_snapshot()
		app.mission_select.refresh_daily(base, CampEconomy.rations(int(base.day), base.crew, int(base.food), app.camp_rules))
	app.mission_select.show()
	if not app.mission_select.review_enabled:
		app.mission_select.choices[0].grab_focus()
	app._request_audio(&"ui_confirm")


func _load_mission_cards() -> void:
	var base: Dictionary = app.camp_snapshot()
	var request_key: String = RecordEncoding.fingerprint(base)
	app._mission_request_key = request_key
	var rations: Dictionary = CampEconomy.rations(int(base.day), base.crew, int(base.food), app.camp_rules)
	app.mission_select.show_waiting(base, rations, request_key.is_empty())
	if request_key.is_empty() or app._mission_worker != null:
		return
	# Only the latest visible request may consume this worker's result.
	var worker: Thread = Thread.new()
	app._mission_worker = worker
	var error: Error = worker.start(app._prepare_mission_cards.bind(base))
	if error != OK:
		app._mission_worker = null
		app.mission_select.show_waiting(base, rations, true)
		return
	while worker.is_alive():
		await app.get_tree().process_frame
	if app._mission_worker != worker:
		return
	var prepared: Dictionary = worker.wait_to_finish()
	app._mission_worker = null
	if not app.mission_select.visible or app._mission_request_key.is_empty():
		return
	if app.phase != app.Phase.TITLE or app.get_node("Interface/Screen/Title/Start").disabled:
		app.close_mission_select()
		return
	if app._mission_request_key != request_key or not TransactionReceipt.same(base, app.camp_snapshot()):
		app._load_mission_cards()
		return
	if prepared.offers.is_empty():
		app.mission_select.show_waiting(base, rations, true)
		return
	app.mission_select.refresh_daily(base, rations, prepared)
	if app.get_viewport().gui_get_focus_owner() == app.mission_select.cancel_button:
		app.mission_select.choices[0].grab_focus()


func _retry_mission_cards() -> void:
	if app.mission_select.visible and not app.mission_select.loading:
		app._load_mission_cards()


func _leave_departure_for(action: StringName) -> void:
	if not app.mission_select.loading:
		app.close_mission_select()
		app._camp_action(action, 0)


func close_mission_select() -> void:
	app._mission_request_key = ""
	app.mission_select.hide()
	app._title.show()
	if is_instance_valid(app._blue_hour_title_art) and is_instance_valid(app.camp_scene) and app.camp_scene.is_visible_in_tree():
		app.camp_scene.restore_focus()
	app._request_audio(&"ui_back")


func _select_mission(supply: MissionSupply) -> void:
	if app._departure_pending or (app.mission_select.visible and app.mission_select.loading) or (is_instance_valid(app._blue_hour_title_art) and app.phase != app.Phase.TITLE):
		return
	var from_menu: bool = is_instance_valid(app._blue_hour_title_art) and app.mission_select.visible
	var started: int = Time.get_ticks_msec()
	app._departure_pending = from_menu
	app._mission_request_key = ""
	app.selected_supply = supply
	app.mission_select.hide()
	app.open_expedition()
	app._departure_pending = false
	if not from_menu:
		return
	if app.phase != app.Phase.EXPEDITION:
		# The transaction owns the failure message and blocking policy. Restore its view.
		if app._progress_blocked:
			app._camp_open = false
		app._title.show()
		app._refresh_presentation()
		if is_instance_valid(app.camp_scene) and app.camp_scene.is_visible_in_tree():
			app.camp_scene.restore_focus()
	elif Time.get_ticks_msec() - started >= app.SLOW_DEPARTURE_MS:
		app._fade_departure()


func _fade_departure() -> void:
	var cover: TextureRect = CampStyle.blue_hour_background(app.BLUE_HOUR_CAMP_ART)
	cover.name = "BlueHourDepartureFade"
	cover.modulate = Color(0.63, 0.76, 0.87, 0.84)
	app.get_node("Interface").add_child(cover)
	var fade: Tween = cover.create_tween()
	fade.tween_property(cover, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(cover.queue_free)


func open_expedition() -> void:
	app._open_sortie()


func _open_sortie(resume: Dictionary = {}) -> void:
	if app.phase != app.Phase.TITLE or app._settings_open():
		return
	if not app._hunger_consented:
		return
	if (app._battle_meta.get("state") == "FAILED" or CampaignState.ended(app.camp_snapshot())):
		return
	if (app._requires_continue or app._progress_blocked):
		return
	if resume.is_empty():
		var started: Dictionary = app.progress_session.begin(app.camp_snapshot(),app.selected_supply)
		if started.error != OK:
			app._accept_transaction(started)
			return
		app.selected_supply = app.progress_session.active_supply()
	app.expedition = app.ExpeditionScene.instantiate() as Expedition
	app.expedition.restoring_world = not resume.is_empty()
	app.expedition.battle_survival = true
	app.expedition.field_departure = app.camp_snapshot()
	app.expedition.field_join_gate = app.progress_session.join_field
	if not resume.is_empty():
		app.expedition.field_joins.assign(resume.receipt.joins.duplicate(true))
	app.expedition.membership_committed.connect(app._attach_damage_gates)
	app.expedition.rescue_completed = RescuePoolState.available(app.expedition.field_departure).is_empty()
	app.expedition.support_commit=app.progress_session.accept_support
	app.expedition.power_commit=app.progress_session.accept_power
	app.expedition.burst_commit=app.progress_session.accept_burst
	app.expedition.growth_binding = app.progress_session.token.duplicate(true)
	app.expedition.rescue_completed = RescuePoolState.available(app.expedition.field_departure).is_empty()
	app.expedition.battle_seed = "NONE"
	app.expedition.ui_theme = app._screen.theme
	app.expedition.initial_cash = app.cash
	app.expedition.initial_food = app.food
	app.expedition.camp_rules = app.camp_rules
	app.expedition.supply = app.selected_supply
	app.expedition.mission_title = app.selected_supply.layout.display_name
	app.expedition.day = app.day
	app.expedition.starting_health = app.crew_health.duplicate()
	app.expedition.crew_snapshot = app.crew.duplicate(true)
	app.expedition.loadout_snapshot = WeaponInventory.snapshot(app.camp_snapshot())
	app.audio.stop_world()
	app.audio.set_world_paused(false)
	app._active_sortie_id = "%s:%d" % [app.profile_id, app.settled_sorties + 1]
	app.expedition.sortie_id = app._active_sortie_id
	app._pending_settlement = {}
	app._finish_callback = app._on_expedition_finished.bind(app._active_sortie_id)
	app.expedition.finished.connect(app._finish_callback)
	app.expedition.combat_feedback.connect(app._on_combat_feedback)
	app.expedition.search_completed.connect(app._on_search_completed)
	app.expedition.engine_started.connect(app._on_engine_started)
	app.expedition.pause_changed.connect(app._on_pause_changed)
	app.expedition.help_changed.connect(app._on_help_changed)
	app.phase = app.Phase.EXPEDITION
	app.get_node("World").add_child(app.expedition)
	app._frozen_world = {}
	if not resume.is_empty():
		var world: Dictionary = resume.receipt.envelope.world
		var restored: String = SortieSnapshot.apply(app.expedition,world)
		if not restored.is_empty():
			app._disconnect_sortie_events()
			app.get_node("World").remove_child(app.expedition)
			app.expedition.queue_free()
			app.expedition = null
			app.phase = app.Phase.TITLE
			app._progress_blocked = true
			app._requires_continue = false
			app._progress_message = "无法安全恢复原战场，暂存未消费。" + app._suspend_problem({"reason":restored})
			app._update_camp()
			return
		app.expedition.suspend_sealed = true
		app._frozen_world = world.duplicate(true)
		var claimed: Dictionary = app.progress_session.claim_world(resume.receipt.envelope.world_hash)
		if claimed.error == OK:
			app.expedition.suspend_sealed = false
			app._frozen_world = {}
		else:
			app.pause_menu.suspend_message = "恢复消费未确认；战场保持暂停。" + app._suspend_problem(claimed)
	app._attach_damage_gates()
	app._screen.hide()
	app._request_audio(&"ui_confirm")
	if not resume.is_empty():
		app.open_pause_menu()


func _on_expedition_finished(report: Dictionary, sortie_id: String) -> void:
	if app.phase != app.Phase.EXPEDITION or sortie_id != app._active_sortie_id or sortie_id == app.last_settlement_id:
		return
	app.audio.stop_world()
	app._disconnect_sortie_events()
	app.phase = app.Phase.RESULT
	app._screen.show()
	app._title.hide()
	app._result.show()
	var carried: Dictionary = {"loot":app.expedition.loot,"food":app.expedition.food_loot,"weapons":app.expedition.weapon_loot.duplicate(true)}
	var prepared: Dictionary = app.progress_session.finish(report,carried)
	if prepared.error == OK:
		app._pending_settlement = prepared.camp.duplicate(true)
	else:
		app._pending_settlement = {}
		app._accept_transaction(prepared,bool(prepared.get("retry_packet",false)))
	if not app._pending_settlement.is_empty():
		if report.evacuated and app.expedition.layout.world_data.has("open_streets") and app.expedition.bus_view != null:
			app.phase = app.Phase.EXPEDITION
			app._screen.hide()
			app._result.hide()
			app.expedition.bus_view.departed.connect(app._present_finished_battle, app.CONNECT_ONE_SHOT)
			app.expedition.bus_view.departure()
		else:
			var failed: bool = app._pending_settlement.journey.state == "FAILED"
			app._present_finished_battle()
			if report.evacuated and not failed and app.expedition.bus_view != null:
				app._screen.hide()
				app.expedition.bus_view.departed.connect(func() -> void: app._screen.show(),app.CONNECT_ONE_SHOT)
				app.expedition.bus_view.departure()
		return
	if app._pending_settlement.is_empty():
		app._status.text = "结算数据无效，营地与旧档未改变。"
		app.get_node("Interface/Screen/Result/Heading").text = "结算未应用"
		app.get_node("Interface/Screen/Result/Scroll/Body").text = app._progress_message+"\n本次行动仍保留在事务记录中，不能退回旧档绕过。"
		app.get_node("Interface/Screen/Result/Continue").text = "返回首页 / 保留阻塞"
		return
	var ledger: Dictionary = app._pending_settlement.last_day
	app._status.text = "完整结果已冻结；返回营地确认提交。重启后继续使用同一结果。"
	app.get_node("Interface/Screen/Result/Heading").text = "平安归航" if report["evacuated"] else "队伍失去行动能力"
	app.get_node("Interface/Screen/Result/Scroll/Body").text = (
		"第 %d 日归航 · 返回营地后进入第 %d 天\n\n货币 %d + 带回 %d = %d\n食物 %d + 带回 %d - 口粮 %d = %d\n今日需求 %d · 实耗 %d · 缺口 %d\n%s\n\n队员生命 %d / %d · 搜集 %d 处 · 击退 %d"
		% [app.day, int(app._pending_settlement.day), app.cash, ledger.cash_gained, ledger.cash_after,
		app.food, ledger.food_stored, ledger.food_consumed, ledger.food_after,
		ledger.food_required, ledger.food_consumed, ledger.food_shortage,
		HungerOutcome.description(ledger),
		ceili(report.health[0]), ceili(report.health[1]), int(report.get("sites_searched", 1 if report.get("searched", false) else 0)), report.kills]
	)
	if ledger.food_overflow > 0:
		app.get_node("Interface/Screen/Result/Scroll/Body").text += "\n库存上限：另有 %d 食物未入库。" % ledger.food_overflow
	var reward_items: Array = report.get("weapons", [])
	if not reward_items.is_empty() and report.evacuated:
		for item: Dictionary in reward_items:app.get_node("Interface/Screen/Result/Scroll/Body").text += "\n带回武器："+WeaponInventory.loot_description(item)+" · 回营后可维修整备"


func _disconnect_sortie_events() -> void:
	if not is_instance_valid(app.expedition):
		return
	if app.expedition.combat_feedback.is_connected(app._on_combat_feedback):
		app.expedition.combat_feedback.disconnect(app._on_combat_feedback)
		app.expedition.search_completed.disconnect(app._on_search_completed)
		app.expedition.engine_started.disconnect(app._on_engine_started)
		app.expedition.pause_changed.disconnect(app._on_pause_changed)
		app.expedition.help_changed.disconnect(app._on_help_changed)
		app.expedition.finished.disconnect(app._finish_callback)


func _attach_damage_gates() -> void:
	app._damage_gates.clear()
	if not is_instance_valid(app.expedition):
		return
	for actor: FieldActor in app.expedition.survivors:
		var gate: PersistedDamageGate = app.progress_session.damage_gate(actor)
		app._damage_gates.append(gate)
		actor.damage_gate = gate.before_damage
		actor.permanent_death_enabled = true


func _on_combat_feedback(event: Dictionary) -> void:
	if event["kind"] == "shot":
		app._request_audio(&"fire", true)
		if float(event.get("applied_damage", 0.0)) > 0.0:
			app._request_audio(&"hit", true)
	elif event["kind"] == "hit" and float(event.get("applied_damage", 0.0)) > 0.0:
		app._request_audio(&"hit", true)


func _on_search_completed(_reward: int) -> void:
	app._request_audio(&"collect_complete", true)


func _on_engine_started() -> void:
	app._request_audio(&"bus_start", true)
	app._request_audio(&"ui_confirm")


func _on_pause_changed(paused: bool) -> void:
	app.audio.set_world_paused(paused)
	app._request_audio(&"ui_confirm")


func _on_help_changed(expanded: bool) -> void:
	app._request_audio(&"ui_confirm" if expanded else &"ui_back")


func suspend_sortie() -> void:
	if app.phase != app.Phase.EXPEDITION or not is_instance_valid(app.expedition) or not app.pause_menu.root.visible:
		return
	var quit_after_save: bool = app.pause_menu.confirming and app._exit_target == "quit"
	if app._frozen_world.is_empty():
		app._frozen_world = SortieSnapshot.capture(app.expedition)
	if app._frozen_world.is_empty():
		app.pause_menu.suspend_message = "未保存成功：当前状态不能完整暂存，请正常巴士撤离。"
		app.pause_menu.show_pause(app._menu_was_paused)
		return
	# Once publication is attempted, a failure may still leave a durable snapshot.
	# Seal the original world until that anchor is consumed or publication is confirmed.
	app.expedition.suspend_sealed = true
	var saved: Dictionary = app.progress_session.suspend_world(app._frozen_world)
	if saved.error != OK:
		print("BH_SUSPEND_BLOCK ",saved.get("reason",""))
		app.pause_menu.suspend_message = "未保存成功，原场景保持暂停；可重试暂存或继续确认安全消费。\n" + app._suspend_problem(saved)
		app.pause_menu.show_pause(app._menu_was_paused)
		return
	app.audio.stop_world()
	app._disconnect_sortie_events()
	app._damage_gates.clear()
	app.get_node("World").remove_child(app.expedition)
	app.expedition.queue_free()
	app.expedition = null
	app._frozen_world = {}
	app.pause_menu.close()
	app.pause_menu.suspend_message = ""
	app._exit_target = ""
	app._menu_from_pause = false
	app.phase = app.Phase.TITLE
	app._camp_open = false
	app._progress_blocked = false
	app._requires_continue = true
	app._progress_dirty = false
	app._progress_message = "本次出击已暂存并回读确认。下次继续原战场；没有回营、奖励、扣粮或推进日期。"
	app._screen.show()
	app._title.show()
	app._continue_button.text = "继续未完成的出击 →"
	app._update_camp()
	if quit_after_save:
		app.audio.shutdown()
		app.get_tree().quit()


func _suspend_problem(result: Dictionary) -> String:
	var reason: String = result.get("reason", "UNKNOWN")
	print("BH_SUSPEND_DETAIL build=%s reason=%s" % [SortieSnapshot.GROWTH_BUILD, reason])
	if "WORLD_OUTDOOR_BUILD_MISMATCH" in reason:
		return "此空投途中暂存使用旧回收规则，请用原版本继续。暂存未消费，原件保留。"
	if "WORLD_DAILY_BUILD_MISMATCH" in reason:
		return "此途中进度属于旧街区版本，请用原版本继续。暂存未消费，原件保留，不回退旧营地。"
	if "WORLD_CONTACT_BUILD_MISMATCH" in reason:
		return "此途中暂存使用旧接触规则，请使用原兼容版本继续；本次未消费或改写暂存。"
	if "BINDING" in reason or "ACK" in reason:
		return "保存确认尚未完成；请保留原记录并重试，不能视为保存成功。"
	if "WRITER" in reason or "LOCK" in reason or "LEASE" in reason:
		return "进度写入权限不可用，可能被另一进程占用；请先关闭另一实例再重试。"
	if "CAPACITY" in reason or "LIMIT" in reason or "SPACE" in reason:
		return "保存容量不足；请保留原记录，勿删除事务文件。"
	if "MISMATCH" in reason or "HASH" in reason or "CORRUPT" in reason:
		return "进度身份、规则或内容校验不一致；为防止回档，继续受阻。"
	return "当前战场或持久记录未通过安全检查；请保留记录。详细原因已写入内部日志。"


func _confirm_result_ui() -> void:
	if app._camp_commit_busy: return
	if not EconomyBuildV1.enabled(app.camp_snapshot()):
		app.return_to_title()
		return
	var button: Button = app.get_node("Interface/Screen/Result/Continue")
	var caption: String = button.text
	app._camp_commit_busy = true
	app._camp_commit_label = "return"
	button.text = "正在确认归航并保存…"
	button.disabled = true
	await app.get_tree().process_frame
	await app.get_tree().process_frame
	app.return_to_title()
	app._camp_commit_busy = false
	app._camp_commit_label = ""
	if button.text == "正在确认归航并保存…": button.text = caption
	button.disabled = false


func _begin_camp_commit(before: Dictionary, kind: String) -> void:
	app._camp_commit_busy = true
	app._camp_commit_label = kind
	if is_instance_valid(app.loadout_panel) and app.loadout_panel.visible:
		app.loadout_panel.refresh(before,"正在保存整备，请稍候…",true)
		app.loadout_panel.armory._retry_button.hide()
		app.loadout_panel.power_panel.retry_button.hide()
	if is_instance_valid(app.supply_panel) and app.supply_panel.visible:
		app.supply_panel.refresh(before,CampEconomy.rations(app.day,before.crew,app.food,app.camp_rules),"正在保存设施，请稍候…",true)
		app.supply_panel._retry.hide()
	await app.get_tree().process_frame
	await app.get_tree().process_frame
