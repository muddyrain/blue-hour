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
const BLUE_HOUR_TITLE_ART: Texture2D = preload("res://assets/ui/m20/title-blue-hour.png")
const BLUE_HOUR_CAMP_ART: Texture2D = preload("res://assets/ui/m20/camp-blue-hour.png")
const SLOW_DEPARTURE_MS: int = 120

var playable_entry: bool = false
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
var transactional_mode: bool = false
var battle_mode: bool = false
var survival_mode: bool = false
var safe_suspend: bool = false
var _frozen_world: Dictionary = {}
var survival_pilot: bool = false
var rescue_mode: bool = false
var growth_mode: bool = false
var field_join_mode: bool = false
var trait_mode: bool = false
var training_mode: bool = false
var pool_mode: bool = false
var roster_mode: bool = false
var enemy_mode: bool = false
var quality_mode: bool = false
var training_panel: TrainingPanel
var _training: Array = []
var camp_prototype: bool = false
var camp_scene: CampSceneView
var _camp_legacy: bool = false
var _camp_scene_problem: String = ""
var _camp_legacy_return: Button
var _camp_leave_dialog: ConfirmationDialog
var _facility_confirmation: ConfirmationDialog
var _facility_choice: String = ""
var _camp_leave_action: Callable
var _recruits: Array = []
var hunger_trial: bool = false
var _hunger_consented: bool = false
var _hunger_confirmation: ConfirmationDialog
var _camp_backdrop: CampBackdrop
var _blue_hour_title_art: TextureRect
var _blue_hour_title_focus: Button
var _departure_pending: bool = false
var _battle_meta: Dictionary = {}
var _survival_origin: Dictionary = {}
var migration_panel: MigrationPanel
var _migration_source: String = ""
var _migration_entry: Button
var _migration_preview: Dictionary = {}
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
var _opening_picker: OpeningBuildPicker
var _opening_confirm_pending: bool = false
var _catalog_button: Button
var _equipment_catalog: EquipmentCatalog
var pause_menu: SortiePauseMenu
var _menu_was_paused: bool = false
var _menu_from_pause: bool = false
var _exit_target: String = ""

@onready var _title: Control = $Interface/Screen/Title
@onready var _status: Label = $Interface/Screen/Status
@onready var _back: Button = $Interface/Screen/Back
@onready var _screen: Control = $Interface/Screen
@onready var _result: Control = $Interface/Screen/Result


func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(func() -> void: request_exit("quit"))
	var entry: Dictionary = PlayableEntry.resolve(OS.get_cmdline_user_args())
	playable_entry = entry.playable
	var launch_arguments: Array[String] = entry.arguments
	progress_path = entry.progress
	audio_settings_path = entry.audio
	enemy_mode = "--bh-enemy-trial" in launch_arguments
	quality_mode = enemy_mode or "--bh-weapon-quality-trial" in launch_arguments
	roster_mode = quality_mode or "--bh-roster-trial" in launch_arguments
	pool_mode = roster_mode or "--bh-rescue-pool-trial" in launch_arguments
	training_mode = pool_mode or "--bh-training-trial" in launch_arguments
	trait_mode = training_mode or "--bh-trait-trial" in launch_arguments
	field_join_mode = trait_mode or "--bh-field-join-trial" in launch_arguments
	growth_mode = field_join_mode or "--bh-growth-trial" in launch_arguments
	rescue_mode = growth_mode or "--bh-rescue-trial" in launch_arguments
	if growth_mode:
		GrowthRules.initialize(crew)
	if trait_mode:
		TraitRules.initialize(crew)
	if training_mode:
		TrainingState.initialize(crew)
		_training = []
	hunger_trial = rescue_mode or "--bh-hunger-trial" in launch_arguments
	survival_pilot = hunger_trial or "--bh-survival-pilot" in launch_arguments
	survival_mode = survival_pilot or "--bh-survival" in launch_arguments
	safe_suspend = survival_mode and "--bh-safe-suspend" in launch_arguments
	battle_mode = survival_mode or "--bh-battle-survival" in launch_arguments
	transactional_mode = battle_mode or "--bh-transactional" in launch_arguments
	if battle_mode:
		_battle_meta = _pool_initial() if pool_mode else TrainingState.initial() if training_mode else TraitState.initial() if trait_mode else FieldJoinState.initial() if field_join_mode else GrowthState.initial() if growth_mode else (RescueState.initial() if rescue_mode else (SurvivalState.initial() if survival_mode else BattleState.initial()))
	for argument: String in launch_arguments:
		if argument.begins_with("--bh-audio-settings="):
			audio_settings_path = argument.trim_prefix("--bh-audio-settings=")
		if argument.begins_with("--bh-progress="):
			progress_path = argument.trim_prefix("--bh-progress=")
		if argument.begins_with("--bh-migrate-v5="):
			_migration_source = argument.trim_prefix("--bh-migrate-v5=")
	camp_prototype = playable_entry or ("--bh-camp-prototype" in launch_arguments and CampSceneLayout.isolated(progress_path))
	if not playable_entry and "--bh-camp-prototype" in launch_arguments and not camp_prototype:
		_camp_scene_problem = "营地场景原型需要明确的隔离目录；保留原界面。"
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
	mission_select.player_mode = playable_entry
	mission_select.rescue_enabled = rescue_mode
	mission_select.field_join_mode = field_join_mode
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
	if playable_entry and not _developer_menu:
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
	if survival_mode and not _migration_source.is_empty():
		_migration_entry = _progress_button("旧存档转换 →", 446, open_migration)
	_update_camp()
	print("BH_READY phase=TITLE renderer=%s" % RenderingServer.get_current_rendering_method())
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--verify-quality="):
			var proof: QualityPlaytest = QualityPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-quality=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-roster="):
			var proof: RosterPlaytest = RosterPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-roster=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-rescue-pool="):
			var proof: RescuePoolPlaytest = RescuePoolPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-rescue-pool=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-record-hash="):
			var proof: RecordHashPlaytest = RecordHashPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-record-hash=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument == "--verify-record-process":
			var proof: RecordHashProcess = RecordHashProcess.new()
			proof.app = self
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-anim="):
			var proof: AnimPlaytest = AnimPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-anim=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-enemy="):
			var proof: EnemyPlaytest = EnemyPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-enemy=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-weapons="):
			var proof: WeaponPlaytest = WeaponPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-weapons=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-training="):
			var proof: TrainingPlaytest = TrainingPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-training=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-traits="):
			var proof: TraitPlaytest = TraitPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-traits=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-camp="):
			var proof: CampScenePlaytest = CampScenePlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-camp=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-field-join="):
			var proof: FieldJoinPlaytest = FieldJoinPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-field-join=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-growth="):
			var proof: GrowthPlaytest = GrowthPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-growth=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-rescue="):
			var proof: RescuePlaytest = RescuePlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-rescue=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-recovery="):
			var proof: RecoveryPlaytest = RecoveryPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-recovery=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-exit="):
			var proof: ExitPlaytest = ExitPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-exit=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-hunger="):
			var proof: HungerPlaytest = HungerPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-hunger=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--observe-pilot="):
			var observer: PilotInputObserver = PilotInputObserver.new()
			observer.app = self
			observer.output_dir = argument.trim_prefix("--observe-pilot=")
			get_tree().root.add_child.call_deferred(observer)
		if argument.begins_with("--verify-pilot="):
			var proof: SurvivalPilotPlaytest = SurvivalPilotPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-pilot=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-migration="):
			var proof: MigrationPlaytest = MigrationPlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-migration=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-battle="):
			var proof: BattlePlaytest = BattlePlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-battle=")
			get_tree().root.add_child.call_deferred(proof)
			return
		if argument.begins_with("--verify-p0d02a="):
			var proof: P0D02APlaytest = P0D02APlaytest.new()
			proof.app = self
			proof.output_dir = argument.trim_prefix("--verify-p0d02a=")
			get_tree().root.add_child.call_deferred(proof)
			return
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
	if progress_session != null:
		progress_session.close()
	if is_instance_valid(audio):
		audio.shutdown()


func _input(event: InputEvent) -> void:
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
	if event.is_action_pressed("return_to_title") and is_instance_valid(migration_panel) and migration_panel.visible:
		close_migration()
		get_viewport().set_input_as_handled()
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
	if battle_mode and not _pending_settlement.is_empty() and (_pending_settlement.journey.state=="FAILED" or CampaignState.ended(_pending_settlement)):
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
		if transactional_mode:
			if not _accept_transaction(progress_session.commit_result(),true): return
		elif _pending_settlement.last_settlement_id != last_settlement_id:
			_apply_progress(_pending_settlement)
			_progress_dirty = true
			print("BH_SETTLED %s" % JSON.stringify(last_day))
		_pending_settlement = {}
	_damage_gates.clear()
	if transactional_mode and _progress_blocked:
		_camp_open = false
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
	if hunger_trial and not _hunger_consented:
		_hunger_confirmation.popup_centered(Vector2i(700,260))
		return
	_title.hide()
	if playable_entry:
		var base: Dictionary = camp_snapshot()
		mission_select.refresh_daily(base, CampEconomy.rations(int(base.day), base.crew, int(base.food), camp_rules))
	else: mission_select.refresh_rescue(RescuePoolState.available(camp_snapshot()).is_empty() if pool_mode else not _recruits.is_empty(), RosterState.unavailable_reason(camp_snapshot()) if roster_mode else "四人历史编制已满" if pool_mode else "")
	mission_select.show()
	mission_select.choices[0].grab_focus()
	_request_audio(&"ui_confirm")


func close_mission_select() -> void:
	mission_select.hide()
	_title.show()
	if is_instance_valid(_blue_hour_title_art) and is_instance_valid(camp_scene) and camp_scene.is_visible_in_tree():
		camp_scene.restore_focus()
	_request_audio(&"ui_back")


func _select_mission(supply: MissionSupply) -> void:
	if _departure_pending or (is_instance_valid(_blue_hour_title_art) and phase != Phase.TITLE):
		return
	var from_menu: bool = is_instance_valid(_blue_hour_title_art) and mission_select.visible
	var started: int = Time.get_ticks_msec()
	_departure_pending = from_menu
	selected_supply = supply
	mission_select.hide()
	open_expedition()
	_departure_pending = false
	if not from_menu:
		return
	if phase != Phase.EXPEDITION:
		# The transaction owns the failure message and blocking policy. Restore its view.
		if _progress_blocked:
			_camp_open = false
		_title.show()
		_refresh_presentation()
		if is_instance_valid(camp_scene) and camp_scene.is_visible_in_tree():
			camp_scene.restore_focus()
	elif Time.get_ticks_msec() - started >= SLOW_DEPARTURE_MS:
		_fade_departure()


