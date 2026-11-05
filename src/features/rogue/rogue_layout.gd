class_name RogueLayout
extends RefCounted
## Versioned finite module assembly. Integer data only; never loads supplied paths.
const VERSION: int = 1
const MAX_ATTEMPTS: int = 3
const BONES: Array[String] = ["straight","fork","ring"]
const NAMES: Array[String] = ["长街","三岔街","环院街"]
static var _valid: Dictionary = {}

static func rng(identity: String) -> RandomNumberGenerator:
	var result: RandomNumberGenerator = RandomNumberGenerator.new()
	result.seed = identity.sha256_text().substr(0,15).hex_to_int()
	return result

static func generate(seed: String, bone: String, force_fallback: bool = false) -> Dictionary:
	var reasons: Array[String] = []
	for attempt: int in range(MAX_ATTEMPTS):
		var data: Dictionary = _assemble(seed,bone,attempt,false)
		var issue: String = validate(data)
		if issue.is_empty() and not force_fallback: return data
		reasons.append("PROBE_REJECT" if force_fallback else issue)
	# A separately verified, fixed module arrangement. Its identity is stored, never rerolled on load.
	var fallback: Dictionary = _assemble("verified-fallback-v1",bone,0,true)
	fallback.fallback_reason = ";".join(reasons)
	assert(validate(fallback).is_empty(),"built-in fallback must remain navigable")
	return fallback

static func _assemble(seed: String, bone: String, attempt: int, fallback: bool) -> Dictionary:
	var random: RandomNumberGenerator = rng("street-v1:"+seed+":"+str(attempt))
	var slots: Array = []
	var roads: Array = []
	var anchors: Array = []
	match bone:
		"straight":
			slots = [[320,96],[1280,96],[320,512],[1280,512],[320,928],[1280,928]]
			roads = [[848,0,224,1440],[480,320,960,112],[480,736,960,112],[480,1152,960,112]]
		"fork":
			slots = [[112,160],[736,160],[1440,160],[112,944],[1120,944],[1552,944]]
			roads = [[80,672,1760,176],[864,672,192,768],[544,0,176,848],[1200,0,176,848]]
		"ring":
			slots = [[96,64],[768,64],[1456,64],[96,1024],[768,1024],[1456,1024]]
			roads = [[400,320,1152,144],[400,832,1152,144],[400,320,144,656],[1408,320,144,656]]
			anchors = [[720,464,448,264]]
	var order: Array[int] = [0,1,2,3,4,5]
	if not fallback:
		for i: int in range(order.size()-1,0,-1):
			var chosen: int = random.randi_range(0,i)
			var old: int = order[i];order[i] = order[chosen];order[chosen] = old
	var entities: Array = []
	var special: Dictionary = {}
	for i: int in range(6):
		var point: Array = slots[order[i]]
		var kind: String = ["bus","cash","food","residence","residence","residence"][i]
		var width: int = 320 if i<3 or fallback else random.randi_range(0,1)*32+288
		var rect: Array = [point[0],point[1],width,184]
		if kind=="bus": rect = [point[0]+40,point[1]+104,240,80]
		var door: Array = [int(rect[0])+int(rect[2])/2,int(rect[1])+int(rect[3])+40]
		if kind=="bus": door = [point[0]+160,point[1]+284]
		var entity: Dictionary = {"id":kind+str(i),"kind":kind,"rect":rect,"door":door}
		entities.append(entity)
		if i<3:special[kind] = entity
	for i: int in range(anchors.size()): entities.append({"id":"anchor%d"%i,"kind":"residence","rect":anchors[i],"door":[944,768]})
	var bus: Array = special.bus.door
	var arrivals: Array = [[bus[0]-48,bus[1]+40],[bus[0],bus[1]+40],[bus[0]+48,bus[1]+40],[bus[0],bus[1]+88]]
	var rescue: Array = entities[3].door.duplicate()
	var data: Dictionary = {"version":VERSION,"bone":bone,"attempt":attempt,"fallback":fallback,"fallback_reason":"","entities":entities,"roads":roads,"arrivals":arrivals,"enemy_points":[[80,640],[1840,800],[960,24],[960,1400]],"rescue":rescue}
	data.id = "rogue_v1_"+geometry_hash(data).substr(0,32)
	return data

