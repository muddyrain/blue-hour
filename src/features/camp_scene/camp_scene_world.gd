class_name CampSceneWorld
extends Node2D
## Read-only isometric fishing-cooperative yard. Owns ambient presentation only.

signal atmosphere_changed(atmosphere: String)

var visible_member_ids: Array[int] = []
var residents: Dictionary[int, CampSceneResident] = {}
var facilities: Dictionary[String, CampSceneScenery] = {}
var stage: Node2D
var tiles: IsoTiles
var dusk: float = 0.46
var _scenery: Array[CampSceneScenery] = []
var _lights: Array[PointLight2D] = []
var _world: Node2D
var _can_depart: bool = true
var _light_texture: GradientTexture2D


func _ready() -> void:
	_world = Node2D.new()
	_world.name = "IsoYard"
	add_child(_world)
	tiles = IsoTiles.new()
	tiles.name = "CampTiles"
	_fill_tiles()
	_world.add_child(tiles)
	stage = Node2D.new()
	stage.name = "CampDepthSort"
	stage.y_sort_enabled = true
	_world.add_child(stage)
	for id: String in CampSceneLayout.FACILITIES:
		var rect: Rect2 = CampSceneLayout.FACILITIES[id]
		var site: CampSceneScenery = _detail("facility", IsoSpace.foot(rect))
		site.name = "Facility" + id.capitalize()
		site.facility_id = id
		site.footprint = rect.size
		site.set_tier(0)
		facilities[id] = site
	var bus: Node2D = Node2D.new()
	bus.name = "ParkedBus"
	IsoSpace.place(bus, IsoSpace.foot(CampSceneLayout.AREAS[&"bus"]))
	stage.add_child(bus)
	IsoAtlas.attach(bus, "props/bus.png")
	var shelter: Node2D = Node2D.new()
	shelter.name = "CrewShelter"
	IsoSpace.place(shelter, IsoSpace.foot(CampSceneLayout.AREAS[&"crew"]))
	stage.add_child(shelter)
	IsoAtlas.attach(shelter, IsoBuildingArt.prop_for("bike_shelter"), 0.8)
	_detail("weapons", IsoSpace.foot(CampSceneLayout.AREAS[&"weapons"]))
	_detail("fire", CampSceneLayout.FIRE)
	for at: Vector2 in [Vector2(248, 344), Vector2(328, 408)]:
		_detail("bench", at)
	for furnishing: Dictionary in CampSceneLayout.DRESSING:
		_detail(furnishing.kind, furnishing.at, furnishing.size)
	for at: Vector2 in CampSceneLayout.LAMPS:
		_detail("lamp", at)
		_add_light(IsoSpace.to_view(at) + Vector2(0, -54), 0.65)
	_add_light(IsoSpace.to_view(CampSceneLayout.FIRE), 0.75)
	for x: int in range(80, 720, 64):
		_detail("fence", Vector2(x, 32), Vector2(60, 8))
	for y: int in range(96, 480, 64):
		_detail("fence", Vector2(704, y), Vector2(8, 60))
		_detail("fence", Vector2(64, y), Vector2(8, 60))
	for x: int in [64, 288, 352, 416, 480, 544, 608, 672]:
		_detail("fence", Vector2(x, 448), Vector2(52, 8))
	for at: Vector2 in [Vector2(100, 172), Vector2(632, 224), Vector2(672, 288)]:
		var tree: Node2D = Node2D.new()
		IsoSpace.place(tree, at)
		stage.add_child(tree)
		IsoAtlas.attach(tree, IsoBuildingArt.prop_for("tree", int(at.x)), 0.8)
	for id: int in [1, 2, 3, 4, 5]:
		var resident: CampSceneResident = CampSceneResident.new()
		resident.name = "Resident%d" % id
		resident.member_id = id
		stage.add_child(resident)
		resident.hide()
		residents[id] = resident
	_set_world_light_mask(_world)
	set_dusk(dusk)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		advance(minf(delta, 0.1))


func advance(delta: float) -> void:
	for id: int in visible_member_ids:
		residents[id].advance(delta)
	for prop: CampSceneScenery in _scenery:
		prop.advance(delta)


func refresh(members: Array) -> void:
	visible_member_ids.clear()
	for id: int in residents:
		residents[id].hide()
	for member: Dictionary in members:
		var id: int = int(member.id)
		if float(member.health) <= 0.0 or not residents.has(id):
			continue
		residents[id].configure(member)
		residents[id].show()
		visible_member_ids.append(id)
	visible_member_ids.sort()


