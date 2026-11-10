class_name NeighborhoodActions
extends RefCounted
## V3 spatial semantics; unchanged budget ranges, deterministic saved seed/day.
const VERSION: int = 3
const TYPES: Array[String] = ["supply","equipment","rescue"]
const CONFIG: Dictionary = {
	"supply":{"mission":"supermarket","name":"食物补给","cash":[2,4],"food":[4,6],"weapons":[0,1]},
	"equipment":{"mission":"scavenge","name":"装备搜寻","cash":[4,7],"food":[0,2],"weapons":[1,1]},
	"rescue":{"mission":"rescue","name":"街角救援","cash":[2,4],"food":[2,4],"weapons":[0,0]}}
static var _checked: ActionMemo = ActionMemo.new(128)
static var _offers: ActionMemo = ActionMemo.new(128)

static func offers(base: Dictionary) -> Array[Dictionary]:
	var cache_key: String=SurvivalContracts.fingerprint({"seed":base.journey.seed,"day":base.day,"eligible":RescuePoolState.available(base)})
	var stored: Variant = _offers.lookup(cache_key)
	if stored != null:
		var cached: Array[Dictionary] = []
		cached.assign(stored.duplicate(true))
		return cached
	var types: Array[String] = TYPES.duplicate()
	var random: RandomNumberGenerator = RogueLayout.rng("daily-v3:"+String(base.journey.seed)+":"+str(int(base.day)))
	if RescuePoolState.available(base).is_empty():types[2]="supply" if random.randi_range(0,1)==0 else "equipment"
	var sizes: Array[String]=NeighborhoodLayout.SIZES.duplicate()
	var bones: Array[String]=NeighborhoodLayout.TOPOLOGIES.duplicate()
	for i: int in range(2,0,-1):
		var j: int=random.randi_range(0,i)
		var old: String=types[i];types[i]=types[j];types[j]=old
		j=random.randi_range(0,i);old=bones[i];bones[i]=bones[j];bones[j]=old
		j=random.randi_range(0,i);old=sizes[i];sizes[i]=sizes[j];sizes[j]=old
	var result: Array[Dictionary]=[]
	var candidate: int=RescuePoolState.choice(base,"%s:%d"%[base.profile_id,int(base.settled_sorties)+1])
	for slot: int in range(3):result.append(_make(String(base.journey.seed),int(base.day),slot,types[slot],bones[slot],sizes[slot],candidate if types[slot]=="rescue" else 0))
	_offers.store(cache_key, result.duplicate(true))
	return result

static func _make(seed: String, day: int, slot: int, type: String, bone: String, size: String, recruit: int) -> Dictionary:
	var key: String="daily-v3:%s:%d:%d"%[seed,day,slot]
	var random: RandomNumberGenerator=RogueLayout.rng(key+":rewards")
	var config: Dictionary=CONFIG[type]
	var layout: Dictionary=NeighborhoodLayout.generate(key,size,bone)
	var cash: int=random.randi_range(config.cash[0],config.cash[1])
	var food: int=random.randi_range(config.food[0],config.food[1])
	var weapons: int=random.randi_range(config.weapons[0],config.weapons[1])
	var result: Dictionary = {"version":VERSION,"id":key.sha256_text(),"seed":seed,"day":day,"slot":slot,"type":type,"cash":cash,"food":food,"weapons":weapons,"recruit":recruit,"layout":layout,"route_length":0,"sites":WorldSites.definitions(layout,cash,food,weapons)}
	result.route_length=route_metrics(result).maximum
	return result

static func problem(value: Variant) -> String:
	var stamp: int = FreezeProfile.enter("action.problem")
	var result: String = _profiled_problem(value)
	FreezeProfile.leave("action.problem", stamp)
	return result


