extends Node
## Owns session/camp and one sortie; settlement is accepted once per sortie.

signal audio_requested(cue: StringName, world: bool, accepted: bool)

enum Phase {
	TITLE,
	VALIDATION,
	EXPEDITION,
	RESULT,
}

const ValidationScene: PackedScene = preload("res://src/features/validation/validation.tscn")
const ExpeditionScene: PackedScene = preload("res://src/features/expedition/expedition.tscn")

var phase: Phase = Phase.TITLE
var _validation: Node2D
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
var _developer_menu: bool = false
var audio_settings_path: String = "user://settings/audio.json"
var audio_preferences: AudioPreferences
var audio: B1AudioService
var sound_settings: SoundSettingsPanel
var _settings_diagnostic: String = ""
var progress_path: String = "user://saves/run.json"
var run_save: RunSave
var profile_id: String = ""
var last_settlement_id: String = ""
var _active_sortie_id: String = ""
var _finish_callback: Callable
var _pending_save: Dictionary = {}
var _pending_settlement: Dictionary = {}
var _migration_notice: String = ""
var _backup_migration_notice: String = ""
var _backup_save: Dictionary = {}
var _requires_continue: bool = false
var _progress_blocked: bool = false
var _progress_dirty: bool = false
var _allow_invalid_replacement: bool = false
var _progress_message: String = ""
var _continue_button: Button
var _backup_button: Button
var _retry_button: Button
var _new_game_confirmation: ConfirmationDialog

@onready var _title: Control = $Interface/Screen/Title
@onready var _status: Label = $Interface/Screen/Status
@onready var _back: Button = $Interface/Screen/Back
@onready var _screen: Control = $Interface/Screen
@onready var _result: Control = $Interface/Screen/Result


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-audio-settings="):
			audio_settings_path = argument.trim_prefix("--bh-audio-settings=")
		if argument.begins_with("--bh-progress="):
			progress_path = argument.trim_prefix("--bh-progress=")
	_setup_progress()
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
	_screen.add_child(mission_select)
	mission_select.hide()
	mission_select.selected.connect(_select_mission)
	mission_select.cancelled.connect(close_mission_select)
	$Interface/Screen/Title/Practice.pressed.connect(open_practice)
	$Interface/Screen/Title/Probe.pressed.connect(open_validation)
	$Interface/Screen/Title/Reset.pressed.connect(reset_demo)
	$Interface/Screen/Title/Quit.pressed.connect(_quit)
	$Interface/Screen/Title/Sound.pressed.connect(open_sound_settings)
	_loadout_button = _progress_button("营地武器 / 配装 →", 600.0, open_loadout)
	_loadout_button.position.x = 100.0
	_loadout_button.size = Vector2(448, 40)
	_roster_button = _progress_button("营地幸存者 →", 600.0, open_roster)
	_roster_button.position.x = 572.0
	_roster_button.size = Vector2(274, 40)
	$Interface/Screen/Result/Continue.pressed.connect(return_to_title)
	_back.pressed.connect(return_to_title)
	_setup_presentation()
	_update_camp()
	print("BH_READY phase=TITLE renderer=%s" % RenderingServer.get_current_rendering_method())
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--verify-m5combat03="):
			var proof: M5Combat03Playtest = M5Combat03Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m5combat03=")
			add_child(proof)
			return
		if argument.begins_with("--verify-m5combat02="):
			var proof: M5Combat02Playtest = M5Combat02Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m5combat02=")
			add_child(proof)
			return
		if argument.begins_with("--verify-m5ux01="):
			var proof: M5UX01Playtest = M5UX01Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m5ux01=")
			add_child(proof)
			return
		if argument.begins_with("--verify-m503="):
			var proof: M503Playtest = M503Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m503=")
			add_child(proof)
			return
		if argument.begins_with("--verify-m502="):
			var proof: M502Playtest = M502Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m502=")
			add_child(proof)
			return
		if argument.begins_with("--verify-m501="):
			var proof: M501Playtest = M501Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m501=")
			add_child(proof)
			break
		if argument.begins_with("--verify-m403="):
			var proof: M403Playtest = M403Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m403=")
			add_child(proof)
			break
		if argument.begins_with("--verify-m402="):
			var proof: M402Playtest = M402Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m402=")
			add_child(proof)
			break
		if argument.begins_with("--verify-m401="):
			var proof: M401Playtest = M401Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m401=")
			add_child(proof)
			break
		if argument.begins_with("--verify-m304="):
			var proof: M304Playtest = M304Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m304=")
			add_child(proof)
			break
		if argument.begins_with("--verify-m303="):
			var proof: M303Playtest = M303Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m303=")
			add_child(proof)
			break
		if argument.begins_with("--verify-m302="):
			var proof: M302Playtest = M302Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m302=")
			add_child(proof)
			break
		if argument.begins_with("--verify-m301="):
			var proof: M301Playtest = M301Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m301=")
			add_child(proof)
			break
		if argument.begins_with("--verify-m202="):
			var proof: M202Playtest = M202Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m202=")
			add_child(proof)
			break
		if argument.begins_with("--verify-p03="):
			var proof: P03Playtest = P03Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-p03=")
			add_child(proof)
			break
		if argument.begins_with("--verify-m201="):
			var proof: M201Playtest = M201Playtest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-m201=")
			add_child(proof)
			break


