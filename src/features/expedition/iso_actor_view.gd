class_name IsoActorView
extends Node2D
## Billboard holder for a FieldActor. The actor node itself stays at map coordinates.

var actor: FieldActor
var _name: Label
var _markers: Node2D


func _ready() -> void:
	z_as_relative = true
	_ensure_markers()
	if actor != null and not actor.is_enemy:
		_name = Label.new()
		_name.name = "CallSign"
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.position = Vector2(-40, -60)
		_name.size = Vector2(80, 16)
		_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name.add_theme_font_size_override("font_size", 10)
		_name.add_theme_color_override("font_color", Color("e8dcc4"))
		_name.add_theme_color_override("font_outline_color", Color("22201e"))
		_name.add_theme_constant_override("outline_size", 3)
		_markers.add_child(_name)


func _process(_delta: float) -> void:
	sync()


func sync() -> void:
	if actor == null or not is_instance_valid(actor):
		return
	position = IsoSpace.to_view(actor.position)
	visible = actor.visible
	_ensure_markers()
	_markers.position = position
	_markers.visible = visible
	if actor._enemy_tag != null and is_instance_valid(actor._enemy_tag) and actor._enemy_tag.get_parent() != _markers:
		actor._enemy_tag.reparent(_markers, false)
	if _name != null:
		_name.text = actor.call_sign
		_name.visible = not actor.call_sign.is_empty() and actor.activity != FieldActor.Activity.DOWN
	_markers.queue_redraw()


func _ensure_markers() -> void:
	if _markers != null and is_instance_valid(_markers):
		return
	_markers = IsoActorMarkers.new()
	_markers.name = "IsoMarkers"
	_markers.view = self
	var overlay: Node = _overlay()
	overlay.add_child(_markers)


func _overlay() -> Node:
	var stage: Node = get_parent()
	if stage != null:
		var world: Node = stage.get_parent()
		if world != null and world.has_meta("iso_markers"):
			var root: Node = world.get_meta("iso_markers")
			if root != null and is_instance_valid(root):
				return root
	return self


func _exit_tree() -> void:
	if _markers != null and is_instance_valid(_markers) and _markers.get_parent() != self:
		_markers.queue_free()
	_markers = null


func _draw() -> void:
	# Overlays are drawn on the raised marker layer so names and HP stay readable.
	pass


class IsoActorMarkers:
	extends Node2D
	var view: IsoActorView

	func _draw() -> void:
		if view != null and is_instance_valid(view) and view.actor != null and is_instance_valid(view.actor):
			view.actor.draw_overlays(self)
