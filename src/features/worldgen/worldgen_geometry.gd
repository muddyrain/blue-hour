class_name WorldgenGeometry
extends RefCounted
## Roads partition the city before frontage, yards and individual buildings are placed.
const DIMENSIONS: Dictionary = {"small":[2560,1920],"medium":[3584,2688],"large":[4608,3456]}
const MIN_WIDTH: int = 736
const MIN_HEIGHT: int = 464

static func assemble(seed: String, size: String, topology: String, attempt: int, fallback: bool,
		task: String = "", industrial: bool = false, residential_rescue: bool = false,
		open_streets: bool = false) -> Dictionary:
	if residential_rescue and (topology != "residential" or task != "rescue"):
		return {}
	var random: RandomNumberGenerator = RogueLayout.rng("worldgen-v1:" + ((size + ":" + topology + ":fallback") if fallback else seed + ":" + str(attempt)))
	var dimensions: Array = OpenStreetsV1.BOUNDS.slice(2) if open_streets else DIMENSIONS[size]
	var width: int = int(dimensions[0])
	var height: int = int(dimensions[1])
	var rank: int = NeighborhoodLayout.SIZES.find(size)
	var main_y: int = int(round(float(height) * random.randf_range(0.40,0.61) / 32.0)) * 32
	var main_width: int = WorldgenScale.MAIN_WIDTH
	var segments: Array = [[0,main_y+main_width/2,width,main_y+main_width/2,main_width]]
	var leaves: Array = [
		{"rect":[0,0,width,main_y],"edges":[false,true,false,false]},
		{"rect":[0,main_y+main_width,width,height-main_y-main_width],"edges":[true,false,false,false]}
	]
	var skeleton: Dictionary = OpenStreetsV1.skeleton(seed, topology, attempt, fallback) if open_streets else {}
	if open_streets:
		if skeleton.is_empty():
			return {}
		segments = skeleton.segments
		leaves = skeleton.leaves
	var target: int = (28 if open_streets else [5,8,11][rank]) + random.randi_range(-1,1)
	# Each cut joins at least one existing road edge. Both children retain that edge.
	for step: int in range(28 if open_streets else 18):
		if leaves.size() >= target: break
		var options: Array[Dictionary] = []
		for index: int in range(leaves.size()):
			var parcel: Dictionary = leaves[index]
			var box: Rect2 = WorldLayout.rect(parcel.rect)
			if box.size.x >= MIN_WIDTH * 2 + 128 and (parcel.edges[0] or parcel.edges[1]):
				options.append({"index":index,"vertical":true,"score":box.get_area()*random.randf_range(0.7,1.3)})
			if box.size.y >= MIN_HEIGHT * 2 + 128 and (parcel.edges[2] or parcel.edges[3]):
				options.append({"index":index,"vertical":false,"score":box.get_area()*random.randf_range(0.7,1.3)})
		if options.is_empty(): break
		options.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.score > b.score)
		var choice: Dictionary = options[0]
		var parent: Dictionary = leaves[int(choice.index)]
		leaves.remove_at(int(choice.index))
		_split(parent, bool(choice.vertical), random, leaves, segments)
		if open_streets and not OpenStreetsV1.stop_clear(skeleton.bus, _roads([segments[-1]], width, height)):
			segments.pop_back()
			leaves.resize(leaves.size() - 2)
			leaves.insert(int(choice.index), parent)
	var roads: Array = _roads(segments,width,height)
	var parcels: Array = []
	# Small local dead ends create service courts without replacing a whole-map template.
	for index: int in range(leaves.size()):
		var leaf: Dictionary = leaves[index]
		var box: Rect2 = WorldLayout.rect(leaf.rect)
		var kinds: Array = {"commercial":["shopfront","shopfront","courtyard","parking"],"residential":["garden","courtyard","homes","homes"],"industrial":["loading","loading","service","parking"]}[topology]
		var kind: String = kinds[random.randi_range(0,kinds.size()-1)]
		var stub: bool = index == random.randi_range(0,leaves.size()-1) and box.size.x >= 1000 and box.size.y >= 600 and (leaf.edges[0] or leaf.edges[1])
		if stub:
			var x: int = int(box.end.x - 176)
			var from_y: int = _connect(int(box.end.y if leaf.edges[1] else box.position.y),x,true,segments)
			var to_y: int = int(box.end.y-240 if leaf.edges[1] else box.position.y+240)
			var spur: Array = [[x,mini(from_y,to_y),x,maxi(from_y,to_y),96], [x-160,to_y,x,to_y,96]]
			if not open_streets or OpenStreetsV1.stop_clear(skeleton.bus, _roads(spur, width, height)):
				segments.append_array(spur)
				kind = "service" if topology == "industrial" else "courtyard"
			else:
				stub = false
		parcels.append({"id":"p%02d"%index,"rect":leaf.rect.duplicate(),"kind":kind,"road_edges":leaf.edges.duplicate(),"buildings":[],"entrance":[],"dead_end":stub,"courtyards":[],"walks":[],"frontage":{"available":0.0,"occupied":0.0,"coverage":0.0}})
	roads = _roads(segments,width,height)
	var stop_x: int = 0 if open_streets else _stop_x(width,main_y,roads,random)
	var foot_y: int = main_y+main_width-48
	var door: Array = [stop_x+190,main_y+main_width+48]
	var bus: Dictionary = {"rect":[stop_x,foot_y-80,240,80],"door":door,"passenger_door":[stop_x+190,foot_y-16],"entry":[-160,foot_y],"exit":[width+160,foot_y],"sweep":[0,foot_y-100,width,120],"facing":"right"}
	if open_streets:
		bus = skeleton.bus
		door = bus.door
	if not task.is_empty():
		LevelPolicy.prepare(parcels, task, seed, WorldLayout.point(door) if open_streets else Vector2.INF)
	var entities: Array = []
	var yard_plan: Dictionary = {}
	var yard: Dictionary = {}
	var yard_parcel: String = ""
	var rescue_plan: Dictionary = {}
	var court: Dictionary = {}
	if industrial and task == "airdrop" and topology == "industrial":
		yard_plan = IndustrialYard.plan(parcels, roads, bus, seed)
		if yard_plan.is_empty():
			return {}
		yard = yard_plan.frozen
		yard_parcel = yard.parcel
	if residential_rescue:
		rescue_plan = RescueCourt.plan(parcels, roads, bus, seed, float(width))
		if rescue_plan.is_empty():
			return {}
		court = rescue_plan.frozen
		yard_parcel = court.parcel
	for parcel: Dictionary in parcels:
		if parcel.id == yard_parcel:
			var filled: bool = _populate_rescue_court(parcel, rescue_plan, entities, roads, bus) if residential_rescue \
				else _populate_yard(parcel, yard_plan, entities, roads, bus)
			if not filled:
				return {}
		else:
			_populate(parcel,topology,random,entities,roads,bus, (2 if topology == "commercial" and parcel.kind == "shopfront" else 1) if open_streets else 0)
	# Food and equipment are actual parcels, not rewards granted to every building.
	_ensure_categories(entities,parcels,roads,bus,yard_parcel)
	_update_frontages(parcels,entities,yard_parcel)
	var rescue: Array = entities[0].door.duplicate() if not entities.is_empty() else [64,64]
	var furthest: float = 0.0
	for entity: Dictionary in entities:
		var distance: float = WorldLayout.point(entity.door).distance_squared_to(WorldLayout.point(door))
		if distance > furthest:
			furthest=distance
			rescue=entity.door.duplicate()
	var walls: Dictionary = _walls(parcels,entities,roads,bus)
	if not yard.is_empty():
		walls.barriers.append_array(yard_plan.barriers)
		walls.gates.append(yard.loading.gate)
		walls.gates.append(yard.service.gate)
	if not court.is_empty():
		walls.barriers.append_array(rescue_plan.barriers)
		walls.gates.append(court.front.gate)
		walls.gates.append(court.side.gate)
	var arrivals: Array = [[door[0]-48,door[1]+24],[door[0],door[1]+24],[door[0]+48,door[1]+24],[door[0],door[1]+56]]
	var data: Dictionary = {"version":5,"seed":seed,"size":size,"topology":topology,"attempt":attempt,"fallback":fallback,"bounds":[0,0,width,height],"entities":entities,"roads":roads,"barriers":walls.barriers,"gates":walls.gates,"bus":bus,"arrivals":arrivals,"enemy_points":[[24,main_y+24],[width-24,main_y+24]],"rescue":rescue,"objects":[],"parcels":parcels,"graph":WorldgenStructure.graph(segments)}
	if open_streets:
		data.open_streets = OpenStreetsV1.VERSION
		data.arrivals = skeleton.arrivals
		data.enemy_points = skeleton.enemy_points
	if not yard.is_empty():
		data.loading_yard = yard
	if not task.is_empty():
		data.level_task=task
		if task=="rescue":
			var target_point: Array = court.target.duplicate() if not court.is_empty() else LevelPolicy.rescue_point(data)
			if target_point.is_empty():
				return {}
			data.rescue=target_point
	if not court.is_empty():
		data.rescue_court = court
	data.art_revision = 3
	data.id = "worldgen_v1_"+RecordEncoding.fingerprint(data).substr(0,32)
	return data

