class_name AnimPlaytest
extends EnemyPlaytest
## Reuses original real gameplay probes in this task's isolated output directory.


func _task_path() -> String:
	return "/.local/m5-anim-01/"


func _run() -> void:
	if not "--camp-case=motion" in OS.get_cmdline_user_args():
		await super._run()
		return
	if not output_dir.is_absolute_path() or _task_path() not in output_dir.replace("\\", "/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	await _settle()
	await _enter()
	_initial = app.camp_snapshot()
	var digest: String = _digest()
	app.get_node("Interface/Screen").hide()
	var result: Dictionary = await MotionProbe.run(get_tree(), _initial, _capture)
	for row: Dictionary in result.samples:
		_expect(row.actual_melee and row.moving_fire and row.enemy_dead, "real hit/moving fire/defeat for " + row.identity + " / " + row.gun)
	_expect(result.survivor_death.health == 0 and result.survivor_death.state == "defeated" and not result.survivor_death.gun_visible, "actual AI survivor death clears gun")
	_expect(result.heavy.actor_hp == 194 and result.heavy.enemy_hp == 0 and result.heavy.moved, "heavy actual windup hit and next strike cancelled by movement")
	_expect(result.rush.turned and result.rush.hidden_target_reset and result.rush.enemy_hp == 0, "rush actual acceleration turn target loss and death")
	_expect(_digest() == digest, "controlled visual fixtures preserve real camp bytes")
	_write(output_dir.path_join("motion-combat.json"), result)
	app.get_node("Interface/Screen").show()
	await _finish_camp()
