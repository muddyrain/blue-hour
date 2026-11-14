class_name MotionAtlas
extends RefCounted
## Original PROJECT_TEMP poses. Survivors have drawn left views; symmetric enemies mirror.

const RIGHT: Array[Texture2D] = [
	preload("res://assets/iso/chars/gu_full.png"),
	preload("res://assets/iso/chars/xia_full.png"),
	preload("res://assets/iso/chars/lin_full.png"),
	preload("res://assets/iso/chars/shen_full.png"),
	preload("res://assets/iso/chars/lu_full.png"),
]
const LEFT: Array[Texture2D] = [
	preload("res://assets/iso/chars/gu_left_full.png"),
	preload("res://assets/iso/chars/xia_left_full.png"),
	preload("res://assets/iso/chars/lin_left_full.png"),
	preload("res://assets/iso/chars/shen_left_full.png"),
	preload("res://assets/iso/chars/lu_left_full.png"),
]
const ENEMIES: Dictionary = {
	EnemyRules.NORMAL: preload("res://assets/iso/chars/normal_full.png"),
	EnemyRules.RUSH: preload("res://assets/iso/chars/rush_full.png"),
	EnemyRules.HEAVY: preload("res://assets/iso/chars/heavy_full.png"),
}
const PART_SHADER: Shader = preload("res://src/features/presentation/motion_part.gdshader")
const COLUMNS: Array[int] = [0, 1, 2, 1, 0, 3, 4, 3]
const LEFT_COLUMNS: Dictionary = {3: 1, 4: 0, 5: 2}
const WAISTS: Array[float] = [192.0, 192.0, 192.0, 192.0, 192.0]
const CROWN: float = 0.50


static func octant(direction: Vector2) -> int:
	return posmod(roundi(direction.angle() / (PI / 4.0)), 8)


static func pose(sprite: Sprite2D, enemy: bool, kind: String, variant: int,
		direction: Vector2, action: int) -> void:
	var oct: int = octant(direction)
	var left: bool = not enemy and LEFT_COLUMNS.has(oct)
	sprite.texture = ENEMIES.get(kind, ENEMIES[EnemyRules.NORMAL]) if enemy else LEFT[variant] if left else RIGHT[variant]
	sprite.hframes = 3 if left else 5
	sprite.vframes = 8 if enemy else 7
	sprite.offset = Vector2(0, -128 if enemy else -96)
	sprite.flip_h = enemy and oct in [3, 4, 5]
	sprite.frame = action * sprite.hframes + (int(LEFT_COLUMNS[oct]) if left else COLUMNS[oct])
	if sprite.material is ShaderMaterial:
		var material: ShaderMaterial = sprite.material as ShaderMaterial
		material.set_shader_parameter("grid", Vector2(sprite.hframes, sprite.vframes))
		material.set_shader_parameter("waist", WAISTS[variant] / 256.0)
		material.set_shader_parameter("crown", CROWN)


static func material(part: int) -> ShaderMaterial:
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = PART_SHADER
	result.set_shader_parameter("part", part)
	return result
