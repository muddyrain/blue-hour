extends "res://tests/campaign_flow.gd"
## Approved M8 bootstrap; current strict owners generate minimal isolated representatives.
func _menu(_count: int) -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(app.mission_select.visible,"M8 candidates accessible")
	for value:Dictionary in app.mission_select.daily_offers:_check(value.version==7,"M8 remains generated7")
func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(BuildState.enabled(app.camp_snapshot()) and not CombatActions.enabled(app.camp_snapshot()),"approved bootstrap creates exact old M8 mode")
	await _menu(0)
	var world:Expedition=await _start(0)
	if world==null:return
	if output.get_file()=="old-underway":
		await _until(world,func()->bool:return world.elapsed>=12)
		app.open_pause_menu()
		var state:Dictionary=SortieSnapshot.capture(world)
		_write("oracle.json",{"fingerprint":RecordEncoding.fingerprint(state),"pid":OS.get_process_id()})
		app.suspend_sortie()
		_check(app._requires_continue and app.expedition==null,"M8 original suspend commits")
	else:
		await _extract(world)
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_check(not app._progress_blocked,"M8 original return confirms")
		_write("oracle.json",{"camp":app.camp_snapshot(),"pid":OS.get_process_id()})
func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	var original:String="old-underway" if "underway" in output else "old-complete"
	var oracle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(original+"/oracle.json")))
	_check(oracle.pid!=OS.get_process_id(),"old M8 crosses PID")
	if original=="old-underway":
		var world:Expedition=app.expedition
		_check(world!=null,"candidate reconstructs old active M8")
		if world==null:return
		world.set_physics_process(false);world.set_process(false)
		_check(RecordEncoding.fingerprint(SortieSnapshot.capture(world))==oracle.fingerprint,"M8 complete historical fingerprint and state remain exact")
		_check(world.supply.generated.version==7 and not world.combat_mode(),"old active M8 gets no new content")
	else:
		_check(TransactionReceipt.same(app.camp_snapshot(),oracle.camp),"old completed M8 camp remains exact")
		_check(DailyActions.offers(app.camp_snapshot())[0].version==7,"old camp keeps original mode")