func _exit_tree() -> void:
	if is_instance_valid(audio):
		audio.shutdown()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("return_to_title") and is_instance_valid(growth_panel) and growth_panel.visible:
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
	elif event.is_action_pressed("return_to_title") and phase == Phase.VALIDATION:
		return_to_title()
		get_viewport().set_input_as_handled()


func open_validation() -> void:
	if phase != Phase.TITLE or _settings_open():
		return
	_validation = ValidationScene.instantiate() as Node2D
	$World.add_child(_validation)
	phase = Phase.VALIDATION
	_request_audio(&"ui_confirm")
	_title.hide()
	_back.show()
	_status.text = "验证场景 / 点击网格放置标记 · Esc 返回"
	print("BH_PHASE VALIDATION")


func return_to_title() -> void:
	if phase != Phase.VALIDATION and phase != Phase.RESULT:
		return
	audio.stop_world()
	_disconnect_sortie_events()
	if phase == Phase.RESULT and not _pending_settlement.is_empty():
		if _pending_settlement.last_settlement_id != last_settlement_id:
			_apply_progress(_pending_settlement)
			_progress_dirty = true
			print("BH_SETTLED %s" % JSON.stringify(last_day))
		_pending_settlement = {}
	if _validation != null:
		$World.remove_child(_validation)
		_validation.queue_free()
		_validation = null
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
	print("BH_PHASE TITLE")


func open_mission_select() -> void:
	if phase != Phase.TITLE or _settings_open() or $Interface/Screen/Title/Start.disabled:
		return
	_title.hide()
	mission_select.show()
	mission_select.choices[0].grab_focus()
	_request_audio(&"ui_confirm")


func close_mission_select() -> void:
	mission_select.hide()
	_title.show()
	_request_audio(&"ui_back")


func _select_mission(supply: MissionSupply) -> void:
	selected_supply = supply
	mission_select.hide()
	open_expedition()


func open_expedition() -> void:
	_open_sortie(false)


func open_practice() -> void:
	_open_sortie(true)


