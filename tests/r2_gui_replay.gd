extends "res://tests/worldgen_flow.gd"
## Full Main callback replay from original synthetic suspend records. No gameplay owner changes.
var fixture: String
var bench_phase: String
var expected_world: Dictionary
var original_result: Dictionary
var setup_started: int

func _run() -> void:
	setup_started=Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-source="): fixture=arg.trim_prefix("--bench-source=")
		if arg.begins_with("--bench-phase="): bench_phase=arg.trim_prefix("--bench-phase=")
	assert("/.local/" in fixture and "/.local/" in OS.get_user_data_dir().replace("\\","/"))
	var source_journal: String=fixture.path_join("user/Godot/app_userdata/Blue Hour - 蓝时归航/playable-v1/run.enemy-v1.json.txn/journal")
	var count: int=3 if bench_phase=="suspend" else 5
	var receipt: Dictionary=decode(source_journal.path_join("%08d/record.json"%count))
	original_result=decode(source_journal.path_join("00000008/record.json"))
	expected_world=receipt.envelope.world.duplicate(true)
	assert(expected_world.generated.layout.entities.size()==47)
	var path: String=PlayableEntry.progress_path()
	var journal: String=path+".txn/journal"
	assert(not FileAccess.file_exists(path))
	DirAccess.make_dir_recursive_absolute(journal)
	for index: int in range(1,count+1):
		var relative: String="%08d/record.json"%index
		DirAccess.make_dir_recursive_absolute(journal.path_join(relative).get_base_dir())
		assert(DirAccess.copy_absolute(source_journal.path_join(relative),journal.path_join(relative))==OK)
	write_file(path,JSON.stringify(receipt.base,"",true,true))
	var root_record: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(journal.path_join("00000001/record.json")))
	var head_record: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(journal.path_join("%08d/record.json"%count)))
	var binding: Dictionary={"binding_version":1,"run_id":receipt.base.profile_id,"root_id":receipt.root_id,"journal":journal,"revision":count,"root_hash":root_record.sha256,"head_hash":head_record.sha256}
	write_file(path+".txn/binding.json",JSON.stringify({"payload":binding,"sha256":TransactionReceipt.legacy_fingerprint(binding)},"",true,true)+"\n")
	for sentinel: String in ["user://saves/run.json","user://saves/run.enemy-v1.json","user://settings/audio.json"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sentinel).get_base_dir())
		write_file(sentinel,"M6 synthetic protected old file; must never be read as playable or migrated")
	await super._run()

func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition=app.expedition
	_check(world!=null,"normal Continue reconstructs the original 47-building world")
	if world==null:
		return
	world.set_process(false)
	world.set_physics_process(false)
	var actual: Dictionary=SortieSnapshot.capture(world)
	_check(RecordEncoding.fingerprint(actual)==RecordEncoding.fingerprint(expected_world),"normal Continue restores exact frozen world before timed request")
	var head: Dictionary=app.progress_session._transaction.recover()
	_check(head.error==OK and int(head.receipt.revision)==(4 if bench_phase=="suspend" else 6),"normal Continue claims exactly one original generation")
	var report: Dictionary=original_result.envelope.result.battle
	var carried: Dictionary={"loot":world.loot,"food":world.food_loot,"weapons":world.weapon_loot.duplicate(true)}
	if bench_phase=="return":
		_check(TransactionReceipt.same(carried,{"loot":report.loot,"food":report.food,"weapons":report.weapons}),"actual restored carry matches the original fixed return request")
	var request: Dictionary={"world":actual} if bench_phase=="suspend" else {"report":report,"carried":carried}
	var input_hash: String=RecordEncoding.fingerprint(request)
	FreezeProfile.enabled=true
	FreezeProfile.start({"phase":bench_phase,"buildings":47,"pid":OS.get_process_id(),"request_hash":input_hash,"start_generations":head.receipt.revision,"setup_and_restore_usec":Time.get_ticks_usec()-setup_started})
	var started: int=Time.get_ticks_usec()
	if bench_phase=="suspend":
		app.suspend_sortie()
	else:
		app._on_expedition_finished(report,app._active_sortie_id)
	var synchronous_usec: int=Time.get_ticks_usec()-started
	FreezeProfile.finish()
	var profile: Dictionary=FreezeProfile.latest.duplicate(true)
	profile.actual_sync_usec=synchronous_usec
	profile.boundary="Main.suspend_sortie including fresh capture, durable ACK and title UI" if bench_phase=="suspend" else "Main._on_expedition_finished including original fixed report, durable result and result UI; no report generation in this replay"
	var wait_started: int=Time.get_ticks_usec()
	await _hold(3)
	profile.waiting_frames_usec=Time.get_ticks_usec()-wait_started
	var durable: Dictionary=app.progress_session._transaction.recover()
	profile.final_record_hash=durable.get("hash","")
	profile.final_phase=durable.get("receipt",{}).get("phase","")
	profile.error=durable.error
	_check(durable.error==OK and profile.final_phase==("SUSPEND_READY" if bench_phase=="suspend" else "RESULT_READY"),"full callback obtains its durable acknowledgement")
	if bench_phase=="suspend":
		_check(app.expedition==null and app._requires_continue,"title is shown only after durable suspend")
	else:
		_check(not app._pending_settlement.is_empty() and not app._progress_blocked,"original result UI receives the frozen settlement")
	profile.failures=failures
	_write("profile.json",profile)
	print("R2_GUI_REPLAY ",bench_phase," sync_ms=",synchronous_usec/1000.0," failures=",failures)

func decode(path: String) -> Dictionary:
	var value: Dictionary=RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(path)))
	assert(value.error==OK,path)
	return value.payload

func write_file(path: String, content: String) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	assert(file!=null,path)
	file.store_string(content)
	file.close()
