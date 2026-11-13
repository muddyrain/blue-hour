class_name AppMenus
extends RefCounted

var app: AppMain


func _init(owner: AppMain) -> void:
	app = owner


func return_to_title() -> void:
	if app.phase != app.Phase.RESULT:
		return
	if not app._pending_settlement.is_empty() and (app._pending_settlement.journey.state=="FAILED" or CampaignState.ended(app._pending_settlement)):
		var terminal: Dictionary=app._pending_settlement.duplicate(true)
		if not app._accept_transaction(app.progress_session.commit_result(),true):
			app._show_battle_result(app._pending_settlement,false)
			return
		app._pending_settlement={}
		app._show_battle_result(terminal,true)
		return
	app.audio.stop_world()
	app._disconnect_sortie_events()
	if app.phase == app.Phase.RESULT and not app._pending_settlement.is_empty():
		if not app._accept_transaction(app.progress_session.commit_result(),true): return
		app._pending_settlement = {}
	app._damage_gates.clear()
	if app._progress_blocked:
		app._camp_open = false
	if app.expedition != null:
		app.get_node("World").remove_child(app.expedition)
		app.expedition.queue_free()
		app.expedition = null
	app.phase = app.Phase.TITLE
	app._screen.show()
	app._title.show()
	app._result.hide()
	app._back.hide()
	if app._progress_dirty:
		app.save_camp()
	app._update_camp()
	app._request_audio(&"ui_back")


func _quit() -> void:
	app.request_exit("quit")


func open_pause_menu() -> void:
	if app.phase != app.Phase.EXPEDITION or app.expedition.phase == Expedition.Phase.FINISHED or app.pause_menu.root.visible:
		return
	app._lock_menu_world()
	app._menu_from_pause = true
	app._configure_suspend_menu()
	app.pause_menu.show_pause(app._menu_was_paused)


func _configure_suspend_menu() -> void:
	app.pause_menu.suspend_available = is_instance_valid(app.expedition)
	app.pause_menu.suspend_enabled = true
	if app.pause_menu.suspend_available:
		var preview: Dictionary = app.progress_session.preview_suspend(SortieSnapshot.capture(app.expedition))
		app.pause_menu.suspend_enabled = preview.error == OK
		if preview.error != OK:
			app.pause_menu.suspend_message = "安全暂存不可用；原记录保留。" + app._suspend_problem(preview)


func _lock_menu_world() -> void:
	if app.phase != app.Phase.EXPEDITION or not is_instance_valid(app.expedition):
		return
	app._menu_was_paused = app.expedition.is_paused
	if not app.expedition.is_paused:
		app.expedition.toggle_pause()
	app.expedition.set_process_unhandled_input(false)
	app.expedition._hud.view.set_process_unhandled_key_input(false)
	app.expedition.camera.menu_blocked = true
	var focus: Control = app.get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()


func close_pause_menu() -> void:
	if app.phase == app.Phase.EXPEDITION and is_instance_valid(app.expedition) and app.expedition.suspend_sealed:
		var released: Dictionary = app.progress_session.release_frozen_world(SurvivalContracts.fingerprint(app._frozen_world))
		if released.error != OK:
			app.pause_menu.suspend_message = "未保存成功，仍在原场景暂停；无法确认消费。" + app._suspend_problem(released)
			app.pause_menu.show_pause(true)
			return
		app.expedition.suspend_sealed = false
		app._frozen_world = {}
	app.pause_menu.suspend_message = ""
	app.pause_menu.close()
	app._exit_target = ""
	app._menu_from_pause = false
	if app.phase == app.Phase.EXPEDITION and is_instance_valid(app.expedition):
		app.expedition.set_process_unhandled_input(true)
		app.expedition._hud.view.set_process_unhandled_key_input(true)
		app.expedition.camera.menu_blocked = false
		if app.expedition.is_paused != app._menu_was_paused:
			app.expedition.toggle_pause()