func _fade_departure() -> void:
	var cover: TextureRect = CampStyle.blue_hour_background(BLUE_HOUR_CAMP_ART)
	cover.name = "BlueHourDepartureFade"
	cover.modulate = Color(0.63, 0.76, 0.87, 0.84)
	$Interface.add_child(cover)
	var fade: Tween = cover.create_tween()
	fade.tween_property(cover, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(cover.queue_free)


func open_expedition() -> void:
	_open_sortie(false)


func open_practice() -> void:
	_open_sortie(true)


func _open_sortie(practice: bool, resume: Dictionary = {}) -> void:
	if phase != Phase.TITLE or _settings_open():
		return
	if hunger_trial and not _hunger_consented:
		return
	if battle_mode and (practice or _battle_meta.get("state") == "FAILED" or CampaignState.ended(camp_snapshot())):
		return
	if not practice and not battle_mode and (crew_health[0] <= 0.0 or crew_health[1] <= 0.0):
		return
	if not practice and (_requires_continue or _progress_blocked):
		return
	if not practice and transactional_mode and resume.is_empty():
		var started: Dictionary = progress_session.begin(camp_snapshot(),selected_supply)
		if started.error != OK:
			_accept_transaction(started)
			return
		if playable_entry: selected_supply = progress_session.active_supply()
	elif not practice and not transactional_mode and RunSave.transaction_namespace(progress_path):
		_progress_blocked = true
		_progress_message = "此进度要求事务入口，不能按旧档出击。"
		_update_camp()
		return
	expedition = ExpeditionScene.instantiate() as Expedition
	expedition.restoring_world = not resume.is_empty()
	expedition.is_practice = practice
	expedition.player_mode = playable_entry
	expedition.battle_survival = battle_mode
	expedition.battle_drill = battle_mode and not survival_pilot and "--bh-battle-drill" in OS.get_cmdline_user_args()
	expedition.hunger_trial = hunger_trial
	expedition.field_join_mode = field_join_mode
	expedition.field_departure = camp_snapshot() if field_join_mode else {}
	expedition.field_join_gate = progress_session.join_field if field_join_mode else Callable()
	if field_join_mode and not resume.is_empty():
		expedition.field_joins.assign(resume.receipt.joins.duplicate(true))
	expedition.membership_committed.connect(_attach_damage_gates)
	expedition.growth_mode = growth_mode
	expedition.enemy_mode = enemy_mode
	expedition.trait_mode = trait_mode
	expedition.training_mode = training_mode
	expedition.pool_mode = pool_mode
	if pool_mode:
		expedition.rescue_completed = RescuePoolState.available(expedition.field_departure).is_empty()
	expedition.support_commit=progress_session.accept_support if transactional_mode else Callable()
	expedition.power_commit=progress_session.accept_power if transactional_mode else Callable()
	expedition.burst_commit=progress_session.accept_burst if transactional_mode else Callable()
	expedition.growth_binding = progress_session.token.duplicate(true) if growth_mode else {}
	expedition.rescue_mode = rescue_mode
	expedition.rescue_completed = RescuePoolState.available(expedition.field_departure).is_empty() if pool_mode else not _recruits.is_empty()
	expedition.battle_seed = "NONE" if pool_mode else _battle_meta.get("seed","NONE")
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
	_frozen_world = {}
	if not resume.is_empty():
		var world: Dictionary = resume.receipt.envelope.world
		var restored: String = SortieSnapshot.apply(expedition,world)
		if not restored.is_empty():
			_disconnect_sortie_events()
			$World.remove_child(expedition)
			expedition.queue_free()
			expedition = null
			phase = Phase.TITLE
			_progress_blocked = true
			_requires_continue = false
			_progress_message = "无法安全恢复原战场，暂存未消费。" + _suspend_problem({"reason":restored})
			_update_camp()
			return
		expedition.suspend_sealed = true
		_frozen_world = world.duplicate(true)
		var claimed: Dictionary = progress_session.claim_world(resume.receipt.envelope.world_hash)
		if claimed.error == OK:
			expedition.suspend_sealed = false
			_frozen_world = {}
		else:
			pause_menu.suspend_message = "恢复消费未确认；战场保持暂停。" + _suspend_problem(claimed)
	if not practice and transactional_mode and (battle_mode or "--bh-txn-death-probe" in OS.get_cmdline_user_args()):
		_attach_damage_gates()
	_screen.hide()
	_request_audio(&"ui_confirm")
	if not resume.is_empty():
		open_pause_menu()


func reset_demo() -> void:
	if phase != Phase.TITLE or _settings_open():
		return
	if battle_mode and _progress_dirty:
		_progress_message = "当前保存或冻结结果尚未确认；请先重试，不能切换到新旅程。"
		_update_camp()
		return
	if playable_entry:
		_open_opening_choice()
		return
	if survival_pilot or run_save.has_files() or _progress_dirty or settled_sorties > 0:
		var preview: Dictionary = _pending_save if _requires_continue and not _pending_save.is_empty() else {"day":day,"cash":cash}
		_new_game_confirmation.dialog_text = "开始新游戏？\n当前进度：第 %d 天，货币 %d。\n旧档暂时保留；新游戏首次回营或确认营地配装后才替换，并保留有效备份。\n异常文件将原字节归档，不会直接删除。" % [int(preview.day), int(preview.cash)]
		if transactional_mode:
			_new_game_confirmation.dialog_text = "开始全新旅程？\n确认后立即保存并登记基础营地；旧档、备份与旧事务保留为历史。\n取消不写盘。永久死亡与缺粮减员仍未开放。"
		if battle_mode:
			_new_game_confirmation.dialog_text = "开始新的隔离生存旅程？\n确认后立即保存独立生存格式；战斗阵亡不可复活。\n旧旅程、备份与事务原件独立保留。缺粮规则仍未开放。"
		if survival_pilot:
			_new_game_confirmation.title = "新生存旅程（测试）"
			_new_game_confirmation.ok_button_text = "确认开始新旅程"
			_new_game_confirmation.dialog_text = "普通初始：两人各200生命 / 食物2 / 货币53 / 原初始装备。\n确认后先保存独立生存进度；普通v5不转换。战斗阵亡不可复活。\n缺粮人选尚未批准，口粮不足会阻塞结算。死者装备闲置仅为测试候选。\n无完整结果的中断不能自动恢复营地；旧旅程与原件保留。"
		if hunger_trial:
			_new_game_confirmation.title = "Blue Hour 暂行饥饿规则 / 隔离测试"
			_new_game_confirmation.dialog_text = _hunger_policy_text() + "\n新旅程：两人各200HP / 食物2 / 原初始装备。普通v5不自动转换。\n确认后立即保存独立基础营地；取消不写盘，旧旅程原件保留。"
		_new_game_confirmation.popup_centered(Vector2i(650, 240))
		return
	_new_game()


func _pool_initial() -> Dictionary:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-rescue-seed="):
			return EnemyState.initial(argument.trim_prefix("--bh-rescue-seed=")) if enemy_mode else WeaponState.initial(argument.trim_prefix("--bh-rescue-seed=")) if quality_mode else RosterState.initial(argument.trim_prefix("--bh-rescue-seed=")) if roster_mode else RescuePoolState.initial(argument.trim_prefix("--bh-rescue-seed="))
	return EnemyState.initial() if enemy_mode else WeaponState.initial() if quality_mode else RosterState.initial() if roster_mode else RescuePoolState.initial()


func _open_opening_choice() -> void:
	_opening_picker.reset_choice()
	_opening_confirm_pending = true
	_new_game_confirmation.popup_centered(Vector2i(740, 372))
	_opening_picker.link_focus.call_deferred(_new_game_confirmation.get_ok_button(), _new_game_confirmation.get_cancel_button())


func _confirm_new_journey() -> void:
	if not playable_entry:
		_new_game()
	elif _opening_confirm_pending:
		_opening_confirm_pending = false
		var catalog: Dictionary = progress_session.refresh_catalog()
		if catalog.error != OK:
			_show_equipment_catalog(catalog)
			return
		if phase == Phase.RESULT:
			return_to_title()
		if phase == Phase.TITLE:
			_new_game(_opening_picker.selected_plan, {"version":CatalogProgress.VERSION, "unlock":catalog.unlock_hash})


func _new_game(opening_plan: String = "", catalog_policy: Dictionary = {}) -> void:
	if not opening_plan.is_empty() and (not playable_entry or not OpeningBuild.PLANS.has(opening_plan)):
		return
	if rescue_mode: _recruits = []
	if transactional_mode and _transactional_new_pending:
		_progress_message = "新旅程基础尚未确认，请先重试保存或退出。"
		_update_camp()
		return
	_camp_open = true
	_hunger_consented = hunger_trial
	cash = CampRules.INITIAL_CASH
	day = 2
	crew = SurvivorRoster.new_crew()
	if growth_mode:
		GrowthRules.initialize(crew)
	if trait_mode:
		TraitRules.initialize(crew)
	if training_mode:
		TrainingState.initialize(crew)
		_training = []
	settled_sorties = 0
	food = camp_rules.initial_food
	if battle_mode:
		_battle_meta = _pool_initial() if pool_mode else TrainingState.initial() if training_mode else TraitState.initial() if trait_mode else FieldJoinState.initial() if field_join_mode else GrowthState.initial() if growth_mode else (RescueState.initial() if rescue_mode else (SurvivalState.initial() if survival_mode else BattleState.initial()))
		_survival_origin = {}
		if not survival_pilot and "--bh-battle-drill" in OS.get_cmdline_user_args():
			_battle_meta.seed = "LOW_HP_4_FOOD_12"
			food = 12
			for member: Dictionary in crew:
				member.health = 4.0
	last_day = {}
	_pending_settlement = {}
	_migration_notice = ""
	profile_id = RunSave.new_profile_id()
	if playable_entry:
		var latest_rules: bool = not catalog_policy.is_empty()
		_battle_meta.campaign = CampaignRules.initial_mission(profile_id, true, true, true, true,
			latest_rules, latest_rules, latest_rules, latest_rules, latest_rules, latest_rules)
		if latest_rules:
			_battle_meta.campaign.night_hound_policy = NightHoundV1.VERSION
			_battle_meta.campaign.workshop = WorkshopV1.initial()
			_battle_meta.campaign.event_sortie_policy = EventSortieV1.VERSION
			_battle_meta.campaign.recon_policy = ReconActionV1.SOURCE_VERSION
			_battle_meta.campaign.barricade_policy = BarricadeV1.VERSION
			_battle_meta.campaign.billboard_policy = BillboardActionV1.VERSION
		_battle_meta.build=WorldgenState.initial_build(_battle_meta.seed, true, true)
		_battle_meta.build.powers = PowerState.initial_progression(
			SpecialPowers.WAVE_VERSION if latest_rules else SpecialPowers.PROGRESSION_VERSION)
		if not opening_plan.is_empty():
			var starter: Dictionary = OpeningBuild.source(opening_plan, profile_id, _battle_meta.root_id, _battle_meta.seed)
			_battle_meta.build.opening = starter
			_battle_meta.build.owned.append(starter.item_id)
			_battle_meta.build.slots[0] = starter.item_id
			if not catalog_policy.is_empty():
				_battle_meta.build.catalog = catalog_policy.duplicate(true)
	_initialize_weapons("initial")
	last_settlement_id = ""
	_pending_save.clear()
	_backup_save.clear()
	_requires_continue = false
	_progress_blocked = false
	_progress_dirty = false
	_allow_invalid_replacement = true
	_progress_message = "新游戏尚未保存；正式回营或确认营地配装后保存。"
	if transactional_mode:
		_transactional_new_pending = true
		_accept_transaction(progress_session.create(camp_snapshot()),true)
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
		$Interface/Screen/Result/Scroll/Body.text = "队员生命 %d / %d\n击退 %d\n\n移动、命中、受击和击败均来自实际战斗。\n营地的天数、资源和队员生命保持不变。" % [ceili(report["health"][0]), ceili(report["health"][1]), report["kills"]]
		return
	if transactional_mode:
		var carried: Dictionary = {"loot":expedition.loot,"food":expedition.food_loot,"weapons":expedition.weapon_loot.duplicate(true)}
		var prepared: Dictionary = progress_session.finish(report,carried)
		if prepared.error == OK:
			_pending_settlement = prepared.camp.duplicate(true)
		else:
			_pending_settlement = {}
			_accept_transaction(prepared,bool(prepared.get("retry_packet",false)))
	else:
		_pending_settlement = CampEconomy.preview(camp_snapshot(), report, sortie_id, camp_rules)
	if battle_mode and not _pending_settlement.is_empty():
		if _pending_settlement.journey.state == "FAILED":
			var frozen: Dictionary = _pending_settlement.duplicate(true)
			if _accept_transaction(progress_session.commit_result(),true):
				_pending_settlement = {}
			_show_battle_result(frozen,_pending_settlement.is_empty())
		else:
			_show_battle_result(_pending_settlement,false)
			if report.evacuated and expedition.bus_view != null:
				_screen.hide()
				expedition.bus_view.departed.connect(func() -> void: _screen.show(),CONNECT_ONE_SHOT)
				expedition.bus_view.departure()
		return
	if _pending_settlement.is_empty():
		_status.text = "结算数据无效，营地与旧档未改变。"
		$Interface/Screen/Result/Heading.text = "结算未应用"
		$Interface/Screen/Result/Scroll/Body.text = "请返回营地；此次不会修改资源或日期。"
		if transactional_mode:
			$Interface/Screen/Result/Scroll/Body.text = _progress_message+"\n本次行动仍保留在事务记录中，不能退回旧档绕过。"
			$Interface/Screen/Result/Continue.text = "返回首页 / 保留阻塞"
		return
	var ledger: Dictionary = _pending_settlement.last_day
	_status.text = "归航结算预览；返回营地时只入库、扣粮一次并保存。此时退出不改变上次营地。"
	if transactional_mode:
		_status.text = "完整结果已冻结；返回营地确认提交。重启后继续使用同一结果。"
	$Interface/Screen/Result/Heading.text = "平安归航" if report["evacuated"] else "队伍失去行动能力"
	$Interface/Screen/Result/Scroll/Body.text = (
		"第 %d 日归航 · 返回营地后进入第 %d 天\n\n货币 %d + 带回 %d = %d\n食物 %d + 带回 %d - 口粮 %d = %d\n今日需求 %d · 实耗 %d · 缺口 %d\n%s\n\n队员生命 %d / %d · 搜集 %d 处 · 击退 %d"
		% [day, int(_pending_settlement.day), cash, ledger.cash_gained, ledger.cash_after,
		food, ledger.food_stored, ledger.food_consumed, ledger.food_after,
		ledger.food_required, ledger.food_consumed, ledger.food_shortage,
		HungerOutcome.description(ledger),
		ceili(report.health[0]), ceili(report.health[1]), int(report.get("sites_searched", 1 if report.get("searched", false) else 0)), report.kills]
	)
	if ledger.food_overflow > 0:
		$Interface/Screen/Result/Scroll/Body.text += "\n库存上限：另有 %d 食物未入库。" % ledger.food_overflow
	var reward_items: Array = report.get("weapons", [])
	if not reward_items.is_empty() and report.evacuated:
		for item: Dictionary in reward_items:$Interface/Screen/Result/Scroll/Body.text += "\n带回武器："+WeaponInventory.loot_description(item)+" · 回营后可维修整备"


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
	var eligible: bool = (_battle_meta.get("state") == "ACTIVE" and not CampaignState.ended(camp_snapshot())) if battle_mode else crew_health[0] > 0.0 and crew_health[1] > 0.0
	$Interface/Screen/Title/Start.disabled = _requires_continue or _progress_blocked or not eligible
	_loadout_button.disabled = _requires_continue or _progress_blocked
	_roster_button.disabled = _requires_continue or _progress_blocked
	_continue_button.visible = _requires_continue
	_backup_button.visible = _progress_blocked and not _backup_save.is_empty()
	_retry_button.visible = _progress_dirty
	if _requires_continue and _pending_save.is_empty() and safe_suspend:
		$Interface/Screen/Title/Camp.text = "已有未完成的出击暂存；请继续原战场。暂存没有回营、结算、扣粮或推进日期。"
	elif _requires_continue:
		$Interface/Screen/Title/Camp.text = "已保存：第 %d 天 / 货币 %d / 食物 %d\n点击“继续游戏”恢复营地；旧档不会自动改写。\n%s" % [int(_pending_save.day), int(_pending_save.cash), int(_pending_save.food), _migration_notice]
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
	pause_menu.suspend_available = safe_suspend and is_instance_valid(expedition) and not expedition.is_practice
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
	if not safe_suspend or phase != Phase.EXPEDITION or not is_instance_valid(expedition) or not pause_menu.root.visible:
		return
	var quit_after_save: bool = pause_menu.confirming and _exit_target == "quit"
	if _frozen_world.is_empty():
		_frozen_world = SortieSnapshot.capture(expedition)
	if _frozen_world.is_empty():
		pause_menu.suspend_message = "未保存成功：当前状态不能完整暂存，请正常巴士撤离。"
		pause_menu.show_pause(_menu_was_paused)
		return
	# Once publication is attempted, a failure may still leave a durable snapshot.
	# Seal the original world until that anchor is consumed or publication is confirmed.
	expedition.suspend_sealed = true
	var saved: Dictionary = progress_session.suspend_world(_frozen_world)
	if saved.error != OK:
		print("BH_SUSPEND_BLOCK ",saved.get("reason",""))
		pause_menu.suspend_message = "未保存成功，原场景保持暂停；可重试暂存或继续确认安全消费。\n" + _suspend_problem(saved)
		pause_menu.show_pause(_menu_was_paused)
		return
	audio.stop_world()
	_disconnect_sortie_events()
	_damage_gates.clear()
	$World.remove_child(expedition)
	expedition.queue_free()
	expedition = null
	_frozen_world = {}
	pause_menu.close()
	pause_menu.suspend_message = ""
	_exit_target = ""
	_menu_from_pause = false
	phase = Phase.TITLE
	_camp_open = false
	_progress_blocked = false
	_requires_continue = true
	_progress_dirty = false
	_progress_message = "本次出击已暂存并回读确认。下次继续原战场；没有回营、奖励、扣粮或推进日期。"
	_screen.show()
	_title.show()
	_continue_button.text = "继续未完成的出击 →"
	_update_camp()
	if quit_after_save:
		print("BH_SAFE_EXIT acknowledged")
		audio.shutdown()
		get_tree().quit()


func _suspend_problem(result: Dictionary) -> String:
	var reason: String = result.get("reason", "UNKNOWN")
	print("BH_SUSPEND_DETAIL build=%s reason=%s" % [SortieSnapshot.GROWTH_BUILD if growth_mode else SortieSnapshot.BUILD, reason])
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


func request_exit(target: String) -> void:
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
	elif phase == Phase.EXPEDITION and not expedition.is_practice:
		title = "这次行动尚未完成"
		message = "本次出击尚未完整结算；退出可能使原旅程无法继续。\n已确认阵亡不会因退出撤销；未结算物资与日期不会被擅自推算。\n正常回营：留在行动，发动巴士并集合所有存活成员。\n强杀、闪退与断电无法由此菜单拦截。"
		if not transactional_mode:
			message = "旧 v5：本次行动尚未保存，退出将丢失本次进展。\n只沿用上次已保存营地，不产生本次结算；没有局内恢复。\n正常回营请留在行动，发动巴士并集合所有存活成员。"
		danger = "仍退出到首页（行动未结算）" if target == "home" else "仍关闭游戏（行动未结算）"
	elif phase == Phase.EXPEDITION and expedition.is_practice:
		message = "练习进度不会保存，也不会改变营地。"
	elif phase == Phase.RESULT:
		if transactional_mode and not _pending_settlement.is_empty():
			title = "完整结果已冻结"
			message = "重启后继续会复用已有冻结结果，只提交一次。\n本次关闭不重新计算资源、口粮、日期或阵亡。"
		elif battle_mode and _battle_meta.state == "FAILED":
			title = "旅程已结束"
			message = "全灭终局与阵亡记录已保存；重启不能复活或返回旧营地。"
		elif not transactional_mode:
			message = "旧 v5：当前只是结果预览，尚未回营保存。\n关闭后仅保留上次营地；要保存请取消并选择返回营地。"
	elif transactional_mode and _requires_continue and progress_session.inspect().get("state") == "RECOVERY_READY":
		title = "已有完整冻结结果待继续"
		message = "已有 RESULT_READY 保留。重启后明确继续将复用原冻结结果并提交一次。\n关闭不会重新计算，也不会回退到出击前营地。"
	elif safe_suspend and _requires_continue and _pending_save.is_empty() and not _progress_blocked:
		title = "本次出击已暂存"
		message = "下次使用同一隔离进度入口继续原战场；暂存已回读确认。\n这次尚未回营或结算，没有领取奖励、扣粮或推进日期。"
	var offer_suspend: bool = safe_suspend and phase == Phase.EXPEDITION and is_instance_valid(expedition) and not expedition.is_practice and expedition.phase != Expedition.Phase.FINISHED and not _progress_blocked
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
		if transactional_mode:
			_progress_blocked = true
			_requires_continue = false
			_progress_message = "上次行动中断，未形成完整结算。原旅程目前无法继续；已确认阵亡保留。不能返回旧营地。"
		else:
			_requires_continue = not _pending_save.is_empty()
			_progress_message = "已退出未结算行动；旧 v5 只保留上次已保存营地。"
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
	if is_instance_valid(_equipment_catalog) and _equipment_catalog.visible:
		return true
	if is_instance_valid(_facility_confirmation) and _facility_confirmation.visible:
		return true
	return (is_instance_valid(training_panel) and training_panel.visible) or (is_instance_valid(_camp_leave_dialog) and _camp_leave_dialog.visible) or (is_instance_valid(camp_scene) and camp_scene.info_visible()) or (is_instance_valid(migration_panel) and migration_panel.visible) or (is_instance_valid(sound_settings) and sound_settings.visible) or _new_game_confirmation.visible or (is_instance_valid(mission_select) and mission_select.visible) or (is_instance_valid(loadout_panel) and loadout_panel.visible) or (is_instance_valid(roster_panel) and roster_panel.visible) or (is_instance_valid(growth_panel) and growth_panel.visible)


func open_roster() -> void:
	if phase != Phase.TITLE or _settings_open() or _requires_continue or _progress_blocked:
		return
	if not is_instance_valid(roster_panel):
		roster_panel = RosterPanel.new()
		roster_panel.player_mode = playable_entry
		_screen.add_child(roster_panel)
		roster_panel.call_sign_requested.connect(rename_survivor)
		roster_panel.equipment_requested.connect(_roster_equipment)
		roster_panel.growth_requested.connect(open_growth)
		roster_panel.training_requested.connect(func(id: int) -> void:
			if _guard_camp_editor(func() -> void: _roster_training(id)): return
			_roster_training(id)
		)
		roster_panel.closed.connect(close_roster)
	if camp_prototype and SurvivorRoster.member(crew, roster_panel.selected_member_id).is_empty():
		roster_panel.selected_member_id = int(crew[0].id)
	_title.hide()
	roster_panel.show()
	if roster_mode:
		roster_panel.death_equipment = progress_session.death_equipment(camp_snapshot())
	roster_panel.refresh(camp_snapshot())
	roster_panel.buttons_by_id[roster_panel.selected_member_id].grab_focus()
	_request_audio(&"ui_confirm")


func close_roster(discard_pending: bool = false) -> void:
	if not discard_pending and _guard_camp_editor(close_roster.bind(true)):
		return
	roster_panel.hide()
	_title.show()
	_roster_button.grab_focus()
	_request_audio(&"ui_back")


func open_growth(member_id: int, discard_pending: bool = false) -> void:
	if phase != Phase.TITLE or not is_instance_valid(roster_panel) or not roster_panel.visible or SurvivorRoster.member(crew,member_id).is_empty():
		return
	if not discard_pending and _guard_camp_editor(open_growth.bind(member_id, true)):
		return
	roster_panel.hide()
	if not is_instance_valid(growth_panel):
		growth_panel = GrowthPanel.new()
		growth_panel.player_mode = playable_entry
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
	if transactional_mode:
		if _accept_transaction(progress_session.edit(camp_snapshot(),{"kind":"rename","member_id":member_id,"value":value}),true):
			_request_audio(&"ui_confirm")
		roster_panel.refresh(camp_snapshot(),_progress_message)
		return
	entry.call_sign = value
	_progress_dirty = true
	save_camp()
	roster_panel.refresh(camp_snapshot(), _progress_message)
	_request_audio(&"ui_confirm")


func _roster_equipment(member_id: int, discard_pending: bool = false) -> void:
	if not discard_pending and _guard_camp_editor(_roster_equipment.bind(member_id, true)):
		return
	close_roster(true)
	_return_roster_member = member_id
	open_loadout()
	loadout_panel._selected_id = WeaponInventory.for_member(camp_snapshot(), member_id).instance_id
	loadout_panel.refresh(camp_snapshot())


func open_loadout() -> void:
	if phase != Phase.TITLE or _settings_open() or _requires_continue or _progress_blocked:
		return
	if not is_instance_valid(loadout_panel):
		loadout_panel = LoadoutPanel.new()
		loadout_panel.player_mode = playable_entry
		_screen.add_child(loadout_panel)
		loadout_panel.equip_requested.connect(equip_weapon)
		loadout_panel.build_requested.connect(equip_build_item)
		loadout_panel.power_requested.connect(equip_power)
		loadout_panel.power_panel.second_requested.connect(equip_power.bind(1))
		loadout_panel.power_panel.investment_requested.connect(invest_power)
		loadout_panel.power_panel.retry_requested.connect(retry_power_edit)
		loadout_panel.repair_requested.connect(repair_weapon)
		loadout_panel.workshop_requested.connect(install_workshop_mod)
		loadout_panel.closed.connect(close_loadout)
	_title.hide()
	loadout_panel.show()
	loadout_panel.refresh(camp_snapshot())
	loadout_panel.items.grab_focus()
	_request_audio(&"ui_confirm")


func close_loadout() -> void:
	if not is_instance_valid(loadout_panel) or loadout_panel.confirmation.visible or loadout_panel.power_panel.confirmation.visible \
			or loadout_panel.workshop_confirmation.visible:
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
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible or _progress_blocked:
		return
	if transactional_mode:
		if _accept_transaction(progress_session.edit(camp_snapshot(),{"kind":"equip","member_id":member_id,"value":identity}),true):
			_request_audio(&"ui_confirm")
		loadout_panel.refresh(camp_snapshot(),_progress_message,_progress_dirty)
		if _progress_dirty:
			loadout_panel.power_panel.retry_button.grab_focus()
		return
	_commit_loadout(WeaponInventory.equip(camp_snapshot(), member_id, identity))


func repair_weapon(identity: String) -> void:
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible or _progress_blocked:
		return
	if transactional_mode:
		if _accept_transaction(progress_session.edit(camp_snapshot(),{"kind":"repair","member_id":0,"value":identity}),true):
			_request_audio(&"ui_confirm")
		loadout_panel.refresh(camp_snapshot(),_progress_message,_progress_dirty)
		if _progress_dirty:
			loadout_panel.power_panel.retry_button.grab_focus()
		return
	_commit_loadout(WeaponInventory.repair(camp_snapshot(), identity))


func install_workshop_mod(identity: String, mod: String) -> void:
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible \
			or _progress_blocked or not transactional_mode:
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
		loadout_panel.power_panel.retry_button.grab_focus()


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


func _attach_damage_gates() -> void:
	_damage_gates.clear()
	if not transactional_mode or not is_instance_valid(expedition):
		return
	for actor: FieldActor in expedition.survivors:
		var gate: PersistedDamageGate = progress_session.damage_gate(actor)
		_damage_gates.append(gate)
		actor.damage_gate = gate.before_damage
		actor.permanent_death_enabled = battle_mode


func camp_snapshot() -> Dictionary:
	var snapshot: Dictionary = {"schema_version":RunSave.SCHEMA_VERSION, "profile_id":profile_id,
		"day":day, "cash":cash, "settled_sorties":settled_sorties,
		"food":food,"last_day":last_day.duplicate(true),
		"weapons":weapons.duplicate(true), "loadout":loadout.duplicate(true), "camp_spending":camp_spending,
		"last_settlement_id":last_settlement_id,
		"crew":crew.duplicate(true)}
	if training_mode:
		return EnemyState.snapshot(snapshot,_battle_meta,_recruits,_training) if enemy_mode else WeaponState.snapshot(snapshot,_battle_meta,_recruits,_training) if quality_mode else RosterState.snapshot(snapshot,_battle_meta,_recruits,_training) if roster_mode else RescuePoolState.snapshot(snapshot,_battle_meta,_recruits,_training) if pool_mode else TrainingState.snapshot(snapshot,_battle_meta,_recruits,_training)
	if trait_mode:
		return TraitState.snapshot(snapshot,_battle_meta,_recruits)
	if field_join_mode:
		return FieldJoinState.snapshot(snapshot,_battle_meta,_recruits)
	if growth_mode:
		return GrowthState.snapshot(snapshot,_battle_meta,_recruits)
	if rescue_mode:
		return RescueState.snapshot(snapshot,_battle_meta,_recruits)
	if survival_mode:
		return SurvivalState.snapshot(snapshot,_battle_meta,_survival_origin)
	return BattleState.snapshot(snapshot,_battle_meta) if battle_mode else snapshot


func open_migration() -> void:
	if phase != Phase.TITLE or _settings_open() or not survival_mode or _migration_source.is_empty():
		return
	if not is_instance_valid(migration_panel):
		migration_panel = MigrationPanel.new()
		_screen.add_child(migration_panel)
		migration_panel.preview_requested.connect(_preview_migration)
		migration_panel.confirmed.connect(_confirm_migration)
		migration_panel.cancelled.connect(close_migration)
	_title.hide()
	_preview_migration("MAIN")


func _preview_migration(choice: String) -> void:
	var value: Dictionary = progress_session.preview_migration(_migration_source, choice)
	_migration_preview = value.intent.duplicate(true) if value.error == OK else {}
	migration_panel.show_preview(value, _migration_reason(value.get("reason", "")))


func _confirm_migration() -> void:
	if _migration_preview.is_empty():
		return
	var value: Dictionary = progress_session.migrate(_migration_source, _migration_preview)
	if value.error == OK and _accept_transaction(value):
		_progress_message = "旧v5转换已确认；原主档/备份与声音独立保留。现按schema102隔离旅程继续。"
		close_migration()
		_update_camp()
		_request_audio(&"ui_confirm")
		return
	_progress_blocked = true
	_progress_message = _migration_reason(value.get("reason", ""))
	var retryable: bool = not String(value.get("reason", "")).contains("CONFLICT") and not String(value.get("reason", "")).contains("CHANGED") and not String(value.get("reason", "")).contains("IDENTITY")
	migration_panel.show_error(_progress_message, retryable)
	print("BH_MIGRATION_BLOCK reason=%s" % value.get("reason", ""))


func close_migration() -> void:
	if is_instance_valid(migration_panel):
		migration_panel.hide()
	_title.show()
	_update_camp()
	_request_audio(&"ui_back")


func _migration_reason(reason: String) -> String:
	if "ZERO_HP" in reason:
		return "旧档含0HP且死因未知，已阻止转换；不会补血或判死。原件保留。"
	if "NOT_VALID_V5" in reason:
		return "所选文件不是完整有效的v5。可明确预览有效备份，不能自动修复原档。"
	if "SOURCE_CHANGED" in reason or "SELECTION_CONFLICT" in reason:
		return "来源主档、备份或选择已变化，旧预览已失效；请重新核对，原件保留。"
	if "SOURCE_TRANSACTION" in reason or "SOURCE_REQUIRED_BINDING" in reason or "SOURCE_NOT_CONFIRMED" in reason:
		return "来源存在未完成或损坏事务；请先由原入口处理，不能用迁移绕过确认记录。"
	if "TARGET_ALREADY" in reason or "CONFLICT" in reason:
		return "目标已有不同进度或迁移身份不匹配，已阻止覆盖。请选择独立目标，保留原件。"
	if "WRITER" in reason:
		return "来源或目标正被其它窗口使用，转换未执行；关闭对应实例后可重试。"
	return "转换尚未完成，出击未解锁。原档保留；可重试同一次转换、取消或退出。"


func continue_game() -> void:
	if phase != Phase.TITLE or _settings_open() or not _requires_continue:
		return
	if hunger_trial and not _hunger_consented:
		_hunger_confirmation.popup_centered(Vector2i(700,260))
		return
	if transactional_mode:
		var inspected: Dictionary = progress_session.inspect()
		if inspected.error == OK and inspected.state == "SUSPENDED":
			var offer: Dictionary = progress_session.resume_offer()
			if offer.error != OK:
				_accept_transaction(offer)
				return
			_apply_progress(offer.receipt.base)
			selected_supply = SortieSnapshot.supply_for_world(offer.receipt.envelope.world)
			_requires_continue = false
			_progress_blocked = false
			_open_sortie(false,offer)
			return
		if _accept_transaction(progress_session.activate(),true):
			_request_audio(&"ui_confirm")
			if battle_mode and (_battle_meta.state == "FAILED" or CampaignState.ended(camp_snapshot())):
				_show_battle_result(camp_snapshot(),true)
		return
	_apply_progress(_pending_save)
	_progress_message = "已继续已保存营地；正式出击结算并回营地后自动保存。" + _migration_notice
	_update_camp()
	_request_audio(&"ui_confirm")
	print("BH_CONTINUED day=%d cash=%d food=%d health=%s" % [day, cash, food, crew_health])


func use_backup() -> void:
	if transactional_mode:
		return
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
	if transactional_mode:
		_accept_transaction(progress_session.retry(),true)
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


func _accept_transaction(result: Dictionary, retryable: bool = false) -> bool:
	if result.get("state")=="BUSINESS_REJECTED":
		_progress_message = result.message
		_update_camp()
		return false
	if result.error == OK and result.get("state") in ["CAMP","ENDED"] and not result.get("camp",{}).is_empty():
		_apply_progress(result.camp)
		_progress_dirty = false
		_transactional_new_pending = false
		_allow_invalid_replacement = false
		_pending_save.clear()
		_progress_message = "事务营地已确认。隔离接线验收中；永久死亡与缺粮减员未开放。"
		if battle_mode:
			_progress_message = "隔离生存测试版：战斗阵亡持久化；死者装备闲置为暂行候选，缺粮仍阻塞。"
		if hunger_trial:
			_progress_message = "PROJECT_TEMP 隔离试运行：缺粮直接减员、冻结哈希选人；死者原武器闲置。正式默认未开放。"
		if playable_entry: _progress_message = "旅程结束，记录已保存。" if result.state=="ENDED" else "营地已保存。可整备后再次出击。"
		_update_camp()
		return true
	_progress_dirty = retryable
	_progress_blocked = true
	_progress_message = _transaction_message(result.get("reason",""))
	print("BH_TXN_BLOCK reason=%s" % result.get("reason",""))
	_update_camp()
	return false


func _transaction_message(reason: String) -> String:
	if playable_entry:
		if "WRITER" in reason: return "进度正被其他窗口使用或暂时无法保存。请关闭其他实例后重开；原件保留。"
		if "UNFINISHED_ACTION" in reason: return "上次行动中断且没有完整结算，当前无法继续。请保留进度；不会回退营地或发放战利品。"
		if "WORLD_OUTDOOR_BUILD_MISMATCH" in reason: return _suspend_problem({"reason":reason})
		if "COMPAT" in reason or "BUILD" in reason or "DAILY" in reason or "LAYOUT" in reason: return "此版本无法安全继续该途中进度。原件保留，不自动转换或回退。"
		return "进度保存或校验未完成，已阻止出击。可重试或退出；原件保留，不自动回退旧档。"
	if "HUNGER_EXPLICIT_TRIAL_REQUIRED" in reason:
		return "此旅程含暂行饥饿规则；请使用 Play-Survival -HungerTrial 并明确确认。当前入口已阻止继续，原件保留。"
	if "UNFINISHED_ACTION" in reason:
		return "上次行动中断，尚无完整结算。确认事实保留，不能恢复旧营地。请保留进度并退出；不会自动扣粮、过日或发放战利品。"
	if "POLICY_REQUIRED" in reason or "PERMADEATH" in reason:
		return "生存政策尚未开放：本次口粮或结算缺少获准处理，已阻止提交。请保留进度并退出；不会自动减员、扣血、过日或发放战利品。"
	if "BINDING" in reason or "JOURNAL" in reason or "CONFLICT" in reason:
		return "事务绑定或记录未通过检查，继续已阻止；请保留原件，不自动选择旧备份。"
	if "WRITER" in reason:
		return "进度正被其他窗口使用或无法取得写者。请关闭其他实例后重开，原件保留。"
	if "ISOLATED" in reason:
		return "此模式需要明确的隔离进度与用户目录；未进入旅程。"
	return "保存或事务确认未完成，出击已阻止；可重试或退出，原件保留。"


func _show_battle_result(snapshot: Dictionary, durable: bool) -> void:
	phase = Phase.RESULT
	_screen.show()
	_title.hide()
	_result.show()
	var ended: bool = snapshot.journey.state == "FAILED" or CampaignState.ended(snapshot)
	var victory: bool = snapshot.journey.get("campaign",{}).get("outcome")=="VICTORY"
	_set_pump_victory_visible(false)
	if _pump_details_back != null:
		_pump_details_back.hide()
	$Interface/Screen/Result/Heading.text = ("旅程胜利" if durable else "胜利预览 · 待确认保存") if victory else "旅程结束 · 全员阵亡" if ended else "幸存者归航"
	var text: String = "隔离生存测试版 / 战斗永久死亡\n"
	if snapshot.journey.seed != "NONE":
		text = "隔离演练：初始两人4HP / 食物12 / 按钮近敌36像素\n"
	for member: Dictionary in snapshot.crew:
		text += "\n%02d %s  ·  %s  ·  生命 %.0f" % [int(member.id),member.call_sign,_member_fate(snapshot, int(member.id)),member.health]
	text += "\n\n第%d天 · 货币%d · 食物%d · 存活%d人" % [int(snapshot.day),int(snapshot.cash),int(snapshot.food),snapshot.journey.active_member_ids.size()]
	text += "\n死者原武器唯一保留库存并解除配装（暂行候选）。"
	if ended:
		text += "\n全灭不是成功撤离；此旅程不能再次出击。"
		text += "\n终局已保存，重启仍为FAILED。" if durable else "\n终局保存未确认：请重试，不能开始下一旅程。"
	else:
		text += "\n完整结果已冻结；返回营地只提交一次，按存活者扣口粮。"
	if hunger_trial:
		text = _hunger_result_text(snapshot,durable)
	if playable_entry: text = _playable_result_text(snapshot,durable)
	$Interface/Screen/Result/Scroll/Body.text = text
	$Interface/Screen/Result/Scroll.scroll_vertical = 0
	$Interface/Screen/Result/Scroll/Body.add_theme_font_size_override("font_size",18 if hunger_trial else 19)
	$Interface/Screen/Result/Continue.text = ("查看旅程记录 →" if durable else "重试保存终局 →") if ended else "返回营地 →"
	_battle_new_button.visible = ended
	_battle_new_button.disabled = not durable
	_status.text = "隔离生存终局" if ended and durable else _progress_message
	if playable_entry:
		_status.text = _progress_message if _progress_blocked else ("结算已保存。" if durable else "确认结算后保存；保存失败时不会进入下一次行动。")
		$Interface/Screen/Result/Continue.text = ("查看旅程记录 →" if durable else "重试保存终局 →") if ended else "确认结算并回营 →"
		if victory and not durable and CampFacilities.enabled(snapshot):
			$Interface/Screen/Result/Heading.text = "归航待确认 · 破阵者已倒地"
			$Interface/Screen/Result/Continue.text = "确认归航并保存胜利 →" if not _progress_blocked else "重试保存终局 →"
		if victory and durable and CampaignRules.pump_station_enabled(snapshot.journey.campaign):
			_show_pump_victory(snapshot)


func _show_pump_victory(snapshot: Dictionary) -> void:
	var inspected: Dictionary = progress_session.inspect()
	var receipt: Dictionary = inspected.get("receipt", {})
	var frozen: Dictionary = receipt.get("envelope", {}).get("result", {})
	var generated: Dictionary = frozen.get("rules", {}).get("mission", {}).get("generated", {})
	var battle: Dictionary = frozen.get("battle", {})
	if inspected.error != OK or receipt.get("phase") != "COMMITTED" or receipt.get("transaction_id") != snapshot.last_settlement_id \
			or not PumpStationAction.enabled(generated) or not battle.get("evacuated", false) \
			or not PumpStationAction.stopped(battle.get("site_facts", {})) or battle.get("encounter", {}).get("defeat", {}).is_empty():
		return
	if _pump_victory == null:
		_pump_victory = PumpVictoryView.new()
		_result.add_child(_pump_victory)
		_pump_victory.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pump_victory.record_requested.connect(return_to_title)
		_pump_victory.new_journey_requested.connect(_request_battle_new_journey)
		_pump_victory.details_requested.connect(_open_pump_details)
		_pump_details_back = Button.new()
		_pump_details_back.text = "返回胜利画面"
		_result.add_child(_pump_details_back)
		_pump_details_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		_pump_details_back.offset_left = 688
		_pump_details_back.offset_right = 900
		_pump_details_back.offset_top = -84
		_pump_details_back.offset_bottom = -28
		_pump_details_back.pressed.connect(func() -> void:
			_pump_details_back.hide()
			_set_pump_victory_visible(true)
			_pump_victory.record_button.grab_focus())
		_pump_details_back.hide()
	var returned: int = battle.member_results.filter(func(member: Dictionary) -> bool: return member.health > 0.0).size()
	_pump_victory.present(int(snapshot.last_day.day), returned, _catalog_result_notice(snapshot))
	_set_pump_victory_visible(true)


func _open_pump_details() -> void:
	_set_pump_victory_visible(false)
	_pump_details_back.show()
	_pump_details_back.grab_focus()


func _set_pump_victory_visible(enabled: bool) -> void:
	if _pump_victory == null:
		return
	_pump_victory.visible = enabled
	$Interface/Screen/Result/Heading.visible = not enabled
	$Interface/Screen/Result/Scroll.visible = not enabled
	$Interface/Screen/Result/Continue.visible = not enabled
	_battle_new_button.visible = not enabled


func _hunger_policy_text() -> String:
	if playable_entry:
		return "开发试玩版：战斗阵亡不可恢复；归航时每名原出发存活者消耗1粮。每缺1粮会失去1名队员，最多至全灭。\n新救援同伴本餐不参食，下一次按实际存活者计粮；死者的原武器保留库存。\n搜刮后须发动巴士并集合存活者，确认结算才入账。中途请使用安全暂存；未保存的中断可能无法继续。\n试玩进度独立，旧档不会自动转换。"
	var rescue: String = "救援试运行：援救10秒，等获救者到达巴士后正常撤离，结算确认才加入。\n本次两人吃2粮，下次三人吃3粮。\n" if rescue_mode else ""
	if field_join_mode:
		rescue = "同场救援：援救10秒后立即参战；存活者全员撤离后登记营地。\n当餐只计算原出发存活者，下次按实际存活者计粮。\n"
	var growth: String = "个人成长试运行：真实个人击退+10XP，归航且存活才生效。\n每级当前/最大生命+5，保留伤量；Trait和食物训练未开放。\n" if growth_mode else ""
	if trait_mode:
		growth = "个人特性试运行：射击、搜集、移动仅影响本人。\n普通XP与Trait进度独立，归航且存活才升级，下次出击生效；食物训练未开放。\n"
	if pool_mode:
		rescue = "候选池救援：每次任务一名未曾招募的原创候选；本旅程历史编制最多四人（PROJECT_TEMP）。\n救援后立即参战，首餐按原出发存活者；旧途中档仍须旧包完成。\n"
	if roster_mode:
		rescue = "候选救援：最多4名存活、5条历史（PROJECT_TEMP）；阵亡后可救剩余身份补位。\n死者身份与成长保留，不复活、不复用。旧档不自动迁移。\n"
	if training_mode:
		growth = "篝火训练试运行：已确认营地中1粮换本人Trait累计进度1，按既有阈值不一定升级。\n训练不增加普通XP/HP或日期，保存后下次出击生效；缺粮风险只作静态预估。\n"
	return growth + rescue + "PROJECT_TEMP：每日每名战后存活者吃1粮，先入库战利品；每缺1粮死亡1人。\n人选使用冻结哈希排名，是Blue Hour暂行候选，非原作精确规则。\n死者原武器保留唯一实例并解除配装；战斗阵亡不再吃粮。\n无完整结果时退出可能使原旅程无法继续；已确认阵亡保留。\n领取暂存后再次崩溃且无新暂存/完整结果，仍可能失去原旅程。\n正常回营须发动巴士并集合存活者；正式政策与默认入口尚未开放。"


func _member_fate(snapshot: Dictionary, id: int) -> String:
	for death: Dictionary in snapshot.journey.deaths:
		if int(death.member_id) == id:
			return "饥饿死亡 / STARVATION" if death.cause == "STARVATION" else "战斗阵亡 / BATTLE"
	return "存活"


func _hunger_result_text(snapshot: Dictionary, durable: bool) -> String:
	# Read the published envelope, including after a fresh-process Continue. Never rerun selection.
	var state: Dictionary = progress_session.inspect()
	var frozen: Dictionary = state.get("receipt",{}).get("envelope",{}).get("result",{})
	var text: String = "任务与口粮 / PROJECT_TEMP\n"
	if rescue_mode:
		text = "救援试运行 / PROJECT_TEMP · 正式发布门禁保留\n"
		if pool_mode:
			for record: Dictionary in snapshot.recruits:
				var member: Dictionary = SurvivorRoster.member(snapshot.crew,int(record.member_id))
				text += "%s · %s；原武器唯一，按实际存活者计粮。\n" % [SurvivorRoster.definition_for(member).default_display_name,"已登记同行" if member.health>0 else "阵亡历史保留"]
		elif field_join_mode and not snapshot.recruits.is_empty() and snapshot.recruits[0].field_status == "LOST":
			text += "林知秋未能生还；死亡与原枪保留历史，没有新增营地活人。\n"
		elif snapshot.recruits.size() > 0: text += "林知秋已正式登记本旅程；自有武器唯一，下次出击按实际存活者计粮。\n"
	if field_join_mode and frozen.get("battle",{}).get("evacuated",false):
		text += "巴士撤离完成 · %d名存活同行全部到齐\n" % frozen.battle.member_results.filter(func(row: Dictionary) -> bool: return row.health > 0).size()
	var meal: Dictionary = frozen.get("food",snapshot.last_day)
	if not meal.is_empty():
		text += "参食%d人 · 库存%d + 带回%d = 可用%d · 需%d · 实耗%d · 缺口%d · 余粮%d\n" % [meal.ration_member_ids.size(),int(meal.food_before),int(meal.food_stored),int(meal.food_before)+int(meal.food_stored),int(meal.food_required),int(meal.food_consumed),int(meal.food_shortage),int(meal.food_after)]
	if growth_mode:
		text = "个人成长试运行 · PROJECT_TEMP · " + ("已保存\n" if durable else "归航成长待确认\n") + text
	var groups: Dictionary = {"存活归航":[],"本次阵亡":[],"历史阵亡":[]}
	for member: Dictionary in snapshot.crew:
		var current: bool = frozen.get("battle",{}).get("member_results",[]).any(func(row: Dictionary) -> bool: return int(row.id)==int(member.id))
		groups["存活归航" if member.health>0 else "本次阵亡" if current else "历史阵亡"].append(member)
	for heading: String in groups:
		if groups[heading].is_empty(): continue
		text += "\n"+heading+" / 成长与身份\n"
		for member: Dictionary in groups[heading]:
			if growth_mode:
				var awarded: Dictionary = GrowthRules.member_row(frozen.get("xp",{}).get("members",[]),int(member.id))
				text += "%02d %s · %s · Lv%d · %d XP (+%d) · 生命%.0f/%.0f\n" % [int(member.id),member.call_sign,_member_fate(snapshot,int(member.id)),int(member.growth.level),int(member.growth.xp_total),int(awarded.get("xp_gained",0)),member.health,GrowthRules.maximum(member)]
			else:
				text += "%02d %s · %s · 生命%.0f\n" % [int(member.id),member.call_sign,_member_fate(snapshot,int(member.id)),member.health]
	text += "\n保存与旅程状态\n任务 %s / 旅程 %s · 第%d天 · 存活%d人\n" % [frozen.get("mission_outcome","EXTRACTED" if meal.get("evacuated",false) else "FAILED"),snapshot.journey.state,int(snapshot.day),snapshot.journey.active_member_ids.size()]
	text += "冻结哈希选人；死者原武器保留库存、解除配装。饥饿不计战斗受伤。\n"
	if snapshot.journey.state == "FAILED":
		text += "返营结算后无人存活，不能再次出击。" if meal.get("evacuated",false) else "全员阵亡，不能再次出击。"
	text += "结果已保存，重启继续同一旅程。" if durable else "结果已冻结，返回只提交一次；保存失败可重试。"
	return text


func _request_battle_new_journey() -> void:
	if playable_entry and phase == Phase.RESULT:
		if not _battle_new_button.disabled and not _new_game_confirmation.visible:
			_open_opening_choice()
		return
	if phase == Phase.RESULT:
		return_to_title()
	if phase == Phase.TITLE:
		reset_demo()


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
	if training_mode:
		_training = data.training.duplicate(true)
	if battle_mode:
		_battle_meta = data.journey.duplicate(true)
		if rescue_mode: _recruits = data.recruits.duplicate(true)
		if survival_mode:
			_survival_origin = data.origin.duplicate(true)
	_requires_continue = false
	_progress_blocked = false


func _setup_progress() -> void:
	run_save = RunSave.new(progress_path)
	profile_id = RunSave.new_profile_id()
	_initialize_weapons("initial")
	var loaded: Error = ERR_UNAVAILABLE
	if transactional_mode:
		progress_session = ProductionProgress.new(progress_path,battle_mode,survival_mode,hunger_trial,rescue_mode,growth_mode,field_join_mode,trait_mode,training_mode,pool_mode,roster_mode,quality_mode,enemy_mode,playable_entry)
		progress_session.suspend_enabled = safe_suspend
		var state: Dictionary = progress_session.inspect()
		if playable_entry:
			progress_session.refresh_catalog()
		if state.error == OK and state.state == "SUSPENDED":
			_requires_continue = true
			_progress_message = "已有未完成的出击暂存。继续将恢复原战场并消费本次快照，不返回旧营地。"
		elif state.error == OK and state.state in ["CAMP","RECOVERY_READY","ENDED"]:
			_pending_save = state.camp.duplicate(true)
			_requires_continue = true
			_progress_message = "事务隔离接线：继续将核对并完成已冻结记录。死亡与缺粮规则未开放。"
			if battle_mode:
				_progress_message = "隔离生存测试版：继续核对死亡、装备与旅程；已结束旅程只可查看记录。"
		elif state.error == OK and state.state == "EMPTY":
			_progress_message = "事务隔离接线：先明确开始新旅程，基础确认后才可出击。"
			if survival_pilot:
				_progress_message = "新生存旅程（测试）使用独立进度；先确认开始并保存，再选择出击。普通旧档保持原样。"
			if survival_mode and not _migration_source.is_empty():
				_progress_blocked = true
				_progress_message = "请选择旧存档转换并预览；或明确开始独立新旅程。原档不会自动转换。"
		else:
			_progress_blocked = true
			_progress_message = _transaction_message(state.get("reason",""))
			if not state.get("confirmed_deaths",[]).is_empty():
				_progress_message += " 已确认%d名成员阵亡，记录保留；不扣粮、不进日。" % state.confirmed_deaths.size()
			print("BH_TXN_BLOCK reason=%s" % state.get("reason",""))
	else:
		loaded = run_save.load_save()
	if not transactional_mode and loaded == OK:
		_pending_save = run_save.snapshot.duplicate(true)
		_requires_continue = true
		_progress_message = "存档校验通过；继续游戏可恢复营地。新游戏需确认，不会立即覆盖。"
		if run_save.migrated_from > 0:
			_migration_notice = run_save.diagnostic
			_progress_message = _migration_notice
	elif not transactional_mode and loaded == ERR_FILE_NOT_FOUND and not run_save.has_files():
		_progress_message = "空档：可直接出击；首次回营或确认营地配装后保存。练习不保存。"
	elif not transactional_mode:
		_progress_blocked = true
		_progress_message = "读取失败：%s；原文件保留，不会自动覆盖。" % run_save.diagnostic
		var backup: RunSave = RunSave.new(progress_path)
		if backup.load_save(true) == OK:
			_backup_save = backup.snapshot.duplicate(true)
			if backup.migrated_from > 0:
				_backup_migration_notice = backup.diagnostic
		else:
			_progress_message += " 备份也不可用。"
	if playable_entry and not _progress_blocked:
		_progress_message = "发现已保存的试玩，可继续同一旅程。" if _requires_continue else "开始试玩会创建独立进度，旧档保持原样。"
	_continue_button = _progress_button("继续游戏 →", 456.0, continue_game)
	_backup_button = _progress_button("使用有效备份（上次营地）", 456.0, use_backup)
	_retry_button = _progress_button("重试保存当前营地", 540.0, save_camp)
	if transactional_mode:
		_continue_button.text = "继续 / 确认事务 →"
		if safe_suspend and _requires_continue and _pending_save.is_empty():
			_continue_button.text = "继续未完成的出击 →"
		_retry_button.text = "重试确认进度"
	$Interface/Screen/Title/Reset.text = "新游戏…"
	$Interface/Screen/Title/Start.text = "选择出击目标 →"
	_new_game_confirmation = ConfirmationDialog.new()
	_new_game_confirmation.title = "确认新游戏"
	_new_game_confirmation.ok_button_text = "确认开始新游戏"
	_new_game_confirmation.cancel_button_text = "保留进度 / 取消"
	_new_game_confirmation.confirmed.connect(_confirm_new_journey)
	_screen.add_child(_new_game_confirmation)
	if playable_entry:
		_new_game_confirmation.title = "开始新旅程"
		_new_game_confirmation.ok_button_text = "确认开始旅程"
		_new_game_confirmation.theme = CampStyle.blue_hour_theme(_screen.theme)
		_new_game_confirmation.theme.set_stylebox("panel", "AcceptDialog", CampStyle.box(CampStyle.INK, Color("48646d")))
		CampStyle.blue_hour_primary(_new_game_confirmation.get_ok_button())
		_opening_picker = OpeningBuildPicker.new()
		_new_game_confirmation.add_child(_opening_picker)
		_new_game_confirmation.canceled.connect(func() -> void:
			_opening_confirm_pending = false
			if phase == Phase.RESULT:
				_battle_new_button.grab_focus.call_deferred())
	_hunger_confirmation = ConfirmationDialog.new()
	_hunger_confirmation.title = "继续试玩前请确认" if playable_entry else "明确选择隔离饥饿试运行"
	_hunger_confirmation.dialog_text = _hunger_policy_text() + "\n继续当前旅程，不创建新旅程；只提交已有冻结结果，不重新选人。"
	_hunger_confirmation.ok_button_text = "同意暂行规则并继续"
	_hunger_confirmation.cancel_button_text = "保留原件 / 取消"
	_hunger_confirmation.confirmed.connect(func() -> void:
		_hunger_consented = true
		if _requires_continue:
			continue_game()
		else:
			open_mission_select())
	_screen.add_child(_hunger_confirmation)
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
	if quality_mode:
		for index: int in range(data.weapons.size()):
			data.weapons[index] = WeaponModifiers.baseline(data.weapons[index])
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
	$Interface/Screen/Result/Scroll/Body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_camp_backdrop = CampBackdrop.new()
	_title.add_child(_camp_backdrop)
	_title.move_child(_camp_backdrop, 0)
	$Interface/Screen/Rule.hide()
	$Interface/Screen/Brand.text = "BLUE HOUR / 归航日志"
	if hunger_trial:
		$Interface/Screen/Brand.text = "Blue Hour 暂行饥饿规则 / 隔离测试 · PROJECT_TEMP"
	if rescue_mode:
		$Interface/Screen/Brand.text = "BLUE HOUR / 首位同行 · 救援隔离试运行"
	if growth_mode:
		$Interface/Screen/Brand.text = "BLUE HOUR / 个人成长试运行 · PROJECT_TEMP"
	if field_join_mode:
		$Interface/Screen/Brand.text = "BLUE HOUR / 当场同行试运行 · PROJECT_TEMP"
	if trait_mode:
		$Interface/Screen/Brand.text = "BLUE HOUR / 救援候选试运行 · PROJECT_TEMP" if pool_mode else "BLUE HOUR / 篝火训练试运行 · PROJECT_TEMP" if training_mode else "BLUE HOUR / 独立特性试运行 · PROJECT_TEMP"
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
	if battle_mode:
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
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--show-dev-menu":
			_developer_menu = true
		if argument.begins_with("--verify-anim=") or argument.begins_with("--verify-enemy=") or argument.begins_with("--verify-quality=") or argument.begins_with("--verify-roster="):
			continue
		if argument.begins_with("--verify-rescue-pool="):
			continue
		if argument.begins_with("--verify-record-hash=") or argument == "--verify-record-process":
			continue
		if argument.begins_with("--verify-weapons=") or argument.begins_with("--verify-training=") or argument.begins_with("--verify-traits=") or argument.begins_with("--verify-camp=") or argument.begins_with("--verify-field-join=") or argument.begins_with("--verify-growth=") or argument.begins_with("--verify-rescue=") or argument.begins_with("--verify-pilot=") or argument.begins_with("--verify-hunger=") or argument.begins_with("--verify-exit=") or argument.begins_with("--verify-recovery="):
			continue
		if argument.begins_with("--verify-") and not argument.begins_with("--verify-migration=") and not argument.begins_with("--verify-battle=") and not argument.begins_with("--verify-p0d02a=") and not argument.begins_with("--verify-m401=") and not argument.begins_with("--verify-m402=") and not argument.begins_with("--verify-m403=") and not argument.begins_with("--verify-m501=") and not argument.begins_with("--verify-m502=") and not argument.begins_with("--verify-m503=") and not argument.begins_with("--verify-m5ux01=") and not argument.begins_with("--verify-m5combat02=") and not argument.begins_with("--verify-m5combat03="):
			_developer_menu = true
			_camp_open = not _requires_continue and not _progress_blocked


func _enter_camp() -> void:
	if phase != Phase.TITLE or _settings_open() or _requires_continue or _progress_blocked:
		return
	if transactional_mode and not run_save.has_files():
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
	_camp_backdrop.show_roster(battle_mode, [] if _progress_blocked else shown.get("crew",[]),
		[] if _progress_blocked or not battle_mode else shown.get("journey", {}).get("active_member_ids", []))
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
		for member_id: int in _battle_meta.get("active_member_ids",[1,2]) if battle_mode else [1,2]:
			var entry: Dictionary = SurvivorRoster.member(crew,member_id)
			camp.text += "\n%02d  %s  ·  生命 %.0f" % [member_id,entry.call_sign,float(entry.health)]
			if growth_mode:
				camp.text += "/%.0f · Lv%d · %d XP" % [GrowthRules.maximum(entry),int(entry.growth.level),int(entry.growth.xp_total)]
			if battle_mode and entry.condition == "dead":
				camp.text += " · 已阵亡"
		camp.text += "\n今日口粮 %d · %s" % [int(daily.required),"库存足够" if daily.shortage == 0 else "缺口%d，建议前往超市" % int(daily.shortage)]
		if not last_day.is_empty() and last_day.food_shortage > 0:
			camp.text += " · 上餐缺口%d已结算" % int(last_day.food_shortage) if hunger_trial else " · 损失候选%d人，未应用" % HungerOutcome.candidate(last_day).loss_count
	_status.visible = _title.visible and (transactional_mode or _progress_dirty or _progress_blocked or not _migration_notice.is_empty())
	start.visible = _camp_open
	if battle_mode:
		eyebrow.text = "隔离生存测试版 · 原v5不迁移 · 缺粮规则未开放"
		if survival_mode:
			eyebrow.text = "schema102隔离版 · v5仅明确确认转换 · 缺粮规则未开放"
		if survival_pilot:
			eyebrow.text = "新生存旅程（测试） · 独立进度 · 缺粮处置尚未开放"
		if hunger_trial:
			eyebrow.text = "Blue Hour 暂行饥饿规则 / 隔离测试 · PROJECT_TEMP"
		if rescue_mode:
			eyebrow.text = "救援试运行 · 独立schema103 · PROJECT_TEMP · 正式门禁保留"
		if growth_mode:
			eyebrow.text = "同场救援试运行 · PROJECT_TEMP · 正式门禁未开放" if field_join_mode else "成长试运行 · 旧旅程独立保留 · 正式门禁未开放"
		if _battle_meta.get("seed") == "LOW_HP_4_FOOD_12":
			eyebrow.text += " · 演练种子4HP/12食物"
		if _battle_meta.get("state") == "FAILED":
			heading.text = "旅程已结束"
			start.visible = false
		_continue_button.text = "查看已结束旅程 →" if _pending_save.get("journey",{}).get("state") == "FAILED" else "继续隔离旅程 →"
		if survival_pilot and _pending_save.get("journey", {}).get("state") != "FAILED":
			_continue_button.text = "继续生存旅程（测试） →"
		if safe_suspend and _requires_continue and _pending_save.is_empty():
			_continue_button.text = "继续未完成的出击 →"
	_roster_button.visible = _camp_open
	_loadout_button.visible = _camp_open
	_home_return.visible = _camp_open
	_continue_button.visible = not _camp_open and _requires_continue
	if is_instance_valid(_migration_entry):
		_migration_entry.visible = not _camp_open and not rescue_mode
		CampStyle.place(_migration_entry, Rect2(420 if _requires_continue or not _progress_blocked else 64,446,400,56))
	_backup_button.visible = not _camp_open and _progress_blocked and not _backup_save.is_empty()
	_home_button.visible = not _camp_open and not _requires_continue and not _progress_blocked
	_home_button.text = "返回营地 →" if run_save.has_files() else "开始旅程 →"
	if survival_pilot and not run_save.has_files():
		_home_button.text = "新生存旅程（测试） →"
	CampStyle.place(_continue_button, Rect2(64,446,320,56))
	CampStyle.place(_backup_button, Rect2(64,446,400,56))
	CampStyle.place(_home_button, Rect2(64,446,320,56))
	CampStyle.place(_retry_button, Rect2(840,556,356,44))
	reset.text = "新游戏…"
	reset.visible = not survival_pilot or run_save.has_files() or _progress_blocked
	if survival_pilot:
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
	$Interface/Screen/Title/Practice.visible = _developer_menu and _camp_open and not battle_mode
	$Interface/Screen/Title/Probe.visible = _developer_menu and _camp_open
	CampStyle.place($Interface/Screen/Title/Practice, Rect2(840,604,220,32))
	CampStyle.place($Interface/Screen/Title/Probe, Rect2(1072,604,144,32))
	$Interface/Screen/Title/Practice.add_theme_font_size_override("font_size", 14)
	$Interface/Screen/Title/Probe.add_theme_font_size_override("font_size", 14)
	if _requires_continue and not _migration_notice.is_empty():
		camp.text = "已保存：第 %d 天 · 货币 %d · 食物 %d\n旧版营地将在继续后读取，原件保留。" % [int(_pending_save.day),int(_pending_save.cash),int(_pending_save.food)]

	if playable_entry: _refresh_playable_presentation()
	if is_instance_valid(_blue_hour_title_art):
		_refresh_blue_hour_title()
	_sync_camp_scene()


func _setup_camp_scene() -> void:
	if not camp_prototype:
		return
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
	camp_scene.player_mode = playable_entry and not _developer_menu
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
		camp_scene.restore_focus.call_deferred())
	_screen.add_child(_facility_confirmation)
	camp_scene.hide()
	_camp_legacy_return = Button.new()
	_camp_legacy_return.text = "返回2D营地场景 →"
	CampStyle.place(_camp_legacy_return, Rect2(840, 604, 356, 36))
	_camp_legacy_return.pressed.connect(func() -> void:
		_camp_legacy = false
		_refresh_presentation())
	_title.add_child(_camp_legacy_return)
	_camp_legacy_return.hide()



