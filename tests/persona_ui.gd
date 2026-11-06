extends SceneTree
## Controlled layout only. Camp/recipes are pure legal initializers; candidate DTOs
## are projected into labelled field rows. This proves no recruitment or journey.

const MAIN: PackedScene = preload("res://src/app/main.tscn")
const HUD_SCENE: PackedScene = preload("res://src/features/expedition_hud/expedition_hud.tscn")
const HUD_THEME: Theme = preload("res://assets/ui/c1/hud_theme.tres")
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1024, 640)]
const LONG_NAME: String = "晚风穿过街角等待你的归来"

var output: String = ""
var checks: Array[Dictionary] = []
var cases: Array[Dictionary] = []
var camp_cases: Array[Dictionary] = []
var failures: int = 0
var base: Dictionary = {}
var source_hash: String = ""


func _initialize() -> void:
	root.unfocusable = true
	call_deferred("run")


func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--persona-output="):
			output = argument.trim_prefix("--persona-output=").replace("\\", "/").simplify_path()
	if not output.is_empty():
		var allowed: String = ProjectSettings.globalize_path("res://.local/m12-survivor-01").replace("\\", "/").simplify_path() + "/"
		if not output.is_absolute_path() or not output.begins_with(allowed) or DisplayServer.get_name() == "headless" or FileAccess.file_exists(output.path_join("report.json")) or FileAccess.file_exists(output.path_join("controlled-persona-4p.png")):
			printerr("PERSONA_UI_ARGUMENTS require native renderer and fresh absolute .local/m12-survivor-01 output")
			quit(2)
			return
		if DirAccess.make_dir_recursive_absolute(output) != OK:
			printerr("PERSONA_UI_OUTPUT cannot create isolated output")
			quit(2)
			return
	base = camp_fixture()
	source_hash = SurvivalContracts.fingerprint(base)
	check(TransactionReceipt.camp_problem(base).is_empty() and PersonaState.enabled(base), "pure original initializers supply a legal persona camp")
	check(LONG_NAME.length() == 12, "long-name UI sample is exactly twelve Chinese characters")
	if failures == 0:
		for size: Vector2i in SIZES:
			for count: int in [2, 3, 4]:
				await scenario(size, count)
		for size: Vector2i in SIZES:
			await camp_scenario(size)
	check(cases.size() == 6, "all six requested UI scenarios reached completion")
	check(camp_cases.size() == SIZES.size(), "both independent camp layout scenarios reached completion")
	check(SurvivalContracts.fingerprint(base) == source_hash, "read-only UI/candidate projection preserves the original legal camp")
	var report: Dictionary = {"scope":"controlled read-only layout fixture; not journey, recruitment, death, persistence or physical-input proof", "source":"pure legal initial camp; extra identities use the existing candidate projection, never a recruited roster", "display_overrides":["field DTO scope", "same names", "twelve-character name", "dead DTO"], "input_level":"GUI APIs, focus and STOP properties; no physical/OS input", "renderer":DisplayServer.get_name(), "checks":checks, "cases":cases, "camp_cases":camp_cases, "failures":failures}
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
		if file == null:
			check(false, "write isolated persona UI report")
			report.failures = failures
		else:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	print("PERSONA_UI " + JSON.stringify(report))
	quit(1 if failures else 0)


