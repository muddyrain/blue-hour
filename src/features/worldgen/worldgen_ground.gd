class_name WorldgenGround
extends Node2D
## Flat materials read the frozen roads/parcels; no independent collision geometry.
var layout: StreetLayout
var supply_entrances: Array[Vector2] = []
var _light_pool: GradientTexture2D


func _ready() -> void:
	if not _blue_hour():
		return
	var falloff: Gradient = Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.36), Color(1, 1, 1, 0)])
	_light_pool = GradientTexture2D.new()
	_light_pool.gradient = falloff
	_light_pool.fill = GradientTexture2D.FILL_RADIAL
	_light_pool.fill_from = Vector2(0.5, 0.5)
	_light_pool.fill_to = Vector2(1.0, 0.5)


func _draw() -> void:
	var doors: Array[Vector2] = supply_entrances.duplicate()
	IsoDraw.ground(self, layout, doors, true)
	if layout.world_data.has("loading_yard"):
		IsoDraw.fill(self, WorldLayout.rect(layout.world_data.loading_yard.bounds), Color("4a5560"))
		IsoDraw.stroke(self, WorldLayout.rect(layout.world_data.loading_yard.bounds), Color("6a7580"), 1.5)
	if layout.world_data.has("rescue_court"):
		IsoDraw.fill(self, WorldLayout.rect(layout.world_data.rescue_court.bounds), Color("8b9890"))
		IsoDraw.stroke(self, WorldLayout.rect(layout.world_data.rescue_court.bounds), Color("7f8778"), 1.5)
	for parcel: Dictionary in layout.world_data.get("parcels", []):
		for detail: Dictionary in parcel.get("dressing", []):
			if detail.has("surface"):
				IsoDraw.fill(self, WorldLayout.rect(detail.get("rect", detail.get("surface", [0,0,1,1]))), Color("9aa392"))


func _junction_curbs(junction: Rect2) -> void:
	for step: int in range(0, int(junction.size.x), 16):
		var x: float = junction.position.x + step
		var y: float = junction.position.y + step
		for edge: Array in [
			[Vector2(x, junction.position.y - 2), Vector2.RIGHT],
			[Vector2(x, junction.end.y + 2), Vector2.RIGHT],
			[Vector2(junction.position.x - 2, y), Vector2.DOWN],
			[Vector2(junction.end.x + 2, y), Vector2.DOWN],
		]:
			if not _junction(edge[0] + edge[1] * 8.0, junction):
				draw_line(edge[0], edge[0] + edge[1] * 16.0, Color("81898c"), 3.0)


func _blue_hour() -> bool:
	return layout.world_data.has("open_streets") or not supply_entrances.is_empty() or layout.world_data.has("loading_yard") or layout.world_data.has("rescue_court")


func _rescue_court_floor(court: Dictionary) -> void:
	var target: Vector2 = WorldLayout.point(court.target)
	var front: Vector2 = WorldLayout.point(court.front.gate)
	# The front terrace contrasts with the narrow tiled alley and leaves the real gaps open.
	var terrace: Rect2 = Rect2(target - Vector2(73.0, 56.0), Vector2(front.x - target.x + 155.0, 152.0))
	draw_rect(terrace.grow(5.0), Color("34454f"))
	_paving(terrace)


func _rescue_court_lights(court: Dictionary) -> void:
	var front: Vector2 = WorldLayout.point(court.front.gate)
	var side: Vector2 = WorldLayout.point(court.side.gate)
	var target: Vector2 = WorldLayout.point(court.target)
	_yard_lamp_pool(front + Vector2(-69.0, 5.0), Vector2(90.0, 96.0), 0.45)
	_yard_lamp_pool(front + Vector2(69.0, 5.0), Vector2(90.0, 96.0), 0.45)
	_yard_lamp_pool(side + Vector2(36.0, -3.0), Vector2(76.0, 70.0), 0.32)
	_yard_lamp_pool(WorldLayout.point(court.side.path[3]) + Vector2(25.0, 10.0), Vector2(90.0, 76.0), 0.30)
	_yard_lamp_pool(target - Vector2(0.0, 24.0), Vector2(152.0, 112.0), 0.51)