func _offer_camp_facility(choice: String) -> void:
	var before: Dictionary = camp_snapshot()
	if not _camp_input_allowed() or not CampFacilities.can_build(before, choice):
		return
	_facility_choice = choice
	_facility_confirmation.dialog_text = "花费 %d 货币建设%s？\n本旅程建设额度仅一次，确认保存后生效。" % [CampFacilities.BUILD_COST, CampSceneView.FACILITY_NAMES[choice]]
	_facility_confirmation.popup_centered(Vector2i(540, 210))


func _confirm_camp_facility() -> void:
	var choice: String = _facility_choice
	_facility_choice = ""
	if phase != Phase.TITLE or not _camp_open or not transactional_mode or not CampSceneView.FACILITY_NAMES.has(choice):
		return
	if _accept_transaction(progress_session.edit(camp_snapshot(), {"kind": "facility", "member_id": 0, "value": choice}), true):
		_progress_message = "%s已建成，建设支出已保存。" % CampSceneView.FACILITY_NAMES[choice]
	_update_camp()
	camp_scene.restore_focus.call_deferred()


func _sync_camp_scene() -> void:
	if not _camp_scene_problem.is_empty():
		_status.text = _progress_message + "\n" + _camp_scene_problem
		_status.visible = _title.visible
	if not is_instance_valid(camp_scene):
		return
	var eligible: bool = _camp_open and phase == Phase.TITLE and not _requires_continue and not _progress_blocked and _pending_settlement.is_empty() and _battle_meta.get("state", "ACTIVE") != "FAILED"
	camp_scene.visible = eligible and not _camp_legacy
	_camp_legacy_return.visible = eligible and _camp_legacy
	if not camp_scene.visible:
		camp_scene.clear()
		return
	var data: Dictionary = camp_snapshot()
	camp_scene.refresh(data, CampEconomy.rations(day, crew, food, camp_rules), not $Interface/Screen/Title/Start.disabled, "可以选择出击目标" if not $Interface/Screen/Title/Start.disabled else ("旧版队伍状态不支持出击；请查看幸存者" if not battle_mode else "当前旅程不能出击"), _progress_message if playable_entry else "")
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
		&"weapons": open_loadout()
		&"supplies": camp_scene.open_info(action)
		&"training":
			if training_mode:
				open_training()
			else:
				camp_scene.open_info(action)
		&"sound": open_sound_settings()
		&"legacy":
			_camp_legacy = true
			_refresh_presentation()
		&"home":
			_camp_open = false
			_refresh_presentation()
		&"quit": request_exit("quit")


