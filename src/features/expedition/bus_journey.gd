class_name BusJourney
extends Node
## Presentation clock only. Frozen result is published by Main before departure begins.
signal departed()
const DRIVE_IN: float = 2.4
const DISEMBARK: float = 1.0
const EMBARK: float = 0.9
const DRIVE_OUT: float = 2.8
const BODY_HALF_SIZE: Vector2 = Vector2(120, 40)
# PROJECT_TEMP presentation speeds and disembark spacing.
const OPEN_ARRIVAL_SPEED: float = 650.0
const OPEN_DEPARTURE_SPEED: float = 780.0
const BOARDING_SPEED: float = 185.0
const ARRIVAL_STAGGER: float = 0.14
var stage: String = "arriving"
var clock: float = 0.0
var world: Expedition
var sprite: Sprite2D
var route: Dictionary
var stop: Vector2
var starts: Array[Vector2] = []
var boarding_starts: Array[Vector2] = []
var final_boarding: Vector2i = Vector2i.ZERO
var skip_button: Button
var _boarding_panel: PanelContainer
var _boarding_label: Label
var _open_body: OpenStreetBody
var _entry_path: JourneyPath
var _exit_path: JourneyPath
var _boarding_paths: Array[JourneyPath] = []
var _boarding_actors: Array[FieldActor] = []
var _boarding_index: int = 0

func configure(owner_world: Expedition, bus: Sprite2D, data: Dictionary) -> void:
	world=owner_world; sprite=bus; route=data.duplicate(true); stop=world.layout.bus_foot()
	for actor: FieldActor in world.survivors:
		starts.append(actor.position)
		actor.hide()
	IsoSpace.place(sprite, WorldLayout.point(route.entry))
	if route.has("in_path"):
		stop = WorldLayout.point(route.stop)
		_entry_path = JourneyPath.new(_route_points(route.in_path))
		_exit_path = JourneyPath.new(_route_points(route.out_path))
		# A top-down placeholder supports every heading without rotating the original facade art.
		sprite.texture = null
		sprite.offset = Vector2.ZERO
		sprite.scale = Vector2.ONE
		_open_body = OpenStreetBody.new()
		sprite.add_child(_open_body)
		_place_open_bus(_entry_path, 0.0)

func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer=12; add_child(layer)
	skip_button=Button.new(); skip_button.position=Vector2(20,158); skip_button.size=Vector2(240,40)
	skip_button.text="巴士驶入 · 跳过演出"; skip_button.pressed.connect(skip)
	layer.add_child(skip_button)
	_boarding_panel = PanelContainer.new()
	_boarding_panel.theme = world._hud.view.theme
	_boarding_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_boarding_panel)
	_boarding_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_boarding_panel.offset_left = -168
	_boarding_panel.offset_right = 168
	_boarding_panel.offset_top = -62
	_boarding_panel.offset_bottom = -16
	_boarding_label = Label.new()
	_boarding_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boarding_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boarding_label.add_theme_font_size_override("font_size", 16)
	_boarding_label.add_theme_color_override("font_color", C1ExpeditionHud.TONES["info"])
	_boarding_panel.add_child(_boarding_label)
	_boarding_panel.hide()

func running() -> bool:
	return stage in ["arriving","disembarking","embarking","departing"]

func advance(delta: float) -> void:
	if not running(): return
	if world.rescue_target!=null: world.rescue_target.refresh()
	if _open_body != null:
		if world.rescue_target != null and not world.rescue_target.npc.visible:
			world.rescue_target.label.hide()
		_advance_open_street(delta)
		return
	clock+=delta
	match stage:
		"arriving":
			IsoSpace.place(sprite, WorldLayout.point(route.entry).lerp(stop,smoothstep(0,1,minf(clock/DRIVE_IN,1))))
			if clock>=DRIVE_IN: stage="disembarking"; clock=0; skip_button.text="队员下车 · 跳过演出"
		"disembarking":
			for i: int in range(world.survivors.size()):
				var actor: FieldActor = world.survivors[i]
				actor.show(); actor.position=WorldLayout.point(route.passenger_door).lerp(starts[i],minf(clock/DISEMBARK,1))
				actor.visual.advance(delta,Vector2.DOWN*40,Vector2.RIGHT)
			if clock>=DISEMBARK: skip()
		"embarking":
			for i: int in range(world.survivors.size()):
				var actor: FieldActor = world.survivors[i]
				if actor.health>0: actor.position=boarding_starts[i].lerp(WorldLayout.point(route.passenger_door),minf(clock/EMBARK,1))
			if clock>=EMBARK:
				for actor: FieldActor in world.survivors:
					if actor.health>0: actor.hide()
				stage="departing"; clock=0; skip_button.text="巴士驶离 · 跳过演出"
				_show_boarding("巴士驶离")
		"departing":
			IsoSpace.place(sprite, stop.lerp(WorldLayout.point(route.exit),smoothstep(0,1,minf(clock/DRIVE_OUT,1))))
			if clock>=DRIVE_OUT: skip()