static func _split(parent: Dictionary, vertical: bool, random: RandomNumberGenerator, leaves: Array, segments: Array) -> void:
	var rect: Array = parent.rect
	var x: int = int(rect[0]); var y: int = int(rect[1]); var width: int = int(rect[2]); var height: int = int(rect[3])
	var edges: Array = parent.edges
	if vertical:
		var offset: int = clampi(int(round(width*random.randf_range(0.36,0.64)/32.0))*32,MIN_WIDTH+64,width-MIN_WIDTH-64)
		segments.append([x+offset,_connect(y,x+offset,true,segments) if edges[0] else y,x+offset,_connect(y+height,x+offset,true,segments) if edges[1] else y+height,128])
		leaves.append({"rect":[x,y,offset-64,height],"edges":[edges[0],edges[1],edges[2],true]})
		leaves.append({"rect":[x+offset+64,y,width-offset-64,height],"edges":[edges[0],edges[1],true,edges[3]]})
	else:
		var offset: int = clampi(int(round(height*random.randf_range(0.36,0.64)/32.0))*32,MIN_HEIGHT+64,height-MIN_HEIGHT-64)
		segments.append([_connect(x,y+offset,false,segments) if edges[2] else x,y+offset,_connect(x+width,y+offset,false,segments) if edges[3] else x+width,y+offset,128])
		leaves.append({"rect":[x,y,width,offset-64],"edges":[edges[0],true,edges[2],edges[3]]})
		leaves.append({"rect":[x,y+offset+64,width,height-offset-64],"edges":[true,edges[1],edges[2],edges[3]]})

