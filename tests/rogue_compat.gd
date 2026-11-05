extends "res://tests/playable_flow.gd"
var mode: String=""
func _journey() -> void:
	mode=output.get_file()
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _tap(app.camp_scene.hotspots[&"bus"])
	await _tap(app.mission_select.choices[1])
	var world: Expedition=app.expedition;world.set_physics_process(false)
	if mode=="old-suspend":
		world.request_search(&"cash")
		await _advance(world,func() -> bool:return world.search_progress>=3)
		app.open_pause_menu()
		var snapshot: Dictionary=SortieSnapshot.capture(world)
		_check(snapshot.version==2 and not snapshot.has("generated"),"synthetic legacy fixed-world v2")
		await _tap(app.pause_menu.buttons[4])
		_check(app.progress_session.inspect().state=="SUSPENDED","legacy fixed-world original suspend saved")
	else:
		world.request_search(&"cash");await _advance(world,func() -> bool:return world.searched)
		world.request_search(&"food");await _advance(world,func() -> bool:return world._food_site.searched)
		await _advance(world,func() -> bool:return world.elapsed>=world.tuning.bus_ready_seconds)
		world.request_bus_action();await _advance(world,func() -> bool:return world.phase==Expedition.Phase.BOARDING)
		world.request_bus_gather();await _advance(world,func() -> bool:return world.phase==Expedition.Phase.FINISHED)
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_check(app.settled_sorties==1 and app.day==3,"synthetic legacy actual completed camp")
	var current: Dictionary=app.progress_session.inspect()
	_write("oracle.json",{"state":current.state,"camp":app.camp_snapshot(),"receipt":current.receipt,"head":current.hash,"originals":_files()})
func _resume() -> void:
	mode=output.get_file()
	var source: String="old-suspend" if mode=="new-refuse" else "old-complete"
	var before: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(source+"/oracle.json")))
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	if mode=="new-refuse":
		_check(app.expedition==null and app._progress_blocked,"normal daily entry rejects old underway world before spawn/claim")
		var current: Dictionary=app.progress_session.inspect()
		_check(current.state=="SUSPENDED" and current.hash==before.head,"refusal leaves exact original generation unconsumed")
		_check(TransactionReceipt.same(before.originals,_files()),"old interrupted files/receipts stay byte-identical")
	else:
		_check(TransactionReceipt.same(before.camp,app.camp_snapshot()),"old completed camp identity/resources/crew preserved")
		_check(app.camp_snapshot().journey.root_id==before.camp.journey.root_id,"same root, no invented new journey")
		await _tap(app.camp_scene.hotspots[&"bus"])
		_check(app.mission_select.daily_offers.size()==3,"old camp enters new daily offers")
		_check(TransactionReceipt.same(before.originals,_files()),"browsing old camp never migrates old records")
		await _tap(app.mission_select.choices[0])
		_check(app.expedition!=null and not app.expedition.supply.generated.is_empty(),"old completed root can begin an authenticated generated action")
		app.expedition.set_physics_process(false)
func _files() -> Dictionary:
	var values: Dictionary={}
	for suffix: String in ["",".bak",".txn/binding.json"]:
		var path: String=app.progress_path+suffix
		values[suffix]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	var path: String=app.progress_path+".txn/journal"
	for folder: String in DirAccess.get_directories_at(path):
		if folder.begins_with(".stage"):continue
		values[folder]=FileAccess.get_sha256(path.path_join(folder+"/record.json"))
	return values
