class_name RecordHashPlaytest
extends EnemyPlaytest
## Reuse the original camp/transaction drivers in the current task's isolated namespace.

var _pre_death_anchor: Dictionary = {}
var _death_id: int = 0


func _task_path() -> String:
	return "/.local/p0-record-hash-02/"


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--camp-case="): camp_case = argument.trim_prefix("--camp-case=")
	if camp_case not in ["hash-rescue","hash-death-replace"]:
		await super._run()
		return
	if not output_dir.is_absolute_path() or _task_path() not in output_dir.replace("\\","/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _settle()
	await _enter()
	_initial = app.camp_snapshot()
	if camp_case == "hash-rescue":
		var count: int = RosterState.living_count(_initial)
		await _rescue_outing()
		_expect(RosterState.living_count(app.camp_snapshot()) == count+1,"real rescue adds exactly one living member through existing owner")
	else:
		_expect(_initial.crew.size() == 4 and RosterState.living_count(_initial) == 4,"death case requires two completed real rescues and four living members")
		if _failures > 0:
			await _finish_camp()
			return
		_death_id = int(_initial.crew[2].id)
		app.survival_pilot = false
		await _open_map(1)
		var world: Expedition = _watch_world()
		await _field_death(world,_death_id)
		if _failures > 0:
			await _finish_camp()
			return
		await _field_search(world)
		await _field_bus(world)
		var dead: Dictionary = app.camp_snapshot()
		_expect(SurvivorRoster.member(dead.crew,_death_id).get("health",-1) == 0 and RosterState.living_count(dead) == 3,"actual AI death reaches acknowledged camp with original stable identity")
		_reports.clear()
		_initial = dead
		app.survival_pilot = true
		await _rescue_outing()
		var replaced: Dictionary = app.camp_snapshot()
		_expect(replaced.crew.size() == 5 and RosterState.living_count(replaced) == 4,"real replacement produces five history and four living")
		_expect(RecordEncoding.fingerprint(SurvivorRoster.member(replaced.crew,_death_id)) == RecordEncoding.fingerprint(SurvivorRoster.member(dead.crew,_death_id)),"rescue never rewrites dead identity health service or growth")
		# Real kills can cap the new recruit's trait before camp. Select a living
		# eligible identity through the original quote policy, never lower a level.
		var training_id: int = 0
		for member: Dictionary in replaced.crew:
			if String(TrainingRules.preview(replaced,int(member.id)).get("error","unavailable")).is_empty() and (training_id==0 or int(member.id)<training_id): training_id = int(member.id)
		_expect(training_id>0,"post-death camp has a living training owner accepted by original quote policy")
		_write(output_dir.path_join("training-owner.json"),{"recruit_id":candidate,"training_id":training_id,"policy":"lowest eligible stable ID; no health, trait, level or food injection"})
		if training_id>0: await _train_member(training_id)
		var edited: Dictionary = app.progress_session.edit(app.camp_snapshot(),{"kind":"rename","member_id":1,"value":"精确回读"})
		_expect(edited.error == OK and app._accept_transaction(edited,true),"post-death training and rename commit through original camp owner")
		_expect(not _pre_death_anchor.is_empty(),"death priority actually exercised a consumed pre-death world")
	await _finish_camp()


func _field_death(world: Expedition, id: int) -> void:
	# Exercise a real consumed anchor before the inherited, explicitly labelled AI death fixture.
	if not world.is_paused:
		await _key_battle(KEY_SPACE)
	var snapshot: Dictionary = SortieSnapshot.capture(world)
	var saved: Dictionary = app.progress_session.suspend_world(snapshot)
	_expect(saved.error == OK,"pre-death authoritative world publishes exact suspend: "+str(saved.get("reason","")))
	if saved.error != OK:
		return
	if saved.error == OK:
		_pre_death_anchor = {"token":RunTransaction.token_for(saved.receipt),"hash":saved.receipt.envelope.world_hash,"generation":saved.receipt.envelope.previous_head,"world":snapshot}
		_write(output_dir.path_join("pre-death-anchor.json"),{"token":_pre_death_anchor.token,"hash":_pre_death_anchor.hash,"generation":_pre_death_anchor.generation})
		var file: FileAccess = FileAccess.open(output_dir.path_join("pre-death-world.exact.json"),FileAccess.WRITE)
		file.store_string(RecordEncoding.stringify(snapshot))
		file.close()
		_expect(app.progress_session.claim_world(_pre_death_anchor.hash).error == OK,"same live owner acknowledges pre-death anchor before continuing")
	if world.is_paused:
		await _key_battle(KEY_SPACE)
	await _isolated_death_stance(world,id)
	_reject_pre_death("confirmed death")


func _isolated_death_stance(world: Expedition, id: int) -> void:
	# The old fixture disabled all four guns while waiting for one AI death.
	# Dynamic contact can hold bystanders in danger. Keep their real defence,
	# and walk the designated subject beyond their actual weapon ranges instead.
	if world.drill_panel != null: world.drill_panel.queue_free()
	world.battle_drill = true
	world.drill_panel = BattleDrillPanel.new()
	world.drill_panel.expedition = world
	world._hud.view.add_child(world.drill_panel)
	await _settle()
	var target: FieldActor = world.drill_panel._member(id)
	_expect(target != null,"contact death fixture retains designated stable ID")
	if target == null: return
	var reach: float = 0.0
	for actor: FieldActor in world.survivors:
		if actor != target: reach = maxf(reach,actor.weapon_definition.shot_range)
	var destination: Vector2 = Vector2.INF
	var nearest: float = INF
	for x: int in range(104,1800,64):
		for y: int in range(104,1320,64):
			var point: Vector2 = Vector2(x,y)
			if point.distance_to(world.layout.bus_door)<reach+180.0 or not world.navigation.is_clear(point): continue
			if not world.navigation.is_clear(point+Vector2(36,0)) or world.navigation.path_between(target.position,point).is_empty(): continue
			if point.distance_squared_to(target.position)<nearest:
				destination = point
				nearest = point.distance_squared_to(target.position)
	_expect(destination.is_finite(),"designated AI death has a reachable legal stance beyond bystander weapon range")
	if not destination.is_finite(): return
	world.command_move(world.layout.bus_door)
	target.command_path(world.navigation.path_between(target.position,destination))
	target.cooldown = 999.0
	for actor: FieldActor in world.survivors:
		if actor != target: actor.cooldown = 0.0
	for frame: int in range(1200):
		if target.permanent_death or target.position.distance_to(destination)<FieldNavigation.CELL: break
		await _step(world)
	_expect(target.permanent_death or target.position.distance_to(destination)<FieldNavigation.CELL,"designated subject really walks to the isolated stance without teleporting")
	_write(output_dir.path_join("death-stance.json"),{"member_id":id,"destination":[destination.x,destination.y],"position":[target.position.x,target.position.y],"bystander_range":reach,"health":target.health,"method":"original paths; only subject fire suppressed; bystanders defend normally; no health or damage changes"})
	if not target.permanent_death:
		for button: Button in world.drill_panel.buttons:
			if int(button.get_meta("member_id")) == id: await _tap(button)
		for frame: int in range(6000):
			if target.permanent_death: break
			await _step(world)
	_expect(target.permanent_death and target.health == 0,"original AI and death writer confirm designated identity, no direct health mutation")
	_expect(world.boarding_status().required == world.living_count(),"bus immediately removes confirmed death from required occupants")
	for actor: FieldActor in world.survivors: actor.cooldown = 0.0
	await _capture("confirmed-death.png")


func _reject_pre_death(stage: String) -> void:
	if _pre_death_anchor.is_empty(): return
	var before: String = _digest()
	var transaction: RunTransaction = app.progress_session._transaction
	_expect(transaction.claim_suspend(_pre_death_anchor.token,_pre_death_anchor.hash,_pre_death_anchor.generation).error != OK,stage+" refuses old pre-death claim")
	_expect(transaction.suspend(_pre_death_anchor.token,_pre_death_anchor.world).error != OK,stage+" refuses pre-death world rewind")
	_expect(before == _digest(),stage+" old world cannot change confirmed journal/camp bytes")


func _finish_camp() -> void:
	_reject_pre_death("later rescue and camp edits")
	var file: FileAccess = FileAccess.open(output_dir.path_join("camp.expected.exact.json"),FileAccess.WRITE)
	file.store_string(RecordEncoding.stringify(app.camp_snapshot()))
	file.close()
	await super._finish_camp()
