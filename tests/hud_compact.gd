extends SceneTree
## Controlled read-only UI fixture. No journey, camp, combat or player data is changed.
## Optional native PNGs illustrate supplied HUD rows, not a playable journey proof.

const MAIN: PackedScene = preload("res://src/app/main.tscn")
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1024, 576)]

var output: String = ""
var theme: Theme
var rows: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var failures: int = 0
var pause_requests: int = 0
var gather_requests: int = 0


func _initialize() -> void:
	root.unfocusable = true
	call_deferred("run")


func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--hud-output="):
			output = argument.trim_prefix("--hud-output=")
	if not output.is_empty():
		var local_root: String = ProjectSettings.globalize_path("res://.local").replace("\\", "/").simplify_path() + "/"
		output = output.replace("\\", "/").simplify_path()
		if not output.is_absolute_path() or not output.begins_with(local_root) or DisplayServer.get_name() == "headless" or FileAccess.file_exists(output.path_join("report.json")):
			printerr("HUD_PROBE_ARGUMENTS require native renderer and a fresh absolute project .local output")
			quit(2)
			return
		if DirAccess.make_dir_recursive_absolute(output) != OK:
			printerr("HUD_PROBE_OUTPUT could not create isolated output")
			quit(2)
			return
	# Read the actual main theme without adding Main to a tree or running its owner.
	var template: Node = MAIN.instantiate()
	theme = (template.get_node("Interface/Screen") as Control).theme
	template.free()
	for size: Vector2i in SIZES:
		for count: int in [2, 3, 4]:
			await scenario(size, count)
	var report: Dictionary = {"scope":"controlled read-only HUD/component fixture; not journey, recruitment, persistence or physical-input proof", "renderer":DisplayServer.get_name(), "rows":rows, "checks":checks, "failures":failures}
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
		if file == null:
			check(false, "write isolated HUD report")
		else:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	print("HUD_PROBE " + JSON.stringify(report))
	quit(1 if failures else 0)