func skip() -> void:
	if stage in ["arriving","disembarking"]:
		if _open_body != null:
			_place_open_bus(_entry_path, _entry_path.length)
			_open_body.show_door(false)
		else:
			IsoSpace.place(sprite, stop)
		for i: int in range(world.survivors.size()):
			world.survivors[i].position=starts[i]; world.survivors[i].show()
		stage="exploring"
	elif stage in ["embarking","departing"]:
		if _open_body != null: return
		IsoSpace.place(sprite, WorldLayout.point(route.exit))
		for actor: FieldActor in world.survivors:
			if actor.health>0: actor.hide()
		stage="done"
		_boarding_panel.hide()
		departed.emit()
	if skip_button!=null: skip_button.hide()
	if world.rescue_target!=null: world.rescue_target.refresh()

func departure() -> void:
	if stage!="exploring" or world.phase!=Expedition.Phase.FINISHED: return
	if _open_body != null:
		_begin_open_boarding()
		return
	for actor: FieldActor in world.survivors: boarding_starts.append(actor.position)
	stage="embarking"; clock=0; skip_button.text="队员登车 · 跳过演出"; skip_button.show()
	_show_boarding("正在登车")


func _show_boarding(status: String) -> void:
	if final_boarding.y > 0:
		_boarding_label.text = "已集合 %d/%d · %s" % [final_boarding.x, final_boarding.y, status]
		_boarding_panel.show()


func _advance_open_street(delta: float) -> void:
	match stage:
		"arriving":
			clock += delta
			var duration: float = maxf(DRIVE_IN, _entry_path.length / OPEN_ARRIVAL_SPEED)
			_place_open_bus(_entry_path, _entry_path.length * smoothstep(0.0, 1.0, minf(clock / duration, 1.0)))
			if clock >= duration:
				stage = "disembarking"
				clock = 0.0
				_open_body.show_door(true)
				skip_button.text = "队员下车 · 跳过演出"
		"disembarking":
			clock += delta
			var door: Vector2 = WorldLayout.point(route.passenger_door)
			var gather: Vector2 = WorldLayout.point(route.door)
			for index: int in range(world.survivors.size()):
				var t: float = clampf((clock - index * ARRIVAL_STAGGER) / DISEMBARK, 0.0, 1.0)
				if t <= 0.0: continue
				var actor: FieldActor = world.survivors[index]
				var point: Vector2 = door.lerp(gather, t * 2.0) if t < 0.5 else gather.lerp(starts[index], t * 2.0 - 1.0)
				if not actor.visible:
					actor.position = door
					actor.show()
				_move_boarding_actor(actor, point, delta)
			if clock >= DISEMBARK + maxi(0, starts.size() - 1) * ARRIVAL_STAGGER:
				skip()
		"embarking":
			_advance_open_boarding(delta)
		"departing":
			_advance_open_departure(delta)


func _begin_open_boarding() -> void:
	var gather: Vector2 = WorldLayout.point(route.door)
	var door: Vector2 = WorldLayout.point(route.passenger_door)
	for actor: FieldActor in world.survivors:
		if actor.health > 0.0:
			_boarding_actors.append(actor)
	var rescue: RescueTarget = world.rescue_target
	if rescue != null and rescue.npc.health > 0.0 and rescue.delivered() and not _boarding_actors.has(rescue.npc):
		_boarding_actors.append(rescue.npc)
	for actor: FieldActor in _boarding_actors:
		var points: PackedVector2Array = PackedVector2Array([actor.position])
		if not world.navigation._segment_is_clear(actor.position, gather):
			points.append_array(world.navigation.path_between(actor.position, gather))
		points.append(gather)
		points.append(door)
		points.append(door.move_toward(stop, 14.0))
		_boarding_paths.append(JourneyPath.new(points))
	stage = "embarking"
	clock = 0.0
	skip_button.hide()
	_open_body.show_door(true)
	_follow_bus()
	_show_boarding("正在登车 0/%d" % _boarding_actors.size())


func _advance_open_boarding(delta: float) -> void:
	while _boarding_index < _boarding_actors.size():
		var actor: FieldActor = _boarding_actors[_boarding_index]
		var path: JourneyPath = _boarding_paths[_boarding_index]
		var duration: float = maxf(0.3, path.length / BOARDING_SPEED)
		var step: float = minf(delta, duration - clock)
		clock += step
		_move_boarding_actor(actor, path.point_at(path.length * clock / duration), step)
		if clock < duration: return
		actor.hide()
		if world.rescue_target != null and actor == world.rescue_target.npc:
			world.rescue_target.label.hide()
		_boarding_index += 1
		_show_boarding("正在登车 %d/%d" % [_boarding_index, _boarding_actors.size()])
		clock = 0.0
		delta -= step
	stage = "departing"
	_open_body.show_door(false)
	_show_boarding("巴士驶离")
	if delta > 0.0:
		_advance_open_departure(delta)


