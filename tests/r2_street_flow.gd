extends "res://tests/worldgen_flow.gd"
## A playable sample inside an ordinary offered action; no alternate world or state writes.
func _journey() -> void:
	FreezeProfile.enabled=true
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _menu()
	if "--flow-size=large" in OS.get_cmdline_user_args():
		await _large_observation()
		return
	var slot: int=-1
	for i: int in range(app.mission_select.daily_offers.size()):
		var offer: Dictionary=app.mission_select.daily_offers[i]
		if offer.layout["size"]=="medium" and offer.layout.topology=="commercial":
			slot=i
	_check(slot>=0,"ordinary daily menu offers a medium commercial action")
	if slot<0:return
	var world: Expedition=await _start(slot)
	if world==null:return
	var layout: Dictionary=world.layout.world_data
	var shops: Array[Expedition.SearchSite]=[]
	for site: Expedition.SearchSite in world.sites:
		if site.prop is FieldProp and not site.prop.street_sign.is_empty():
			shops.append(site)
	shops.sort_custom(func(a: Expedition.SearchSite,b: Expedition.SearchSite)->bool:return a.door.distance_squared_to(world.layout.bus_door)<b.door.distance_squared_to(world.layout.bus_door))
	_check(shops.size()>=2,"new real facades participate in original searchable sites")
	if shops.size()<2:return
	var front: Vector2=(shops[0].door+shops[1].door)*0.5
	world.camera.pan_by(front-Vector2(0,180)-world.camera.position)
	if capture_caption!=null:capture_caption.text="普通新旅程 · 商业街样板 · 自动输入 · 1×"
	segment_frames=0;segment_limit=300;recording=true
	world.command_move(front)
	await _until(world,func()->bool:return world.survivors.all(func(a:FieldActor)->bool:return a.position.distance_to(front)<90))
	await _hold(maxi(0,300-segment_frames))
	recording=false
	await _shot("ordinary-street-sample")
	var corner: Dictionary={}
	for parcel: Dictionary in layout.parcels:
		for detail: Dictionary in parcel.dressing:
			if detail.kind=="courtyard_edge":corner=detail
	_check(not corner.is_empty(),"ordinary action contains the supplied courtyard wall")
	if not corner.is_empty():
		var anchor: Vector2=WorldLayout.point(corner.point)
		var inner: Vector2=anchor+Vector2(float(corner.width)*0.65,-42)
		var opening: Vector2=inner+Vector2(80,0)
		_check(world.navigation.is_clear(inner) and world.navigation.is_clear(opening),"L wall leaves upper-right interior and opening clear")
		world.command_move(inner)
		await _until(world,func()->bool:return world.survivors.all(func(a:FieldActor)->bool:return a.position.distance_to(inner)<75))
		world.camera.pan_by(inner-Vector2(0,65)-world.camera.position)
		await _shot("courtyard-interior")
		world.command_move(opening)
		await _until(world,func()->bool:return world.survivors.all(func(a:FieldActor)->bool:return a.position.distance_to(opening)<75))
	for site: Expedition.SearchSite in shops.slice(0,2):
		world.request_search(site.id)
	await _until(world,func()->bool:return shops[0].progress>0 and shops[1].progress>0)
	_check(world.search_assignments.member_for(String(shops[0].id))!=world.search_assignments.member_for(String(shops[1].id)),"two actual storefronts have independent workers")
	var other_member: int=world.search_assignments.member_for(String(shops[1].id))
	world.request_search(shops[0].id)
	_check(world.search_assignments.member_for(String(shops[1].id))==other_member,"cancel affects only selected storefront")
	world.request_search(shops[0].id)
	world.camera.pan_by(front-Vector2(0,180)-world.camera.position)
	segment_frames=0;segment_limit=240;recording=true
	await _hold(240)
	recording=false
	await _shot("parallel-storefronts")
	await _until(world,func()->bool:return shops[0].searched and shops[1].searched)
	var car: Expedition.SearchSite=_closest(world,front,"vehicle")
	world.request_search(car.id)
	await _until(world,func()->bool:return car.progress>1)
	world.camera.pan_by(car.door-Vector2(0,80)-world.camera.position)
	segment_frames=0;segment_limit=180;recording=true
	await _hold(180)
	recording=false
	await _until(world,func()->bool:return car.searched)
	await _shot("searched-car")
	for site: Expedition.SearchSite in world.sites:
		if not site.searched and world.search_assignments.ordered().size()<2:
			world.request_search(site.id)
	await _until(world,func()->bool:return world.search_assignments.ordered().any(func(job:Dictionary)->bool:return job.phase=="working"))
	acceptance.sample={"action":world.supply.generated.id,"seed":layout.seed,"front":[front.x,front.y],"wall":corner,"normal_menu":true}
	await _suspend(world)

func _large_observation() -> void:
	var slot: int=-1
	for i: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[i].layout["size"]=="large":slot=i
	_check(slot>=0,"ordinary menu offers the large observation")
	if slot<0:return
	var world: Expedition=await _start(slot)
	if world==null:return
	var tree: Expedition.SearchSite=_closest(world,world.layout.bus_door,"fruit_tree")
	world.request_search(tree.id)
	await _until(world,func()->bool:return tree.searched)
	world.request_search(_closest(world,tree.door,"optional_building").id)
	world.request_search(_closest(world,tree.door,"vehicle").id)
	await _until(world,func()->bool:return world.search_assignments.ordered().any(func(job:Dictionary)->bool:return job.phase=="working"))
	acceptance.large_observation={"buildings":world.layout.world_data.entities.size(),"action":world.supply.generated.id}
	await _suspend(world)

func _suspend(world: Expedition) -> void:
	# Same normal GUI callback measured without hiding its capture/authentication work.
	app.open_pause_menu()
	await _hold(2)
	var captured: Dictionary=SortieSnapshot.capture(world)
	_write("checkpoint.json",{"fingerprint":RecordEncoding.fingerprint(captured),"pid":OS.get_process_id(),"legacy":false})
	FreezeProfile.start({"phase":"suspend-gui","buildings":world.layout.world_data.entities.size()})
	var started: int=Time.get_ticks_usec()
	app.suspend_sortie()
	acceptance.suspend_gui_sync_usec=Time.get_ticks_usec()-started
	FreezeProfile.finish()
	_write("suspend-profile.json",FreezeProfile.latest)
	var wait_started: int=Time.get_ticks_usec()
	await _hold(3)
	acceptance.suspend_wait_usec=Time.get_ticks_usec()-wait_started
	_check(app.expedition==null and app._requires_continue,"save success is shown only after durable ACK")
	var durable: Dictionary=app.progress_session._transaction.recover().receipt
	var file: FileAccess=FileAccess.open(output.path_join("oracle.json"),FileAccess.WRITE)
	file.store_string(RecordEncoding.stringify({"world":captured,"receipt":durable,"camp":app.camp_snapshot()}))
	file.close()
	_write("acceptance.json",acceptance)