func _loading_yard_floor(yard: Dictionary) -> void:
	var gate: Vector2 = WorldLayout.point(yard.loading.gate)
	var surface: Rect2 = WorldLayout.rect(yard.bounds).grow(-12)
	surface.size.y = gate.y - 8.0 - surface.position.y
	draw_rect(surface, Color("3e4953"))
	draw_texture_rect(StreetBlock.AsphaltTexture, surface, true, Color(0.62, 0.71, 0.83, 0.31))


func _loading_yard_surface(yard: Dictionary) -> void:
	var loading_gate: Vector2 = WorldLayout.point(yard.loading.gate)
	var service_gate: Vector2 = WorldLayout.point(yard.service.gate)
	var work_point: Vector2 = WorldLayout.point(yard.work_point)
	var apron: Rect2
	for footprint: Array in yard.loading.paving:
		var slab: Rect2 = WorldLayout.rect(footprint)
		draw_rect(slab, Color("424e5a"))
		draw_texture_rect(StreetBlock.AsphaltTexture, slab, true, Color(0.67, 0.76, 0.88, 0.43))
		if slab.get_area() > apron.get_area():
			apron = slab
	# Draw all shoulders before the tiles so intersecting legs read as one paved bend.
	for footprint: Array in yard.service.paving:
		draw_rect(WorldLayout.rect(footprint).grow(3), Color("34444d"))
	for footprint: Array in yard.service.paving:
		_paving(WorldLayout.rect(footprint))
	var paint: Color = Color(0.73, 0.57, 0.34, 0.46)
	# Worn approach paint stays within the frozen apron and leaves the work point open.
	for side: float in [-1.0, 1.0]:
		var x: float = loading_gate.x + side * 51.0
		for y: float in [loading_gate.y - 50.0, loading_gate.y - 86.0, loading_gate.y - 122.0]:
			var start: Vector2 = Vector2(x, y)
			var end: Vector2 = start - Vector2(0, 23)
			if apron.has_point(start) and apron.has_point(end):
				draw_line(start, end, paint, 2.0, true)
	for offset: int in range(-48, 48, 16):
		var start: Vector2 = loading_gate + Vector2(offset, 5)
		var stroke: Vector2 = Vector2(9, -10) if offset != -16 else Vector2(5, -6)
		draw_line(start, start + stroke, paint, 3.0, true)
	for offset: float in [-18.0, 14.0]:
		var start: Vector2 = service_gate + Vector2(offset, 1)
		draw_line(start, start + Vector2(7, 0), Color(0.72, 0.71, 0.61, 0.44), 2.0, true)
	var stop_line: Rect2 = Rect2(work_point + Vector2(-36, 30), Vector2(72, 3))
	if apron.encloses(stop_line):
		draw_rect(stop_line, paint)


func _loading_yard_lights(yard: Dictionary) -> void:
	var loading_gate: Vector2 = WorldLayout.point(yard.loading.gate)
	var service_gate: Vector2 = WorldLayout.point(yard.service.gate)
	var work_point: Vector2 = WorldLayout.point(yard.work_point)
	_yard_lamp_pool(loading_gate + Vector2(-70, 5), Vector2(78, 70), 0.32)
	_yard_lamp_pool(loading_gate + Vector2(70, 5), Vector2(78, 70), 0.32)
	_yard_lamp_pool(service_gate + Vector2(36, 1), Vector2(80, 81), 0.36)
	_yard_lamp_pool(work_point - Vector2(0, 21), Vector2(146, 104), 0.43)


func _yard_lamp_pool(point: Vector2, size: Vector2, opacity: float) -> void:
	draw_texture_rect(_light_pool, Rect2(point - size * 0.5, size), false, Color(1.0, 0.67, 0.32, opacity))
	var core: Vector2 = size * 0.36
	draw_texture_rect(_light_pool, Rect2(point - core * 0.5, core), false, Color(1.0, 0.77, 0.47, opacity * 0.73))


