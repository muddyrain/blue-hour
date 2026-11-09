class_name LevelSummary
extends RefCounted
## Frozen route evidence only. Movement, work, threat and settlement retain their owners.

const SPEED: float = 125.0


static func freeze(layout: Dictionary, sites: Array, objective: Dictionary, type: String, extra_site: String = "") -> Dictionary:
	var proof: Dictionary=ValueProofCache.lookup("level-summary",{"layout":layout,"sites":sites,"objective":objective,"type":type,"extra_site":extra_site})
	if proof.hit:
		return proof.result
	var result: Dictionary=_freeze(layout,sites,objective,type,extra_site)
	if not result.is_empty():
		ValueProofCache.remember(proof,result)
	return result


static func _freeze(layout: Dictionary, sites: Array, objective: Dictionary, type: String, extra_site: String) -> Dictionary:
	var routing: Dictionary = ExplorationLayout._routing(layout)
	if routing.is_empty() or type not in TaskActions.TYPES:
		return {}
	var nav: FieldNavigation = routing.nav
	var points: Dictionary = {"bus":WorldLayout.point(layout.bus.door)}
	var work: Dictionary = {}
	var primary: Array[String] = []
	if type == "rescue":
		primary.append("rescue")
		points.rescue = WorldLayout.point(layout.rescue)
		work.rescue = RescueTarget.SECONDS
	else:
		for id: String in objective.site_ids:
			primary.append(id)
	for site: Dictionary in sites:
		points[site.id] = ExplorationSites.site_point(layout, site)
		work[site.id] = float(site.seconds)
	if primary.is_empty() or primary.size() > 2:
		return {}
	var routes: Dictionary = {}
	for id: String in primary:
		if not points.has(id) or not work.has(id):
			return {}
		for endpoints: Array in [["bus", id], [id, "bus"]]:
			var route: Dictionary = _route(nav, points[endpoints[0]], points[endpoints[1]])
			if route.is_empty():
				return {}
			routes[_key(endpoints[0], endpoints[1])] = route
		for other: String in primary:
			if other == id:
				continue
			var route: Dictionary = _route(nav, points[id], points[other])
			if route.is_empty():
				return {}
			routes[_key(id, other)] = route
	var tuning: ExpeditionTuning = ExpeditionTuning.new()
	var single: Dictionary = _estimate([primary], routes, work, tuning)
	var split: Array = []
	for id: String in primary:
		split.append([id])
	var parallel: Dictionary = _estimate(split, routes, work, tuning)
	var optional: Dictionary = {}
	var from_ids: Array[String] = primary.duplicate()
	from_ids.append("bus")
	# The selected branch measures a genuine choice, not another completion reward.
	for site: Dictionary in sites:
		if (extra_site.is_empty() and site.source not in ["optional_building", "vehicle", "fruit_tree"]) \
				or (not extra_site.is_empty() and site.id != extra_site):
			continue
		var extra_routes: Dictionary = routes.duplicate()
		var valid: bool = true
		for id: String in from_ids:
			var route: Dictionary = _route(nav, points[id], points[site.id])
			if route.is_empty():
				valid = false
				break
			extra_routes[_key(id, site.id)] = route
		var back: Dictionary = _route(nav, points[site.id], points.bus)
		if not valid or back.is_empty():
			continue
		extra_routes[_key(site.id, "bus")] = back
		var serial_order: Array = primary.duplicate()
		serial_order.append(site.id)
		var solo_extra: Dictionary = _estimate([serial_order], extra_routes, work, tuning)
		var best_split: Dictionary = {}
		var worker: int = 0
		for index: int in range(split.size()):
			var orders: Array = split.duplicate(true)
			orders[index].append(site.id)
			var estimate: Dictionary = _estimate(orders, extra_routes, work, tuning)
			if best_split.is_empty() or estimate.team_return_seconds < best_split.team_return_seconds:
				best_split = estimate
				worker = index
		var added: float = best_split.team_return_seconds - parallel.team_return_seconds
		if optional.is_empty() or added > float(optional.added_team_seconds):
			var branch: Dictionary = {}
			for key: String in extra_routes:
				if not routes.has(key):
					branch[key] = extra_routes[key]
			optional = {"site_id":site.id, "source":site.source, "point":[points[site.id].x, points[site.id].y],
				"work_seconds":float(site.seconds), "worker_index":worker, "routes":branch,
				"single":solo_extra, "two_worker":best_split, "added_team_seconds":added,
				"added_serial_length":float(solo_extra.travel_lengths[0]) - float(single.travel_lengths[0])}
	if optional.is_empty():
		return {}
	return {"version":1, "type":type, "source":"FINAL_COLLISION_NAVIGATION", "primary":primary,
		"assumptions":{"speed":SPEED, "work_factor":1.0, "dispatch":"simultaneous_from_bus", "return":"slowest_assigned_worker_back_at_bus",
			"engine":"requested_after_team_returns", "excludes":"combat, personal factors, command delay, formation and live obstruction",
			"bus_ready_seconds":tuning.bus_ready_seconds, "engine_seconds":tuning.engine_seconds,
			"late_seconds":tuning.daylight_seconds * ThreatRules.LATE_FRACTION, "night_seconds":tuning.daylight_seconds,
			"departure_presentation_seconds":BusJourney.EMBARK + BusJourney.DRIVE_OUT},
		"work_seconds":work, "routes":routes, "single":single, "two_worker":parallel, "optional":optional}


