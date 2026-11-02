class_name P0D02APlaytest
extends Node
## Explicit source/export verification. No ordinary caller or implicit test user path.

var app: Node
var output_dir: String
var _mode: String = "business"
var _checks: Array[Dictionary] = []
var _failures: int = 0
var _fault_point: String = ""
var _barrier: String = ""
var _snapshots: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\","/").to_lower():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	get_tree().root.size = Vector2i(1280,720)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--p0d-case="):
			_mode = arg.trim_prefix("--p0d-case=")
		if arg.begins_with("--p0d-barrier="):
			_barrier = arg.trim_prefix("--p0d-barrier=")
	if app.progress_session != null:
		app.progress_session.fault_hook = _fault
	await _settle()
	match _mode:
		"business": await _business()
		"ready", "commit":
			await _enter()
			await _sortie(1,_mode == "commit")
		"new": await _enter()
		"reopen":
			_expect(app._requires_continue,"actual main offers coordinated Continue")
			if app._requires_continue:
				await _tap(app._continue_button)
			_expect(not app._requires_continue and not app._progress_blocked,"Continue completes frozen acknowledgement and enters camp")
		"locked-continue":
			_expect(app._requires_continue,"frozen result offers actual Continue before locked write")
			await _tap(app._continue_button)
			_expect(app._progress_blocked and app._progress_dirty,"real locked Continue fails safely and offers retry")
		"shortage":
			await _enter()
			await _sortie(0,true)
			await _sortie(0,false,true)
		"observe":
			_expect(app._progress_blocked and not app._requires_continue,"unsafe state blocks actual Continue before applying camp")
			var before: String = _digest()
			app.open_expedition()
			_expect(app.expedition == null and _digest() == before,"blocked UI cannot enter sortie or change stored progress")
		"legacy-continue":
			_expect(app.progress_session==null and app._requires_continue,"ordinary supported legacy save has explicit Continue without registration")
			var original: String = FileAccess.get_sha256(app.run_save.path)
			await _tap(app._continue_button)
			_expect(not app._progress_blocked and not app._requires_continue and FileAccess.get_sha256(app.run_save.path)==original,"legacy Continue/memory migration preserves source bytes")
			_expect(not DirAccess.dir_exists_absolute(app.run_save.path+".txn"),"ordinary legacy Continue never silently registers a journal")
		"legacy-backup":
			_expect(app._progress_blocked and not app._backup_save.is_empty(),"bad legacy main offers only explicit valid backup")
			var original: String = FileAccess.get_sha256(app.run_save.path)
			await _tap(app._backup_button)
			_expect(not app._progress_blocked and FileAccess.get_sha256(app.run_save.path)==original,"explicit backup selection preserves bad original")
		"begin", "in-progress":
			await _enter()
			await _open_map(0)
			if _mode == "in-progress" and app.expedition != null:
				var sortie: Expedition = app.expedition
				var target: FieldActor = sortie.survivors[1]
				sortie.survivors[0].clear_order()
				sortie.survivors[0].position = Vector2(1600,1200)
				var enemy: FieldActor = sortie._make_actor(true,900,target.position+Vector2(36,0))
				sortie.enemies.append(enemy)
				for frame: int in range(120):
					if target.health < 200:
						break
					sortie.step(1.0/60.0)
				var health: Array[Dictionary] = []
				for actor: FieldActor in sortie.survivors:
					health.append({"id":actor.member_id,"health":actor.health})
				var saved: Dictionary = app.progress_session._transaction.checkpoint(app.progress_session.token,health)
				_expect(target.health == 196 and saved.error == OK and saved.receipt.phase == "IN_PROGRESS","real nonlethal AI hit creates actual in-progress checkpoint")
		"edit":
			await _enter()
			await _rename("归航乙")
		"edit-retry":
			await _enter()
			await _tap(app._roster_button)
			app.roster_panel.name_edit.text = "重试甲"
			_fault_point = "before_record_write"
			await _tap(app.roster_panel.save_button)
			_expect(app._progress_dirty and app._progress_blocked and app.crew[0].call_sign!="重试甲","unpublished real edit failure leaves original camp and retained request")
			var identity: String = app.progress_session._pending_edit
			_fault_point = ""
			app.save_camp()
			_expect(not app._progress_blocked and app.crew[0].call_sign=="重试甲" and app.progress_session._pending_edit.is_empty(),"same unpublished edit can explicitly prepare and commit on retry")
			_expect(not identity.is_empty(),"one pending edit identity was retained")
		"prepare-retry":
			await _enter()
			await _sortie(1,false,false,true)
		"insufficient-repair":
			await _insufficient_repair()
		"overwrite":
			await _enter()
			var before: Dictionary = app.camp_snapshot()
			var digest: String = _digest()
			var old_main: String = FileAccess.get_sha256(app.run_save.path)
			var old_backup: String = FileAccess.get_sha256(app.run_save.path+".bak") if FileAccess.file_exists(app.run_save.path+".bak") else ""
			await _tap(app.get_node("Interface/Screen/Title/Reset"))
			await _tap(app._new_game_confirmation.get_cancel_button())
			_expect(_digest() == digest,"overwrite cancellation preserves all live bytes")
			await _tap(app.get_node("Interface/Screen/Title/Reset"))
			await _tap(app._new_game_confirmation.get_ok_button())
			_expect(app.profile_id != before.profile_id and app.day == 2 and not app._progress_blocked,"confirmed fresh journey registers a new identity")
			_expect(_retained_hash(old_main) and (old_backup.is_empty() or _retained_hash(old_backup)),"new journey retains exact original main and valid backup bytes")
			await _rename("换代甲")
			_expect(_retained_hash(old_main) and (old_backup.is_empty() or _retained_hash(old_backup)),"old main and backup survive subsequent new-journey camp save")
		"hold":
			_write(output_dir.path_join("barrier.json"),{"pid":OS.get_process_id(),"point":"session-held"})
			var deadline: int = Time.get_ticks_msec()+45000
			while not FileAccess.file_exists(output_dir.path_join("release")) and Time.get_ticks_msec()<deadline:
				await get_tree().create_timer(0.05).timeout
		"probe": await _probe()
		_:
			_expect(false,"known explicit verification case")
	await _settle()
	await get_tree().create_timer(0.25).timeout
	var state: Dictionary = app.progress_session.inspect() if app.progress_session != null else {"state":"LEGACY","reason":""}
	_write(output_dir.path_join("report.json"),{"checks":_checks,"failures":_failures,"case":_mode,
		"display":DisplayServer.get_name(),"pid":OS.get_process_id(),"camp":app.camp_snapshot(),
		"requires_continue":app._requires_continue,"blocked":app._progress_blocked,"reason":state.get("reason",""),
		"state":state.state,"snapshots":_snapshots,"scope":"real main and UI via viewport events; explicit isolated transaction mode"})
	print("BH_P0_D02A checks=%d failures=%d case=%s display=%s" % [_checks.size(),_failures,_mode,DisplayServer.get_name()])
	get_tree().quit(0 if _failures==0 else 1)


