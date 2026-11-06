class_name WorldgenStructure
extends RefCounted
## The certificate describes actual road connections, independent of seed, art and coordinates.

static func graph(segments: Array) -> Dictionary:
	var nodes: Array = []
	var edges: Array = []
	var lookup: Dictionary = {}
	for line: Array in segments:
		var vertical: bool = line[0]==line[2]
		var points: Array[Vector2] = [Vector2(line[0],line[1]),Vector2(line[2],line[3])]
		for other: Array in segments:
			if vertical==(other[0]==other[2]):continue
			var point: Vector2 = Vector2(line[0],other[1]) if vertical else Vector2(other[0],line[1])
			if point.x>=float(line[0]) and point.x<=float(line[2]) and point.y>=float(line[1]) and point.y<=float(line[3]) and point.x>=float(other[0]) and point.x<=float(other[2]) and point.y>=float(other[1]) and point.y<=float(other[3]) and point not in points:
				points.append(point)
		points.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.y<b.y if vertical else a.x<b.x)
		for index: int in range(points.size()-1):
			var first: int = _node(points[index],nodes,lookup)
			var second: int = _node(points[index+1],nodes,lookup)
			edges.append([first,second,int(line[4])])
	return {"nodes":nodes,"edges":edges}

static func _node(point: Vector2, nodes: Array, lookup: Dictionary) -> int:
	var key: String = "%d:%d"%[int(point.x),int(point.y)]
	if not lookup.has(key):
		lookup[key]=nodes.size()
		nodes.append([point.x,point.y])
	return int(lookup[key])

static func metrics(layout: Dictionary) -> Dictionary:
	var graph_data: Dictionary = layout.graph
	var degree: Array[int] = []
	degree.resize(graph_data.nodes.size());degree.fill(0)
	for edge: Array in graph_data.edges:
		degree[int(edge[0])]+=1;degree[int(edge[1])]+=1
	var ends: int=0;var turns: int=0;var junctions: int=0;var crosses: int=0
	for value: int in degree:
		if value==1:ends+=1
		if value==2:turns+=1
		if value>=3:junctions+=1
		if value>=4:crosses+=1
	var kinds: Dictionary = {}
	var combinations: Array[String] = []
	var entrances: int = 0
	var parcel_details: Array = []
	var courtyard_kinds: Dictionary = {}
	for parcel: Dictionary in layout.parcels:
		kinds[parcel.kind]=int(kinds.get(parcel.kind,0))+1
		var ports: int = 0
		for active: bool in parcel.road_edges:
			if active:ports+=1
		var uses_signature: Array[String]=[]
		for court: Dictionary in parcel.courtyards:uses_signature.append(court.kind)
		uses_signature.sort()
		combinations.append("%s:%d:%d:%d:%s"%[parcel.kind,parcel.buildings.size(),ports,int(parcel.dead_end),"/".join(uses_signature)])
		if not parcel.entrance.is_empty():entrances+=1
		var uses: Dictionary={}
		for court: Dictionary in parcel.courtyards:
			uses[court.kind]=int(uses.get(court.kind,0))+1
			courtyard_kinds[court.kind]=int(courtyard_kinds.get(court.kind,0))+1
		var rows: Dictionary={}
		for entity: Dictionary in layout.entities:
			if entity.parcel!=parcel.id:continue
			var foot: float=float(entity.rect[1])+float(entity.rect[3])-float(parcel.rect[1])
			var key: String=str(foot)
			if not rows.has(key):rows[key]={"foot":foot,"buildings":0,"visible_height":0.0}
			rows[key].buildings+=1
			rows[key].visible_height=maxf(float(rows[key].visible_height),WorldgenScale.visible_height(entity.archetype,int(entity.variant)))
		parcel_details.append({"id":parcel.id,"dimensions":[parcel.rect[2],parcel.rect[3]],"kind":parcel.kind,"buildings":parcel.buildings.size(),"frontage":parcel.frontage.duplicate(),"courtyards":uses,"walks":parcel.walks.size(),"rows":rows.values()})
	combinations.sort()
	return {"buildings":layout.entities.size(),"blocks":layout.parcels.size(),"junctions":junctions,"crossroads":crosses,"degree_two":turns,"ends":ends,"loops":graph_data.edges.size()-graph_data.nodes.size()+1,"parcel_kinds":kinds,"parcel_combinations":combinations,"entrances":entrances,"parcel_details":parcel_details,"courtyard_kinds":courtyard_kinds}

static func signature(layout: Dictionary) -> String:
	var graph_data: Dictionary = layout.graph
	var neighbors: Array = []
	for node: Array in graph_data.nodes:neighbors.append([])
	for edge: Array in graph_data.edges:
		neighbors[int(edge[0])].append(int(edge[1]));neighbors[int(edge[1])].append(int(edge[0]))
	var colors: Array[String] = []
	for group: Array in neighbors:colors.append(str(group.size()))
	# Refinement encodes connection neighborhoods, not coordinates or source IDs.
	for round_index: int in range(graph_data.nodes.size()):
		var next: Array[String] = []
		for index: int in range(neighbors.size()):
			var adjacent: Array[String] = []
			for other: int in neighbors[index]:adjacent.append(colors[other])
			adjacent.sort()
			next.append((colors[index]+":"+"|".join(adjacent)).sha256_text())
		colors=next
	colors.sort()
	var summary: Dictionary = metrics(layout)
	# All properties are counts or combinations; translations, reflections, texture and micro-jitter disappear.
	return RecordEncoding.fingerprint({"connections":colors,"parcels":summary.parcel_combinations,"loops":summary.loops,"buildings":summary.buildings})
