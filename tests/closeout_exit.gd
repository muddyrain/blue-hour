extends "res://tests/playable_flow.gd"
## Close during departure and new PID recovery of the exact RESULT_READY record.
func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _tap(app.camp_scene.hotspots[&"bus"])
	var slot: int = 0
	for i: int in range(3):
		if app.mission_select.daily_offers[i].layout["size"]=="large": slot=i
	await _tap(app.mission_select.choices[slot])
	var world: Expedition = app.expedition
	world.set_physics_process(false); world.set_process(false)
	await _advance(world,func() -> bool: return not world.bus_view.running())
	var target: StringName=&"food" if world.supply.food_reward>0 else &"cash"
	world.request_search(target)
	await _advance(world,func() -> bool: return world.search_site(target).searched)
	await _advance(world,func() -> bool: return world.elapsed>=world.tuning.bus_ready_seconds)
	world.request_bus_action()
	await _advance(world,func() -> bool: return world.phase==Expedition.Phase.BOARDING)
	_check(world.bus_view.stage=="exploring","not gathered cannot depart")
	world.request_bus_gather()
	await _advance(world,func() -> bool: return world.phase==Expedition.Phase.FINISHED)
	var frozen: Dictionary = app.progress_session.inspect()
	_check(frozen.receipt.phase=="RESULT_READY" and world.bus_view.stage=="embarking","durable result precedes visible boarding")
	world.step(1.0)
	_check(world.bus_view.stage=="departing","actual boarding reaches departure")
	world.step(0.4)
	_check(world._bus_sprite.position.x>world.layout.bus_foot().x,"actual world bus position advances")
	_check(app.progress_session.inspect().hash==frozen.hash,"departure never modifies frozen receipt")
	_write("oracle.json",{"encoded":RecordEncoding.stringify(frozen.receipt),"hash":frozen.hash,"camp":app.camp_snapshot(),"pid":OS.get_process_id()})

func _resume() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/oracle.json")))
	_check(int(expected.pid)!=OS.get_process_id(),"new PID after closing during departure")
	var current: Dictionary = app.progress_session.inspect()
	_check(current.hash==expected.hash and TransactionReceipt.same(current.receipt,RecordEncoding.unpack(JSON.parse_string(expected.encoded)).payload),"exact same frozen result before explicit continue")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
	_check(app.expedition==null and app.phase==app.Phase.TITLE,"original explicit continue confirms frozen result without replaying action")
	var banked: Dictionary = app.camp_snapshot()
	_check(banked.day==expected.camp.day+1 and banked.last_day.food_found==RecordEncoding.unpack(JSON.parse_string(expected.encoded)).payload.envelope.result.battle.food,"single actual partial-food settlement")
	var hash: String = FileAccess.get_sha256(app.progress_path)
	app.return_to_title()
	_check(hash==FileAccess.get_sha256(app.progress_path),"duplicate confirm never advances again")