static func _profiled_problem(value: Variant) -> String:
	if not value is Dictionary or value.size()!=13 or not value.has_all(["version","id","seed","day","slot","type","cash","food","weapons","recruit","layout","route_length","sites"]):return "DAILY_FIELDS"
	if value.version!=VERSION or not value.seed is String or value.seed.length()!=32 or not value.seed.is_valid_hex_number(false) or not SurvivalContracts.integer(value.day,2,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(value.slot,0,2) or value.type not in TYPES:return "DAILY_VERSION_OR_SEED"
	for key: String in ["cash","food","weapons","recruit","route_length"]:
		if not SurvivalContracts.integer(value[key],0,RunSave.MAX_COUNTER):return "DAILY_VALUE"
	var issue: String=NeighborhoodLayout.validate(value.layout)
	if not issue.is_empty():return issue
	var signature: String=SurvivalContracts.fingerprint(value)
	if _checked.lookup(signature) == true:return ""
	var expected: Dictionary=_make(value.seed,int(value.day),int(value.slot),value.type,value.layout.topology,value.layout["size"],int(value.recruit))
	if not TransactionReceipt.same(value,expected):return "DAILY_CANONICAL"
	if (value.type=="rescue" and int(value.recruit) not in [3,4,5]) or (value.type!="rescue" and value.recruit!=0):return "DAILY_RECRUIT"
	_checked.store(signature, true)
	return ""

static func matches(base: Dictionary, value: Variant) -> bool:
	if not EnemyState.is_state(base) or not problem(value).is_empty():return false
	return TransactionReceipt.same(offers(base)[int(value.slot)],value)

static func mission_problem(mission: Dictionary) -> String:
	if mission.size()!=6 or not mission.has_all(["map_id","mission_id","cash_reward","food_reward","has_weapon_sample","generated"]):return "DAILY_MISSION_FIELDS"
	var issue: String=problem(mission.generated)
	if not issue.is_empty():return issue
	var value: Dictionary=mission.generated
	return "" if mission.map_id==value.layout.id and mission.mission_id==CONFIG[value.type].mission and mission.cash_reward==value.cash and mission.food_reward==value.food and mission.has_weapon_sample==(value.weapons==1) else "DAILY_MISSION_BINDING"

static func supply(value: Dictionary) -> MissionSupply:
	assert(problem(value).is_empty())
	var result: MissionSupply=MissionSupply.new()
	result.generated=value.duplicate(true)
	result.id=StringName(CONFIG[value.type].mission)
	result.display_name=CONFIG[value.type].name
	result.cash_reward=int(value.cash);result.food_reward=int(value.food);result.has_weapon_sample=value.weapons==1
	result.layout=NeighborhoodLayout.resource(value.layout)
	result.description="%s · %s · %s\n可搜获上限：货币%d · 食物%d · 武器%d件\n%s"%[result.display_name,result.layout.display_name,{"small":"小型","medium":"中型","large":"大型"}[value.layout["size"]],value.cash,value.food,value.weapons,risk(value)]
	if value.type=="rescue":result.description+="\n援救%s10秒后同行参战。"%SurvivorRoster.definition(int(value.recruit)).default_display_name
	return result

static var _routes: ActionMemo = ActionMemo.new(129)
static func route_metrics(value: Dictionary) -> Dictionary:
	var key: String = SurvivalContracts.fingerprint({"layout":value.layout,"sites":value.sites,"rescue":value.recruit})
	var cached: Variant = _routes.lookup(key)
	if cached != null:
		return cached.duplicate(true)
	var layout: StreetLayout = NeighborhoodLayout.resource(value.layout)
	var nav: FieldNavigation = FieldNavigation.new(); nav.configure(layout.blockers(),layout.world_bounds)
	var lengths: Dictionary = {}
	for site: Dictionary in value.sites:
		for e: Dictionary in value.layout.entities:
			if e.id==site.building: lengths[site.id]=_length(nav.path_between(layout.bus_door,WorldLayout.point(e.door)))
	if value.type=="rescue": lengths["rescue"]=_length(nav.path_between(layout.bus_door,layout.rescue_point))
	var maximum: int = 0
	for length: int in lengths.values(): maximum=maxi(maximum,length)
	var result: Dictionary = {"maximum":maximum,"paths":lengths,"speed":125,"work_seconds":30}
	_routes.store(key, result.duplicate(true))
	return result
static func _length(path: PackedVector2Array) -> int:
	var length: float = 0
	for i: int in range(1,path.size()): length+=path[i-1].distance_to(path[i])
	return ceili(length)
static func risk(value: Dictionary) -> String:
	return {"commercial":"主街贯通，侧后巷可绕行","residential":"庭院墙与错位巷口，请留出返程时间","industrial":"装卸院口与外围服务路可选，长墙挡视线"}[value.layout.topology]+"；最远有效目标单程约%d秒。暮色后原增援加快，可提前撤离。"%ceili(float(value.route_length)/125)
