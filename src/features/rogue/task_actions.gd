class_name TaskActions
extends RefCounted
## V4 task descriptions and pure projections; existing world/transaction owners advance facts.
const VERSION: int = 4
const TEMPLATE_VERSION: int = 1
const PARAMETERS: Dictionary = {"airdrop_seconds":12.0,"reinforcements":2,"source":"PROJECT_TEMP"}
const TYPES: Array[String] = ["supply","equipment","rescue","airdrop"]
const CONFIG: Dictionary = {
	"supply":{"mission":"supermarket","name":"食物补给","cash":[2,4],"food":[4,6],"weapons":[0,1]},
	"equipment":{"mission":"scavenge","name":"装备搜寻","cash":[4,7],"food":[0,2],"weapons":[1,1]},
	"rescue":{"mission":"rescue","name":"幸存者救援","cash":[2,4],"food":[2,4],"weapons":[0,0]},
	"airdrop":{"mission":"scavenge","name":"空投回收","cash":[4,7],"food":[0,2],"weapons":[1,1]}}
const FOOD_TYPES: Array[String] = ["supermarket","convenience_store","eatery"]
const GEAR_TYPES: Array[String] = ["warehouse","garage"]
static var _checked: Dictionary = {}
static var _offers: Dictionary = {}

static func offers(base: Dictionary) -> Array[Dictionary]:
	var cache_key: String = SurvivalContracts.fingerprint({"seed":base.journey.seed,"day":base.day,"eligible":RescuePoolState.available(base)})
	if _offers.has(cache_key):
		var cached: Array[Dictionary] = []; cached.assign(_offers[cache_key].duplicate(true)); return cached
	var random: RandomNumberGenerator = RogueLayout.rng("daily-v4:"+String(base.journey.seed)+":"+str(int(base.day)))
	var types: Array[String] = TYPES.duplicate()
	if RescuePoolState.available(base).is_empty(): types.erase("rescue")
	_shuffle(types,random)
	var sizes: Array[String] = NeighborhoodLayout.SIZES.duplicate()
	var bones: Array[String] = NeighborhoodLayout.TOPOLOGIES.duplicate()
	_shuffle(sizes,random); _shuffle(bones,random)
	# Equipment requires an actual workshop/warehouse; trade compatible theme slots.
	for i: int in range(3):
		if types[i]=="equipment" and bones[i]=="residential":
			var j: int = bones.find("industrial")
			bones[j]="residential"; bones[i]="industrial"
	var candidate: int = RescuePoolState.choice(base,"%s:%d"%[base.profile_id,int(base.settled_sorties)+1])
	var result: Array[Dictionary] = []
	for i: int in range(3):
		var offer: Dictionary = _make(base.journey.seed,int(base.day),i,types[i],bones[i],sizes[i],candidate if types[i]=="rescue" else 0)
		if offer.is_empty(): offer=_make(base.journey.seed,int(base.day),i,types[i],"industrial",sizes[i],0)
		result.append(offer)
	if _offers.size()>=128: _offers.clear()
	_offers[cache_key]=result.duplicate(true)
	return result

static func _shuffle(values: Array[String], random: RandomNumberGenerator) -> void:
	for i: int in range(values.size()-1,0,-1):
		var j: int = random.randi_range(0,i)
		var old: String = values[i]; values[i]=values[j]; values[j]=old

static func _make(seed: String, day: int, slot: int, type: String, bone: String, size: String, recruit: int) -> Dictionary:
	var key: String = "daily-v4:%s:%d:%d"%[seed,day,slot]
	var random: RandomNumberGenerator = RogueLayout.rng(key+":rewards")
	var config: Dictionary = CONFIG[type]
	var layout: Dictionary = {}
	for attempt: int in range(8):
		layout=NeighborhoodLayout.generate(key+":%d"%attempt,size,bone)
		if type!="equipment" or layout.entities.any(func(e: Dictionary) -> bool:return e.archetype in GEAR_TYPES): break
	if type=="equipment" and not layout.entities.any(func(e: Dictionary) -> bool:return e.archetype in GEAR_TYPES): return {}
	var cash: int = random.randi_range(config.cash[0],config.cash[1])
	var food: int = random.randi_range(config.food[0],config.food[1])
	var weapons: int = random.randi_range(config.weapons[0],config.weapons[1])
	var defs: Array = _sites(layout,cash,food,weapons,type)
	var targets: Array = []
	if type=="supply":
		for site: Dictionary in defs:
			if site.kind=="food" and targets.size()<2: targets.append(site.id)
	elif type!="rescue": targets.append("cash")
	var result: Dictionary = {"version":VERSION,"template_version":TEMPLATE_VERSION,"parameters":PARAMETERS.duplicate(true),"id":key.sha256_text(),"seed":seed,"day":day,"slot":slot,"type":type,"cash":cash,"food":food,"weapons":weapons,"recruit":recruit,"layout":layout,"route_length":0,"sites":defs,"objective":{"task_id":key.sha256_text(),"site_ids":targets,"member_id":recruit}}
	result.route_length=route_metrics(result)
	return result