static func _connect(edge: int, along: int, vertical: bool, segments: Array) -> int:
	for segment: Array in segments:
		if vertical and segment[1]==segment[3] and absi(int(segment[1])-edge)<=maxi(WorldgenScale.MAIN_WIDTH,int(segment[4]))/2 and along>=int(segment[0]) and along<=int(segment[2]):return int(segment[1])
		if not vertical and segment[0]==segment[2] and absi(int(segment[0])-edge)<=maxi(WorldgenScale.MAIN_WIDTH,int(segment[4]))/2 and along>=int(segment[1]) and along<=int(segment[3]):return int(segment[0])
	return edge

static func _roads(segments: Array, width: int, height: int) -> Array:
	var result: Array = []
	var bounds: Rect2 = Rect2(0,0,width,height)
	for line: Array in segments:
		var vertical: bool = line[0] == line[2]
		var half: float = float(line[4])/2.0
		var rect: Rect2 = Rect2(Vector2(line[0]-half,line[1]),Vector2(line[4],line[3]-line[1])) if vertical else Rect2(Vector2(line[0],line[1]-half),Vector2(line[2]-line[0],line[4]))
		rect=rect.intersection(bounds)
		result.append([rect.position.x,rect.position.y,rect.size.x,rect.size.y])
	return result

static func _stop_x(width: int, main_y: int, roads: Array, random: RandomNumberGenerator) -> int:
	var candidates: Array[int] = []
	for x: int in range(176,width-448,32):
		var berth: Rect2 = Rect2(x-48,main_y,336,WorldgenScale.MAIN_WIDTH)
		var clear: bool = true
		for value: Array in roads:
			var road: Rect2 = WorldLayout.rect(value)
			if road.size.y > road.size.x and road.intersects(berth): clear=false
		if clear: candidates.append(x)
	return candidates[random.randi_range(0,candidates.size()-1)] if not candidates.is_empty() else 176

