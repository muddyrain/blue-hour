class_name IsoBuildingArt
extends RefCounted
## Picks a closed-roof iso sprite for a world entity without changing layout data.

const HOUSES_WIDE: Array[String] = [
	"buildings/house_wide_a.png",
	"buildings/house_wide_b.png",
	"buildings/house_wide_c.png",
]
const HOUSES_TOWN: Array[String] = [
	"buildings/house_a.png",
	"buildings/house_b.png",
	"buildings/house_c.png",
	"buildings/house_d.png",
	"buildings/house_e.png",
	"buildings/house_f.png",
	"buildings/house_g.png",
]
const ROWS: Array[String] = ["buildings/row_a.png", "buildings/row_b.png"]
const APTS: Array[String] = ["buildings/apartment_a.png", "buildings/apartment_b.png"]
const CONV: Array[String] = [
	"buildings/convenience.png",
	"buildings/convenience_b.png",
	"buildings/convenience_wide.png",
]
const GROC: Array[String] = ["buildings/grocery.png", "buildings/grocery_b.png"]
const EAT: Array[String] = ["buildings/eatery.png", "buildings/eatery_b.png"]
const SUPER: Array[String] = ["buildings/supermarket.png", "buildings/supermarket_b.png"]
const WARE: Array[String] = [
	"buildings/warehouse.png",
	"buildings/warehouse_b.png",
	"buildings/warehouse_wide.png",
	"buildings/warehouse_wide_b.png",
]
const GARAGE: Array[String] = ["buildings/garage.png", "buildings/garage_b.png"]


static func pick(entity: Dictionary) -> String:
	var existing: String = String(entity.get("art", ""))
	if existing.begins_with("buildings/") or existing.begins_with("props/"):
		return existing
	var salt: int = String(entity.get("id", "")).hash() + int(entity.get("variant", 0)) * 17
	var chosen: String = _from_archetype(String(entity.get("archetype", "")), existing, salt)
	var rect: Variant = entity.get("rect", [])
	if rect is Array and rect.size() >= 4 and not chosen.is_empty():
		var pool: Array[String] = _pool_for(String(entity.get("archetype", "")), existing)
		if not pool.is_empty():
			chosen = _closest(pool, Vector2(float(rect[2]), float(rect[3])), salt)
	return chosen


static func _from_archetype(arch: String, art: String, salt: int) -> String:
	match arch:
		"convenience_store":
			return _at(CONV, salt)
		"supermarket":
			return _at(SUPER, salt)
		"eatery":
			return _at(EAT, salt)
		"warehouse":
			return _at(WARE, salt)
		"garage":
			return _at(GARAGE, salt)
		"detached_home":
			return _at(HOUSES_WIDE, salt)
		"row_house":
			return _at(ROWS, salt)
		"small_apartment":
			return _at(APTS, salt)
	if art == "street_shop" or art.ends_with("office") or art == WarehouseDistrict.OFFICE:
		return _at(CONV, salt)
	if art == "street_eatery":
		return _at(EAT, salt)
	if art == WarehouseDistrict.HALL or art == WarehouseDistrict.SHED or art.begins_with("warehouse"):
		return _at(WARE, salt)
	if not arch.is_empty() or not art.is_empty():
		return _at(HOUSES_WIDE if salt % 2 == 0 else HOUSES_TOWN, salt)
	return ""


static func _at(items: Array[String], salt: int) -> String:
	if items.is_empty():
		return ""
	return items[posmod(salt, items.size())]


static func _pool_for(arch: String, art: String) -> Array[String]:
	match arch:
		"convenience_store":
			return CONV
		"supermarket":
			return SUPER
		"eatery":
			return EAT
		"warehouse":
			return WARE
		"garage":
			return GARAGE
		"detached_home":
			return HOUSES_WIDE
		"row_house":
			return ROWS
		"small_apartment":
			return APTS
	if art == WarehouseDistrict.HALL or art == WarehouseDistrict.SHED or art.begins_with("warehouse"):
		return WARE
	if art == "street_shop" or art == WarehouseDistrict.OFFICE:
		return CONV
	if art == "street_eatery":
		return EAT
	return [] as Array[String]


static func _closest(items: Array[String], size: Vector2, salt: int) -> String:
	var want: float = size.x + size.y
	var scored: Array[Dictionary] = []
	for rel: String in items:
		var meta: Dictionary = IsoAtlas.info(rel)
		var map_size: Variant = meta.get("map", [])
		if not map_size is Array or map_size.size() < 2:
			continue
		var authored: Vector2 = Vector2(float(map_size[0]), float(map_size[1]))
		var score: float = absf((authored.x + authored.y) - want) + absf(authored.x - size.x) * 0.25
		# Prefer a slightly smaller sprite over one that would balloon past the lot.
		if authored.x + authored.y < want * 0.7:
			score += 80.0
		scored.append({"rel": rel, "score": score})
	if scored.is_empty():
		return _at(items, salt)
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) < float(b.score))
	var cutoff: float = float(scored[0].score) + 48.0
	var near: Array[String] = []
	for row: Dictionary in scored:
		if float(row.score) <= cutoff:
			near.append(String(row.rel))
	return _at(near, salt)


static func prop_for(kind: String, variant: int = 0) -> String:
	var key: String = kind.to_lower()
	if key == "lamp" or key.ends_with("lamp"):
		return "props/lamp.png"
	if "tree_b" in key or (("tree" in key) and posmod(variant, 2) == 1):
		return "props/tree_b.png"
	if "tree" in key:
		return "props/tree.png"
	if "planter" in key:
		return "props/planter.png"
	if "hedge" in key:
		return "props/hedge.png"
	if "bush" in key:
		return "props/bush.png"
	if key == "yard_wall" or key == "wall" or "yard_wall" in key:
		return "props/yard_wall.png"
	if "pole" in key:
		return "props/pole.png"
	if "crate" in key or key == "box":
		return "props/crate.png"
	if "vending" in key:
		return ["props/vending_red.png", "props/vending_blue.png", "props/vending_green.png"][posmod(variant, 3)]
	if key == "bike":
		return "props/bike.png"
	return ""
