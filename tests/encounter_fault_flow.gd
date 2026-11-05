extends "res://tests/campaign_flow.gd"
## R1 replays an existing genuine synthetic checkpoint; never starts preparation actions.
var fault_mode:String="zero"
var fault:Dictionary={"fired":false,"calls":0,"block":true,"request_id":"","member_id":0}
var attempts:Array[Dictionary]=[]

func _journey() -> void:
	_check(false,"R1 requires an existing isolated checkpoint")

func _resume() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--r1-mode="):fault_mode=arg.trim_prefix("--r1-mode=")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	if fault_mode=="readback":
		var prior:String="zero" if FileAccess.file_exists(output.get_base_dir().path_join("zero/report.json")) else "partial"
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(prior+"/report.json")))
		_check(expected.pid!=OS.get_process_id() and TransactionReceipt.same(expected.camp,app.camp_snapshot()),"new PID restores exact confirmed camp including one XP award")
		_check(app.camp_snapshot().journey.campaign.outcome=="VICTORY" and app.progress_session.inspect().state=="ENDED","R1 victory persists in a new process")
		app.open_expedition()
		_check(app.expedition==null,"ended R1 journey cannot start another action")
		return
	var world:Expedition=app.expedition
	_check(world!=null,"normal continue reconstructs genuine boss checkpoint")
	if world==null:return
	world.set_physics_process(false);world.set_process(false)
	world.combat_feedback.connect(func(event:Dictionary)->void:events.append(event.duplicate(true)))
	_check(world.encounter.health()>0 and world.is_paused,"restored live boss waits for normal resume")
	var originals:Dictionary={}
	for member:FieldActor in world.survivors:
		originals[member.member_id]=member.damage_gate
		member.damage_gate=func(target:FieldActor,proposal:Dictionary)->Error:
			var runtime:EncounterRuntime=world.encounter
			if not runtime.handling.is_empty():attempts.append({"elapsed":world.elapsed,"boss_health":runtime.health(),"member_id":target.member_id,"handling":runtime.handling.duplicate(true),"pending":runtime.behavior.snapshot().pending})
			var low:bool=runtime.health()<=18.0 if fault_mode=="zero" else true
			var part:bool=runtime.handling.get("hits",[]).size()==1 if fault_mode in ["partial","retry"] else true
			var current:String=runtime.handling.get("request_id","")
			var pending:Array=runtime.behavior.snapshot().pending.filter(func(request:Dictionary)->bool:return request.id==current)
			var boss_damage:bool=not pending.is_empty() and proposal.health_before-proposal.health_after==(BossDefinition.POLICY.melee_damage if pending[0].kind=="melee" else BossDefinition.POLICY.slam_damage)
			var continuing:bool=current==fault.request_id and target.member_id==fault.member_id
			if fault.block and boss_damage and ((not fault.fired and part and low) or continuing):
				fault.fired=true;fault.calls+=1;fault.request_id=current;fault.member_id=target.member_id
				return ERR_CANT_OPEN
			return originals[target.member_id].call(target,proposal)
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:world.toggle_pause()
	if fault_mode in ["partial","retry"]:
		for member:FieldActor in world.survivors:member.clear_order()
	for index:int in range(6000):
		if fault.fired or world.phase==Expedition.Phase.FINISHED or not world.encounter.defeat.is_empty():break
		if fault_mode in ["partial","retry"] and index>=21 and index%15==0:_cluster(world)
		world.step(1.0/30.0)
		if index%30==0:await _frame()
	_write("attempts.json",{"attempts":attempts})
	_check(fault.fired and world.is_paused and not world.encounter.handling.is_empty(),"one real boss damage submission fails and retains handling")
	if not fault.fired:
		for member:FieldActor in world.survivors:member.damage_gate=originals[member.member_id]
		return
	for member:FieldActor in world.survivors:member.clear_order()
	var before:Dictionary=world.encounter.snapshot()
	var health:Array=world.survivors.map(func(member:FieldActor)->float:return member.health)
	var hit_count:int=world.encounter.handling.hits.size()
	_check(hit_count==(1 if fault_mode in ["partial","retry"] else 0),"requested zero/partial application actually reached")
	app.open_pause_menu()
	var paused:Dictionary=SortieSnapshot.capture(world)
	var live_preview:Dictionary=app.progress_session.preview_suspend(paused)
	_check(live_preview.error==OK,"failed live attack remains a valid original suspend candidate: "+String(live_preview.get("reason","")))
	_write("fault.json",{"before":before,"world":paused,"health":health,"elapsed":world.elapsed,"mode":fault_mode})
	app.close_pause_menu()
	if world.is_paused:world.toggle_pause()
	if fault_mode=="retry":
		fault.block=false
		for member:FieldActor in world.survivors:member.damage_gate=originals[member.member_id]
		world.encounter.advance(0.0)
		_check(world.encounter.handling.is_empty() and world.encounter.behavior.snapshot().pending.is_empty(),"live retry acknowledges the same attack")
		_check(world.survivors[0].health==health[0] and world.survivors[1].health==health[1]-BossDefinition.POLICY.slam_damage,"applied member is skipped and remaining member hit once")
		return
	# Retry the same unavailable submission at normal 30Hz. Release the fault
	# when an original, legal fatal shot is due in the next simulation step.
	var event_start:int=events.size()
	for tick:int in range(900):
		if not world.encounter.defeat.is_empty() or world.phase==Expedition.Phase.FINISHED:break
		if world.is_paused:world.toggle_pause()
		for member:FieldActor in world.survivors:
			if member.health>0 and member.cooldown<=1.0/30.0 and member.magazine.can_fire() and member.weapon_definition.damage>=world.encounter.health() and world._attack_target(member)==world.encounter.actor:
				_check(world.encounter.handling.get("request_id","")==fault.request_id and not world.encounter.behavior.snapshot().pending.is_empty(),"same unacknowledged request remains until the fatal step")
				_write("before-fatal.json",{"encounter":world.encounter.snapshot(),"health":world.survivors.map(func(actor:FieldActor)->float:return actor.health),"elapsed":world.elapsed,"fault_calls":fault.calls})
				fault.block=false
		world.step(1.0/30.0)
		if tick%30==0:await _frame()
	for member:FieldActor in world.survivors:member.damage_gate=originals[member.member_id]
	_check(not fault.block,"submission fault is released before the fatal normal step")
	_check(events.slice(event_start).all(func(event:Dictionary)->bool:return event.get("attack_id","")!=fault.request_id),"cancelled request produces no further hit events")
	_check(not world.encounter.defeat.is_empty(),"resumed 30Hz original combat defeats boss before pending effect retry")
	_check(world.survivors.map(func(member:FieldActor)->float:return member.health)==health,"boss death does not apply the cancelled damage")
	_check(world.encounter.handling.is_empty() and world.encounter.behavior.snapshot().pending.is_empty(),"real death ends pending and handling together")
	app.open_pause_menu()
	var after:Dictionary=SortieSnapshot.capture(world)
	var problem:String=EncounterRuntime.facts_problem(after.encounter,after.generated,after.xp_inputs)
	_check(problem.is_empty(),"post-defeat original snapshot validates: "+problem)
	var preview:Dictionary=app.progress_session.preview_suspend(after)
	_check(preview.error==OK,"post-defeat original suspend preview accepts terminal facts: "+String(preview.get("reason","")))
	_write("terminal.json",{"world":after,"validation":problem,"preview_reason":preview.get("reason",""),"fault_calls":fault.calls})
	if not problem.is_empty():
		app.close_pause_menu()
		if world.is_paused:world.toggle_pause()
		await _extract(world)
		_check(not app._pending_settlement.is_empty(),"original bus return must freeze after terminal cancellation")
		_write("return-rejection.json",{"message":app._progress_message,"blocked":app._progress_blocked})
		return
	app.suspend_sortie();await _hold(3)
	_check(app.expedition==null and app._requires_continue,"post-defeat snapshot is actually persisted")
	await _tap(app._continue_button)
	world=app.expedition
	_check(world!=null,"same process can continue acknowledged terminal snapshot")
	if world==null:return
	world.set_physics_process(false);world.set_process(false)
	_check(RecordEncoding.fingerprint(SortieSnapshot.capture(world))==RecordEncoding.fingerprint(after),"post-defeat world restores exactly without extra damage or XP")
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:world.toggle_pause()
	await _extract(world)
	_check(not app._pending_settlement.is_empty() and not app._progress_blocked,"original return freezes a valid victory result")
	if app._pending_settlement.is_empty():return
	var xp:int=app.progress_session.packet.envelope.result.battle.xp_inputs.events.filter(func(event:Dictionary)->bool:return event.enemy_id==0).size()
	_check(xp==1,"fatal-shot owner contributes one boss XP input")
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(app.camp_snapshot().journey.campaign.outcome=="VICTORY","original explicit return confirmation durably wins")
	var saved:Dictionary=app.camp_snapshot()
	app.return_to_title()
	_check(TransactionReceipt.same(saved,app.camp_snapshot()),"duplicate confirmation cannot repeat damage death or XP")

func _cluster(world:Expedition) -> void:
	var center:Vector2=world.encounter.actor.position+Vector2(-120,80)
	for index:int in range(world.survivors.size()):
		var point:Vector2=center+Vector2(index*28,0)
		if world.navigation.is_clear(point):world.survivors[index].command_path(world.navigation.path_between(world.survivors[index].position,point))
