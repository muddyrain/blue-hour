class_name AppSession
extends RefCounted

var app: AppMain


func _init(owner: AppMain) -> void:
	app = owner


func _setup_progress(preloaded_state: Dictionary = {}) -> void:
	app.run_save = RunSave.new(app.progress_path)
	app.profile_id = RunSave.new_profile_id()
	app._initialize_weapons("initial")
	var loaded: Error = ERR_UNAVAILABLE
	var state: Dictionary = preloaded_state
	if state.is_empty():
		app.progress_session = app._create_progress_session()
		state = app.progress_session.inspect()
		app.progress_session.refresh_catalog()
	if state.error == OK and state.state == "SUSPENDED":
		app._requires_continue = true
		app._progress_message = "已有未完成的出击暂存。继续将恢复原战场并消费本次快照，不返回旧营地。"
	elif state.error == OK and state.state in ["CAMP","RECOVERY_READY","ENDED"]:
		app._pending_save = state.camp.duplicate(true)
		app._requires_continue = true
		app._progress_message = "事务隔离接线：继续将核对并完成已冻结记录。死亡与缺粮规则未开放。"
		app._progress_message = "隔离生存测试版：继续核对死亡、装备与旅程；已结束旅程只可查看记录。"
	elif state.error == OK and state.state == "EMPTY":
		app._progress_message = "事务隔离接线：先明确开始新旅程，基础确认后才可出击。"
		app._progress_message = "新生存旅程（测试）使用独立进度；先确认开始并保存，再选择出击。普通旧档保持原样。"
	else:
		app._progress_blocked = true
		app._progress_message = app._transaction_message(state.get("reason",""))
		if not state.get("confirmed_deaths",[]).is_empty():
			app._progress_message += " 已确认%d名成员阵亡，记录保留；不扣粮、不进日。" % state.confirmed_deaths.size()
		print("BH_TXN_BLOCK reason=%s" % state.get("reason",""))
	if not app._progress_blocked:
		app._progress_message = "发现已保存的试玩，可继续同一旅程。" if app._requires_continue else "开始试玩会创建独立进度，旧档保持原样。"
	app._continue_button = app._progress_button("继续游戏 →", 456.0, app.continue_game)
	app._backup_button = app._progress_button("使用有效备份（上次营地）", 456.0, app.use_backup)
	app._retry_button = app._progress_button("重试保存当前营地", 540.0, app.save_camp)
	app._continue_button.text = "继续 / 确认事务 →"
	if app._requires_continue and app._pending_save.is_empty():
		app._continue_button.text = "继续未完成的出击 →"
	app._retry_button.text = "重试确认进度"
	app.get_node("Interface/Screen/Title/Reset").text = "新游戏…"
	app.get_node("Interface/Screen/Title/Start").text = "选择出击目标 →"
	app._new_game_confirmation = ConfirmationDialog.new()
	app._new_game_confirmation.title = "确认新游戏"
	app._new_game_confirmation.ok_button_text = "确认开始新游戏"
	app._new_game_confirmation.cancel_button_text = "保留进度 / 取消"
	app._new_game_confirmation.confirmed.connect(app._confirm_new_journey)
	app._screen.add_child(app._new_game_confirmation)
	app._new_game_confirmation.title = "开始新旅程"
	app._new_game_confirmation.ok_button_text = "确认开始旅程"
	app._new_game_confirmation.theme = CampStyle.blue_hour_theme(app._screen.theme)
	app._new_game_confirmation.theme.set_stylebox("panel", "AcceptDialog", CampStyle.box(CampStyle.INK, Color("48646d")))
	app._new_game_confirmation.theme.set_constant("buttons_min_height", "AcceptDialog", 42)
	CampStyle.blue_hour_primary(app._new_game_confirmation.get_ok_button())
	app._opening_picker = OpeningBuildPicker.new()
	app._new_game_confirmation.add_child(app._opening_picker)
	app._new_game_confirmation.canceled.connect(func() -> void:
		app._opening_confirm_pending = false
		if app.phase == app.Phase.RESULT:
			app._battle_new_button.grab_focus.call_deferred())
	app._hunger_confirmation = ConfirmationDialog.new()
	app._hunger_confirmation.title = "继续试玩前请确认"
	app._hunger_confirmation.dialog_text = app._hunger_policy_text() + "\n继续当前旅程，不创建新旅程；只提交已有冻结结果，不重新选人。"
	app._hunger_confirmation.ok_button_text = "同意暂行规则并继续"
	app._hunger_confirmation.cancel_button_text = "保留原件 / 取消"
	app._hunger_confirmation.confirmed.connect(func() -> void:
		app._hunger_consented = true
		if app._requires_continue:
			app.continue_game()
		else:
			app.open_mission_select())
	app._screen.add_child(app._hunger_confirmation)
	app._status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	app._status.offset_right = 1232.0
	app._status.offset_bottom = 714.0
	var camp_label: Label = app.get_node("Interface/Screen/Title/Camp")
	camp_label.offset_top = 362.0
	camp_label.offset_bottom = 450.0
	camp_label.add_theme_font_size_override("font_size", 16)
	var description: Label = app.get_node("Interface/Screen/Title/Description")
	description.offset_top = 300.0
	description.offset_bottom = 352.0
	description.text = "搜集补给和武器后回营，维修、配装再出击；装备与营地进度一同保存。\n原作缺粮可能减员；本版损失候选尚未应用，触发与选人仍待校准。"


