extends SceneTree
## Pure geometry and final navigation evidence; never a substitute for native play.
const SHOWCASE_SEEDS: Array[String] = ["worldgen-v1-showcase-01","worldgen-v1-showcase-02","worldgen-v1-showcase-03","worldgen-v1-showcase-04","worldgen-v1-showcase-05","worldgen-v1-showcase-06"]
var checks: int = 0
var failures: int = 0
var cases: Array[Dictionary] = []
var showcase: Array[Dictionary] = []
var output: String = "res://.local/m14-worldgen-01/generation"

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		printerr("WORLDGEN_GENERATION_FAIL "+label)

func _reachable(nav: FieldNavigation, start: Vector2, point: Vector2) -> bool:
	if not nav.is_clear(point):return false
	var path: PackedVector2Array=nav.path_between(start,point)
	return not path.is_empty() and path[-1].distance_to(point)<=14.0

func _connected(graph: Dictionary) -> bool:
	if graph.nodes.is_empty():return false
	var seen: Dictionary={0:true}
	var queue: Array[int]=[0]
	while not queue.is_empty():
		var node: int=queue.pop_back()
		for edge: Array in graph.edges:
			var other: int=int(edge[1]) if int(edge[0])==node else int(edge[0]) if int(edge[1])==node else -1
			if other>=0 and not seen.has(other):
				seen[other]=true;queue.append(other)
	return seen.size()==graph.nodes.size()

func _geometry(layout: Dictionary,label: String) -> void:
	var bounds: Rect2=WorldLayout.rect(layout.bounds)
	var safe: bool=true
	for entity: Dictionary in layout.entities:
		var block: Rect2=WorldLayout.rect(entity.rect)
		safe=safe and bounds.encloses(block) and bounds.has_point(WorldLayout.point(entity.door))
		for road: Array in layout.roads:safe=safe and not block.intersects(WorldLayout.rect(road))
		for other: Dictionary in layout.entities:
			if entity.id!=other.id:safe=safe and not block.grow(12).intersects(WorldLayout.rect(other.rect))
	expect(safe,"actual buildings do not overlap roads, each other or bounds "+label)
	expect(_connected(layout.graph),"actual road centerline graph is connected "+label)
	var street: StreetLayout=WorldgenLayout.resource(layout)
	var sweep_ok: bool=true
	var sweep: Rect2=WorldLayout.rect(layout.bus.sweep)
	for blocker: Rect2 in street.blockers():
		if blocker==street.bus_block:continue
		sweep_ok=sweep_ok and not sweep.intersects(blocker)
	# Sweep the complete 240x80 physical bus body across entry and exit, not only the berth.
	var bus: Rect2=street.bus_block
	for x: int in range(-240,int(bounds.size.x)+241,40):
		var moving: Rect2=Rect2(x,bus.position.y,bus.size.x,bus.size.y)
		for blocker: Rect2 in street.blockers():
			if blocker!=bus:sweep_ok=sweep_ok and not moving.intersects(blocker)
	expect(sweep_ok,"entire bus enters, docks and exits without moving through geometry "+label)

