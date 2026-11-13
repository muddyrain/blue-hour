class_name AppMain
extends Node
## Owns session/camp and one sortie; settlement is accepted once per sortie.

signal audio_requested(cue: StringName, world: bool, accepted: bool)

enum Phase {
	TITLE,
	EXPEDITION,
	RESULT,
}

const ExpeditionScene: PackedScene = preload("res://src/features/expedition/expedition.tscn")
const BLUE_HOUR_TITLE_ART: Texture2D = preload("res://assets/ui/m20/title-blue-hour.png")
const BLUE_HOUR_CAMP_ART: Texture2D = preload("res://assets/ui/m20/camp-blue-hour.png")
const SLOW_DEPARTURE_MS: int = 120

var phase: Phase = Phase.TITLE
var expedition: Expedition
var cash: int = 53
var day: int = 2
var crew: Array[Dictionary] = SurvivorRoster.new_crew()
var crew_health: Array[float]:
	get:
		var values: Array[float] = []
		for member_id: int in [1, 2]:
			values.append(float(SurvivorRoster.member(crew, member_id).health))
		return values
var settled_sorties: int = 0
var camp_rules: CampRules = preload("res://src/features/camp/camp_rules.tres")
var selected_supply: MissionSupply = preload("res://src/features/camp/supermarket.tres")
var mission_select: MissionSelect
var supply_panel: CampSupplyPanel
var _mission_worker: Thread
var _mission_request_key: String = ""
var food: int = camp_rules.initial_food
var last_day: Dictionary = {}
var weapons: Array[Dictionary] = []
var loadout: Array[Dictionary] = []
var camp_spending: int = 0
var loadout_panel: LoadoutPanel
var _loadout_button: Button
var roster_panel: RosterPanel
var growth_panel: GrowthPanel
var _roster_button: Button
var _return_roster_member: int = 0
var _camp_open: bool = false
var _home_button: Button
var _home_return: Button
var audio_settings_path: String = "user://settings/audio.json"
var audio_preferences: AudioPreferences
var audio: B1AudioService
var sound_settings: SoundSettingsPanel
var _settings_diagnostic: String = ""
var progress_path: String
var run_save: RunSave
var _frozen_world: Dictionary = {}
var training_panel: TrainingPanel
var _training: Array = []
var camp_scene: CampSceneView
var _camp_scene_problem: String = ""
var _camp_leave_dialog: ConfirmationDialog
var _facility_confirmation: ConfirmationDialog
var _facility_choice: String = ""
var _facility_upgrade: bool = false
var _economy_request: Dictionary = {}
var _camp_leave_action: Callable
var _recruits: Array = []
var _hunger_consented: bool = false
var _hunger_confirmation: ConfirmationDialog
var _camp_backdrop: CampBackdrop
var _blue_hour_title_art: TextureRect
var _blue_hour_title_focus: Button
var _departure_pending: bool = false
var _battle_meta: Dictionary = {}
var _survival_origin: Dictionary = {}
var _battle_new_button: Button
var _pump_victory: PumpVictoryView
var _pump_details_back: Button
var progress_session: ProductionProgress
var _transactional_new_pending: bool = false
var _damage_gates: Array[PersistedDamageGate] = []
var profile_id: String = ""
var last_settlement_id: String = ""
var _active_sortie_id: String = ""
var _finish_callback: Callable
var _pending_save: Dictionary = {}
var _pending_settlement: Dictionary = {}
var _backup_save: Dictionary = {}
var _requires_continue: bool = false
var _progress_blocked: bool = false
var _progress_dirty: bool = false
var _camp_commit_busy: bool = false
var _camp_commit_label: String = ""
var _allow_invalid_replacement: bool = false
var _progress_message: String = ""
var _continue_button: Button
var _backup_button: Button
var _retry_button: Button
var _new_game_confirmation: ConfirmationDialog
var _opening_picker: OpeningBuildPicker
var _opening_confirm_pending: bool = false
var _catalog_button: Button
var _equipment_catalog: EquipmentCatalog
var pause_menu: SortiePauseMenu
var _menu_was_paused: bool = false
var _menu_from_pause: bool = false
var _exit_target: String = ""
var _startup_pending: bool = false
var _startup_worker: Thread
var _startup_overlay: PanelContainer
var _startup_label: Label
var _startup_exit_requested: bool = false

var _session: AppSession = AppSession.new(self)
var _sortie: AppSortie = AppSortie.new(self)
var _results: AppResults = AppResults.new(self)

@onready var _title: Control = $Interface/Screen/Title
@onready var _status: Label = $Interface/Screen/Status
@onready var _back: Button = $Interface/Screen/Back
@onready var _screen: Control = $Interface/Screen
@onready var _result: Control = $Interface/Screen/Result


func _ready() -> void:
	await _session._boot_session()
	audio_preferences = AudioPreferences.new(audio_settings_path)
	var load_result: Error = audio_preferences.load_preferences()
	if load_result == ERR_FILE_NOT_FOUND:
		_settings_diagnostic = "首次使用默认音量，点击保存后保留。"
	elif load_result != OK:
		_settings_diagnostic = "声音设置读取失败，原文件已保留。可调整音量后显式保存。"
	audio = B1AudioService.new(audio_preferences)
	add_child(audio)
	$Interface/Screen/Title/Start.pressed.connect(open_mission_select)
	mission_select = MissionSelect.new()
	mission_select.review_enabled = true
	_screen.add_child(mission_select)
	mission_select.hide()
	mission_select.selected.connect(_select_mission)
	mission_select.cancelled.connect(close_mission_select)
	mission_select.retry_requested.connect(_retry_mission_cards)
	mission_select.navigation_requested.connect(_leave_departure_for)
	$Interface/Screen/Title/Reset.pressed.connect(reset_demo)
	$Interface/Screen/Title/Quit.pressed.connect(_quit)
	$Interface/Screen/Title/Sound.pressed.connect(open_sound_settings)
	_loadout_button = _progress_button("营地武器 / 配装 →", 600.0, open_loadout)
	_loadout_button.position.x = 100.0
	_loadout_button.size = Vector2(448, 40)
	_roster_button = _progress_button("营地幸存者 →", 600.0, open_roster)
	_roster_button.position.x = 572.0
	_roster_button.size = Vector2(274, 40)
	$Interface/Screen/Result/Continue.pressed.connect(_confirm_result_ui)
	_back.pressed.connect(return_to_title)
	_setup_presentation()
	_setup_blue_hour_title()
	mission_select.theme = CampStyle.blue_hour_theme(_screen.theme)
	_setup_camp_scene()
	pause_menu = SortiePauseMenu.new()
	add_child(pause_menu)
	pause_menu.root.theme = _screen.theme
	pause_menu.resume_requested.connect(close_pause_menu)
	pause_menu.bus_requested.connect(func() -> void:
		close_pause_menu()
		if is_instance_valid(expedition) and not pause_menu.root.visible:
			expedition.camera.pan_by(expedition.layout.bus_block.get_center() - expedition.camera.position))
	pause_menu.home_requested.connect(func() -> void: request_exit("home"))
	pause_menu.quit_requested.connect(func() -> void: request_exit("quit"))
	pause_menu.exit_cancelled.connect(_cancel_exit)
	pause_menu.exit_confirmed.connect(_confirm_exit)
	pause_menu.suspend_requested.connect(suspend_sortie)
	_update_camp()
	if _startup_pending:
		_startup_overlay.queue_free()
		_startup_pending = false
		if _startup_exit_requested:
			request_exit("quit")
	print("BH_READY phase=TITLE renderer=%s" % RenderingServer.get_current_rendering_method())


func _exit_tree() -> void:
	if _startup_worker != null and _startup_worker.is_started():
		_startup_worker.wait_to_finish()
		_startup_worker = null
	if _mission_worker != null:
		_mission_worker.wait_to_finish()
		_mission_worker = null
	if progress_session != null:
		progress_session.close()
	if is_instance_valid(audio):
		audio.shutdown()


