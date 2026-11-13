extends SceneTree
## Real FieldActor path motion and swept foot contacts, plus live Expedition regression.

var checks: int = 0
var failures: int = 0
var results: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _actor(id: int, point: Vector2, enemy: bool = false) -> FieldActor:
	var actor: FieldActor = FieldActor.new()
	actor.actor_id = id
	actor.member_id = 0 if enemy else id
	actor.is_enemy = enemy
	actor.speed = 34.0 if enemy else 125.0
	actor.position = point
	root.add_child(actor)
	return actor

func _minimum(actors: Array[FieldActor]) -> float:
	var distance: float = INF
	for i: int in range(actors.size()):
		for j: int in range(i+1,actors.size()):
			if FieldContacts.participates(actors[i]) and FieldContacts.participates(actors[j]): distance = minf(distance,actors[i].position.distance_to(actors[j].position))
	return distance

func _clear(actors: Array[FieldActor]) -> void:
	for actor: FieldActor in actors: actor.free()
	actors.clear()

func _expect(value: bool, label: String) -> void:
	checks += 1
	results.append({"pass":value,"label":label})
	if not value:
		failures += 1
		print("CONTACT_FAIL ",label)

func _run() -> void:
	_corner_body_truncation()
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure([])
	for octant: int in [0,2,4,6]:
		var direction: Vector2 = Vector2.RIGHT.rotated(octant*PI/4.0)
		var center: Vector2 = Vector2(1000,900)
		var actors: Array[FieldActor] = [_actor(1,center-direction*60),_actor(2,center+direction*60,true)]
		actors[0].command_path(PackedVector2Array([actors[0].position,center+direction*90]))
		actors[1].command_path(PackedVector2Array([actors[1].position,center-direction*90]))
		var minimum: float = INF
		for tick: int in range(240):
			FieldContacts.move(actors,actors,nav,1.0/60.0,true)
			minimum = minf(minimum,_minimum(actors))
		_expect(minimum>=19.99,"cardinal swept crossover keeps20px "+str(octant))
		_expect((actors[0].position-center).dot(direction)>30,"survivor passes around rather than through "+str(octant))
		_clear(actors)
	var pile: Array[FieldActor] = []
	for id: int in range(1,9): pile.append(_actor(id,Vector2(1000,900),id>4))
	var maximum: float = 0.0
	for tick: int in range(240):
		var previous: Array[Vector2] = []
		for actor: FieldActor in pile: previous.append(actor.position)
		FieldContacts.move(pile,pile,nav,1.0/60.0,true)
		for i: int in range(pile.size()): maximum = maxf(maximum,previous[i].distance_to(pile[i].position))
	_expect(_minimum(pile)>=19.99,"eight exact-coincident bodies recover without persistent overlap")
	print("CONTACT_PILE minimum=",_minimum(pile)," maximum_step=",maximum)
	_expect(maximum<=FieldContacts.RECOVERY_SPEED/60.0+0.001,"coincident recovery speed capped peractor percall")
	var positions: Array[Vector2] = []
	for actor: FieldActor in pile: positions.append(actor.position)
	_clear(pile)
	for id: int in range(8,0,-1): pile.append(_actor(id,Vector2(1000,900),id>4))
	for tick: int in range(240): FieldContacts.move(pile,pile,nav,1.0/60.0,true)
	var deterministic: bool = true
	for i: int in range(pile.size()): deterministic = deterministic and pile[i].position==positions[7-i]
	_expect(deterministic,"exact pile outcome independent of insertion order")
	_clear(pile)
	var fast: Array[FieldActor] = [_actor(1,Vector2(900,900)),_actor(2,Vector2(960,900),true)]
	fast[0].command_path(PackedVector2Array([fast[0].position,Vector2(1100,900)]))
	fast[1].command_path(PackedVector2Array([fast[1].position,Vector2(800,900)]))
	var large: Dictionary = FieldContacts.move(fast,fast,nav,1.0,true)
	_expect(_minimum(fast)>=19.99 and large.minimum_distance>=19.99 and large.substeps<=FieldContacts.MAX_STEPS,"large delta is swept in bounded steps without crossing between samples")
	_clear(fast)
	var corridor: FieldNavigation = FieldNavigation.new()
	corridor.configure([Rect2(500,500,100,200),Rect2(652,500,100,200)])
	var team: Array[FieldActor] = [_actor(1,Vector2(632,530)),_actor(2,Vector2(632,670))]
	team[0].command_path(corridor.path_between(team[0].position,Vector2(632,650)))
	team[1].command_path(corridor.path_between(team[1].position,Vector2(632,550)))
	var goals: Array[Vector2] = [team[0].path[-1],team[1].path[-1]]
	var legal: bool = true
	for tick: int in range(900):
		FieldContacts.move(team,team,corridor,1.0/60.0,true)
		for actor: FieldActor in team: legal = legal and corridor.is_clear(actor.position)
	_expect(legal and _minimum(team)>=19.99,"narrow static corridor remains legal and separated")
	_expect(team[0].position.distance_to(goals[0])<3.0 and team[1].position.distance_to(goals[1])<3.0,"opposing teammates reach actual routable goals instead of deadlock")
	print("CONTACT_CORRIDOR ",team[0].position," ",team[1].position)
	_clear(team)
	var excluded: Array[FieldActor] = [_actor(1,Vector2(1000,900)),_actor(2,Vector2(1001,900)),_actor(3,Vector2(1002,900)),_actor(4,Vector2(1003,900))]
	excluded[1].hide()
	excluded[2].activity = FieldActor.Activity.SEARCHING
	excluded[3].activity = FieldActor.Activity.DOWN
	excluded[0].command_path(PackedVector2Array([excluded[0].position,Vector2(1100,900)]))
	for tick: int in range(90): FieldContacts.move(excluded,excluded,nav,1.0/60.0,true)
	_expect(excluded[0].position.x>=1099.0,"hidden searching and down actors do not occupy feet")
	_expect(excluded[1].position==Vector2(1001,900) and excluded[2].position==Vector2(1002,900) and excluded[3].position==Vector2(1003,900),"inactive actors are never displaced")
	_clear(excluded)
	var wall: FieldNavigation = FieldNavigation.new()
	wall.configure([Rect2(960,840,80,120)])
	var walker: Array[FieldActor] = [_actor(1,Vector2(900,900))]
	walker[0].command_path(PackedVector2Array([walker[0].position,Vector2(1100,900)]))
	var wall_legal: bool = true
	for tick: int in range(240):
		FieldContacts.move(walker,walker,wall,1.0/60.0,true)
		wall_legal = wall_legal and wall.is_clear(walker[0].position)
	_expect(wall_legal,"even a direct invalid path cannot move through a static wall")
	_clear(walker)
	_corner_cases()
	_free_path_cases()
	await _world_cases()
	await _world_crossings()
	print("BH_CONTACT_SEPARATION checks=",checks," failures=",failures)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--contact-report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--contact-report="),FileAccess.WRITE)
			file.store_string(JSON.stringify({"checks":results,"failures":failures},"",true,true))
	quit(0 if failures==0 else 1)


