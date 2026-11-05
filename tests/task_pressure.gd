extends "res://tests/task_flow.gd"
## Late pressure still uses ordinary infected and is authenticated by the same world snapshot.
func _journey() -> void:
	await _tap(app._home_button); await _tap(app._new_game_confirmation.get_ok_button())
	await _menu(); await _start("airdrop")
	var world: Expedition = app.expedition
	await _advance(world,func() -> bool:return world.elapsed>=130)
	world.request_search(&"cash")
	await _advance(world,func() -> bool:return world.search_site(&"cash").progress>=3)
	_check(world.task_event.started and world.task_event.resolutions.size()==2,"late event has exactly two bounded attempt facts")
	for resolution: Dictionary in world.task_event.resolutions:
		for actor: FieldActor in world.enemies:
			if actor.actor_id==resolution.enemy_id: _check(actor.enemy_behavior.kind==EnemyRules.NORMAL,"late event uses existing ordinary enemy type")
	app.open_pause_menu(); await _hold(3)
	var snapshot: Dictionary = SortieSnapshot.capture(world)
	var receipt: Dictionary = app.progress_session._transaction.recover().receipt
	_check(SortieSnapshot.problem(snapshot,receipt).is_empty(),"late forced ordinary identities authenticate without changing natural enemy selection")
	_write("late-pressure.json",{"event":world.task_event,"stage":int(world.threat.stage),"snapshot":RecordEncoding.stringify(snapshot)})