func _input(event: InputEvent) -> void:
	if _startup_pending:
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_equipment_catalog) and _equipment_catalog.visible and event.is_action_pressed("return_to_title") and not event.is_echo():
		_close_equipment_catalog()
		get_viewport().set_input_as_handled()
		return
	if phase==Phase.EXPEDITION and is_instance_valid(expedition) and expedition._hud!=null and expedition._hud.view.persona_details.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			expedition._hud.view.persona_details.close()
			get_viewport().set_input_as_handled()
			return
		if event.keycode==KEY_SPACE:
			expedition.toggle_pause()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("return_to_title") and not event.is_echo() and _camp_escape():
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(pause_menu) and pause_menu.root.visible and event is InputEventKey:
		var focus: Control = get_viewport().gui_get_focus_owner()
		if focus == null or not pause_menu.root.is_ancestor_of(focus):
			if event.is_action("ui_focus_next") or event.is_action("ui_focus_prev") or event.is_action("ui_accept"):
				pause_menu.buttons[0].grab_focus()
				get_viewport().set_input_as_handled()
				return
	if is_instance_valid(pause_menu) and pause_menu.root.visible and event.is_action_pressed("return_to_title"):
		if not event.is_echo():
			if pause_menu.confirming:
				_cancel_exit()
			else:
				close_pause_menu()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _startup_pending:
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_equipment_catalog) and _equipment_catalog.visible:
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(pause_menu) and pause_menu.root.visible:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("return_to_title") and phase == Phase.EXPEDITION \
			and expedition.event_sortie_panel != null and expedition.event_sortie_panel.visible:
		if not event.is_echo():
			expedition.event_sortie_panel.hide()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("return_to_title") and phase == Phase.EXPEDITION and expedition.support_aiming:
		expedition.support_aiming=false
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("return_to_title") and phase == Phase.EXPEDITION:
		if event.is_echo():
			return
		if expedition._hud.view._help.visible:
			expedition._hud.view._help_button.pressed.emit()
		else:
			open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("return_to_title") and is_instance_valid(camp_scene) and camp_scene.is_visible_in_tree():
		if camp_scene.info_visible():
			camp_scene.close_info()
		else:
			camp_scene.restore_focus()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("return_to_title") and is_instance_valid(growth_panel) and growth_panel.visible:
		close_growth()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("return_to_title") and is_instance_valid(roster_panel) and roster_panel.visible:
		close_roster()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("return_to_title") and is_instance_valid(loadout_panel) and loadout_panel.visible:
		close_loadout()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("return_to_title") and is_instance_valid(mission_select) and mission_select.visible:
		close_mission_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("return_to_title") and is_instance_valid(sound_settings) and sound_settings.visible:
		sound_settings.close_panel()
		get_viewport().set_input_as_handled()


func _confirm_result_ui() -> void:
	await _sortie._confirm_result_ui()


func _begin_camp_commit(before: Dictionary, kind: String) -> void:
	await _sortie._begin_camp_commit(before, kind)


func return_to_title() -> void:
	if phase != Phase.RESULT:
		return
	if not _pending_settlement.is_empty() and (_pending_settlement.journey.state=="FAILED" or CampaignState.ended(_pending_settlement)):
		var terminal: Dictionary=_pending_settlement.duplicate(true)
		if not _accept_transaction(progress_session.commit_result(),true):
			_show_battle_result(_pending_settlement,false)
			return
		_pending_settlement={}
		_show_battle_result(terminal,true)
		return
	audio.stop_world()
	_disconnect_sortie_events()
	if phase == Phase.RESULT and not _pending_settlement.is_empty():
		if not _accept_transaction(progress_session.commit_result(),true): return
		_pending_settlement = {}
	_damage_gates.clear()
	if _progress_blocked:
		_camp_open = false
	if expedition != null:
		$World.remove_child(expedition)
		expedition.queue_free()
		expedition = null
	phase = Phase.TITLE
	_screen.show()
	_title.show()
	_result.hide()
	_back.hide()
	if _progress_dirty:
		save_camp()
	_update_camp()
	_request_audio(&"ui_back")


func open_mission_select() -> void:
	_sortie.open_mission_select()


func _load_mission_cards() -> void:
	await _sortie._load_mission_cards()


static func _prepare_mission_cards(base: Dictionary) -> Dictionary:
	var offers: Array[Dictionary] = DailyActions.offers(base)
	var supplies: Array[MissionSupply] = []
	for offer: Dictionary in offers:
		supplies.append(DailyActions.supply(offer))
	return {"offers":offers, "supplies":supplies}


func _retry_mission_cards() -> void:
	_sortie._retry_mission_cards()


func _leave_departure_for(action: StringName) -> void:
	_sortie._leave_departure_for(action)


func close_mission_select() -> void:
	_sortie.close_mission_select()


func _select_mission(supply: MissionSupply) -> void:
	_sortie._select_mission(supply)


func _fade_departure() -> void:
	_sortie._fade_departure()


func open_expedition() -> void:
	_sortie.open_expedition()


func _open_sortie(resume: Dictionary = {}) -> void:
	_sortie._open_sortie(resume)


func reset_demo() -> void:
	_session.reset_demo()


func _pool_initial() -> Dictionary:
	return _session._pool_initial()


func _open_opening_choice() -> void:
	_session._open_opening_choice()


func _confirm_new_journey() -> void:
	_session._confirm_new_journey()


func _new_game(opening_plan: String = "", catalog_policy: Dictionary = {}, m47_policy: Dictionary = {}) -> void:
	_session._new_game(opening_plan, catalog_policy, m47_policy)


func _on_expedition_finished(report: Dictionary, sortie_id: String) -> void:
	_sortie._on_expedition_finished(report, sortie_id)


func _update_camp() -> void:
	_status.text = _progress_message
	$Interface/Screen/Title/Camp.text = "第 %d 天   /   货币 %d   /   队员生命 %d · %d" % [day, cash, ceili(crew_health[0]), ceili(crew_health[1])]
	var daily: Dictionary = CampEconomy.rations(day, camp_snapshot().crew, food, camp_rules)
	var ration_text: String = "今日口粮 %d（队员%s，每人%d）" % [daily.required, str(daily.member_ids), daily.per_member]
	ration_text += " · 缺%d，建议选择超市" % daily.shortage if daily.shortage > 0 else " · 库存足够"
	var change: String = "初始库存为样板值；出击前可选搜集或超市。"
	if not last_day.is_empty():
		change = "上次归航：食物 %d +%d −%d = %d；货币 +%d；缺口%d" % [last_day.food_before, last_day.food_stored, last_day.food_consumed, last_day.food_after, last_day.cash_gained, last_day.food_shortage]
	if not last_day.is_empty() and last_day.food_shortage > 0:
		change += "；损失候选%d人，未应用" % HungerOutcome.candidate(last_day).loss_count
	$Interface/Screen/Title/Camp.text = "第 %d 天 / 货币 %d / 食物 %d / 队员生命 %d · %d\n%s\n%s" % [day,cash,food,ceili(crew_health[0]),ceili(crew_health[1]),ration_text,change]
	var eligible: bool = (_battle_meta.get("state") == "ACTIVE" and not CampaignState.ended(camp_snapshot()))
	$Interface/Screen/Title/Start.disabled = _requires_continue or _progress_blocked or not eligible
	_loadout_button.disabled = _requires_continue or _progress_blocked
	_roster_button.disabled = _requires_continue or _progress_blocked
	_continue_button.visible = _requires_continue
	_backup_button.visible = _progress_blocked and not _backup_save.is_empty()
	_retry_button.visible = _progress_dirty
	if _requires_continue and _pending_save.is_empty():
		$Interface/Screen/Title/Camp.text = "已有未完成的出击暂存；请继续原战场。暂存没有回营、结算、扣粮或推进日期。"
	elif _requires_continue:
		$Interface/Screen/Title/Camp.text = "已保存：第 %d 天 / 货币 %d / 食物 %d\n点击“继续游戏”恢复营地；旧档不会自动改写。" % [int(_pending_save.day), int(_pending_save.cash), int(_pending_save.food)]
	elif _progress_blocked:
		$Interface/Screen/Title/Camp.text = "存档未加载；出击已锁定。原文件保留，可选有效备份或确认新游戏。"
	else:
		$Interface/Screen/Title/Camp.text += "\n武器 %d 件 / 已装备 %d / 闲置 %d" % [weapons.size(), loadout.size(), weapons.size() - loadout.size()]

	_refresh_presentation()


func _quit() -> void:
	request_exit("quit")


func open_pause_menu() -> void:
	if phase != Phase.EXPEDITION or expedition.phase == Expedition.Phase.FINISHED or pause_menu.root.visible:
		return
	_lock_menu_world()
	_menu_from_pause = true
	_configure_suspend_menu()
	pause_menu.show_pause(_menu_was_paused)


func _configure_suspend_menu() -> void:
	pause_menu.suspend_available = is_instance_valid(expedition)
	pause_menu.suspend_enabled = true
	if pause_menu.suspend_available:
		var preview: Dictionary = progress_session.preview_suspend(SortieSnapshot.capture(expedition))
		pause_menu.suspend_enabled = preview.error == OK
		if preview.error != OK:
			pause_menu.suspend_message = "安全暂存不可用；原记录保留。" + _suspend_problem(preview)


func _lock_menu_world() -> void:
	if phase != Phase.EXPEDITION or not is_instance_valid(expedition):
		return
	_menu_was_paused = expedition.is_paused
	if not expedition.is_paused:
		expedition.toggle_pause()
	expedition.set_process_unhandled_input(false)
	expedition._hud.view.set_process_unhandled_key_input(false)
	expedition.camera.menu_blocked = true
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()