func _business() -> void:
	_expect(not FileAccess.file_exists(app.run_save.path),"fresh actual main has no implicit pre-confirmation write")
	_fault_point = "before_foundation_write"
	await _tap(app._home_button)
	_expect(app._progress_blocked and app._progress_dirty and not FileAccess.file_exists(app.run_save.path),"real new journey failure blocks first sortie before registration")
	app.open_expedition()
	_expect(app.expedition == null,"first-base failure cannot enter expedition")
	var profile: String = app.profile_id
	_fault_point = ""
	await _tap(app._retry_button)
	_expect(not app._progress_blocked and app.profile_id == profile and FileAccess.file_exists(app.run_save.path),"retry signs the same confirmed base")
	_expect(RunSave.new(app.run_save.path).load_save()!=OK,"ordinary v5 entry cannot bypass required namespace")
	var before: String = _digest()
	await _tap(app.get_node("Interface/Screen/Title/Reset"))
	await _tap(app._new_game_confirmation.get_cancel_button())
	_expect(not app._new_game_confirmation.visible,"actual cancel closes new-journey modal")
	_expect(_digest()==before,"new journey cancel is byte-preserving")
	if app._new_game_confirmation.visible:
		return
	await _sortie(0,true)
	var old_token: Dictionary = app.progress_session.token.duplicate(true)
	await _rename("归航甲")
	var stale: Dictionary = app.progress_session._transaction.commit(old_token)
	_expect(stale.error!=OK,"actual rename rejects old sortie callback")
	await _tap(app._loadout_button)
	var panel: LoadoutPanel = app.loadout_panel
	var reward: String = app.profile_id+":1:weapon:north-cache"
	_select_item(panel,reward)
	before = _digest()
	await _tap(panel.repair_button)
	await _tap(panel.confirmation.get_cancel_button())
	_expect(_digest()==before and app.cash==57,"real repair cancel creates no edit or cost")
	await _tap(panel.repair_button)
	await _tap(panel.confirmation.get_ok_button())
	_expect(app.cash==47 and WeaponInventory.find(app.camp_snapshot(),reward).condition=="ready","real repair confirms one cost and one instance")
	await _tap(panel.equip_buttons[0])
	_expect(WeaponInventory.owner(app.camp_snapshot(),reward)==1,"real equip moves unique instance to member1")
	await _tap(panel.equip_buttons[1])
	_expect(WeaponInventory.owner(app.camp_snapshot(),reward)==2 and app.loadout.size()==2,"real exchange retains unique ownership")
	await _tap(panel.back_button)
	await _sortie(1,true)
	before = _digest()
	await _tap(app.get_node("Interface/Screen/Title/Sound"))
	app.sound_settings.sliders.values()[0].value = 73.0
	await _tap(app.sound_settings.save_button)
	_expect(FileAccess.file_exists(app.audio_settings_path) and _digest()==before,"real sound preference save is independent from camp transaction")
	await _tap(app.sound_settings.back_button)
	_expect(app.day==4 and app.cash==51 and app.food==1 and app.weapons.size()==4,"two real sorties conserve complete C outcome after camp edits")
	_expect(SurvivorRoster.member(app.crew,1).call_sign=="归航甲" and SurvivorRoster.member(app.crew,1).service.sorties==2,"Chinese call sign and stable service survive both sorties")
	await _capture("camp-confirmed.png")


