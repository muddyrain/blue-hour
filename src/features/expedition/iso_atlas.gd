class_name IsoAtlas
extends RefCounted
## Shared first-pass 2:1 tiles and sprites. Feet come from tools/make_iso_art.py.

const ROOT: String = "res://assets/iso/"
const MANIFEST_PATH: String = "res://assets/iso/manifest.json"
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _ground_textures: Dictionary[String, Texture2D] = {}


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
	var tex: Texture2D = ground_texture(rel)
	if tex == null:
		return
	var map: Rect2 = Rect2(Vector2(cell) * tile, Vector2(tile, tile))
	var poly: PackedVector2Array = IsoSpace.polygon(map)
	# Adjacent cells must share an opaque edge, rather than alpha-blend their
	# overlapping bounding boxes. Stay two source pixels inside the authored
	# diamond to exclude its smoothed transparent rim; interior detail stays intact.
	var inset: Vector2 = Vector2(2.0 / tex.get_width(), 2.0 / tex.get_height())
	var uv: PackedVector2Array = PackedVector2Array([
		Vector2(0.5, inset.y), Vector2(1.0 - inset.x, 0.5),
		Vector2(0.5, 1.0 - inset.y), Vector2(inset.x, 0.5),
	])
	canvas.draw_polygon(poly, PackedColorArray([Color.WHITE]), uv, tex)


static func ground_texture(rel: String) -> Texture2D:
	if not _ground_textures.has(rel):
		var source: Texture2D = texture(rel)
		if source == null:
			return null
		var image: Image = source.get_image()
		if image.is_compressed():
			image.decompress()
		# The polygon owns coverage. Tile alpha (including authored slab/ripple
		# strokes) must never expose the canvas or a neighboring cell underneath.
		image.convert(Image.FORMAT_RGB8)
		_ground_textures[rel] = ImageTexture.create_from_image(image)
	return _ground_textures[rel]
