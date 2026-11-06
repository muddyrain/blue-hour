extends "res://tests/exploration_flow.gd"
## Controlled lethal input after real collection; never presented as a normal journey.
func _journey() -> void:
	await _tap(app._home_button);await _tap(app._new_game_confirmation.get_ok_button())
	var initial: Dictionary=app.camp_snapshot()
	await _menu()
	var slot: int=0
	for i: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[i].layout["size"]=="small":slot=i
	var world: Expedition=await _start(slot)
	if world==null:return
	var car: Expedition.SearchSite=_closest(world,world.layout.bus_door,"vehicle")
	var tree: Expedition.SearchSite=_closest(world,world.layout.bus_door,"fruit_tree")
	world.request_search(car.id);world.request_search(tree.id)
	await _until(world,func()->bool:return car.searched and tree.searched)
	_check(world.loot==1 and world.food_loot==1,"controlled lethal checkpoint first carries actual car and tree rewards")
	for actor: FieldActor in world.survivors:actor.take_damage(actor.health+1.0)
	await _until(world,func()->bool:return world.phase==Expedition.Phase.FINISHED)
	_check(not app._progress_blocked,"real death-gated failed world publishes original settlement: "+app._progress_message)
	var saved: Dictionary=app.camp_snapshot()
	_check(saved.cash==initial.cash and saved.food==initial.food and saved.journey.state=="FAILED","full wipe durably banks neither carried cash nor food")
	var packet: Dictionary=app.progress_session.packet
	_check(not packet.is_empty() and packet.input.rules.data_version==10,"failed closeout retains strict frozen new-mode packet")
	if not packet.is_empty():
		var file: FileAccess=FileAccess.open(output.path_join("wipe-packet.json"),FileAccess.WRITE)
		file.store_string(RecordEncoding.stringify({"input":packet.input}));file.close()
	var again: Dictionary=app.progress_session.commit_result()
	_check(again.error==OK and TransactionReceipt.same(saved,app.camp_snapshot()),"duplicate failed confirmation preserves durable zero-gain camp")
	_write("acceptance.json",{"scope":"CONTROLLED_LETHAL_INPUT_AFTER_REAL_COLLECTION","carried":{"cash":world.loot,"food":world.food_loot},"saved":saved,"packet_error":app._progress_message})
