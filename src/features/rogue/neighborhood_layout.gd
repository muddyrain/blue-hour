class_name NeighborhoodLayout
extends RefCounted
## V3 finite theme modules with physical gates; all saved geometry is canonical.
const SIZES: Array[String] = ["small","medium","large"]
const TOPOLOGIES: Array[String] = ["commercial","residential","industrial"]
const DIMENSIONS: Dictionary = {"small":[1920,1440],"medium":[2560,1920],"large":[3584,2688]}
const THEMES: Dictionary = {"commercial":"贯通商业街","residential":"错巷住宅区","industrial":"仓储院落"}
const MAX_ATTEMPTS: int = 3
static var _checked: Dictionary = {}

static func generate(seed: String, size: String, topology: String) -> Dictionary:
	for attempt: int in range(MAX_ATTEMPTS):
		var data: Dictionary = _assemble(seed,size,topology,attempt,false)
		if validate(data).is_empty(): return data
	var fallback: Dictionary = _assemble(seed,size,topology,0,true)
	var issue: String=validate(fallback)
	if not issue.is_empty():
		push_error("NEIGHBORHOOD_FALLBACK_INVALID "+size+" "+topology+" "+issue)
		return {}
	return fallback

static func _assemble(seed: String, size: String, topology: String, attempt: int, fallback: bool) -> Dictionary:
	var random: RandomNumberGenerator = RogueLayout.rng(("verified-v3:"+size+topology) if fallback else "neighborhood-v3:"+seed+":"+str(attempt))
	var dimensions: Array = DIMENSIONS[size]
	var width: int = dimensions[0]; var height: int = dimensions[1]
	var rank: int = SIZES.find(size)
	var cols: int = rank+3; var rows: int = rank+2
	var cell: int = (width-192)/cols
	var main_y: int = height-368
	var spacing: int = (main_y-160-464)/(rows-1)
	var entities: Array = []
	var pools: Dictionary = {"commercial":["convenience_store","eatery","supermarket","row_house","garage"],"residential":["detached_home","row_house","small_apartment","convenience_store","eatery"],"industrial":["warehouse","warehouse","garage","garage","convenience_store","small_apartment"]}
	for row: int in range(rows):
		for col: int in range(cols):
			var pool: Array = pools[topology].filter(func(t: String) -> bool: return int(NeighborhoodArt.WIDTH[t])<=cell-32)
			if topology=="commercial" and col in [cols/2-1,cols/2]:
				pool=pool.filter(func(t: String) -> bool:return int(NeighborhoodArt.WIDTH[t])<=cell-128)
			if topology=="residential" and (row*cols+col)%3!=2:
				pool=["detached_home","row_house","small_apartment"]
			if topology=="industrial" and (row*cols+col)%4!=3:
				pool=["warehouse","garage"]
			var type: String = pool[random.randi_range(0,pool.size()-1)]
			if row==0 and topology=="residential" and col<3:type=["detached_home","row_house","small_apartment"][col]
			if row==0 and topology=="industrial" and col<2:type=["warehouse","garage"][col]
			if row==0 and topology=="commercial" and col==0:type="eatery"
			if row==0 and topology=="commercial" and size=="large" and col==cols-1:type="supermarket"
			if row==rows-1 and col==0: type="small_apartment" if topology!="industrial" else "garage"
			if row==rows-1 and col==1: type="convenience_store"
			var frontage: int = NeighborhoodArt.WIDTH[type]
			var depth: int = NeighborhoodArt.DEPTH[type]
			var x: int = 96+col*cell+(cell-frontage)/2+random.randi_range(-1,1)*8
			var foot: int = 464+row*spacing+random.randi_range(-1,1)*16
			var door_x: int = x+frontage/2+roundi((NeighborhoodArt.DOOR_X[type]-256)*frontage/448.0)
			entities.append({"id":"b%02d"%(row*cols+col),"archetype":type,"rect":[x,foot-depth,frontage,depth],"door":[door_x,foot+48]})
	var roads: Array = [[0,main_y,width,240]]
	var barriers: Array = []
	var gates: Array = []
	if topology=="commercial":
		roads.append([96+cell*(cols/2)-48,0,96,main_y+240])
		for row: int in range(rows-1): roads.append([32,464+row*spacing+112,width-64,96])
	elif topology=="residential":
		var previous: int = width/2
		for row: int in range(rows-1,-1,-1):
			var lane_y: int = 464+row*spacing+112
			var next: int = 96+cell*(1 if row%2 else cols-1)
			roads.append([mini(previous,next)-64,lane_y,absi(previous-next)+128,112])
			roads.append([next-48,0 if row==0 else lane_y-spacing,96,lane_y+112 if row==0 else spacing+112])
			previous=next
			if row<rows-1:
				var side: int = 96 if random.randi_range(0,1)==0 else width-192
				_add_wall(barriers,lane_y+20,width,[[next-72,next+72],[side-56,side+96]])
				gates.append([next,lane_y+36]);gates.append([side+20,lane_y+36])
	else:
		roads.append([24,96,96,main_y+144]); roads.append([width-120,96,96,main_y+144]); roads.append([32,96,width-64,144])
		for row: int in range(rows-1):
			var lane_y: int = 464+row*spacing+112
			roads.append([64,lane_y,width-128,144])
			var gate: int = width/2+random.randi_range(-1,1)*int(cell/2)
			_add_wall(barriers,lane_y+16,width,[[64,224],[gate-112,gate+112],[width-224,width-64]])
			gates.append([gate,lane_y+32])
	# Stop beside a real junction, with the complete bus clear of its opening.
	var side: int=random.randi_range(0,1)
	var stop_x: int
	if topology=="industrial":stop_x=144+side*32
	else:
		var junction: int=96+cell*(cols/2 if topology=="commercial" else (1 if (rows-1)%2 else cols-1))
		stop_x=junction+72 if side==0 else junction-312
		if topology=="residential" and rows%2==1:stop_x=junction-360+side*16
	stop_x=clampi(stop_x+random.randi_range(0,2)*8,144,width-400)
	var foot_y: int = main_y+192
	var door: Array = [stop_x+190,main_y+288]
	var data: Dictionary = {"version":3,"seed":seed,"size":size,"topology":topology,"attempt":attempt,"fallback":fallback,"bounds":[0,0,width,height],"entities":entities,"roads":roads,"barriers":barriers,"gates":gates,
		"bus":{"rect":[stop_x,foot_y-80,240,80],"door":door,"passenger_door":[stop_x+190,foot_y-16],"entry":[-160,foot_y],"exit":[width+160,foot_y],"sweep":[0,main_y+92,width,120],"facing":"right"},
		"arrivals":[[door[0]-48,door[1]+24],[door[0],door[1]+24],[door[0]+48,door[1]+24],[door[0],door[1]+56]],"enemy_points":[[24,main_y-40],[width-24,main_y-40],[width/2,24],[width/2,height-20]],"rescue":entities[0].door.duplicate()}
	data.id="rogue_v3_"+SurvivalContracts.fingerprint(data).substr(0,32)
	return data