func close_pause_menu() -> void:
	if phase == Phase.EXPEDITION and is_instance_valid(expedition) and expedition.suspend_sealed:
		var released: Dictionary = progress_session.release_frozen_world(SurvivalContracts.fingerprint(_frozen_world))
		if released.error != OK:
			pause_menu.suspend_message = "未保存成功，仍在原场景暂停；无法确认消费。" + _suspend_problem(released)
			pause_menu.show_pause(true)
			return
		expedition.suspend_sealed = false
		_frozen_world = {}
	pause_menu.suspend_message = ""
	pause_menu.close()
	_exit_target = ""
	_menu_from_pause = false
	if phase == Phase.EXPEDITION and is_instance_valid(expedition):
		expedition.set_process_unhandled_input(true)
		expedition._hud.view.set_process_unhandled_key_input(true)
		expedition.camera.menu_blocked = false
		if expedition.is_paused != _menu_was_paused:
			expedition.toggle_pause()


func suspend_sortie() -> void:
	_sortie.suspend_sortie()


func _suspend_problem(result: Dictionary) -> String:
	return _sortie._suspend_problem(result)


func request_exit(target: String) -> void:
	if _startup_pending:
		if target == "quit":
			_startup_exit_requested = true
			_startup_label.text = "正在核验旅程与资料…\n核验完成后将显示退出确认。"
		return
	# A native exclusive dialog owns Esc/close until its choice is resolved.
	if is_instance_valid(_facility_confirmation) and _facility_confirmation.visible:
		return
	if _new_game_confirmation.visible or _hunger_confirmation.visible or (is_instance_valid(_camp_leave_dialog) and _camp_leave_dialog.visible) or (is_instance_valid(training_panel) and training_panel.confirmation.visible):
		return
	if pause_menu.root.visible and pause_menu.confirming:
		return
	if not pause_menu.root.visible:
		_menu_from_pause = false
		_lock_menu_world()
	_exit_target = target
	var title: String = "退出游戏"
	var message: String = "已保存的营地进度保留。关闭不会开始新的行动。"
	var danger: String = "确认退出游戏"
	if _progress_blocked:
		title = "当前进度仍受阻"
		message = "现有记录与已确认阵亡保留。退出不会解除阻塞、生成结算或读取旧营地。\n" + _progress_message
	elif _progress_dirty:
		title = "营地变更尚未保存"
		message = "部分变更仅在当前内存中，退出可能丢失这些变更。\n请取消并重试保存；旧文件与已有记录保留。"
	elif phase == Phase.EXPEDITION:
		title = "这次行动尚未完成"
		message = "本次出击尚未完整结算；退出可能使原旅程无法继续。\n已确认阵亡不会因退出撤销；未结算物资与日期不会被擅自推算。\n正常回营：留在行动，发动巴士并集合所有存活成员。\n强杀、闪退与断电无法由此菜单拦截。"
		danger = "仍退出到首页（行动未结算）" if target == "home" else "仍关闭游戏（行动未结算）"
	elif phase == Phase.RESULT:
		if not _pending_settlement.is_empty():
			title = "完整结果已冻结"
			message = "重启后继续会复用已有冻结结果，只提交一次。\n本次关闭不重新计算资源、口粮、日期或阵亡。"
		elif _battle_meta.state == "FAILED":
			title = "旅程已结束"
			message = "全灭终局与阵亡记录已保存；重启不能复活或返回旧营地。"
	elif _requires_continue and progress_session.inspect().get("state") == "RECOVERY_READY":
		title = "已有完整冻结结果待继续"
		message = "已有 RESULT_READY 保留。重启后明确继续将复用原冻结结果并提交一次。\n关闭不会重新计算，也不会回退到出击前营地。"
	elif _requires_continue and _pending_save.is_empty() and not _progress_blocked:
		title = "本次出击已暂存"
		message = "下次使用同一隔离进度入口继续原战场；暂存已回读确认。\n这次尚未回营或结算，没有领取奖励、扣粮或推进日期。"
	var offer_suspend: bool = phase == Phase.EXPEDITION and is_instance_valid(expedition) and expedition.phase != Expedition.Phase.FINISHED and not _progress_blocked
	if offer_suspend:
		_configure_suspend_menu()
		offer_suspend = pause_menu.suspend_enabled
		message += "\n推荐安全暂存：写入并回读确认后才离开，不结算、不撤销阵亡。" if offer_suspend else "\n" + pause_menu.suspend_message
		if offer_suspend:
			danger = "危险退出到首页（不暂存）" if target == "home" else "危险关闭游戏（不暂存）"
	pause_menu.show_exit(title, message, danger, offer_suspend)


func _cancel_exit() -> void:
	_exit_target = ""
	if _menu_from_pause:
		_configure_suspend_menu()
		pause_menu.show_pause(_menu_was_paused)
	else:
		close_pause_menu()


func _confirm_exit() -> void:
	if _exit_target == "home":
		close_pause_menu()
		if pause_menu.root.visible:
			return
		audio.stop_world()
		_disconnect_sortie_events()
		_damage_gates.clear()
		$World.remove_child(expedition)
		expedition.queue_free()
		expedition = null
		phase = Phase.TITLE
		_camp_open = false
		_progress_blocked = true
		_requires_continue = false
		_progress_message = "上次行动中断，未形成完整结算。原旅程目前无法继续；已确认阵亡保留。不能返回旧营地。"
		_screen.show()
		_title.show()
		_update_camp()
		return
	print("BH_EXIT requested")
	audio.shutdown()
	get_tree().quit()


func open_sound_settings() -> void:
	if phase != Phase.TITLE or _settings_open():
		return
	if not is_instance_valid(sound_settings):
		sound_settings = SoundSettingsPanel.new()
		sound_settings.preferences = audio_preferences
		sound_settings.diagnostic = _settings_diagnostic
		sound_settings.saved.connect(func() -> void: _request_audio(&"ui_confirm"))
		sound_settings.closed.connect(_close_sound_settings)
		_screen.add_child(sound_settings)
	sound_settings.show()
	_title.hide()
	if is_instance_valid(_blue_hour_title_art):
		sound_settings.back_button.grab_focus()
	_request_audio(&"ui_confirm")


func _close_sound_settings() -> void:
	_title.show()
	_request_audio(&"ui_back")


func _settings_open() -> bool:
	if is_instance_valid(supply_panel) and supply_panel.visible:
		return true
	if is_instance_valid(_equipment_catalog) and _equipment_catalog.visible:
		return true
	if is_instance_valid(_facility_confirmation) and _facility_confirmation.visible:
		return true
	return (is_instance_valid(training_panel) and training_panel.visible) or (is_instance_valid(_camp_leave_dialog) and _camp_leave_dialog.visible) or (is_instance_valid(camp_scene) and camp_scene.info_visible()) or (is_instance_valid(sound_settings) and sound_settings.visible) or _new_game_confirmation.visible or (is_instance_valid(mission_select) and mission_select.visible) or (is_instance_valid(loadout_panel) and loadout_panel.visible) or (is_instance_valid(roster_panel) and roster_panel.visible) or (is_instance_valid(growth_panel) and growth_panel.visible)


func open_roster() -> void:
	if phase != Phase.TITLE or _settings_open() or _requires_continue or _progress_blocked:
		return
	if not is_instance_valid(roster_panel):
		roster_panel = RosterPanel.new()
		_screen.add_child(roster_panel)
		roster_panel.call_sign_requested.connect(rename_survivor)
		roster_panel.equipment_requested.connect(_roster_equipment)
		roster_panel.growth_requested.connect(open_growth)
		roster_panel.training_requested.connect(func(id: int) -> void:
			if _guard_camp_editor(func() -> void: _roster_training(id)): return
			_roster_training(id)
		)
		roster_panel.closed.connect(close_roster)
		roster_panel.navigation_requested.connect(_leave_roster_for)
	if SurvivorRoster.member(crew, roster_panel.selected_member_id).is_empty():
		roster_panel.selected_member_id = int(crew[0].id)
	_title.hide()
	roster_panel.show()
	roster_panel.death_equipment = progress_session.death_equipment(camp_snapshot())
	roster_panel.refresh(camp_snapshot())
	roster_panel.buttons_by_id[roster_panel.selected_member_id].grab_focus()
	_request_audio(&"ui_confirm")


func close_roster(discard_pending: bool = false) -> void:
	if not discard_pending and _guard_camp_editor(close_roster.bind(true)):
		return
	roster_panel.hide()
	_title.show()
	if is_instance_valid(camp_scene) and camp_scene.is_visible_in_tree():
		camp_scene.restore_focus()
	else:
		_roster_button.grab_focus()
	_request_audio(&"ui_back")


func _leave_roster_for(action: StringName, discard_pending: bool = false) -> void:
	if not discard_pending and _guard_camp_editor(_leave_roster_for.bind(action, true)):
		return
	close_roster(true)
	if action != &"camp":
		_camp_action(action, 0)