static func _populate_yard(parcel: Dictionary, plan: Dictionary, entities: Array, roads: Array, bus: Dictionary) -> bool:
	var yard: Dictionary = plan.frozen
	var warehouse: Vector2 = plan.warehouse_foot
	var garage: Vector2 = plan.garage_foot
	if not _add_building("warehouse", 0, warehouse.x, warehouse.y, parcel, entities, roads, bus):
		return false
	yard.warehouse = entities[-1].id
	if not _add_building("garage", 0, garage.x, garage.y, parcel, entities, roads, bus):
		return false
	yard.garage = entities[-1].id
	parcel.kind = "service"
	parcel.entrance = yard.loading.gate.duplicate()
	parcel.frontage.scope = "internal"
	_add_court(parcel, plan.cargo_area, "loading", plan.cargo_entry, entities, roads, bus)
	for name: String in ["loading", "service"]:
		for paving: Array in yard[name].paving:
			_add_walk(parcel, WorldLayout.rect(paving))
	return true


static func _populate_rescue_court(parcel: Dictionary, plan: Dictionary, entities: Array, roads: Array, bus: Dictionary) -> bool:
	var home: Vector2 = plan.home
	var annex: Vector2 = plan.annex
	var court: Dictionary = plan.frozen
	if not _add_building("row_house", 0, home.x, home.y, parcel, entities, roads, bus):
		return false
	court.home = entities[-1].id
	RescueCourt.finish(court, plan, WorldLayout.point(entities[-1].door))
	if not _add_building("detached_home", 3, annex.x, annex.y, parcel, entities, roads, bus):
		return false
	court.optional_building = entities[-1].id
	parcel.kind = "homes"
	parcel.entrance = court.front.gate.duplicate()
	parcel.frontage.scope = "internal"
	for approach: Dictionary in [court.front, court.side]:
		for paving: Array in approach.paving:
			_add_walk(parcel, WorldLayout.rect(paving))
	return true

