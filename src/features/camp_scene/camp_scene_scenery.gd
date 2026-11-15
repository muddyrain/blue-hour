class_name CampSceneScenery
extends Node2D
## Original procedural camp furnishings, combined with the project's iso atlas.

var kind: String = ""
var facility_id: String = ""
var tier: int = -1
var footprint: Vector2 = Vector2(32, 24)
var _art: Sprite2D
var _clock: float = 0.0


func set_tier(value: int) -> void:
	if tier == value:
		return
	tier = value
	if is_instance_valid(_art):
		remove_child(_art)
		_art.queue_free()
		_art = null
	if tier > 0:
		var archetype: String = "garage" if tier == 1 else "warehouse"
		if facility_id == "planning":
			archetype = "row_house" if tier == 1 else "detached_home"
		var rel: String = IsoBuildingArt.pick({"id":"camp_" + facility_id, "archetype":archetype,
			"rect":[0, 0, footprint.x, footprint.y], "variant":tier})
		var authored: Array = IsoAtlas.info(rel).get("map", [footprint.x, footprint.y])
		var fit: float = minf(footprint.x / float(authored[0]), footprint.y / float(authored[1]))
		_art = IsoAtlas.attach(self, rel, fit)
		_art.light_mask = 2
	queue_redraw()


func advance(delta: float) -> void:
	_clock += delta
	if kind == "fire":
		queue_redraw()


func _draw() -> void:
	match kind:
		"facility": _draw_facility()
		"fire": _draw_fire()
		"bench": _draw_bench()
		"fence":
			IsoDraw.box(self, footprint, 16, Color("b8aa8d"), Color("827867"), Color("746e61"))
			for x: float in [-footprint.x * 0.45, footprint.x * 0.45]:
				var at: Vector2 = IsoSpace.to_view(Vector2(x, 0))
				draw_line(at, at + Vector2(0, -27), Color("c8b99b"), 3, true)
		"weapons":
			IsoDraw.box(self, Vector2(64, 32), 18, Color("ac8a61"), Color("75644f"), Color("5d574a"))
			for index: int in range(3):
				var at: Vector2 = Vector2(-12 + index * 15, -23 + index * 5)
				draw_line(at, at + Vector2(15, -7.5), Color("ddd1b5"), 2, true)
		"crate": _draw_crate()
		"lamp": IsoDraw.lamp(self)
		"clothesline": _draw_clothesline()
		"bucket": _draw_bucket()
		"bicycle": _draw_bicycle()
		"planter": _draw_planter()
		"blackboard": _draw_blackboard()


func _draw_bench() -> void:
	for x: float in [-25.0, 25.0]:
		var leg: Vector2 = IsoSpace.to_view(Vector2(x, -8))
		draw_line(leg, leg + Vector2(0, -14), Color("655b4c"), 4, true)
	IsoDraw.box(self, Vector2(64, 22), 14, Color("b4976f"), Color("7d664b"), Color("6f5c48"))
	for y: float in [-7.0, -14.0]:
		draw_line(IsoSpace.to_view(Vector2(-32, y)) + Vector2(0, -14), IsoSpace.to_view(Vector2(32, y)) + Vector2(0, -14), Color("74624e"), 1, true)
	var left: Vector2 = IsoSpace.to_view(Vector2(-32, -20))
	var right: Vector2 = IsoSpace.to_view(Vector2(32, -20))
	for end: Vector2 in [left, right]:
		draw_line(end, end + Vector2(0, -32), Color("655b4c"), 3, true)
	draw_colored_polygon(PackedVector2Array([left + Vector2(0, -20), right + Vector2(0, -20), right + Vector2(0, -30), left + Vector2(0, -30)]), Color("ac8a61"))


func _draw_crate() -> void:
	IsoDraw.box(self, footprint, 22, Color("af9065"), Color("92734f"), Color("7d684e"))
	var left: Vector2 = IsoSpace.to_view(Vector2(-footprint.x * 0.5, 0))
	var right: Vector2 = IsoSpace.to_view(Vector2(footprint.x * 0.5, 0))
	for amount: float in [0.25, 0.5, 0.75]:
		var at: Vector2 = left.lerp(right, amount)
		draw_line(at, at + Vector2(0, -22), Color("695842"), 1, true)
	draw_line(left + Vector2(2, -2), right + Vector2(-2, -20), Color("ccb38a"), 3, true)
	draw_line(left + Vector2(2, -20), right + Vector2(-2, -2), Color("b79a71"), 2, true)


