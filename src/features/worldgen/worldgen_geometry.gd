class_name WorldgenGeometry
extends RefCounted
## Roads partition the city before frontage, yards and individual buildings are placed.
const DIMENSIONS: Dictionary = {"small":[2560,1920],"medium":[3584,2688],"large":[4608,3456]}
const MIN_WIDTH: int = 736
const MIN_HEIGHT: int = 464

static func assemble(seed: String, size: String, topology: String, attempt: int, fallback: bool) -> Dictionary:
	var random: RandomNumberGenerator = RogueLayout.rng("worldgen-v1:" + ((size + ":" + topology + ":fallback") if fallback else seed + ":" + str(attempt)))
	var dimensions: Array = DIMENSIONS[size]
	var width: int = int(dimensions[0])
	var height: int = int(dimensions[1])
	var rank: int = NeighborhoodLayout.SIZES.find(size)
	var main_y: int = int(round(float(height) * random.randf_range(0.40,0.61) / 32.0)) * 32
	var segments: Array = [[0,main_y+112,width,main_y+112,224]]
	var leaves: Array = [
		{"rect":[0,0,width,main_y],"edges":[false,true,false,false]},
		{"rect":[0,main_y+224,width,height-main_y-224],"edges":[true,false,false,false]}
	]
	var target: int = [5,8,11][rank] + random.randi_range(-1,1)
	# Each cut joins at least one existing road edge. Both children retain that edge.
	for step: int in range(18):
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
			segments.append([x,mini(from_y,to_y),x,maxi(from_y,to_y),96])
			segments.append([x-160,to_y,x,to_y,96])
			kind = "service" if topology == "industrial" else "courtyard"
		parcels.append({"id":"p%02d"%index,"rect":leaf.rect.duplicate(),"kind":kind,"road_edges":leaf.edges.duplicate(),"buildings":[],"entrance":[],"dead_end":stub})
	roads = _roads(segments,width,height)
	var stop_x: int = _stop_x(width,main_y,roads,random)
	var foot_y: int = main_y+176
	var door: Array = [stop_x+190,main_y+272]
	var bus: Dictionary = {"rect":[stop_x,foot_y-80,240,80],"door":door,"passenger_door":[stop_x+190,foot_y-16],"entry":[-160,foot_y],"exit":[width+160,foot_y],"sweep":[0,main_y+76,width,120],"facing":"right"}
	var entities: Array = []
	for parcel: Dictionary in parcels:
		_populate(parcel,topology,random,entities,roads,bus)
	# Food and equipment are actual parcels, not rewards granted to every building.
	_ensure_categories(entities,WorldLayout.point(door))
	var rescue: Array = entities[0].door.duplicate() if not entities.is_empty() else [64,64]
	var furthest: float = 0.0
	for entity: Dictionary in entities:
		var distance: float = WorldLayout.point(entity.door).distance_squared_to(WorldLayout.point(door))
		if distance > furthest:
			furthest=distance
			rescue=entity.door.duplicate()
	var walls: Dictionary = _walls(parcels,entities,roads,bus)
	var arrivals: Array = [[door[0]-48,door[1]+24],[door[0],door[1]+24],[door[0]+48,door[1]+24],[door[0],door[1]+56]]
	var data: Dictionary = {"version":5,"seed":seed,"size":size,"topology":topology,"attempt":attempt,"fallback":fallback,"bounds":[0,0,width,height],"entities":entities,"roads":roads,"barriers":walls.barriers,"gates":walls.gates,"bus":bus,"arrivals":arrivals,"enemy_points":[[24,main_y+24],[width-24,main_y+24]],"rescue":rescue,"objects":[],"parcels":parcels,"graph":WorldgenStructure.graph(segments)}
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
		if vertical and segment[1]==segment[3] and absi(int(segment[1])-edge)<=112 and along>=int(segment[0]) and along<=int(segment[2]):return int(segment[1])
		if not vertical and segment[0]==segment[2] and absi(int(segment[0])-edge)<=112 and along>=int(segment[1]) and along<=int(segment[3]):return int(segment[0])
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
		var berth: Rect2 = Rect2(x-48,main_y,336,224)
		var clear: bool = true
		for value: Array in roads:
			var road: Rect2 = WorldLayout.rect(value)
			if road.size.y > road.size.x and road.intersects(berth): clear=false
		if clear: candidates.append(x)
	return candidates[random.randi_range(0,candidates.size()-1)] if not candidates.is_empty() else 176