func _enter() -> void:
	if app._requires_continue:
		await _tap(app._continue_button)
	elif not app.run_save.has_files():
		await _tap(app._home_button)
	_expect(not app._progress_blocked and not app._requires_continue and app.run_save.has_files(),"real UI reaches registered durable camp")


func _open_map(index: int) -> void:
	await _tap(app.get_node("Interface/Screen/Title/Start"))
	await _tap(app.mission_select.choices[index])
	_expect(app.expedition!=null,"actual map choice starts a signed expedition")
	if app.expedition!=null:
		app.expedition.set_physics_process(false)


func _sortie(index: int, return_now: bool, policy_block_expected: bool = false, retry_prepare: bool = false) -> void:
	var before: Dictionary = app.camp_snapshot()
	await _open_map(index)
	if app.expedition==null:
		return
	var sortie: Expedition = app.expedition
	if retry_prepare:
		_fault_point = "before_record_write"
	sortie.request_search(&"cash")
	for frame: int in range(7200):
		if sortie.searched and sortie.kills>0:
			break
		sortie.step(1.0/60.0)
		if frame%120==0:
			await get_tree().process_frame
	_expect(sortie.searched and sortie.kills>0,"actual search and enemy AI combat map="+str(index))
	if index==1:
		sortie.request_search(&"food")
		var hidden: bool = false
		for frame: int in range(7200):
			if sortie.search_actor!=null and sortie.search_actor.activity==FieldActor.Activity.SEARCHING:
				hidden = hidden or not sortie.search_actor.visible
			if sortie.search_site(&"food").searched:
				break
			sortie.step(1.0/60.0)
			if frame%120==0:
				await get_tree().process_frame
		_expect(hidden and sortie.food_loot==3,"actual food worker hides, completes and carries real source amount")
	sortie.toggle_pause()
	var elapsed: float = sortie.elapsed
	sortie.request_extraction()
	sortie.step(1.0)
	_expect(sortie.elapsed==elapsed and sortie.phase==Expedition.Phase.ENGINE,"pause freezes clock and engine while explicit order is accepted")
	sortie.toggle_pause()
	for frame: int in range(190):
		sortie.step(1.0/60.0)
	sortie.request_bus_gather()
	for frame: int in range(7200):
		if sortie.phase==Expedition.Phase.FINISHED:
			break
		sortie.step(1.0/60.0)
		if frame%120==0:
			await get_tree().process_frame
	if policy_block_expected:
		_expect(app.phase==app.Phase.RESULT and app._pending_settlement.is_empty() and app._progress_blocked and TransactionReceipt.same(before,app.camp_snapshot()),"real shortage blocks without H50/random victim/economy application")
		await _capture("shortage-policy-required.png")
		return
	if retry_prepare:
		_expect(app._pending_settlement.is_empty() and app._progress_dirty and not app.progress_session.packet.is_empty(),"complete result retained after failed preparation with retry UI")
		var original: String = app.progress_session.packet.envelope.result_hash
		_fault_point = ""
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_expect(not app._progress_blocked and app.day==before.day+1 and app.progress_session.packet.envelope.result_hash==original,"explicit Return retries the same frozen packet and commits once")
		return
	_expect(app.phase==app.Phase.RESULT and not app._pending_settlement.is_empty(),"real gathering yields complete prepared result")
	if app._pending_settlement.is_empty():
		return
	var packet: Dictionary = app.progress_session.packet
	_expect(FrozenSettlement.validate(packet).is_empty() and packet.envelope.result.scope==FrozenSettlement.FOUNDATION,"real result is complete validated foundation C packet")
	_expect(TransactionReceipt.same(before,app.camp_snapshot()),"RESULT_READY has not prematurely changed memory camp")
	_write(output_dir.path_join("map-"+str(index)+"-packet.json"),packet)
	_snapshots.append({"map":index,"before":before,"after":packet.envelope.result.camp,"result_hash":packet.envelope.result_hash})
	await _capture("map-"+str(index)+"-result.png")
	if return_now:
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_expect(not app._progress_blocked and TransactionReceipt.same(app.camp_snapshot(),packet.envelope.result.camp),"actual Return commits exact frozen after once")
		_expect(app.progress_session.inspect().state=="CAMP","committed result and binding acknowledged")


