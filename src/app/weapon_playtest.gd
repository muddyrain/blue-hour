class_name WeaponPlaytest
extends TrainingPlaytest
## Explicit final-package weapon acceptance; original campaign actions and diagnostic pairs.

var weapon_samples: Array[Dictionary] = []
var weapon_ui: Array[Dictionary] = []
var natural_weapons: Array[Dictionary] = []


func _task_path() -> String:
	return "/.local/m5-weapon-02/"


func _tap(button: BaseButton) -> void:
	# MovieWriter and native layout can finish later than the inherited two-frame wait.
	# Observe the actual signal; never let activate() substitute for a missed UI commit.
	for frame: int in range(4): await get_tree().process_frame
	var pressed: Array[bool] = [false]
	var observe: Callable = func() -> void: pressed[0] = true
	button.pressed.connect(observe,CONNECT_ONE_SHOT)
	await super._tap(button)
	for frame: int in range(8):
		if pressed[0]: break
		await get_tree().process_frame
	_expect(pressed[0],"dispatched viewport button actually emits pressed before inspecting its result")
	if is_instance_valid(button) and button.pressed.is_connected(observe): button.pressed.disconnect(observe)
	for frame: int in range(4): await get_tree().process_frame


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--camp-case="): camp_case = arg.trim_prefix("--camp-case=")
	if camp_case == "old-suspend-blocked":
		await _settle()
		await get_tree().create_timer(0.3).timeout
		var digest: String = _digest()
		await _tap(app._continue_button)
		if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
		_expect(app.expedition==null and app._progress_blocked,"old weapon-data snapshot refuses before running a changed world")
		_expect(digest==_digest(),"incompatible old snapshot refusal never consumes its generation or rewrites profile bytes")
		await _capture("old-snapshot-preserved.png")
		await _finish_camp()
		return
	if camp_case != "measure":
		await super._run()
		return
	if not output_dir.is_absolute_path() or _task_path() not in output_dir.replace("\\","/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _settle()
	await get_tree().create_timer(0.3).timeout
	await _enter()
	_initial = app.camp_snapshot()
	await _weapons_ui("initial")
	var digest: String = _digest()
	app.get_node("Interface/Screen").hide()
	weapon_samples = await WeaponCombatProbe.run(get_tree(),_initial,_capture)
	app.get_node("Interface/Screen").show()
	_expect(weapon_samples.size()==4,"four actual weapon pairs use same member level Trait enemy HP and distance")
	for index: int in range(0,weapon_samples.size(),2):
		var carbine: Dictionary = weapon_samples[index]
		var rifle: Dictionary = weapon_samples[index+1]
		_expect(carbine.member_id==rifle.member_id and carbine.ordinary_level==rifle.ordinary_level and carbine.trait_level==rifle.trait_level and carbine.initial_enemy_hp==rifle.initial_enemy_hp,"paired shooter and enemy conditions fixed")
		_expect(carbine.damage==18 and rifle.damage==32 and carbine.range==210 and rifle.range==315 and carbine.base_interval==0.65 and rifle.base_interval==1.30,"real actor definitions use explicit PROJECT_TEMP two-gun values")
		_expect(carbine.damage_in_window>rifle.damage_in_window and not carbine.mid_fires and rifle.mid_fires,"carbine wins sustained near output; rifle alone fires at260")
		for sample: Dictionary in [carbine,rifle]:
			_expect(sample.pause_freezes and sample.edge_refuses and sample.inside_fires,"actual pause and strict foot-range edge preserved")
			_expect(sample.near_shots.all(func(shot: Dictionary) -> bool: return shot.applied_damage==sample.damage and shot.interval==sample.effective_interval),"actual shot damage and cooldown follow selected gun and fixed owner Trait")
			_expect(sample.observed_intervals.all(func(interval: float) -> bool: return absf(interval-float(sample.effective_interval))<=0.0011),"real consecutive shot timing matches within one millisecond diagnostic tick")
	_expect(digest==_digest() and TransactionReceipt.same(_initial,app.camp_snapshot()),"controlled worlds never publish fixture XP guns death or progress")
	await _finish_camp()


func _maintenance() -> void:
	await super._maintenance()
	await _weapons_ui("saved-equipment")


func _field_bus(world: Expedition) -> void:
	var owners: Dictionary = {}
	for actor: FieldActor in world.survivors:
		owners[actor.member_id] = {"instance_id":actor.weapon_instance_id,"weapon_id":String(actor.weapon_definition.id),"damage":actor.weapon_definition.damage,"range":actor.weapon_definition.shot_range,"interval":actor.weapon_definition.shot_interval(actor.trait_shot_factor)}
	await super._field_bus(world)
	var shots: Array = _battle_events.filter(func(event: Dictionary) -> bool: return event.kind=="shot")
	_expect(not shots.is_empty(),"normal sortie emits real owned weapon shots")
	for id: int in owners:
		var definition: Dictionary = owners[id]
		var personal: Array = shots.filter(func(event: Dictionary) -> bool: return int(event.member_id)==id)
		_expect(personal.all(func(event: Dictionary) -> bool: return event.instance_id==definition.instance_id and event.weapon_id==definition.weapon_id and event.damage==definition.damage and event.shot_range==definition.range and event.foot_distance<definition.range and event.interval==definition.interval and event.applied_damage>0 and event.applied_damage<=definition.damage),"natural shots retain equipped instance damage range cooldown and personal Trait for ID%d" % id)
		natural_weapons.append({"member_id":id,"definition":definition,"shots":personal})


func _weapons_ui(label: String) -> void:
	var before: Dictionary = app.camp_snapshot()
	var digest: String = _digest()
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var panel: LoadoutPanel = app.loadout_panel
	_expect(panel.visible,"original camp workshop opens original inventory")
	for index: int in range(mini(2,panel.items.item_count)):
		panel.items.select(index)
		panel.items.item_selected.emit(index)
		await _settle()
		var item: Dictionary = WeaponInventory.find(before,panel.items.get_item_metadata(index))
		var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
		_expect(panel._detail.text.contains("PROJECT_TEMP") and panel._detail.text.contains("间隔 %.3f秒" % weapon.interval) and panel._detail.text.contains("射程 %.0f" % weapon.shot_range),"inventory displays real base damage interval range and temporary status")
		var owner: int = WeaponInventory.owner(before,item.instance_id)
		if owner>0:
			var member: Dictionary = SurvivorRoster.member(before.crew,owner)
			_expect(panel._detail.text.contains("%.3f秒" % weapon.shot_interval(TraitRules.factor(member,"shot"))),"selected owner's displayed effective interval uses same definition function as combat")
		for member: Dictionary in before.crew:
			var gun: Dictionary = WeaponInventory.for_member(before,int(member.id))
			if gun.is_empty(): continue
			var definition: WeaponDefinition = WeaponInventory.definition(gun.weapon_id)
			_expect(panel._member_equipment[int(member.id)].text.contains("%.3fs" % definition.shot_interval(TraitRules.factor(member,"shot"))),"member current loadout shows actual personal interval")
		var viewport: Rect2 = get_viewport().get_visible_rect()
		for control: Control in [panel.items,panel.back_button,panel.repair_button,panel.equip_buttons[0],panel._preview]:
			var rect: Rect2 = control.get_global_rect()
			_expect(viewport.encloses(rect),"inventory control stays inside actual logical viewport: "+control.get_class())
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = panel.back_button.get_global_rect().get_center()
		get_viewport().push_input(motion,true)
		await _settle()
		var hovered: Control = get_viewport().gui_get_hovered_control()
		_expect(hovered==panel.back_button or (hovered!=null and panel.back_button.is_ancestor_of(hovered)),"resolved native GUI hit target exposes back button without overlay occlusion")
		weapon_ui.append({"label":label,"weapon":String(weapon.id),"detail":panel._detail.text,"detail_rect":str(panel._detail.get_global_rect()),"viewport":str(viewport),"back":str(panel.back_button.get_global_rect()),"hovered":str(hovered)})
		await _capture(label+"-"+String(weapon.id)+".png")
		var scroll: ScrollContainer = panel._detail.get_parent() as ScrollContainer
		for tick: int in range(6):
			await _click_at(scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
		_expect(panel._detail.get_global_rect().size.y<=scroll.size.y or scroll.scroll_vertical>0,"overflowing weapon details remain reachable with real viewport wheel")
	_expect(digest==_digest() and TransactionReceipt.same(before,app.camp_snapshot()),"viewing base/effective parameters never writes camp or logs")
	await _key_battle(KEY_ESCAPE)


func _finish_camp() -> void:
	_write(output_dir.path_join("weapon-measurements.json"),{"samples":weapon_samples,"ui":weapon_ui,"natural":natural_weapons})
	await super._finish_camp()
