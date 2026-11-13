class_name WarehouseDressingArt
extends RefCounted
## One renderer-only pack selection. Both packs map stable IDs to normalized display regions.

const DEFAULT: String = "yard"
const PACKS: Dictionary = {
	"yard":"res://assets/worldgen/m45/r3/warehouse-yard.svg",
	"signal":"res://assets/worldgen/m45/r3/warehouse-signal.svg",
}
const REGIONS: Dictionary = {
	WarehouseSlots.NARROW: Rect2i(0,0,112,186),
	WarehouseSlots.END: Rect2i(112,0,112,176),
	WarehouseSlots.RACK: Rect2i(240,0,144,76),
	WarehouseSlots.CARGO: Rect2i(384,0,88,60),
	WarehouseSlots.REPAIR: Rect2i(472,0,64,56),
	WarehouseSlots.LAMP: Rect2i(536,0,24,56),
	WarehouseSlots.EDGE: Rect2i(560,0,36,52),
	WarehouseSlots.BAY: Rect2i(0,192,576,96),
	WarehouseSlots.DOCK: Rect2i(0,288,128,20),
	WarehouseSlots.PAVING: Rect2i(576,192,64,192),
	WarehouseSlots.MAT: Rect2i(128,288,256,96),
}
static var _scheme: String = ""
static var _atlases: Dictionary = {}
static var _textures: Dictionary = {}


static func scheme() -> String:
	if _scheme.is_empty():
		_scheme = DEFAULT
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--bh-warehouse-art="):
				var selected: String = arg.trim_prefix("--bh-warehouse-art=")
				if PACKS.has(selected):
					_scheme = selected
				else:
					push_warning("BH_WAREHOUSE_ART unknown pack '%s'; using %s" % [selected, DEFAULT])
				break
	return _scheme


static func texture(slot: String) -> Texture2D:
	if _textures.has(slot):
		return _textures[slot]
	var pack: String = scheme()
	var image: Image = _region(pack, slot)
	if image == null and pack != DEFAULT:
		push_warning("BH_WAREHOUSE_ART missing or incompatible %s in %s; using %s" % [slot, pack, DEFAULT])
		image = _region(DEFAULT, slot)
	if image == null:
		push_warning("BH_WAREHOUSE_ART default slot is missing: " + slot)
		if not REGIONS.has(slot):
			return null
		var size: Vector2i = REGIONS[slot].size
		image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color("6a7578"))
	_textures[slot] = ImageTexture.create_from_image(image)
	return _textures[slot]


static func _region(pack: String, slot: String) -> Image:
	if not REGIONS.has(slot):
		return null
	if not _atlases.has(pack):
		var path: String = PACKS[pack]
		var atlas: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path, "Texture2D") else null
		_atlases[pack] = atlas.get_image() if atlas != null else null
	var source: Image = _atlases[pack]
	var region: Rect2i = REGIONS[slot]
	if source == null or not Rect2i(Vector2i.ZERO, source.get_size()).encloses(region):
		return null
	var image: Image = source.get_region(region)
	# Annexe frame and facade split are fixed. An empty sprite is also incompatible.
	if image.is_invisible() or (WarehouseSlots.BUILDINGS.has(slot) and
			Vector2(image.get_size()) != WarehouseSlots.BUILDINGS[slot].size):
		return null
	return image