func open_growth(member_id: int, discard_pending: bool = false) -> void:
	if phase != Phase.TITLE or not is_instance_valid(roster_panel) or not roster_panel.visible or SurvivorRoster.member(crew,member_id).is_empty():
		return
	if not discard_pending and _guard_camp_editor(open_growth.bind(member_id, true)):
		return
	roster_panel.hide()
	if not is_instance_valid(growth_panel):
		growth_panel = GrowthPanel.new()
		_screen.add_child(growth_panel)
		growth_panel.closed.connect(close_growth)
	growth_panel.selected_member_id = member_id
	growth_panel.show()
	growth_panel.refresh(camp_snapshot())
	growth_panel.buttons_by_id[member_id].grab_focus()
	_request_audio(&"ui_confirm")


func close_growth() -> void:
	roster_panel.selected_member_id = growth_panel.selected_member_id
	growth_panel.hide()
	open_roster()


func rename_survivor(member_id: int, value: String) -> void:
	if phase != Phase.TITLE or not is_instance_valid(roster_panel) or not roster_panel.visible:
		return
	var problem: String = SurvivorRoster.name_problem(value)
	var entry: Dictionary = SurvivorRoster.member(crew, member_id)
	if entry.is_empty():
		problem = "队员身份无效。"
	if not problem.is_empty():
		roster_panel.refresh(camp_snapshot(), problem)
		return
	if entry.call_sign == value:
		roster_panel.refresh(camp_snapshot(), "呼号未改变，未重复保存。")
		return
	if _accept_transaction(progress_session.edit(camp_snapshot(),{"kind":"rename","member_id":member_id,"value":value}),true):
		_request_audio(&"ui_confirm")
	roster_panel.refresh(camp_snapshot(),_progress_message)
	return


func _roster_equipment(member_id: int, discard_pending: bool = false) -> void:
	if not discard_pending and _guard_camp_editor(_roster_equipment.bind(member_id, true)):
		return
	close_roster(true)
	_return_roster_member = member_id
	open_loadout()
	loadout_panel.select_for_member(member_id)


func open_loadout(workshop: bool = false) -> void:
	if phase != Phase.TITLE or _settings_open() or _requires_continue or _progress_blocked:
		return
	if not is_instance_valid(loadout_panel):
		loadout_panel = LoadoutPanel.new()
		_screen.add_child(loadout_panel)
		loadout_panel.equip_requested.connect(equip_weapon)
		loadout_panel.build_requested.connect(equip_build_item)
		loadout_panel.power_requested.connect(equip_power)
		loadout_panel.power_panel.second_requested.connect(equip_power.bind(1))
		loadout_panel.power_panel.third_requested.connect(equip_power.bind(2))
		loadout_panel.build_investment_requested.connect(invest_build)
		loadout_panel.power_panel.investment_requested.connect(invest_power)
		loadout_panel.power_panel.retry_requested.connect(retry_power_edit)
		loadout_panel.repair_requested.connect(repair_weapon)
		loadout_panel.workshop_requested.connect(install_workshop_mod)
		loadout_panel.economy_requested.connect(confirm_economy_edit)
		loadout_panel.closed.connect(close_loadout)
		loadout_panel.navigation_requested.connect(_leave_loadout_for)
	_title.hide()
	loadout_panel.show()
	loadout_panel.refresh(camp_snapshot())
	if workshop:
		loadout_panel.show_workshop()
	else:
		loadout_panel.show_inventory()
	_request_audio(&"ui_confirm")


func _leave_loadout_for(action: StringName) -> void:
	_return_roster_member = 0
	close_loadout()
	if not loadout_panel.visible and action != &"camp":
		_camp_action(action, 0)


func close_loadout() -> void:
	if _camp_commit_busy: return
	if not is_instance_valid(loadout_panel) or loadout_panel.confirmation.visible or loadout_panel.power_panel.confirmation.visible \
			or loadout_panel.workshop_confirmation.visible or loadout_panel.build_panel._confirmation.visible:
		return
	loadout_panel.hide()
	_title.show()
	if is_instance_valid(camp_scene) and camp_scene.is_visible_in_tree():
		camp_scene.restore_focus()
	else:
		_loadout_button.grab_focus()
	_request_audio(&"ui_back")
	if _return_roster_member > 0:
		roster_panel.selected_member_id = _return_roster_member
		_return_roster_member = 0
		open_roster()


func equip_weapon(member_id: int, identity: String) -> void:
	if _camp_commit_busy: return
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible or _progress_blocked:
		return
	var before: Dictionary = camp_snapshot()
	if not loadout_panel.matches_equip(before, member_id, identity):
		loadout_panel.refresh(before, "配装或持有人已变化，请重新预览。", _progress_dirty)
		return
	if EconomyBuildV1.enabled(before): await _begin_camp_commit(before, "weapon_equip")
	if _accept_transaction(progress_session.edit(before,{"kind":"equip","member_id":member_id,"value":identity}),true):
		_request_audio(&"ui_confirm")
	_camp_commit_busy = false
	_camp_commit_label = ""
	loadout_panel.refresh(camp_snapshot(),_progress_message,_progress_dirty)
	if _progress_dirty:
		loadout_panel.focus_retry()
	return


func repair_weapon(identity: String) -> void:
	if _camp_commit_busy: return
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible or _progress_blocked:
		return
	var before: Dictionary = camp_snapshot()
	if EconomyBuildV1.enabled(before): await _begin_camp_commit(before, "weapon_repair")
	if _accept_transaction(progress_session.edit(before,{"kind":"repair","member_id":0,"value":identity}),true):
		_request_audio(&"ui_confirm")
	_camp_commit_busy = false
	_camp_commit_label = ""
	loadout_panel.refresh(camp_snapshot(),_progress_message,_progress_dirty)
	if _progress_dirty:
		loadout_panel.focus_retry()
	return


func install_workshop_mod(identity: String, mod: String) -> void:
	if _camp_commit_busy: return
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible \
			or _progress_blocked:
		return
	var before: Dictionary = camp_snapshot()
	var issue: String = WorkshopV1.mod_problem(before, identity, mod)
	if not issue.is_empty():
		loadout_panel.refresh(before, issue, _progress_dirty)
		return
	var saved: bool = _accept_transaction(progress_session.edit(before, {"kind":mod, "member_id":0, "value":identity}), true)
	if saved:
		_request_audio(&"ui_confirm")
	loadout_panel.refresh(camp_snapshot(), "已安装%s · 使用工具箱 ×1、8 币" % WorkshopV1.name_for(mod) if saved else _progress_message, _progress_dirty)
	if _progress_dirty:
		loadout_panel.focus_retry()


func confirm_economy_edit(request: Dictionary) -> void:
	if _camp_commit_busy: return
	if phase != Phase.TITLE or _progress_blocked or _progress_dirty:
		return
	var before: Dictionary = camp_snapshot()
	var frozen_request: Dictionary = request.duplicate(true)
	await _begin_camp_commit(before,"economy")
	var saved: bool = _accept_transaction(progress_session.edit(before, frozen_request), true)
	_camp_commit_busy = false
	_camp_commit_label = ""
	if saved:
		_request_audio(&"ui_confirm")
	_update_camp()
	if is_instance_valid(loadout_panel) and loadout_panel.visible:
		loadout_panel.refresh(camp_snapshot(), _progress_message, _progress_dirty)
		if _progress_dirty:
			loadout_panel.focus_retry()
	_refresh_supply_panel()


func _request_audio(cue: StringName, world: bool = false) -> bool:
	var accepted: bool = audio.play_world(cue) if world else audio.play_ui(cue)
	audio_requested.emit(cue, world, accepted)
	return accepted


func _on_combat_feedback(event: Dictionary) -> void:
	_sortie._on_combat_feedback(event)


func _on_search_completed(_reward: int) -> void:
	_sortie._on_search_completed(_reward)


func _on_engine_started() -> void:
	_sortie._on_engine_started()


func _on_pause_changed(paused: bool) -> void:
	_sortie._on_pause_changed(paused)


func _on_help_changed(expanded: bool) -> void:
	_sortie._on_help_changed(expanded)


func _disconnect_sortie_events() -> void:
	_sortie._disconnect_sortie_events()


func _attach_damage_gates() -> void:
	_sortie._attach_damage_gates()


func camp_snapshot() -> Dictionary:
	return _session.camp_snapshot()


func continue_game() -> void:
	_session.continue_game()


func use_backup() -> void:
	_session.use_backup()


func save_camp() -> void:
	_session.save_camp()


func _accept_transaction(result: Dictionary, retryable: bool = false) -> bool:
	return _session._accept_transaction(result, retryable)


func _transaction_message(reason: String) -> String:
	return _session._transaction_message(reason)


func _present_finished_battle() -> void:
	_results._present_finished_battle()


func _show_battle_result(snapshot: Dictionary, durable: bool) -> void:
	_results._show_battle_result(snapshot, durable)


func _show_pump_victory(snapshot: Dictionary) -> void:
	_results._show_pump_victory(snapshot)


func _open_pump_details() -> void:
	_results._open_pump_details()


func _set_pump_victory_visible(enabled: bool) -> void:
	_results._set_pump_victory_visible(enabled)


func _hunger_policy_text() -> String:
	return _results._hunger_policy_text()


