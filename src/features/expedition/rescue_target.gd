class_name RescueTarget
extends Node2D
## One visible objective, using existing actor movement. Camp ownership starts at commit.

const SECONDS: float = 10.0 # PROJECT_TEMP: assistance time, not an original-game fact.
const START: Vector2 = Vector2(1344,1120)
var world: Expedition
var status: String = "AVAILABLE"
var progress: float = 0.0
var worker: int = 0
var npc: FieldActor
var button: C1HudButton
var _joined_at_ms: int = -1
var persona_card: PersonaCard
var label: Label


func _ready() -> void:
	npc = world._make_actor(false,99,world.layout.rescue_point,{"id":world.candidate_id(),"definition_id":"crew_%d" % world.candidate_id()})
	npc.weapon_definition = WeaponInventory.definition("long_rifle" if world.pool_mode and world.candidate_id()==4 else "carbine")
	npc.visual.set_weapon(npc.weapon_definition.presentation)
	label = Label.new()
	label.add_theme_font_size_override("font_size",17)
	label.add_theme_color_override("font_color",Color("ffd3a8"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world._sort.add_child(label)
	button = C1HudButton.new()
	button.text = "援救"+candidate_name()+" · 10秒"
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	button.offset_left = 16
	button.offset_right = 296
	button.offset_top = -116
	button.offset_bottom = -68
	if world.layout.world_data.get("version") == 3:
		button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		button.offset_left = 16
		button.offset_right = 296
		button.offset_top = 208
		button.offset_bottom = 256
	button.pressed.connect(request)
	world._hud.view.add_child(button)
	if world.persona_mode():
		button.offset_top=548
		button.offset_bottom=588
		button.offset_right=264
		persona_card=PersonaCard.new()
		world._hud.view.add_child(persona_card)
		persona_card.position=Vector2(16,410)
		persona_card.size.x=248
		var model: Dictionary=PersonaViewModel.camp(world.field_departure,world.candidate_id(),"candidate")
		persona_card.present(model,true)
		persona_card.selected.connect(func(_id: int) -> void:
			world._hud.view._persona_id=0
			world._hud.view.persona_details.present(model)
			world._hud.view.persona_details.grab_focus()
		)
	refresh()


func _draw() -> void:
	# Read-only assistance cue. No extra clock, state, interaction rule or save field.
	if npc != null and status in ["AVAILABLE", "IN_PROGRESS"]:
		draw_arc(npc.position, 34, 0, TAU, 32, Color("ffca91"), 3, true)
	if npc == null or status != "IN_PROGRESS":
		return
	for actor: FieldActor in world.survivors:
		if actor.member_id != worker or actor.health <= 0 or not actor.visible or actor.position.distance_to(npc.position) > 52.0:
			continue
		var pulse: float = 0.6 + 0.3 * sin(world.elapsed * 8.0)
		var colour: Color = Color(0.55, 0.95, 0.85, pulse)
		draw_arc(npc.position + Vector2(0, -36), 23, -PI * 0.5, -PI * 0.5 + TAU * progress / SECONDS, 32, colour, 2.0, true)
		for point: Vector2 in [actor.position + Vector2(18, -36), npc.position + Vector2(-18, -36)]:
			draw_arc(point, 5, PI * 0.2, PI * 1.8, 12, colour, 2.0, true)
		return


func candidate_name() -> String:
	return SurvivorRoster.definition(world.candidate_id()).default_display_name


func contains(point: Vector2) -> bool:
	return not (world.field_join_mode and status == "IN_FIELD_JOINED") and Rect2(npc.position-Vector2(56,92),Vector2(112,116)).has_point(point)


func request() -> void:
	if world.bus_view!=null and world.bus_view.running(): return
	if world.field_join_mode and progress >= SECONDS and status == "IN_PROGRESS":
		_complete_field_join()
		return
	if status in ["RESCUED","FAILED","IN_FIELD_JOINED"] or world.phase == Expedition.Phase.FINISHED:
		return
	if status == "IN_PROGRESS":
		cancel()
		return
	var nearest: FieldActor
	for actor: FieldActor in world.survivors:
		if actor.health > 0 and actor.visible and not world.has_search_job(actor.member_id) and (nearest == null or actor.position.distance_to(npc.position) < nearest.position.distance_to(npc.position)):
			nearest = actor
	if nearest == null:
		world._show_notice("需要一名可见、存活且未搜集的队员援救。")
		return
	var path: PackedVector2Array = world.navigation.path_between(nearest.position,npc.position+Vector2(-40,0))
	if path.is_empty():
		world._show_notice("援救路线不可达，目标未改变。")
		return
	worker = nearest.member_id
	status = "IN_PROGRESS"
	nearest.command_path(path)
	refresh()


func cancel() -> void:
	if not world.field_join_error.is_empty():
		return
	if status != "IN_PROGRESS": return
	var previous: int = worker
	status = "AVAILABLE"
	worker = 0
	for actor: FieldActor in world.survivors:
		if actor.member_id == previous and actor.health > 0 and actor.visible:
			actor.clear_order()
			if world.goal != Vector2.ZERO: world._move_to_group_goal(actor)
	refresh()


func step(delta: float) -> void:
	if status == "IN_PROGRESS":
		var actor: FieldActor
		for member: FieldActor in world.survivors:
			if member.member_id == worker: actor = member
		if actor == null or actor.health <= 0 or not actor.visible:
			cancel()
		elif actor.position.distance_to(npc.position) <= 52.0:
			progress = minf(SECONDS,progress+delta)
			if progress >= SECONDS:
				if world.field_join_mode:
					_complete_field_join()
					refresh()
					return
				status = "RESCUED"
				worker = 0
				npc.command_path(world.navigation.path_between(npc.position,world.layout.bus_door))
				world._show_notice(candidate_name()+"已获救，正在前往巴士；归航结算后正式加入。下一次多一人，多一份口粮。")
	if status == "RESCUED":
		npc.advance(delta)
	refresh()


func _complete_field_join() -> void:
	if _joined_at_ms < 0:
		_joined_at_ms = floori(world.elapsed*1000.0)
	if world.join_target(_joined_at_ms):
		world._show_notice(candidate_name()+"已加入本次行动，接受编队命令并自动参战；全员撤离后正式登记营地。本餐口粮政策保持。")
	refresh()


func delivered() -> bool:
	if world.field_join_mode:
		return status == "IN_FIELD_JOINED" and npc.health > 0 and npc.position.distance_to(world.layout.bus_door) <= world.tuning.boarding_radius
	return status == "RESCUED" and npc.position.distance_to(world.layout.bus_door) <= world.tuning.boarding_radius


func refresh() -> void:
	if persona_card!=null: persona_card.visible=status in ["AVAILABLE","IN_PROGRESS"]
	label.visible = not (world.field_join_mode and status == "IN_FIELD_JOINED")
	label.position = npc.position + Vector2(-100,-132)
	label.text = candidate_name()+" · 等待援救\n左键 / 10秒援救" if status == "AVAILABLE" else ("援救 %.1f / 10秒" % progress if status == "IN_PROGRESS" else ("已上车 · 归航后加入" if delivered() else "已获救 · 前往巴士"))
	button.text = "取消援救 · %.1f / 10秒" % progress if status == "IN_PROGRESS" else ("援救"+candidate_name()+" · 10秒" if status == "AVAILABLE" else label.text)
	if world.field_join_mode and status == "IN_FIELD_JOINED":
		label.text = candidate_name()+" · 本次行动队员" if npc.health > 0 else candidate_name()+" · 已确认阵亡"
		button.text = candidate_name()+"已加入 · 全员撤离后登记营地" if npc.health > 0 else candidate_name()+"已阵亡 · 历史保留"
	if not world.field_join_error.is_empty():
		button.text = "重试完成援救 / 接纳"+candidate_name()
	button.disabled = status in ["RESCUED","FAILED","IN_FIELD_JOINED"] or (world.bus_view!=null and world.bus_view.running())
	queue_redraw()


func fact(evacuated: bool) -> Dictionary:
	return {"rescue_id":RescueState.TARGET,"status":("RESCUED" if delivered() else "FAILED") if evacuated else "FAILED"}


func snapshot() -> Dictionary:
	if world.field_join_mode and status == "IN_FIELD_JOINED":
		return {"status":status,"progress":progress,"worker":0}
	var path: Array = []
	for point: Vector2 in npc.path: path.append([point.x,point.y])
	return {"status":status,"progress":progress,"worker":worker,"position":[npc.position.x,npc.position.y],"path":path,"path_index":npc._path_index,"walk_clock":npc.visual._walk_clock}


func restore(value: Dictionary) -> void:
	status = value.status
	progress = float(value.progress)
	worker = int(value.worker)
	if world.field_join_mode and status == "IN_FIELD_JOINED":
		refresh()
		return
	npc.position = Vector2(value.position[0],value.position[1])
	npc.path.clear()
	for point: Array in value.path: npc.path.append(Vector2(point[0],point[1]))
	npc._path_index = int(value.path_index)
	npc.activity = FieldActor.Activity.MOVING if npc._path_index < npc.path.size() else FieldActor.Activity.IDLE
	npc.visual._walk_clock = value.walk_clock
	refresh()


static func fact_problem(value: Dictionary) -> String:
	return "" if value.size() == 2 and value.get("rescue_id") == RescueState.TARGET and value.get("status") in ["RESCUED","FAILED","UNAVAILABLE"] else "RESCUE_FACT"


static func snapshot_problem(value: Variant, ids: Array[int], field: bool = false, candidate: int = 3, max_id: int = 3, bounds: Rect2 = FieldNavigation.BOUNDS) -> String:
	if field and value is Dictionary and value.get("status") == "IN_FIELD_JOINED":
		return "" if value.size() == 3 and value.get("progress") == SECONDS and value.get("worker") == 0 and candidate in ids else "FIELD_JOIN_TARGET_STATE"
	if field and value is Dictionary and value.get("status") not in ["AVAILABLE","IN_PROGRESS"]:
		return "FIELD_JOIN_LEGACY_TARGET"
	if not value is Dictionary or value.size() != 7 or not value.has_all(["status","progress","worker","position","path","path_index","walk_clock"]) or value.status not in ["AVAILABLE","IN_PROGRESS","RESCUED"] or not SurvivalContracts.number(value.progress) or value.progress < 0 or value.progress > SECONDS or not SurvivalContracts.integer(value.worker,0,max_id) or (value.status == "IN_PROGRESS" and int(value.worker) not in ids) or (value.status != "IN_PROGRESS" and value.worker != 0) or (value.status == "RESCUED" and value.progress != SECONDS):
		return "RESCUE_SNAPSHOT_FIELDS"
	if not value.path is Array or value.path.size() > 4096 or not SurvivalContracts.integer(value.path_index,0,value.path.size()) or not SurvivalContracts.number(value.walk_clock) or value.walk_clock < 0:
		return "RESCUE_SNAPSHOT_PATH"
	var points: Array = value.path.duplicate()
	points.append(value.position)
	for point: Variant in points:
		if not point is Array or point.size() != 2 or not SurvivalContracts.number(point[0]) or not SurvivalContracts.number(point[1]) or not bounds.has_point(Vector2(point[0],point[1])):
			return "RESCUE_SNAPSHOT_POINT"
	return ""
