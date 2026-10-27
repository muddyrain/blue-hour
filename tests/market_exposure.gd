extends SceneTree
## Paired real production trials; only authored geometry differs between A and B.

const ALayout: StreetLayout = preload("res://src/app/playtest_maps/market_loop_a.tres")
const BLayout: StreetLayout = preload("res://src/app/playtest_maps/market_loop_b.tres")
const SEEDS: Array[int] = [3103,4103,5103,6103,7103]
const OFFSETS: Array[int] = [-16,-8,0,8,16]

var _checks: Array[Dictionary] = []
var _failures: int = 0
var _rows: Array[Dictionary] = []
var _hits: Array[Dictionary] = []
var _cue: float = -1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for label: String in ["A","B","B-avoid"]:
		for n: int in range(5):
			await _trial(label,n)
	var a_loss: float = 0.0
	var b_loss: float = 0.0
	var avoid_loss: float = 0.0
	for row: Dictionary in _rows:
		if row.label == "A":
			a_loss += float(row.damage)
		elif row.label == "B":
			b_loss += float(row.damage)
		else:
			avoid_loss += float(row.damage)
	_expect(a_loss == 0.0 and b_loss > a_loss,"all prelocked paired trials reveal real B contact beyond safe A")
	_expect(avoid_loss < b_loss and avoid_loss == 0.0,"same B trials allow timely cue-driven avoidance to reduce actual damage")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			var path: String = argument.trim_prefix("--bh-progress=").get_base_dir()
			DirAccess.make_dir_recursive_absolute(path)
			var file: FileAccess = FileAccess.open(path.path_join("market-exposure.json"),FileAccess.WRITE)
			file.store_string(JSON.stringify({"checks":_checks,"failures":_failures,"rows":_rows},"\t")+"\n")
	print("BH_MARKET_EXPOSURE checks=%d failures=%d A_loss=%.1f B_loss=%.1f avoid_loss=%.1f" % [_checks.size(),_failures,a_loss,b_loss,avoid_loss])
	quit(0 if _failures == 0 else 1)


func _trial(label: String, n: int) -> void:
	seed(SEEDS[n])
	_hits = []
	_cue = -1.0
	var campaign: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/m5-combat-02/normal/market/saved-run.json")) as Dictionary
	var supply: MissionSupply = preload("res://src/features/camp/supermarket.tres").duplicate(true)
	supply.layout = ALayout if label == "A" else BLayout
	var sortie: Expedition = Expedition.new()
	sortie.supply = supply
	sortie.crew_snapshot.assign(campaign.crew)
	sortie.loadout_snapshot = WeaponInventory.snapshot(campaign)
	root.add_child(sortie)
	sortie.set_physics_process(false)
	sortie.camera.zoom = Vector2.ONE * 1.1
	sortie.camera.position = Vector2(744,840)
	sortie.camera.force_update_scroll()
	sortie.combat_feedback.connect(func(event: Dictionary) -> void:
		if event.kind == "hit":
			_hits.append(event.duplicate(true))
		elif event.kind == "shot" and event.foot_distance < 100.0 and _cue < 0.0:
			_cue = float(event.elapsed))
	sortie.request_search(&"cash")
	sortie.command_move(Vector2(568,864+OFFSETS[n]))
	_expect(sortie.search_actor.actor_id == 0 and sortie.survivors[1].weapon_definition.id == &"carbine","same worker and actual v5 guard weapon on "+label+str(SEEDS[n]))
	var acted: bool = false
	var ordered: bool = false
	var gathered: bool = false
	var foot_clear: bool = true
	for frame: int in range(10800):
		if label == "B-avoid" and not acted and _cue >= 0.0 and sortie.elapsed >= _cue+0.25:
			if sortie.search_actor != null:
				sortie.request_search(&"cash")
			sortie.command_move(sortie.layout.bus_door)
			acted = true
		if not ordered and (sortie.elapsed >= 90.0 or acted):
			sortie.request_extraction()
			ordered = sortie.phase == Expedition.Phase.ENGINE
		if ordered and not gathered and sortie.phase == Expedition.Phase.BOARDING:
			sortie.request_bus_gather()
			gathered = true
		sortie.step(1.0/60.0)
		for enemy: FieldActor in sortie.enemies:
			foot_clear = foot_clear and sortie.navigation.is_clear(enemy.position)
		if sortie.phase == Expedition.Phase.FINISHED:
			break
		if frame%1200 == 0:
			await process_frame
	var loss: float = 400.0-sortie.survivors[0].health-sortie.survivors[1].health
	var actual: float = 0.0
	for hit: Dictionary in _hits:
		actual += float(hit.applied_damage)
	_expect(is_equal_approx(actual,loss) and sortie.survivors[0].health == 200.0,"real hit sums match health; worker is never given fake injury")
	_expect(foot_clear and sortie.phase == Expedition.Phase.FINISHED and sortie.living_count() == 2,"ordinary original navigation permits a safe two-person evacuation")
	_expect(sortie.tuning.enemy_health == 54.0 and sortie.tuning.enemy_speed == 34.0 and sortie.tuning.enemy_damage == 4.0 and sortie.tuning.spawn_seconds == 7.0 and not sortie.is_practice,"trial retains original stats and ordinary director")
	_rows.append({"label":label,"seed":SEEDS[n],"damage":loss,"hits":_hits.size(),"health":[sortie.survivors[0].health,sortie.survivors[1].health],"cue":_cue,"acted":acted,"searched":sortie.searched,"loot":sortie.loot,"elapsed":sortie.elapsed})
	sortie.queue_free()
	await process_frame


func _expect(passed: bool, label: String) -> void:
	_checks.append({"passed":passed,"label":label})
	if not passed:
		_failures += 1
		push_error(label)
