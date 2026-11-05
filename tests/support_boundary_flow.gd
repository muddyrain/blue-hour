extends "res://tests/combat_flow.gd"
# R1 controlled geometry on an original authenticated synthetic checkpoint.
# No HP, death, inventory, enemy kind, or receipt mutations.
func _resume()->void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	var w:Expedition=app.expedition
	_check(w!=null,"authenticated checkpoint continues")
	if w==null:return
	w.set_physics_process(false);w.set_process(false)
	if app.pause_menu.visible:await _tap(app.pause_menu.buttons[0])
	if w.is_paused:w.toggle_pause()
	if output.get_file()=="boss":
		await boss_boundary(w)
		return
	var a:FieldActor=w.survivors[0];var b:FieldActor=w.survivors[1]
	var caster:FieldActor=null;var target:FieldActor=null
	for e:FieldActor in w.enemies:
		if e.enemy_behavior.kind==CombatEnemyRules.TOXIC:caster=e
		else:target=e
	_check(caster!=null and target!=null and a.weapon_definition.id==&"fire_axe_v1","natural toxic source, target and legitimately equipped axe retained")
	if caster==null or target==null:return
	var point:Vector2=SortieSnapshot._vec(w.combat.toxic.zones[0].point)
	a.clear_order();b.clear_order();a.position=point;b.position=point+Vector2(20,0)
	for e:FieldActor in w.enemies:e.clear_order();e.position=point+Vector2(190,0)
	caster.position=point+Vector2(150,0)
	w.combat.attack(w,a,1.0);a.advance(10.0,false,false)
	for i:int in range(30000):
		if b.health<b.max_health:b.position=point+Vector2(-140,0)
		var projected:Dictionary=ToxicV1.plan(w.combat.toxic,0.01,w.combat.rows([caster]),w.combat.rows(w.survivors),w.shot_obstacles)
		if a.health<=6.0 and projected.hits.any(func(h:Dictionary)->bool:return h.member_id==a.member_id):break
		w.elapsed+=0.01;w.basic_support.advance(0.01,true);w.combat.advance_toxic(w,0.01)
		if w.is_paused or a.health<=0:break
	_check(a.health>0 and a.health<=6 and b.health>0 and b.health<b.max_health,"real toxic ticks prepare lethal boundary and injured living companion")
	target.position=point+Vector2(40,0)
	w.step(0.0)
	var lethal:Dictionary={}
	var original:Callable=a.damage_gate
	a.damage_gate=func(actor:FieldActor,proposal:Dictionary)->Error:
		if proposal.health_after==0:lethal.merge({"windup":w.combat.action(actor).remaining,"before":actor.health})
		return original.call(actor,proposal) as Error
	var receipt:Dictionary=app.progress_session._transaction.recover().receipt
	print("R1_LATE pre hp=",a.health," companion=",b.health," remaining=",w.combat.action(a).remaining," snapshot=",SortieSnapshot.problem(capture(w),receipt))
	w.step(0.01)
	_check(lethal.get("windup",0.0)>0,"actual lethal gate observes unfinished axe windup in late toxic phase")
	print("R1_LATE lethal_gate=",lethal)
	var raw:Dictionary=capture(w)
	receipt=app.progress_session._transaction.recover().receipt
	var issue:String=SortieSnapshot.problem(raw,receipt)
	_check(a.health==0 and a.permanent_death and b.health>0,"same actual step commits lethal ToxicV1 damage through PersistedDamageGate")
	var accepted:bool=w.request_heal() # No intervening step, pause or cleanup.
	print("R1_LATE post issue=",issue," accepted=",accepted," remaining=",w.combat.action(w.survivors[0]).remaining," paused=",w.is_paused," pending=",w.pending_support.keys())
	_write("boundary.json",{"raw":raw,"issue":issue,"accepted":accepted,"pending":w.pending_support,"receipt":receipt,"events":events})
	_check(accepted and w.pending_support.is_empty() and not w.is_paused,"immediate same-step heal accepts after late lethal damage")
	if not accepted:
		var frozen:String=RecordEncoding.fingerprint(w.pending_support.before)
		w.toggle_pause()
		print("R1_LATE retry immutable=",RecordEncoding.fingerprint(w.pending_support.before)==frozen," reason=",SortieSnapshot.problem(w.pending_support.before,receipt))
		return
	var final:Dictionary=capture(w)
	_check(SortieSnapshot.problem(final,app.progress_session._transaction.recover().receipt).is_empty(),"strict snapshot remains valid after support")
	_write("checkpoint.json",{"encoded":RecordEncoding.stringify(final),"fingerprint":RecordEncoding.fingerprint(final),"pid":OS.get_process_id()})
	app.open_pause_menu();app.suspend_sortie();await _hold(3)
	_check(app.expedition==null and app._requires_continue,"original suspend publishes cleaned boundary")

func boss_boundary(w:Expedition)->void:
	await _extract(w)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	await _menu(4)
	w=await _start(0)
	if w==null:return
	var a:FieldActor=w.survivors[0];var b:FieldActor=w.survivors[1]
	var boss:FieldActor=w.encounter.actor
	var point:Vector2=boss.position+Vector2(40,0)
	a.clear_order();b.clear_order();a.position=point;b.position=point+Vector2(15,0)
	for i:int in range(10000):
		if b.health<b.max_health:b.position=point+Vector2(700,0)
		var state:Dictionary=w.encounter.behavior.snapshot()
		if a.health<=32.0 and state.state=="slam_windup" and state.remaining<=0.01:break
		w.elapsed+=0.01;w.basic_support.advance(0.01,true);w.encounter.advance(0.01)
	_check(a.health>0 and a.health<=32 and b.health>0 and b.health<b.max_health,"real boss requests prepare lethal slam and injured living companion")
	a.advance(10.0,false,false)
	w.combat.attack(w,a,0.0)
	var lethal:Dictionary={};var original:Callable=a.damage_gate
	a.damage_gate=func(actor:FieldActor,proposal:Dictionary)->Error:
		if proposal.health_after==0:lethal.merge({"windup":w.combat.action(actor).remaining,"before":actor.health})
		return original.call(actor,proposal) as Error
	w.step(0.01)
	_check(a.health==0 and a.permanent_death and lethal.get("windup",0.0)>0,"actual late boss slam commits permanent death during axe windup")
	var accepted:bool=w.request_heal()
	print("R1_BOSS lethal=",lethal," accepted=",accepted," pending=",w.pending_support.keys())
	_write("boss-boundary.json",{"lethal":lethal,"accepted":accepted,"pending":w.pending_support,"receipt":app.progress_session._transaction.recover().receipt})
	_check(accepted and not w.is_paused and w.pending_support.is_empty(),"immediate support accepts after equivalent late boss death")

func capture(w:Expedition)->Dictionary:
	var paused:bool=w.is_paused;w.is_paused=true
	var value:Dictionary=SortieSnapshot.capture(w)
	w.is_paused=paused;return value
