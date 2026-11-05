class_name BossBehavior
extends RefCounted
## Pure intent state. The existing combat/spawn owners resolve and acknowledge requests.

const KEYS: Array[String] = ["version","identity","state","sequence","target_id","point",
	"remaining","melee_cooldown","slam_cooldown","min_health_ratio","thresholds",
	"pending","last_handled","attack_result"]
const REQUEST_KEYS: Array[String] = ["id","kind","target_id","position","sequence"]
const LIMIT: int = 2147483647
var _value: Dictionary = {}


func configure(identity: String) -> void:
	assert(not identity.is_empty())
	_value = {"version":1,"identity":identity,"state":"idle","sequence":0,"target_id":0,
		"point":[0.0,0.0],"remaining":0.0,"melee_cooldown":0.0,"slam_cooldown":0.0,
		"min_health_ratio":1.0,"thresholds":[],"pending":[],"last_handled":0,"attack_result":{}}
	for threshold: int in BossDefinition.POLICY.thresholds:
		_value.thresholds.append({"threshold":threshold,"issued":false,"handled":false,"result":{}})


func snapshot() -> Dictionary:
	return _value.duplicate(true)


func restore(value: Dictionary) -> void:
	assert(problem(value,String(value.get("identity",""))).is_empty())
	_value = value.duplicate(true)


func step(delta: float, health_ratio: float, alive: bool, targets: Array[Dictionary], position: Vector2) -> Array[Dictionary]:
	assert(not _value.is_empty() and is_finite(delta) and delta>=0.0 and is_finite(health_ratio) and health_ratio>=0.0 and health_ratio<=1.0)
	_value.min_health_ratio = minf(_value.min_health_ratio,health_ratio)
	if not alive or health_ratio<=0.0:
		_value.state = "dead"
		_value.pending.clear()
		_clear_lock()
		return []
	if _value.state=="dead": return []
	# A normally acknowledges in this same simulation step. An outstanding effect
	# must remain identical if the owner pauses/saves before acknowledgement.
	var waiting: bool = not _value.pending.is_empty()
	for threshold: Dictionary in _value.thresholds:
		if not threshold.issued and health_ratio<=float(threshold.threshold)/100.0:
			threshold.issued = true
			_value.pending.append({"id":_summon_id(_value.identity,int(threshold.threshold)),
				"kind":"summon","target_id":0,"position":[position.x,position.y],
				"sequence":0,"threshold":threshold.threshold,"count":BossDefinition.POLICY.summon_count})
	if waiting: return _requests()
	_value.melee_cooldown = maxf(0.0,_value.melee_cooldown-delta)
	_value.slam_cooldown = maxf(0.0,_value.slam_cooldown-delta)
	if _value.state in ["melee_windup","slam_windup"]:
		var kind: String = "melee" if _value.state=="melee_windup" else "slam"
		if kind=="melee" and not _locked_melee_legal(targets,position):
			_value.melee_cooldown = BossDefinition.POLICY.melee_cooldown
			_value.state = "idle"
			_clear_lock()
		else:
			_value.remaining = maxf(0.0,_value.remaining-delta)
			if _value.remaining==0.0:
				_value.pending.append({"id":_attack_id(_value.identity,int(_value.sequence)),
					"kind":kind,"target_id":_value.target_id,"position":_value.point.duplicate(),
					"sequence":_value.sequence})
				_value[kind+"_cooldown"] = BossDefinition.POLICY[kind+"_cooldown"]
				_value.state = "idle"
				_clear_lock()
		return _requests()
	var target: Dictionary = _choose(targets,position,"melee") if _value.melee_cooldown==0.0 else {}
	var kind: String = "melee"
	if target.is_empty() and _value.slam_cooldown==0.0:
		target = _choose(targets,position,"slam")
		kind = "slam"
	if not target.is_empty():
		_value.sequence = int(_value.sequence)+1
		_value.state = kind+"_windup"
		_value.target_id = int(target.member_id)
		_value.point = [target.position.x,target.position.y]
		_value.remaining = BossDefinition.POLICY[kind+"_windup"]
	return _requests()