func _member_fate(snapshot: Dictionary, id: int) -> String:
	return _results._member_fate(snapshot, id)


func _request_battle_new_journey() -> void:
	_results._request_battle_new_journey()


func _apply_progress(data: Dictionary) -> void:
	_session._apply_progress(data)


func _has_progress_sources() -> bool:
	return _session._has_progress_sources()


func _show_startup_verification() -> void:
	_session._show_startup_verification()


func _create_progress_session() -> ProductionProgress:
	return _session._create_progress_session()


static func _inspect_startup(session: ProductionProgress) -> Dictionary:
	# One writer owns inspection and any legitimate catalog publication until join.
	var state: Dictionary = session.inspect()
	session.refresh_catalog()
	return state


func _setup_progress(preloaded_state: Dictionary = {}) -> void:
	_session._setup_progress(preloaded_state)


func _initialize_weapons(origin: String) -> void:
	_session._initialize_weapons(origin)


func _progress_button(label: String, y: float, action: Callable) -> Button:
	return _session._progress_button(label, y, action)


func _setup_presentation() -> void:
	_screen.theme = CampStyle.theme(_screen.theme)
	$Interface/Screen/Result/Scroll/Body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_camp_backdrop = CampBackdrop.new()
	_title.add_child(_camp_backdrop)
	_title.move_child(_camp_backdrop, 0)
	$Interface/Screen/Rule.hide()
	$Interface/Screen/Brand.text = "BLUE HOUR / 救援候选试运行 · PROJECT_TEMP"
	$Interface/Screen/Brand.add_theme_font_size_override("font_size", 16)
	CampStyle.place($Interface/Screen/Brand, Rect2(64,32,600,28))
	_screen.move_child(_status, _screen.get_child_count() - 1)
	_title.visibility_changed.connect(func() -> void: _status.visible = _title.visible and (_progress_dirty or _progress_blocked))
	_status.add_theme_font_size_override("font_size", 16)
	CampStyle.place(_status, Rect2(64,646,1152,68))
	_home_button = Button.new()
	_home_button.text = "开始旅程 →"
	_home_button.pressed.connect(_enter_camp)
	_title.add_child(_home_button)
	_home_return = Button.new()
	_home_return.text = "返回首页"
	_home_return.pressed.connect(func() -> void:
		_camp_open = false
		_refresh_presentation()
		_request_audio(&"ui_back")
	)
	_title.add_child(_home_return)
	_battle_new_button = Button.new()
	_battle_new_button.text = "开始新旅程…"
	CampStyle.place(_battle_new_button,Rect2(480,538,280,56))
	_battle_new_button.pressed.connect(_request_battle_new_journey)
	_result.add_child(_battle_new_button)
	_battle_new_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_battle_new_button.offset_left = 380
	_battle_new_button.offset_right = 660
	_battle_new_button.offset_top = -84
	_battle_new_button.offset_bottom = -28
	_battle_new_button.hide()
	_new_game_confirmation.canceled.connect(func() -> void:
		if _battle_meta.get("state") == "FAILED":
			_show_battle_result(camp_snapshot(),true))


func _enter_camp() -> void:
	if phase != Phase.TITLE or _settings_open() or _requires_continue or _progress_blocked:
		return
	if not run_save.has_files():
		reset_demo()
		return
	_camp_open = true
	_refresh_presentation()
	$Interface/Screen/Title/Start.grab_focus()
	_request_audio(&"ui_confirm")


func _refresh_presentation() -> void:
	if not is_instance_valid(_home_button):
		return
	if is_instance_valid(camp_scene) and camp_scene.visible:
		for child: Node in _title.get_children():
			if child is CanvasItem and child != camp_scene:
				child.show()
	var shown: Dictionary = _pending_save if _requires_continue else camp_snapshot()
	_camp_backdrop.show_roster(true, [] if _progress_blocked else shown.get("crew",[]),
		[] if _progress_blocked else shown.get("journey", {}).get("active_member_ids", []))
	var heading: Label = $Interface/Screen/Title/Heading
	var eyebrow: Label = $Interface/Screen/Title/Eyebrow
	var description: Label = $Interface/Screen/Title/Description
	var camp: Label = $Interface/Screen/Title/Camp
	var start: Button = $Interface/Screen/Title/Start
	var reset: Button = $Interface/Screen/Title/Reset
	var sound: Button = $Interface/Screen/Title/Sound
	var exit: Button = $Interface/Screen/Title/Quit
	heading.text = "蓝时驿站" if _camp_open else "蓝时归航"
	heading.add_theme_font_size_override("font_size", 48 if _camp_open else 64)
	eyebrow.text = "归来之后，准备下一次启程。" if _camp_open else "在天色暗下之前，找到归途。"
	eyebrow.add_theme_font_size_override("font_size", 16)
	description.text = "整备队伍 · 收拢补给 · 穿过旧街" if _camp_open else "穿过寂静的街口。带上同伴，一起回来。"
	description.add_theme_font_size_override("font_size", 18)
	CampStyle.place(eyebrow, Rect2(64,120 if _camp_open else 144,680,28))
	CampStyle.place(heading, Rect2(60,160 if _camp_open else 184,680,88))
	CampStyle.place(description, Rect2(64,252 if _camp_open else 280,680,32))
	CampStyle.place(camp, Rect2(64,304 if _camp_open else 338,850 if _camp_open else 500,120 if _camp_open else 88))
	camp.add_theme_font_size_override("font_size", 17)
	camp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not _camp_open and not _requires_continue and not _progress_blocked:
		camp.text = "第 %d 天 · %d 位同伴\n货币 %d · 食物 %d" % [day,crew.size(),cash,food]
	if _camp_open and not _requires_continue and not _progress_blocked:
		var daily: Dictionary = CampEconomy.rations(day, crew, food, camp_rules)
		camp.text = "第 %d 天  /  货币 %d  /  食物 %d  /  武器 %d件" % [day,cash,food,weapons.size()]
		for member_id: int in _battle_meta.get("active_member_ids", [1, 2]):
			var entry: Dictionary = SurvivorRoster.member(crew,member_id)
			camp.text += "\n%02d  %s  ·  生命 %.0f" % [member_id,entry.call_sign,float(entry.health)]
			camp.text += "/%.0f · Lv%d · %d XP" % [GrowthRules.maximum(entry),int(entry.growth.level),int(entry.growth.xp_total)]
			if entry.condition == "dead":
				camp.text += " · 已阵亡"
		camp.text += "\n今日口粮 %d · %s" % [int(daily.required),"库存足够" if daily.shortage == 0 else "缺口%d，建议前往超市" % int(daily.shortage)]
		if not last_day.is_empty() and last_day.food_shortage > 0:
			camp.text += " · 上餐缺口%d已结算" % int(last_day.food_shortage)
	_status.visible = _title.visible
	start.visible = _camp_open
	eyebrow.text = "同场救援试运行 · PROJECT_TEMP · 正式门禁未开放"
	if _battle_meta.get("seed") == "LOW_HP_4_FOOD_12":
		eyebrow.text += " · 演练种子4HP/12食物"
	if _battle_meta.get("state") == "FAILED":
		heading.text = "旅程已结束"
		start.visible = false
	_continue_button.text = "查看已结束旅程 →" if _pending_save.get("journey",{}).get("state") == "FAILED" else "继续隔离旅程 →"
	if _pending_save.get("journey", {}).get("state") != "FAILED":
		_continue_button.text = "继续生存旅程（测试） →"
	if _requires_continue and _pending_save.is_empty():
		_continue_button.text = "继续未完成的出击 →"
	_roster_button.visible = _camp_open
	_loadout_button.visible = _camp_open
	_home_return.visible = _camp_open
	_continue_button.visible = not _camp_open and _requires_continue
	_backup_button.visible = not _camp_open and _progress_blocked and not _backup_save.is_empty()
	_home_button.visible = not _camp_open and not _requires_continue and not _progress_blocked
	_home_button.text = "返回营地 →" if run_save.has_files() else "开始旅程 →"
	if not run_save.has_files():
		_home_button.text = "新生存旅程（测试） →"
	CampStyle.place(_continue_button, Rect2(64,446,320,56))
	CampStyle.place(_backup_button, Rect2(64,446,400,56))
	CampStyle.place(_home_button, Rect2(64,446,320,56))
	CampStyle.place(_retry_button, Rect2(840,556,356,44))
	reset.text = "新游戏…"
	reset.visible = run_save.has_files() or _progress_blocked
	reset.text = "新生存旅程…"
	CampStyle.place(reset, Rect2(260 if _camp_open else 64,556 if _camp_open else 514,180 if _camp_open else 320,44))
	CampStyle.place(sound, Rect2(64,556 if _camp_open else 574,180 if _camp_open else 148,44))
	CampStyle.place(exit, Rect2(456 if _camp_open else 224,556 if _camp_open else 574,140 if _camp_open else 160,44))
	CampStyle.place(_home_return, Rect2(612,556,180,44))
	start.text = "01  行动地图\n选择出击目标 →"
	_roster_button.text = "02  幸存者\n查看同伴与战绩 →"
	_loadout_button.text = "03  武器整备\n维修与出击配装 →"
	for index: int in range(3):
		var button: Button = [start, _roster_button, _loadout_button][index]
		CampStyle.place(button, Rect2(64 + index * 352,432,336,100))
		button.add_theme_font_size_override("font_size", 22)

	_refresh_playable_presentation()
	if is_instance_valid(_blue_hour_title_art):
		_refresh_blue_hour_title()
	_sync_camp_scene()