static func _populate(parcel: Dictionary, topology: String, random: RandomNumberGenerator, entities: Array, roads: Array, bus: Dictionary) -> void:
	var box: Rect2 = WorldLayout.rect(parcel.rect)
	var pools: Dictionary = {
		"shopfront":["convenience_store","eatery","supermarket","garage","convenience_store"],
		"courtyard":["row_house","small_apartment","eatery"] if topology=="commercial" else ["detached_home","row_house","small_apartment"],
		"parking":["convenience_store","garage","supermarket"] if topology=="commercial" else ["warehouse","garage","convenience_store"],
		"garden":["detached_home","row_house"],"homes":["detached_home","row_house","small_apartment"],
		"loading":["warehouse","warehouse","garage"],"service":["warehouse","garage","convenience_store"]}
	var pool: Array = pools[parcel.kind]
	var gap: float = {"shopfront":24.0,"courtyard":48.0,"parking":64.0,"garden":88.0,"homes":40.0,"loading":56.0,"service":48.0}[parcel.kind]
	var front: Array[String] = []
	var available: float = box.size.x-112
	var wanted: int = 2 if box.size.x < 1000 else 3
	if topology=="industrial" or parcel.kind in ["garden","parking"]: wanted=2
	for index: int in range(wanted):
		var choices: Array = pool.filter(func(type: String) -> bool: return float(WorldgenScale.WIDTH[type]) <= available-(wanted-index-1)*(256+gap))
		if choices.is_empty(): break
		var type: String=choices[random.randi_range(0,choices.size()-1)]
		if index>0 and type==front[-1] and choices.size()>1:type=choices[(choices.find(type)+1)%choices.size()]
		front.append(type)
		available-=float(WorldgenScale.WIDTH[type])+gap
	if front.is_empty():front.append("garage" if topology=="industrial" else "row_house" if topology=="residential" else "convenience_store")
	var frontage: float = 0.0
	for type: String in front: frontage+=float(WorldgenScale.WIDTH[type])
	frontage+=gap*(front.size()-1)
	var left: float = box.position.x+maxf(56,(box.size.x-frontage)*random.randf_range(0.35,0.65))
	var setback: float = 200 if parcel.kind=="parking" else 168 if parcel.kind=="loading" else (80 if parcel.road_edges[1] else 120) if parcel.kind=="garden" else (64 if parcel.road_edges[1] else 104)
	var foot: float = box.end.y-setback
	for type: String in front:
		_add_building(type,left,foot,parcel,entities,roads,bus,random)
		left+=float(WorldgenScale.WIDTH[type])+gap
	# A second, staggered frontage faces an actual shared courtyard; it is not a second grid row.
	if box.size.y >= (800 if parcel.kind in ["loading","parking"] else 520) and parcel.buildings.size()<4:
		var type: String = "garage" if topology=="industrial" else "detached_home" if topology=="residential" else "small_apartment"
		if parcel.kind in ["parking","service"]:type="convenience_store"
		var back_x: float = box.position.x+80+maxf(0,box.size.x-float(WorldgenScale.WIDTH[type])-176)*random.randf_range(0.0,1.0)
		_add_building(type,back_x,foot-272,parcel,entities,roads,bus,random)
	# Store the court access as geometry, regardless of the façade orientation.
	var entrance: Vector2 = Vector2(box.get_center().x,box.end.y-32) if parcel.road_edges[1] else Vector2(box.get_center().x,box.position.y+32) if parcel.road_edges[0] else Vector2(box.position.x+32,box.get_center().y) if parcel.road_edges[2] else Vector2(box.end.x-32,box.get_center().y)
	parcel.entrance=[entrance.x,entrance.y]

static func _add_building(type: String, x: float, foot: float, parcel: Dictionary, entities: Array, roads: Array, bus: Dictionary, random: RandomNumberGenerator) -> void:
	var width: float = float(WorldgenScale.WIDTH[type]);var depth: float=float(WorldgenScale.DEPTH[type])
	var block: Rect2 = Rect2(x,foot-depth,width,depth)
	var plot: Rect2 = WorldLayout.rect(parcel.rect)
	if not plot.grow(-32).encloses(block):return
	# Keep all boarding/arrival positions and the full sweep free before props are added.
	if block.grow(32).intersects(WorldLayout.rect(bus.sweep)) or block.grow(20).intersects(Rect2(WorldLayout.point(bus.door)-Vector2(128,128),Vector2(256,256))):return
	for value: Array in roads:
		if block.grow(16).intersects(WorldLayout.rect(value)):return
	for entity: Dictionary in entities:
		if block.grow(16).intersects(WorldLayout.rect(entity.rect)):return
	var id: String = "b%02d"%entities.size()
	var door_x: float = x+width/2.0+(float(WorldgenScale.DOOR_X[type])-256.0)*width/448.0
	entities.append({"id":id,"archetype":type,"rect":[x,foot-depth,width,depth],"door":[door_x,foot+48],"variant":random.randi_range(0,2),"parcel":parcel.id})
	parcel.buildings.append(id)

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
		for other: Dictionary in parcels:clear=clear and not wall.grow(44).has_point(WorldLayout.point(other.entrance))
		for road: Array in roads:clear=clear and not wall.grow(24).intersects(WorldLayout.rect(road))
		clear=clear and not wall.grow(40).intersects(WorldLayout.rect(bus.sweep)) and not Rect2(WorldLayout.point(bus.door)-Vector2(160,160),Vector2(320,320)).intersects(wall)
		if clear:
			barriers.append([wall.position.x,wall.position.y,wall.size.x,wall.size.y]);gates.append([gate.x,gate.y])
	return {"barriers":barriers,"gates":gates}

static func _ensure_categories(entities: Array, bus_door: Vector2) -> void:
	# Geometric distance is only a placement preference. The final navigation certificate
	# must still prove a non-near real food/workshop entrance after every prop is added.
	var farthest: float=0.0
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
			var distant: bool=WorldLayout.point(entity.door).distance_squared_to(bus_door)>=farthest*0.36
			if entity.archetype in category or (entity.archetype in opposite and (other_count<=2 or (distant and other_away<=1))):continue
			var type: String="eatery" if category==TaskActions.FOOD_TYPES else "garage"
			if float(entity.rect[2])<float(WorldgenScale.WIDTH[type]):continue
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