func _guard_camp_editor(action: Callable) -> bool:
	if not camp_prototype or not is_instance_valid(_camp_leave_dialog) or not is_instance_valid(roster_panel) or not roster_panel.visible or not roster_panel.name_edit.editable:
		return false
	var member: Dictionary = SurvivorRoster.member(crew, roster_panel.selected_member_id)
	if member.is_empty() or roster_panel.name_edit.text == member.call_sign:
		return false
	_camp_leave_action = action
	_camp_leave_dialog.popup_centered(Vector2i(620, 230))
	return true


func _camp_escape() -> bool:
	if is_instance_valid(pause_menu) and pause_menu.root.visible:
		return false
	# LineEdit consumes ui_cancel before _unhandled_input, so this scope owns its back intent.
	if not camp_prototype or phase != Phase.TITLE or _new_game_confirmation.visible or _hunger_confirmation.visible or (is_instance_valid(_camp_leave_dialog) and _camp_leave_dialog.visible):
		return false
	if is_instance_valid(training_panel) and training_panel.visible:
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
			or loadout_panel.workshop_confirmation.visible:
			return false
		close_loadout()
	elif mission_select.visible:
		close_mission_select()
	elif is_instance_valid(sound_settings) and sound_settings.visible:
		sound_settings.close_panel()
	else:
		return false
	return true