func _open_sortie(practice: bool) -> void:
	if phase != Phase.TITLE or _settings_open():
		return
	if not practice and (crew_health[0] <= 0.0 or crew_health[1] <= 0.0):
		return
	if not practice and (_requires_continue or _progress_blocked):
		return
	expedition = ExpeditionScene.instantiate() as Expedition
	expedition.is_practice = practice
	expedition.ui_theme = _screen.theme
	expedition.initial_cash = cash
	expedition.initial_food = food
	expedition.camp_rules = camp_rules
	expedition.supply = selected_supply
	expedition.mission_title = selected_supply.layout.display_name
	expedition.day = day
	expedition.starting_health = crew_health.duplicate()
	expedition.crew_snapshot = crew.duplicate(true)
	expedition.loadout_snapshot = WeaponInventory.snapshot(camp_snapshot())
	if not practice and "--bh-threat-rehearsal" in OS.get_cmdline_user_args():
		expedition.threat_rehearsal = true
		expedition.tuning.daylight_seconds = ThreatRules.REHEARSAL_DAYLIGHT
		expedition.mission_title += " · 短时压力演练"
	if practice:
		expedition.starting_health = [200.0, 200.0]
		for argument: String in OS.get_cmdline_user_args():
			if argument in ["--bh-los-map=repair_lane", "--bh-los-map=market_loop"]:
				expedition.supply = preload("res://src/features/camp/scavenge.tres") if argument.ends_with("repair_lane") else preload("res://src/features/camp/supermarket.tres")
				expedition.los_practice = true
				expedition.mission_title = expedition.supply.layout.display_name + " · 项目验收演练"
			if argument == "--bh-los-case=range":
				expedition.los_range_case = true
	audio.stop_world()
	audio.set_world_paused(false)
	_active_sortie_id = "practice" if practice else "%s:%d" % [profile_id, settled_sorties + 1]
	expedition.sortie_id = _active_sortie_id
	_pending_settlement = {}
	_finish_callback = _on_expedition_finished.bind(_active_sortie_id)
	expedition.finished.connect(_finish_callback)
	expedition.combat_feedback.connect(_on_combat_feedback)
	expedition.search_completed.connect(_on_search_completed)
	expedition.engine_started.connect(_on_engine_started)
	expedition.pause_changed.connect(_on_pause_changed)
	expedition.help_changed.connect(_on_help_changed)
	phase = Phase.EXPEDITION
	$World.add_child(expedition)
	_screen.hide()
	_request_audio(&"ui_confirm")


func reset_demo() -> void:
	if phase != Phase.TITLE or _settings_open():
		return
	if run_save.has_files() or _progress_dirty or settled_sorties > 0:
		var preview: Dictionary = _pending_save if _requires_continue else {"day":day,"cash":cash}
		_new_game_confirmation.dialog_text = "开始新游戏？\n当前进度：第 %d 天，货币 %d。\n旧档暂时保留；新游戏首次回营或确认营地配装后才替换，并保留有效备份。\n异常文件将原字节归档，不会直接删除。" % [int(preview.day), int(preview.cash)]
		_new_game_confirmation.popup_centered(Vector2i(650, 240))
		return
	_new_game()


func _new_game() -> void:
	_camp_open = true
	cash = 53
	day = 2
	crew = SurvivorRoster.new_crew()
	settled_sorties = 0
	food = camp_rules.initial_food
	last_day = {}
	_pending_settlement = {}
	_migration_notice = ""
	profile_id = RunSave.new_profile_id()
	_initialize_weapons("initial")
	last_settlement_id = ""
	_pending_save.clear()
	_backup_save.clear()
	_requires_continue = false
	_progress_blocked = false
	_progress_dirty = false
	_allow_invalid_replacement = true
	_progress_message = "新游戏尚未保存；正式回营或确认营地配装后保存。"
	_update_camp()
	_request_audio(&"ui_confirm")


