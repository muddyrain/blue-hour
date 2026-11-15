class_name ScreamerVisualV1
extends RefCounted
## Registered sprite poses and event-driven warning. Gameplay owns the clock and release.

const SHEET: Texture2D = preload("res://assets/infected_v1/screamer/actions.png")
const KIND: String = ScreamerPolicyV1.KIND
const CELL: Vector2 = SpecialInfectedSheetV1.CELL
const ROOT: Vector2 = SpecialInfectedSheetV1.ROOT
const DISPLAY_SCALE: float = 0.35
const AMBER: Color = Color("ffd18b")
const INK: Color = Color("22201e")


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName, walk_clock: float,
		attack_clock: float, defeat_clock: float, progress: float) -> void:
	SpecialInfectedSheetV1.pose(sprite, SHEET, direction,
		SpecialInfectedSheetV1.frame_for(state, walk_clock, attack_clock, defeat_clock, progress))


static func draw_cue(canvas: CanvasItem, phase: StringName, progress: float) -> void:
	# Sound rings communicate a call for reinforcements, not a damage radius.
	if phase == &"windup":
		_waves(canvas, 18.0 + 5.0 * progress, 0.65 + 0.35 * progress)
		canvas.draw_style_box(_panel(), Rect2(-43, -80, 86, 23))
		canvas.draw_string(ThemeDB.fallback_font, Vector2(-43, -64), "尖啸蓄势",
			HORIZONTAL_ALIGNMENT_CENTER, 86, 12, InfectedDangerGeometry.CREAM)
		canvas.draw_rect(Rect2(-37, -61, 74 * progress, 2), AMBER)
	elif phase == &"released" and progress < 1.0:
		_waves(canvas, lerpf(23.0, 46.0, progress), 1.0 - progress)


static func _panel() -> StyleBoxFlat:
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Color("22201e")
	panel.border_color = Color("e8dcc4")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(3)
	return panel


static func _waves(canvas: CanvasItem, radius: float, opacity: float) -> void:
	for direction: float in [0.0, PI]:
		for spacing: float in [0.0, 7.0]:
			var points: PackedVector2Array = PackedVector2Array()
			for index: int in range(13):
				var angle: float = direction - 0.68 + 1.36 * float(index) / 12.0
				points.append(Vector2(cos(angle), sin(angle) * 0.5) * (radius + spacing))
			canvas.draw_polyline(points, Color(INK, opacity), 5.0, true)
			canvas.draw_polyline(points, Color(AMBER, opacity), 2.8, true)
