extends SceneTree
## Synthetic pure-state cases. Integration effects remain owned/tested by A.

const IDENTITY: String = "0123456789abcdef0123456789abcdef:5:breacher"
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("BOSS_BEHAVIOR_FAIL "+label)


func target(id: int, point: Vector2, melee: bool, slam: bool = true) -> Dictionary:
	return {"member_id":id,"position":point,"melee_legal":melee,"slam_legal":slam}


func fresh() -> BossBehavior:
	var value: BossBehavior = BossBehavior.new()
	value.configure(IDENTITY)
	return value


func same(a: Variant, b: Variant) -> bool:
	return TransactionReceipt.same({"value":a},{"value":b})


func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	var behavior: BossBehavior = fresh()
	expect(BossDefinition.POLICY.health==480.0 and BossDefinition.POLICY.speed==26.0,"separate V1 life and speed")
	expect(BossBehavior.problem(behavior.snapshot(),IDENTITY).is_empty(),"initial state authenticates")
	expect(behavior.step(0.5,1.0,true,[],Vector2.ZERO).is_empty() and behavior.snapshot().state=="idle","no target cannot create attack")
	var near: Array[Dictionary] = [target(2,Vector2(20,0),true),target(1,Vector2(-20,0),true)]
	expect(behavior.step(0.1,1.0,true,near,Vector2.ZERO).is_empty(),"arming does not apply an immediate effect")
	var armed: Dictionary = behavior.snapshot()
	expect(armed.state=="melee_windup" and armed.target_id==1 and armed.remaining==0.9,"stable target tie and complete melee windup")
	behavior.step(0.4,1.0,true,near,Vector2.ZERO)
	expect(behavior.snapshot().remaining==0.5,"only active simulation advances windup")
	var copy: BossBehavior = fresh()
	copy.restore(behavior.snapshot())
	expect(same(copy.snapshot(),behavior.snapshot()),"windup restore is exact")
	var requests: Array[Dictionary] = behavior.step(0.5,1.0,true,near,Vector2.ZERO)
	expect(requests.size()==1 and requests[0].kind=="melee" and requests[0].target_id==1,"melee produces one stable intent")
	expect(same(requests,copy.step(0.5,1.0,true,near,Vector2.ZERO)),"restored windup yields same request identity")
	expect(BossBehavior.problem(behavior.snapshot(),IDENTITY).is_empty(),"pending melee authenticates")
	var pending: Dictionary = behavior.snapshot()
	copy.restore(pending)
	expect(same(copy.step(8.0,1.0,true,near,Vector2.ZERO),requests) and same(copy.snapshot(),pending),"unacknowledged request is retained without timer drift")
	behavior.acknowledge(requests[0].id,{"hits":[1]})
	var acknowledged: Dictionary = behavior.snapshot()
	behavior.acknowledge(requests[0].id,{"hits":[]})
	expect(same(behavior.snapshot(),acknowledged),"duplicate ack cannot rewrite actual hits")
	expect(acknowledged.pending.is_empty() and acknowledged.last_handled==1 and acknowledged.melee_cooldown==2.2,"completion cooldown begins once")
	behavior = fresh()
	behavior.step(0.1,1.0,true,near,Vector2.ZERO)
	var far: Array[Dictionary] = [target(1,Vector2(100,0),false)]
	behavior.step(0.4,1.0,true,far,Vector2.ZERO)
	expect(behavior.snapshot().state=="idle" and behavior.snapshot().melee_cooldown==2.2 and behavior.snapshot().pending.is_empty(),"out-of-range melee cancels and consumes cooldown")
	behavior.step(0.1,1.0,true,far,Vector2.ZERO)
	expect(behavior.snapshot().state=="slam_windup" and behavior.snapshot().remaining==1.2,"slam can arm while melee cooldown runs")
	armed = behavior.snapshot()
	var moved: Array[Dictionary] = [target(1,Vector2(180,0),false)]
	behavior.step(0.6,1.0,true,moved,Vector2.ZERO)
	expect(behavior.snapshot().point==armed.point,"slam point remains frozen after target moves")
	copy.restore(behavior.snapshot())
	requests = behavior.step(0.6,1.0,true,moved,Vector2.ZERO)
	expect(requests.size()==1 and requests[0].kind=="slam" and requests[0].position==[100.0,0.0],"slam requests original point after full warning")
	expect(same(copy.step(0.6,1.0,true,moved,Vector2.ZERO),requests),"slam continuation deterministic across snapshot")
	behavior.acknowledge(requests[0].id,{"hits":[]})
	expect(behavior.snapshot().attack_result.result.hits.is_empty() and behavior.snapshot().slam_cooldown==4.0,"dodge is acknowledged without invented damage")
	behavior = fresh()
	requests = behavior.step(0.1,0.6,true,[],Vector2(80,90))
	expect(requests.size()==1 and requests[0].kind=="summon" and requests[0].threshold==60 and requests[0].count==2,"60 percent threshold requests at most two")
	behavior.acknowledge(requests[0].id,{"resolutions":[{"reason":"capacity","enemy_id":0}]})
	var threshold_checkpoint: Dictionary = behavior.snapshot()
	expect(BossBehavior.problem(threshold_checkpoint,IDENTITY).is_empty(),"capacity result authenticates")
	copy.restore(threshold_checkpoint)
	expect(copy.step(10.0,0.6,true,[],Vector2.ZERO).is_empty(),"capacity failure never retries threshold")
	requests = copy.step(0.1,0.3,true,[],Vector2.ZERO)
	expect(requests.size()==1 and requests[0].threshold==30,"30 percent threshold independent")
	copy.acknowledge(requests[0].id,{"resolutions":[{"reason":"spawned","enemy_id":7},{"reason":"no_safe_point","enemy_id":0}]})
	expect(copy.step(0.5,0.1,true,[],Vector2.ZERO).is_empty() and BossBehavior.problem(copy.snapshot(),IDENTITY).is_empty(),"partial summon actual result is persistent and one-shot")
	behavior = fresh()
	requests = behavior.step(0.1,0.29,true,far,Vector2.ZERO)
	expect(requests.size()==2 and behavior.snapshot().state=="slam_windup","crossing both thresholds requests each once without simultaneous attacks")
	expect(BossBehavior.problem(behavior.snapshot(),IDENTITY).is_empty(),"two threshold requests and active attack authenticates")
	for request: Dictionary in requests: behavior.acknowledge(request.id,{"resolutions":[]})
	requests = behavior.step(1.2,0.29,true,far,Vector2.ZERO)
	expect(requests.size()==1,"only one attack follows thresholds")
	behavior.step(0.1,0.0,false,far,Vector2.ZERO)
	expect(behavior.snapshot().state=="dead" and behavior.snapshot().pending.is_empty() and behavior.step(10.0,1.0,true,near,Vector2.ZERO).is_empty(),"death clears pending attack and cannot resurrect behavior")
	expect(BossBehavior.problem(behavior.snapshot(),IDENTITY).is_empty(),"dead snapshot authenticates")
	var exact: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(threshold_checkpoint))).payload
	expect(same(exact,threshold_checkpoint) and BossBehavior.problem(exact,IDENTITY).is_empty(),"exact transport preserves cooldown and threshold facts")
	for change: String in ["identity","version","unknown","negative_timer","timer_nan","timer_infinite","cooldown","point","target","threshold_duplicate","threshold_retry","threshold_fake","result_extra","result_capacity","result_many","result_duplicate"]:
		var bad: Dictionary = threshold_checkpoint.duplicate(true)
		match change:
			"identity": bad.identity="different"
			"version": bad.version=2
			"unknown": bad.extra=1
			"negative_timer": bad.remaining=-1.0
			"timer_nan": bad.remaining=NAN
			"timer_infinite": bad.remaining=INF
			"cooldown": bad.melee_cooldown=2.3
			"point": bad.point=[0.0,NAN]
			"target": bad.target_id=3
			"threshold_duplicate": bad.thresholds[1].threshold=60
			"threshold_retry": bad.thresholds[0].issued=false
			"threshold_fake": bad.min_health_ratio=1.0
			"result_extra": bad.thresholds[0].result.extra=true
			"result_capacity": bad.thresholds[0].result.resolutions[0].enemy_id=2
			"result_many": bad.thresholds[0].result.resolutions=[{"reason":"capacity","enemy_id":0},{"reason":"capacity","enemy_id":0},{"reason":"capacity","enemy_id":0}]
			"result_duplicate": bad.thresholds[0].result.resolutions=[{"reason":"spawned","enemy_id":3},{"reason":"spawned","enemy_id":3}]
		expect(not BossBehavior.problem(bad,IDENTITY).is_empty(),"reject malformed "+change)
	behavior = fresh()
	behavior.step(0.1,1.0,true,far,Vector2.ZERO)
	armed = behavior.snapshot()
	for change: String in ["elapsed","overlong","cooldown","sequence"]:
		var bad: Dictionary = armed.duplicate(true)
		match change:
			"elapsed": bad.remaining=0.0
			"overlong": bad.remaining=1.3
			"cooldown": bad.slam_cooldown=0.1
			"sequence": bad.sequence=0
		expect(not BossBehavior.problem(bad,IDENTITY).is_empty(),"reject active "+change)
	requests = behavior.step(1.2,1.0,true,far,Vector2.ZERO)
	pending = behavior.snapshot()
	for change: String in ["id","sequence","duplicate","target","extra","cooldown"]:
		var bad: Dictionary = pending.duplicate(true)
		match change:
			"id": bad.pending[0].id="forged"
			"sequence": bad.pending[0].sequence=2
			"duplicate": bad.pending.append(bad.pending[0].duplicate(true))
			"target": bad.pending[0].target_id=0
			"extra": bad.pending[0].extra=0
			"cooldown": bad.slam_cooldown=3.9
		expect(not BossBehavior.problem(bad,IDENTITY).is_empty(),"reject pending "+change)
	var warning: BossWarning = BossWarning.new()
	root.add_child(warning)
	var unchanged: Dictionary = armed.duplicate(true)
	warning.update_state(armed,Vector2.ZERO,480.0,480.0)
	expect(same(armed,unchanged),"warning does not change its input snapshot")
	warning.queue_free()
	await process_frame
	print(JSON.stringify({"checks":checks,"failures":failures,"scope":"pure boss behavior and read-only warning","policy":BossDefinition.POLICY}))
	quit(0 if failures==0 else 1)