static func description(value: Dictionary, for_card: bool = false) -> String:
	var level: Dictionary = value.get("exploration", {}).get("level", {})
	if level.is_empty():
		return ""
	var first: String = level.primary[0]
	var outbound: float = float(level.routes[_key("bus", first)].length) / SPEED
	var text: String
	match String(value.type):
		"supply":
			text = "食品主点单程约%d秒。" % ceili(outbound)
			if level.primary.size() == 2:
				var between: float = float(level.routes[_key(first, level.primary[1])].length) / SPEED
				text += "两点相隔约%d秒，可分工。" % ceili(between)
		"equipment":
			text = "深入装备点，单程约%d秒；沿途可搜。" % ceili(outbound)
		"rescue":
			text = "住宅簇单程约%d秒；援救后带其归航。" % ceili(outbound)
		"airdrop":
			text = "户外回收12秒，可受击；一次性增援。"
	var source_name: String = {"optional_building":"可选建筑", "vehicle":"停放车辆", "fruit_tree":"果树"}[level.optional.source]
	if for_card:
		var assignment: String = "另派一人搜" if level.primary.size() == 1 else "其中一人再搜"
		var extra: int = ceili(extra_return_seconds(level))
		var wait: String = "回车无需多等" if extra == 0 else "回车多约%d秒" % extra
		return text + "\n%s%s，%s。\n两人从巴士分头出发，按基础移速和工时估算。\n实战时间另计，带回确认后生效。" % [assignment, source_name, wait]
	text += "\n追加%s，双人回车约多%d秒。" % [source_name, ceili(float(level.optional.added_team_seconds))]
	return text + "\n125移速/工作因子1，战斗与个人差异另计。\n带回确认后生效。"