static func geometry_hash(data: Dictionary) -> String:
	# Names/seed/task IDs, fallback bookkeeping and entity IDs cannot fake diversity.
	var shapes: Dictionary = {}
	for row: Dictionary in data.entities:
		var shape: Dictionary={"kind":row.kind,"rect":row.rect,"door":row.door}
		shapes[SurvivalContracts.fingerprint(shape)]=shape
	var roads: Dictionary={}
	for road: Array in data.roads:roads[SurvivalContracts.fingerprint({"v":road})]=road
	return SurvivalContracts.fingerprint({"entities":shapes,"roads":roads,"arrivals":data.arrivals,"enemy_points":data.enemy_points,"rescue":data.rescue})

static func footprint_hash(data: Dictionary) -> String:
	var blocks: Dictionary={}
	var roads: Dictionary={}
	for row: Dictionary in data.entities:blocks[SurvivalContracts.fingerprint({"v":row.rect})]=row.rect
	for road: Array in data.roads:roads[SurvivalContracts.fingerprint({"v":road})]=road
	return SurvivalContracts.fingerprint({"blocks":blocks,"roads":roads})

static func is_map_id(value: Variant) -> bool:
	return value is String and value.length()==41 and value.begins_with("rogue_v1_") and value.substr(9).is_valid_hex_number(false)

static func _point(value: Variant) -> bool:
	return value is Array and value.size()==2 and SurvivalContracts.integer(value[0],0,1920) and SurvivalContracts.integer(value[1],0,1440)

static func _rect(value: Variant) -> bool:
	return value is Array and value.size()==4 and SurvivalContracts.integer(value[0],0,1920) and SurvivalContracts.integer(value[1],0,1440) and SurvivalContracts.integer(value[2],16,1920) and SurvivalContracts.integer(value[3],16,1440) and int(value[0])+int(value[2])<=1920 and int(value[1])+int(value[3])<=1440