func _free_path_cases() -> void:
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure([])
	for enemy: bool in [false,true]:
		var actor: FieldActor = _actor(1,Vector2(80,900),enemy)
		var actors: Array[FieldActor] = [actor]
		var route: PackedVector2Array = PackedVector2Array()
		for x: int in range(80,1681,16): route.append(Vector2(x,900))
		actor.command_path(route)
		var uniform: bool = true
		var frames: int = ceili(1600.0/actor.speed*60.0)+1
		for tick: int in range(frames):
			var previous: Vector2 = actor.position
			FieldContacts.move(actors,actors,nav,1.0/60.0)
			if actor.activity==FieldActor.Activity.MOVING: uniform = uniform and absf(previous.distance_to(actor.position)-actor.speed/60.0)<0.001
		_expect(actor.position.distance_to(Vector2(1680,900))<0.01,"unoccupied1600px grid route preserves declared travel time, enemy="+str(enemy))
		_expect(uniform,"waypoints do not cause short steps or lower effective speed, enemy="+str(enemy))
		_clear(actors)


func _corner_cases() -> void:
	for boundary: bool in [false,true]:
		var nav: FieldNavigation = FieldNavigation.new()
		var blockers: Array[Rect2] = []
		if not boundary: blockers.assign([Rect2(500,500,200,80),Rect2(500,580,80,200)])
		nav.configure(blockers)
		var point: Vector2 = FieldNavigation.BOUNDS.position+Vector2(11,11) if boundary else Vector2(610,610)
		var actors: Array[FieldActor] = []
		for id: int in range(1,9): actors.append(_actor(id,point,id>4))
		var legal: bool = true
		var maximum: float = 0.0
		for tick: int in range(600):
			var starts: Array[Vector2] = []
			for actor: FieldActor in actors: starts.append(actor.position)
			FieldContacts.move(actors,actors,nav,1.0/60.0,true)
			for i: int in range(actors.size()):
				legal = legal and nav.is_clear(actors[i].position)
				maximum = maxf(maximum,starts[i].distance_to(actors[i].position))
		_expect(legal and maximum<=80.0/60.0+0.001,"corner recovery stays static-safe and bounded, map boundary="+str(boundary))
		_expect(_minimum(actors)>=19.99,"corner eight-person pile actually separates, map boundary="+str(boundary))
		_clear(actors)