func _camp_input_allowed() -> bool:
	return not (is_instance_valid(training_panel) and training_panel.visible) and phase == Phase.TITLE and not _new_game_confirmation.visible and not _hunger_confirmation.visible and not (is_instance_valid(pause_menu) and pause_menu.root.visible) and not (is_instance_valid(_camp_leave_dialog) and _camp_leave_dialog.visible)


func _roster_training(id: int) -> void:
	if not is_instance_valid(roster_panel) or not roster_panel.visible: return
	roster_panel.hide()
	open_training()
	if is_instance_valid(training_panel) and training_panel.visible:
		training_panel.selected_member_id=id
		training_panel.refresh(camp_snapshot())

func open_training() -> void:
	if not training_mode or phase!=Phase.TITLE or not _camp_open or _settings_open() or _requires_continue or _progress_blocked or not _pending_settlement.is_empty():
		return
	if not is_instance_valid(training_panel):
		training_panel = TrainingPanel.new()
		training_panel.player_mode = playable_entry
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
	if not training_mode or phase!=Phase.TITLE or not _camp_open or not is_instance_valid(training_panel) or not training_panel.visible or _requires_continue or _progress_blocked or not _pending_settlement.is_empty():
		return
	var accepted: bool = _accept_transaction(progress_session.edit(camp_snapshot(),request),true)
	training_panel.refresh(camp_snapshot(),"训练已保存。粮食与本人Trait已同时确认；下次出击按新等级生效。" if accepted else _progress_message,_progress_blocked)
	if accepted:
		_request_audio(&"ui_confirm")