func _setup_camp_scene() -> void:
	_camp_leave_dialog = ConfirmationDialog.new()
	_camp_leave_dialog.title = "呼号尚未保存"
	_camp_leave_dialog.dialog_text = "当前呼号修改尚未确认。放弃修改并返回，还是继续编辑？"
	_camp_leave_dialog.ok_button_text = "放弃修改并继续"
	_camp_leave_dialog.cancel_button_text = "继续编辑"
	_camp_leave_dialog.confirmed.connect(func() -> void: _camp_leave_action.call_deferred())
	_camp_leave_dialog.canceled.connect(func() -> void: roster_panel.name_edit.grab_focus.call_deferred())
	_screen.add_child(_camp_leave_dialog)
	var path: String = "res://src/features/camp_scene/camp_scene.tscn"
	var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed == null or not packed.can_instantiate():
		_camp_scene_problem = "营地场景原型不可用；原营地功能保留。"
		return
	var candidate: Node = packed.instantiate()
	if not candidate is CampSceneView:
		candidate.free()
		_camp_scene_problem = "营地场景未通过检查；原营地功能保留。"
		return
	camp_scene = candidate as CampSceneView
	camp_scene.player_mode = true
	if camp_scene.player_mode:
		camp_scene.theme = CampStyle.blue_hour_theme(_screen.theme)
	_title.add_child(camp_scene)
	camp_scene.input_allowed = _camp_input_allowed
	camp_scene.action_requested.connect(_camp_action)
	camp_scene.facility_requested.connect(_offer_camp_facility)
	_facility_confirmation = ConfirmationDialog.new()
	_facility_confirmation.title = "确认营地建设"
	_facility_confirmation.ok_button_text = "建设并保存"
	_facility_confirmation.cancel_button_text = "暂不建设"
	_facility_confirmation.confirmed.connect(_confirm_camp_facility)
	_facility_confirmation.canceled.connect(func() -> void:
		_facility_choice = ""
		_economy_request = {}
		_restore_facility_focus.call_deferred())
	_screen.add_child(_facility_confirmation)
	camp_scene.hide()


func _offer_camp_facility(choice: String, upgrade: bool = false) -> void:
	if not _camp_input_allowed() or _progress_dirty or not CampSupplyPanel.NAMES.has(choice):
		return
	var before: Dictionary = camp_snapshot()
	if EconomyBuildV1.enabled(before):
		if not upgrade and EconomyBuildV1.level(before, choice) > 0:
			open_supplies()
			return
		var op: String = "upgrade_facility" if upgrade else "build"
		var quote: Dictionary = EconomyBuildV1.offer(before, op, choice)
		if not quote.available:
			_progress_message = quote.reason
			_refresh_supply_panel()
			return
		var identity: String = String(before.profile_id) + ":edit:" + RunSave.new_profile_id()
		_economy_request = EconomyBuildV1.request(before, op, choice, "", identity)
		_facility_confirmation.dialog_text = quote.summary
		_facility_confirmation.popup_centered(Vector2i(660, 260))
		return
	var offer: Dictionary = CampFacilities.upgrade_offer(before, choice) if upgrade else {}
	if (upgrade and not offer.available) or (not upgrade and not CampFacilities.can_build(before, choice)):
		return
	_facility_choice = choice
	_facility_upgrade = upgrade
	var label: String = CampSupplyPanel.UPGRADES[choice] if upgrade else CampSupplyPanel.NAMES[choice]
	var cost: int = int(offer.cost) if upgrade else CampFacilities.BUILD_COST
	var effect: String = CampSupplyPanel.UPGRADE_EFFECTS[choice] if upgrade else CampSupplyPanel.EFFECTS[choice]
	_facility_confirmation.ok_button_text = "确认投资并保存"
	_facility_confirmation.dialog_text = "%s · 花费 %d 币 · 保存后余 %d 币\n%s" % [label, cost, int(before.cash) - cost, effect]
	_facility_confirmation.popup_centered(Vector2i(630, 200))


func _confirm_camp_facility() -> void:
	if not _economy_request.is_empty():
		var request: Dictionary = _economy_request
		_economy_request = {}
		confirm_economy_edit(request)
		_restore_facility_focus.call_deferred()
		return
	var choice: String = _facility_choice
	_facility_choice = ""
	if phase != Phase.TITLE or not _camp_open or not CampSceneView.FACILITY_NAMES.has(choice):
		return
	var kind: String = "facility_upgrade" if _facility_upgrade else "facility"
	if _accept_transaction(progress_session.edit(camp_snapshot(), {"kind":kind, "member_id":0, "value":choice}), true):
		var label: String = CampSupplyPanel.UPGRADES[choice] if _facility_upgrade else CampSupplyPanel.NAMES[choice]
		_progress_message = "%s已建成，支出已保存。" % label
		_request_audio(&"ui_confirm")
	_update_camp()
	_refresh_supply_panel()
	_restore_facility_focus.call_deferred()


func _restore_facility_focus() -> void:
	if is_instance_valid(supply_panel) and supply_panel.visible:
		supply_panel.back_button.grab_focus()
	elif is_instance_valid(camp_scene):
		camp_scene.restore_focus()


func open_supplies() -> void:
	if phase != Phase.TITLE or _settings_open() or _requires_continue or _progress_blocked:
		return
	if not is_instance_valid(supply_panel):
		supply_panel = CampSupplyPanel.new()
		supply_panel.theme = CampStyle.blue_hour_theme(_screen.theme)
		_screen.add_child(supply_panel)
		supply_panel.investment_requested.connect(_offer_camp_facility)
		supply_panel.retry_requested.connect(_retry_facility)
		supply_panel.navigation_requested.connect(_leave_supplies_for)
	_title.hide()
	supply_panel.show()
	_refresh_supply_panel()
	supply_panel.back_button.grab_focus()
	_request_audio(&"ui_confirm")


func _refresh_supply_panel() -> void:
	if is_instance_valid(supply_panel) and supply_panel.visible:
		var base: Dictionary = camp_snapshot()
		supply_panel.refresh(base, CampEconomy.rations(day, base.crew, food, camp_rules), _progress_message, _progress_dirty)


func _retry_facility() -> void:
	if _camp_commit_busy: return
	if not _progress_dirty:
		return
	_accept_transaction(progress_session.retry(), true)
	_refresh_supply_panel()


func _leave_supplies_for(action: StringName) -> void:
	if _camp_commit_busy: return
	if _facility_confirmation.visible:
		return
	supply_panel.hide()
	_title.show()
	camp_scene.restore_focus()
	_request_audio(&"ui_back")
	if action != &"camp":
		_camp_action(action, 0)


func _sync_camp_scene() -> void:
	if not _camp_scene_problem.is_empty():
		_status.text = _progress_message + "\n" + _camp_scene_problem
		_status.visible = _title.visible
	if not is_instance_valid(camp_scene):
		return
	var eligible: bool = _camp_open and phase == Phase.TITLE and not _requires_continue and not _progress_blocked and _pending_settlement.is_empty() and _battle_meta.get("state", "ACTIVE") != "FAILED"
	camp_scene.visible = eligible
	if not camp_scene.visible:
		camp_scene.clear()
		return
	var data: Dictionary = camp_snapshot()
	camp_scene.refresh(data, CampEconomy.rations(day, crew, food, camp_rules), not $Interface/Screen/Title/Start.disabled, "可以选择出击目标" if not $Interface/Screen/Title/Start.disabled else ("当前旅程不能出击"), _progress_message)
	for child: Node in _title.get_children():
		if child is CanvasItem and child != camp_scene:
			child.hide()
	_status.hide()


func _camp_action(action: StringName, member_id: int) -> void:
	if not is_instance_valid(camp_scene) or not camp_scene.is_visible_in_tree() or _settings_open() or _hunger_confirmation.visible or _progress_blocked or _requires_continue or not _camp_input_allowed():
		return
	match action:
		&"bus": open_mission_select()
		&"crew":
			if member_id > 0 and is_instance_valid(roster_panel) and not SurvivorRoster.member(crew, member_id).is_empty():
				roster_panel.selected_member_id = member_id
			open_roster()
			if member_id > 0 and is_instance_valid(roster_panel):
				roster_panel.selected_member_id = member_id
				roster_panel.refresh(camp_snapshot())
				roster_panel.buttons_by_id[member_id].grab_focus()
		&"weapons", &"inventory": open_loadout()
		&"workshop": open_loadout(true)
		&"supplies":
			if camp_scene.player_mode:
				open_supplies()
			else:
				camp_scene.open_info(action)
		&"training":
			open_training()
		&"specialties": _show_equipment_catalog(progress_session.refresh_catalog())
		&"sound": open_sound_settings()
		&"home":
			_camp_open = false
			_refresh_presentation()
		&"quit": request_exit("quit")


