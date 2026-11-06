extends SceneTree
## Replays fixed requests captured by the ordinary flow, with byte-identical journal prefixes.
var output: String
var source: String
var phase: String

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-output="): output=arg.trim_prefix("--bench-output=")
		if arg.begins_with("--bench-source="): source=arg.trim_prefix("--bench-source=")
		if arg.begins_with("--bench-phase="): phase=arg.trim_prefix("--bench-phase=")
	assert("/.local/" in output and "/.local/" in source and "/.local/" in OS.get_user_data_dir().replace("\\","/"))
	var prepared: int=Time.get_ticks_usec()
	var oracle: Dictionary=RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(source.path_join("first/oracle.json")))).payload
	var journal_source: String=source.path_join("user/Godot/app_userdata/Blue Hour - 蓝时归航/playable-v1/run.enemy-v1.json.txn/journal")
	var result_record: Dictionary=RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(journal_source.path_join("00000008/record.json")))).payload
	var count: int=2 if phase=="suspend" else 6
	var receipt: Dictionary=RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(journal_source.path_join("%08d/record.json"%count)))).payload
	assert(receipt.rules.mission.generated.layout.entities.size()==47)
	var path: String=output.path_join("run.enemy-v1.json")
	var journal: String=path+".txn/journal"
	DirAccess.make_dir_recursive_absolute(journal)
	for index: int in range(1,count+1):
		var relative: String="%08d/record.json"%index
		DirAccess.make_dir_recursive_absolute(journal.path_join(relative).get_base_dir())
		assert(DirAccess.copy_absolute(journal_source.path_join(relative),journal.path_join(relative))==OK)
	write(path,JSON.stringify(receipt.base,"",true,true))
	var root_record: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(journal.path_join("00000001/record.json")))
	var head_record: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(journal.path_join("%08d/record.json"%count)))
	var binding: Dictionary={"binding_version":1,"run_id":receipt.base.profile_id,"root_id":receipt.root_id,"journal":journal,"revision":count,"root_hash":root_record.sha256,"head_hash":head_record.sha256}
	write(path+".txn/binding.json",JSON.stringify({"payload":binding,"sha256":TransactionReceipt.legacy_fingerprint(binding)},"",true,true)+"\n")
	var session: ProductionProgress=ProductionProgress.new(path,true,true,true,true,true,true,true,true,true,true,true,true,true)
	assert(session._problem.is_empty(),session._problem)
	session.suspend_enabled=true
	session._transaction=RunTransaction.new(journal,path,receipt.base.profile_id,receipt.root_id,Callable(),session._writer)
	session.token=RunTransaction.token_for(receipt)
	session._active_base=receipt.base.duplicate(true)
	session._active_rules=receipt.rules.duplicate(true)
	var cold: int=Time.get_ticks_usec()
	var recovered: Dictionary=session._transaction.recover()
	assert(recovered.error==OK,str(recovered))
	var cold_usec: int=Time.get_ticks_usec()-cold
	var report: Dictionary=result_record.envelope.result.battle
	var carried: Dictionary={"loot":report.loot,"food":report.food,"weapons":report.weapons.duplicate(true)}
	var request: Dictionary={"world":oracle.world} if phase=="suspend" else {"report":report,"carried":carried}
	var request_hash: String=RecordEncoding.fingerprint(request)
	var prep_usec: int=Time.get_ticks_usec()-prepared
	FreezeProfile.enabled=true
	FreezeProfile.start({"phase":phase,"buildings":47,"start_generations":count,"request_hash":request_hash,"input_preparation_usec":prep_usec,"cold_restore_usec":cold_usec,"pid":OS.get_process_id()})
	var started: int=Time.get_ticks_usec()
	var answer: Dictionary=session.suspend_world(oracle.world) if phase=="suspend" else session.finish(report,carried)
	var sync_usec: int=Time.get_ticks_usec()-started
	FreezeProfile.finish()
	var profile: Dictionary=FreezeProfile.latest.duplicate(true)
	profile.actual_sync_usec=sync_usec
	profile.waiting_frames_usec=0
	profile.boundary="ProductionProgress.suspend_world durable ACK" if phase=="suspend" else "ProductionProgress.finish result-ready ACK; report and GUI overhead separately measured by normal flow"
	profile.error=answer.error
	profile.reason=answer.get("reason","")
	profile.result_hash=RecordEncoding.fingerprint(answer)
	var durable: Dictionary=session._transaction.recover()
	profile.final_record_hash=durable.get("hash","")
	profile.final_phase=durable.get("receipt",{}).get("phase","")
	if phase=="return" and answer.error==OK:
		var original_input: Dictionary=session.packet.input.duplicate(true)
		var expected: Dictionary=FrozenSettlement._profiled_compute(original_input)
		var alias: Dictionary=FrozenSettlement.compute(original_input)
		assert(TransactionReceipt.same(alias,expected),"cold and cached complete settlement match")
		alias.packet.envelope.result.camp.cash+=100
		assert(TransactionReceipt.same(FrozenSettlement.compute(original_input),expected),"caller cannot mutate cached settlement result")
		var changed_input: Dictionary=original_input.duplicate(true)
		changed_input.report.loot+=1
		assert(not FrozenSettlement.compute(changed_input).error.is_empty(),"nested reward request cannot reuse successful settlement")
		assert(TransactionReceipt.same(FrozenSettlement.compute(original_input),expected),"invalid settlement does not poison valid result")
		profile.settlement_cache_checks=4
	write(output.path_join("profile.json"),JSON.stringify(profile,"\t"))
	session.close()
	print("R2_SAVE_REPLAY ",phase," sync_ms=",sync_usec/1000.0," error=",answer.error," reason=",answer.get("reason",""))
	quit(0 if answer.error==OK else 1)

func write(path: String, content: String) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	assert(file!=null,path)
	file.store_string(content)
	file.close()