static func _populate(parcel: Dictionary, topology: String, random: RandomNumberGenerator, entities: Array, roads: Array, bus: Dictionary, row_limit: int = 0) -> void:
	var box: Rect2=WorldLayout.rect(parcel.rect)
	var group_count: int=maxi(1,int((box.size.x-96.0)/720.0))
	var group_width: float=(box.size.x-96.0-96.0*(group_count-1))/group_count
	var setback: float=200.0 if parcel.kind=="loading" else 208.0 if parcel.kind=="parking" else (80.0 if parcel.road_edges[1] else 120.0) if parcel.kind=="garden" else (64.0 if parcel.road_edges[1] else 104.0)
	var front_foot: float=box.end.y-setback
	var front_available: float=0.0
	var front_occupied: float=0.0
	var entry_x: float=box.position.x+32.0
	var entry_y: float=box.end.y-32.0 if parcel.road_edges[1] else box.position.y+32.0 if parcel.road_edges[0] else front_foot+48.0
	parcel.entrance=[entry_x,entry_y]
	# Explicit orthogonal lanes are authored from groups, never from a navigation polyline.
	_add_walk(parcel,Rect2(entry_x-24,box.position.y+16,48,box.size.y-32))
	for group: int in range(group_count):
		var left: float=box.position.x+48+group*(group_width+96)
		var lane_x: float=left-24 if group==0 else left-48
		_add_walk(parcel,Rect2(lane_x-28,box.position.y+16,56,box.size.y-32))
		var foot: float=front_foot
		var row: int=0
		var rear_roof: float=box.end.y
		while foot>box.position.y+128 and (row_limit == 0 or row < row_limit):
			var headroom: float=foot-box.position.y-16.0
			var pool: Array=_building_pool(parcel.kind,topology,row)
			# A shallow commercial back row uses low shops; homes are admitted only
			# when their actual roof fits, including the shorter courtyard variant.
			if row>0 and topology=="commercial" and headroom<WorldgenScale.visible_height("detached_home",3):
				pool=["convenience_store","eatery","garage"]
			pool=pool.filter(func(type: String) -> bool: return WorldgenScale.visible_height(type,3 if type=="detached_home" else 0)<=headroom)
			if pool.is_empty():break
			var gap: float=24.0 if row==0 and parcel.kind=="shopfront" else 32.0 if topology=="commercial" else 40.0
			var types: Array[String]=_fill_frontage(pool,group_width,gap,random)
			var paired: bool = row==0 and topology=="commercial" and parcel.kind in ["shopfront","courtyard"] and group_width>=560 and headroom>=248
			if paired:
				gap=16.0
				types.assign(["convenience_store","eatery"] if random.randi_range(0,1)==0 else ["eatery","convenience_store"])
			if types.is_empty():break
			var used: float=gap*maxi(0,types.size()-1)
			for type: String in types:used+=float(WorldgenScale.WIDTH[type])
			var x: float=left+(group_width-used)*0.5
			var occupied: float=0.0
			var row_height: float=0.0
			var row_depth: float=0.0
			for type: String in types:
				var variant: int=3 if type=="detached_home" and (headroom<WorldgenScale.visible_height(type) or random.randi_range(0,1)==0) else random.randi_range(0,2)
				var art: String = StreetModuleArt.for_archetype(type) if paired else ""
				row_height=maxf(row_height,WorldgenScale.visible_height(type,variant,art))
				row_depth=maxf(row_depth,float(WorldgenScale.DEPTH[type]))
				if _add_building(type,variant,x,foot,parcel,entities,roads,bus,art):occupied+=float(WorldgenScale.WIDTH[type])
				x+=float(WorldgenScale.WIDTH[type])+gap
			# At least 24 world units separate visible roofs and rear feet. The
			# physical gap also leaves the rear door +48 and its 48-wide walk clear.
			var spacing: float=ceil(maxf(208.0,maxf(row_height+24.0,row_depth+112.0))/16.0)*16.0
			if paired:
				spacing=ceil((row_height+192.0)/16.0)*16.0
			if row_height<=240.0:spacing+=16.0*random.randi_range(0,1)
			var roof_top: float=foot-row_height
			if occupied>0:rear_roof=minf(rear_roof,roof_top)
			_add_walk(parcel,Rect2(lane_x-28,foot+24,left+group_width-lane_x+28,48))
			if row==0:
				front_available+=_available_frontage(left,group_width,foot,roads,bus)
				front_occupied+=occupied
			var kind: String="loading" if topology=="industrial" else "garden" if topology=="residential" or row>0 else "court"
			# Courts occupy visible free land, not the physical space under a roof.
			# The next row's foot is below this strip; its roof extends northward.
			var court_top: float=maxf(box.position.y+24,foot-spacing+16)
			_add_court(parcel,Rect2(left+8,court_top,group_width-16,roof_top-16-court_top),kind,Vector2(lane_x,foot-spacing+48),entities,roads,bus)
			var side_width: float=(group_width-used)*0.5-16.0
			_add_court(parcel,Rect2(left+8,roof_top,side_width,row_height-16),kind,Vector2(lane_x,foot+48),entities,roads,bus)
			_add_court(parcel,Rect2(left+group_width-side_width-8,roof_top,side_width,row_height-16),kind,Vector2(lane_x,foot+48),entities,roads,bus)
			if row==0 and parcel.kind in ["parking","loading"]:
				_add_court(parcel,Rect2(left+8,foot+60,group_width-16,box.end.y-32-(foot+60)),parcel.kind,Vector2(lane_x,foot+72),entities,roads,bus)
			foot-=spacing
			row+=1
		# The shallow strip behind the last roofs is a planted/back-service edge, not an unassigned lawn.
		var rear_end: float=rear_roof-16
		if rear_end>box.position.y+56:
			_add_court(parcel,Rect2(left+8,box.position.y+24,group_width-16,rear_end-box.position.y-24),"loading" if topology=="industrial" else "garden",Vector2(lane_x,box.position.y+40),entities,roads,bus)
	# A top or side road connects the same straight lane; gaps between groups stay open.
	if parcel.road_edges[0]:_add_walk(parcel,Rect2(box.position.x+16,box.position.y+16,box.size.x-32,48))
	if parcel.road_edges[3]:_add_walk(parcel,Rect2(box.position.x+16,front_foot+24,box.size.x-32,48))
	parcel.frontage={"available":front_available,"occupied":front_occupied,"coverage":front_occupied/front_available if front_available>0 else 0.0}