static func _add_wall(result: Array, y: int, width: int, openings: Array) -> void:
	openings.sort_custom(func(a: Array,b: Array) -> bool: return a[0]<b[0])
	var left: int = 0
	for gap: Array in openings:
		var right: int = maxi(left,int(gap[0]))
		if right-left>=24: result.append([left,y,right-left,24])
		left=maxi(left,int(gap[1]))
	if width-left>=24: result.append([left,y,width-left,24])

static func is_map_id(v: Variant) -> bool:
	return v is String and v.length()==41 and v.begins_with("rogue_v3_") and v.substr(9).is_valid_hex_number(false)

static func validate(value: Variant, cached: bool = true) -> String:
	var stamp: int = FreezeProfile.enter("layout.validate")
	var result: String = _profiled_validate(value,cached)
	FreezeProfile.leave("layout.validate", stamp)
	return result


static func _profiled_validate(value: Variant, cached: bool = true) -> String:
	if not value is Dictionary or value.size()!=16 or not value.has_all(["version","seed","size","topology","attempt","fallback","bounds","entities","roads","barriers","gates","bus","arrivals","enemy_points","rescue","id"]): return "NEIGHBORHOOD_FIELDS"
	if value.version!=3 or not value.seed is String or value.seed.length()>128 or value["size"] not in SIZES or value.topology not in TOPOLOGIES or not SurvivalContracts.integer(value.attempt,0,2) or not value.fallback is bool: return "NEIGHBORHOOD_VERSION"
	var signature: String = SurvivalContracts.fingerprint(value)
	if cached and _checked.has(signature): return ""
	if not TransactionReceipt.same(value,_assemble(value.seed,value["size"],value.topology,int(value.attempt),value.fallback)): return "NEIGHBORHOOD_CANONICAL"
	var bounds: Rect2 = WorldLayout.rect(value.bounds)
	var blocks: Array[Rect2] = []
	for entity: Dictionary in value.entities:
		var block: Rect2 = WorldLayout.rect(entity.rect)
		if not bounds.encloses(block) or block.intersects(WorldLayout.rect(value.bus.sweep)): return "NEIGHBORHOOD_BOUNDS_OR_BUS"
		for other: Rect2 in blocks:
			if block.grow(12).intersects(other): return "NEIGHBORHOOD_OVERLAP"
		blocks.append(block)
	for road: Array in value.roads:
		var area: Rect2=WorldLayout.rect(road)
		if not bounds.encloses(area) or area.size.x<=0 or area.size.y<=0:return "NEIGHBORHOOD_ROAD_BOUNDS"
		for block: Rect2 in blocks:
			if area.intersects(block):return "NEIGHBORHOOD_ROAD_BUILDING"
	for wall: Array in value.barriers:
		var block: Rect2 = WorldLayout.rect(wall)
		if not bounds.encloses(block) or block.intersects(WorldLayout.rect(value.bus.sweep)): return "NEIGHBORHOOD_WALL"
		for other: Rect2 in blocks:
			if block.grow(12).intersects(other): return "NEIGHBORHOOD_WALL_BUILDING"
		blocks.append(block)
	blocks.append(WorldLayout.rect(value.bus.rect))
	var nav: FieldNavigation = FieldNavigation.new(); nav.configure(blocks,bounds)
	var start: Vector2 = WorldLayout.point(value.bus.door)
	var goals: Array = value.arrivals+value.enemy_points+[value.rescue]
	for e: Dictionary in value.entities: goals.append(e.door)
	for p: Array in goals:
		var target: Vector2 = WorldLayout.point(p)
		if not nav.is_clear(target): return "NEIGHBORHOOD_POINT_"+str(p)
		var path: PackedVector2Array = nav.path_between(start,target)
		if path.is_empty() or path[-1].distance_to(target)>16: return "NEIGHBORHOOD_ROUTE"
	for i: int in range(4):
		if not nav.is_clear(start+Vector2.ONE*((i-1.5)*35.2)): return "NEIGHBORHOOD_GATHER"
	if _checked.size()>128: _checked.clear()
	_checked[signature]=true
	return ""