func _guard_camp_editor(action: Callable) -> bool:
	if _camp_commit_busy: return true
	if not is_instance_valid(_camp_leave_dialog) or not is_instance_valid(roster_panel) or not roster_panel.visible or not roster_panel.name_edit.editable:
		return false
	var member: Dictionary = SurvivorRoster.member(crew, roster_panel.selected_member_id)
	if member.is_empty() or roster_panel.name_edit.text == member.call_sign:
		return false
	_camp_leave_action = action
	_camp_leave_dialog.popup_centered(Vector2i(620, 230))
	return true


func _camp_escape() -> bool:
	if _camp_commit_busy: return true
	if is_instance_valid(pause_menu) and pause_menu.root.visible:
		return false
	# LineEdit consumes ui_cancel before _unhandled_input, so this scope owns its back intent.
	if phase != Phase.TITLE or _new_game_confirmation.visible or _hunger_confirmation.visible or (is_instance_valid(_camp_leave_dialog) and _camp_leave_dialog.visible):
		return false
	if is_instance_valid(_facility_confirmation) and _facility_confirmation.visible:
		return false
	if is_instance_valid(supply_panel) and supply_panel.visible:
		_leave_supplies_for(&"camp")
	elif is_instance_valid(training_panel) and training_panel.visible:
		if training_panel.confirmation.visible:
			return false
		close_training()
	elif is_instance_valid(camp_scene) and camp_scene.is_visible_in_tree():
		if camp_scene.info_visible():
			camp_scene.close_info()
		else:
			camp_scene.restore_focus()
	elif is_instance_valid(growth_panel) and growth_panel.visible:
		close_growth()
	elif is_instance_valid(roster_panel) and roster_panel.visible:
		close_roster()
	elif is_instance_valid(loadout_panel) and loadout_panel.visible:
		if loadout_panel.confirmation.visible or loadout_panel.power_panel.confirmation.visible \
			or loadout_panel.workshop_confirmation.visible or loadout_panel.build_panel._confirmation.visible:
			return false
		if not loadout_panel.cancel_swap_preview() and not loadout_panel.back_from_workshop():
			close_loadout()
	elif mission_select.visible:
		close_mission_select()
	elif is_instance_valid(sound_settings) and sound_settings.visible:
		sound_settings.close_panel()
	else:
		return false
	return true


func _camp_input_allowed() -> bool:
	return not _camp_commit_busy and not (is_instance_valid(training_panel) and training_panel.visible) and phase == Phase.TITLE and not _new_game_confirmation.visible and not _hunger_confirmation.visible and not (is_instance_valid(pause_menu) and pause_menu.root.visible) and not (is_instance_valid(_camp_leave_dialog) and _camp_leave_dialog.visible)


func _roster_training(id: int) -> void:
	if not is_instance_valid(roster_panel) or not roster_panel.visible: return
	roster_panel.hide()
	open_training()
	if is_instance_valid(training_panel) and training_panel.visible:
		training_panel.selected_member_id=id
		training_panel.refresh(camp_snapshot())

func open_training() -> void:
	if phase!=Phase.TITLE or not _camp_open or _settings_open() or _requires_continue or _progress_blocked or not _pending_settlement.is_empty():
		return
	if not is_instance_valid(training_panel):
		training_panel = TrainingPanel.new()
		_screen.add_child(training_panel)
		training_panel.closed.connect(close_training)
		training_panel.confirmed.connect(confirm_training)
		training_panel.retry_requested.connect(retry_training)
	_title.hide()
	training_panel.show()
	training_panel.refresh(camp_snapshot())
	training_panel.back_button.grab_focus()
	_request_audio(&"ui_confirm")


func close_training() -> void:
	if not is_instance_valid(training_panel) or training_panel.confirmation.visible:
		return
	training_panel.hide()
	_title.show()
	_update_camp()
	if is_instance_valid(camp_scene) and camp_scene.visible:
		camp_scene.hotspots[&"training"].grab_focus()


func confirm_training(request: Dictionary) -> void:
	if not request.get("kind") is String or request.kind!="train_trait":
		return
	if phase!=Phase.TITLE or not _camp_open or not is_instance_valid(training_panel) or not training_panel.visible or _requires_continue or _progress_blocked or not _pending_settlement.is_empty():
		return
	var accepted: bool = _accept_transaction(progress_session.edit(camp_snapshot(),request),true)
	training_panel.refresh(camp_snapshot(),"训练已保存。粮食与本人Trait已同时确认；下次出击按新等级生效。" if accepted else _progress_message,_progress_blocked)
	if accepted:
		_request_audio(&"ui_confirm")


func retry_training() -> void:
	if not is_instance_valid(training_panel) or not training_panel.visible or not _progress_dirty:
		return
	var accepted: bool = _accept_transaction(progress_session.retry(),true)
	training_panel.refresh(camp_snapshot(),"原训练已保存确认；没有再次扣粮或增加进度。" if accepted else _progress_message,not accepted)


func _refresh_playable_presentation() -> void:
	$Interface/Screen/Brand.text = "BLUE HOUR · 开发试玩版"
	$Interface/Screen/Title/Eyebrow.text = "开发试玩版 · 整备队伍，再次启程。" if _camp_open else "开发试玩版 · 独立进度 · 阵亡与缺粮损失会保存"
	_home_button.text = "进入营地 →" if run_save.has_files() else "开始试玩 →"
	_continue_button.text = "继续试玩 →" if not _pending_save.is_empty() else "继续出击 →"
	if _pending_save.get("journey",{}).get("state")=="FAILED" or CampaignState.ended(_pending_save): _continue_button.text = "查看旅程记录 →"
	$Interface/Screen/Title/Reset.text = "新的试玩旅程…"
	if _battle_meta.has("campaign") and not _requires_continue:
		var display: Dictionary=CampaignRules.display(_battle_meta.campaign)
		$Interface/Screen/Title/Eyebrow.text=display.title+" · "+display.progress
	$Interface/Screen/Title/Sound.text = "设置"
	if _requires_continue and not _pending_save.is_empty():
		$Interface/Screen/Title/Camp.text = "已保存：第%d天 · 货币%d · 食物%d\n继续同一旅程，或明确开始新的试玩。" % [_pending_save.day,_pending_save.cash,_pending_save.food]


func _setup_blue_hour_title() -> void:
	_title.theme = CampStyle.blue_hour_theme(_screen.theme)
	_blue_hour_title_art = CampStyle.blue_hour_background(BLUE_HOUR_TITLE_ART)
	_blue_hour_title_art.name = "BlueHourTitleArt"
	_title.add_child(_blue_hour_title_art)
	_title.move_child(_blue_hour_title_art, 0)
	_catalog_button = Button.new()
	_catalog_button.text = "专精 / 图鉴"
	_catalog_button.pressed.connect(func() -> void: _show_equipment_catalog(progress_session.refresh_catalog()))
	_title.add_child(_catalog_button)
	var title_font: SystemFont = SystemFont.new()
	title_font.font_names = PackedStringArray(["STZhongsong", "SimSun", "Noto Serif CJK SC", "Microsoft YaHei"])
	title_font.font_weight = 700
	$Interface/Screen/Title/Heading.add_theme_font_override("font", title_font)
	var english_font: FontVariation = FontVariation.new()
	english_font.base_font = ThemeDB.fallback_font
	english_font.spacing_glyph = 7
	$Interface/Screen/Title/Eyebrow.add_theme_font_override("font", english_font)
	for button: Button in _blue_hour_title_buttons():
		_style_blue_hour_title_button(button)
		button.focus_entered.connect(_remember_blue_hour_title_focus.bind(button))
	_title.visibility_changed.connect(func() -> void: _restore_blue_hour_title_focus.call_deferred())
	_new_game_confirmation.canceled.connect(func() -> void: _restore_blue_hour_title_focus.call_deferred())
	_hunger_confirmation.canceled.connect(func() -> void: _restore_blue_hour_title_focus.call_deferred())