func _on_expedition_finished(report: Dictionary, sortie_id: String) -> void:
	if phase != Phase.EXPEDITION or sortie_id != _active_sortie_id or sortie_id == last_settlement_id:
		return
	audio.stop_world()
	_disconnect_sortie_events()
	phase = Phase.RESULT
	_screen.show()
	_title.hide()
	_result.show()
	if expedition.is_practice:
		_status.text = "交火练习不改变营地进度。"
		$Interface/Screen/Result/Heading.text = "交火练习结束"
		$Interface/Screen/Result/Body.text = "队员生命 %d / %d\n击退 %d\n\n移动、命中、受击和击败均来自实际战斗。\n营地的天数、资源和队员生命保持不变。" % [ceili(report["health"][0]), ceili(report["health"][1]), report["kills"]]
		return
	_pending_settlement = CampEconomy.preview(camp_snapshot(), report, sortie_id, camp_rules)
	if _pending_settlement.is_empty():
		_status.text = "结算数据无效，营地与旧档未改变。"
		$Interface/Screen/Result/Heading.text = "结算未应用"
		$Interface/Screen/Result/Body.text = "请返回营地；此次不会修改资源或日期。"
		return
	var ledger: Dictionary = _pending_settlement.last_day
	_status.text = "归航结算预览；返回营地时只入库、扣粮一次并保存。此时退出不改变上次营地。"
	$Interface/Screen/Result/Heading.text = "平安归航" if report["evacuated"] else "队伍失去行动能力"
	$Interface/Screen/Result/Body.text = (
		"第 %d 日归航 · 返回营地后进入第 %d 天\n\n货币 %d + 带回 %d = %d\n食物 %d + 带回 %d - 口粮 %d = %d\n今日需求 %d · 实耗 %d · 缺口 %d\n%s\n\n队员生命 %d / %d · 搜集 %d 处 · 击退 %d"
		% [day, int(_pending_settlement.day), cash, ledger.cash_gained, ledger.cash_after,
		food, ledger.food_stored, ledger.food_consumed, ledger.food_after,
		ledger.food_required, ledger.food_consumed, ledger.food_shortage,
		HungerOutcome.description(ledger),
		ceili(report.health[0]), ceili(report.health[1]), int(report.get("sites_searched", 1 if report.get("searched", false) else 0)), report.kills]
	)
	if ledger.food_overflow > 0:
		$Interface/Screen/Result/Body.text += "\n库存上限：另有 %d 食物未入库。" % ledger.food_overflow
	var reward_items: Array = report.get("weapons", [])
	if not reward_items.is_empty() and report.evacuated:
		$Interface/Screen/Result/Body.text += "\n带回武器：损坏长管步枪 · 回营后可维修整备"


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
	$Interface/Screen/Title/Start.disabled = _requires_continue or _progress_blocked or crew_health[0] <= 0.0 or crew_health[1] <= 0.0
	_loadout_button.disabled = _requires_continue or _progress_blocked
	_roster_button.disabled = _requires_continue or _progress_blocked
	_continue_button.visible = _requires_continue
	_backup_button.visible = _progress_blocked and not _backup_save.is_empty()
	_retry_button.visible = _progress_dirty
	if _requires_continue:
		$Interface/Screen/Title/Camp.text = "已保存：第 %d 天 / 货币 %d / 食物 %d\n点击“继续游戏”恢复营地；旧档不会自动改写。\n%s" % [int(_pending_save.day), int(_pending_save.cash), int(_pending_save.food), _migration_notice]
	elif _progress_blocked:
		$Interface/Screen/Title/Camp.text = "存档未加载；出击已锁定。原文件保留，可选有效备份或确认新游戏。"
	else:
		$Interface/Screen/Title/Camp.text += "\n武器 %d 件 / 已装备 %d / 闲置 %d" % [weapons.size(), loadout.size(), weapons.size() - loadout.size()]

	_refresh_presentation()


func _quit() -> void:
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
	_request_audio(&"ui_confirm")


func _close_sound_settings() -> void:
	_title.show()
	_request_audio(&"ui_back")