func scenario(size: Vector2i, count: int) -> void:
	var tag: String = "%dx%d/%dp" % [size.x, size.y, count]
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	var background: ColorRect = ColorRect.new()
	background.color = Color("30454d")
	background.size = Vector2(size)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(background)
	var layer: CanvasLayer = CanvasLayer.new()
	viewport.add_child(layer)
	var hud: C1ExpeditionHud = HUD_SCENE.instantiate() as C1ExpeditionHud
	hud.theme = HUD_THEME
	layer.add_child(hud)
	var ids: Array[int] = [1, 2]
	if count >= 3:
		ids.append(4)
	if count == 4:
		ids.append(5)
	var rows: Array[Dictionary] = []
	for id: int in ids:
		var model: Dictionary = PersonaViewModel.camp(base, id, "camp" if id <= 2 else "candidate")
		if model.is_empty():
			check(false, tag + " original model projection for identity %d" % id)
			viewport.queue_free()
			await process_frame
			return
		# These are explicit read-only display variants, never modifications to a camp.
		model.scope = "field"
		model.editable = false
		if id <= 2:
			model.name = "同名队员"
		elif id == 4:
			model.name = LONG_NAME
		if id == 5:
			model.alive = false
			model.hp = 0.0
			model.status = "阵亡 · 只读历史"
		else:
			model.status = SearchWorkView.actor_status("working" if id == 1 else "approach", SearchWorkView.short_site("街角便利店", id), false)
		rows.append({"id":id, "persona":model})
	hud.refresh({"mission_title":"受控布局样本", "objective":"只读字段排布，不运行任务", "day_text":"第 2 天", "search_progress_text":"0 / 3", "defeated_text":"0", "currency_text":"53", "resource_text":"货币 53 · 食物 2\n携带：钱0 · 粮0 · 武器0", "survivors":rows, "time":{"label":"界面样本", "text":"01:36", "hint":"威胁 · 平稳"}, "bus_status_text":"巴士准备 20 秒", "bus_action_label":"巴士准备 20 秒", "bus_action_enabled":false, "status_hint":"受控布局：同名、长名、ID空洞与阵亡档案"})
	await settle()
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(size)).grow(0.5)
	var panel: Control = hud.get_node("MembersPanel") as Control
	check(bounds.encloses(panel.get_global_rect()) and hud._persona_cards.size() == count, tag + " actual persona member panel stays inside viewport")
	var identities: Array[int] = []
	var card_metrics: Array[Dictionary] = []
	var all_reachable: bool = true
	var compact: bool = true
	var chinese: bool = true
	for index: int in range(count):
		var card: PersonaCard = hud._persona_cards[index]
		var id: int = int(rows[index].id)
		identities.append(id)
		hud._member_scroll.ensure_control_visible(card)
		await settle()
		var client: Rect2 = scroll_client(hud._member_scroll).grow(0.5)
		var rect: Rect2 = card.get_global_rect()
		all_reachable = all_reachable and client.encloses(rect) and bounds.encloses(rect)
		compact = compact and card.size.y <= 124.5 and card.size.x <= 242.0
		chinese = chinese and chinese_supported(card.primary_label) and chinese_supported(card.positive_label) and chinese_supported(card.negative_label)
		var model: Dictionary = rows[index].persona
		var names_match: bool = card.primary_label.text == model.primary_short and card.name_label.tooltip_text.contains(model.name) and card.positive_label.text == "＋" + model.positive.name and card.negative_label.text == "－" + model.negative.name
		all_reachable = all_reachable and names_match
		card_metrics.append({"id":id, "rect":rect_values(rect), "client":rect_values(client), "full_name":model.name, "primary":card.primary_label.text, "positive":card.positive_label.text, "negative":card.negative_label.text, "hp":card.health_label.text, "ammo":card.ammo_label.text})
	check(identities == ids and all_reachable, tag + " every stable identity and full trait/name explanation is reachable through actual member scroll")
	check(compact and chinese, tag + " compact cards stay bounded and Chinese glyphs are available")
	# Native GUI focus plus actual existing button signal, not an OS-input claim.
	var chosen: PersonaCard = hud._persona_cards[count - 1]
	chosen.info_button.grab_focus()
	chosen.info_button.pressed.emit()
	await settle()
	var details: PersonaDetails = hud.persona_details
	check(details.visible and hud._persona_id == ids[-1] and bounds.encloses(details.get_global_rect()) and details.name_label.text.contains(rows[-1].persona.name), tag + " actual card selection opens the matching bounded details")
	check(details.mouse_filter == Control.MOUSE_FILTER_STOP and not details.mouse_force_pass_scroll_events and details.scroll.mouse_filter == Control.MOUSE_FILTER_STOP and not details.scroll.mouse_force_pass_scroll_events, tag + " detail root and scroll own click/wheel boundaries")
	check(not details.equipment_button.visible and not details.training_button.visible and details.scope_label.text.contains("行动继续") and chinese_supported(details.primary_label), tag + " field details remain read-only and state the continuing clock")
	var dead: Dictionary = rows[-1].persona.duplicate(true)
	dead.scope = "camp"
	dead.alive = false
	dead.hp = 0.0
	dead.editable = true
	dead.status = "阵亡 · 只读历史"
	details.present(dead)
	await settle()
	check(not details.equipment_button.visible and not details.training_button.visible and details.scope_label.text.contains("阵亡"), tag + " dead history never exposes equipment or training even with editable DTO")
	var candidate: Dictionary = rows[-1].persona.duplicate(true)
	candidate.scope = "candidate"
	candidate.alive = true
	candidate.editable = true
	details.present(candidate)
	await settle()
	check(not details.equipment_button.visible and not details.training_button.visible and details.scope_label.text.contains("尚未接纳"), tag + " candidate view exposes no camp editing")
	var current: Dictionary = rows[mini(2, count - 1)].persona
	details.present(current)
	details.grab_focus()
	details.sources_button.pressed.emit()
	await settle()
	check(details.sources_label.visible and not details.sources_label.text.is_empty() and bounds.encloses(details.get_global_rect()), tag + " calculation sources remain available inside bounded scroll details")
	if not output.is_empty() and size == Vector2i(1280, 720) and count == 4:
		hud._member_scroll.scroll_vertical = 0
		var caption: Label = Label.new()
		caption.theme = HUD_THEME
		caption.text = "受控布局样本 · 非旅程、救援、保存或物理输入证明\n同名 · 12字长名 · ID 1/2/4/5 · 阵亡卡"
		caption.position = Vector2(216, 184)
		caption.add_theme_font_size_override("font_size", 12)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(caption)
		await settle()
		RenderingServer.force_draw()
		var image: Image = viewport.get_texture().get_image()
		check(not image.is_empty() and image.save_png(output.path_join("controlled-persona-4p.png")) == OK, tag + " native controlled third screenshot is saved")
	var case: Dictionary = {"size":[size.x, size.y], "ids":ids, "cards":card_metrics, "details":rect_values(details.get_global_rect()), "scope":"controlled DTO display only"}
	details.close()
	check(viewport.gui_get_focus_owner() == null and not details.visible and hud._persona_id == 0, tag + " closing details clears local focus and selection")
	viewport.queue_free()
	await process_frame
	cases.append(case)