static func _sites(layout: Dictionary, cash: int, food: int, weapons: int, type: String) -> Array:
	var defs: Array = []; var used: Array[String] = []
	# Reserve real food entrances first, so optional cash never consumes them.
	for kind: String in ["food","cash"]:
		var budget: int = food if kind=="food" else cash
		if budget==0: continue
		var preferred: Array[String] = FOOD_TYPES if kind=="food" else GEAR_TYPES
		var candidates: Array = layout.entities.filter(func(e: Dictionary) -> bool:return e.id not in used and (kind!="food" or e.archetype in FOOD_TYPES))
		candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			var av: float = WorldLayout.point(layout.bus.door).distance_to(WorldLayout.point(a.door))+(0 if a.archetype in preferred else 10000)
			var bv: float = WorldLayout.point(layout.bus.door).distance_to(WorldLayout.point(b.door))+(0 if b.archetype in preferred else 10000)
			return av<bv)
		var count: int = mini(candidates.size(),mini(budget,2))
		for i: int in range(count):
			var entity: Dictionary = candidates[i]
			var site: Dictionary = {"id":kind if i==0 else kind+"_%d"%(i+1),"building":entity.id,"kind":kind,"amount":budget/count+int(i<budget%count),"weapon":kind=="cash" and i==0 and weapons==1,"seconds":WorldSites.WORK_SECONDS}
			if type=="airdrop" and kind=="cash" and i==0:
				site.building=""; site.point=_airdrop_point(layout); site.seconds=PARAMETERS.airdrop_seconds
			else: used.append(entity.id)
			defs.append(site)
	return defs

static func _airdrop_point(layout: Dictionary) -> Array:
	# Bottom edge of a real connecting lane, above the protected bus sweep.
	var street: StreetLayout = NeighborhoodLayout.resource(layout)
	var nav: FieldNavigation = FieldNavigation.new(); nav.configure(street.blockers(),street.world_bounds)
	for entity: Dictionary in layout.entities:
		var door: Vector2 = WorldLayout.point(entity.door)
		for offset: Vector2 in [Vector2(80,32),Vector2(-80,32),Vector2(0,64)]:
			var point: Vector2 = door+offset
			var clear: bool = nav.is_clear(point)
			for corner: Vector2 in [Vector2(-28,-28),Vector2(28,-28),Vector2(-28,28),Vector2(28,28)]: clear=clear and nav.is_clear(point+corner)
			if not WorldLayout.rect(layout.bus.sweep).grow(40).has_point(point) and clear and not nav.path_between(street.bus_door,point).is_empty(): return [point.x,point.y]
	assert(false,"V4 bounded airdrop placement has no legal point")
	return []

static func outdoor_site(value: Dictionary, id: StringName) -> bool:
	if (value.get("version")!=4 and value.get("version")!=5) or value.get("type")!="airdrop" or id!=&"cash": return false
	for site: Dictionary in value.sites:
		if site.id==String(id): return site.has("point") and site.building.is_empty()
	return false


static func site_point(value: Dictionary, site: Dictionary) -> Vector2:
	if site.has("point"): return WorldLayout.point(site.point)
	for entity: Dictionary in value.layout.entities:
		if entity.id==site.building: return WorldLayout.point(entity.door)
	return Vector2.INF

