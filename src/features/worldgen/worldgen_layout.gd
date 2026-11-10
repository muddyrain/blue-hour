class_name WorldgenLayout
extends RefCounted
## Roads/parcels are frozen before exploration places collision-bearing objects.
const PREFIX: String="worldgen_v1_"
const KEYS: Array[String]=["version","seed","size","topology","attempt","fallback","bounds","entities","roads","barriers","gates","bus","arrivals","enemy_points","rescue","id","objects","graph","parcels","art_revision"]

static func policy(level: bool = false, industrial: bool = false, residential_rescue: bool = false, open_streets: bool = false) -> Dictionary:
	var value: Dictionary = {"version":1,"revision":3,"policy_id":"BH_WORLDGEN_V1","status":"PROJECT_TEMP","layout_version":5,"attempts":3,"fallback":"same_size_theme_bounded_partition","base_walk_speed":125,"scale":WorldgenScale.WIDTH}

	if level:
		value.version=2
		value.revision = 3 if residential_rescue else 2 if industrial else 1
		value.policy_id="BH_LEVEL_V1"
	if open_streets:
		value.open_streets = OpenStreetsV1.VERSION
	return value

static func generate(seed: String, size: String, topology: String, task: String = "") -> Dictionary:
	if (not task.is_empty() and task not in TaskActions.TYPES) or seed.is_empty() or seed.length()>128 or size not in NeighborhoodLayout.SIZES or topology not in NeighborhoodLayout.TOPOLOGIES: return {}
	for attempt: int in range(3):
		var data: Dictionary=_assemble(seed,size,topology,attempt,false,task)
		if not data.is_empty(): return data
	return _assemble(seed,size,topology,0,true,task)

static func _assemble(seed: String,size: String,topology: String,attempt: int,fallback: bool,
		task: String = "", industrial: bool = false, residential_rescue: bool = false, open_streets: bool = false) -> Dictionary:
	var data: Dictionary = WorldgenGeometry.assemble(seed, size, topology, attempt, fallback, task, industrial, residential_rescue, open_streets)
	if not data.is_empty(): WorldgenDressing.freeze(data)
	return ExplorationLayout.complete(data) if not data.is_empty() else {}

static func validate(value: Variant,cached: bool=true) -> String:
	if not value is Dictionary or value.size()!=KEYS.size()+int(value.has("level_task"))+int(value.has("loading_yard"))+int(value.has("rescue_court"))+int(value.has("open_streets")) or not value.has_all(KEYS) or not SurvivalContracts.json_value(value): return "WORLDGEN_LAYOUT_FIELDS"
	if value.version!=5 or not value.seed is String or value.seed.is_empty() or value.seed.length()>128 or value["size"] not in NeighborhoodLayout.SIZES or value.topology not in NeighborhoodLayout.TOPOLOGIES or not SurvivalContracts.integer(value.attempt,0,2) or not value.fallback is bool or not is_map_id(value.id): return "WORLDGEN_LAYOUT_IDENTITY"
	if value.has("level_task") and value.level_task not in TaskActions.TYPES:
		return "LEVEL_TASK_IDENTITY"
	var open_streets: bool = value.has("open_streets")
	if open_streets and (value["size"] != "large" or not value.has("level_task") or value.open_streets != OpenStreetsV1.VERSION):
		return "OPEN_STREETS_LAYOUT_POLICY"
	var industrial: bool = value.has("loading_yard")
	var residential_rescue: bool = value.has("rescue_court")
	if industrial and (value.topology != "industrial" or value.get("level_task") != "airdrop" or not value.loading_yard is Dictionary):
		return "INDUSTRIAL_YARD_CONTEXT"
	if residential_rescue and (value.topology != "residential" or value.get("level_task") != "rescue" or not value.rescue_court is Dictionary):
		return "RESCUE_COURT_CONTEXT"
	var signature: String=RecordEncoding.fingerprint(value)
	if cached and ExplorationLayout._checked.has(signature): return ""
	var expected: Dictionary = _assemble(value.seed, value["size"], value.topology, int(value.attempt),
		value.fallback, value.get("level_task", ""), industrial, residential_rescue, open_streets)
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