func camp_scenario(size: Vector2i) -> void:
	var tag: String = "camp/%dx%d" % [size.x, size.y]
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	var template: Node = MAIN.instantiate()
	var camp_theme: Theme = CampStyle.theme((template.get_node("Interface/Screen") as Control).theme)
	template.free()
	var panel: RosterPanel = RosterPanel.new()
	panel.player_mode = true
	panel.theme = camp_theme
	viewport.add_child(panel)
	panel.refresh(base)
	await settle()
	var details: PersonaDetails = panel.persona_details
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(size)).grow(0.5)
	var inner: Rect2 = scroll_client(panel._detail_host).grow(0.5)
	check(panel.is_visible_in_tree() and details.is_visible_in_tree() and bounds.encloses(panel.get_global_rect()) and inner.encloses(details.get_global_rect()), tag + " actual roster and shared details remain fully reachable")
	check(details.scroll.size.y >= 140.0, tag + " shared details retain at least 140px of actual inner scroll height")
	var rename_reachable: bool = panel.name_edit.is_visible_in_tree() and panel.save_button.is_visible_in_tree() and panel.name_edit.editable and not panel.save_button.disabled and bounds.encloses(panel.name_edit.get_global_rect()) and bounds.encloses(panel.save_button.get_global_rect())
	panel.name_edit.grab_focus()
	await process_frame
	rename_reachable = rename_reachable and viewport.gui_get_focus_owner() == panel.name_edit
	panel.save_button.grab_focus()
	await process_frame
	rename_reachable = rename_reachable and viewport.gui_get_focus_owner() == panel.save_button
	check(rename_reachable, tag + " original rename field and save remain visible, bounded and keyboard-reachable")
	var equipment_ids: Array[int] = []
	var training_ids: Array[int] = []
	panel.equipment_requested.connect(func(id: int) -> void: equipment_ids.append(id))
	panel.training_requested.connect(func(id: int) -> void: training_ids.append(id))
	var actions_reachable: bool = details.equipment_button.is_visible_in_tree() and details.training_button.is_visible_in_tree() and not details.equipment_button.disabled and not details.training_button.disabled and bounds.encloses(details.equipment_button.get_global_rect()) and bounds.encloses(details.training_button.get_global_rect())
	details.equipment_button.grab_focus()
	await process_frame
	actions_reachable = actions_reachable and viewport.gui_get_focus_owner() == details.equipment_button
	details.equipment_button.pressed.emit()
	details.training_button.grab_focus()
	await process_frame
	actions_reachable = actions_reachable and viewport.gui_get_focus_owner() == details.training_button
	details.training_button.pressed.emit()
	check(actions_reachable and equipment_ids == [panel.selected_member_id] and training_ids == [panel.selected_member_id], tag + " living camp equipment/training controls retain original stable-member signals and GUI reachability")
	var entry: Dictionary = {"size":[size.x, size.y], "roster":rect_values(panel.get_global_rect()), "details":rect_values(details.get_global_rect()), "detail_host_client":rect_values(inner), "inner_scroll_height":details.scroll.size.y, "name_edit":rect_values(panel.name_edit.get_global_rect()), "save_button":rect_values(panel.save_button.get_global_rect()), "equipment_button":rect_values(details.equipment_button.get_global_rect()), "training_button":rect_values(details.training_button.get_global_rect()), "scope":"actual RosterPanel with pure legal initial camp; GUI APIs only, no rename commit or gameplay owner"}
	viewport.queue_free()
	await process_frame
	camp_cases.append(entry)