func _settings_open() -> bool:
	return (is_instance_valid(sound_settings) and sound_settings.visible) or _new_game_confirmation.visible or (is_instance_valid(mission_select) and mission_select.visible) or (is_instance_valid(loadout_panel) and loadout_panel.visible) or (is_instance_valid(roster_panel) and roster_panel.visible) or (is_instance_valid(growth_panel) and growth_panel.visible)


func open_roster() -> void:
	if phase != Phase.TITLE or _settings_open() or _requires_continue or _progress_blocked:
		return
	if not is_instance_valid(roster_panel):
		roster_panel = RosterPanel.new()
		_screen.add_child(roster_panel)
		roster_panel.call_sign_requested.connect(rename_survivor)
		roster_panel.equipment_requested.connect(_roster_equipment)
		roster_panel.growth_requested.connect(open_growth)
		roster_panel.closed.connect(close_roster)
	_title.hide()
	roster_panel.show()
	roster_panel.refresh(camp_snapshot())
	roster_panel.member_buttons[roster_panel.selected_member_id - 1].grab_focus()
	_request_audio(&"ui_confirm")


func close_roster() -> void:
	roster_panel.hide()
	_title.show()
	_roster_button.grab_focus()
	_request_audio(&"ui_back")


func open_growth(member_id: int) -> void:
	if phase != Phase.TITLE or not is_instance_valid(roster_panel) or not roster_panel.visible or member_id not in [1,2]:
		return
	roster_panel.hide()
	if not is_instance_valid(growth_panel):
		growth_panel = GrowthPanel.new()
		_screen.add_child(growth_panel)
		growth_panel.closed.connect(close_growth)
	growth_panel.selected_member_id = member_id
	growth_panel.show()
	growth_panel.refresh(camp_snapshot())
	growth_panel.member_buttons[member_id - 1].grab_focus()
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
	entry.call_sign = value
	_progress_dirty = true
	save_camp()
	roster_panel.refresh(camp_snapshot(), _progress_message)
	_request_audio(&"ui_confirm")


func _roster_equipment(member_id: int) -> void:
	close_roster()
	_return_roster_member = member_id
	open_loadout()
	loadout_panel._selected_id = WeaponInventory.for_member(camp_snapshot(), member_id).instance_id
	loadout_panel.refresh(camp_snapshot())


func open_loadout() -> void:
	if phase != Phase.TITLE or _settings_open() or _requires_continue or _progress_blocked:
		return
	if not is_instance_valid(loadout_panel):
		loadout_panel = LoadoutPanel.new()
		_screen.add_child(loadout_panel)
		loadout_panel.equip_requested.connect(equip_weapon)
		loadout_panel.repair_requested.connect(repair_weapon)
		loadout_panel.closed.connect(close_loadout)
	_title.hide()
	loadout_panel.show()
	loadout_panel.refresh(camp_snapshot())
	loadout_panel.items.grab_focus()
	_request_audio(&"ui_confirm")


func close_loadout() -> void:
	if not is_instance_valid(loadout_panel) or loadout_panel.confirmation.visible:
		return
	loadout_panel.hide()
	_title.show()
	_loadout_button.grab_focus()
	_request_audio(&"ui_back")
	if _return_roster_member > 0:
		roster_panel.selected_member_id = _return_roster_member
		_return_roster_member = 0
		open_roster()


func equip_weapon(member_id: int, identity: String) -> void:
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible:
		return
	_commit_loadout(WeaponInventory.equip(camp_snapshot(), member_id, identity))


func repair_weapon(identity: String) -> void:
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible:
		return
	_commit_loadout(WeaponInventory.repair(camp_snapshot(), identity))


func _commit_loadout(transaction: Dictionary) -> void:
	var feedback: String = transaction.message
	if transaction.has("data"):
		var problem: String = RunSave.validate(transaction.data)
		if not problem.is_empty():
			loadout_panel.refresh(camp_snapshot(), problem)
			return
		_apply_progress(transaction.data)
		_progress_dirty = true
		save_camp()
		feedback += " " + _progress_message
		_request_audio(&"ui_confirm")
	loadout_panel.refresh(camp_snapshot(), feedback)