static func validate(value: Variant) -> String:
	if not value is Dictionary or value.size()!=11 or not value.has_all(["version","bone","attempt","fallback","fallback_reason","entities","roads","arrivals","enemy_points","rescue","id"]): return "LAYOUT_FIELDS"
	if value.version!=VERSION or value.bone not in BONES or not SurvivalContracts.integer(value.attempt,0,MAX_ATTEMPTS-1) or not value.fallback is bool or not value.fallback_reason is String or value.fallback_reason.length()>256: return "LAYOUT_VERSION"
	if not value.entities is Array or value.entities.size()<6 or value.entities.size()>7 or not value.roads is Array or value.roads.size()<1 or value.roads.size()>6: return "LAYOUT_MODULES"
	if not value.arrivals is Array or value.arrivals.size()!=4 or not value.enemy_points is Array or value.enemy_points.size()!=4 or not _point(value.rescue): return "LAYOUT_POINTS"
	var ids: Array = []
	var counts: Dictionary = {"bus":0,"cash":0,"food":0,"residence":0}
	var blockers: Array[Rect2] = []
	var doors: Array[Vector2] = []
	for row: Variant in value.entities:
		if not row is Dictionary or row.size()!=4 or not row.get("id") is String or row.id.length()>32 or row.id in ids or row.get("kind") not in counts or not _rect(row.get("rect")) or not _point(row.get("door")): return "LAYOUT_ENTITY"
		ids.append(row.id);counts[row.kind]+=1
		var rect: Rect2 = Rect2(row.rect[0],row.rect[1],row.rect[2],row.rect[3])
		for other: Rect2 in blockers:
			if rect.grow(24).intersects(other.grow(24)):return "LAYOUT_OVERLAP"
		blockers.append(rect)
		doors.append(Vector2(row.door[0],row.door[1]))
	if counts.bus!=1 or counts.cash!=1 or counts.food!=1: return "LAYOUT_TARGET_COUNT"
	for road: Variant in value.roads:
		if not _rect(road): return "LAYOUT_ROAD"
	if not is_map_id(value.id) or value.id!="rogue_v1_"+geometry_hash(value).substr(0,32): return "LAYOUT_IDENTITY"
	var signature: String = SurvivalContracts.fingerprint(value)
	if _valid.has(signature):return ""
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure(blockers)
	var bus: Vector2
	for row: Dictionary in value.entities:
		if row.kind=="bus":bus = Vector2(row.door[0],row.door[1])
	var targets: Array[Vector2] = doors.duplicate()
	targets.append(Vector2(value.rescue[0],value.rescue[1]))
	targets.append(Vector2(value.rescue[0]-40,value.rescue[1]))
	for p: Variant in value.arrivals+value.enemy_points:
		if not _point(p):return "LAYOUT_SPAWN_FIELD"
		targets.append(Vector2(p[0],p[1]))
	for target: Vector2 in targets:
		if not nav.is_clear(target): return "LAYOUT_BLOCKED_POINT"
		var path: PackedVector2Array = nav.path_between(bus,target)
		if path.is_empty() or path[-1].distance_to(target)>16:return "LAYOUT_DISCONNECTED"
	for i: int in range(4):
		var start: Vector2 = Vector2(value.arrivals[i][0],value.arrivals[i][1])
		for k: int in range(i):
			if start.distance_to(Vector2(value.arrivals[k][0],value.arrivals[k][1]))<FieldContacts.DISTANCE:return "LAYOUT_SPAWN_OCCUPANCY"
		# Actual four-person formation destinations must have clearance within bus radius.
		var tuning: ExpeditionTuning = ExpeditionTuning.new()
		var gap: float = minf(tuning.squad_spacing,tuning.boarding_radius*1.2/3.0)
		var goal: Vector2 = bus+Vector2.ONE*((i-1.5)*gap)
		if not nav.is_clear(goal) or nav.path_between(start,goal).is_empty():return "LAYOUT_BOARDING_SPACE"
	if _valid.size()>=128:_valid.clear()
	_valid[signature]=true
	return ""

static func resource(data: Dictionary) -> StreetLayout:
	assert(validate(data).is_empty())
	var result: StreetLayout = StreetLayout.new()
	result.id = StringName(data.id)
	result.display_name = NAMES[BONES.find(data.bone)]
	for row: Dictionary in data.entities:
		var rect: Rect2 = Rect2(row.rect[0],row.rect[1],row.rect[2],row.rect[3])
		var door: Vector2 = Vector2(row.door[0],row.door[1])
		match row.kind:
			"bus":result.bus_block=rect;result.bus_door=door
			"cash":result.cash_block=rect;result.cash_door=door;result.cash_title="街区货运站"
			"food":result.food_block=rect;result.food_door=door;result.food_title="街区补给店"
			"residence":result.residences.append(rect)
	for road: Array in data.roads:result.roads.append(Rect2(road[0],road[1],road[2],road[3]))
	for p: Array in data.arrivals:result.arrivals.append(Vector2(p[0],p[1]))
	for p: Array in data.enemy_points:result.enemy_points.append(Vector2(p[0],p[1]))
	result.rescue_point=Vector2(data.rescue[0],data.rescue[1])
	result.camera_start=result.bus_door+Vector2(0,-160)
	result.route_hint="沿%s寻找货运站和补给店；巴士就绪后发动并集合存活队员。"%result.display_name
	return result

static func route_length(data: Dictionary, rescue: bool = true, food: bool = true) -> int:
	var layout: StreetLayout = resource(data)
	var nav: FieldNavigation = FieldNavigation.new();nav.configure(layout.blockers())
	var maximum: float = 0
	var goals: Array[Vector2]=[layout.cash_door]
	if food:goals.append(layout.food_door)
	if rescue:goals.append(layout.rescue_point)
	for goal: Vector2 in goals:
		var path: PackedVector2Array=nav.path_between(layout.bus_door,goal)
		var length: float=0
		for i: int in range(1,path.size()):length+=path[i-1].distance_to(path[i])
		maximum=maxf(maximum,length)
	return ceili(maximum)