func _create_progress_session() -> ProductionProgress:
	var session: ProductionProgress = ProductionProgress.new(app.progress_path, true, true, true, true, true, true, true, true, true, true, true, true, true)
	session.suspend_enabled = true
	return session


func _has_progress_sources() -> bool:
	var absolute: String = ProjectSettings.globalize_path(app.progress_path)
	var directory: DirAccess = DirAccess.open(absolute.get_base_dir())
	if directory == null:
		return false
	var prefix: String = absolute.get_file()
	for entry: String in directory.get_files():
		if entry == prefix or entry.begins_with(prefix + "."):
			return true
	for entry: String in directory.get_directories():
		if entry.begins_with(prefix + "."):
			return true
	return false


func _show_startup_verification() -> void:
	app._startup_overlay = PanelContainer.new()
	app._startup_overlay.name = "StartupVerification"
	app._startup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app._startup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	app._startup_overlay.z_index = 4000
	app._startup_overlay.theme = CampStyle.blue_hour_theme(app._screen.theme)
	app._startup_overlay.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.INK, Color("48646d")))
	app._startup_label = Label.new()
	app._startup_label.text = "正在核验旅程与资料…\n完成后可继续同一旅程。"
	app._startup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app._startup_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	app._startup_label.add_theme_font_size_override("font_size", 24)
	app._startup_overlay.add_child(app._startup_label)
	app._screen.add_child(app._startup_overlay)


func _apply_progress(data: Dictionary) -> void:
	app._camp_open = true
	app.profile_id = data.profile_id
	app.day = int(data.day)
	app.cash = int(data.cash)
	app.food = int(data.food)
	app.last_day = data.last_day.duplicate(true)
	app.weapons.assign(data.weapons.duplicate(true))
	app.loadout.assign(data.loadout.duplicate(true))
	app.camp_spending = int(data.camp_spending)
	app.settled_sorties = int(data.settled_sorties)
	app.last_settlement_id = data.last_settlement_id
	app.crew.assign(data.crew.duplicate(true))
	app._training = data.training.duplicate(true)
	app._battle_meta = data.journey.duplicate(true)
	app._recruits = data.recruits.duplicate(true)
	app._survival_origin = data.origin.duplicate(true)
	app._requires_continue = false
	app._progress_blocked = false


func _initialize_weapons(origin: String) -> void:
	var data: Dictionary = {"profile_id":app.profile_id, "crew":[{"id":1,"health":app.crew_health[0]}, {"id":2,"health":app.crew_health[1]}]}
	WeaponInventory.initialize(data, origin)
	for index: int in range(data.weapons.size()):
		data.weapons[index] = WeaponModifiers.baseline(data.weapons[index])
	app.weapons.assign(data.weapons)
	app.loadout.assign(data.loadout)
	app.camp_spending = 0


