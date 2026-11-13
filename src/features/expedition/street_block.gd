class_name StreetBlock
extends Node2D
## Authored ground is presentation; the same layout supplies every navigation blocker.

const BOUNDS: Rect2 = Rect2(0, 0, 1920, 1440)
const AsphaltTexture: Texture2D = preload("res://assets/m402/asphalt.png")
const PavingTexture: Texture2D = preload("res://assets/m402/paving.png")
const GrassTexture: Texture2D = preload("res://assets/m402/grass.png")
const ConcreteTexture: Texture2D = preload("res://assets/m402/concrete.png")

var layout: StreetLayout
var supply_entrances: Array[Vector2] = []


func _ready() -> void:
	if layout.world_data.get("version")==5:
		var surface: WorldgenGround = WorldgenGround.new()
		surface.layout = layout
		surface.supply_entrances = supply_entrances
		add_child(surface)
		return

var food_source_visible: bool = true


func _draw() -> void:
	if layout.world_data.get("version")==5:
		return
	var doors: Array[Vector2] = supply_entrances.duplicate()
	if doors.is_empty():
		if layout.cash_door != Vector2.ZERO:
			doors.append(layout.cash_door)
		if layout.food_door != Vector2.ZERO:
			doors.append(layout.food_door)
	IsoDraw.ground(self, layout, doors, food_source_visible)


func _draw_markings(road: Rect2) -> void:
	var horizontal: bool = road.size.x > road.size.y
	var count: int = int((road.size.x if horizontal else road.size.y) / 88)
	for index: int in range(count):
		var point: Vector2 = Vector2(road.position.x + 16 + index * 88, road.get_center().y) if horizontal else Vector2(road.get_center().x, road.position.y + 16 + index * 88)
		var at_junction: bool = false
		for other: Rect2 in layout.roads:
			if other != road and other.grow(32).has_point(point):
				at_junction = true
		if not at_junction:
			draw_line(point, point + (Vector2(36, 0) if horizontal else Vector2(0, 36)), Color("cebd8b"), 2)
	# A few verge leaves and drainage grooves, all flat and traversable.
	for index: int in range(count):
		var point: Vector2 = road.position + (Vector2(24 + index * 88, -15) if horizontal else Vector2(-15, 24 + index * 88))
		draw_line(point, point + Vector2(5, 2), Color("9b956b"), 2)
		if index % 5 == 0:
			draw_rect(Rect2(point + Vector2(8, 2), Vector2(18, 10)), Color("62746e"))
			for groove: int in range(3):
				draw_line(point + Vector2(11 + groove * 5, 3), point + Vector2(11 + groove * 5, 10), Color("384f54"), 1)


func _draw_world() -> void:
	var bounds: Rect2 = layout.world_bounds
	draw_rect(bounds,Color("697b78"))
	draw_texture_rect(ConcreteTexture,bounds,true,Color(0.84,0.94,0.95,0.68))
	# Continuous paving, distinct block courts, and curb modules share the street axes.
	for row: Dictionary in layout.world_data.entities:
		var body: Rect2 = Rect2(row.rect[0],row.rect[1],row.rect[2],row.rect[3])
		var court: Rect2 = Rect2(body.position-Vector2(24,16),body.size+Vector2(48,100))
		draw_rect(court,Color("8b9890"))
		draw_texture_rect(PavingTexture,court,true,Color(0.9,1,0.96,0.40))
		for i: int in range(int(court.size.x/32)):
			var x: float = court.position.x+i*32
			draw_line(Vector2(x,body.end.y),Vector2(x,court.end.y),Color(0.23,0.34,0.35,0.22),1)
		var verge: Rect2 = Rect2(body.position+Vector2(-20,-20),Vector2(body.size.x+40,32))
		draw_rect(verge,Color("4a6460")); draw_texture_rect(GrassTexture,verge,true,Color(0.7,0.9,0.8,0.5))
	for road: Rect2 in layout.roads:
		draw_rect(road.grow(34),Color("b0b5a0"))
		draw_texture_rect(PavingTexture,road.grow(30),true,Color(0.95,1,0.97,0.70))
	for road: Rect2 in layout.roads:
		draw_rect(road,Color("344d59")); draw_texture_rect(AsphaltTexture,road,true,Color(0.8,0.95,1,0.64))
	for road: Rect2 in layout.roads: _draw_markings(road)
	# Pedestrian crossings beside the three vertical connections; never an obstacle.
	for x: int in [560,1184,1840]:
		for stripe: int in range(8):
			draw_rect(Rect2(x-52,1130+stripe*27,40,12),Color("b9bba8"))
		for side: int in [-1,1]:
			var y: float = 1120 if side<0 else 1360
			draw_line(Vector2(x-42,y),Vector2(x-42,y+side*18),Color("e1be72"),5)
	var parking: Rect2 = layout.bus_block.grow(14)
	draw_rect(parking,Color("ddd2a3"),false,2)
	for row: Dictionary in layout.world_data.entities:
		var door: Vector2 = Vector2(row.door[0],row.door[1])
		draw_circle(door,14,Color(0.9,0.78,0.45,0.12))
		draw_arc(door,14,0,TAU,24,Color("c7ba8c"),1.5)
