class_name NightLighting
extends CanvasLayer
## Grades the field canvas before squad readouts and HUD. The world owns the clock.

const Grade: Shader = preload("res://src/features/expedition/night_lighting.gdshader")

var amount: float = 0.0
var _surface: ColorRect
var _grade: ShaderMaterial
var _bus_foot: Vector2 = Vector2.INF
var _zoom: float = 0.0
var _viewport_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = 2
	_grade = ShaderMaterial.new()
	_grade.shader = Grade
	_surface = ColorRect.new()
	_surface.name = "FieldGrade"
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.material = _grade
	_surface.hide()
	add_child(_surface)
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func refresh(strength: float, bus_foot: Vector2, zoom: float) -> void:
	var next: float = clampf(strength, 0.0, 1.0)
	if amount != next:
		amount = next
		_grade.set_shader_parameter("amount", amount)
		_surface.visible = amount > 0.0
	if not _surface.visible:
		return

	# Local UVs use the logical viewport, independently of the back buffer's render size.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if _viewport_size != viewport_size:
		_viewport_size = viewport_size
		_grade.set_shader_parameter("viewport_size", _viewport_size)
	if _bus_foot != bus_foot:
		_bus_foot = bus_foot
		_grade.set_shader_parameter("bus_foot", _bus_foot)
	if not is_equal_approx(_zoom, zoom):
		_zoom = zoom
		_grade.set_shader_parameter("camera_zoom", _zoom)
