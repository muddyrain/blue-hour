class_name CampSceneWorld
extends Node2D
## Pixel seaside plate with independent moving residents and original camp intentions.

signal atmosphere_changed(atmosphere: String)

const PLATE: Texture2D = preload("res://assets/camp_pixel/coast-yard.png")
var visible_member_ids: Array[int] = []
var residents: Dictionary[int, CampSceneResident] = {}
var facilities: Dictionary[String, int] = {}
var stage: Node2D
var plate: Sprite2D
var dusk: float = 0.0
var _world: Node2D
var _can_depart: bool = true


func _ready() -> void:
	_world = Node2D.new()
	_world.name = "CoastYard"
	add_child(_world)
	plate = Sprite2D.new()
	plate.name = "ScenePlate"
	plate.texture = PLATE
	plate.centered = false
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.scale = Vector2.ONE * CampSceneLayout.SCENE_SIZE.x / PLATE.get_width()
	plate.z_index = -1
	_world.add_child(plate)
	stage = Node2D.new()
	stage.name = "Residents"
	stage.y_sort_enabled = true
	_world.add_child(stage)
	for id: String in CampSceneLayout.FACILITIES:
		facilities[id] = 0
	for definition: SurvivorDefinition in SurvivorRoster.Definitions:
		var resident: CampSceneResident = CampSceneResident.new()
		resident.name = "Resident%d" % definition.member_id
		resident.member_id = definition.member_id
		stage.add_child(resident)
		resident.hide()
		residents[definition.member_id] = resident
	set_dusk(dusk)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		advance(minf(delta, 0.1))


func advance(delta: float) -> void:
	for id: int in visible_member_ids:
		residents[id].advance(delta)


func refresh(members: Array) -> void:
	visible_member_ids.clear()
	for resident: CampSceneResident in residents.values():
		resident.hide()
	for member: Dictionary in members:
		var id: int = int(member.id)
		if float(member.health) <= 0.0 or not residents.has(id):
			continue
		residents[id].configure(member)
		residents[id].show()
		visible_member_ids.append(id)
	visible_member_ids.sort()
	# Reserve identities may share artwork, but living people never share a yard slot.
	for index: int in range(visible_member_ids.size()):
		residents[visible_member_ids[index]].set_slot(index)


func refresh_camp(camp: Dictionary, can_depart: bool) -> void:
	refresh(camp.get("crew", []))
	_can_depart = can_depart
	for id: String in facilities:
		facilities[id] = CampSceneLayout.facility_level(camp, id)


func set_dusk(value: float) -> void:
	dusk = clampf(value, 0.0, 1.0)
	if is_instance_valid(_world):
		_world.modulate = Color.WHITE.lerp(Color("647d9a"), dusk * 0.6)
	atmosphere_changed.emit(atmosphere_name())


func atmosphere_name() -> String:
	return "白昼" if dusk <= 0.15 else "暖暮" if dusk < 0.625 else "蓝时" if dusk <= 0.80 else "夜色"


func pick(view_point: Vector2) -> Dictionary:
	var nearest: int = 0
	var depth: float = -INF
	for id: int in visible_member_ids:
		var foot: Vector2 = residents[id].position
		if Rect2(foot + Vector2(-24, -70), Vector2(48, 76)).has_point(view_point) and foot.y > depth:
			nearest = id
			depth = foot.y
	if nearest > 0:
		return {"action":&"crew", "member_id":nearest}
	# The visible workbench is a sub-area of the workshop.
	if CampSceneLayout.AREAS[&"weapons"].has_point(view_point):
		return {"action":&"weapons", "member_id":0}
	for id: String in facilities:
		if CampSceneLayout.FACILITIES[id].has_point(view_point):
			return {"facility":id}
	for action: StringName in CampSceneLayout.AREAS:
		if CampSceneLayout.AREAS[action].has_point(view_point):
			if action == &"bus" and not _can_depart:
				return {}
			return {"action":action, "member_id":0}
	return {}


func highlight(view_point: Vector2) -> void:
	var hit: Dictionary = pick(view_point)
	var id: int = int(hit.get("member_id", 0)) if hit.get("action", &"") == &"crew" else 0
	for member: int in visible_member_ids:
		residents[member].highlight(member == id)
