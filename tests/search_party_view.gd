extends SceneTree
## Controlled party component fixture, NOT recruitment, journey or persistence proof.
## The original Expedition owns assignment, movement, protection, progress and all UI.

const SIZE: Vector2i = Vector2i(1280, 720)
const MAIN: PackedScene = preload("res://src/app/main.tscn")

var viewport: SubViewport
var input_path: String = ""
var output: String = ""
var source: Dictionary = {}
var theme: Theme
var checks: Array[Dictionary] = []
var cases: Array[Dictionary] = []
var failures: int = 0


func _initialize() -> void:
	root.unfocusable = true
	call_deferred("run")


func check(value: bool, label: String) -> void:
	checks.append({"pass":value, "label":label})
	if not value:
		failures += 1
		printerr("SEARCH_PARTY_VIEW_FAIL " + label)


func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--party-world="):
			input_path = local_path(argument.trim_prefix("--party-world="))
		if argument.begins_with("--party-output="):
			output = local_path(argument.trim_prefix("--party-output="))
	if input_path.is_empty() or output.is_empty() or not FileAccess.file_exists(input_path) or FileAccess.file_exists(output.path_join("report.json")):
		printerr("SEARCH_PARTY_VIEW_ARGUMENTS require isolated .local input and fresh .local output")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(input_path))
	if not parsed is Dictionary:
		check(false, "controlled descriptor input is a JSON object")
		finish()
		return
	var world_value: Variant = parsed.get("world")
	if not world_value is Dictionary and parsed.get("encoded") is String:
		var encoded: Variant = JSON.parse_string(parsed.encoded)
		if encoded is Dictionary:
			world_value = RecordEncoding.unpack(encoded).get("payload")
	if not world_value is Dictionary or not world_value.get("generated") is Dictionary or not world_value.get("support") is Dictionary or not world_value.support.get("binding") is Dictionary:
		check(false, "source world contains original generated descriptor and support binding")
		finish()
		return
	source = world_value
	check(DailyActions.problem(source.generated).is_empty() and source.generated.get("version") == 8, "component reuses authentic generated8 descriptor without modifying it")
	check(DisplayServer.get_name() != "headless", "native renderer is required for actual PNG evidence")
	if failures > 0:
		finish()
		return
	# Instantiating outside the tree obtains the actual theme without starting Main.
	var template: Node = MAIN.instantiate()
	theme = (template.get_node("Interface/Screen") as Control).theme
	template.free()
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	for party: int in [3, 4]:
		await scenario(party)
	finish()


func finish() -> void:
	var report: Dictionary = {
		"scope":"controlled original-Expedition party/dispatch/UI component fixture",
		"initialization":"manual legal roster and inventory; original descriptor; controlled reachable starts beside actual sites; background spawns suppressed",
		"not_proven":["actual recruitment", "normal whole journey", "persistence", "physical OS input", "display FPS"],
		"source":input_path, "source_sha256":FileAccess.get_sha256(input_path),
		"renderer":DisplayServer.get_name(), "viewport":[SIZE.x, SIZE.y],
		"pid":OS.get_process_id(), "checks":checks, "failures":failures, "cases":cases,
	}
	var file: FileAccess = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		printerr("SEARCH_PARTY_VIEW_REPORT_WRITE_FAILED")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SEARCH_PARTY_VIEW checks=%d failures=%d" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)