func _advance_open_departure(delta: float) -> void:
	clock += delta
	var duration: float = maxf(DRIVE_OUT, _exit_path.length / OPEN_DEPARTURE_SPEED)
	var t: float = minf(clock / duration, 1.0)
	# Integrate an acceleration ramp, followed by a steady speed through the boundary.
	const RAMP: float = 0.25
	var distance_fraction: float = t * t / (2.0 * RAMP) if t < RAMP else t - RAMP * 0.5
	_place_open_bus(_exit_path, _exit_path.length * distance_fraction / (1.0 - RAMP * 0.5))
	if t >= 1.0 and _entire_bus_outside():
		stage = "done"
		_boarding_panel.hide()
		departed.emit()


func _place_open_bus(path: JourneyPath, distance: float) -> void:
	IsoSpace.place(sprite, path.point_at(distance))
	var before: Vector2 = path.point_at(distance - 32.0)
	var after: Vector2 = path.point_at(distance + 32.0)
	if not before.is_equal_approx(after):
		sprite.rotation = (after - before).angle()
	_follow_bus()


func _follow_bus() -> void:
	world.camera.pan_by(sprite.position - world.camera.position)


func _entire_bus_outside() -> bool:
	var bounds: Rect2 = world.layout.world_bounds
	var foot: Vector2 = IsoSpace.map_of(sprite)
	var extent: Vector2 = BODY_HALF_SIZE
	return (foot.x + extent.x < bounds.position.x or foot.x - extent.x > bounds.end.x
		or foot.y + extent.y < bounds.position.y or foot.y - extent.y > bounds.end.y)


func _move_boarding_actor(actor: FieldActor, point: Vector2, delta: float) -> void:
	var movement: Vector2 = (point - actor.position) / maxf(delta, 0.0001)
	actor.position = point
	actor.visual.advance(delta, movement, movement)


func _route_points(rows: Array) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for row: Array in rows:
		points.append(WorldLayout.point(row))
	return points


class JourneyPath extends RefCounted:
	var points: PackedVector2Array = PackedVector2Array()
	var offsets: PackedFloat64Array = PackedFloat64Array()
	var length: float = 0.0

	func _init(waypoints: PackedVector2Array) -> void:
		for point: Vector2 in waypoints:
			if not points.is_empty():
				var leg: float = point.distance_to(points[-1])
				if leg <= 0.001: continue
				length += leg
			points.append(point)
			offsets.append(length)

	func point_at(distance: float) -> Vector2:
		if distance <= 0.0: return points[0]
		for index: int in range(1, offsets.size()):
			if distance <= offsets[index]:
				var t: float = (distance - offsets[index - 1]) / (offsets[index] - offsets[index - 1])
				return points[index - 1].lerp(points[index], t)
		return points[-1]


class OpenStreetBody extends Node2D:
	var door_open: bool = false

	func show_door(value: bool) -> void:
		door_open = value
		queue_redraw()

	func _draw() -> void:
		var shape: PackedVector2Array = PackedVector2Array([
			Vector2(-120,-27), Vector2(-110,-36), Vector2(94,-36), Vector2(120,-26),
			Vector2(120,26), Vector2(94,36), Vector2(-110,36), Vector2(-120,27),
		])
		draw_colored_polygon(shape, Color("d6be89"))
		shape.append(shape[0])
		draw_polyline(shape, Color("253b47"), 4.0, true)
		for x: float in [-81.0, 68.0]:
			for y: float in [-39.0, 33.0]:
				draw_rect(Rect2(x,y,30,6), Color("18242d"))
		draw_rect(Rect2(84,-28,16,56), Color("567986"))
		draw_rect(Rect2(-112,-23,13,46), Color("597782"))
		for x: float in [-84.0,-51.0,-18.0,15.0,48.0]:
			draw_rect(Rect2(x,-32,26,8), Color("658590"))
			draw_rect(Rect2(x,24,26,8), Color("658590"))
		draw_rect(Rect2(-69,-14,115,28), Color("ecdbaf"))
		draw_rect(Rect2(-46,-10,31,20), Color("857557"))
		draw_rect(Rect2(-9,-10,32,20), Color("77866a"))
		for y: float in [-23.0,15.0]:
			draw_rect(Rect2(109,y,8,8), Color("f9e3ae"))
			draw_rect(Rect2(-117,y,6,8), Color("c96754"))
		draw_rect(Rect2(59,27,26,10), Color("354b4d") if door_open else Color("b5a16e"))
