extends SceneTree
var failures: int = 0
var samples: Array = []
var fallbacks: Array = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for size: String in NeighborhoodLayout.SIZES:
		for topology: String in NeighborhoodLayout.TOPOLOGIES:
			var fixed: Dictionary=NeighborhoodLayout._assemble("fallback-probe",size,topology,0,true)
			var fallback_issue: String=NeighborhoodLayout.validate(fixed,false)
			fallbacks.append({"size":size,"topology":topology,"issue":fallback_issue,"id":fixed.id})
			if not fallback_issue.is_empty():failures+=1;printerr("FALLBACK_FAIL ",size," ",topology," ",fallback_issue)
			for seed_index: int in range(4):
				var started: int = Time.get_ticks_usec()
				var key: String = ("world02-fixed-%d"%seed_index).md5_text()
				var data: Dictionary = NeighborhoodLayout.generate(key,size,topology)
				var generation_usec: int = Time.get_ticks_usec()-started
				started=Time.get_ticks_usec()
				var issue: String = NeighborhoodLayout.validate(data,false)
				if not issue.is_empty(): failures+=1;printerr("NEIGHBORHOOD_FAIL ",size," ",topology," ",issue)
				var validation_usec: int=Time.get_ticks_usec()-started
				var types: Array=[]
				var homes: int=0
				for e: Dictionary in data.entities:
					types.append(e.archetype)
					if e.archetype in ["row_house","detached_home","small_apartment"]:homes+=1
				if topology=="residential" and (not types.has("row_house") or not types.has("detached_home") or not types.has("small_apartment") or homes<=data.entities.size()/2):failures+=1
				if topology=="industrial" and (not types.has("warehouse") or not types.has("garage")):failures+=1
				var offer: Dictionary = NeighborhoodActions._make(key,2,0,"supply",topology,size,0)
				var metrics: Dictionary = NeighborhoodActions.route_metrics(offer)
				var cash: int = 0;var food: int = 0;var weapons: int = 0
				for site: Dictionary in offer.sites:
					if site.kind=="cash": cash+=int(site.amount)
					else: food+=int(site.amount)
					weapons+=int(site.weapon)
				if cash!=offer.cash or food!=offer.food or weapons!=offer.weapons:failures+=1
				if not TransactionReceipt.same(data,NeighborhoodLayout.generate(key,size,topology)):failures+=1
				var alternative: float=-1
				if not data.gates.is_empty():
					var layout: StreetLayout=NeighborhoodLayout.resource(data)
					var blocks: Array[Rect2]=layout.blockers()
					var gate: Vector2=WorldLayout.point(data.gates[0])
					blocks.append(Rect2(gate-Vector2(120,20),Vector2(240,40)))
					var nav: FieldNavigation=FieldNavigation.new();nav.configure(blocks,layout.world_bounds)
					var path: PackedVector2Array=nav.path_between(layout.bus_door,WorldLayout.point(data.entities[0].door))
					if path.is_empty():failures+=1;printerr("ALTERNATIVE_FAIL ",size," ",topology)
					else:alternative=NeighborhoodActions._length(path)/125.0
				samples.append({"seed":key,"type":offer.type,"size":size,"topology":topology,"bounds":data.bounds,"entities":data.entities,"alternative_when_first_gate_closed_seconds":alternative,"buildings":data.entities.size(),"sites":offer.sites.size(),"roads":data.roads,"walls":data.barriers,"bus":data.bus.rect,"id":data.id,"paths":metrics.paths,"max_one_way_seconds":metrics.maximum/125.0,"far_roundtrip_and_work_seconds":metrics.maximum/125.0*2+30,"work_seconds":30,"main_return_seconds":metrics.paths.food/125.0,"main_total_seconds":metrics.paths.food/125.0*2+30,"generation_usec":generation_usec,"validation_usec":validation_usec,"fallback":data.fallback})
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--neighborhood-output="):
			var path: String=arg.trim_prefix("--neighborhood-output=")
			assert(path.is_absolute_path() and "/.local/" in path)
			var f: FileAccess=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify({"samples":samples,"fallbacks":fallbacks,"failures":failures},"\t"));f.close()
	print("NEIGHBORHOOD_DATA samples=",samples.size()," fallbacks=",fallbacks.size()," failures=",failures)
	quit(1 if failures else 0)