func _rename(value: String) -> void:
	await _tap(app._roster_button)
	app.roster_panel.name_edit.text = value
	await _tap(app.roster_panel.save_button)
	_expect(SurvivorRoster.member(app.crew,1).call_sign==value,"actual roster save uses coordinated edit")
	await _tap(app.roster_panel.back_button)


func _insufficient_repair() -> void:
	# Synthetic low-cash initial state, then all actions use the real main and confirmation UI.
	var before: Dictionary = app.camp_snapshot()
	before.cash = 1
	_expect(app._accept_transaction(app.progress_session.create(before)),"isolated low-cash base registered by production owner")
	await _sortie(0,true)
	await _tap(app._loadout_button)
	var panel: LoadoutPanel = app.loadout_panel
	_select_item(panel,app.profile_id+":1:weapon:north-cache")
	var digest: String = _digest()
	await _tap(panel.repair_button)
	await _tap(panel.confirmation.get_ok_button())
	_expect(app.cash==5 and not app._progress_blocked and not app._progress_dirty and _digest()==digest and app.progress_session._pending_edit.is_empty(),"insufficient real repair is a business refusal, not a stuck transaction")


func _probe() -> void:
	_expect("--bh-txn-death-probe" in OS.get_cmdline_user_args(),"death probe explicitly enabled in isolated main")
	var base: Dictionary = app.camp_snapshot()
	base.crew[1].health = 4.0
	# Explicit low-HP fixture. Ordinary new-journey UI tests are separate.
	_expect(app._accept_transaction(app.progress_session.create(base)),"isolated 4HP fixture uses the same production owner")
	await _open_map(1)
	if app.expedition==null:
		return
	var sortie: Expedition = app.expedition
	var target: FieldActor = sortie.survivors[1]
	sortie.survivors[0].clear_order()
	sortie.survivors[0].position = Vector2(1600,1200)
	var enemy_start: Vector2 = target.position+Vector2(36,0)
	var enemy: FieldActor = sortie._make_actor(true,900,enemy_start)
	sortie.enemies.append(enemy)
	var hits: Array[Dictionary] = []
	sortie.combat_feedback.connect(func(event: Dictionary) -> void:
		if event.kind=="hit":
			hits.append(event.duplicate(true)))
	_fault_point = "before_record_write"
	for frame: int in range(120):
		if sortie.is_paused:
			break
		sortie.step(1.0/60.0)
	_expect(sortie.is_paused and target.health==4 and hits.is_empty() and target.damage_received==0,"real rejected lethal checkpoint leaves 4HP and no hit")
	_expect(enemy.position.distance_to(enemy_start)>1.0,"real enemy navigates into original legal melee range")
	await _capture("probe-blocked-4hp.png")
	_fault_point = ""
	sortie.toggle_pause()
	sortie.step(1.0/60.0)
	_expect(target.health==0 and target.damage_received==4 and hits.size()==1,"successful checkpoint precedes one actual lethal hit")
	_expect(app.progress_session.inspect().error!=OK,"actual main owner will not Continue from old camp after confirmed death")
	await _capture("probe-confirmed.png")


