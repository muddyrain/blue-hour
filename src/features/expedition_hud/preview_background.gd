extends Node2D
## Static reuse of original project assets, not a running expedition.

const Asphalt: Texture2D = preload("res://assets/p03/asphalt_03.png")
const Grass: Texture2D = preload("res://assets/p03/grass_03.png")
const Shop: Texture2D = preload("res://assets/candidates/shop_02.png")
const Bus: Texture2D = preload("res://assets/candidates/bus_02.png")
const Survivor: Texture2D = preload("res://assets/p03/survivor_03.png")

var simulation_ticks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	get_viewport().size_changed.connect(queue_redraw)


func _physics_process(_delta: float) -> void:
	simulation_ticks += 1


func _draw() -> void:
	var extent: Vector2 = get_viewport_rect().size
	draw_texture_rect(Grass, Rect2(Vector2.ZERO, extent), true, Color(0.65, 0.72, 0.73))
	var road: Rect2 = Rect2(0, extent.y * 0.56, extent.x, 180)
	draw_texture_rect(Asphalt, road, true, Color(0.7, 0.8, 0.86))
	draw_texture_rect(Asphalt, Rect2(extent.x * 0.65, 0, 160, extent.y), true, Color(0.7, 0.8, 0.86))
	draw_dashed_line(Vector2(0, road.get_center().y), Vector2(extent.x, road.get_center().y), Color("d1d4b1"), 2, 30)
	draw_texture_rect(Shop, Rect2(extent.x * 0.20, extent.y * 0.23, 320, 280), false)
	draw_texture_rect(Shop, Rect2(extent.x * 0.75, extent.y * 0.22, 288, 252), false)
	draw_texture_rect(Bus, Rect2(40, road.position.y - 22, 240, 150), false)
	for index: int in range(2):
		var point: Vector2 = Vector2(340 + index * 58, road.get_center().y + index * 25)
		draw_arc(point + Vector2(36, 68), 17, 0, TAU, 32, C1ExpeditionHud.IDENTITY_COLORS[index], 2, true)
		draw_texture_rect_region(Survivor, Rect2(point, Vector2(80, 80)), Rect2(0, 0, 256, 256))
