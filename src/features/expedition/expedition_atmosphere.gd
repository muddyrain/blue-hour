class_name ExpeditionAtmosphere
extends RefCounted
## World-canvas lighting only. Reads the expedition clock; owns no simulation.

const NIGHT_TINT: Color = Color(0.24, 0.28, 0.48)
const DUSK_WARM: Color = Color(1.0, 0.82, 0.68)
const BLUE_HOUR: Color = Color(0.46, 0.42, 0.62)

var _modulate: CanvasModulate
var _lights: Array[PointLight2D] = []
var _sources: Array[Vector2] = []
var _scenery_lights: Array[PointLight2D] = []


static func tint_for(amount: float) -> Color:
	var t: float = clampf(amount, 0.0, 1.0)
	if t <= 0.45:
		return Color.WHITE.lerp(DUSK_WARM, t / 0.45)
	if t <= 0.80:
		return DUSK_WARM.lerp(BLUE_HOUR, (t - 0.45) / 0.35)
	return BLUE_HOUR.lerp(NIGHT_TINT, (t - 0.80) / 0.20)


func refresh(world: Expedition, amount: float) -> void:
	if _modulate == null:
		_modulate = CanvasModulate.new()
		_modulate.name = "WorldDayNight"
		world.add_child(_modulate)
		var gradient: Gradient = Gradient.new()
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0.65), Color(1, 1, 1, 0)])
		var texture: GradientTexture2D = GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 256
		texture.height = 256
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 1.0)
		# Reuse twelve pools near the visible street; the map can be much larger
		# than the viewport. Two additional lights follow the bus headlights.
		for prop: Node in world._sort.get_children():
			if (prop is WorldFurniture and prop.kind == "lamp") or (prop is WorldgenFurniture and (prop.detail.get("kind", "") == "lamp" or prop.detail.get("slot", "") == WarehouseSlots.LAMP)):
				_sources.append((prop as Node2D).position + Vector2(0, -35))
		for prop: FieldProp in world._buildings:
			_sources.append(prop.position + Vector2(0, -45))
		for index: int in range(mini(12, _sources.size())):
			_add_light(world, _sources[index], texture, 1.25)
			_scenery_lights.append(_lights.back())
		for offset: Vector2 in [Vector2(-95, -65), Vector2(-95, -25)]:
			_add_light(world._bus_sprite, offset, texture, 1.7)
	var center: Vector2 = world.camera.position
	_sources.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(center) < b.distance_squared_to(center))
	for index: int in range(_scenery_lights.size()):
		_scenery_lights[index].position = _sources[index]
	_modulate.color = tint_for(amount)
	for light: PointLight2D in _lights:
		light.energy = 1.25 * smoothstep(0.35, 1.0, amount)
		light.visible = amount > 0.01

func _add_light(parent: Node2D, offset: Vector2, texture: Texture2D, spread: float) -> void:
	var light: PointLight2D = PointLight2D.new()
	light.name = "WarmFieldLight"
	light.position = offset
	light.texture = texture
	light.texture_scale = spread
	light.color = Color("ffa64a")
	light.energy = 0.0
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.shadow_enabled = false
	parent.add_child(light)
	_lights.append(light)
