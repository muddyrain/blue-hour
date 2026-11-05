extends SceneTree
## Pure wording fixtures; the existing owner supplies occupancy, phase and stable IDs.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("SEARCH_WORK_VIEW_FAIL " + label)


func run() -> void:
	_test_sites()
	_test_members()
	_test_notices()
	print("SEARCH_WORK_VIEW checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_sites() -> void:
	expect(SearchWorkView.short_site("便利店", 1) == "便利店01", "stable one-based number is explicit")
	expect(SearchWorkView.short_site("联排住宅", 12) == "联排住宅12", "four-character title is retained")
	expect(SearchWorkView.short_site("便利店", 1) != SearchWorkView.short_site("便利店", 2), "same building type remains distinguishable")
	expect(SearchWorkView.short_site("旧街仓储补给中心", 3) == "旧街仓…03", "long title has bounded four-character prefix")
	expect(SearchWorkView.short_site("", 4) == "站点04", "empty title keeps stable number")
	expect(SearchWorkView.short_site("  超市\n\t", 5) == "超市05", "single-line title trims control characters")
	var labels: Array[String] = []
	for number: int in [8, 2, 11]:
		labels.append(SearchWorkView.short_site("联排住宅", number))
	expect(labels == ["联排住宅08", "联排住宅02", "联排住宅11"], "display never sorts or renumbers supplied identity")
	expect(SearchWorkView.actor_status("approach", "旧街仓储补给中心09", false) == "前往·旧街仓…09", "caller long site label preserves numeric suffix")
	expect(SearchWorkView.actor_status("working", "超市02", false) == "搜寻·超市02", "short label is not renumbered")
	expect(SearchWorkView.actor_status("working", "", false) == "搜寻·站点", "missing label is readable without inventing a number")


func _test_members() -> void:
	var names: Array[String] = ["许澄", "程砚", "沈听澜", "陆闻溪"]
	var titles: Array[String] = ["便利店", "联排住宅", "储物棚", "空投"]
	var phases: Array[String] = ["approach", "working", "working", "working"]
	var outdoor: Array[bool] = [false, false, false, true]
	var seen_buildings: Array[String] = []
	var seen_status: Array[String] = []
	for index: int in range(4):
		var site: String = SearchWorkView.short_site(titles[index], index + 1)
		var text: String = SearchWorkView.building_text(index + 1, names[index], phases[index], outdoor[index])
		var status: String = SearchWorkView.actor_status(phases[index], site, outdoor[index])
		seen_buildings.append(text)
		seen_status.append(status)
		expect(text.begins_with("%02d " % [index + 1]) and text.contains(names[index]), "member %d keeps stable identity and name" % [index + 1])
		expect(text.ends_with("再点取消") and not text.contains("\n"), "member %d building offers local cancellation in one line" % [index + 1])
		expect(status.contains("%02d" % [index + 1]) and status.length() <= 9, "member %d HUD stays compact and identifies building" % [index + 1])
	expect(seen_buildings.slice(0, 3) == ["01 许澄·前往·再点取消", "02 程砚·搜寻·再点取消", "03 沈听澜·搜寻·再点取消"], "three-member work text maps phases separately")
	expect(seen_buildings[3] == "04 陆闻溪·回收·再点取消" and seen_status[3] == "回收·空投04", "fourth member explicitly works outdoors")
	expect(seen_status == ["前往·便利店01", "搜寻·联排住宅02", "搜寻·储物棚03", "回收·空投04"], "four members retain independent destinations and phase")
	expect(SearchWorkView.actor_status("approach", "空投04", true) == "前往·空投04", "outdoor approach does not pretend recovery started")
	expect(SearchWorkView.actor_status("working", "仓库05", false) != SearchWorkView.actor_status("working", "仓库05", true), "indoor search differs from outdoor recovery")
	expect(SearchWorkView.building_text(3, "非常非常长的幸存者呼号", "working", false) == "03 非常…·搜寻·再点取消", "long call sign remains bounded")
	expect(SearchWorkView.building_text(1, "", "approach", false) == "01 队员·前往·再点取消", "missing name falls back without changing member number")
	expect(SearchWorkView.building_text(2, "程\n砚\t", "working", true) == "02 程砚·回收·再点取消", "control characters cannot add label lines")
	expect(SearchWorkView.building_text(0, "许澄", "working", false).is_empty(), "unoccupied building has no worker claim or cancel prompt")
	expect(SearchWorkView.building_text(-1, "许澄", "approach", false).is_empty(), "missing worker sentinel is empty")
	for phase: String in ["", "cancelled", "completed", "idle", "queue"]:
		expect(SearchWorkView.actor_status(phase, "超市01", false).is_empty(), "inactive or unknown phase never claims HUD work: " + phase)
		expect(SearchWorkView.building_text(1, "许澄", phase, false).is_empty(), "inactive or unknown phase never claims building occupancy: " + phase)


func _test_notices() -> void:
	var site: String = SearchWorkView.short_site("联排住宅", 3)
	expect(SearchWorkView.notice("assigned", site, "03 沈听澜") == "已派遣03 沈听澜前往联排住宅03。", "assignment identifies actual member and building")
	expect(SearchWorkView.notice("assigned", site) == "已派遣队员前往联排住宅03。", "optional member label has readable fallback")
	var cancelled: String = SearchWorkView.notice("cancelled", site, "03 沈听澜")
	expect(cancelled.contains("取消") and cancelled.contains("进度保留") and cancelled.contains("联排住宅03"), "cancel notice preserves destination and progress policy")
	expect(not cancelled.contains("完成") and not cancelled.contains("奖励"), "cancellation does not imply completion or rewards")
	var no_idle: String = SearchWorkView.notice("no_idle", site)
	expect(no_idle.contains("暂无空闲队员") and no_idle.contains("未派遣"), "all busy notice does not claim assignment")
	var unreachable: String = SearchWorkView.notice("unreachable", site)
	expect(unreachable.contains("无法到达") and unreachable.contains("未派遣") and unreachable.contains("03"), "unreachable notice identifies rejected building")
	var completed: String = SearchWorkView.notice("completed", site, "03 沈听澜")
	expect(completed.contains("已完成") and completed.contains("归队") and not completed.contains("取消"), "completion separates result from cancellation")
	expect(SearchWorkView.notice("unknown", site).is_empty() and SearchWorkView.notice("", site).is_empty(), "unknown notice code does not invent outcome")
	var long_notice: String = SearchWorkView.notice("assigned", "很长很长的住宅搜寻站点19", "很长很长的幸存者名字与编号")
	expect(long_notice.contains("19") and long_notice.length() <= 25 and not long_notice.contains("\n"), "long notice remains bounded and keeps stable number")
	for code: String in ["assigned", "cancelled", "no_idle", "unreachable", "completed"]:
		expect(not SearchWorkView.notice(code, "").is_empty(), "known notice remains readable with missing display label: " + code)