func retry_training() -> void:
	if not training_mode or not is_instance_valid(training_panel) or not training_panel.visible or not _progress_dirty:
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
	_catalog_button.text = "装备图鉴"
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
	# Presentation reads the already-frozen result; it never recalculates rewards/deaths.
	var state: Dictionary = progress_session.inspect()
	var frozen: Dictionary = state.get("receipt",{}).get("envelope",{}).get("result",{})
	var meal: Dictionary = frozen.get("food",snapshot.last_day)
	var battle: Dictionary = frozen.get("battle",{})
	var text: String = "归航结果 · 已入账\n" if durable else "归航预览 · 确认保存后入账\n"
	var catalog_notice: String = _catalog_result_notice(snapshot) if durable else ""
	if not catalog_notice.is_empty():
		text += catalog_notice + "\n"
	var generated: Dictionary = frozen.get("rules",{}).get("mission",{}).get("generated",{})
	if BillboardActionV1.enabled(generated):
		if not BillboardIntelV1.opportunity(snapshot).is_empty():
			text += "超市广告牌 · 下次选卡保证出现超市补给%s\n" % ("" if durable else "（确认后生效）")
		elif battle.get("billboard", {}).get("completed", false):
			text += "超市广告牌 · 已调查，本次未登记情报\n"
		else:
			text += "超市广告牌 · 调查未完成\n"
	if PumpStationAction.enabled(generated) and not battle.is_empty():
		if battle.encounter.defeat.is_empty():
			text += "河堤泵站 · 提前撤离，未登记胜利。\n" if battle.evacuated else "河堤泵站 · 未能归航。\n"
		else:
			text += "河堤泵站 · 已停机 · 破阵者已倒地\n"
	if snapshot.last_day.has("task") and not generated.get("campaign",{}).get("is_finale",false):
		var title: String = ""
		if generated.get("mission_policy") == 1:
			if generated.has("rare_policy"):
				title = RareSortie.title(generated.type)
			elif generated.has("investigation"):
				title = "调查 · " + CampaignRules.CLUE_NAMES[generated.investigation.clue_id]
			elif generated.type == "airdrop":
				title = "装备 · 露天回收"
		var task: Dictionary = snapshot.last_day.task
		text += TaskActions.summary_text(task, title) + "\n"
		if task.type == "event_sortie":
			var reward: String = "0 粮 · 0 币"
			if task.branch == EventSortieV1.QUIET:
				reward = "%s%d 粮" % ["+" if task.event_food > 0 else "", int(task.event_food)]
			elif task.branch == EventSortieV1.FORCE:
				reward = "%s%d 币" % ["+" if task.event_cash > 0 else "", int(task.event_cash)]
			text += "%s · 本次事件收益\n%s · %s\n" % [EventSortieV1.TITLE, EventSortiePanel.branch_title(task.branch), reward]
	if not meal.is_empty():
		text += ReturnFeedback.food_text(meal) + "\n"
		if meal.food_shortage > 0:
			text += "本次口粮缺口 %d 粮\n" % meal.food_shortage
	text += "带回 %d 币 · %d 件武器\n" % [snapshot.last_day.cash_gained, battle.get("weapons", []).size()]
	if not WorkshopSiteV1.site_id(generated).is_empty():
		var gained: int = int(WorkshopV1.recovered(generated, battle))
		text += "本次工具箱 ×%d · %s %d\n" % [gained, "营地库存" if durable else "确认后库存", WorkshopV1.tools(snapshot)]
	var ended: bool = snapshot.journey.state == "FAILED" or CampaignState.ended(snapshot)
	if not ended:
		var next_rations: Dictionary = CampEconomy.rations(snapshot.day, snapshot.crew, snapshot.food, camp_rules)
		if next_rations.shortage > 0:
			text += "下一趟口粮缺口 %d 粮，可优先选择补给。\n" % next_rations.shortage
		if battle.get("weapons", []).any(func(item: Dictionary) -> bool: return item.condition == "damaged"):
			text += "损坏武器可在营地武器整备中先维修，再配装。\n"
	if BuildState.enabled(snapshot) and int(frozen.get("rules",{}).get("data_version",0)) in [8,9,10]:
		var obtained: Array=BuildState.acquired(frozen.rules.mission.generated,battle.site_facts,battle.evacuated)
		var names: PackedStringArray=[]
		for item: String in obtained: names.append(generated.build.policy.items[item].name)
		text+="本次道具："+("、".join(names) if not names.is_empty() else "无")+" · 本局库存%d/%d（"%[snapshot.journey.build.owned.size(), BuildItems.ids(BuildState.pool(snapshot)).size()]+("已保存" if durable else "确认后入库")+"）\n"
	if PowerState.enabled(snapshot) and not battle.is_empty():
		var sample: String=generated.powers.sample if battle.evacuated and battle.site_facts.get("cash",{}).get("searched",false) else ""
		var inventory: Dictionary = snapshot.journey.build.powers
		var count: int = SpecialPowers.policy(int(inventory.version)).size()
		text+="本次能力："+(PowerActions.name_for(sample) if not sample.is_empty() else "无")+" · 本旅程%d/%d（"%[inventory.owned.size(),count]+("已保存" if durable else "确认后入库")+"）\n"
	for item: Dictionary in battle.get("weapons",[]):text+="带回武器："+WeaponInventory.loot_description(item)+"\n"
	if CampaignState.is_short(snapshot):
		var campaign: Dictionary = snapshot.journey.campaign
		var recorded: Dictionary = campaign
		if CampaignRules.is_investigation(campaign):
			if not durable:
				recorded = camp_snapshot().journey.campaign
			if not campaign.clues.is_empty():
				var clue: Dictionary = campaign.clues.back()
				if clue.transaction_id == snapshot.last_settlement_id:
					text += "调查线索：%s（%s）\n" % [CampaignRules.CLUE_NAMES[clue.id], "已登记" if durable else "确认后登记"]
		var display: Dictionary = CampaignRules.display(recorded)
		text += display.title + " · " + display.progress + "\n"
		if campaign.outcome == "VICTORY":
			text += "首领真实击败、存活者巴士撤离；" + ("旅程胜利已保存。" if durable else "胜利仅为预览，确认保存成功才结束旅程。") + "\n"
	for member: Dictionary in snapshot.crew:
		var awarded: Dictionary = GrowthRules.member_row(frozen.get("xp",{}).get("members",[]),int(member.id))
		var fate: String = _member_fate(snapshot,int(member.id)).replace(" / STARVATION", "").replace(" / BATTLE", "")
		text += "\n%02d %s · %s · 生命%.0f/%.0f\nLv%d · %d XP（本次+%d）\n" % [member.id,member.call_sign,fate,member.health,GrowthRules.maximum(member),member.growth.level,member.growth.xp_total,awarded.get("xp_gained",0)]
	text += "\n营地：第%d天 · 货币%d · 存活%d人\n" % [snapshot.day,snapshot.cash,snapshot.journey.active_member_ids.size()]
	text += "旅程已结束，不能再次出击。" if ended else "确认结算后可回营整备，再次出击。"
	return text