func _request_audio(cue: StringName, world: bool = false) -> bool:
	var accepted: bool = audio.play_world(cue) if world else audio.play_ui(cue)
	audio_requested.emit(cue, world, accepted)
	return accepted


func _on_combat_feedback(event: Dictionary) -> void:
	if event["kind"] == "shot":
		_request_audio(&"fire", true)
		if float(event.get("applied_damage", 0.0)) > 0.0:
			_request_audio(&"hit", true)
	elif event["kind"] == "hit" and float(event.get("applied_damage", 0.0)) > 0.0:
		_request_audio(&"hit", true)


func _on_search_completed(_reward: int) -> void:
	_request_audio(&"collect_complete", true)


func _on_engine_started() -> void:
	_request_audio(&"bus_start", true)
	_request_audio(&"ui_confirm")


func _on_pause_changed(paused: bool) -> void:
	audio.set_world_paused(paused)
	_request_audio(&"ui_confirm")


func _on_help_changed(expanded: bool) -> void:
	_request_audio(&"ui_confirm" if expanded else &"ui_back")


func _disconnect_sortie_events() -> void:
	if not is_instance_valid(expedition):
		return
	if expedition.combat_feedback.is_connected(_on_combat_feedback):
		expedition.combat_feedback.disconnect(_on_combat_feedback)
		expedition.search_completed.disconnect(_on_search_completed)
		expedition.engine_started.disconnect(_on_engine_started)
		expedition.pause_changed.disconnect(_on_pause_changed)
		expedition.help_changed.disconnect(_on_help_changed)
		expedition.finished.disconnect(_finish_callback)


func camp_snapshot() -> Dictionary:
	return {"schema_version":RunSave.SCHEMA_VERSION, "profile_id":profile_id,
		"day":day, "cash":cash, "settled_sorties":settled_sorties,
		"food":food,"last_day":last_day.duplicate(true),
		"weapons":weapons.duplicate(true), "loadout":loadout.duplicate(true), "camp_spending":camp_spending,
		"last_settlement_id":last_settlement_id,
		"crew":crew.duplicate(true)}


func continue_game() -> void:
	if phase != Phase.TITLE or _settings_open() or not _requires_continue:
		return
	_apply_progress(_pending_save)
	_progress_message = "已继续已保存营地；正式出击结算并回营地后自动保存。" + _migration_notice
	_update_camp()
	_request_audio(&"ui_confirm")
	print("BH_CONTINUED day=%d cash=%d food=%d health=%s" % [day, cash, food, crew_health])


func use_backup() -> void:
	if phase != Phase.TITLE or _settings_open() or not _progress_blocked or _backup_save.is_empty():
		return
	_apply_progress(_backup_save)
	_allow_invalid_replacement = true
	_progress_message = "已使用校验通过的上次备份；异常主档保留，下次结算回营时归档替换。"
	_progress_message += _backup_migration_notice
	_update_camp()
	_request_audio(&"ui_confirm")


func save_camp() -> void:
	if phase != Phase.TITLE or not _progress_dirty:
		return
	var error: Error = run_save.save(camp_snapshot(), _allow_invalid_replacement)
	_progress_message = run_save.diagnostic
	if error == OK:
		_progress_dirty = false
		_allow_invalid_replacement = false
		_progress_message += "；重开后点击继续游戏。中途出击不保存。"
	else:
		_progress_message = "保存失败：%s。进度仍在本次运行中；可在营地重试保存。" % run_save.diagnostic
	print("BH_SAVE error=%d day=%d cash=%d food=%d health=%s" % [error, day, cash, food, crew_health])
	_update_camp()