func _case(size: String,topology: String,index: int) -> void:
	var seed: String="worldgen-v1-matrix:%s:%s:%d"%[size,topology,index]
	var label: String="%s/%s/%d"%[size,topology,index]
	var started: int=Time.get_ticks_msec()
	var layout: Dictionary=WorldgenLayout.generate(seed,size,topology)
	expect(not layout.is_empty(),"bounded generation succeeds "+label)
	if layout.is_empty():return
	expect(layout.version==5 and WorldgenLayout.validate(layout,false).is_empty(),"full layout-five canonical identity "+label)
	var fingerprint: String=RecordEncoding.fingerprint(layout)
	expect(fingerprint==RecordEncoding.fingerprint(WorldgenLayout.generate(seed,size,topology)),"same action never rerolls geometry or appearance "+label)
	var restored: Dictionary=RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(layout))).payload
	expect(WorldgenLayout.validate(restored).is_empty() and RecordEncoding.fingerprint(restored)==fingerprint,"exact serialization retains all frozen geometry and variants "+label)
	expect(layout.bounds==ExplorationLayout.SIZES[size].bounds,"small medium large retain their actual exploration bounds "+label)
	_geometry(layout,label)
	var street: StreetLayout=WorldgenLayout.resource(layout)
	var routing: Dictionary=WorldgenLayout._routing(layout)
	var nav: FieldNavigation=routing.nav
	var start: Vector2=street.bus_door
	var routes_ok: bool=true
	var dmax: float=0.0
	for entity: Dictionary in layout.entities:
		var point: Vector2=WorldLayout.point(entity.door)
		routes_ok=routes_ok and _reachable(nav,start,point)
		dmax=maxf(dmax,ExplorationLayout._length(nav.path_between(start,point)))
	for point: Vector2 in street.arrivals+street.enemy_points+[street.rescue_point]:routes_ok=routes_ok and _reachable(nav,start,point)
	for parcel: Dictionary in layout.parcels:
		var reachable: bool=_reachable(nav,start,WorldLayout.point(parcel.entrance))
		if not reachable:printerr("WORLDGEN_YARD_BLOCKED "+label+" "+parcel.id+" "+str(parcel.entrance))
		routes_ok=routes_ok and reachable
	for offset: Vector2 in [Vector2(-48,-48),Vector2(48,-48),Vector2(-48,48),Vector2(48,48)]:routes_ok=routes_ok and _reachable(nav,start,start+offset)
	for object: Dictionary in layout.objects:routes_ok=routes_ok and _reachable(nav,start,WorldLayout.point(object.work_point))
	expect(routes_ok and absf(dmax-float(routing.dmax))<0.0001,"all actual doors, props, yards, rescue, arrivals, gather and spawns reachable after collisions "+label)
	var policy: Dictionary=ExplorationLayout.SIZES[size]
	var vehicles: int=0;var trees: int=0
	for object: Dictionary in layout.objects:
		if object.kind=="vehicle":vehicles+=1
		else:trees+=1
	expect(vehicles==policy.vehicles and trees==policy.fruit_trees,"original bounded interactive object counts "+label)
	var type: String=TaskActions.TYPES[index]
	var budget: Dictionary=TaskActions.CONFIG[type]
	var action_id: String=("worldgen-v1-action:"+seed).sha256_text()
	var content: Dictionary=ExplorationSites.generate(layout,type,int(budget.cash[1]),int(budget.food[1]),int(budget.weapons[1]),action_id)
	expect(not content.is_empty(),"actual final geometry supports task sites and near/middle/far distribution "+label)
	if content.is_empty():
		var fixture: FileAccess=FileAccess.open(output+"/failed-"+size+"-"+topology+"-"+str(index)+".json",FileAccess.WRITE)
		fixture.store_string(JSON.stringify(layout,"\t"));fixture.close()
		var archetypes: Dictionary={}
		for entity: Dictionary in layout.entities:archetypes[entity.archetype]=int(archetypes.get(entity.archetype,0))+1
		printerr("WORLDGEN_SITES_DIAG "+JSON.stringify({"case":label,"archetypes":archetypes,"dmax":dmax,"doors":routing.doors}))
		return
	var counts: Dictionary={"optional_building":0,"vehicle":0,"fruit_tree":0}
	var primary: Dictionary={"cash":0,"food":0,"weapons":0}
	var zones: Dictionary={"near":0,"middle":0,"far":0}
	var site_ok: bool=true
	for site: Dictionary in content.sites:
		if site.source=="primary":
			primary[site.kind]+=int(site.amount);primary.weapons+=int(site.weapon)
			site_ok=site_ok and site.seconds==(12.0 if type=="airdrop" and site.id=="cash" else 30.0)
		else:
			counts[site.source]+=1
			site_ok=site_ok and site.amount==1 and not site.weapon and site.seconds=={"optional_building":18.0,"vehicle":8.0,"fruit_tree":6.0}[site.source]
		var point: Vector2=ExplorationSites.site_point(layout,site)
		var length: float=ExplorationLayout._length(nav.path_between(start,point))
		var metric: Dictionary=content.metrics.routes[site.id]
		var zone: String="near" if length<=dmax*0.35 else "middle" if length<=dmax*0.65 else "far"
		zones[zone]+=1
		site_ok=site_ok and _reachable(nav,start,point) and absf(float(metric.length)-length)<0.0001 and metric.zone==zone and absf(float(metric.base_walk_seconds)-length/125.0)<0.0001
	expect(site_ok and primary.cash==budget.cash[1] and primary.food==budget.food[1] and primary.weapons==budget.weapons[1],"original rewards, work seconds and final real path distances "+label)
	expect(counts.optional_building==policy.optional_buildings and counts.vehicle==policy.vehicles and counts.fruit_tree==policy.fruit_trees and content.sites.size()<=15,"new ordinary buildings never increase interactive rewards "+label)
	expect(zones.near>=1 and zones.middle>=1 and zones.far>=(1 if size=="small" else 2),"near middle far targets retained "+label)
	var row: Dictionary=WorldgenStructure.metrics(layout)
	row.merge({"seed":seed,"size":size,"theme":topology,"fallback":layout.fallback,"attempt":layout.attempt,"dmax":dmax,"sites":content.sites.size(),"zones":zones,"elapsed_ms":Time.get_ticks_msec()-started,"signature":WorldgenStructure.signature(layout)})
	cases.append(row)

