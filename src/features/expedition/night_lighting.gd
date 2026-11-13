class_name NightLighting
extends CanvasLayer
## Screen-edge vignette below squad readouts and HUD. The world owns the clock.

const Grade: Shader = preload("res://src/features/expedition/night_lighting.gdshader")

var amount: float = 0.0
var _surface: ColorRect
var _grade: ShaderMaterial


func _ready() -> void:
	layer = 2
	_grade = ShaderMaterial.new()
	_grade.shader = Grade
	_surface = ColorRect.new()
	_surface.name = "FieldGrade"
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.material = _grade
	_surface.show()
	add_child(_surface)
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(func() -> void: _surface.size = get_viewport().get_visible_rect().size)


func refresh(strength: float, _bus_foot_position: Vector2, _camera_zoom: float) -> void:
	var next: float = clampf(strength, 0.0, 1.0)
	if amount != next:
		amount = next
		_grade.set_shader_parameter("amount", amount)
		_surface.visible = true
	if not _surface.visible:
		return
