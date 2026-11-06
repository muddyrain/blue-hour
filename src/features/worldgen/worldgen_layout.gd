class_name WorldgenLayout
extends RefCounted
## Roads/parcels are frozen before exploration places collision-bearing objects.
const PREFIX: String="worldgen_v1_"
const KEYS: Array[String]=["version","seed","size","topology","attempt","fallback","bounds","entities","roads","barriers","gates","bus","arrivals","enemy_points","rescue","id","objects","graph","parcels","art_revision"]

static func policy() -> Dictionary:
	return {"version":1,"revision":3,"policy_id":"BH_WORLDGEN_V1","status":"PROJECT_TEMP","layout_version":5,"attempts":3,"fallback":"same_size_theme_bounded_partition","base_walk_speed":125,"scale":WorldgenScale.WIDTH}

static func generate(seed: String, size: String, topology: String) -> Dictionary:
	if seed.is_empty() or seed.length()>128 or size not in NeighborhoodLayout.SIZES or topology not in NeighborhoodLayout.TOPOLOGIES: return {}
	for attempt: int in range(3):
		var data: Dictionary=_assemble(seed,size,topology,attempt,false)
		if not data.is_empty(): return data
	return _assemble(seed,size,topology,0,true)

static func _assemble(seed: String,size: String,topology: String,attempt: int,fallback: bool) -> Dictionary:
	var data: Dictionary=WorldgenGeometry.assemble(seed,size,topology,attempt,fallback)
	if not data.is_empty(): WorldgenDressing.freeze(data)
	return ExplorationLayout.complete(data) if not data.is_empty() else {}

static func validate(value: Variant,cached: bool=true) -> String:
	if not value is Dictionary or value.size()!=KEYS.size() or not value.has_all(KEYS) or not SurvivalContracts.json_value(value): return "WORLDGEN_LAYOUT_FIELDS"
	if value.version!=5 or not value.seed is String or value.seed.is_empty() or value.seed.length()>128 or value["size"] not in NeighborhoodLayout.SIZES or value.topology not in NeighborhoodLayout.TOPOLOGIES or not SurvivalContracts.integer(value.attempt,0,2) or not value.fallback is bool or not is_map_id(value.id): return "WORLDGEN_LAYOUT_IDENTITY"
	var signature: String=RecordEncoding.fingerprint(value)
	if cached and ExplorationLayout._checked.has(signature): return ""
	var expected: Dictionary=_assemble(value.seed,value["size"],value.topology,int(value.attempt),value.fallback)
	return "" if not expected.is_empty() and RecordEncoding.fingerprint(expected)==signature else "WORLDGEN_LAYOUT_CANONICAL"

static func is_map_id(value: Variant) -> bool:
	return value is String and value.begins_with(PREFIX) and value.length()==PREFIX.length()+32 and value.substr(PREFIX.length()).is_valid_hex_number(false)

static func _routing(data: Dictionary) -> Dictionary:
	return ExplorationLayout._routing(data)

static func resource(data: Dictionary) -> StreetLayout:
	return NeighborhoodLayout.resource(data) if validate(data).is_empty() else null

static func content_reachable(data: Dictionary, routes: Dictionary) -> bool:
	# Every task family needs an actual non-near primary frontage after props.
	for category: Array in [TaskActions.FOOD_TYPES,TaskActions.GEAR_TYPES]:
		var count: int=0
		var away: bool=false
		for entity: Dictionary in data.entities:
			if entity.archetype in category:
				count+=1
				away=away or float(routes.doors[entity.id].length)>float(routes.dmax)*0.35
		if count<2 or not away: return false
	return true