func _showcase() -> void:
	var distinct: Dictionary={}
	for seed: String in SHOWCASE_SEEDS:
		var layout: Dictionary=WorldgenLayout.generate(seed,"medium","commercial")
		expect(not layout.is_empty(),"predeclared showcase seed "+seed)
		if layout.is_empty():continue
		var signature: String=WorldgenStructure.signature(layout)
		distinct[signature]=true
		var mirrored: Dictionary=layout.duplicate(true)
		for point: Array in mirrored.graph.nodes:point[0]=-float(point[0])+12345.0;point[1]=float(point[1])+5432.0
		mirrored.seed="not-the-original";mirrored.id="changed"
		for entity: Dictionary in mirrored.entities:entity.variant=99;entity.id="irrelevant"
		expect(WorldgenStructure.signature(mirrored)==signature,"signature excludes seed IDs art translation and reflection "+seed)
		var row: Dictionary=WorldgenStructure.metrics(layout)
		row.merge({"seed":seed,"size":"medium","theme":"commercial","signature":signature,"fallback":layout.fallback,"attempt":layout.attempt,"bus":layout.bus,"bounds":layout.bounds})
		showcase.append(row)
		var file: FileAccess=FileAccess.open(output+"/"+seed+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify(layout,"\t"));file.close()
	expect(distinct.size()>=4,"at least four substantive structures among six predeclared seeds")

func _fallbacks() -> void:
	for size: String in NeighborhoodLayout.SIZES:
		for topology: String in NeighborhoodLayout.TOPOLOGIES:
			var label: String="explicit fallback "+size+"/"+topology
			var layout: Dictionary=WorldgenLayout._assemble("worldgen-v1-fallback-proof",size,topology,0,true)
			expect(not layout.is_empty(),label+" is legal with all props")
			if layout.is_empty():continue
			expect(layout.fallback and layout["size"]==size and layout.topology==topology and layout.version==5 and layout.bounds==ExplorationLayout.SIZES[size].bounds and WorldgenLayout.validate(layout,false).is_empty(),label+" keeps new generator, scale and theme")
			_geometry(layout,label)

func _negatives() -> void:
	var layout: Dictionary=WorldgenLayout.generate("worldgen-v1-negatives","medium","commercial")
	if layout.is_empty():expect(false,"negative fixture exists");return
	for mutation: String in ["missing","extra","version","graph","parcels","variant","road","bus"]:
		var changed: Dictionary=layout.duplicate(true)
		match mutation:
			"missing":changed.erase("parcels")
			"extra":changed.bonus=1
			"version":changed.version=4
			"graph":changed.graph.edges.pop_back()
			"parcels":changed.parcels[0].kind="free_rewards"
			"variant":changed.entities[0].variant=99
			"road":changed.roads[0][2]-=64
			"bus":changed.bus.sweep[1]+=32
		expect(not WorldgenLayout.validate(changed).is_empty(),"full canonical identity rejects "+mutation)
	expect(WorldgenLayout.generate("seed","tiny","commercial").is_empty() and WorldgenLayout.generate("seed","small","unknown").is_empty(),"unknown size or theme is rejected")

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2);return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--worldgen-output="):output=arg.trim_prefix("--worldgen-output=")
	if not ProjectSettings.globalize_path(output).begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	_showcase()
	for size: String in NeighborhoodLayout.SIZES:
		for topology: String in NeighborhoodLayout.TOPOLOGIES:
			for index: int in range(4):_case(size,topology,index)
	_fallbacks()
	_negatives()
	expect(cases.size()==36,"all thirty-six matrix cases complete")
	var report: Dictionary={"suite":"worldgen_generation","checks":checks,"failures":failures,"scope":"PURE_GENERATION_AND_POST_PROP_NAVIGATION_NOT_RUNTIME_SCREENSHOTS","cases":cases,"showcase":showcase}
	var file: FileAccess=FileAccess.open(output+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report))
	quit(0 if failures==0 else 1)
