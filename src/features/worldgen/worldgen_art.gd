class_name WorldgenArt
extends RefCounted
## R1 assets apply only to the unpublished worldgen candidate, never layout4.
const HOME: Texture2D=preload("res://assets/worldgen/courtyard_home.png")
const HEDGE: Texture2D=preload("res://assets/worldgen/hedge.png")
const WALL: Texture2D=preload("res://assets/worldgen/courtyard_wall.png")
const CARGO: Texture2D=preload("res://assets/worldgen/loading_cargo.png")
const SCRAP: Texture2D=preload("res://assets/worldgen/scrap_car.png")
const STREET_SHOP: Texture2D = preload("res://assets/worldgen/r2/street_shop.png")
const STREET_EATERY: Texture2D = preload("res://assets/worldgen/r2/street_eatery.png")
const PAVING: Texture2D = preload("res://assets/worldgen/r2/paving_material.png")
const COURTYARD_EDGE: Texture2D = preload("res://assets/worldgen/r2/courtyard_edge.png")

static func definition(entity: Dictionary) -> Dictionary:
	var value: Dictionary=WorldgenScale.definition(entity.archetype)
	if entity.archetype=="detached_home" and entity.variant==3:
		value.texture=HOME;value.roof_split=476;value.title="内院住宅"
	var art: String = entity.get("art", "")
	if StreetModuleArt.DEFINITIONS.has(art):
		value.merge(StreetModuleArt.definition(art), true)
		value.foot = value.origin
		value.texture = STREET_SHOP if art == "street_shop" else STREET_EATERY
	return value

static func texture(kind: String) -> Texture2D:
	return {"hedge":HEDGE,"wall":WALL,"cargo":CARGO,"scrap":SCRAP,"courtyard_edge":COURTYARD_EDGE}[kind]
