extends SceneTree
## Pure frozen routes; these estimates do not claim actual crew timing or gameplay completion.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func run() -> void:
	var layout: Dictionary = ExplorationLayout.generate("level-summary-final-nav", "medium", "commercial")
	expect(not layout.is_empty(), "real layout fixture completes all prop collisions")
	if layout.is_empty():
		quit(1)
		return
	var content: Dictionary = ExplorationSites.generate(layout, "supply", 2, 4, 0, "1".repeat(64))
	expect(not content.is_empty(), "real sites retain original budget and work")
	if content.is_empty():
		quit(1)
		return
	var before: String = RecordEncoding.fingerprint({"layout":layout, "content":content})
	var value: Dictionary = LevelSummary.freeze(layout, content.sites, content.objective, "supply")
	expect(not value.is_empty(), "final graph yields primary and optional full routes")
	if value.is_empty():
		quit(1)
		return
	expect(RecordEncoding.fingerprint(value) == RecordEncoding.fingerprint(LevelSummary.freeze(layout, content.sites, content.objective, "supply")), "same inputs freeze identically")
	var original: String=RecordEncoding.fingerprint(value)
	value.routes[value.routes.keys()[0]].length+=1.0
	expect(RecordEncoding.fingerprint(LevelSummary.freeze(layout,content.sites,content.objective,"supply"))==original,"returned route mutation never changes a cached successful proof")
	value=LevelSummary.freeze(layout,content.sites,content.objective,"supply")
	var changed_sites: Array=content.sites.duplicate(true)
	changed_sites[0].seconds+=5.0
	expect(RecordEncoding.fingerprint(LevelSummary.freeze(layout,changed_sites,content.objective,"supply"))!=original,"warm cache compares all work/source inputs")
	var changed_layout: Dictionary=layout.duplicate(true)
	changed_layout.bus.door[0]+=24.0
	expect(LevelSummary.freeze(changed_layout,content.sites,content.objective,"supply").is_empty(),"warm cache cannot bless changed geometry")
	expect(before == RecordEncoding.fingerprint({"layout":layout, "content":content}), "summary never mutates geometry, sites or objectives")
	expect(SurvivalContracts.json_value(value), "all route evidence is finite JSON data")
	expect(float(value.two_worker.team_return_seconds) <= float(value.single.team_return_seconds), "two dispatched food workers wait for the slower return")
	expect(value.optional.added_team_seconds > 0.0 and value.optional.work_seconds > 0.0, "extra content has real work and whole-team time cost")
	var nav: FieldNavigation = ExplorationLayout._routing(layout).nav
	for key: String in value.routes:
		var route: Dictionary = value.routes[key]
		var path: PackedVector2Array = []
		for point: Array in route.path:
			path.append(WorldLayout.point(point))
			expect(nav.is_clear(path[-1]), "frozen route stays clear after all object collisions " + key)
		expect(is_equal_approx(ExplorationLayout._length(path), float(route.length)), "length is measured from the saved real path " + key)
	var generated: Dictionary = {"type":"supply", "exploration":{"level":value}}
	var text: String = LevelSummary.description(generated)
	expect(text.contains("工作因子1") and text.contains("确认后生效"), "card distinguishes baseline estimate and actual banked reward")
	expect(not text.contains("安全剩余") and not text.contains("难度"), "card never invents a safety countdown or difficulty tier")
	var rescue: Dictionary = LevelSummary.freeze(layout, content.sites, {"site_ids":[]}, "rescue")
	expect(not rescue.is_empty() and rescue.primary == ["rescue"] and rescue.work_seconds.rescue == RescueTarget.SECONDS, "rescue uses its real frozen point and original ten second work")
	print(JSON.stringify({"suite":"level_summary", "checks":checks, "failures":failures, "scope":"PURE_FINAL_NAV_ROUTE_ESTIMATES"}))
	quit(1 if failures else 0)