func _world_cases() -> void:
	for kind: String in [EnemyRules.NORMAL,EnemyRules.RUSH,EnemyRules.HEAVY]:
		var world: Expedition = Expedition.new()
		root.add_child(world)
		world.set_physics_process(false)
		var hero: FieldActor = world.survivors[0]
		hero.position = Vector2(781,907)
		hero.clear_order()
		hero.cooldown = 999.0
		world.survivors[1].activity = FieldActor.Activity.SEARCHING
		world.survivors[1].hide()
		var enemy: FieldActor = world._make_actor(true,9001,hero.position+Vector2(-80,0),{},kind)
		world.enemies.append(enemy)
		var partner: FieldActor = world.survivors[1]
		partner.show()
		partner.activity = FieldActor.Activity.IDLE
		partner.position = hero.position
		_expect(world._nearest_target(enemy,[partner,hero],INF)==hero,"equal-distance target uses stable ID rather than insertion order "+kind)
		partner.activity = FieldActor.Activity.SEARCHING
		partner.hide()
		var minimum: float = INF
		for tick: int in range(480):
			world.step(1.0/60.0)
			minimum = minf(minimum,hero.position.distance_to(enemy.position))
		_expect(minimum>=19.99,"real pursuit stays separated "+kind)
		_expect(hero.health<200 and enemy.cooldown<=world.tuning.enemy_interval,"original enemy type still reaches and attacks "+kind)
		world.toggle_pause()
		var paused: Vector2 = enemy.position
		var clock: float = world.elapsed
		var cooldown: float = enemy.cooldown
		world.step(1.0)
		_expect(enemy.position==paused and world.elapsed==clock and enemy.cooldown==cooldown,"contact pause freezes positions and timers "+kind)
		world.queue_free()
		await process_frame


func _world_crossings() -> void:
	for direction: Vector2 in [Vector2.LEFT,Vector2.UP,Vector2.RIGHT,Vector2.DOWN]:
		var world: Expedition = Expedition.new()
		root.add_child(world)
		world.set_physics_process(false)
		var center: Vector2 = Vector2(781,907)
		var hero: FieldActor = world.survivors[0]
		hero.position = center
		hero.clear_order()
		hero.cooldown = 999.0
		world.survivors[1].activity = FieldActor.Activity.SEARCHING
		world.survivors[1].hide()
		var enemy: FieldActor = world._make_actor(true,9001,center+direction*84.0,{},EnemyRules.NORMAL)
		world.enemies.append(enemy)
		for tick: int in range(126): world.step(1.0/60.0)
		hero.command_path(world.navigation.path_between(hero.position,center+direction*96.0))
		var minimum: float = INF
		var progress: float = -INF
		var legal: bool = true
		for tick: int in range(60):
			world.step(1.0/60.0)
			minimum = minf(minimum,hero.position.distance_to(enemy.position))
			progress = maxf(progress,(hero.position-center).dot(direction))
			legal = legal and world.navigation.is_clear(hero.position) and world.navigation.is_clear(enemy.position)
		_expect(minimum>=19.99 and legal,"real World active crossing stays separated and static-safe "+str(direction))
		_expect(progress>40.0,"real World passes a holding pursuer instead of orbiting an occupied waypoint "+str(direction))
		world.queue_free()
		await process_frame


func _corner_body_truncation() -> void:
	# R1's real garage corner: a body-truncated step must not strand a mover
	# inside the static margin even when the original 4-unit sampling missed it.
	var nav: FieldNavigation=FieldNavigation.new()
	nav.configure([Rect2(1016,1272,264,96)],Rect2(0,0,3584,2688))
	var actors: Array[FieldActor]=[_actor(1,Vector2(1297,1386.5)),_actor(2,Vector2(1312,1371.5))]
	var wish: Vector2=Vector2(2,-2)
	var body_limit: float=FieldContacts._sweep(actors[0].position-actors[1].position,wish)
	_expect(nav._segment_is_clear(actors[0].position,actors[0].position+wish) and not nav.is_clear(actors[0].position+wish*body_limit),"fixture exposes a body-truncated sampled-clear step inside a static corner")
	var accepted: Vector2=FieldContacts._limited(actors[0],wish,actors,nav)
	var endpoint: Vector2=actors[0].position+accepted
	_expect(nav.is_clear(endpoint) and nav._segment_is_clear(actors[0].position,endpoint) and endpoint.distance_to(actors[1].position)>=FieldContacts.DISTANCE and accepted.length()<=wish.length()*body_limit,"final contact displacement keeps static clearance and the original body bound")
	_clear(actors)
