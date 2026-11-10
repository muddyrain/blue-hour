class_name WorldLayout
extends RefCounted
## V2 street modules. V1 geometry and its authentication remain in RogueLayout.
const BONES: Array[String] = ["avenue", "lanes", "court"]
const NAMES: Array[String] = ["青禾商业街", "柳巷街区", "北岸仓储街"]
const BOUNDS: Rect2 = Rect2(0, 0, 2560, 1920)
const TYPES: Array[String] = ["convenience_store", "supermarket", "eatery", "warehouse", "garage", "detached_home", "row_house", "small_apartment"]
static var _checked: ActionMemo = ActionMemo.new()

static func generate(seed: String, bone: String, forced_offset: int = -1) -> Dictionary:
	var variant: int = BONES.find(bone)
	assert(variant >= 0)
	var cols: Array = [[96, 704, 1376, 2016], [128, 752, 1392, 2016], [160, 768, 1408, 2016]][variant]
	var rows: Array = [[304, 800, 1536], [256, 784, 1504], [288, 768, 1536]][variant]
	var random: RandomNumberGenerator = RogueLayout.rng("world-v2:" + seed)
	var offset: int = random.randi_range(0, 3) if forced_offset<0 else forced_offset
	var entities: Array = []
	for row: int in range(3):
		for col: int in range(4):
			var index: int = row * 4 + col
			var archetype: String = TYPES[(index + offset) % 8]
			var width: int = 400 if archetype not in ["eatery", "garage", "detached_home"] else 336
			var x: int = cols[col]
			var y: int = rows[row]
			var depth: int = BuildingLibrary.DEPTH[archetype]
			var door_x: int = x+width/2+roundi((BuildingLibrary.DOOR_X[archetype]-256)*width/448.0)
			entities.append({"id":"building_%02d" % index, "archetype":archetype, "rect":[x,y+208-depth,width,depth], "door":[door_x,y+256]})
	var stop: Array = [[656,1256,240,80], [1392,1256,240,80], [1952,1256,240,80]][variant]
	var door: Array = [stop[0]+190,1400]
	var roads: Array = [[0,1120,2560,240],[0,640,2560,112],[560,0,112,1920],[1184,0,128,1920],[1840,0,112,1920]]
	var data: Dictionary = {"version":2,"bone":bone,"bounds":[0,0,2560,1920],"entities":entities,"roads":roads,
		"bus":{"rect":stop,"door":door,"passenger_door":[stop[0]+190,1320],"entry":[-160,1336],"exit":[2720,1336],"sweep":[0,1236,2560,120],"facing":"right"},
		"arrivals":[[door[0]-48,1448],[door[0],1448],[door[0]+48,1448],[door[0],1476]],
		"enemy_points":[[32,1088],[2528,1088],[1248,32],[1248,1888]],"rescue":entities[7].door.duplicate()}
	data.id = "rogue_v2_" + SurvivalContracts.fingerprint(data).substr(0,32)
	return data

static func is_map_id(value: Variant) -> bool:
	return value is String and value.length()==41 and value.begins_with("rogue_v2_") and value.substr(9).is_valid_hex_number(false)