func request_exit(target: String) -> void:
	if app._startup_pending:
		if target == "quit":
			app._startup_exit_requested = true
			app._startup_label.text = "正在核验旅程与资料…\n核验完成后将显示退出确认。"
		return
	# A native exclusive dialog owns Esc/close until its choice is resolved.
	if is_instance_valid(app._facility_confirmation) and app._facility_confirmation.visible:
		return
	if app._new_game_confirmation.visible or app._hunger_confirmation.visible or (is_instance_valid(app._camp_leave_dialog) and app._camp_leave_dialog.visible) or (is_instance_valid(app.training_panel) and app.training_panel.confirmation.visible):
		return
	if app.pause_menu.root.visible and app.pause_menu.confirming:
		return
	if not app.pause_menu.root.visible:
		app._menu_from_pause = false
		app._lock_menu_world()
	app._exit_target = target
	var title: String = "退出游戏"
	var message: String = "已保存的营地进度保留。关闭不会开始新的行动。"
	var danger: String = "确认退出游戏"
	if app._progress_blocked:
		title = "当前进度仍受阻"
		message = "现有记录与已确认阵亡保留。退出不会解除阻塞、生成结算或读取旧营地。\n" + app._progress_message
	elif app._progress_dirty:
		title = "营地变更尚未保存"
		message = "部分变更仅在当前内存中，退出可能丢失这些变更。\n请取消并重试保存；旧文件与已有记录保留。"
	elif app.phase == app.Phase.EXPEDITION:
		title = "这次行动尚未完成"
		message = "本次出击尚未完整结算；退出可能使原旅程无法继续。\n已确认阵亡不会因退出撤销；未结算物资与日期不会被擅自推算。\n正常回营：留在行动，发动巴士并集合所有存活成员。\n强杀、闪退与断电无法由此菜单拦截。"
		danger = "仍退出到首页（行动未结算）" if target == "home" else "仍关闭游戏（行动未结算）"
	elif app.phase == app.Phase.RESULT:
		if not app._pending_settlement.is_empty():
			title = "完整结果已冻结"
			message = "重启后继续会复用已有冻结结果，只提交一次。\n本次关闭不重新计算资源、口粮、日期或阵亡。"
		elif app._battle_meta.state == "FAILED":
			title = "旅程已结束"
			message = "全灭终局与阵亡记录已保存；重启不能复活或返回旧营地。"
	elif app._requires_continue and app.progress_session.inspect().get("state") == "RECOVERY_READY":
		title = "已有完整冻结结果待继续"
		message = "已有 RESULT_READY 保留。重启后明确继续将复用原冻结结果并提交一次。\n关闭不会重新计算，也不会回退到出击前营地。"
	elif app._requires_continue and app._pending_save.is_empty() and not app._progress_blocked:
		title = "本次出击已暂存"
		message = "下次使用同一隔离进度入口继续原战场；暂存已回读确认。\n这次尚未回营或结算，没有领取奖励、扣粮或推进日期。"
	var offer_suspend: bool = app.phase == app.Phase.EXPEDITION and is_instance_valid(app.expedition) and app.expedition.phase != Expedition.Phase.FINISHED and not app._progress_blocked
	if offer_suspend:
		app._configure_suspend_menu()
		offer_suspend = app.pause_menu.suspend_enabled
		message += "\n推荐安全暂存：写入并回读确认后才离开，不结算、不撤销阵亡。" if offer_suspend else "\n" + app.pause_menu.suspend_message
		if offer_suspend:
			danger = "危险退出到首页（不暂存）" if target == "home" else "危险关闭游戏（不暂存）"
	app.pause_menu.show_exit(title, message, danger, offer_suspend)


func _cancel_exit() -> void:
	app._exit_target = ""
	if app._menu_from_pause:
		app._configure_suspend_menu()
		app.pause_menu.show_pause(app._menu_was_paused)
	else:
		app.close_pause_menu()


func _confirm_exit() -> void:
	if app._exit_target == "home":
		app.close_pause_menu()
		if app.pause_menu.root.visible:
			return
		app.audio.stop_world()
		app._disconnect_sortie_events()
		app._damage_gates.clear()
		app.get_node("World").remove_child(app.expedition)
		app.expedition.queue_free()
		app.expedition = null
		app.phase = app.Phase.TITLE
		app._camp_open = false
		app._progress_blocked = true
		app._requires_continue = false
		app._progress_message = "上次行动中断，未形成完整结算。原旅程目前无法继续；已确认阵亡保留。不能返回旧营地。"
		app._screen.show()
		app._title.show()
		app._update_camp()
		return
	print("BH_EXIT requested")
	app.audio.shutdown()
	app.get_tree().quit()


func open_sound_settings() -> void:
	if app.phase != app.Phase.TITLE or app._settings_open():
		return
	if not is_instance_valid(app.sound_settings):
		app.sound_settings = SoundSettingsPanel.new()
		app.sound_settings.preferences = app.audio_preferences
		app.sound_settings.diagnostic = app._settings_diagnostic
		app.sound_settings.saved.connect(func() -> void: app._request_audio(&"ui_confirm"))
		app.sound_settings.closed.connect(app._close_sound_settings)
		app._screen.add_child(app.sound_settings)
	app.sound_settings.show()
	app._title.hide()
	if is_instance_valid(app._blue_hour_title_art):
		app.sound_settings.back_button.grab_focus()
	app._request_audio(&"ui_confirm")


func _close_sound_settings() -> void:
	app._title.show()
	app._request_audio(&"ui_back")


func _settings_open() -> bool:
	if is_instance_valid(app.supply_panel) and app.supply_panel.visible:
		return true
	if is_instance_valid(app._equipment_catalog) and app._equipment_catalog.visible:
		return true
	if is_instance_valid(app._facility_confirmation) and app._facility_confirmation.visible:
		return true
	return (is_instance_valid(app.training_panel) and app.training_panel.visible) or (is_instance_valid(app._camp_leave_dialog) and app._camp_leave_dialog.visible) or (is_instance_valid(app.camp_scene) and app.camp_scene.info_visible()) or (is_instance_valid(app.sound_settings) and app.sound_settings.visible) or app._new_game_confirmation.visible or (is_instance_valid(app.mission_select) and app.mission_select.visible) or (is_instance_valid(app.loadout_panel) and app.loadout_panel.visible) or (is_instance_valid(app.roster_panel) and app.roster_panel.visible) or (is_instance_valid(app.growth_panel) and app.growth_panel.visible)


func _request_audio(cue: StringName, world: bool = false) -> bool:
	var accepted: bool = app.audio.play_world(cue) if world else app.audio.play_ui(cue)
	app.audio_requested.emit(cue, world, accepted)
	return accepted