static func resource(data: Dictionary) -> StreetLayout:
	var result: StreetLayout = StreetLayout.new()
	result.id=StringName(data.id);result.display_name=THEMES[data.topology]
	result.world_bounds=WorldLayout.rect(data.bounds);result.world_data=data.duplicate(true)
	result.bus_block=WorldLayout.rect(data.bus.rect);result.bus_door=WorldLayout.point(data.bus.door)
	for e: Dictionary in data.entities: result.residences.append(WorldLayout.rect(e.rect))
	for b: Array in data.barriers: result.fences.append(WorldLayout.rect(b))
	for r: Array in data.roads: result.roads.append(WorldLayout.rect(r))
	for p: Array in data.arrivals: result.arrivals.append(WorldLayout.point(p))
	for p: Array in data.enemy_points: result.enemy_points.append(WorldLayout.point(p))
	result.cash_block=result.residences[0];result.food_block=result.residences[1]
	result.cash_door=WorldLayout.point(data.entities[0].door);result.food_door=WorldLayout.point(data.entities[1].door)
	result.rescue_point=WorldLayout.point(data.rescue);result.camera_start=result.bus_door+Vector2(360,-220)
	result.route_hint={"commercial":"沿主街选店搜刮，侧后通道可绕行。","residential":"庭院砖墙留有错位巷口和侧门，注意往返路线。","industrial":"经装卸院口或外围服务路绕行，留意长墙遮挡。"}[data.topology]
	return result