func acknowledge(request_id: String, result: Dictionary) -> void:
	for index: int in range(_value.pending.size()):
		var request: Dictionary = _value.pending[index]
		if request.id!=request_id: continue
		assert(_result_problem(result,String(request.kind)).is_empty())
		if request.kind=="summon":
			for threshold: Dictionary in _value.thresholds:
				if threshold.threshold==request.threshold:
					threshold.handled = true
					threshold.result = result.duplicate(true)
		else:
			_value.last_handled = int(request.sequence)
			_value.attack_result = {"id":request.id,"kind":request.kind,
				"sequence":request.sequence,"result":result.duplicate(true)}
		_value.pending.remove_at(index)
		return
	# Repeated acknowledgement cannot create a second effect or rewrite old facts.


func _requests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(_value.pending.duplicate(true))
	return result


func _clear_lock() -> void:
	_value.target_id = 0
	_value.point = [0.0,0.0]
	_value.remaining = 0.0


func _locked_melee_legal(targets: Array[Dictionary], position: Vector2) -> bool:
	for target: Dictionary in targets:
		if target.member_id==_value.target_id:
			return target.melee_legal and position.distance_to(target.position)<BossDefinition.POLICY.melee_range
	return false


static func _choose(targets: Array[Dictionary], position: Vector2, kind: String) -> Dictionary:
	var best: Dictionary = {}
	var distance: float = float(BossDefinition.POLICY[kind+"_range"])
	for target: Dictionary in targets:
		if not target[kind+"_legal"]: continue
		var next: float = position.distance_to(target.position)
		if next<distance or (next==distance and not best.is_empty() and int(target.member_id)<int(best.member_id)):
			best = target
			distance = next
	return best


static func problem(value: Variant, identity: String) -> String:
	if not _fields(value,KEYS) or identity.is_empty() or value.identity!=identity or not _integer(value.version,1,1): return "BOSS_STATE_FIELDS"
	if not value.state is String or value.state not in ["idle","melee_windup","slam_windup","dead"] or not _integer(value.sequence,0,LIMIT) or not _integer(value.last_handled,0,int(value.sequence)) or not _integer(value.target_id,0,LIMIT) or not _point(value.point): return "BOSS_STATE_VALUES"
	for kind: String in ["melee","slam"]:
		if not _range(value[kind+"_cooldown"],0.0,BossDefinition.POLICY[kind+"_cooldown"]): return "BOSS_COOLDOWN"
	if not _range(value.min_health_ratio,0.0,1.0) or not _range(value.remaining,0.0,BossDefinition.POLICY.slam_windup): return "BOSS_TIMER"
	var active: bool = value.state in ["melee_windup","slam_windup"]
	if active:
		var kind: String = "melee" if value.state=="melee_windup" else "slam"
		if value.target_id==0 or value.remaining<=0.0 or value.remaining>BossDefinition.POLICY[kind+"_windup"] or value.sequence<=value.last_handled or value[kind+"_cooldown"]!=0.0: return "BOSS_WINDUP"
	elif value.target_id!=0 or value.remaining!=0.0 or value.point!=[0.0,0.0]: return "BOSS_IDLE_LOCK"
	if not value.thresholds is Array or value.thresholds.size()!=2 or not value.pending is Array or value.pending.size()>3: return "BOSS_REQUEST_CONTAINER"
	var ids: Array[String] = []
	var attack_pending: int = 0
	for request: Variant in value.pending:
		var issue: String = _request_problem(request,identity,int(value.sequence))
		if not issue.is_empty(): return issue
		if request.id in ids: return "BOSS_REQUEST_DUPLICATE"
		ids.append(request.id)
		if request.kind!="summon":
			attack_pending += 1
			if request.sequence<=value.last_handled or value[request.kind+"_cooldown"]!=BossDefinition.POLICY[request.kind+"_cooldown"]: return "BOSS_REQUEST_HANDLED"
	if attack_pending>1 or (attack_pending>0 and active) or (value.state=="dead" and not value.pending.is_empty()): return "BOSS_REQUEST_PHASE"
	for index: int in range(2):
		var row: Variant = value.thresholds[index]
		var threshold: int = BossDefinition.POLICY.thresholds[index]
		if not _fields(row,["threshold","issued","handled","result"]) or row.threshold!=threshold or not row.issued is bool or not row.handled is bool or not row.result is Dictionary: return "BOSS_THRESHOLD_FIELDS"
		var queued: bool = _summon_id(identity,threshold) in ids
		if not row.issued:
			if row.handled or queued or not row.result.is_empty() or (value.state!="dead" and value.min_health_ratio<=float(threshold)/100.0): return "BOSS_THRESHOLD_SOURCE"
		else:
			if value.min_health_ratio>float(threshold)/100.0 or (row.handled and queued): return "BOSS_THRESHOLD_SOURCE"
			if row.handled:
				if not _result_problem(row.result,"summon").is_empty(): return "BOSS_THRESHOLD_RESULT"
			elif not row.result.is_empty() or (not queued and value.state!="dead"): return "BOSS_THRESHOLD_PENDING"
	if value.last_handled==0:
		if not value.attack_result is Dictionary or not value.attack_result.is_empty(): return "BOSS_ATTACK_HISTORY"
	else:
		var history: Variant = value.attack_result
		if not _fields(history,["id","kind","sequence","result"]) or history.id!=_attack_id(identity,int(value.last_handled)) or history.sequence!=value.last_handled or history.kind not in ["melee","slam"] or not _result_problem(history.result,history.kind).is_empty(): return "BOSS_ATTACK_HISTORY"
	return ""


