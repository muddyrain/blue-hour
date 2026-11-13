class_name IsoActorView
extends Node2D
## Billboard holder for a FieldActor. The actor node itself stays at map coordinates.

var actor: FieldActor
var _name: Label


func _ready() -> void:
	z_as_relative = true
	if actor != null and not actor.is_enemy:
		_name = Label.new()
		_name.name = "CallSign"
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.position = Vector2(-48, -92)
		_name.size = Vector2(96, 18)
		_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name.add_theme_font_size_override("font_size", 12)
		_name.add_theme_color_override("font_color", Color("e8dcc4"))
		_name.add_theme_color_override("font_outline_color", Color("22201e"))
		_name.add_theme_constant_override("outline_size", 3)
		add_child(_name)


func _process(_delta: float) -> void:
	sync()


func sync() -> void:
	if actor == null or not is_instance_valid(actor):
		return
	position = IsoSpace.to_view(actor.position)
	visible = actor.visible
	if _name != null:
		_name.text = actor.call_sign
		_name.visible = not actor.call_sign.is_empty() and actor.activity != FieldActor.Activity.DOWN
	queue_redraw()


func _draw() -> void:
	if actor != null and is_instance_valid(actor):
		actor.draw_overlays(self)