func _walk_edges(walk: Rect2) -> void:
	draw_line(walk.position, Vector2(walk.position.x, walk.end.y), Color("667684"), 1)
	draw_line(Vector2(walk.end.x, walk.position.y), walk.end, Color("293d46"), 2)


func _crossing_landings(road: Rect2, y: float) -> void:
	for x: float in [road.position.x - 15, road.end.x + 4]:
		var landing: Rect2 = Rect2(x, y - 1, 11, 20)
		draw_rect(landing, Color("857963"))
		for rib: int in range(3, 19, 4):
			var start: Vector2 = landing.position + Vector2(2, rib)
			draw_line(start, start + Vector2(7, 0), Color("b5a484"), 1)


func _curb(point: Vector2, tangent: Vector2, side: int, road: Rect2, drain: bool) -> void:
	var end: Vector2 = point + tangent * 32.0
	if _junction(end, road):
		return
	var outside: Vector2 = (Vector2.DOWN if tangent == Vector2.RIGHT else Vector2.RIGHT) * side
	draw_line(point - outside * 2.0, end - outside * 2.0, Color("192a38"), 5)
	draw_line(point + outside, end + outside, Color("798794"), 2)
	draw_line(point + outside * 4.0, end + outside * 4.0, Color("5a6977"), 1)
	draw_line(point, point + outside * 5.0, Color("354655"), 1)
	if drain:
		var inset: Vector2 = point - outside * 6.0
		draw_line(inset, inset + tangent * 19.0, Color("172633"), 5)
		for rung: int in range(2, 18, 4):
			var start: Vector2 = inset + tangent * rung
			draw_line(start - outside * 1.4, start + outside * 1.4, Color("556874"), 1)


func _bus_curb_paint() -> void:
	var stop: Rect2 = layout.bus_block
	for road: Rect2 in layout.roads:
		if road.size.y != WorldgenScale.MAIN_WIDTH or not road.has_point(stop.get_center()):
			continue
		var curb_y: float = road.end.y - 12.0 if layout.bus_door.y > road.get_center().y else road.position.y + 12.0
		for offset: float in [26.0, 104.0, 182.0]:
			var start: Vector2 = Vector2(stop.position.x + offset, curb_y)
			var end: Vector2 = start + Vector2(32, 0)
			if road.has_point(start) and road.has_point(end) and not _junction(start, road) and not _junction(end, road):
				draw_line(start, end, Color(0.52, 0.58, 0.62, 0.46), 2.0, true)
		return


func _supply_lights() -> void:
	for index: int in range(supply_entrances.size()):
		var door: Vector2 = supply_entrances[index]
		var color: Color = Color(1.0, 0.68, 0.32, 0.37) if index == 0 else Color(1.0, 0.76, 0.48, 0.30)
		draw_texture_rect(_light_pool, Rect2(door - Vector2(77, 58), Vector2(154, 99)), false, color)
		draw_texture_rect(_light_pool, Rect2(door - Vector2(32, 45), Vector2(64, 42)), false, Color(1.0, 0.78, 0.50, 0.35))
		draw_line(door + Vector2(-20, -30), door + Vector2(20, -30), Color(0.86, 0.67, 0.42, 0.65), 2)
	for detail: Dictionary in NeighborhoodDecor.placements(layout):
		if detail.kind == "lamp":
			var origin: Vector2 = detail.position + Vector2(-35, -35)
			draw_texture_rect(_light_pool, Rect2(origin, Vector2(140, 74)), false, Color(1.0, 0.68, 0.32, 0.28))

