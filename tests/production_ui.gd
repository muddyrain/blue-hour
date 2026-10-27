extends SceneTree
## Layout and state boundaries, separate from native gameplay/art inspection.

const MAIN: PackedScene = preload("res://src/app/main.tscn")
var _results: Array[Dictionary] = []
var _failures: int = 0
var _path: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			_path = argument.trim_prefix("--bh-progress=")
	if not _path.contains(".local") or FileAccess.file_exists(_path):
		quit(1)
		return
	root.size = Vector2i(1280,720)
	var app: Node = MAIN.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	_expect(not app._camp_open and app._home_button.visible, "ordinary fresh launch presents actual home entry")
	_expect(not app.get_node("Interface/Screen/Title/Practice").visible and not app.get_node("Interface/Screen/Title/Probe").visible, "developer controls hidden in ordinary sample")
	var before: Dictionary = app.camp_snapshot()
	app._enter_camp()
	await process_frame
	_expect(app._camp_open and app._roster_button.visible and app._loadout_button.visible and app.camp_snapshot() == before, "camp navigation never modifies resources or identity")
	app.open_roster()
	app.rename_survivor(1,"蓝时归航观察员一号同行者")
	app.rename_survivor(2,"暮色归航观察员二号同行者")
	await process_frame
	await process_frame
	_expect(app.crew[0].call_sign.length() == 12 and app.crew[1].call_sign.length() == 12, "real v4 controls retain maximum Chinese call signs")
	_within(app.roster_panel.back_button, "roster back")
	_within(app.roster_panel.name_edit, "roster name")
	_within(app.roster_panel.equipment_button, "roster equipment")
	_within(app.roster_panel._identity, "long profile identity")
	_expect(app.roster_panel.member_buttons[1].icon != app.roster_panel.member_buttons[0].icon and app.roster_panel.member_buttons[1].material == null, "stable ID has distinct original portrait, no palette substitution")
	app.roster_panel.selected_member_id = 2
	app.roster_panel.refresh(app.camp_snapshot())
	_expect((app.roster_panel._portrait.texture as AtlasTexture).atlas == CrewAppearance.AMBER_FULL, "second portrait uses independent Amber atlas")
	app._roster_equipment(2)
	await process_frame
	await process_frame
	_within(app.loadout_panel.back_button, "equipment back")
	_within(app.loadout_panel.repair_button, "equipment repair")
	for button: Button in app.loadout_panel.equip_buttons:
		_within(button, "long-name equip action")
	for index: int in range(app.loadout_panel.items.item_count):
		_expect(not app.loadout_panel.items.get_item_text(index).contains(":starter:") and not app.loadout_panel.items.get_item_tooltip(index).is_empty(), "instance identity remains metadata/tooltip, not main list copy")
	app.close_loadout()
	_expect(app.roster_panel.visible and app.roster_panel.selected_member_id == 2, "equipment returns to original survivor")
	app.close_roster()
	app.open_mission_select()
	await process_frame
	for choice: Button in app.mission_select.choices:
		_within(choice,"mission choice")
	app.close_mission_select()
	var saved: Dictionary = app.camp_snapshot()
	app.open_expedition()
	app.expedition.set_physics_process(false)
	_expect(app.expedition.survivors[1].visual._upper.texture == CrewAppearance.AMBER_UPPER and app.expedition.survivors[1].visual._head.texture == CrewAppearance.AMBER_UPPER
		and app.expedition.survivors[1].visual._body.texture == CrewAppearance.AMBER_LEGS, "all active second-survivor layers use independent original parts")
	_expect(app.expedition.crew_snapshot == saved.crew and app.expedition.survivors[0].call_sign == saved.crew[0].call_sign, "presentation preserves campaign snapshot into real sortie")
	_expect(app.expedition._food_site.prop.facade == MissionSelect.MARKET and app.expedition._shop.facade == FieldProp.ShopTexture, "search points use distinct real building assets")
	_expect(app.expedition.navigation.obstacles == app.expedition.layout.blockers(), "paint and navigation use the selected actual layout")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var file: FileAccess = FileAccess.open(_path.get_base_dir().path_join("production-ui-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":_results.size(),"failures":_failures,"results":_results},"\t"))
	file.close()
	print("BH_PRODUCTION_UI checks=%d failures=%d" % [_results.size(),_failures])
	quit(0 if _failures == 0 else 1)


func _within(control: Control, label: String) -> void:
	var rect: Rect2 = control.get_global_rect()
	_expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= 1280.5 and rect.end.y <= 720.5, label + " remains in reference viewport")


func _expect(value: bool, label: String) -> void:
	_results.append({"passed":value,"label":label})
	if not value:
		_failures += 1
		push_error("FAIL production UI: " + label)
	else:
		print("PASS production UI: " + label)