func _refresh_blue_hour_title() -> void:
	_blue_hour_title_art.visible = not _camp_open
	_camp_backdrop.visible = _camp_open
	$Interface/Screen/Brand.hide()
	if _camp_open:
		_catalog_button.hide()
		CampStyle.place(_status, Rect2(64, 646, 1152, 68))
		return
	var heading: Label = $Interface/Screen/Title/Heading
	var english: Label = $Interface/Screen/Title/Eyebrow
	var camp: Label = $Interface/Screen/Title/Camp
	var reset: Button = $Interface/Screen/Title/Reset
	var sound: Button = $Interface/Screen/Title/Sound
	var exit: Button = $Interface/Screen/Title/Quit
	heading.text = "蓝时归航"
	heading.add_theme_font_size_override("font_size", 76)
	heading.add_theme_color_override("font_color", Color("f3e7d1"))
	CampStyle.place(heading, Rect2(90, 144, 426, 94))
	english.text = "BLUE HOUR"
	english.add_theme_color_override("font_color", Color("f3e7d1"))
	CampStyle.place(english, Rect2(99, 242, 334, 28))
	$Interface/Screen/Title/Description.hide()
	var live_camp: bool = _home_button.visible and run_save.has_files()
	_continue_button.visible = not live_camp
	_continue_button.disabled = not _requires_continue or _progress_blocked
	if _pending_save.get("journey", {}).get("state") != "FAILED" and not CampaignState.ended(_pending_save):
		_continue_button.text = "继续出击" if _requires_continue and _pending_save.is_empty() else "继续旅程"
	_home_button.text = "继续旅程" if live_camp else "新旅程"
	reset.text = "新旅程"
	reset.visible = not _home_button.visible or live_camp
	sound.text = "设置"
	exit.text = "退出游戏"
	CampStyle.place(_continue_button, Rect2(91, 316, 276, 44))
	CampStyle.place(_home_button, Rect2(91, 316 if live_camp else 367, 276, 44))
	CampStyle.place(reset, Rect2(91, 367, 276, 44))
	CampStyle.place(sound, Rect2(91, 418, 126, 44))
	var catalog_ready: bool = progress_session.catalog_state().get("error", FAILED) == OK
	_catalog_button.text = "专精 / 图鉴" if catalog_ready else "专精待同步"
	_catalog_button.tooltip_text = "" if catalog_ready else "打开专精资料，重试读取与同步"
	_catalog_button.show()
	CampStyle.place(_catalog_button, Rect2(223, 418, 144, 44))
	CampStyle.place(exit, Rect2(91, 469, 276, 44))
	CampStyle.place(_backup_button, Rect2(91, 524, 365, 38))
	CampStyle.place(_retry_button, Rect2(91, 569 if _backup_button.visible else 524, 365, 38))
	camp.visible = _requires_continue and not _pending_save.is_empty() and not _progress_blocked
	camp.add_theme_color_override("font_color", Color("cad7d6"))
	CampStyle.place(camp, Rect2(103, 532, 426, 68))
	CampStyle.place(_status, Rect2(103, 633, 490, 74))
	_status.add_theme_color_override("font_color", CampStyle.AMBER if _progress_blocked else Color("c5d3d1"))
	var focusable: Array[Button] = []
	for button: Button in _blue_hour_title_buttons():
		if button.visible and not button.disabled:
			focusable.append(button)
	for index: int in range(focusable.size()):
		focusable[index].focus_next = focusable[(index + 1) % focusable.size()].get_path()
		focusable[index].focus_previous = focusable[(index + focusable.size() - 1) % focusable.size()].get_path()
	_restore_blue_hour_title_focus.call_deferred()


func _blue_hour_title_buttons() -> Array[Button]:
	return [_continue_button, _home_button, $Interface/Screen/Title/Reset, $Interface/Screen/Title/Sound,
		_catalog_button, $Interface/Screen/Title/Quit, _backup_button, _retry_button]


func _style_blue_hour_title_button(button: Button) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", CampStyle.box(Color(0.06, 0.14, 0.2, 0.40), Color.TRANSPARENT, 8))
	button.add_theme_stylebox_override("hover", CampStyle.box(Color(0.10, 0.24, 0.33, 0.92), CampStyle.TEAL, 8))
	button.add_theme_stylebox_override("pressed", CampStyle.box(Color(0.10, 0.17, 0.22, 0.96), CampStyle.AMBER, 8))
	button.add_theme_stylebox_override("disabled", CampStyle.box(Color(0.06, 0.14, 0.2, 0.35), Color.TRANSPARENT, 8))
	var focus: StyleBoxFlat = CampStyle.box(Color.TRANSPARENT, CampStyle.AMBER, 0)
	focus.border_width_left = 4
	button.add_theme_stylebox_override("focus", focus)


func _remember_blue_hour_title_focus(button: Button) -> void:
	if not _camp_open:
		_blue_hour_title_focus = button


func _restore_blue_hour_title_focus() -> void:
	if _camp_open or phase != Phase.TITLE or not _title.is_visible_in_tree() or _settings_open():
		return
	if is_instance_valid(_blue_hour_title_focus) and _blue_hour_title_focus.is_visible_in_tree() and not _blue_hour_title_focus.disabled:
		_blue_hour_title_focus.grab_focus()
		return
	for button: Button in _blue_hour_title_buttons():
		if button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()
			return


func _playable_result_text(snapshot: Dictionary, durable: bool) -> String:
	return _results._playable_result_text(snapshot, durable)


func _catalog_result_notice(snapshot: Dictionary) -> String:
	return _results._catalog_result_notice(snapshot)


func _show_equipment_catalog(state: Dictionary) -> void:
	if _equipment_catalog == null:
		_equipment_catalog = EquipmentCatalog.new()
		_equipment_catalog.theme = CampStyle.blue_hour_theme(_screen.theme)
		_screen.add_child(_equipment_catalog)
		_equipment_catalog.closed.connect(_close_equipment_catalog)
		_equipment_catalog.retry_requested.connect(func() -> void:
			_equipment_catalog.present(progress_session.refresh_catalog()))
	_title.hide()
	_result.hide()
	_equipment_catalog.show()
	_equipment_catalog.present(state)


func _close_equipment_catalog() -> void:
	_equipment_catalog.hide()
	if phase == Phase.TITLE:
		_title.show()
		if _camp_open:
			camp_scene.restore_focus()
		else:
			_refresh_blue_hour_title()
			_catalog_button.grab_focus()
	elif phase == Phase.RESULT:
		_show_battle_result(camp_snapshot(), true)
		if _pump_victory != null and _pump_victory.visible:
			_pump_victory.new_journey_button.grab_focus()
		else:
			_battle_new_button.grab_focus()


func equip_build_item(slot: int, item: String) -> void:
	if _camp_commit_busy: return
	if phase!=Phase.TITLE or not loadout_panel.visible or _progress_blocked or not BuildState.enabled(camp_snapshot()): return
	var before: Dictionary = camp_snapshot()
	if EconomyBuildV1.enabled(before): await _begin_camp_commit(before, "build_slot")
	var saved: bool=_accept_transaction(progress_session.edit(before,{"kind":"build_slot","member_id":slot,"value":item}),true)
	_camp_commit_busy = false
	_camp_commit_label = ""
	loadout_panel.refresh(camp_snapshot(),"本局道具配装已保存；下一行动生效。" if saved else _progress_message,_progress_dirty)
	if _progress_dirty:
		loadout_panel.focus_retry()
	if not saved:
		var build: Dictionary = camp_snapshot().journey.build
		loadout_panel.build_panel.present(build.owned, build.slots, false, false,
			build.get("opening", {}).get("plan", ""), BuildState.pool(camp_snapshot()), camp_snapshot())

func equip_power(id: String, slot: int = 0) -> void:
	var camp: Dictionary = camp_snapshot()
	if not PowerState.enabled(camp):
		return
	var kind: String = "power_equip" if PowerState.progression(camp.journey.build.powers) else "power_slot"
	_edit_power({"kind":kind,"member_id":slot,"value":id}, "特殊能力装配已保存；下次出击生效。")


func invest_power(choice: String) -> void:
	_edit_power({"kind":"power_invest","member_id":0,"value":choice}, "能力投资已保存；余额与效果已更新。")


func invest_build(choice: String) -> void:
	_edit_power({"kind":"build_invest","member_id":0,"value":choice}, "道具投资已保存；余额与效果已更新。")


func _edit_power(request: Dictionary, success: String) -> void:
	if _camp_commit_busy: return
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible or _progress_blocked:
		return
	var before: Dictionary = camp_snapshot()
	var frozen_request: Dictionary = request.duplicate(true)
	if EconomyBuildV1.enabled(before): await _begin_camp_commit(before,String(request.kind))
	var saved: bool = _accept_transaction(progress_session.edit(before,frozen_request),true)
	_camp_commit_busy = false
	_camp_commit_label = ""
	loadout_panel.refresh(camp_snapshot(),success if saved else _progress_message,_progress_dirty)
	if _progress_dirty:
		loadout_panel.focus_retry()


func retry_power_edit() -> void:
	if _camp_commit_busy: return
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible or not _progress_dirty:
		return
	var before: Dictionary = camp_snapshot()
	if EconomyBuildV1.enabled(before): await _begin_camp_commit(before, "retry_edit")
	var saved: bool = _accept_transaction(progress_session.retry(),true)
	_camp_commit_busy = false
	_camp_commit_label = ""
	loadout_panel.refresh(camp_snapshot(),"本次整备已保存；余额与状态已更新。" if saved else _progress_message,not saved)