func scenario(party: int) -> void:
	var camp: Dictionary = {"profile_id":String(source.support.binding.run_id), "crew":[]}
	for id: int in range(1, party + 1):
		camp.crew.append({"id":id, "health":200.0})
	check(SurvivorRoster.initialize(camp.crew).is_empty(), "%d-person controlled roster uses original definitions" % party)
	WeaponInventory.initialize(camp, "initial")
	for id: int in range(3, party + 1):
		var gun: Dictionary = RescuePoolState.weapon(camp.profile_id, id)
		camp.weapons.append(gun)
		camp.loadout.append({"member_id":id, "instance_id":gun.instance_id})
	var equipment: Array[Dictionary] = WeaponInventory.snapshot(camp)
	check(WeaponInventory.snapshot_problem(camp.crew, equipment).is_empty(), "%d-person controlled equipment passes original snapshot boundary" % party)
	var world: Expedition = Expedition.new()
	world.supply = DailyActions.supply(source.generated)
	world.mission_title = world.supply.display_name
	world.crew_snapshot.assign(camp.crew.duplicate(true))
	world.loadout_snapshot.assign(equipment)
	world.growth_binding = source.support.binding.duplicate(true)
	world.sortie_id = String(source.support.binding.transaction_id)
	world.ui_theme = theme
	viewport.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.set_process_unhandled_input(false)
	check(world.setup_problem.is_empty() and world.survivors.size() == party, "%d-person original Expedition initializes every controlled member" % party)
	if not world.setup_problem.is_empty() or world.survivors.size() != party:
		world.queue_free()
		await process_frame
		return
	world.camera.set_process(false)
	world.camera.set_process_unhandled_input(false)
	if world.bus_view != null:
		world.bus_view.skip()
	# This fixture isolates dispatch and UI, not combat pressure or a natural journey.
	world._spawn_clock = INF
	world._ai_clock = INF
	var caption_layer: CanvasLayer = CanvasLayer.new()
	caption_layer.layer = 100
	world.add_child(caption_layer)
	var caption: Label = Label.new()
	caption.theme = theme
	caption.text = "受控%d人派工界面 · 手工名册/起点 · 非招募、旅程或保存证明" % party
	caption.position = Vector2(14.0, 693.0)
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 3)
	caption_layer.add_child(caption)
	var selected: Array[Expedition.SearchSite] = []
	for site: Expedition.SearchSite in world.sites:
		if not site.searched and world.supply.supports(site.kind):
			selected.append(site)
	check(selected.size() >= party, "%d-person real descriptor has enough distinct searchable sites" % party)
	if selected.size() < party:
		world.queue_free()
		await process_frame
		return
	selected.resize(party)
	var starts: Array[Dictionary] = []
	for index: int in range(party):
		var point: Vector2 = controlled_start(world, selected[index])
		check(point.is_finite(), "%d-person controlled start %d is clear and reaches original door" % [party, index + 1])
		if not point.is_finite():
			world.queue_free()
			await process_frame
			return
		world.survivors[index].position = point
		starts.append({"member_id":world.survivors[index].member_id, "site_id":String(selected[index].id), "foot":[point.x, point.y]})
	for site: Expedition.SearchSite in selected:
		world.request_search(site.id)
	check(world.search_assignments.ordered().size() == party, "%d-person original requests allow everyone to work without a guard slot" % party)
	check(world.survivors.all(func(actor: FieldActor) -> bool: return world.has_search_job(actor.member_id)), "%d-person every actual member owns a distinct job" % party)
	var member_ids: Array[int] = []
	var site_ids: Array[String] = []
	for actor: FieldActor in world.survivors:
		member_ids.append(actor.member_id)
	for site: Expedition.SearchSite in world.sites:
		site_ids.append(String(site.id))
	check(SearchAssignments.problem(world.search_assignments.snapshot(), member_ids, site_ids).is_empty(), "%d-person assignments retain unique original member/site identities" % party)
	world._update_ui()
	await settle()
	var approach_metrics: Array[Dictionary] = hud_metrics(world, party, "approach")
	for tick: int in range(180):
		if all_working(world, party):
			break
		world.step(1.0 / 30.0)
		if tick % 12 == 0:
			await process_frame
	check(all_working(world, party), "%d-person original paths and work entry reach all independent buildings" % party)
	if not all_working(world, party):
		cases.append({"party":party, "starts":starts, "jobs":world.search_assignments.snapshot(), "setup":world.setup_problem})
		world.queue_free()
		await process_frame
		return
	var before: Dictionary = progresses(world)
	for tick: int in range(15):
		world.step(1.0 / 30.0)
	for site: Expedition.SearchSite in world.sites:
		var owns: bool = world.search_assignments.member_for(String(site.id)) > 0
		check(site.progress > float(before[String(site.id)]) if owns else site.progress == float(before[String(site.id)]), "%d-person only assigned site progresses: %s" % [party, site.id])
		if owns:
			var actor: FieldActor = world.search_member(world.search_assignments.member_for(String(site.id)))
			check(world.work_state_matches(actor, site), "%d-person work protection and presence belong only to own site: %s" % [party, site.id])
	world._update_ui()
	await settle()
	var working_metrics: Array[Dictionary] = hud_metrics(world, party, "working")
	for member: FieldActor in world.survivors:
		if member.magazine != null:
			while member.magazine.can_fire():
				member.magazine.commit_shot()
	world._update_ui()
	await settle()
	var reload_metrics: Array[Dictionary] = hud_metrics(world, party, "working_reload_paused")
	var building_metrics: Array[Dictionary] = []
	for site: Expedition.SearchSite in selected:
		var label: Label = site.prop._work
		world.camera.pan_by(label.get_global_rect().get_center() - world.camera.position)
		world.camera.force_update_scroll()
		await settle()
		var measurement: Dictionary = label_measurement(label)
		measurement.site_id = String(site.id)
		measurement.camera = [world.camera.position.x, world.camera.position.y, world.camera.zoom.x]
		building_metrics.append(measurement)
		check(bool(measurement.text_fits), "%d-person original building label fits including outline: %s" % [party, site.id])
		check(bool(measurement.viewport_fits), "%d-person focused original building label stays inside viewport: %s" % [party, site.id])
	# One actual focused street view per party; all destinations remain visible in HUD.
	world.camera.pan_by(selected[0].prop._work.get_global_rect().get_center() - world.camera.position)
	world.camera.force_update_scroll()
	world._update_ui()
	await settle()
	RenderingServer.force_draw()
	var image: Image = viewport.get_texture().get_image()
	check(image != null and image.get_size() == SIZE, "%d-person native image is actual 1280x720 viewport" % party)
	var screenshot: String = "party-%d.png" % party
	if image != null:
		check(image.save_png(output.path_join(screenshot)) == OK, "%d-person native screenshot saves" % party)
	var jobs_before_cancel: Dictionary = world.search_assignments.snapshot()
	var owned: int = world.search_assignments.member_for(String(selected[0].id))
	var progress_before_cancel: Dictionary = progresses(world)
	world.request_search(selected[0].id)
	check(not world.has_search_job(owned) and world.search_assignments.ordered().size() == party - 1, "%d-person repeat click releases only selected worker" % party)
	for tick: int in range(8):
		world.step(1.0 / 30.0)
	check(selected[0].progress == float(progress_before_cancel[String(selected[0].id)]), "%d-person local cancellation retains progress without further work" % party)
	for site: Expedition.SearchSite in selected.slice(1):
		check(site.progress > float(progress_before_cancel[String(site.id)]), "%d-person other member continues at own site after cancellation: %s" % [party, site.id])
	cases.append({"party":party, "controlled_starts":starts, "approach_hud":approach_metrics, "working_hud":working_metrics, "buildings_individually_focused":building_metrics, "jobs_before_cancel":jobs_before_cancel, "jobs_after_cancel":world.search_assignments.snapshot(), "screenshot":screenshot, "media_scope":"actual original HUD and focused building; other buildings checked by normal camera pan, not all claimed in this one frame"})
	world.queue_free()
	await process_frame


