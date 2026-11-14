class_name CampSceneWorld
extends Node2D
## Original transit yard geometry, existing Blue Hour props; no camp simulation.

const BUS: Texture2D = preload("res://assets/candidates/bus_02.png")
const SHOP: Texture2D = preload("res://assets/candidates/shop_02.png")
const SHELTER: Texture2D = preload("res://assets/m401/market.png")

var visible_member_ids: Array[int] = []
var residents: Dictionary[int, Sprite2D] = {}


func _ready() -> void:
	_prop(SHELTER, Vector2(636, 374), 260, true)
	_prop(SHOP, Vector2(1046, 374), 240, false)
	var bus: Sprite2D = Sprite2D.new()
	bus.name = "ParkedBus"
	bus.texture = BUS
	bus.offset = Vector2(0, -128)
	bus.scale = Vector2.ONE * (280.0 / 448.0)
	bus.position = Vector2(278, 496)
	add_child(bus)
	for id: int in [1, 2, 3, 4, 5]:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = "Resident%d" % id
		sprite.centered = true
		sprite.texture = MotionAtlas.RIGHT[id - 1]
		sprite.hframes = 5
		sprite.vframes = 7
		sprite.frame = 1
		sprite.offset = Vector2(0, -96)
		sprite.scale = Vector2.ONE * 0.44
		sprite.position = CampSceneLayout.member_position(id)
		sprite.set_meta("member_id", id)
		sprite.hide()
		add_child(sprite)
		residents[id] = sprite


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, CampSceneLayout.SIZE), Color("23383b"))
	draw_rect(Rect2(0, 98, 84, 552), Color("17323e"))
	for y: int in range(110, 650, 34):
		draw_line(Vector2(4, y), Vector2(65, y - 12), Color("254957"), 2)
	draw_rect(Rect2(90, 98, 44, 552), Color("354b4d"))
	for y: int in range(112, 640, 76):
		draw_rect(Rect2(94, y, 8, 38), Color("8c9b91"))
	draw_rect(Rect2(136, 322, 1100, 296), Color("4d5955"))
	draw_rect(Rect2(426, 140, 416, 468), Color("627065"))
	draw_rect(Rect2(870, 138, 352, 360), Color("53645c"))
	# A south approach and east service lane give the yard a different plan from the reference.
	draw_rect(Rect2(136, 558, 1100, 62), Color("3b494b"))
	draw_rect(Rect2(824, 104, 44, 520), Color("435351"))
	for x: int in range(158, 1200, 96):
		draw_line(Vector2(x, 590), Vector2(x + 42, 590), Color("9a9c7f"), 3)
	for index: int in range(120):
		var point: Vector2 = Vector2(150 + (index * 139) % 1050, 126 + (index * 71) % 484)
		draw_line(point, point + Vector2(5, 1), Color(0.72, 0.77, 0.66, 0.10), 1)
	for x: int in [156, 400]:
		draw_line(Vector2(x, 378), Vector2(x, 535), Color("afb5a2"), 2)
	for y: int in [390, 526]:
		draw_line(Vector2(164, y), Vector2(198, y), Color("afb5a2"), 2)
	# Low cost original fire/benches and supply crates are replaceable prototype props.
	draw_circle(Vector2(268, 250), 37, Color("27383b"))
	for index: int in range(8):
		var point: Vector2 = Vector2(268, 250) + Vector2.from_angle(index * TAU / 8) * 27
		draw_circle(point, 7, Color("879086"))
	draw_line(Vector2(249, 261), Vector2(285, 242), Color("785e42"), 8)
	draw_line(Vector2(250, 244), Vector2(283, 263), Color("9c7651"), 7)
	draw_colored_polygon(PackedVector2Array([Vector2(254, 253), Vector2(264, 220), Vector2(272, 241), Vector2(281, 228), Vector2(284, 254)]), Color("e6a565"))
	for x: int in [196, 320]:
		draw_rect(Rect2(x, 232, 24, 50), Color("897655"))
		draw_rect(Rect2(x + 3, 235, 18, 4), Color("b5a17a"))
	for x: int in [927, 986, 1045, 1104]:
		_crate(Vector2(x, 553), Color("8a795a"))
	_crate(Vector2(956, 526), Color("718674"))
	_crate(Vector2(1074, 526), Color("718674"))
	draw_rect(Rect2(948, 409, 170, 21), Color("a48b63"))
	for x: int in [956, 1099]:
		draw_rect(Rect2(x, 430, 10, 18), Color("6c5b49"))
	draw_line(Vector2(976, 414), Vector2(1017, 414), Color("24383e"), 6)
	draw_line(Vector2(1000, 414), Vector2(1008, 424), Color("24383e"), 5)
	for point: Vector2 in [Vector2(166, 142), Vector2(1215, 620), Vector2(1208, 108)]:
		draw_circle(point + Vector2(8, 5), 32, Color(0.04, 0.09, 0.08, 0.18))
		draw_circle(point, 29, Color("345c54"))
		draw_circle(point + Vector2(-8, -6), 20, Color("527363"))


func refresh(members: Array) -> void:
	visible_member_ids.clear()
	for id: int in residents:
		residents[id].hide()
	for member: Dictionary in members:
		if member.health <= 0 or not residents.has(int(member.id)):
			continue
		var definition: SurvivorDefinition = SurvivorRoster.definition_for(member)
		# HUD / roster use face close-ups; camp yard keeps the official standing sprite.
		residents[int(member.id)].set_meta("definition_id", definition.id)
		residents[int(member.id)].show()
		visible_member_ids.append(int(member.id))
	visible_member_ids.sort()
	if members.any(func(member: Dictionary) -> bool: return int(member.id)>3) or members.size()>3:
		for slot: int in range(visible_member_ids.size()):
			residents[visible_member_ids[slot]].position = Vector2(470+slot*114,476)
	else:
		for id: int in residents:
			residents[id].position = CampSceneLayout.member_position(id)


func _prop(texture: Texture2D, point: Vector2, width: float, shelter: bool) -> void:
	var prop: FieldProp = FieldProp.new()
	prop.facade = texture
	prop.position = point
	prop.front_width = width
	prop.is_residence = true
	prop.is_market = shelter
	prop.searchable = false
	add_child(prop)


func _crate(point: Vector2, colour: Color) -> void:
	draw_rect(Rect2(point + Vector2(4, 6), Vector2(48, 30)), Color(0.08, 0.13, 0.12, 0.3))
	draw_rect(Rect2(point, Vector2(48, 30)), colour)
	draw_rect(Rect2(point, Vector2(48, 30)), Color("b8b195"), false, 2)
	draw_line(point + Vector2(3, 3), point + Vector2(45, 27), Color("b0a486"), 2)