func scenario(size: Vector2i, count: int) -> void:
	var label: String = "%dx%d/%dp" % [size.x, size.y, count]
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	var background: ColorRect = ColorRect.new()
	background.color = Color("324b56")
	background.size = Vector2(size)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(background)
	# Use the real adapter: its C1 scene retains the committed HUD theme, and the
	# time ratio, Chinese help and resource formatting follow the production path.
	var adapter: ExpeditionHud = ExpeditionHud.new()
	adapter.ui_theme = theme
	adapter.pause_requested.connect(func() -> void: pause_requests += 1)
	adapter.extraction_requested.connect(func() -> void: gather_requests += 1)
	viewport.add_child(adapter)
	var hud: C1ExpeditionHud = adapter.view
	var support: BasicSupportPanel = BasicSupportPanel.new()
	hud.add_child(support)
	support.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	support.offset_left = -220
	support.offset_right = 220
	support.offset_top = -76
	support.offset_bottom = -8
	var members: Array[Dictionary] = []
	var names: Array[String] = ["顾予安", "夏之遥", "林知秋", "沈听澜"]
	for index: int in range(count):
		var site: String = SearchWorkView.short_site("街角便利店" if index % 2 == 0 else "旧街修理铺", index + 1)
		members.append({"id":index + 1, "call_sign":names[index], "label":names[index], "hp":205, "max_hp":210, "level":3, "status":SearchWorkView.actor_status("working" if index % 2 == 0 else "approach", site, false), "detail":"街角便利店 · 独立任务；完整说明只读", "ammo":"卡宾枪 12/12 · ∞"})
	var director: ThreatDirector = ThreatDirector.new()
	var threat: Dictionary = director.snapshot()
	threat.enabled = true
	var waiting: Array[Dictionary] = []
	var activities: Array[String] = ["searching", "gathering", "pending"]
	for index: int in range(1, count):
		waiting.append({"id":index + 1, "call_sign":names[index], "activity":activities[index - 1]})
	var state: Dictionary = {"seconds":105, "engine":"等待幸存者", "can_extract":false, "can_gather":true, "practice":false, "threat":threat, "objective":"主目标：食品站点 0/2", "mission_title":"贯通商业街", "day":3, "sites_searched":0, "sites_total":4, "kills":0, "cash":57, "food":2, "loot":4, "food_loot":3, "weapon_loot":1, "paused":false, "members":members, "notice":"已下令集合 · 搜集中的队员完成后归队。", "notice_visible":true, "time_fraction":0.75, "enemy_mode":true, "route_hint":"食品站点与装备站点分别派遣。",
		"boarding":{"arrived":1, "required":count, "working":1, "ordered":true, "waiting":waiting, "rescue_waiting":true}}
	adapter.refresh(state)
	support.present("无受伤存活者", "空槽", false, false)
	await settle()
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(size)).grow(0.5)
	var panels: Array[Control] = []
	var panel_metrics: Array[Dictionary] = []
	for path: String in ["MissionPanel", "TimePanel", "ResourcesPanel", "MembersPanel", "ActionsPanel"]:
		var panel: Control = hud.get_node(path) as Control
		panels.append(panel)
		panel_metrics.append(control_metrics(panel, bounds))
	check(panel_metrics.all(func(value: Dictionary) -> bool: return value.fits), label + " required panels stay inside viewport")
	check(disjoint(panels), label + " required panels do not overlap")
	check((hud.get_node("MissionPanel") as Control).size.y <= 144.0, label + " objective remains compact")
	var member_metrics: Array[Dictionary] = []
	var member_controls: Array[Control] = []
	var text_fits: bool = true
	for member: Dictionary in hud._members:
		if not member.box.visible:
			continue
		member_controls.append(member.box)
		var metrics: Dictionary = {"box":control_metrics(member.box, bounds), "labels":[]}
		for key: String in ["title", "health", "status", "ammo"]:
			var line: Dictionary = label_metrics(member[key], bounds)
			metrics.labels.append(line)
			text_fits = text_fits and line.fits and line.one_line and line.glyphs_fit
		member_metrics.append(metrics)
	check(member_controls.size() == count and disjoint(member_controls) and member_metrics.all(func(value: Dictionary) -> bool: return value.box.fits), label + " every member has a distinct bounded vertical row")
	check(text_fits, label + " names, HP, work destinations and ammo fit on one line")
	var skill_controls: Array[Control] = [support.rally_button, support.focus_button, support.heal_button, support.special_button]
	var skill_metrics: Array[Dictionary] = []
	for control: Control in skill_controls:
		skill_metrics.append(control_metrics(control, bounds))
	check(disjoint(skill_controls) and skill_metrics.all(func(value: Dictionary) -> bool: return value.fits), label + " Q/W/E/R command keys stay separate and inside viewport")
	check(support.rally_button.text.contains("集合") and support.focus_button.text.contains("集火") and support.heal_button.text.contains("治疗") and support.special_button.text.contains("特技"), label + " command keycaps keep their locked titles")
	check(support.rally_button.text.contains("Q") and support.focus_button.text.contains("W") and support.heal_button.text.contains("E") and support.special_button.text.contains("R"), label + " command keycaps keep QWER shortcuts")
	check(skill_controls.all(func(control: Control) -> bool: return control.icon != null) and support.size.x <= 448.0 and support.size.y <= 80.0, label + " command icons stay on compact bottom keycaps")
	check(support.heal_button.text.contains("无需") and support.special_button.text.contains("空槽"), label + " heal and special captions keep their actual unavailable meaning")
	var action_rect: Rect2 = (hud.get_node("ActionsPanel") as Control).get_global_rect()
	check(not action_rect.intersects(support.get_global_rect()), label + " command strip sits below the bus action cluster")
	var bus_labels: Array[Dictionary] = [label_metrics(hud._bus_status, bounds), label_metrics(hud._bus_waiting, bounds)]
	var bus_controls: Array[Control] = [hud._bus_status, hud._bus_waiting, hud._bus_button, hud._hint]
	check(bus_controls.all(func(control: Control) -> bool: return control.is_visible_in_tree() and bounds.encloses(control.get_global_rect())) and disjoint(bus_controls), label + " collection count, waiting rows, notice and button have separate visible bounds")
	check(bus_labels.all(func(metrics: Dictionary) -> bool: return metrics.glyphs_fit and metrics.lines_fit), label + " collection count and each waiting line fit at full font size")
	check(hud._bus_status.text == "已集合 1/%d" % count and bus_labels[0].one_line, label + " one-line count reflects supplied membership")
	var expected: PackedStringArray = ["等待夏之遥 · 搜集中", "等待救援对象"]
	if count >= 3:
		expected.insert(1, "等待林知秋 · 前往巴士")
	if count >= 4:
		expected.insert(2, "等待沈听澜 · 未集合")
	check(hud._bus_waiting.text.split("\n") == expected, label + " waiting names, states and rescue object remain distinct")
	check(hud._bus_status.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud._bus_waiting.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud._bus_status.focus_mode == Control.FOCUS_NONE and hud._bus_waiting.focus_mode == Control.FOCUS_NONE, label + " count and names are passive HUD labels")
	var before_gather: int = gather_requests
	await click_at(viewport, hud._bus_waiting.get_global_rect().get_center())
	check(gather_requests == before_gather, label + " waiting text has no collection action")
	await click_at(viewport, hud._bus_button.get_global_rect().get_center())
	check(gather_requests == before_gather + 1 and hud._bus_button.focus_mode == Control.FOCUS_ALL, label + " viewport click activates original collection button once")
	var before_pause: int = pause_requests
	var visible_before: bool = hud._objective.visible
	hud._objective_toggle.pressed.emit()
	await settle()
	var collapsed: bool = not hud._objective.visible
	hud._objective_toggle.pressed.emit()
	(hud.get_node("ThreatExplanation") as Button).pressed.emit()
	await settle()
	var details_fit: bool = bounds.encloses(hud._threat_details.get_global_rect())
	(hud.get_node("ThreatExplanation") as Button).pressed.emit()
	hud._help_button.pressed.emit()
	await settle()
	var help_fit: bool = bounds.encloses(hud._help.get_global_rect())
	hud._help_button.pressed.emit()
	check(visible_before and collapsed and hud._objective.visible and details_fit and help_fit and pause_requests == before_pause, label + " objective and explanation controls are bounded and do not request pause")
	var row: Dictionary = {"size":[size.x, size.y], "count":count, "panels":panel_metrics, "members":member_metrics, "skills":skill_metrics, "bus_labels":bus_labels, "resource_lines":hud._currency.get_line_count(), "scope":"supplied UI rows only; no journey or gameplay mutations"}
	if not output.is_empty() and count == 4:
		var caption: Label = Label.new()
		caption.theme = theme
		caption.text = "受控4人 HUD 组件 · 只读排布 · 非旅程、保存或物理输入证明"
		caption.position = Vector2(222, 194)
		caption.add_theme_font_size_override("font_size", 12)
		caption.add_theme_color_override("font_color", Color("edf0df"))
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewport.add_child(caption)
		await settle()
		RenderingServer.force_draw()
		var image: Image = viewport.get_texture().get_image()
		var file_name: String = "hud-%dx%d-4p.png" % [size.x, size.y]
		check(not image.is_empty() and image.save_png(output.path_join(file_name)) == OK, label + " native renderer writes controlled HUD PNG")
		row.screenshot = file_name
	state.can_gather = false
	state.engine_running = true
	state.engine = "发动引擎 2"
	adapter.refresh(state)
	await settle()
	check(hud._bus_status.text == "发动引擎 2" and "前往巴士" in hud._bus_waiting.text and hud._bus_button.disabled and hud._bus_button.focus_mode == Control.FOCUS_NONE, label + " engine countdown and approach hint retain disabled focus rule")
	rows.append(row)
	viewport.queue_free()
	await process_frame