static func _building_pool(kind: String, topology: String, row: int) -> Array:
	if row>0:
		if topology=="industrial":return ["warehouse","garage","convenience_store"]
		# Apartments are occasional back-of-block landmarks, never a repeated front wall.
		return ["detached_home","row_house","detached_home","garage","small_apartment"] if row>=2 else ["detached_home","row_house","convenience_store","detached_home"]
	return {"shopfront":["convenience_store","eatery","garage","convenience_store","supermarket"],
		"courtyard":["eatery","row_house","convenience_store"] if topology=="commercial" else ["detached_home","row_house"],
		"parking":["garage","convenience_store","supermarket"] if topology=="commercial" else ["warehouse","garage"],
		"garden":["detached_home","row_house"],"homes":["detached_home","row_house"],
		"loading":["warehouse","garage","warehouse"],"service":["warehouse","garage","convenience_store"]}[kind]

static func _fill_frontage(pool: Array, width: float, gap: float, random: RandomNumberGenerator) -> Array[String]:
	var result: Array[String]=[]
	var remaining: float=width*0.90 # Includes inter-building gaps; measured façade coverage is lower.
	while remaining>=256:
		var choices: Array=pool.filter(func(type: String) -> bool: return float(WorldgenScale.WIDTH[type])<=remaining)
		if choices.is_empty():break
		var type: String=choices[random.randi_range(0,choices.size()-1)]
		if not result.is_empty() and type==result[-1] and choices.any(func(other: String) -> bool: return other!=type):
			choices=choices.filter(func(other: String) -> bool: return other!=type)
			type=choices[random.randi_range(0,choices.size()-1)]
		result.append(type)
		remaining-=float(WorldgenScale.WIDTH[type])+gap
	return result

static func _available_frontage(left: float, width: float, foot: float, roads: Array, bus: Dictionary) -> float:
	var spans: Array[Vector2]=[Vector2(left,left+width)]
	var clearances: Array[Rect2] = OpenStreetsV1.swept_rects(bus, 32)
	clearances.append(Rect2(WorldLayout.point(bus.door)-Vector2(148,148),Vector2(296,296)))
	for road: Array in roads:clearances.append(WorldLayout.rect(road).grow(16))
	for area: Rect2 in clearances:
		if area.end.y<=foot-128 or area.position.y>=foot:continue
		var next: Array[Vector2]=[]
		for span: Vector2 in spans:
			if area.end.x<=span.x or area.position.x>=span.y:next.append(span);continue
			if area.position.x>span.x:next.append(Vector2(span.x,area.position.x))
			if area.end.x<span.y:next.append(Vector2(area.end.x,span.y))
		spans=next
	var result: float=0.0
	for span: Vector2 in spans:result+=span.y-span.x
	return result

static func _add_walk(parcel: Dictionary, rect: Rect2) -> void:
	var area: Rect2=rect.intersection(WorldLayout.rect(parcel.rect))
	if area.size.x>0 and area.size.y>0:parcel.walks.append([area.position.x,area.position.y,area.size.x,area.size.y])

static func _add_court(parcel: Dictionary, area: Rect2, kind: String, entrance: Vector2, entities: Array, roads: Array, bus: Dictionary) -> void:
	if area.size.x<40 or area.size.y<40:return
	for entity: Dictionary in entities:
		if area.intersects(WorldgenScale.visible_rect(entity)):return
	for road: Array in roads:
		if area.intersects(WorldLayout.rect(road)):return
	if area.intersects(WorldLayout.rect(bus.rect)):return
	parcel.courtyards.append({"rect":[area.position.x,area.position.y,area.size.x,area.size.y],"kind":kind,"entrance":[entrance.x,entrance.y]})

