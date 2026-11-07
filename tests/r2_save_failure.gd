extends SceneTree
## A bounded real journal fault representative, with synthetic normal-entry progress only.
var failures: int=0
var checks: int=0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("R2_SAVE_FAILURE ",label)

func run() -> void:
	assert("/.local/" in OS.get_user_data_dir().replace("\\","/"))
	var app: Node=load("res://src/app/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._new_game()
	app._select_mission(DailyActions.supply(DailyActions.offers(app.camp_snapshot())[0]))
	var world: Expedition=app.expedition
	expect(world!=null,"normal isolated entry starts before fault injection")
	if world==null:
		await finish(app)
		return
	world.set_process(false)
	world.set_physics_process(false)
	app.open_pause_menu()
	var captured: Dictionary=SortieSnapshot.capture(world)
	var session: ProductionProgress=app.progress_session
	var prior: Dictionary=session._transaction.recover()
	expect(prior.error==OK,"original strict transaction authenticates")
	var preview: Dictionary=session.preview_suspend(captured)
	expect(not captured.is_empty() and preview.error==OK,"normal paused snapshot authenticates before injecting a write fault: "+str(preview.get("reason","")))
	if captured.is_empty() or preview.error!=OK:
		await finish(app)
		return
	session.fault_hook=func(point: String) -> Error: return ERR_CANT_CREATE if point=="before_record_write" else OK
	var failed: Dictionary=session.suspend_world(captured)
	expect(failed.error!=OK and not failed.get("acknowledged",false) and failed.get("reason","")=="INJECTED_RECORD_WRITE","actual injected write failure never acknowledges suspend: "+str(failed.get("reason","")))
	session.fault_hook=Callable()
	var unchanged: Dictionary=session._transaction.recover()
	expect(unchanged.error==OK and unchanged.hash==prior.hash,"failed write retains exact authoritative head")
	var saved: Dictionary=session.suspend_world(captured)
	expect(saved.error==OK and saved.get("acknowledged",false) and saved.receipt.phase=="SUSPEND_READY","retry durably acknowledges the same snapshot: "+str(saved.get("reason","")))
	if saved.error!=OK or not saved.get("receipt",{}).has("revision"):
		await finish(app)
		return
	var duplicate: Dictionary=session.suspend_world(captured)
	expect(duplicate.error==OK and duplicate.hash==saved.hash,"duplicate suspend does not add a generation")
	var journal: ReceiptJournal=session._transaction._journal
	var path: String=journal.directory.path_join("%08d/record.json"%int(saved.receipt.revision))
	var original: String=FileAccess.get_file_as_string(path)
	write(path,original.substr(0,int(original.length()/2)))
	expect(session._transaction.recover().error!=OK,"warm successful proof cannot hide a truncated actual record")
	write(path,original)
	expect(session._transaction.recover().error==OK,"restored original remains recoverable after rejected truncation")
	var changed: Dictionary=captured.duplicate(true)
	changed.survivors[0].state.health-=1.0
	expect(session.suspend_world(changed).error!=OK,"same generation rejects changed nested actor request")
	expect(session.suspend_world(captured).error==OK,"rejected request does not poison the exact valid retry")
	await finish(app)

func finish(app: Node) -> void:
	app.audio.shutdown()
	await create_timer(0.2).timeout
	app.queue_free()
	await process_frame
	print("R2_SAVE_FAILURE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures==0 else 1)

func write(path: String, content: String) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(content)
	file.flush()
	file.close()