func _draw_clothesline() -> void:
	var left: Vector2 = IsoSpace.to_view(Vector2(-40, 0))
	var right: Vector2 = IsoSpace.to_view(Vector2(40, 0))
	for end: Vector2 in [left, right]:
		draw_line(end, end + Vector2(0, -48), Color("9c8564"), 4, true)
	var rope_left: Vector2 = left + Vector2(0, -44)
	var rope_right: Vector2 = right + Vector2(0, -44)
	var sag: Vector2 = (rope_left + rope_right) * 0.5 + Vector2(0, 4)
	draw_polyline(PackedVector2Array([rope_left, sag, rope_right]), Color("d5c7a7"), 1.5, true)
	var cloth_colours: Array[Color] = [Color("ddd4b9"), Color("819b9c"), Color("b5876a")]
	for index: int in range(3):
		var at: Vector2 = rope_left.lerp(rope_right, 0.18 + index * 0.25) + Vector2(0, 3)
		var edge: Vector2 = IsoSpace.to_view(Vector2(15, 0))
		draw_colored_polygon(PackedVector2Array([at, at + edge, at + edge + Vector2(-1, 20), at + Vector2(1, 20)]), cloth_colours[index])
		draw_line(at + Vector2(4, 2), at + Vector2(4, 17), Color(1, 1, 1, 0.22), 1, true)
		draw_line(at + Vector2(2, -3), at + Vector2(2, 3), Color("8c7252"), 2, true)


func _draw_bucket() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(-9, -17), Vector2(9, -17), Vector2(7, -2), Vector2(-7, -2)]), Color("88999a"))
	_ellipse(Vector2(0, -3), Vector2(7, 3.5), Color("6a7d80"))
	_ellipse(Vector2(0, -17), Vector2(9, 4.5), Color("c1ccbf"))
	_ellipse(Vector2(0, -17), Vector2(6.5, 2.8), Color("596e73"))
	draw_arc(Vector2(0, -18), 8, PI, TAU, 16, Color("ddd1b5"), 1.5, true)
	draw_line(Vector2(-5, -13), Vector2(-4, -5), Color("b0bdb2"), 1.5, true)


func _draw_bicycle() -> void:
	var rear: Vector2 = IsoSpace.to_view(Vector2(-22, 0)) + Vector2(0, -11)
	var front: Vector2 = IsoSpace.to_view(Vector2(22, 0)) + Vector2(0, -11)
	for center: Vector2 in [rear, front]:
		var rim: PackedVector2Array = PackedVector2Array()
		for index: int in range(25):
			var angle: float = index * TAU / 24.0
			rim.append(center + IsoSpace.to_view(Vector2(cos(angle) * 11, 0)) + Vector2(0, sin(angle) * 11))
		draw_polyline(rim, Color("343b3a"), 3, true)
		draw_line(rim[0], rim[12], Color("b0b8ac"), 1, true)
		draw_line(rim[6], rim[18], Color("b0b8ac"), 1, true)
	var crank: Vector2 = (rear + front) * 0.5 + Vector2(0, 2)
	var saddle: Vector2 = rear.lerp(front, 0.30) + Vector2(0, -20)
	var handle: Vector2 = front + Vector2(-5, -23)
	var frame_colour: Color = Color("b08162")
	draw_polyline(PackedVector2Array([rear, saddle, crank, rear]), frame_colour, 2.5, true)
	draw_polyline(PackedVector2Array([saddle, handle, crank, front, handle]), frame_colour, 2.5, true)
	draw_line(saddle + Vector2(-6, -2), saddle + Vector2(7, 4), Color("514d42"), 4, true)
	draw_line(handle, handle + Vector2(8, -3), Color("b8bdae"), 2, true)
	draw_line(crank + Vector2(-4, 4), crank + Vector2(5, -2), Color("ddd1b5"), 2, true)
	IsoDraw.stroke(self, Rect2(12, -12, 16, 12), Color("bbac8d"), 1)


