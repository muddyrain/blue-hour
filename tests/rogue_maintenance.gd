extends "res://tests/playable_flow.gd"
## Real existing camp edit, no candidate re-roll or invented inventory.
func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	await _tap(app.camp_scene.hotspots[&"bus"])
	var offers: Array[Dictionary]=app.mission_select.daily_offers.duplicate(true)
	await _tap(app.mission_select.cancel_button)
	var before: Dictionary=app.camp_snapshot()
	var damaged: Dictionary={}
	for item: Dictionary in before.weapons:
		if item.condition=="damaged":damaged=item;break
	_check(not damaged.is_empty(),"actual prior outing brought a damaged weapon")
	if damaged.is_empty():return
	await _tap(app.camp_scene.hotspots[&"weapons"])
	app.repair_weapon(damaged.instance_id)
	var after: Dictionary=app.camp_snapshot()
	var item: Dictionary=WeaponInventory.find(after,damaged.instance_id)
	_check(item.condition=="ready" and after.cash==before.cash-WeaponInventory.definition(item.weapon_id).repair_cost,"original real repair charges the fixed price")
	_check(item.instance_id==damaged.instance_id and item.quality==damaged.quality and item.affixes==damaged.affixes,"repair never rerolls instance or attributes")
	app.close_loadout()
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(TransactionReceipt.same({"v":offers},{"v":app.mission_select.daily_offers}),"real repair and menu reopen preserve full candidate descriptors")
	_write("maintenance.json",{"before":before,"after":after,"offers":offers})
