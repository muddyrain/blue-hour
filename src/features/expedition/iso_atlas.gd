class_name IsoAtlas
extends RefCounted
## Shared first-pass 2:1 tiles and sprites. Feet come from tools/make_iso_art.py.

const ROOT: String = "res://assets/iso/"
const MANIFEST_PATH: String = "res://assets/iso/manifest.json"
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_manifest = parsed
	return _manifest


static func texture(rel: String) -> Texture2D:
	if not _textures.has(rel):
		var loaded: Resource = load(ROOT + rel)
		_textures[rel] = loaded if loaded is Texture2D else null
	return _textures[rel]


static func info(rel: String) -> Dictionary:
	return manifest().get("sprites", {}).get(rel, {})


static func art_scale() -> float:
	return float(manifest().get("scale", 0.5))


static func attach(host: Node2D, rel: String, extra_scale: float = 1.0) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "IsoSprite"
	sprite.texture = texture(rel)
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var factor: float = art_scale() * extra_scale
	sprite.scale = Vector2.ONE * factor
	var meta: Dictionary = info(rel)
	if sprite.texture != null and not meta.is_empty():
		var foot: Array = meta.get("foot", [sprite.texture.get_width() * 0.5, sprite.texture.get_height()])
		sprite.position = -Vector2(float(foot[0]), float(foot[1])) * factor
	elif sprite.texture != null:
		sprite.position = Vector2(-sprite.texture.get_width(), -sprite.texture.get_height()) * factor * 0.5
	host.add_child(sprite)
	host.set_meta("iso_art", rel)
	return sprite


static func flip_attached(host: Node2D, rel: String, extra_scale: float = 1.0) -> void:
	# Mirror around the authored south-center foot so a flipped door stays on the facade.
	var sprite: Sprite2D = host.get_node_or_null("IsoSprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return
	var factor: float = art_scale() * extra_scale
	var meta: Dictionary = info(rel)
	var tex_w: float = float(sprite.texture.get_width())
	var foot: Array = meta.get("foot", [tex_w * 0.5, sprite.texture.get_height()])
	sprite.flip_h = true
	sprite.position.x = -(tex_w - float(foot[0])) * factor
	var lights: Sprite2D = host.get_node_or_null("IsoLights") as Sprite2D
	if lights == null or lights.texture == null:
		return
	var light_rel: String = rel.replace(".png", "_lights.png")
	var lmeta: Dictionary = info(light_rel)
	var ltex_w: float = float(lights.texture.get_width())
	var lfoot: Array = lmeta.get("foot", [ltex_w * 0.5, lights.texture.get_height()])
	lights.flip_h = true
	lights.position.x = -(ltex_w - float(lfoot[0])) * factor


static func stamp_cell(canvas: CanvasItem, rel: String, cell: Vector2i, tile: float = 64.0) -> void:
	var tex: Texture2D = texture(rel)
	if tex == null:
		return
	var map: Rect2 = Rect2(Vector2(cell) * tile, Vector2(tile, tile))
	var poly: PackedVector2Array = IsoSpace.polygon(map)
	var left: float = INF
	var top: float = INF
	for point: Vector2 in poly:
		left = minf(left, point.x)
		top = minf(top, point.y)
	canvas.draw_texture_rect(tex, Rect2(left, top, tile * 2.0, tile), false)
