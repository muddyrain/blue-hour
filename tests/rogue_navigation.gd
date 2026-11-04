extends SceneTree
## Six layouts, real four-body path/occupancy solve; no campaign state.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var failures: int=0
	for bone: String in RogueLayout.BONES:
		for variant: int in range(2):
			var data: Dictionary=RogueLayout.generate("occupancy-%d"%variant,bone)
			var layout: StreetLayout=RogueLayout.resource(data)
			var nav: FieldNavigation=FieldNavigation.new();nav.configure(layout.blockers())
			var actors: Array[FieldActor]=[]
			for i: int in range(4):
				var actor: FieldActor=FieldActor.new();actor.member_id=i+1;actor.actor_id=i;actor.position=layout.arrivals[i];actor.speed=125
				root.add_child(actor);actors.append(actor)
			var okay: bool=true
			var minimum: float=INF
			for destination: Vector2 in [layout.cash_door+Vector2(0,100),layout.bus_door]:
				for i: int in range(4): actors[i].command_path(nav.path_between(actors[i].position,destination+Vector2.ONE*((i-1.5)*35.2)))
				for tick: int in range(1800):
					FieldContacts.move(actors,actors,nav,1.0/30.0,true)
					for i: int in range(4):
						okay=okay and nav.is_clear(actors[i].position)
						for k: int in range(i):minimum=minf(minimum,actors[i].position.distance_to(actors[k].position))
					if actors.all(func(v: FieldActor) -> bool:return v.activity!=FieldActor.Activity.MOVING):break
				okay=okay and actors.all(func(v: FieldActor) -> bool:return v.position.distance_to(destination)<=88)
			okay=okay and minimum>=FieldContacts.DISTANCE-0.01
			print("ROGUE_NAV ",bone," ",variant," pass=",okay," minimum=",minimum)
			if not okay:failures+=1
			for actor: FieldActor in actors:actor.free()
	print("ROGUE_NAV_SUMMARY cases=6 failures=",failures)
	quit(1 if failures else 0)