static func mission_card_text(value: Dictionary, base: Dictionary = {}, rations: Dictionary = {}) -> String:
	var level: Dictionary = value.exploration.level
	var first: String = level.primary[0]
	var outbound: int = _mission_route_seconds(level, "bus", first)
	var reward: String
	var decision: String = ""
	var route: String
	var risk: String
	match String(value.type):
		"supply":
			var food: PackedStringArray = []
			for site: Dictionary in value.sites:
				if site.id in level.primary:
					food.append(str(int(site.amount)))
			reward = "食物 %s 份，按实搜入库" % " + ".join(food)
			if not base.is_empty():
				reward = "食物 %s 份，按实搜带回" % " + ".join(food)
				if not rations.is_empty():
					decision = "\n口粮 · 现有 %d 粮 / 需 %d 粮" % [int(base.food), int(rations.required)]
					if rations.shortage > 0:
						decision += " / 缺 %d 粮" % int(rations.shortage)
			route = "巴士到食品点约 %d 秒" % outbound
			if level.primary.size() > 1:
				var second: int = _mission_route_seconds(level, "bus", level.primary[1])
				route = "巴士到两点约 %d / %d 秒" % [outbound, second]
			risk = "可只搜一处，多留会加重敌情"
		"airdrop":
			var sortie_risk: bool = SortieRiskV1.enabled(value)
			reward = "损坏武器 1 件，可回营维修"
			for site: Dictionary in value.sites:
				if site.id == first and site.weapon:
					var definition: WeaponDefinition = WeaponInventory.definition(site.get("drop", {}).get("weapon_id", ""))
					if definition == null:
						break
					var weapon: String = definition.display_name
					var damaged: bool = true
					var item: Dictionary = {}
					reward = "损坏%s 1 件，可回营维修" % weapon
					if not base.is_empty():
						var sortie_id: String = "%s:%d" % [base.profile_id, int(base.settled_sorties) + 1]
						item = WeaponInventory.site_reward(sortie_id, value, site, WeaponState.is_family(base))
						damaged = item.get("condition", "damaged") == "damaged"
						reward = "损坏%s ×1，先维修再配装" % weapon if damaged else "%s ×1，可直接配装" % weapon
					if sortie_risk:
						reward = ("损坏" if damaged else "") + "%s ×1" % weapon
					if not item.is_empty() and damaged and String(definition.id) == CombatEquipment.HAMMER_ID:
						var quote: Dictionary = WeaponInventory.repair_offer(base, item)
						reward += " · %s维修 %d 币" % [quote.source, int(quote.cost)]
					break
			if ContentWaveV1.marked(value):
				reward += _wave_rewards(value)
			elif value.has("gear_build_policy") and not value.build.drops.is_empty():
				reward += " · 被动道具 %d 件" % value.build.drops.size()
			if sortie_risk:
				return _sortie_risk_card_text(value, level, reward)
			route = "露天单程约 %d 秒，回收 %d 秒" % [outbound, int(level.work_seconds[first])]
			if value.layout.has("loading_yard"):
				route = "宽装卸口、折角维修道汇合，回收 %d 秒" % int(level.work_seconds[first])
			risk = "可受击，首次回收最多增援 %d 名" % int(value.parameters.reinforcements)
		"equipment":
			reward = CampaignRules.CLUE_NAMES.get(value.get("investigation", {}).get("clue_id"), "主装备点")
			if ContentWaveV1.marked(value):
				reward += _wave_rewards(value)
			route = "深入约 %d 秒，回车约 %d 秒" % [outbound, _mission_route_seconds(level, first, "bus")]
			risk = "返程较远，额外搜刮会延后回车"
		"rescue":
			reward = RescueTarget.ANONYMOUS_NAME + " ×1"
			var size: String = {"small":"小型", "medium":"中型", "large":"大型"}[value.layout["size"]]
			route = "住宅簇单程约 %d 秒，援救 %d 秒" % [outbound, int(level.work_seconds[first])]
			if value.layout.has("rescue_court"):
				route = "正门直达、侧巷绕墙，援救 %d 秒" % int(level.work_seconds[first])
			route = size + "街区 · " + route
			risk = "需要护送同行者生还归航"
			if not base.is_empty():
				risk = "现场接纳，生还归航确认入队"
	return "主收益 · %s%s\n路线 · %s\n风险 · %s" % [reward, decision, route, risk]


static func _wave_rewards(value: Dictionary) -> String:
	var build: Dictionary = value.get("build", {})
	var items: Dictionary = build.get("policy", {}).get("items", {})
	var rewards: PackedStringArray = []
	for id: String in build.get("drops", []):
		var item: String = items.get(id, {}).get("name", "")
		if not item.is_empty():
			rewards.append(item)
	var power: String = PowerActions.name_for(value.get("powers", {}).get("sample", ""))
	if not power.is_empty():
		rewards.append(power)
	return " · " + " · ".join(rewards) if not rewards.is_empty() else ""