static func validate(value: Variant) -> String:
	if not value is Dictionary or value.size()!=10 or not value.has_all(["version","bone","bounds","entities","roads","bus","arrivals","enemy_points","rescue","id"]): return "WORLD_LAYOUT_FIELDS"
	if value.version!=2 or value.bone not in BONES or not TransactionReceipt.same({"v":value.bounds},{"v":[0,0,2560,1920]}) or not is_map_id(value.id): return "WORLD_LAYOUT_VERSION"
	# Only finite canonical modules are accepted; reject arbitrary geometry before navigation.
	if not value.entities is Array or value.entities.size()!=12: return "WORLD_BUILDINGS"
	var bare: Dictionary = value.duplicate(true)
	bare.erase("id")
	if value.id!="rogue_v2_"+SurvivalContracts.fingerprint(bare).substr(0,32): return "WORLD_LAYOUT_ID"
	if not value.entities[0] is Dictionary or value.entities[0].get("archetype") not in TYPES: return "WORLD_ARCHETYPE"
	var offset: int = TYPES.find(value.entities[0].archetype)
	if offset>3 or not TransactionReceipt.same(value,generate("",value.bone,offset)): return "WORLD_NONCANONICAL"
	var signature: String = SurvivalContracts.fingerprint(value)
	if _checked.lookup(signature) == true: return ""
	if not value.bus is Dictionary or value.bus.size()!=7 or not value.bus.has_all(["rect","door","passenger_door","entry","exit","sweep","facing"]) or not _rect(value.bus.rect) or not _point(value.bus.door) or not _rect(value.bus.sweep): return "WORLD_BUS_FIELDS"
	if not value.roads is Array or not value.arrivals is Array or not value.enemy_points is Array or value.arrivals.size()!=4 or value.enemy_points.size()!=4: return "WORLD_ARRAYS"
	var blocks: Array[Rect2] = []
	var ids: Array[String] = []
	for entity: Variant in value.entities:
		if not entity is Dictionary or entity.size()!=4 or not entity.has_all(["id","archetype","rect","door"]) or not entity.id is String or entity.id in ids or entity.archetype not in TYPES or not _rect(entity.rect) or not _point(entity.door): return "WORLD_BUILDING_FIELDS"
		ids.append(entity.id)
		var body: Rect2 = rect(entity.rect)
		for other: Rect2 in blocks:
			if body.grow(24).intersects(other): return "WORLD_BUILDING_OVERLAP"
		if body.intersects(rect(value.bus.sweep)): return "WORLD_BUS_SWEEP"
		blocks.append(body)
	for road: Variant in value.roads:
		if not _rect(road): return "WORLD_ROAD"
	if not value.bus is Dictionary or value.bus.size()!=7 or value.bus.get("facing")!="right" or not _rect(value.bus.get("rect")) or not _point(value.bus.get("door")): return "WORLD_BUS_FIELDS"
	blocks.append(rect(value.bus.rect))
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure(blocks,BOUNDS)
	var start: Vector2 = point(value.bus.door)
	var targets: Array = value.arrivals + value.enemy_points + [value.rescue]
	for entity: Dictionary in value.entities: targets.append(entity.door)
	for target: Variant in targets:
		if not _point(target) or not nav.is_clear(point(target)): return "WORLD_BLOCKED_POINT_"+str(target)
		var path: PackedVector2Array = nav.path_between(start,point(target))
		if path.is_empty() or path[-1].distance_to(point(target))>16: return "WORLD_DISCONNECTED"
	for i: int in range(4):
		var goal: Vector2 = start+Vector2.ONE*((i-1.5)*16)
		if not nav.is_clear(goal): return "WORLD_GATHER_SPACE"
	_checked.store(signature, true)
	return ""

static func resource(data: Dictionary) -> StreetLayout:
	assert(validate(data).is_empty())
	var result: StreetLayout = StreetLayout.new()
	result.id = StringName(data.id)
	result.display_name = NAMES[BONES.find(data.bone)]
	result.world_bounds = BOUNDS
	result.world_data = data.duplicate(true)
	result.bus_block = rect(data.bus.rect)
	result.bus_door = point(data.bus.door)
	for entity: Dictionary in data.entities:
		result.residences.append(rect(entity.rect))
	# The legacy aliases are removed from blockers in the V2 branch.
	result.cash_block=rect(data.entities[0].rect); result.cash_door=point(data.entities[0].door)
	result.food_block=rect(data.entities[1].rect); result.food_door=point(data.entities[1].door)
	for road: Array in data.roads: result.roads.append(rect(road))
	for p: Array in data.arrivals: result.arrivals.append(point(p))
	for p: Array in data.enemy_points: result.enemy_points.append(point(p))
	result.rescue_point=point(data.rescue)
	result.camera_start=result.bus_door+Vector2(0,-220)
	result.route_hint="路侧巴士停在主路南沿；商业街、住宅侧巷与仓储区相连。选择建筑搜刮，可提前集合撤离。"
	return result

static func rect(v: Array) -> Rect2:
	return Rect2(v[0],v[1],v[2],v[3])
static func point(v: Array) -> Vector2:
	return Vector2(v[0],v[1])
static func _point(v: Variant) -> bool:
	return v is Array and v.size()==2 and SurvivalContracts.integer(v[0],0,2560) and SurvivalContracts.integer(v[1],0,1920)
static func _rect(v: Variant) -> bool:
	return v is Array and v.size()==4 and _point(v.slice(0,2)) and SurvivalContracts.integer(v[2],16,2560) and SurvivalContracts.integer(v[3],16,1920) and BOUNDS.encloses(rect(v))

static var _routes: ActionMemo = ActionMemo.new()
static func route_length(data: Dictionary) -> int:
	var cached: Variant = _routes.lookup(data.id)
	if cached != null:
		return int(cached)
	var layout: StreetLayout = resource(data)
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure(layout.blockers(),layout.world_bounds)
	var maximum: float = 0
	for entity: Dictionary in data.entities:
		var path: PackedVector2Array = nav.path_between(layout.bus_door,point(entity.door))
		var distance: float = 0
		for i: int in range(1,path.size()): distance+=path[i-1].distance_to(path[i])
		maximum=maxf(maximum,distance)
	_routes.store(data.id, ceili(maximum))
	return ceili(maximum)
