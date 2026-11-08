extends "res://tests/campaign_flow.gd"
## R1 viewport input regression; the separately recorded release EXE covers Win32 input.
func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _tap(app.camp_scene.hotspots[&"bus"])
	var w: Expedition=await _start(0)
	if w==null:return
	var scroll: InputEventMouseButton=InputEventMouseButton.new()
	scroll.button_index=MOUSE_BUTTON_WHEEL_DOWN;scroll.pressed=true;scroll.position=Vector2(640,360)
	for i: int in range(5):viewport.push_input(scroll,true);await _frame()
	_check(w.camera.zoom.x>=0.7,"minimum float32 camera zoom satisfies strict snapshot bound")
	var target: Vector2=w.survivors[0].position-Vector2(80,0)
	var preview: Dictionary=w.support_plan_airstrike(target)
	var authoritative: Dictionary=BuildAuthority.plan_airstrike(w.support_world(),target)
	_check(not preview.is_empty() and TransactionReceipt.same(preview,authoritative),"reused field grid previews the same reachable ground as confirmation")
	await key(KEY_E)
	_check(w.support_aiming,"E enters aiming")
	await key(KEY_ESCAPE)
	_check(not w.support_aiming and w.basic_support.snapshot().sequence==0,"cancel has no effect or cooldown")
	await key(KEY_E)
	await click(w,Vector2(-100,-100))
	_check(not w.is_paused and w.support_aiming and w.basic_support.snapshot().sequence==0 and w.basic_support.remaining("airstrike")==0.0,"invalid target leaves aiming and cooldown intact")
	_check("空袭无法落在此处" in w._notice_text and w.support_aim._impact_remaining==0.0,"invalid target shows an actionable notice without impact")
	await click(w,target)
	_check(not w.is_paused and w.pending_support.is_empty() and w.basic_support.snapshot().sequence==1,"E then valid left click accepts once at minimum zoom")
	_check(w.basic_support.remaining("airstrike")==20.0,"empty-ground strike consumes exactly one normal cooldown")
	_check(not w.support_aim._aiming and w.support_aim._impact_remaining==BasicSupportAim.IMPACT_SECONDS and w._notice_text=="空袭已落地","confirmed empty-ground strike immediately replaces aiming with landing feedback")
	await key(KEY_E)
	_check(not w.support_aiming and not w.request_airstrike(target) and w.basic_support.snapshot().sequence==1,"cooldown repeated inputs cannot accept another strike")
	var elapsed: float=w.elapsed
	for i: int in range(601):w.step(1.0/30.0)
	_check(w.elapsed>elapsed and not w.is_paused,"simulation continues after accepted support")
	_check(not w.enemies.is_empty(),"original spawn owner supplies a real enemy")
	if w.enemies.is_empty():return
	# Controlled geometry only: actual natural identity/HP/source and all commit owners remain.
	var enemy: FieldActor=w.enemies[0]
	target=w.survivors[0].position
	enemy.clear_order();enemy.position=target+Vector2(20,0)
	var hp: float=enemy.health
	var id: int=enemy.actor_id
	var kills: int=w.kills
	var xp: int=w.xp_inputs.events.size()
	var fired: Dictionary={"once":false}
	app.progress_session.fault_hook=func(point:String)->Error:
		if point=="after_record_flush" and not fired.once:fired.once=true;return ERR_CANT_CREATE
		return OK
	await key(KEY_E)
	await click(w,target)
	_check(fired.once and w.is_paused and not w.pending_support.is_empty(),"actual airstrike publication failure freezes its original request")
	_check(w.basic_support.snapshot().sequence==1 and enemy.health==hp and w.kills==kills,"failure exposes no unconfirmed damage/cooldown/kills")
	_check(w.support_aim._impact_remaining==0.0,"failed publication shows no confirmed impact")
	var frozen: String=RecordEncoding.fingerprint(w.pending_support.before)
	app.progress_session.fault_hook=Callable()
	w.toggle_pause()
	_check(not w.is_paused and w.pending_support.is_empty() and w.basic_support.snapshot().sequence==2,"retry accepts exactly the frozen second request")
	_check(w.kills==kills+1 and w.xp_inputs.events.size()==xp+1 and not w.enemies.any(func(e:FieldActor)->bool:return e.actor_id==id),"confirmed strike kills real target and awards XP exactly once")
	_check(w.support_aim._impact_remaining==BasicSupportAim.IMPACT_SECONDS and "空袭命中" in w._notice_text,"confirmed hit presents impact and target feedback on retry")
	var state: Dictionary=w.basic_support.snapshot()
	_check(state.accepted.back().facts.targets.any(func(f:Dictionary)->bool:return f.enemy_id==id and f.health_before==hp and f.health_after==0),"durable target facts retain real HP before and after")
	_check(not w.request_airstrike(target) and w.kills==kills+1 and w.xp_inputs.events.size()==xp+1,"post-retry repeat cannot replay damage or XP")
	_write("support-state.json",{"support":state,"failed_before_fingerprint":frozen,"kills":w.kills,"xp":w.xp_inputs.snapshot(w),"pending":w.pending_support})

func key(code: Key) -> void:
	var event: InputEventKey=InputEventKey.new();event.keycode=code;event.pressed=true
	viewport.push_input(event,true);await _frame()

func click(w: Expedition, point: Vector2) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	event.position=w.get_global_transform_with_canvas()*point
	viewport.push_input(event,true);await _frame()
