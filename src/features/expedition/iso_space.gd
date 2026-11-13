class_name IsoSpace
extends RefCounted
## 2:1 isometric presentation helpers. Gameplay stays in map (top-down) space.


static func to_view(map: Vector2) -> Vector2:
	return Vector2(map.x - map.y, (map.x + map.y) * 0.5)


static func to_map(view: Vector2) -> Vector2:
	return Vector2(view.y + view.x * 0.5, view.y - view.x * 0.5)


static func polygon(map_rect: Rect2) -> PackedVector2Array:
	var p: Vector2 = map_rect.position
	var e: Vector2 = map_rect.end
	return PackedVector2Array([
		to_view(p),
		to_view(Vector2(e.x, p.y)),
		to_view(e),
		to_view(Vector2(p.x, e.y)),
	])


static func view_bounds(map_bounds: Rect2) -> Rect2:
	return _aabb(polygon(map_bounds))


static func map_bounds_from_view(view_rect: Rect2) -> Rect2:
	var p: Vector2 = view_rect.position
	var e: Vector2 = view_rect.end
	return _aabb(PackedVector2Array([
		to_map(p),
		to_map(Vector2(e.x, p.y)),
		to_map(e),
		to_map(Vector2(p.x, e.y)),
	]))


static func foot(map_rect: Rect2) -> Vector2:
	return Vector2(map_rect.get_center().x, map_rect.end.y)


static func place(node: Node2D, map_point: Vector2) -> void:
	node.set_meta("iso_map", map_point)
	node.position = to_view(map_point)


static func map_of(node: Node2D) -> Vector2:
	var stored: Variant = node.get_meta("iso_map") if node.has_meta("iso_map") else null
	# Until IsoSpace.place() runs, the node still stores a logical map point in position.
	return stored if stored is Vector2 else node.position


static func attach_actor(actor: FieldActor, stage: Node2D) -> void:
	if actor.get_node_or_null("IsoView") != null:
		return
	var view: IsoActorView = IsoActorView.new()
	view.name = "IsoView"
	view.actor = actor
	stage.add_child(view)
	if actor.visual != null:
		actor.visual.reparent(view, false)
		actor.visual.position = Vector2.ZERO
	if actor._enemy_tag != null:
		actor._enemy_tag.reparent(view, false)
	actor.set_meta("iso_view", view)
	view.sync()


static func _aabb(points: PackedVector2Array) -> Rect2:
	var bounds: Rect2 = Rect2(points[0], Vector2.ZERO)
	for index: int in range(1, points.size()):
		bounds = bounds.expand(points[index])
	return bounds