static func route_metrics(value: Dictionary) -> int:
	var street: StreetLayout = NeighborhoodLayout.resource(value.layout)
	var nav: FieldNavigation = FieldNavigation.new(); nav.configure(street.blockers(),street.world_bounds)
	var maximum: int = 0
	for site: Dictionary in value.sites: maximum=maxi(maximum,NeighborhoodActions._length(nav.path_between(street.bus_door,site_point(value,site))))
	if value.type=="rescue": maximum=maxi(maximum,NeighborhoodActions._length(nav.path_between(street.bus_door,street.rescue_point)))
	return maximum

static func problem(value: Variant) -> String:
	if not value is Dictionary or value.size()!=16 or not value.has_all(["version","template_version","parameters","id","seed","day","slot","type","cash","food","weapons","recruit","layout","route_length","sites","objective"]): return "TASK_FIELDS"
	if value.version!=VERSION or value.template_version!=TEMPLATE_VERSION or not value.seed is String or value.seed.length()!=32 or not value.seed.is_valid_hex_number(false) or not SurvivalContracts.integer(value.day,2,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(value.slot,0,2) or value.type not in TYPES: return "TASK_VERSION"
	for key: String in ["cash","food","weapons","recruit","route_length"]:
		if not SurvivalContracts.integer(value[key],0,RunSave.MAX_COUNTER): return "TASK_VALUE"
	if not NeighborhoodLayout.validate(value.layout).is_empty(): return "TASK_LAYOUT"
	if value.type=="equipment" and value.layout.topology=="residential": return "TASK_THEME"
	if (value.type=="rescue" and int(value.recruit) not in [3,4,5]) or (value.type!="rescue" and value.recruit!=0): return "TASK_RECRUIT"
	var signature: String = SurvivalContracts.fingerprint(value)
	if _checked.has(signature): return ""
	if not TransactionReceipt.same(value,_make(value.seed,int(value.day),int(value.slot),value.type,value.layout.topology,value.layout["size"],int(value.recruit))): return "TASK_CANONICAL"
	if _checked.size()>=128: _checked.clear()
	_checked[signature]=true
	return ""

static func matches(base: Dictionary, value: Variant) -> bool:
	return EnemyState.is_state(base) and problem(value).is_empty() and TransactionReceipt.same(offers(base)[int(value.slot)],value)

static func mission_problem(mission: Dictionary) -> String:
	if mission.size()!=6 or not mission.has_all(["map_id","mission_id","cash_reward","food_reward","has_weapon_sample","generated"]): return "TASK_MISSION_FIELDS"
	var issue: String = problem(mission.generated)
	if not issue.is_empty(): return issue
	var value: Dictionary = mission.generated
	return "" if mission.map_id==value.layout.id and mission.mission_id==CONFIG[value.type].mission and mission.cash_reward==value.cash and mission.food_reward==value.food and mission.has_weapon_sample==(value.weapons==1) else "TASK_MISSION_BINDING"

static func supply(value: Dictionary) -> MissionSupply:
	assert(problem(value).is_empty())
	var result: MissionSupply = MissionSupply.new()
	result.generated=value.duplicate(true); result.id=StringName(CONFIG[value.type].mission); result.display_name=CONFIG[value.type].name
	result.cash_reward=int(value.cash); result.food_reward=int(value.food); result.has_weapon_sample=value.weapons==1
	result.layout=NeighborhoodLayout.resource(value.layout)
	var target: String = {"supply":"搜完标记的%d处食品站点并归航"%value.objective.site_ids.size(),"equipment":"从标记仓库/修理铺取得武器并归航","rescue":"援救%s，带其生还归航"%SurvivorRoster.definition(maxi(3,int(value.recruit))).default_display_name,"airdrop":"回收标记空投箱（12秒）并归航"}[value.type]
	result.description="主目标：%s\n%s · %s\n可搜获上限：货币%d · 食物%d · 武器%d件\n%s"%[target,{"small":"小型","medium":"中型","large":"大型"}[value.layout["size"]],result.layout.display_name,value.cash,value.food,value.weapons,"首次回收最多引来2名普通感染者；可随时撤离。" if value.type=="airdrop" else NeighborhoodActions.risk(value)]
	return result

static func empty_event() -> Dictionary:
	return {"started":false,"resolutions":[]}

static func event_problem(value: Dictionary, facts: Dictionary, event: Variant, spawn_count: int) -> String:
	if spawn_count<0: return "TASK_EVENT_SPAWN_COUNT"
	if not event is Dictionary or event.size()!=2 or not event.get("started") is bool or not event.get("resolutions") is Array: return "TASK_EVENT_FIELDS"
	if value.type!="airdrop": return "" if TransactionReceipt.same(event,empty_event()) else "TASK_EVENT_UNEXPECTED"
	if event.resolutions.size()!=(PARAMETERS.reinforcements if event.started else 0) or (facts.cash.progress>0 and not event.started): return "TASK_EVENT_TRIGGER"
	var ids: Array[int] = []
	for row: Variant in event.resolutions:
		if not row is Dictionary or row.size()!=2 or row.get("reason") not in ["spawned","capacity","no_safe_point"] or not SurvivalContracts.integer(row.get("enemy_id"),-1,SurvivalContracts.MAX_ID): return "TASK_EVENT_RESOLUTION"
		if row.reason=="spawned":
			if row.enemy_id<0 or int(row.enemy_id) in ids or row.enemy_id>=spawn_count: return "TASK_EVENT_ENEMY"
			ids.append(int(row.enemy_id))
		elif row.enemy_id!=-1: return "TASK_EVENT_ENEMY"
	return ""

static func outcome(value: Dictionary, report: Dictionary) -> Dictionary:
	var count: int = 0
	var total: int = value.objective.site_ids.size()
	var lost: bool = false
	if value.type=="rescue":
		total=1
		var member: Dictionary = SurvivorRoster.member(report.member_results,int(value.recruit))
		var joined: bool = report.field_joins.any(func(row: Dictionary) -> bool:return row.member_id==value.recruit)
		lost=joined and not member.is_empty() and member.health<=0
		count=int(joined and not member.is_empty() and member.health>0)
	else:
		for id: String in value.objective.site_ids: count+=int(report.site_facts[id].searched)
		if value.type in ["equipment","airdrop"] and report.weapons.is_empty(): count=0
	return {"version":1,"task_id":value.id,"type":value.type,"completed":count,"total":total,"status":"COMPLETED" if report.evacuated and count==total else "TARGET_LOST" if lost else "EARLY" if report.evacuated else "FAILED"}

static func summary_problem(value: Variant) -> String:
	if not value is Dictionary or value.size()!=6 or not value.has_all(["version","task_id","type","completed","total","status"]): return "TASK_SUMMARY_FIELDS"
	if value.version!=1 or not value.task_id is String or value.task_id.length()!=64 or not value.task_id.is_valid_hex_number(false) or value.type not in TYPES or not SurvivalContracts.integer(value.total,1,2) or not SurvivalContracts.integer(value.completed,0,int(value.total)) or value.status not in ["COMPLETED","EARLY","TARGET_LOST","FAILED"]: return "TASK_SUMMARY_VALUE"
	if (value.status=="COMPLETED" and value.completed!=value.total) or (value.status=="TARGET_LOST" and value.type!="rescue"): return "TASK_SUMMARY_STATUS"
	return ""

static func summary_text(value: Dictionary) -> String:
	return "%s · %s（%d/%d）"%[CONFIG[value.type].name,{"COMPLETED":"完成主目标","EARLY":"提前撤离未完成","TARGET_LOST":"救援目标阵亡 · 未完成","FAILED":"未能归航 · 未完成"}[value.status],value.completed,value.total]

static func hud(world: Expedition) -> String:
	var value: Dictionary = world.supply.generated
	if value.get("version")!=VERSION and value.get("version")!=5: return ""
	if value.type=="rescue":
		if world.rescue_target!=null and world.rescue_target.status=="IN_FIELD_JOINED": return "主目标：带%s归航"%world.rescue_target.candidate_name() if world.rescue_target.npc.health>0 else "主目标：救援对象已阵亡 · 可撤离"
		return "主目标：援救%s"%SurvivorRoster.definition(int(value.recruit)).default_display_name
	var done: int = 0
	for id: String in value.objective.site_ids: done+=int(world.search_site(StringName(id)).searched)
	if done==value.objective.site_ids.size(): return "主目标已取得 · 带回巴士归航"
	if value.type=="airdrop": return "主目标：回收空投 %.1f/12秒"%world.search_site(&"cash").progress
	return "主目标：%s %d/%d"%["食品站点" if value.type=="supply" else "取得标记武器",done,value.objective.site_ids.size()]