func _apply_progress(data: Dictionary) -> void:
	_camp_open = true
	profile_id = data.profile_id
	day = int(data.day)
	cash = int(data.cash)
	food = int(data.food)
	last_day = data.last_day.duplicate(true)
	weapons.assign(data.weapons.duplicate(true))
	loadout.assign(data.loadout.duplicate(true))
	camp_spending = int(data.camp_spending)
	settled_sorties = int(data.settled_sorties)
	last_settlement_id = data.last_settlement_id
	crew.assign(data.crew.duplicate(true))
	_requires_continue = false
	_progress_blocked = false


func _setup_progress() -> void:
	run_save = RunSave.new(progress_path)
	profile_id = RunSave.new_profile_id()
	_initialize_weapons("initial")
	var loaded: Error = run_save.load_save()
	if loaded == OK:
		_pending_save = run_save.snapshot.duplicate(true)
		_requires_continue = true
		_progress_message = "存档校验通过；继续游戏可恢复营地。新游戏需确认，不会立即覆盖。"
		if run_save.migrated_from > 0:
			_migration_notice = run_save.diagnostic
			_progress_message = _migration_notice
	elif loaded == ERR_FILE_NOT_FOUND and not run_save.has_files():
		_progress_message = "空档：可直接出击；首次回营或确认营地配装后保存。练习不保存。"
	else:
		_progress_blocked = true
		_progress_message = "读取失败：%s；原文件保留，不会自动覆盖。" % run_save.diagnostic
		var backup: RunSave = RunSave.new(progress_path)
		if backup.load_save(true) == OK:
			_backup_save = backup.snapshot.duplicate(true)
			if backup.migrated_from > 0:
				_backup_migration_notice = backup.diagnostic
		else:
			_progress_message += " 备份也不可用。"
	_continue_button = _progress_button("继续游戏 →", 456.0, continue_game)
	_backup_button = _progress_button("使用有效备份（上次营地）", 456.0, use_backup)
	_retry_button = _progress_button("重试保存当前营地", 540.0, save_camp)
	$Interface/Screen/Title/Reset.text = "新游戏…"
	$Interface/Screen/Title/Start.text = "选择出击目标 →"
	_new_game_confirmation = ConfirmationDialog.new()
	_new_game_confirmation.title = "确认新游戏"
	_new_game_confirmation.ok_button_text = "确认开始新游戏"
	_new_game_confirmation.cancel_button_text = "保留进度 / 取消"
	_new_game_confirmation.confirmed.connect(_new_game)
	_screen.add_child(_new_game_confirmation)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.offset_right = 1232.0
	_status.offset_bottom = 714.0
	var camp_label: Label = $Interface/Screen/Title/Camp
	camp_label.offset_top = 362.0
	camp_label.offset_bottom = 450.0
	camp_label.add_theme_font_size_override("font_size", 16)
	var description: Label = $Interface/Screen/Title/Description
	description.offset_top = 300.0
	description.offset_bottom = 352.0
	description.text = "搜集补给和武器后回营，维修、配装再出击；装备与营地进度一同保存。\n原作缺粮可能减员；本版损失候选尚未应用，触发与选人仍待校准。"


func _initialize_weapons(origin: String) -> void:
	var data: Dictionary = {"profile_id":profile_id, "crew":[{"id":1,"health":crew_health[0]}, {"id":2,"health":crew_health[1]}]}
	WeaponInventory.initialize(data, origin)
	weapons.assign(data.weapons)
	loadout.assign(data.loadout)
	camp_spending = 0


