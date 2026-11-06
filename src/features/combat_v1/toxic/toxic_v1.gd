class_name ToxicV1
extends RefCounted
## Pure V1 intent and fixed tick batches. The existing owner alone commits damage.

const KIND: String = "toxic_zombie_v1"
const POLICY: Dictionary = {
	"id":"BH_TOXIC_V1", "health":64.0, "speed":26.0,
	"range":220.0, "windup":0.90, "cooldown":6.0,
	"radius":60.0, "lifetime":3.0, "tick_seconds":0.75,
	"damage":6.0, "ticks":4, "caster_cap":1, "zone_cap":2,
	"weights":[[90,0,0,10], [76,14,0,10], [59,22,9,10], [40,27,23,10]],
} # PROJECT_TEMP; these are project adaptations, not original-game measurements.
const LIMIT: int = 4096
const ROOT_KEYS: Array[String] = ["version", "sequence", "casters", "zones", "releases", "pending"]
const CASTER_KEYS: Array[String] = ["id", "phase", "remaining", "point", "sequence"]
const RELEASE_KEYS: Array[String] = ["id", "source_id", "sequence", "point", "source_point"]
const ZONE_KEYS: Array[String] = ["id", "source_id", "sequence", "point", "source_point", "age", "next_tick"]
const HIT_KEYS: Array[String] = ["zone_id", "tick", "member_id", "amount", "member_point"]


static func initial() -> Dictionary:
	return {"version":1, "sequence":0, "casters":{}, "zones":[], "releases":[], "pending":{}}


static func pick(identity: String, index: int, stage: int, live_toxic: int = 0) -> String:
	if stage < 0 or stage > 3 or index < 0:
		return ""
	var roll: int = (String(POLICY.id) + ":" + identity + ":" + str(index) + ":" + str(stage)).sha256_text().substr(0, 8).hex_to_int() % 100
	var weights: Array = POLICY.weights[stage]
	if roll < int(weights[0]):
		return EnemyRules.NORMAL
	if roll < int(weights[0]) + int(weights[1]):
		return EnemyRules.RUSH
	if roll < int(weights[0]) + int(weights[1]) + int(weights[2]):
		return EnemyRules.HEAVY
	return KIND if live_toxic < int(POLICY.caster_cap) else EnemyRules.NORMAL


static func plan(state: Dictionary, delta: float, casters: Array[Dictionary], members: Array[Dictionary], obstacles: Array[ShotObstacle], caster_active: bool = true) -> Dictionary:
	var next: Dictionary = state.duplicate(true)
	if not problem(state).is_empty() or not _number(delta) or delta < 0.0 or not _rows_valid(casters, 0, RunSave.MAX_COUNTER) or not _rows_valid(members, 1, SurvivorRoster.MAX_MEMBER_ID):
		return {"state":next, "hits":[]}
	# Failed partial commits retain the original target set and stop every clock.
	if not next.pending.is_empty():
		return {"state":next, "hits":next.pending.hits.slice(int(next.pending.cursor)).duplicate(true)}
	var living: Array[Dictionary] = []
	for caster: Dictionary in casters:
		if caster.alive:
			living.append(caster)
	if living.size() > int(POLICY.caster_cap):
		return {"state":next, "hits":[]}
	living.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	var present: Dictionary = {}
	var newborn_age: Dictionary = {}
	for caster: Dictionary in living:
		var key: String = str(int(caster.id))
		present[key] = true
		if not next.casters.has(key):
			next.casters[key] = _caster(int(caster.id))
		var intent: Dictionary = next.casters[key]
		if not caster_active: continue
		if intent.phase == "windup":
			if not caster.available:
				_cooldown(intent)
				continue
			var overdue: float = maxf(0.0, delta - float(intent.remaining))
			intent.remaining = maxf(0.0, float(intent.remaining) - delta)
			if intent.remaining == 0.0:
				var point: Vector2 = _vec(intent.point)
				if next.zones.size() < int(POLICY.zone_cap) and _cast_legal(caster.foot, point, obstacles):
					var release: Dictionary = {"id":zone_id(int(caster.id), int(intent.sequence)), "source_id":int(caster.id), "sequence":int(intent.sequence), "point":intent.point.duplicate(), "source_point":_point(caster.foot)}
					next.releases.append(release)
					var zone: Dictionary = release.duplicate(true)
					zone.age = 0.0
					zone.next_tick = 1
					next.zones.append(zone)
					newborn_age[zone.id] = overdue
				_cooldown(intent)
				intent.remaining = maxf(0.0, float(POLICY.cooldown) - overdue)
				if intent.remaining == 0.0:
					_reset(intent)
		elif intent.phase == "cooldown":
			intent.remaining = maxf(0.0, float(intent.remaining) - delta)
			if intent.remaining == 0.0:
				_reset(intent)
		elif caster.available and next.zones.size() < int(POLICY.zone_cap) and int(next.sequence) < LIMIT:
			var target: Dictionary = _target(caster.foot, members, obstacles)
			if not target.is_empty():
				next.sequence = int(next.sequence) + 1
				intent.phase = "windup"
				intent.remaining = float(POLICY.windup)
				intent.point = _point(target.foot)
				intent.sequence = int(next.sequence)
	for key: String in next.casters.keys():
		if not present.has(key):
			next.casters.erase(key)
	var hits: Array[Dictionary] = []
	for zone: Dictionary in next.zones:
		zone.age = minf(float(POLICY.lifetime), float(zone.age) + float(newborn_age.get(zone.id, delta)))
		while int(zone.next_tick) <= int(POLICY.ticks) and float(zone.age) >= float(zone.next_tick) * float(POLICY.tick_seconds):
			var victims: Array[Dictionary] = _victims(_vec(zone.point), members, obstacles)
			for victim: Dictionary in victims:
				hits.append({"zone_id":zone.id, "tick":int(zone.next_tick), "member_id":int(victim.id), "amount":float(POLICY.damage), "member_point":_point(victim.foot)})
			zone.next_tick = int(zone.next_tick) + 1
	if not hits.is_empty():
		next.pending = {"hits":hits.duplicate(true), "cursor":0}
	else:
		_retire(next)
	return {"state":next, "hits":hits}


