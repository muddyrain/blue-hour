extends SceneTree
## Exercise cached journal authority through rereads of changed real record bytes.
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("JOURNAL_CACHE_FAIL ", label)


func run() -> void:
	assert("/.local/" in OS.get_user_data_dir().replace("\\", "/"))
	var app: Node = load("res://src/app/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._new_game("scavenge", {"version":CatalogProgress.VERSION, "unlock":""}, {"version":OpeningBuild.POLICY_VERSION, "eligible":[]})
	app._select_mission(DailyActions.supply(DailyActions.offers(app.camp_snapshot())[0]))
	app.expedition.set_physics_process(false)
	app.expedition.set_process(false)
	var transaction: RunTransaction = app.progress_session._transaction
	var journal: ReceiptJournal = transaction._journal
	var valid: Dictionary = journal.read_all()
	expect(valid.error == OK, "strict signed fixture authenticates")
	var source: String = journal.directory.path_join("%08d/record.json" % int(valid.receipt.revision))
	var original: String = FileAccess.get_file_as_string(source)
	var alias: Dictionary = journal.read_all()
	alias.receipt.rules.mission.generated.layout.entities[0].rect[0] += 16
	expect(TransactionReceipt.same(journal.read_all().receipt, valid.receipt), "caller mutation cannot poison cached receipt")
	for kind: String in ["geometry", "budget", "record", "death", "task", "template"]:
		var changed: Dictionary = valid.receipt.duplicate(true)
		if kind == "geometry":
			changed.rules.mission.generated.layout.entities[0].rect[0] += 16
		elif kind == "budget":
			changed.rules.mission.generated.cash += 1
		elif kind == "record":
			changed.rules.data_version = 999
		elif kind == "task":
			changed.rules.mission.generated.objective.site_ids=["foreign"]
		elif kind == "template":
			changed.rules.mission.generated.template_version=999
		else:
			changed.deaths.append({"member_id":1})
		write(source, RecordEncoding.stringify(changed))
		expect(journal.read_all().error != OK, "warm cache rejects rehashed changed " + kind)
		write(source, original)
		expect(journal.read_all().error == OK, "exact original restored after negative " + kind)
		changed.revision += 1
		expect(journal.append(changed, valid.hash).error != OK, "append still validates mutated " + kind)
	write(source, original + " ")
	expect(journal.read_all().error == OK, "new raw identity with identical payload remains valid")
	write(source, original)
	var root_path: String = journal.directory.path_join("00000001/record.json")
	var root_original: String = FileAccess.get_file_as_string(root_path)
	var early: Dictionary = RecordEncoding.unpack(JSON.parse_string(root_original)).payload
	early.base.cash += 1
	write(root_path, RecordEncoding.stringify(early))
	expect(transaction.recover().error != OK, "changed earlier history rejected with unchanged latest record")
	write(root_path, root_original)
	expect(transaction.recover().error == OK, "original complete chain remains readable")
	journal.fault = func(point: String) -> Error:
		return ERR_CANT_OPEN if point == "before_directory_list" else OK
	expect(journal.read_all().error != OK, "warm cache never bypasses directory failure")
	journal.fault = Callable()
	write(source, "not json")
	expect(journal.read_all().error != OK, "warm cache rejects unreadable replacement")
	write(source, original)
	expect(transaction.recover().error == OK, "original binding/head intact after all negative cases")
	journal = null
	transaction = null
	app.audio.shutdown()
	await create_timer(0.2).timeout
	app.queue_free()
	await process_frame
	print("JOURNAL_CACHE checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()