static func _add_building(type: String, variant: int, x: float, foot: float, parcel: Dictionary, entities: Array, roads: Array, bus: Dictionary, art: String = "") -> bool:
	var width: float = float(WorldgenScale.WIDTH[type]);var depth: float=float(WorldgenScale.DEPTH[type])
	var block: Rect2 = Rect2(x,foot-depth,width,depth)
	var plot: Rect2 = WorldLayout.rect(parcel.rect)
	if not plot.grow(-32).encloses(block):return false
	if foot-WorldgenScale.visible_height(type,variant,art)<plot.position.y+16:return false
	# Keep all boarding/arrival positions and the full sweep free before props are added.
	if OpenStreetsV1.intersects_sweep(bus, block, 32) or block.grow(20).intersects(Rect2(WorldLayout.point(bus.door)-Vector2(128,128),Vector2(256,256))):return false
	for value: Array in roads:
		if block.grow(16).intersects(WorldLayout.rect(value)):return false
	for entity: Dictionary in entities:
		if block.grow(16).intersects(WorldLayout.rect(entity.rect)):return false
	var id: String = "b%02d"%entities.size()
	var door_x: float = x+width/2.0+(WorldgenScale.door_x(type,variant)-256.0)*width/448.0
	if not art.is_empty():
		door_x=x+width/2.0+StreetModuleArt.door_offset(art,width)
	entities.append({"id":id,"archetype":type,"rect":[x,foot-depth,width,depth],"door":[door_x,foot+48],"variant":variant,"parcel":parcel.id})
	if not art.is_empty():
		entities[-1].art=art
	parcel.buildings.append(id)
	return true

static func _update_frontages(parcels: Array, entities: Array, yard_parcel: String = "") -> void:
	for parcel: Dictionary in parcels:
		if parcel.id == yard_parcel:
			continue
		# A blocked frontage stays empty; a remaining rear row must not become the street façade.
		var setback: float=200.0 if parcel.kind=="loading" else 208.0 if parcel.kind=="parking" else (80.0 if parcel.road_edges[1] else 120.0) if parcel.kind=="garden" else (64.0 if parcel.road_edges[1] else 104.0)
		var foot: float=WorldLayout.rect(parcel.rect).end.y-setback
		var occupied: float=0.0
		for entity: Dictionary in entities:
			if entity.parcel==parcel.id and is_equal_approx(float(entity.rect[1])+float(entity.rect[3]),foot):occupied+=float(entity.rect[2])
		parcel.frontage.occupied=occupied
		parcel.frontage.coverage=occupied/float(parcel.frontage.available) if parcel.frontage.available>0 else 0.0
		# South-facing art fronts a street only where this parcel has a south road.
		# Other first rows serve an internal court, and cannot prove street coverage.
		parcel.frontage.scope="street" if parcel.road_edges[1] else "internal"

static func _walls(parcels: Array, entities: Array, roads: Array, bus: Dictionary) -> Dictionary:
	var barriers: Array=[]
	var gates: Array=[]
	for parcel: Dictionary in parcels:
		if parcel.kind not in ["garden","courtyard","loading"]:continue
		var box: Rect2=WorldLayout.rect(parcel.rect)
		var wall: Rect2=Rect2(box.position.x+36,box.end.y-280,minf(240,box.size.x*0.3),16)
		var gate: Vector2=Vector2(wall.end.x+52,wall.get_center().y)
		var clear: bool=true
		for entity: Dictionary in entities:
			var block: Rect2=WorldLayout.rect(entity.rect)
			clear=clear and not wall.grow(32).intersects(block) and not block.grow(32).has_point(gate) and not wall.grow(56).has_point(WorldLayout.point(entity.door))
		for other: Dictionary in parcels:
			clear=clear and not wall.grow(44).has_point(WorldLayout.point(other.entrance))
			for court: Dictionary in other.courtyards:
				clear=clear and not wall.grow(44).has_point(WorldLayout.point(court.entrance))
		for road: Array in roads:clear=clear and not wall.grow(24).intersects(WorldLayout.rect(road))
		clear=clear and not OpenStreetsV1.intersects_sweep(bus, wall, 40) and not Rect2(WorldLayout.point(bus.door)-Vector2(160,160),Vector2(320,320)).intersects(wall)
		if clear:
			barriers.append([wall.position.x,wall.position.y,wall.size.x,wall.size.y]);gates.append([gate.x,gate.y])
	return {"barriers":barriers,"gates":gates}