static func ack(state: Dictionary, hit: Dictionary) -> Dictionary:
	var next: Dictionary = state.duplicate(true)
	if not problem(state).is_empty() or state.pending.is_empty():
		return next
	var expected: Dictionary = state.pending.hits[int(state.pending.cursor)]
	if not TransactionReceipt.same(expected, hit):
		return next
	next.pending.cursor = int(next.pending.cursor) + 1
	if int(next.pending.cursor) == next.pending.hits.size():
		next.pending = {}
		_retire(next)
	return next


static func zone_id(source_id: int, sequence: int) -> String:
	return "toxic:%d:%d" % [source_id, sequence]


static func problem(state: Variant) -> String:
	if not _keys(state, ROOT_KEYS) or not _integer(state.version, 1, 1) or not _integer(state.sequence, 0, LIMIT):
		return "TOXIC_VERSION_FIELDS"
	if not state.casters is Dictionary or state.casters.size() > int(POLICY.caster_cap) or not state.zones is Array or state.zones.size() > int(POLICY.zone_cap) or not state.releases is Array or state.releases.size() > int(state.sequence) or not state.pending is Dictionary:
		return "TOXIC_COLLECTIONS"
	var cast_sequences: Array[int] = []
	for key: Variant in state.casters:
		var intent: Variant = state.casters[key]
		if not key is String or not _keys(intent, CASTER_KEYS) or not _integer(intent.id, 0, RunSave.MAX_COUNTER) or key != str(int(intent.id)) or not intent.phase is String or intent.phase not in ["chase", "windup", "cooldown"] or not _number(intent.remaining) or not intent.point is Array or not _integer(intent.sequence, 0, int(state.sequence)):
			return "TOXIC_CASTER_FIELDS"
		if intent.phase == "windup":
			if intent.remaining <= 0.0 or intent.remaining > float(POLICY.windup) or int(intent.sequence) < 1 or int(intent.sequence) != int(state.sequence) or not _point_valid(intent.point):
				return "TOXIC_WINDUP_PHASE"
			cast_sequences.append(int(intent.sequence))
		elif intent.sequence != 0 or not intent.point.is_empty() or (intent.phase == "chase" and intent.remaining != 0.0) or (intent.phase == "cooldown" and (intent.remaining <= 0.0 or intent.remaining > float(POLICY.cooldown))):
			return "TOXIC_RECOVERY_PHASE"
	var releases: Dictionary = {}
	var last_sequence: int = 0
	for release: Variant in state.releases:
		if not _keys(release, RELEASE_KEYS) or not _release_valid(release, int(state.sequence)) or int(release.sequence) <= last_sequence or int(release.sequence) in cast_sequences or (not cast_sequences.is_empty() and int(release.sequence) >= int(cast_sequences[0])):
			return "TOXIC_RELEASE_SOURCE"
		releases[release.id] = release
		last_sequence = int(release.sequence)
	var zones: Dictionary = {}
	for zone: Variant in state.zones:
		if not _keys(zone, ZONE_KEYS) or not _release_valid(zone, int(state.sequence)) or zones.has(zone.id) or not releases.has(zone.id) or not _number(zone.age) or zone.age < 0.0 or zone.age > float(POLICY.lifetime) or not _integer(zone.next_tick, 1, int(POLICY.ticks) + 1):
			return "TOXIC_ZONE_FIELDS"
		for key: String in RELEASE_KEYS:
			if not TransactionReceipt.same({"v":zone[key]}, {"v":releases[zone.id][key]}):
				return "TOXIC_ZONE_RELEASE"
		var expected_tick: int = 1
		while expected_tick <= int(POLICY.ticks) and float(zone.age) >= float(expected_tick) * float(POLICY.tick_seconds):
			expected_tick += 1
		if int(zone.next_tick) != expected_tick:
			return "TOXIC_TICK_CLOCK"
		zones[zone.id] = zone
	if not state.pending.is_empty():
		if not _keys(state.pending, ["hits", "cursor"]) or not state.pending.hits is Array or state.pending.hits.is_empty() or state.pending.hits.size() > int(POLICY.zone_cap) * int(POLICY.ticks) * SurvivorRoster.MAX_MEMBER_ID or not _integer(state.pending.cursor, 0, state.pending.hits.size() - 1):
			return "TOXIC_PENDING_FIELDS"
		var seen: Dictionary = {}
		var previous_zone: int = -1
		var previous_tick: int = 0
		var previous_member: int = 0
		for hit: Variant in state.pending.hits:
			if not _keys(hit, HIT_KEYS) or not hit.zone_id is String or not zones.has(hit.zone_id) or not _integer(hit.tick, 1, int(POLICY.ticks)) or not _integer(hit.member_id, 1, SurvivorRoster.MAX_MEMBER_ID) or not _number(hit.amount) or hit.amount != POLICY.damage or not _point_valid(hit.member_point):
				return "TOXIC_PENDING_HIT"
			var zone: Dictionary = zones[hit.zone_id]
			var position: int = state.zones.find(zone)
			var identity: String = "%s:%d:%d" % [hit.zone_id, int(hit.tick), int(hit.member_id)]
			if seen.has(identity) or int(hit.tick) >= int(zone.next_tick) or float(zone.age) < float(hit.tick) * float(POLICY.tick_seconds) or _vec(zone.point).distance_squared_to(_vec(hit.member_point)) > float(POLICY.radius) * float(POLICY.radius) or position < previous_zone or (position == previous_zone and (int(hit.tick) < previous_tick or (int(hit.tick) == previous_tick and int(hit.member_id) <= previous_member))):
				return "TOXIC_PENDING_ORDER"
			seen[identity] = true
			previous_zone = position
			previous_tick = int(hit.tick)
			previous_member = int(hit.member_id)
	else:
		for zone: Dictionary in state.zones:
			if zone.age == POLICY.lifetime:
				return "TOXIC_EXPIRED_ZONE"
	return ""


