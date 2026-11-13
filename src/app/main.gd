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
var _camp: AppCamp = AppCamp.new(self)
var _presentation: AppPresentation = AppPresentation.new(self)
var _menus: AppMenus = AppMenus.new(self)

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
	_menus.return_to_title()

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
	_camp._update_camp()

func _quit() -> void:
	_menus._quit()
func open_pause_menu() -> void:
	_menus.open_pause_menu()
func _configure_suspend_menu() -> void:
	_menus._configure_suspend_menu()
func _lock_menu_world() -> void:
	_menus._lock_menu_world()
func close_pause_menu() -> void:
	_menus.close_pause_menu()

func suspend_sortie() -> void:
	_sortie.suspend_sortie()
func _suspend_problem(result: Dictionary) -> String:
	return _sortie._suspend_problem(result)

func request_exit(target: String) -> void:
	_menus.request_exit(target)
func _cancel_exit() -> void:
	_menus._cancel_exit()
func _confirm_exit() -> void:
	_menus._confirm_exit()
func open_sound_settings() -> void:
	_menus.open_sound_settings()
func _close_sound_settings() -> void:
	_menus._close_sound_settings()
func _settings_open() -> bool:
	return _menus._settings_open()

func open_roster() -> void:
	_camp.open_roster()
func close_roster(discard_pending: bool = false) -> void:
	_camp.close_roster(discard_pending)
func _leave_roster_for(action: StringName, discard_pending: bool = false) -> void:
	_camp._leave_roster_for(action, discard_pending)
func open_growth(member_id: int, discard_pending: bool = false) -> void:
	_camp.open_growth(member_id, discard_pending)
func close_growth() -> void:
	_camp.close_growth()
func rename_survivor(member_id: int, value: String) -> void:
	_camp.rename_survivor(member_id, value)
func _roster_equipment(member_id: int, discard_pending: bool = false) -> void:
	_camp._roster_equipment(member_id, discard_pending)
func open_loadout(workshop: bool = false) -> void:
	_camp.open_loadout(workshop)
func _leave_loadout_for(action: StringName) -> void:
	_camp._leave_loadout_for(action)
func close_loadout() -> void:
	_camp.close_loadout()
func equip_weapon(member_id: int, identity: String) -> void:
	await _camp.equip_weapon(member_id, identity)
func repair_weapon(identity: String) -> void:
	await _camp.repair_weapon(identity)
func install_workshop_mod(identity: String, mod: String) -> void:
	_camp.install_workshop_mod(identity, mod)
func confirm_economy_edit(request: Dictionary) -> void:
	await _camp.confirm_economy_edit(request)

func _request_audio(cue: StringName, world: bool = false) -> bool:
	return _menus._request_audio(cue, world)

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
	_presentation._setup_presentation()

func _enter_camp() -> void:
	_camp._enter_camp()

func _refresh_presentation() -> void:
	_presentation._refresh_presentation()

func _setup_camp_scene() -> void:
	_camp._setup_camp_scene()
func _offer_camp_facility(choice: String, upgrade: bool = false) -> void:
	_camp._offer_camp_facility(choice, upgrade)
func _confirm_camp_facility() -> void:
	_camp._confirm_camp_facility()
func _restore_facility_focus() -> void:
	_camp._restore_facility_focus()
func open_supplies() -> void:
	_camp.open_supplies()
func _refresh_supply_panel() -> void:
	_camp._refresh_supply_panel()
func _retry_facility() -> void:
	_camp._retry_facility()
func _leave_supplies_for(action: StringName) -> void:
	_camp._leave_supplies_for(action)
func _sync_camp_scene() -> void:
	_camp._sync_camp_scene()
func _camp_action(action: StringName, member_id: int) -> void:
	_camp._camp_action(action, member_id)
func _guard_camp_editor(action: Callable) -> bool:
	return _camp._guard_camp_editor(action)
func _camp_escape() -> bool:
	return _camp._camp_escape()
func _camp_input_allowed() -> bool:
	return _camp._camp_input_allowed()
func _roster_training(id: int) -> void:
	_camp._roster_training(id)
func open_training() -> void:
	_camp.open_training()
func close_training() -> void:
	_camp.close_training()
func confirm_training(request: Dictionary) -> void:
	_camp.confirm_training(request)
func retry_training() -> void:
	_camp.retry_training()

func _refresh_playable_presentation() -> void:
	_presentation._refresh_playable_presentation()
func _setup_blue_hour_title() -> void:
	_presentation._setup_blue_hour_title()
func _refresh_blue_hour_title() -> void:
	_presentation._refresh_blue_hour_title()
func _blue_hour_title_buttons() -> Array[Button]:
	return _presentation._blue_hour_title_buttons()
func _style_blue_hour_title_button(button: Button) -> void:
	_presentation._style_blue_hour_title_button(button)
func _remember_blue_hour_title_focus(button: Button) -> void:
	_presentation._remember_blue_hour_title_focus(button)
func _restore_blue_hour_title_focus() -> void:
	_presentation._restore_blue_hour_title_focus()

func _playable_result_text(snapshot: Dictionary, durable: bool) -> String:
	return _results._playable_result_text(snapshot, durable)
func _catalog_result_notice(snapshot: Dictionary) -> String:
	return _results._catalog_result_notice(snapshot)

func _show_equipment_catalog(state: Dictionary) -> void:
	_camp._show_equipment_catalog(state)
func _close_equipment_catalog() -> void:
	_camp._close_equipment_catalog()
func equip_build_item(slot: int, item: String) -> void:
	await _camp.equip_build_item(slot, item)
func equip_power(id: String, slot: int = 0) -> void:
	_camp.equip_power(id, slot)
func invest_power(choice: String) -> void:
	_camp.invest_power(choice)
func invest_build(choice: String) -> void:
	_camp.invest_build(choice)
func _edit_power(request: Dictionary, success: String) -> void:
	await _camp._edit_power(request, success)
func retry_power_edit() -> void:
	await _camp.retry_power_edit()