static func _request_problem(value: Variant, identity: String, sequence: int) -> String:
	if not value is Dictionary or not value.get("kind") is String or value.kind not in ["melee","slam","summon"]: return "BOSS_REQUEST_FIELDS"
	var summon: bool = value.kind=="summon"
	if not _fields(value,REQUEST_KEYS+["threshold","count"] if summon else REQUEST_KEYS) or not _point(value.position): return "BOSS_REQUEST_FIELDS"
	if summon:
		if value.threshold not in [60,30] or value.count!=BossDefinition.POLICY.summon_count or value.target_id!=0 or value.sequence!=0 or value.id!=_summon_id(identity,int(value.threshold)): return "BOSS_SUMMON_IDENTITY"
	elif not _integer(value.target_id,1,LIMIT) or not _integer(value.sequence,1,sequence) or value.sequence!=sequence or value.id!=_attack_id(identity,int(value.sequence)): return "BOSS_ATTACK_IDENTITY"
	return ""


static func _result_problem(value: Variant, kind: String) -> String:
	if kind=="summon":
		if not _fields(value,["resolutions"]) or not value.resolutions is Array or value.resolutions.size()>2: return "BOSS_SUMMON_RESULT"
		var ids: Array[int] = []
		for row: Variant in value.resolutions:
			if not _fields(row,["reason","enemy_id"]) or row.reason not in ["spawned","capacity","no_safe_point"] or not _integer(row.enemy_id,0,LIMIT): return "BOSS_SUMMON_RESULT"
			if row.reason=="spawned":
				if row.enemy_id==0 or int(row.enemy_id) in ids: return "BOSS_SUMMON_RESULT"
				ids.append(int(row.enemy_id))
			elif row.enemy_id!=0: return "BOSS_SUMMON_RESULT"
	else:
		if not _fields(value,["hits"]) or not value.hits is Array or value.hits.size()>4: return "BOSS_ATTACK_RESULT"
		var ids: Array[int] = []
		for id: Variant in value.hits:
			if not _integer(id,1,LIMIT) or int(id) in ids: return "BOSS_ATTACK_RESULT"
			ids.append(int(id))
	return ""


static func _fields(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size()==keys.size() and value.has_all(keys)


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and value>=minimum and value<=maximum


static func _range(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=minimum and value<=maximum


static func _point(value: Variant) -> bool:
	return value is Array and value.size()==2 and _range(value[0],-1000000.0,1000000.0) and _range(value[1],-1000000.0,1000000.0)


static func _attack_id(identity: String, sequence: int) -> String:
	return identity+":attack:"+str(sequence)


static func _summon_id(identity: String, threshold: int) -> String:
	return identity+":summon:"+str(threshold)
