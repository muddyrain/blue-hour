extends SceneTree
## Red-capable melee feedback: real default AI/step/damage, no direct health writes.

var _hits: Array[Dictionary] = []
var _checks: Array[Dictionary] = []
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var sortie: Expedition = Expedition.new()
	sortie.is_practice = true
	sortie.set_physics_process(false)
	root.add_child(sortie)
	sortie.combat_feedback.connect(func(event: Dictionary) -> void:
		if event.kind == "hit":
			_hits.append(event.duplicate(true)))
	sortie.practice_incoming(Vector2.RIGHT,24.0)
	sortie.practice_incoming(Vector2.LEFT,24.0)
	_expect(sortie.enemies.all(func(enemy: FieldActor) -> bool: return sortie.navigation.is_clear(enemy.position)),"explicit near-start feet are legal on the actual map")
	sortie.step(1.0/60.0)
	_expect(_hits.size() == 2 and sortie.survivors[0].health == 192.0,"two real default enemy attacks reduce actual health by8")
	_expect(sortie.enemies.all(func(enemy: FieldActor) -> bool: return is_equal_approx(enemy.cooldown,1.1)),"actual attacks reset original enemy cooldown")
	sortie.toggle_pause()
	var point: Vector2 = sortie.enemies[0].position
	var clock: float = sortie.elapsed
	sortie.step(2.2)
	_expect(sortie.elapsed == clock and sortie.survivors[0].health == 192.0 and _hits.size() == 2 and sortie.enemies[0].position == point and is_equal_approx(sortie.enemies[0].cooldown,1.1),"pause spans two melee cycles without movement, timer, health or cooldown progress")
	sortie.toggle_pause()
	sortie.step(1.0/60.0)
	_expect(_hits.size() == 2,"resume does not pay queued wall-clock attacks")
	for frame: int in range(178):
		sortie.step(1.0/60.0)
	var emitted: float = 0.0
	for event: Dictionary in _hits:
		emitted += float(event.applied_damage)
	_expect(_hits.size() >= 3 and emitted > 8.0,"remaining default enemy genuinely attacks again after simulation cooldown")
	_expect(is_equal_approx(emitted,400.0-sortie.survivors[0].health-sortie.survivors[1].health) and is_equal_approx(emitted,sortie.survivors[0].damage_received+sortie.survivors[1].damage_received),"actual health loss, hit events and received-damage service inputs agree")
	_expect(sortie._hud.view._members[0].health.text == "生命 %d / 200" % ceili(sortie.survivors[0].health),"real HUD reads the resulting health")
	var health: Array[float] = [sortie.survivors[0].health,sortie.survivors[1].health]
	sortie._finish(true)
	sortie.step(5.0)
	_expect(health == [sortie.survivors[0].health,sortie.survivors[1].health],"finished simulation cannot apply later attacks")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			var path: String = argument.trim_prefix("--bh-progress=").get_base_dir()
			DirAccess.make_dir_recursive_absolute(path)
			var file: FileAccess = FileAccess.open(path.path_join("contact-damage.json"),FileAccess.WRITE)
			file.store_string(JSON.stringify({"checks":_checks,"failures":_failures,"hits":_hits,"health":health},"\t")+"\n")
	print("BH_CONTACT_DAMAGE checks=%d failures=%d hits=%d health=%s" % [_checks.size(),_failures,_hits.size(),health])
	sortie.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)


func _expect(passed: bool, label: String) -> void:
	_checks.append({"passed":passed,"label":label})
	if not passed:
		_failures += 1
		push_error(label)
