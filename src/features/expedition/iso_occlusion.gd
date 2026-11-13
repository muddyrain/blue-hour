class_name IsoOcclusion
extends RefCounted
## Fade an occluding building, tree or bus when a field actor is behind it.
## Presentation only: click and collision stay on the original closed solids.

const FADE_ALPHA: float = 0.48
const FADE_SPEED: float = 6.0
const MIN_OVERLAP: float = 70.0
const SKIP_KINDS: Array[String] = ["lamp", "bike", "crate", "bridge", "tram"]


static func update(expedition: Expedition, delta: float) -> void:
	if expedition == null or expedition._sort == null:
		return
	var actors: Array[Node2D] = []
	var occluders: Array[Node2D] = []
	for child: Node in expedition._sort.get_children():
		if child is IsoActorView and (child as IsoActorView).actor != null:
			actors.append(child)
		elif child is Node2D and _is_occluder(child):
			occluders.append(child)
	var blocked: Dictionary = {}
	for view: Node2D in actors:
		var actor_rect: Rect2 = _actor_rect(view)
		if not actor_rect.has_area():
			continue
		for occ: Node2D in occluders:
			# Y-sort uses view-space feet: a larger Y is drawn in front.
			if occ.position.y <= view.position.y + 1.0:
				continue
			var occ_rect: Rect2 = _art_rect(occ)
			if not occ_rect.has_area():
				continue
			var overlap: Rect2 = actor_rect.intersection(occ_rect)
			if overlap.has_area() and overlap.get_area() >= MIN_OVERLAP:
				blocked[occ.get_instance_id()] = true
	var step: float = maxf(delta, 0.0) * FADE_SPEED
	for occ: Node2D in occluders:
		var target: float = FADE_ALPHA if blocked.has(occ.get_instance_id()) else 1.0
		_fade_art(occ, target, step)


static func _is_occluder(node: Node) -> bool:
	if node is FieldProp:
		return not String((node as FieldProp).iso_art).is_empty()
	if node is Sprite2D and node.get_node_or_null("IsoBusView") != null:
		return true
	if node.has_meta("iso_kind"):
		return String(node.get_meta("iso_kind")) not in SKIP_KINDS
	return node.has_meta("iso_art")


static func _art_rect(host: Node2D) -> Rect2:
	var sprite: Sprite2D = host.find_child("IsoSprite", true, false) as Sprite2D
	if sprite == null or sprite.texture == null:
		return Rect2()
	var size: Vector2 = sprite.texture.get_size() * sprite.scale.abs()
	# The authored sprite AABB includes transparent corners; inset so a passerby
	# on the side of a house does not fade the whole facade.
	var rect: Rect2 = Rect2(sprite.global_position, size).grow_individual(-size.x * 0.12, -size.y * 0.06, -size.x * 0.12, -size.y * 0.10)
	return rect


static func _actor_rect(view: Node2D) -> Rect2:
	var iso: IsoActorView = view as IsoActorView
	if iso == null or iso.actor == null or iso.actor.visual == null:
		return Rect2()
	# Tight torso/head box. Billboard frames have large transparent padding.
	var height: float = 52.0 * ActorVisual.BODY_SCALE / ActorVisual.SCALE_REF
	var width: float = 18.0 * ActorVisual.BODY_SCALE / ActorVisual.SCALE_REF
	var origin: Vector2 = view.global_position
	if iso.actor.visual != null:
		origin += iso.actor.visual.position
	return Rect2(origin + Vector2(-width * 0.5, -height), Vector2(width, height * 0.88))


static func _fade_art(host: Node2D, target: float, step: float) -> void:
	var sprite: Sprite2D = host.find_child("IsoSprite", true, false) as Sprite2D
	if sprite == null:
		return
	var current: float = sprite.modulate.a
	if is_equal_approx(current, target) and step <= 0.0:
		return
	var next: float = target if step <= 0.0 else move_toward(current, target, step)
	sprite.modulate.a = next
