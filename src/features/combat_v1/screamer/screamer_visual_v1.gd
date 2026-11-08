class_name ScreamerVisualV1
extends RefCounted
## Registered sprite poses and event-driven warning. Gameplay owns the clock and release.

const SHEET: Texture2D = preload("res://assets/infected_v1/screamer/screamer.png")
const KIND: String = "screamer_zombie_v1"
const CELL: Vector2 = Vector2(160, 160)
const ROOT: Vector2 = Vector2(80, 144)
const DISPLAY_SCALE: float = 0.58
const AMBER: Color = Color("ffd18b")
const INK: Color = Color("101923")


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName, walk_clock: float,
		attack_clock: float, defeat_clock: float, progress: float) -> void:
	var octant: int = MotionAtlas.octant(direction)
	var row: int = 1 if state == &"windup" else 2 if state == &"release" else 0
	sprite.texture = SHEET
	sprite.hframes = 5
	sprite.vframes = 3
	sprite.flip_h = octant in [3, 4, 5]
	sprite.offset = CELL * 0.5 - ROOT
	sprite.frame = row * 5 + NormalInfectedV1.SOURCE_FOR_OCTANT[octant]
	sprite.rotation = 0.0
	match state:
		&"move":
			var swing: float = sin(walk_clock * 12.0)
			sprite.rotation = swing * 0.048
			sprite.position.y -= absf(swing) * 2.0
		&"attack":
			sprite.rotation = attack_clock * direction.x * 0.30
		&"windup":
			sprite.rotation = -direction.x * progress * 0.07
		&"defeated":
			var fall_side: float = -1.0 if direction.x < -0.1 else 1.0
			sprite.rotation = fall_side * lerpf(0.0, 1.35, clampf(defeat_clock / 0.23, 0.0, 1.0))


static func draw_cue(canvas: CanvasItem, phase: StringName, progress: float) -> void:
	if phase == &"windup":
		_waves(canvas, 22.0 + 5.0 * progress, 0.60 + 0.40 * progress)
		canvas.draw_rect(Rect2(-48, -126, 96, 28), INK)
		canvas.draw_rect(Rect2(-48, -126, 96, 28), AMBER, false, 1.0)
		canvas.draw_string(ThemeDB.fallback_font, Vector2(-48, -108), "尖啸蓄势",
			HORIZONTAL_ALIGNMENT_CENTER, 96, 15, AMBER)
		canvas.draw_rect(Rect2(-41, -104, 82, 3), Color("574632"))
		canvas.draw_rect(Rect2(-41, -104, 82.0 * progress, 3), AMBER)
	elif phase == &"released" and progress < 1.0:
		_waves(canvas, lerpf(24.0, 46.0, progress), 1.0 - progress)


static func _waves(canvas: CanvasItem, radius: float, opacity: float) -> void:
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	for direction: float in [0.0, PI]:
		for spacing: float in [0.0, 7.0]:
			canvas.draw_arc(Vector2.ZERO, radius + spacing, direction - 0.68, direction + 0.68,
				12, Color(INK, opacity), 5.0, true)
			canvas.draw_arc(Vector2.ZERO, radius + spacing, direction - 0.68, direction + 0.68,
				12, Color(AMBER, opacity), 2.8, true)
	canvas.draw_set_transform(Vector2.ZERO)