static func _sortie_risk_card_text(value: Dictionary, level: Dictionary, reward: String) -> String:
	var size: String = {"medium":"中型街区", "large":"大型街区"}[value.layout["size"]]
	var round_trip: int = ceili(SortieRiskV1.round_trip_seconds(level))
	var optional: String = ""
	for site: Dictionary in value.sites:
		if site.id != level.optional.site_id:
			continue
		var source: String = {"optional_building":"可选建筑", "vehicle":"停放车辆", "fruit_tree":"果树"}[site.source]
		var resource: String = "货币" if site.kind == "cash" else "食物"
		var added: int = ceili(float(level.optional.single.team_return_seconds) - float(level.single.team_return_seconds))
		optional = "可选 · %s %s +%d，绕路另约 %d 秒（含搜集）\n" % [source, resource, int(site.amount), added]
		break
	return "主收益 · %s\n路线 · %s，步行往返约 %d 秒\n%s风险 · 首次最多增援 %d 名，取到即可撤离" % [
		reward, size, round_trip, optional, int(value.parameters.reinforcements)]


static func _mission_route_seconds(level: Dictionary, from: String, to: String) -> int:
	return ceili(float(level.routes[_key(from, to)].length) / float(level.assumptions.speed))


static func extra_return_seconds(level: Dictionary) -> float:
	if level.primary.size() == 2:
		return float(level.optional.added_team_seconds)
	var site: String = level.optional.site_id
	var routes: Dictionary = level.optional.routes
	var distance: float = float(routes[_key("bus", site)].length) + float(routes[_key(site, "bus")].length)
	var optional_return: float = distance / float(level.assumptions.speed) + float(level.optional.work_seconds)
	return maxf(0.0, optional_return - float(level.two_worker.team_return_seconds))


static func _key(from: String, to: String) -> String:
	return from + ">" + to


static func _route(nav: FieldNavigation, from: Vector2, to: Vector2) -> Dictionary:
	if not from.is_finite() or not to.is_finite() or not nav.is_clear(from) or not nav.is_clear(to):
		return {}
	var path: PackedVector2Array = nav.path_between(from, to)
	if path.is_empty() or path[-1].distance_to(to) > 14.0:
		return {}
	var points: Array = []
	# Grid steps along the same straight segment carry no additional route fact.
	# Keep every turn and endpoint, preserving the exact final-collision polyline.
	for index: int in range(path.size()):
		if index>0 and index<path.size()-1:
			var incoming: Vector2=path[index]-path[index-1]
			var outgoing: Vector2=path[index+1]-path[index]
			if incoming.cross(outgoing)==0.0 and incoming.dot(outgoing)>0.0:
				continue
		points.append([path[index].x, path[index].y])
	return {"length":ExplorationLayout._length(path), "path":points}


static func _estimate(orders: Array, routes: Dictionary, work: Dictionary, tuning: ExpeditionTuning) -> Dictionary:
	var lengths: Array[float] = []
	var working: Array[float] = []
	var returns: Array[float] = []
	var team_return: float = 0.0
	for order: Array in orders:
		var previous: String = "bus"
		var length: float = 0.0
		var seconds: float = 0.0
		for id: String in order:
			length += float(routes[_key(previous, id)].length)
			seconds += float(work[id])
			previous = id
		length += float(routes[_key(previous, "bus")].length)
		var returning: float = length / SPEED + seconds
		lengths.append(length)
		working.append(seconds)
		returns.append(returning)
		team_return = maxf(team_return, returning)
	var wait: float = maxf(0.0, tuning.bus_ready_seconds - team_return)
	return {"orders":orders.duplicate(true), "travel_lengths":lengths, "work_seconds":working, "worker_return_seconds":returns,
		"team_return_seconds":team_return, "bus_ready_wait_seconds":wait, "finish_seconds":team_return + wait + tuning.engine_seconds}