func _tap(button: BaseButton) -> void:
	_expect(button.is_visible_in_tree() and not button.disabled,"viewport control available: "+String(button.name))
	if button.get_viewport()!=get_viewport():
		button.grab_focus()
		for pressed: bool in [true,false]:
			var key: InputEventKey = InputEventKey.new()
			key.keycode = KEY_ENTER
			key.physical_keycode = KEY_ENTER
			key.pressed = pressed
			button.get_viewport().push_input(key,true)
			await get_tree().process_frame
		await _settle()
		return
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true,false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		button.get_viewport().push_input(event,true)
		await get_tree().process_frame
	await _settle()


func _select_item(panel: LoadoutPanel, identity: String) -> void:
	for index: int in range(panel.items.item_count):
		if panel.items.get_item_metadata(index)==identity:
			panel.items.select(index)
			panel.items.item_selected.emit(index)
			return
	_expect(false,"real reward item exists in actual inventory list")


func _fault(point: String) -> Error:
	if point==_fault_point:
		return ERR_CANT_CREATE
	var matches: bool = point==_barrier and not _barrier.is_empty()
	if _barrier in ["ready-published","edit-published"] and point=="after_record_publish":
		var readback: Dictionary = ReceiptJournal.new(app.run_save.path+".txn/journal").read_all()
		matches = readback.error==OK and readback.receipt.phase==("RESULT_READY" if _barrier=="ready-published" else "EDIT_READY")
	if matches:
		_write(output_dir.path_join("barrier.json"),{"pid":OS.get_process_id(),"point":_barrier})
		var deadline: int = Time.get_ticks_msec()+45000
		while Time.get_ticks_msec()<deadline:
			OS.delay_msec(10)
	return OK


func _digest() -> String:
	var files: Dictionary = {}
	for suffix: String in ["",".bak",".txn/binding.json"]:
		files[suffix] = FileAccess.get_sha256(app.run_save.path+suffix) if FileAccess.file_exists(app.run_save.path+suffix) else "MISSING"
	var log: Dictionary = ReceiptJournal.new(app.run_save.path+".txn/journal").read_all()
	files.head = log.get("hash","")
	return SurvivalContracts.fingerprint(files)


func _retained_hash(expected: String) -> bool:
	var folder: DirAccess = DirAccess.open(app.run_save.path.get_base_dir())
	for name: String in folder.get_files():
		if name.begins_with("run.txn-v1.json") and FileAccess.get_sha256(app.run_save.path.get_base_dir().path_join(name))==expected:
			return true
	return false


func _capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":
		return
	await _settle()
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(name))


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _expect(value: bool, label: String) -> void:
	_checks.append({"passed":value,"label":label})
	if not value:
		_failures += 1
		push_error(label)


func _write(path: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t",true,true)+"\n")
	file.close()