func controlled_start(world: Expedition, site: Expedition.SearchSite) -> Vector2:
	for offset: Vector2 in [Vector2(0.0, 40.0), Vector2(32.0, 32.0), Vector2(-32.0, 32.0), Vector2(0.0, 24.0), Vector2(40.0, 0.0), Vector2(-40.0, 0.0), Vector2.ZERO]:
		var point: Vector2 = site.door + offset
		if not world.navigation.is_clear(point):
			continue
		var path: PackedVector2Array = world.navigation.path_between(point, site.door)
		if point.distance_to(site.door) <= 14.0 or (not path.is_empty() and path[-1].distance_to(site.door) <= 14.0):
			return point
	return Vector2.INF


func all_working(world: Expedition, party: int) -> bool:
	if world.search_assignments.ordered().size() != party:
		return false
	for actor: FieldActor in world.survivors:
		var site: Expedition.SearchSite = world.member_site(actor.member_id)
		if site == null or world.search_assignments.phase_for(actor.member_id) != "working" or not world.work_state_matches(actor, site):
			return false
	return true


func progresses(world: Expedition) -> Dictionary:
	var values: Dictionary = {}
	for site: Expedition.SearchSite in world.sites:
		values[String(site.id)] = site.progress
	return values


func hud_metrics(world: Expedition, party: int, stage: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var members: Array[Dictionary] = world._hud.view._members
	check(members.size() >= party, "%d-person actual HUD creates all member columns: %s" % [party, stage])
	for index: int in range(mini(party, members.size())):
		var label: Label = members[index].status
		var measurement: Dictionary = label_measurement(label)
		measurement.member_id = world.survivors[index].member_id
		result.append(measurement)
		var site: Expedition.SearchSite = world.member_site(world.survivors[index].member_id)
		check(site != null and label.text.contains(world.site_label(site)), "%d-person actual HUD status names own destination for member %d: %s" % [party, index + 1, stage])
		check(bool(measurement.text_fits) and bool(measurement.viewport_fits), "%d-person actual HUD status fits without wrapping or viewport overflow for member %d: %s" % [party, index + 1, stage])
		for previous: int in range(index):
			check(not members[index].box.get_global_rect().intersects(members[previous].box.get_global_rect()), "%d-person original HUD member columns do not overlap: %d/%d %s" % [party, previous + 1, index + 1, stage])
	return result


func label_measurement(label: Label) -> Dictionary:
	var font: Font = label.get_theme_font("font")
	var size: int = label.get_theme_font_size("font_size")
	var outline: int = label.get_theme_constant("outline_size")
	var text_size: Vector2 = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	var transformed: Rect2 = label.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, label.size)
	return {"text":label.text, "font_size":size, "glyph_width":text_size.x, "control_width":label.size.x, "outline":outline, "screen_rect":[transformed.position.x, transformed.position.y, transformed.size.x, transformed.size.y], "text_fits":text_size.x + 2.0 * outline <= label.size.x + 0.5 and label.get_line_count() == 1, "viewport_fits":Rect2(Vector2.ZERO, Vector2(SIZE)).encloses(transformed), "visible":label.is_visible_in_tree()}


func settle() -> void:
	for tick: int in range(3):
		await process_frame


func local_path(value: String) -> String:
	var path: String = value.replace("\\", "/")
	if not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://" + path.trim_prefix("./"))
	path = path.simplify_path()
	var base: String = ProjectSettings.globalize_path("res://.local").replace("\\", "/").simplify_path()
	return path if path.to_lower().begins_with(base.to_lower() + "/") else ""