func _court(court: Dictionary) -> void:
	var area: Rect2=WorldLayout.rect(court.rect)
	var garden: bool=court.kind=="garden"
	var parking: bool=court.kind=="parking"
	var loading: bool=court.kind=="loading"
	var street_material: bool = int(layout.world_data.get("art_revision", 0)) == 3
	var blue_hour: bool = _blue_hour()
	if street_material:
		if garden:
			draw_rect(area, Color("3b5049") if blue_hour else Color("5d684a"))
			draw_texture_rect(StreetBlock.GrassTexture, area, true, Color(0.58, 0.70, 0.73, 0.55) if blue_hour else Color(0.94, 0.96, 0.81, 0.67))
		elif parking or loading:
			draw_rect(area, Color("4a5560") if blue_hour else Color("6d7069"))
			draw_texture_rect(StreetBlock.ConcreteTexture, area, true, Color(0.66, 0.73, 0.85, 0.53) if blue_hour else Color(0.92, 0.91, 0.84, 0.55))
		else:
			_paving(area)
	else:
		draw_rect(area.grow(3),Color("46574d") if garden else Color("535f5f"))
		draw_rect(area,Color("506b49") if garden else Color("5b6869") if parking or loading else Color("858c7c"))
		draw_texture_rect(StreetBlock.GrassTexture if garden else StreetBlock.ConcreteTexture if parking or loading else StreetBlock.PavingTexture,area,true,Color(0.82,0.87,0.78,0.55))
	if garden:
		# Low planting and soil remain traversable; raised hedges have frozen collisions.
		var bed: Rect2=Rect2(area.position+Vector2(8,8),Vector2(maxf(8,area.size.x-16),minf(38,area.size.y*0.22)))
		draw_rect(bed,Color("33463e") if blue_hour else Color("4c5440"))
		for x: int in range(int(bed.position.x)+8,int(bed.end.x)-4,19):
			draw_circle(Vector2(x,bed.get_center().y),5,Color("79945b"))
			if x%3==0:draw_circle(Vector2(x-2,bed.get_center().y-2),1.8,Color("cec277"))
	elif parking or loading:
		var stripe: Color = Color("929487") if blue_hour else Color("c2c1a5")
		for x: int in range(int(area.position.x)+20,int(area.end.x)-132,164):
			var y: float=area.position.y+8
			var depth: float=minf(86,area.size.y-16)
			draw_line(Vector2(x,y),Vector2(x,y+depth),stripe,2)
			draw_line(Vector2(x,y+depth),Vector2(x+132,y+depth),stripe,2)
		if loading:
			for x: int in range(int(area.position.x)+12,int(area.end.x)-16,24):
				draw_line(Vector2(x,area.end.y-8),Vector2(x+12,area.end.y-20),Color("95866b") if blue_hour else Color("b8a877"),3)

func _junction(point: Vector2,current: Rect2) -> bool:
	for other: Rect2 in layout.roads:
		if other!=current and other.grow(5).has_point(point): return true
	return false

func _paving(area: Rect2) -> void:
	# The raw material has an odd staggered row count, so panel joints are explicit.
	# World-aligned crops keep adjoining walks and shop aprons continuous at 256 units.
	var patch: float = StreetModuleArt.PAVING_PATCH
	var ratio: float = float(WorldgenArt.PAVING.get_width()) / patch
	var left: int = int(floor(area.position.x / patch))
	var top: int = int(floor(area.position.y / patch))
	var right: int = int(ceil(area.end.x / patch))
	var bottom: int = int(ceil(area.end.y / patch))
	var blue_hour: bool = _blue_hour()
	var material: Color = Color(0.64, 0.72, 0.85) if blue_hour else Color(1.0, 0.97, 0.89)
	var joint: Color = Color(0.16, 0.24, 0.32, 0.48) if blue_hour else Color(0.37, 0.36, 0.33, 0.48)
	for y: int in range(top, bottom):
		for x: int in range(left, right):
			var origin: Vector2 = Vector2(x, y) * patch
			var panel: Rect2 = Rect2(origin, Vector2.ONE * patch).intersection(area)
			var source: Rect2 = Rect2((panel.position - origin) * ratio, panel.size * ratio)
			draw_texture_rect_region(WorldgenArt.PAVING, panel, source, material)
	for x: int in range(left + 1, right):
		draw_line(Vector2(x * patch, area.position.y), Vector2(x * patch, area.end.y), joint, 1.1)
	for y: int in range(top + 1, bottom):
		draw_line(Vector2(area.position.x, y * patch), Vector2(area.end.x, y * patch), joint, 1.1)