static func _ensure_categories(entities: Array, parcels: Array, roads: Array, bus: Dictionary, yard_parcel: String = "") -> void:
	# Geometric distance is only a placement preference. The final navigation certificate
	# must still prove a non-near real food/workshop entrance after every prop is added.
	var farthest: float=0.0
	var bus_door: Vector2=WorldLayout.point(bus.door)
	var ranked: Array=entities.duplicate()
	ranked.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return WorldLayout.point(a.door).distance_squared_to(bus_door)>WorldLayout.point(b.door).distance_squared_to(bus_door))
	for entity: Dictionary in entities:farthest=maxf(farthest,WorldLayout.point(entity.door).distance_squared_to(bus_door))
	for category: Array in [TaskActions.FOOD_TYPES,TaskActions.GEAR_TYPES]:
		var count: int=0
		var away: bool=false
		var opposite: Array=TaskActions.GEAR_TYPES if category==TaskActions.FOOD_TYPES else TaskActions.FOOD_TYPES
		var other_count: int=0
		var other_away: int=0
		for entity: Dictionary in entities:
			if entity.archetype in category:
				count+=1
				away=away or WorldLayout.point(entity.door).distance_squared_to(bus_door)>=farthest*0.36
			if entity.archetype in opposite:
				other_count+=1
				if WorldLayout.point(entity.door).distance_squared_to(bus_door)>=farthest*0.36:other_away+=1
		for entity: Dictionary in ranked:
			if count>=2 and away:break
			if entity.has("art") or entity.parcel == yard_parcel:continue
			var distant: bool=WorldLayout.point(entity.door).distance_squared_to(bus_door)>=farthest*0.36
			if entity.archetype in category or (entity.archetype in opposite and (other_count<=2 or (distant and other_away<=1))):continue
			var type: String="eatery" if category==TaskActions.FOOD_TYPES else "garage"
			if float(entity.rect[2])<float(WorldgenScale.WIDTH[type]):continue
			if not _replacement_fits(entity,type,entities,parcels,roads,bus):continue
			if entity.archetype in opposite:
				other_count-=1
				if distant:other_away-=1
			var foot: float=float(entity.rect[1])+float(entity.rect[3])
			entity.archetype=type
			entity.rect[2]=WorldgenScale.WIDTH[type]
			entity.rect[1]=foot-float(WorldgenScale.DEPTH[type]);entity.rect[3]=WorldgenScale.DEPTH[type]
			entity.door=[float(entity.rect[0])+float(entity.rect[2])/2.0+(float(WorldgenScale.DOOR_X[type])-256.0)*float(entity.rect[2])/448.0,foot+48]
			count+=1
			away=away or WorldLayout.point(entity.door).distance_squared_to(bus_door)>=farthest*0.36

static func _replacement_fits(entity: Dictionary, type: String, entities: Array, parcels: Array, roads: Array, bus: Dictionary) -> bool:
	var foot: float=float(entity.rect[1])+float(entity.rect[3])
	var block: Rect2=Rect2(float(entity.rect[0]),foot-float(WorldgenScale.DEPTH[type]),float(WorldgenScale.WIDTH[type]),float(WorldgenScale.DEPTH[type]))
	var visible: Rect2=Rect2(block.position.x,foot-WorldgenScale.visible_height(type),block.size.x,WorldgenScale.visible_height(type))
	for parcel: Dictionary in parcels:
		if parcel.id==entity.parcel:
			var plot: Rect2=WorldLayout.rect(parcel.rect)
			if not plot.grow(-16).encloses(visible) or not plot.grow(-32).encloses(block):return false
		for court: Dictionary in parcel.courtyards:
			if visible.intersects(WorldLayout.rect(court.rect)):return false
	for other: Dictionary in entities:
		if other.id!=entity.id and (block.grow(16).intersects(WorldLayout.rect(other.rect)) or visible.intersects(WorldgenScale.visible_rect(other))):return false
	for road: Array in roads:
		if block.grow(16).intersects(WorldLayout.rect(road)):return false
	return not OpenStreetsV1.intersects_sweep(bus, block, 32) and not block.grow(20).intersects(Rect2(WorldLayout.point(bus.door)-Vector2(128,128),Vector2(256,256)))