func settle() -> void:
	for tick: int in range(4):
		await process_frame


func click_at(viewport: SubViewport, point: Vector2) -> void:
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)
		await process_frame


func check(value: bool, label: String) -> void:
	checks.append({"pass":value, "label":label})
	if not value:
		failures += 1
		printerr("HUD_PROBE_FAIL " + label)


func disjoint(controls: Array[Control]) -> bool:
	for index: int in range(controls.size()):
		for previous: int in range(index):
			if controls[index].get_global_rect().intersects(controls[previous].get_global_rect()):
				return false
	return true


func control_metrics(control: Control, bounds: Rect2) -> Dictionary:
	var rect: Rect2 = control.get_global_rect()
	return {"name":String(control.name), "rect":[rect.position.x, rect.position.y, rect.size.x, rect.size.y], "fits":bounds.encloses(rect)}


func label_metrics(label: Label, bounds: Rect2) -> Dictionary:
	var result: Dictionary = control_metrics(label, bounds)
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var outline: int = label.get_theme_constant("outline_size")
	var width: float = 0.0
	var lines: PackedStringArray = label.text.split("\n")
	for line: String in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	result.text = label.text
	result.font_size = font_size
	result.glyph_width = width
	result.control_width = label.size.x
	result.one_line = label.get_line_count() == 1
	result.glyphs_fit = width + 2.0 * float(outline) <= label.size.x + 0.5
	result.lines_fit = label.get_line_count() == lines.size() and label.get_visible_line_count() == lines.size()
	return result
