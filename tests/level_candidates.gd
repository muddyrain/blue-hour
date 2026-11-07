extends "res://tests/level_flow.gd"
## A third real PID continues the banked camp and verifies same-day maintenance.
func _resume() -> void:
	var prior: Dictionary = RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("resume/camp-exact.json")))).payload
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_check(app.expedition==null and TransactionReceipt.same(app.camp_snapshot(),prior.camp), "fresh PID continues the exact banked camp")
	await _menu()
	_check(TransactionReceipt.same({"v":app.mission_select.daily_offers},{"v":prior.offers}), "restart retains identical same-day complete candidates")
	await _tap(app.mission_select.cancel_button)
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var damaged: Dictionary = app.camp_snapshot().weapons.filter(func(item: Dictionary) -> bool: return item.condition=="damaged")[0]
	app.repair_weapon(damaged.instance_id)
	_check(WeaponInventory.find(app.camp_snapshot(),damaged.instance_id).condition=="ready", "real earned equipment repaired through original owner")
	var original: String = WeaponInventory.for_member(app.camp_snapshot(),1).instance_id
	app.equip_weapon(1,damaged.instance_id)
	app.equip_weapon(1,original)
	app.close_loadout()
	await _menu()
	_check(TransactionReceipt.same({"v":app.mission_select.daily_offers},{"v":prior.offers}), "real repair and loadout changes cannot redraw same-day geometry or rewards")
	_write("acceptance.json", {"same_day_restart_repair_loadout":true,"offers":app.mission_select.daily_offers})