static func line_clear(start: Vector2, end: Vector2, obstacles: Array[ShotObstacle]) -> bool:
	for obstacle: ShotObstacle in obstacles:
		if obstacle.blocks_shots and AttackRules._segment_entry(start, end, obstacle.footprint) < INF:
			return false
	return true


static func _caster(id: int) -> Dictionary:
	return {"id":id, "phase":"chase", "remaining":0.0, "point":[], "sequence":0}


static func _reset(intent: Dictionary) -> void:
	intent.phase = "chase"
	intent.remaining = 0.0
	intent.point = []
	intent.sequence = 0


static func _cooldown(intent: Dictionary) -> void:
	_reset(intent)
	intent.phase = "cooldown"
	intent.remaining = float(POLICY.cooldown)


static func _target(origin: Vector2, members: Array[Dictionary], obstacles: Array[ShotObstacle]) -> Dictionary:
	var result: Dictionary = {}
	var distance: float = float(POLICY.range) * float(POLICY.range)
	for member: Dictionary in members:
		if not member.alive or not member.available or not _cast_legal(origin, member.foot, obstacles):
			continue
		var squared: float = origin.distance_squared_to(member.foot)
		if squared < distance or (squared == distance and not result.is_empty() and int(member.id) < int(result.id)):
			result = member
			distance = squared
	return result


static func _victims(point: Vector2, members: Array[Dictionary], obstacles: Array[ShotObstacle]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member: Dictionary in members:
		if member.alive and member.available and point.distance_squared_to(member.foot) <= float(POLICY.radius) * float(POLICY.radius) and line_clear(point, member.foot, obstacles):
			result.append(member)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return result


static func _cast_legal(origin: Vector2, point: Vector2, obstacles: Array[ShotObstacle]) -> bool:
	return origin.distance_to(point) < float(POLICY.range) and line_clear(origin, point, obstacles)


static func _retire(state: Dictionary) -> void:
	for index: int in range(state.zones.size() - 1, -1, -1):
		if float(state.zones[index].age) >= float(POLICY.lifetime) and int(state.zones[index].next_tick) == int(POLICY.ticks) + 1:
			state.zones.remove_at(index)


static func _release_valid(value: Dictionary, sequence: int) -> bool:
	return value.id is String and _integer(value.source_id, 0, RunSave.MAX_COUNTER) and _integer(value.sequence, 1, sequence) and value.id == zone_id(int(value.source_id), int(value.sequence)) and _point_valid(value.point) and _point_valid(value.source_point) and _vec(value.source_point).distance_to(_vec(value.point)) < float(POLICY.range)


static func _rows_valid(rows: Array[Dictionary], low: int, high: int) -> bool:
	var seen: Array[int] = []
	for row: Dictionary in rows:
		if not row.has_all(["id", "foot", "alive", "available"]) or not _integer(row.id, low, high) or int(row.id) in seen or not row.foot is Vector2 or not row.foot.is_finite() or not row.alive is bool or not row.available is bool:
			return false
		seen.append(int(row.id))
	return true


static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and value.has_all(keys)


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= float(low) and float(value) <= float(high)


static func _point_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])


static func _point(value: Vector2) -> Array:
	return [value.x, value.y]


static func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