func _progress_button(label: String, y: float, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.position = Vector2(868.0, y)
	button.size = Vector2(328.0, 60.0 if y == 456.0 else 48.0)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	app._title.add_child(button)
	return button


func continue_game() -> void:
	if app.phase != app.Phase.TITLE or app._settings_open() or not app._requires_continue:
		return
	if not app._hunger_consented:
		app._hunger_confirmation.popup_centered(Vector2i(700,260))
		return
	var inspected: Dictionary = app.progress_session.inspect()
	if inspected.error == OK and inspected.state == "SUSPENDED":
		var offer: Dictionary = app.progress_session.resume_offer()
		if offer.error != OK:
			app._accept_transaction(offer)
			return
		app._apply_progress(offer.receipt.base)
		app.selected_supply = SortieSnapshot.supply_for_world(offer.receipt.envelope.world)
		app._requires_continue = false
		app._progress_blocked = false
		app._open_sortie(offer)
		return
	if app._accept_transaction(app.progress_session.activate(),true):
		app._request_audio(&"ui_confirm")
		if (app._battle_meta.state == "FAILED" or CampaignState.ended(app.camp_snapshot())):
			app._show_battle_result(app.camp_snapshot(),true)
	return


func use_backup() -> void:
	return


func save_camp() -> void:
	if app.phase != app.Phase.TITLE or not app._progress_dirty:
		return
	app._accept_transaction(app.progress_session.retry(),true)
	return


func camp_snapshot() -> Dictionary:
	var snapshot: Dictionary = {"schema_version":RunSave.SCHEMA_VERSION, "profile_id":app.profile_id,
		"day":app.day, "cash":app.cash, "settled_sorties":app.settled_sorties,
		"food":app.food,"last_day":app.last_day.duplicate(true),
		"weapons":app.weapons.duplicate(true), "loadout":app.loadout.duplicate(true), "camp_spending":app.camp_spending,
		"last_settlement_id":app.last_settlement_id,
		"crew":app.crew.duplicate(true)}
	return EnemyState.snapshot(snapshot, app._battle_meta, app._recruits, app._training)


func _accept_transaction(result: Dictionary, retryable: bool = false) -> bool:
	if result.get("state")=="BUSINESS_REJECTED":
		app._progress_message = result.message
		app._update_camp()
		return false
	if result.error == OK and result.get("state") in ["CAMP","ENDED"] and not result.get("camp",{}).is_empty():
		app._apply_progress(result.camp)
		app._progress_dirty = false
		app._transactional_new_pending = false
		app._allow_invalid_replacement = false
		app._pending_save.clear()
		app._progress_message = "事务营地已确认。隔离接线验收中；永久死亡与缺粮减员未开放。"
		app._progress_message = "隔离生存测试版：战斗阵亡持久化；死者装备闲置为暂行候选，缺粮仍阻塞。"
		app._progress_message = "PROJECT_TEMP 隔离试运行：缺粮直接减员、冻结哈希选人；死者原武器闲置。正式默认未开放。"
		app._progress_message = "旅程结束，记录已保存。" if result.state=="ENDED" else "营地已保存。可整备后再次出击。"
		app._update_camp()
		return true
	app._progress_dirty = retryable
	app._progress_blocked = true
	app._progress_message = app._transaction_message(result.get("reason",""))
	print("BH_TXN_BLOCK reason=%s" % result.get("reason",""))
	app._update_camp()
	return false


func _transaction_message(reason: String) -> String:
	if "WRITER" in reason: return "进度正被其他窗口使用或暂时无法保存。请关闭其他实例后重开；原件保留。"
	if "UNFINISHED_ACTION" in reason: return "上次行动中断且没有完整结算，当前无法继续。请保留进度；不会回退营地或发放战利品。"
	if "WORLD_OUTDOOR_BUILD_MISMATCH" in reason: return app._suspend_problem({"reason":reason})
	if "COMPAT" in reason or "BUILD" in reason or "DAILY" in reason or "LAYOUT" in reason: return "此版本无法安全继续该途中进度。原件保留，不自动转换或回退。"
	return "进度保存或校验未完成，已阻止出击。可重试或退出；原件保留，不自动回退旧档。"


func reset_demo() -> void:
	if app.phase != app.Phase.TITLE or app._settings_open():
		return
	if app._progress_dirty:
		app._progress_message = "当前保存或冻结结果尚未确认；请先重试，不能切换到新旅程。"
		app._update_camp()
		return
	app._open_opening_choice()
	return


func _pool_initial() -> Dictionary:
	return EnemyState.initial()


func _new_game(opening_plan: String = "", catalog_policy: Dictionary = {}, m47_policy: Dictionary = {}) -> void:
	if not opening_plan.is_empty() and (not OpeningBuild.PLANS.has(opening_plan)):
		return
	app._recruits = []
	if app._transactional_new_pending:
		app._progress_message = "新旅程基础尚未确认，请先重试保存或退出。"
		app._update_camp()
		return
	app._camp_open = true
	app._hunger_consented = true
	app.cash = CampRules.INITIAL_CASH
	app.day = 2
	app.crew = SurvivorRoster.new_crew()
	GrowthRules.initialize(app.crew)
	TraitRules.initialize(app.crew)
	TrainingState.initialize(app.crew)
	app._training = []
	app.settled_sorties = 0
	app.food = app.camp_rules.initial_food
	app._battle_meta = app._pool_initial()
	app._survival_origin = {}
	app.last_day = {}
	app._pending_settlement = {}
	app.profile_id = RunSave.new_profile_id()
	app._battle_meta.campaign = CampaignRules.initial_mission(app.profile_id, true, true, true, true,
		true, true, true, true, true, true)
	CampFacilities.enable_tier_two(app._battle_meta.campaign)
	app._battle_meta.campaign.night_hound_policy = NightHoundV1.VERSION
	app._battle_meta.campaign.workshop = WorkshopV1.initial()
	app._battle_meta.campaign.event_sortie_policy = EventSortieV1.VERSION
	app._battle_meta.campaign.recon_policy = ReconActionV1.SOURCE_VERSION
	app._battle_meta.campaign.barricade_policy = BarricadeV1.VERSION
	app._battle_meta.campaign.billboard_policy = BillboardActionV1.VERSION
	app._battle_meta.campaign.open_streets_policy = OpenStreetsV1.VERSION
	app._battle_meta.build=WorldgenState.initial_build(app._battle_meta.seed, true, true)
	app._battle_meta.campaign.economy = EconomyBuildV1.initial()
	app._battle_meta.build.powers = PowerState.initial_progression(SpecialPowers.M48_VERSION)
	BuildState.enable_m48(app._battle_meta.build)
	if not opening_plan.is_empty():
		var starter: Dictionary = OpeningBuild.source(opening_plan, app.profile_id, app._battle_meta.root_id, app._battle_meta.seed, m47_policy)
		app._battle_meta.build.opening = starter
		app._battle_meta.build.owned.append(starter.item_id)
		app._battle_meta.build.slots[0] = starter.item_id
		app._battle_meta.build.catalog = catalog_policy.duplicate(true)
	app._initialize_weapons("initial")
	app.last_settlement_id = ""
	app._pending_save.clear()
	app._backup_save.clear()
	app._requires_continue = false
	app._progress_blocked = false
	app._progress_dirty = false
	app._allow_invalid_replacement = true
	app._progress_message = "新游戏尚未保存；正式回营或确认营地配装后保存。"
	app._transactional_new_pending = true
	app._accept_transaction(app.progress_session.create(app.camp_snapshot()),true)
	app._update_camp()
	app._request_audio(&"ui_confirm")


func _confirm_new_journey() -> void:
	if app._opening_confirm_pending:
		app._opening_confirm_pending = false
		var catalog: Dictionary = app.progress_session.refresh_catalog()
		if catalog.error != OK:
			app._show_equipment_catalog(catalog)
			return
		if app.phase == app.Phase.RESULT:
			app.return_to_title()
		if app.phase == app.Phase.TITLE:
			var plan: String = app._opening_picker.selected_plan
			var policy: Dictionary = {"version":OpeningBuild.POLICY_VERSION, "eligible":CatalogProgress.eligible_for(catalog, plan)}
			app._new_game(plan, {"version":CatalogProgress.VERSION, "unlock":catalog.unlock_hash}, policy)


func _open_opening_choice() -> void:
	app._opening_picker.present(app.progress_session.catalog_state())
	app._opening_picker.reset_choice()
	app._opening_confirm_pending = true
	app._new_game_confirmation.popup_centered(Vector2i(950, 496))
	app._opening_picker.link_focus.call_deferred(app._new_game_confirmation.get_ok_button(), app._new_game_confirmation.get_cancel_button())


func _boot_session() -> void:
	app.get_tree().auto_accept_quit = false
	app.get_window().close_requested.connect(func() -> void: app.request_exit("quit"))
	var entry: Dictionary = PlayableEntry.resolve(OS.get_cmdline_user_args())
	var launch_arguments: Array[String] = entry.arguments
	app.progress_path = entry.progress
	app.audio_settings_path = entry.audio
	GrowthRules.initialize(app.crew)
	TraitRules.initialize(app.crew)
	TrainingState.initialize(app.crew)
	app._training = []
	app._battle_meta = app._pool_initial()
	for argument: String in launch_arguments:
		if argument.begins_with("--bh-audio-settings="):
			app.audio_settings_path = argument.trim_prefix("--bh-audio-settings=")
		if argument.begins_with("--bh-progress="):
			app.progress_path = argument.trim_prefix("--bh-progress=")
	var startup_state: Dictionary = {}
	if DisplayServer.get_name() != "headless" and app._has_progress_sources():
		app._startup_pending = true
		app._show_startup_verification()
		# Paint before acquiring the writer or hashing existing source files.
		await app.get_tree().process_frame
		await app.get_tree().process_frame
		app.progress_session = app._create_progress_session()
		app._startup_worker = Thread.new()
		if app._startup_worker.start(app._inspect_startup.bind(app.progress_session)) == OK:
			while app._startup_worker.is_alive():
				await app.get_tree().process_frame
			startup_state = app._startup_worker.wait_to_finish()
		else:
			startup_state = app._inspect_startup(app.progress_session)
		app._startup_worker = null
	app._setup_progress(startup_state)
