class_name WorldgenLayout
extends RefCounted
## Roads/parcels are frozen before exploration places collision-bearing objects.
const PREFIX: String="worldgen_v1_"
const KEYS: Array[String]=["version","seed","size","topology","attempt","fallback","bounds","entities","roads","barriers","gates","bus","arrivals","enemy_points","rescue","id","objects","graph","parcels","art_revision"]

static func policy(_level: bool = false, industrial: bool = false, residential_rescue: bool = false, open_streets: int = 0) -> Dictionary:
	var value: Dictionary = {"version":2,"revision":3 if residential_rescue else 2 if industrial else 1,"policy_id":"BH_LEVEL_V1","status":"PROJECT_TEMP","layout_version":5,"attempts":3,"fallback":"same_size_theme_bounded_partition","base_walk_speed":125,"scale":WorldgenScale.WIDTH}

	if open_streets > 0:
		value.open_streets = open_streets
	return value

static func _assemble(seed: String,size: String,topology: String,attempt: int,fallback: bool,
		task: String = "", industrial: bool = false, residential_rescue: bool = false, open_streets: int = 0, trace: Array[String] = []) -> Dictionary:
	var compact_fit: bool = size != "large" and open_streets == OpenStreetsV1.SEEDED_VERSION
	var data: Dictionary = WorldgenGeometry.assemble(seed, size, topology, attempt, fallback, task,
		industrial, residential_rescue, 0 if compact_fit else open_streets)
	if data.is_empty():
		trace.append("parcel_geometry")
		return {}
	var dressed: bool = open_streets == OpenStreetsV1.DRESSING_VERSION
	if dressed and not WarehouseScenery.attach(data):
		return {}
	WorldgenDressing.freeze(data)
	if dressed and not WarehouseScenery.dress(data):
		return {}
	if compact_fit:
		data.scenery_revision = open_streets
	if open_streets == OpenStreetsV1.SEEDED_VERSION:
		ParcelScenery.fit(data)
	return ExplorationLayout.complete(data, trace)

static func validate(value: Variant,cached: bool=true) -> String:
	if not value is Dictionary or value.size()!=KEYS.size()+int(value.has("level_task"))+int(value.has("loading_yard"))+int(value.has("rescue_court"))+int(value.has("open_streets"))+int(value.has("warehouse_district"))+int(value.has("themed_district"))+int(value.has("scenery_revision")) or not value.has_all(KEYS) or not SurvivalContracts.json_value(value): return "WORLDGEN_LAYOUT_FIELDS"
	if value.version!=5 or not value.seed is String or value.seed.is_empty() or value.seed.length()>128 or value["size"] not in NeighborhoodLayout.SIZES or value.topology not in NeighborhoodLayout.TOPOLOGIES or not SurvivalContracts.integer(value.attempt,0,2) or not value.fallback is bool or not is_map_id(value.id): return "WORLDGEN_LAYOUT_IDENTITY"
	if value.has("level_task") and value.level_task not in TaskActions.TYPES:
		return "LEVEL_TASK_IDENTITY"
	if value.has("open_streets") and (value["size"] != "large" or not value.has("level_task") \
			or not OpenStreetsV1.supported(value.open_streets)):
		return "OPEN_STREETS_LAYOUT_POLICY"
	if value.has("scenery_revision") and (value.has("open_streets") or value["size"] == "large" or not value.has("level_task") \
			or not SurvivalContracts.integer(value.scenery_revision, OpenStreetsV1.SEEDED_VERSION, OpenStreetsV1.SEEDED_VERSION)):
		return "SCENERY_LAYOUT_POLICY"
	var open_streets: int = int(value.get("open_streets", value.get("scenery_revision", 0)))
	var industrial: bool = value.has("loading_yard")
	var residential_rescue: bool = value.has("rescue_court")
	var warehouse: bool = value.has("open_streets") and OpenStreetsV1.warehouse(open_streets, value.topology, industrial)
	var themed: bool = value.has("open_streets") and open_streets == OpenStreetsV1.SEEDED_VERSION and ThemedDistrict.FAMILIES.has(value.topology)
	if themed != value.has("themed_district"):
		return "THEMED_DISTRICT_CONTEXT"
	if warehouse != value.has("warehouse_district") \
			or (open_streets in [OpenStreetsV1.DISTRICT_VERSION, OpenStreetsV1.DRESSING_VERSION] and not warehouse) \
			or (open_streets == OpenStreetsV1.SEEDED_VERSION and (industrial or residential_rescue)):
		return "WAREHOUSE_DISTRICT_CONTEXT"
	if industrial and (value.topology != "industrial" or value.get("level_task") != "airdrop" or not value.loading_yard is Dictionary):
		return "INDUSTRIAL_YARD_CONTEXT"
	if residential_rescue and (value.topology != "residential" or value.get("level_task") != "rescue" or not value.rescue_court is Dictionary):
		return "RESCUE_COURT_CONTEXT"
	var signature: String=RecordEncoding.fingerprint(value)
	if cached and ExplorationLayout.has_certificate(signature): return ""
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
			if entity.archetype in category and not entity.get("service_only", false):
				count+=1
				away=away or float(routes.doors[entity.id].length)>float(routes.dmax)*0.35
		if count<2 or not away: return false
	return true