func refresh_camp(camp: Dictionary, can_depart: bool) -> void:
	refresh(camp.get("crew", []))
	_can_depart = can_depart
	for id: String in facilities:
		facilities[id].set_tier(CampSceneLayout.facility_level(camp, id))


func set_dusk(value: float) -> void:
	dusk = clampf(value, 0.0, 1.0)
	if not is_instance_valid(_world):
		return
	# A local modulate avoids CanvasModulate tinting menus on the shared canvas.
	_world.modulate = ExpeditionAtmosphere.tint_for(dusk)
	for light: PointLight2D in _lights:
		light.energy = 0.55 * smoothstep(0.25, 0.8, dusk)
	atmosphere_changed.emit(atmosphere_name())


func atmosphere_name() -> String:
	if dusk <= 0.15:
		return "白昼"
	if dusk < 0.625:
		return "暖暮"
	if dusk <= 0.80:
		return "蓝时"
	return "夜色"


func pick(view_point: Vector2) -> Dictionary:
	# Residents take priority over buildings, and use their current projected foot.
	var nearest: int = 0
	var depth: float = -INF
	for id: int in visible_member_ids:
		var foot: Vector2 = residents[id].position
		if Rect2(foot + Vector2(-22, -62), Vector2(44, 72)).has_point(view_point) and foot.y > depth:
			nearest = id
			depth = foot.y
	if nearest > 0:
		return {"action":&"crew", "member_id":nearest}
	for id: String in facilities:
		var site: CampSceneScenery = facilities[id]
		var sprite: Sprite2D = site.get_node_or_null("IsoSprite") as Sprite2D
		if sprite != null and sprite.get_rect().has_point(sprite.to_local(to_global(view_point))):
			return {"facility":id}
		if CampSceneLayout.FACILITIES[id].has_point(IsoSpace.to_map(view_point)):
			return {"facility":id}
	for action: StringName in CampSceneLayout.AREAS:
		var area: Rect2 = CampSceneLayout.AREAS[action]
		var foot: Vector2 = IsoSpace.to_view(IsoSpace.foot(area))
		if area.grow(12).has_point(IsoSpace.to_map(view_point)) or Rect2(foot + Vector2(-35, -50), Vector2(70, 65)).has_point(view_point):
			if action == &"bus" and not _can_depart:
				return {}
			return {"action":action, "member_id":0}
	return {}


func _fill_tiles() -> void:
	for y: int in range(-2, 19):
		for x: int in range(-3, 23):
			var tile: String = "grass"
			if x <= 0:
				tile = "canal"
			elif x == 1:
				tile = "bank"
			elif y >= 15 and y <= 17:
				tile = "road"
			elif y == 14 or y == 18:
				tile = "sidewalk"
			elif y >= 1 and y <= 13 and x >= 2 and x <= 21:
				tile = "gravel"
			if tile == "gravel":
				var center: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) * IsoTiles.TILE
				for path: Rect2 in CampSceneLayout.PATHS:
					if path.has_point(center):
						tile = "concrete"
						break
			if y == 16 and x > 1:
				tile = "road_ew"
			tiles.cells[Vector2i(x, y)] = tile


func _detail(kind: String, at: Vector2, footprint: Vector2 = Vector2(32, 24)) -> CampSceneScenery:
	var detail: CampSceneScenery = CampSceneScenery.new()
	detail.kind = kind
	detail.footprint = footprint
	IsoSpace.place(detail, at)
	stage.add_child(detail)
	_scenery.append(detail)
	return detail


func _add_light(at: Vector2, spread: float) -> void:
	if _light_texture == null:
		var gradient: Gradient = Gradient.new()
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0.65), Color(1, 1, 1, 0)])
		_light_texture = GradientTexture2D.new()
		_light_texture.gradient = gradient
		_light_texture.width = 256
		_light_texture.height = 256
		_light_texture.fill = GradientTexture2D.FILL_RADIAL
		_light_texture.fill_from = Vector2(0.5, 0.5)
		_light_texture.fill_to = Vector2(0.5, 1.0)
	var light: PointLight2D = PointLight2D.new()
	light.name = "CampWarmLight"
	light.position = at
	light.texture = _light_texture
	light.texture_scale = spread
	light.color = Color("ffa64a")
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.shadow_enabled = false
	light.range_item_cull_mask = 2
	_world.add_child(light)
	_lights.append(light)


func _set_world_light_mask(node: Node) -> void:
	if node is CanvasItem:
		node.light_mask = 2
	for child: Node in node.get_children():
		_set_world_light_mask(child)