func _progress_button(label: String, y: float, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.position = Vector2(868.0, y)
	button.size = Vector2(328.0, 60.0 if y == 456.0 else 48.0)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	_title.add_child(button)
	return button


func _setup_presentation() -> void:
	_screen.theme = CampStyle.theme(_screen.theme)
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop: CampBackdrop = CampBackdrop.new()
	_title.add_child(backdrop)
	_title.move_child(backdrop, 0)
	$Interface/Screen/Rule.hide()
	$Interface/Screen/Brand.text = "BLUE HOUR / 归航日志"
	$Interface/Screen/Brand.add_theme_font_size_override("font_size", 16)
	CampStyle.place($Interface/Screen/Brand, Rect2(64,32,600,28))
	_screen.move_child(_status, _screen.get_child_count() - 1)
	_title.visibility_changed.connect(func() -> void: _status.visible = _title.visible and (_progress_dirty or _progress_blocked or not _migration_notice.is_empty()))
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
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--show-dev-menu":
			_developer_menu = true
		if argument.begins_with("--verify-") and not argument.begins_with("--verify-m401=") and not argument.begins_with("--verify-m402=") and not argument.begins_with("--verify-m403=") and not argument.begins_with("--verify-m501=") and not argument.begins_with("--verify-m502=") and not argument.begins_with("--verify-m503=") and not argument.begins_with("--verify-m5ux01=") and not argument.begins_with("--verify-m5combat02=") and not argument.begins_with("--verify-m5combat03="):
			_developer_menu = true
			_camp_open = not _requires_continue and not _progress_blocked


func _enter_camp() -> void:
	if phase != Phase.TITLE or _settings_open() or _requires_continue or _progress_blocked:
		return
	_camp_open = true
	_refresh_presentation()
	$Interface/Screen/Title/Start.grab_focus()
	_request_audio(&"ui_confirm")


func _refresh_presentation() -> void:
	if not is_instance_valid(_home_button):
		return
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
		for member_id: int in [1,2]:
			var entry: Dictionary = SurvivorRoster.member(crew,member_id)
			camp.text += "\n%02d  %s  ·  生命 %.0f" % [member_id,entry.call_sign,float(entry.health)]
		camp.text += "\n今日口粮 %d · %s" % [int(daily.required),"库存足够" if daily.shortage == 0 else "缺口%d，建议前往超市" % int(daily.shortage)]
		if not last_day.is_empty() and last_day.food_shortage > 0:
			camp.text += " · 损失候选%d人，未应用" % HungerOutcome.candidate(last_day).loss_count
	_status.visible = _title.visible and (_progress_dirty or _progress_blocked or not _migration_notice.is_empty())
	start.visible = _camp_open
	_roster_button.visible = _camp_open
	_loadout_button.visible = _camp_open
	_home_return.visible = _camp_open
	_continue_button.visible = not _camp_open and _requires_continue
	_backup_button.visible = not _camp_open and _progress_blocked and not _backup_save.is_empty()
	_home_button.visible = not _camp_open and not _requires_continue and not _progress_blocked
	_home_button.text = "返回营地 →" if run_save.has_files() else "开始旅程 →"
	CampStyle.place(_continue_button, Rect2(64,446,320,56))
	CampStyle.place(_backup_button, Rect2(64,446,400,56))
	CampStyle.place(_home_button, Rect2(64,446,320,56))
	CampStyle.place(_retry_button, Rect2(840,556,356,44))
	reset.text = "新游戏…"
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
	$Interface/Screen/Title/Practice.visible = _developer_menu and _camp_open
	$Interface/Screen/Title/Probe.visible = _developer_menu and _camp_open
	CampStyle.place($Interface/Screen/Title/Practice, Rect2(840,604,220,32))
	CampStyle.place($Interface/Screen/Title/Probe, Rect2(1072,604,144,32))
	$Interface/Screen/Title/Practice.add_theme_font_size_override("font_size", 14)
	$Interface/Screen/Title/Probe.add_theme_font_size_override("font_size", 14)
	if _requires_continue and not _migration_notice.is_empty():
		camp.text = "已保存：第 %d 天 · 货币 %d · 食物 %d\n旧版营地将在继续后读取，原件保留。" % [int(_pending_save.day),int(_pending_save.cash),int(_pending_save.food)]