func camp_fixture() -> Dictionary:
	var crew: Array[Dictionary] = SurvivorRoster.new_crew()
	GrowthRules.initialize(crew)
	TraitRules.initialize(crew)
	TrainingState.initialize(crew)
	var camp: Dictionary = {"schema_version":5, "profile_id":"0123456789abcdef0123456789abcdef", "day":2, "cash":53, "food":RunSave.DefaultRules.initial_food, "last_day":{}, "settled_sorties":0, "last_settlement_id":"", "crew":crew}
	WeaponInventory.initialize(camp, "initial")
	for index: int in range(camp.weapons.size()):
		camp.weapons[index] = WeaponModifiers.baseline(camp.weapons[index])
	var journey: Dictionary = EnemyState.initial("persona-ui-fixture")
	journey.campaign = CampaignRules.initial(camp.profile_id)
	journey.build = PersonaState.initial_build(journey.seed)
	return EnemyState.snapshot(camp, journey, [], [])


func settle() -> void:
	for tick: int in range(4):
		await process_frame


func scroll_client(scroll: ScrollContainer) -> Rect2:
	var rect: Rect2 = scroll.get_global_rect()
	if scroll.get_v_scroll_bar().visible:
		rect.size.x -= scroll.get_v_scroll_bar().size.x
	return rect


func chinese_supported(label: Label) -> bool:
	var font: Font = label.get_theme_font("font")
	for character: int in range(label.text.length()):
		var code: int = label.text.unicode_at(character)
		if code >= 0x4e00 and code <= 0x9fff and not font.has_char(code):
			return false
	return true


func rect_values(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func check(value: bool, label: String) -> void:
	checks.append({"pass":value, "label":label})
	if not value:
		failures += 1
		printerr("PERSONA_UI_FAIL " + label)
