class_name QualityPlaytest
extends RosterPlaytest
## Explicit110 verification intentions; ordinary game never attaches this controller.

func _task_path() -> String:
	return "/.local/m5-weapon-03a/"

func _trait_problem(data: Dictionary) -> String:
	return WeaponState.problem(data)

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--camp-case="): camp_case = arg.trim_prefix("--camp-case=")
		if arg.begins_with("--camp-expected="): expected_path = arg.trim_prefix("--camp-expected=")
	if not output_dir.is_absolute_path() or _task_path() not in output_dir.replace("\\","/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	await _settle()
	await get_tree().create_timer(0.3).timeout
	if camp_case in ["resume","resave","same-resave"]:
		await _restore_pool()
		await _finish_camp()
		return
	await _enter()
	_initial = app.camp_snapshot()
	if camp_case=="measure":
		await _measure_instances()
		await _finish_camp()
		return
	_expect(_trait_problem(_initial).is_empty(),"strict instance initial camp: "+_trait_problem(_initial))
	if not expected_path.is_empty():
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		_expect(TransactionReceipt.same(_initial,expected.camp),"new PID exactly restores all five historical identities and four living")
	await _camp_ui("camp-before")
	if camp_case=="prepare":
		await _maintain_rich()
	elif camp_case in ["loot","loot-measure","save-loot"]:
		await _open_map(1)
		var loot_world: Expedition = _watch_world()
		await _field_search(loot_world)
		_expect(loot_world.weapon_loot.size()==1,"real cash search generates one frozen rich instance")
		var found: Dictionary = loot_world.weapon_loot[0].duplicate(true)
		await _capture("natural-loot.png")
		if camp_case=="save-loot":
			await _save_field(loot_world)
			await _finish_camp()
			return
		await _field_bus(loot_world)
		_expect(TransactionReceipt.same(found,WeaponInventory.find(app.camp_snapshot(),found.instance_id)),"actual carried level quality affix enter inventory unchanged only after bus")
		_write(output_dir.path_join("natural-loot.json"),found)
		await _maintain_rich()
		if camp_case=="loot-measure":
			await _measure_instances()
	elif camp_case=="terminal-view":
		var digest: String = _digest()
		var view: Dictionary = _initial.duplicate(true)
		view.journey.state = "FAILED" # View-only terminal geometry fixture, never submitted.
		app._show_battle_result(view,true)
		await _settle()
		var button: Button = app._battle_new_button
		_expect(get_viewport().get_visible_rect().encloses(button.get_global_rect()),"terminal new-journey button stays inside actual viewport")
		button.grab_focus()
		_expect(get_viewport().gui_get_focus_owner()==button,"terminal button can receive native keyboard focus")
		await _tap(button)
		_expect(app._new_game_confirmation.visible,"terminal new-journey action opens explicit confirmation")
		await _tap(app._new_game_confirmation.get_cancel_button())
		_expect(digest==_digest(),"view-only terminal fixture and cancel leave real saved camp unchanged")
	elif camp_case=="continue":
		await _profiles()
	elif camp_case.begins_with("train") or camp_case.begins_with("kill-"):
		await _train_member(int(_initial.journey.active_member_ids[-1]))
	elif camp_case=="death-replace":
		_expect(_initial.crew.size()==4 and RosterState.living_count(_initial)==4,"death starts with four legitimate historical living members")
		await _train_member(3)
		await _long_names()
		await _tap(app.camp_scene.hotspots[&"weapons"])
		var swapped: String = ""
		for item: Dictionary in app.weapons:
			if item.origin=="north-cache" and item.condition=="ready" and (item.weapon_level==2 or item.quality=="rare"):
				swapped = item.instance_id
				break
		_expect(not swapped.is_empty(),"death ownership uses legitimately found non-baseline instance")
		_select_item(app.loadout_panel,swapped)
		await _tap(app.loadout_panel.equip_by_id[3])
		await _key_battle(KEY_ESCAPE)
		_initial = app.camp_snapshot()
		app.survival_pilot = false
		await _open_map(1)
		var death_world: Expedition = _watch_world()
		await _field_death(death_world,3)
		await _field_search(death_world)
		await _field_bus(death_world)
		var before_replace: Dictionary = app.camp_snapshot()
		_expect(before_replace.crew.size()==4 and RosterState.living_count(before_replace)==3 and SurvivorRoster.member(before_replace.crew,3).condition=="dead","real AI death saved; identity3 permanently retained")
		_expect(WeaponInventory.owner(before_replace,swapped)==0 and TransactionReceipt.same(WeaponInventory.find(before_replace,swapped),WeaponInventory.find(_initial,swapped)),"real death unassigns exactly one rich gun and preserves all random attributes")
		_expect(app.progress_session.death_equipment(before_replace).get(3,{}).get("instance_id","")==swapped,"dead member with no kills in death sortie retains actual swapped gun via original receipts")
		_write(output_dir.path_join("death-camp.json"),before_replace)
		journey_stages.append({"stage":"real-death","camp":before_replace,"reports":_reports.duplicate(true)})
		_reports.clear()
		_initial = before_replace
		app.survival_pilot = true
		await _rescue_outing()
		var after: Dictionary = app.camp_snapshot()
		_expect(after.crew.size()==5 and RosterState.living_count(after)==4,"replacement forms five history and four living")
		_expect(TransactionReceipt.same(SurvivorRoster.member(before_replace.crew,3),SurvivorRoster.member(after.crew,3)),"dead identity alias XP Trait training service and action remain exactly unchanged")
		_expect(TransactionReceipt.same({"v":before_replace.journey.deaths},{"v":after.journey.deaths}),"replacement does not erase or mutate confirmed death provenance")
		await _profiles()
		await _maintain_rich()
	elif camp_case=="next":
		await _profiles()
		var restored_gun: Dictionary = WeaponInventory.for_member(_initial,1).duplicate(true)
		await _maintenance()
		_expect(TransactionReceipt.same(restored_gun,WeaponInventory.for_member(app.camp_snapshot(),1)),"new PID preserves exact selected real rich instance before next battle")
		await _train_member(int(_initial.journey.active_member_ids[-1]))
		_initial = app.camp_snapshot()
		await _open_map(1)
		var world: Expedition = _watch_world()
		_expect(world.survivors.size()==4 and world.survivors.all(func(a: FieldActor) -> bool: return a.member_id!=3),"only four living IDs depart; archived3 never respawns")
		await _capture("four-hud.png")
		await _field_search(world)
		for frame: int in range(1200):
			if _battle_events.any(func(event: Dictionary) -> bool: return event.get("kind")=="shot" and event.get("member_id")==1): break
			world.command_move(Vector2(568,864))
			await _step(world)
		var real: Array = _battle_events.filter(func(event: Dictionary) -> bool: return event.get("kind")=="shot" and event.get("member_id")==1)
		var effective: Dictionary = WeaponModifiers.effective(restored_gun,TraitRules.factor(SurvivorRoster.member(_initial.crew,1),"shot"))
		_expect(not real.is_empty(),"restored actually found rich gun fires during real next sortie")
		for shot: Dictionary in real:
			_expect(shot.instance_id==restored_gun.instance_id and is_equal_approx(shot.damage,effective.damage) and is_equal_approx(shot.cooldown_after,effective.interval) and is_equal_approx(shot.shot_range,effective.range),"real next-sortie shot uses exact restored instance level affix and own Trait")
		_write(output_dir.path_join("real-rich-shots.json"),{"instance":restored_gun,"member":SurvivorRoster.member(_initial.crew,1),"effective":effective,"shots":real})
		await _field_bus(world)
		_expect(app.camp_snapshot().last_day.food_required==4,"next normal meal consumes four rations")
	else:
		await _rescue_outing()
	await _finish_camp()


func _maintain_rich() -> void:
	var selected: Dictionary = {}
	for item: Dictionary in app.weapons:
		if item.origin=="north-cache" and (item.weapon_level==2 or item.quality=="rare"):
			selected = item.duplicate(true)
			break
	if selected.is_empty():
		_write(output_dir.path_join("rich-status.json"),{"available":false})
		return
	await _tap(app.camp_scene.hotspots[&"weapons"])
	_select_item(app.loadout_panel,selected.instance_id)
	if selected.condition=="damaged":
		await _tap(app.loadout_panel.repair_button)
		await _tap(app.loadout_panel.confirmation.get_ok_button())
		selected.condition = "ready"
	_expect(TransactionReceipt.same(selected,WeaponInventory.find(app.camp_snapshot(),selected.instance_id)),"repair only changes condition, never level quality affix or instance ID")
	await _tap(app.loadout_panel.equip_by_id[1])
	_expect(WeaponInventory.owner(app.camp_snapshot(),selected.instance_id)==1,"one original owner equips rich instance")
	await _capture("rich-equipped.png")
	await _key_battle(KEY_ESCAPE)
	_write(output_dir.path_join("rich-status.json"),{"available":true,"instance":selected})


func _maintenance() -> void:
	await _maintain_rich()


func _field_search(world: Expedition) -> void:
	for kind: StringName in [&"cash",&"food"]:
		if not world.supply.supports(kind) or world.search_site(kind).searched: continue
		world.command_move(world.search_site(kind).door)
		for frame: int in range(1600):
			if world.survivors.all(func(actor: FieldActor) -> bool: return actor.activity!=FieldActor.Activity.MOVING): break
			await _step(world)
		world.request_search(kind)
		for frame: int in range(3200):
			if world.search_site(kind).searched: break
			await _step(world)
		_expect(world.search_site(kind).searched,"original real search completes "+String(kind))
	if not world.field_joins.is_empty() and world.rescue_target.npc.health>0:
		var npc: FieldActor = world.rescue_target.npc
		var expected: WeaponDefinition = WeaponInventory.definition("long_rifle" if npc.member_id==4 else "carbine")
		_expect(npc.weapon_definition.damage==expected.damage and npc.weapon_definition.interval==expected.interval and npc.weapon_definition.shot_range==expected.shot_range,"new recruit starts with real Lv1 common baseline weapon through original combat owner")
		var personal: Array = _battle_events.filter(func(event: Dictionary) -> bool: return event.get("kind")=="shot" and event.get("member_id")==npc.member_id)
		_write(output_dir.path_join("recruit-combat.json"),{"member_id":npc.member_id,"shots":personal,"confirmed_kills":npc.confirmed_kills,"interpretation":"natural competition; zero personal kills is valid when existing longer-range guns fire first; XP follows actual killer"})
		await _capture("recruit-combat.png")


func _weapons_ui(label: String) -> void:
	var before: Dictionary = app.camp_snapshot()
	var digest: String = _digest()
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var panel: LoadoutPanel = app.loadout_panel
	for index: int in range(panel.items.item_count):
		panel.items.select(index)
		panel.items.item_selected.emit(index)
		await _settle()
		var item: Dictionary = WeaponInventory.find(before,panel.items.get_item_metadata(index))
		_expect(panel._detail.text.contains(WeaponModifiers.description(item)),"UI displays exact stored quality level and affix")
		_expect(panel._detail.text.contains("PROJECT_TEMP") and panel._detail.text.contains("枪型基础"),"base type and instance effects separately labeled")
		for member: Dictionary in before.crew:
			if member.health<=0: continue
			var gun: Dictionary = WeaponInventory.for_member(before,int(member.id))
			var stats: Dictionary = WeaponModifiers.effective(gun,TraitRules.factor(member,"shot"))
			_expect(panel._member_equipment[int(member.id)].text.contains("%.3fs" % stats.interval),"member display uses exact own Trait and instance interval")
		_expect(get_viewport().get_visible_rect().encloses(panel.back_button.get_global_rect()),"weapons close fits viewport")
		if index<3: await _capture(label+"-weapon-%d.png" % index)
	var scroll: ScrollContainer = panel._detail.get_parent()
	for tick: int in range(10):
		await _click_at(scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
	_expect(scroll.scroll_vertical>0 or panel._detail.size.y<=scroll.size.y,"full comparison scrolls with native wheel")
	await _capture(label+"-comparison.png")
	await _key_battle(KEY_ESCAPE)
	_expect(digest==_digest(),"weapon comparisons never reroll save or acquire an instance")


func _measure_instances() -> void:
	var digest: String = _digest()
	app.get_node("Interface/Screen").hide()
	var samples: Array[Dictionary] = await QualityCombatProbe.run(get_tree(),_initial,_capture)
	app.get_node("Interface/Screen").show()
	_expect(samples.size()==9,"nine actual auto-combat paired samples")
	_expect(is_equal_approx(samples[0].shots[0].applied_damage,18.0) and is_equal_approx(samples[1].shots[0].applied_damage,19.8),"same carbine gains real18 to19.8 damage from independent weapon level")
	_expect(is_equal_approx(samples[4].shots[0].applied_damage,32.0) and is_equal_approx(samples[5].shots[0].applied_damage,35.2),"same long rifle gains real32 to35.2 damage from independent weapon level")
	_expect(float(samples[3].intervals[0])<float(samples[0].intervals[0]) and float(samples[7].intervals[0])<float(samples[4].intervals[0]),"quick affix actually fires sooner for same type and same Trait")
	for sample: Dictionary in samples:
		_expect(sample.ordinary_level==1 and sample.enemy_hp==10000 and sample.distance==100,"same ordinary level enemy distance and LOS")
		_expect(sample.shots.size()>2,"real original auto-combat emits multiple shots")
		for shot: Dictionary in sample.shots:
			_expect(is_equal_approx(shot.applied_damage,sample.expected.damage),"real damage equals shared effective formula")
		for interval: float in sample.intervals:
			_expect(absf(interval-float(sample.expected.interval))<0.002,"real shot intervals equal instance then own Trait formula")
		_expect(sample.extension_fires==(sample.spec.variant=="reach_v1"),"only range affix extends original type reach")
		_expect(sample.mid_260_fires==(sample.spec.kind=="long_rifle"),"base carbine vs long-rifle reach positioning preserved")
	_expect(digest==_digest(),"diagnostic A/B never writes campaign state")
	_write(output_dir.path_join("paired.json"),{"samples":samples})
	await _weapons_ui("paired-camp")