func _catalog_result_notice(snapshot: Dictionary) -> String:
	if not snapshot.journey.get("build", {}).has("catalog"):
		return ""
	var catalog: Dictionary = progress_session.catalog_state()
	if catalog.get("error", FAILED) != OK:
		return "装备图鉴待同步 · 可重启补记"
	if catalog.unlock.get("receipt", {}).get("transaction_id") == snapshot.last_settlement_id:
		return "已解锁 · 滤毒面罩"
	return ""


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
		_catalog_button.grab_focus()
	elif phase == Phase.RESULT:
		_show_battle_result(camp_snapshot(), true)
		if _pump_victory != null and _pump_victory.visible:
			_pump_victory.new_journey_button.grab_focus()
		else:
			_battle_new_button.grab_focus()


func equip_build_item(slot: int, item: String) -> void:
	if phase!=Phase.TITLE or not loadout_panel.visible or _progress_blocked or not BuildState.enabled(camp_snapshot()): return
	var saved: bool=_accept_transaction(progress_session.edit(camp_snapshot(),{"kind":"build_slot","member_id":slot,"value":item}),true)
	loadout_panel.refresh(camp_snapshot(),"本局道具配装已保存；下一行动生效。" if saved else _progress_message)
	if not saved:
		var build: Dictionary = camp_snapshot().journey.build
		loadout_panel.build_panel.present(build.owned, build.slots, false, false,
			build.get("opening", {}).get("plan", ""), BuildState.pool(camp_snapshot()))

