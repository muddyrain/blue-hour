extends "res://tests/campaign_flow.gd"
## Normal new journey: viewport building clicks, original navigation, rewards and suspend owners.
var selected_ids: Array[StringName] = []

func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _tap(app.camp_scene.hotspots[&"bus"])
	var w: Expedition=await _start(0)
	if w==null:
		return
	_check(w.parallel_search and w.sites.size()>=3,"fresh M9 journey enables parallel search without new mission generation")
	var a: Expedition.SearchSite=w.sites[0]
	var b: Expedition.SearchSite=w.sites[1]
	selected_ids.assign([a.id,b.id])
	await click_site(w,a)
	var first: Dictionary=w.search_assignments.snapshot()
	await click_site(w,b)
	_check(w.search_assignments.ordered().size()==2 and w.search_assignments.member_for(String(a.id))!=w.search_assignments.member_for(String(b.id)),"two actual building clicks assign different members without cancelling first")
	var both: Dictionary=w.search_assignments.snapshot()
	await click_site(w,w.sites[2])
	_check(TransactionReceipt.same(both,w.search_assignments.snapshot()) and "暂无空闲" in w._notice_text,"all members may work; no idle member does not steal a task")
	# Both are still approaching: a legal R1 strike must retain every task/path/progress.
	for i: int in range(5):
		w.camera.zoom_at(Vector2(640,360),1.0/w.camera.zoom_step)
	var before: Dictionary=w.support_world()
	_check(w.request_airstrike(w.survivors[0].position),"minimum-zoom legal support accepts in world12")
	var after: Dictionary=w.support_world()
	_check(TransactionReceipt.same(before.jobs,after.jobs) and TransactionReceipt.same(before.sites,after.sites),"support reconstruction preserves both task associations and progress")
	_check(TransactionReceipt.same({"path":SortieSnapshot._encode(w.survivors[0].path)},{"path":before.survivors[0].state.path}),"support reconstruction preserves approach path")
	await _until(w,func()->bool:return a.progress>2.0 and b.progress>0.0)
	var saved_b: float=b.progress
	var saved_a: float=a.progress
	await click_site(w,a)
	_check(not w.has_search_job(w.search_assignments.member_for(String(a.id))) and w.search_assignments.ordered().size()==1 and a.progress==saved_a,"repeat building click cancels only its task and preserves earned progress")
	for i: int in range(15):
		w.step(1.0/30.0)
	_check(b.progress>saved_b,"other building continues after local cancellation")
	await click_site(w,a)
	await _until(w,func()->bool:return w.search_assignments.phase_for(w.search_assignments.member_for(String(a.id)))=="working" and a.progress>saved_a+0.5)
	_check(w.search_assignments.ordered().size()==2 and a.progress!=b.progress,"reassigned tasks independently advance at different progress")
	w.toggle_pause()
	var captured: Dictionary=SortieSnapshot.capture(w)
	var frozen: String=RecordEncoding.fingerprint(captured)
	w.step(2.0)
	_check(RecordEncoding.fingerprint(SortieSnapshot.capture(w))==frozen,"pause freezes task clocks, movement and protection")
	_check(app.progress_session.preview_suspend(captured).error==OK,"strict world12 before suspend validates")
	var receipt: Dictionary=app.progress_session._transaction.recover().receipt
	var bad: Dictionary=captured.duplicate(true)
	bad.jobs.assignments.append(bad.jobs.assignments[0].duplicate(true))
	_check(not SortieSnapshot.problem(bad,receipt).is_empty(),"duplicate member/site assignments reject")
	bad=captured.duplicate(true);bad.jobs.assignments=[]
	_check(SortieSnapshot.problem(bad,receipt)=="SEARCH_ORPHAN_WORKER","unregistered hidden workers reject")
	bad=captured.duplicate(true);bad.survivors[0]="invalid"
	_check(SortieSnapshot.problem(bad,receipt)=="WORLD_SURVIVOR_FIELDS","malformed actor rejects before method dispatch")
	_write("checkpoint.json",{"world":captured,"fingerprint":frozen,"pid":OS.get_process_id(),"sites":[String(a.id),String(b.id)],"first":first})
	app.open_pause_menu();app.suspend_sortie();await _hold(3)
	_check(app.expedition==null and app._requires_continue,"original suspend ACK publishes two independent tasks")

func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var w: Expedition=app.expedition
	_check(w!=null,"new PID restores original acknowledged parallel sortie")
	if w==null:
		return
	w.set_process(false);w.set_physics_process(false)
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	_check(OS.get_process_id()!=expected.pid and RecordEncoding.fingerprint(SortieSnapshot.capture(w))==expected.fingerprint,"new PID exactly restores associations, paths, HP, visibility and differing progress")
	if app.pause_menu.visible:
		await _tap(app.pause_menu.buttons[0])
	if w.is_paused:
		w.toggle_pause()
	await _until(w,func()->bool:return w.elapsed>=20.0)
	w.request_extraction()
	await _until(w,func()->bool:return w.phase==Expedition.Phase.BOARDING)
	w.request_bus_gather()
	_check(w.boarding_status().required==2 and w.boarding_status().working>0 and w.goal==w.layout.bus_door,"bus counts hidden workers and keeps them working after gather")
	await _until(w,func()->bool:return expected.sites.all(func(id:String)->bool:return w.search_site(StringName(id)).searched))
	var loot: int=w.loot
	var food: int=w.food_loot
	var weapons: int=w.weapon_loot.size()
	for id: String in expected.sites:
		await click_site(w,w.search_site(StringName(id)))
	_check(w.loot==loot and w.food_loot==food and w.weapon_loot.size()==weapons and w.search_assignments.ordered().is_empty(),"completed sites cannot pay or occupy twice after recovery")
	w.request_bus_gather()
	await _until(w,func()->bool:return w.phase==Expedition.Phase.FINISHED)
	for i: int in range(300):
		if not w.bus_view.running():
			break
		w.step(1.0/30.0)
	await _hold(3)
	_check(not app._progress_blocked,"original return preview authenticates independent site rewards")
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(not app._progress_blocked and app.camp_snapshot().journey.campaign.preparations==1,"original confirmation commits one return without new reward owner")
	_write("returned.json",{"camp":app.camp_snapshot(),"reports":reports})

func click_site(w: Expedition, site: Expedition.SearchSite) -> void:
	w.camera.pan_by(site.hit.get_center()-w.camera.position)
	w.camera.force_update_scroll()
	await _frame()
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	event.position=w.get_global_transform_with_canvas()*site.hit.get_center()
	viewport.push_input(event,true)
	await _frame()