func _draw_planter() -> void:
	IsoDraw.box(self, footprint, 12, Color("615e49"), Color("aa8969"), Color("8c735a"))
	for index: int in range(5):
		var at: Vector2 = Vector2(-9 + index * 4, -17 - float(index % 2) * 4)
		draw_line(at + Vector2(0, 5), at + Vector2(0, -5), Color("657e58"), 2, true)
		draw_circle(at + Vector2(-3, 0), 4, Color("70865b"))
		draw_circle(at + Vector2(3, -3), 3, Color("829367"))
		if index % 2 == 0:
			draw_circle(at + Vector2(0, -6), 2.5, Color("e0bc86"))


func _draw_blackboard() -> void:
	var left: Vector2 = IsoSpace.to_view(Vector2(-22, 0))
	var right: Vector2 = IsoSpace.to_view(Vector2(22, 0))
	for end: Vector2 in [left, right]:
		draw_line(end, end + Vector2(0, -40), Color("9b805d"), 4, true)
	var corners: PackedVector2Array = PackedVector2Array([left + Vector2(0, -12), right + Vector2(0, -12), right + Vector2(0, -38), left + Vector2(0, -38)])
	draw_colored_polygon(corners, Color("46574e"))
	draw_polyline(PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]), Color("b39970"), 3, true)
	for index: int in range(3):
		var start: Vector2 = left + Vector2(7, -30 + index * 6)
		draw_line(start, start + (right - left) * (0.60 if index == 0 else 0.42), Color("d3d5bc"), 1.2, true)


func _ellipse(center: Vector2, radii: Vector2, colour: Color) -> void:
	draw_set_transform(center, 0.0, radii)
	draw_circle(Vector2.ZERO, 1.0, colour)
	draw_set_transform(Vector2.ZERO)


func _draw_facility() -> void:
	if tier == 0:
		var lot: Rect2 = Rect2(Vector2(-footprint.x * 0.5, -footprint.y), footprint)
		IsoDraw.fill(self, lot, Color("a29378"))
		IsoDraw.stroke(self, lot, Color("e4c994"), 2.0)
		for x: float in [-footprint.x * 0.45, footprint.x * 0.45]:
			var at: Vector2 = IsoSpace.to_view(Vector2(x, -footprint.y * 0.1))
			draw_line(at, at + Vector2(0, -16), Color("dfba7b"), 3, true)
		draw_set_transform(IsoSpace.to_view(Vector2(-footprint.x * 0.3, -footprint.y * 0.5)))
		IsoDraw.crate(self)
		draw_set_transform(Vector2.ZERO)
		return
	if tier >= 2:
		# Small additions sit on the south apron; the roof remains closed at every tier.
		draw_set_transform(IsoSpace.to_view(Vector2(-footprint.x * 0.3, 18)))
		if facility_id == "supply":
			IsoDraw.planter(self)
		elif facility_id == "workshop":
			IsoDraw.box(self, Vector2(40, 20), 18, Color("82918b"), Color("b4baa4"), Color("8a958b"))
		else:
			IsoDraw.box(self, Vector2(28, 16), 28, Color("9d886a"), Color("e8dcc4"), Color("b8ac96"))
		draw_set_transform(Vector2.ZERO)


func _draw_fire() -> void:
	for index: int in range(10):
		var at: Vector2 = Vector2.from_angle(index * TAU / 10.0) * Vector2(23, 11.5)
		draw_circle(at, 5, Color("8e8c80"))
	draw_line(Vector2(-15, 3), Vector2(15, -5), Color("806349"), 6, true)
	draw_line(Vector2(-13, -6), Vector2(13, 5), Color("9c7953"), 5, true)
	var sway: float = sin(_clock * 3.0) * 2.0
	draw_colored_polygon(PackedVector2Array([Vector2(-10, 0), Vector2(-6, -13), Vector2(sway, -26), Vector2(5, -10), Vector2(10, -18), Vector2(12, 0)]), Color("dc9c55"))
	draw_colored_polygon(PackedVector2Array([Vector2(-5, 0), Vector2(1, -15), Vector2(6, 0)]), Color("f7d89b"))