func equip_power(id: String, slot: int = 0) -> void:
	var camp: Dictionary = camp_snapshot()
	if not PowerState.enabled(camp):
		return
	var kind: String = "power_equip" if PowerState.progression(camp.journey.build.powers) else "power_slot"
	_edit_power({"kind":kind,"member_id":slot,"value":id}, "特殊能力装配已保存；下次出击生效。")


func invest_power(choice: String) -> void:
	_edit_power({"kind":"power_invest","member_id":0,"value":choice}, "能力投资已保存；余额与效果已更新。")


func _edit_power(request: Dictionary, success: String) -> void:
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible or _progress_blocked:
		return
	var saved: bool = _accept_transaction(progress_session.edit(camp_snapshot(),request),true)
	loadout_panel.refresh(camp_snapshot(),success if saved else _progress_message,_progress_dirty)
	if _progress_dirty:
		loadout_panel.power_panel.retry_button.grab_focus()


func retry_power_edit() -> void:
	if phase != Phase.TITLE or not is_instance_valid(loadout_panel) or not loadout_panel.visible or not _progress_dirty:
		return
	var saved: bool = _accept_transaction(progress_session.retry(),true)
	loadout_panel.refresh(camp_snapshot(),"本次整备已保存；余额与状态已更新。" if saved else _progress_message,not saved)
