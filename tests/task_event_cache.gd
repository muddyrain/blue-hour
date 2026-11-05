extends "res://tests/task_flow.gd"
## Warm R1 proofs must never authenticate changed new event facts in real receipt bytes.
func _journey() -> void:
	await super._journey()
	var journal: ReceiptJournal = app.progress_session._transaction._journal
	var valid: Dictionary = journal.read_all()
	_check(valid.error==OK and valid.receipt.phase=="SUSPEND_READY","real partial crate is durably suspended before cache negatives")
	if valid.error!=OK: return
	var path: String = journal.directory.path_join("%08d/record.json"%int(valid.receipt.revision))
	var original: String = FileAccess.get_file_as_string(path)
	var digest: String = FileAccess.get_sha256(path)
	for kind: String in ["trigger","unknown","identity"]:
		var changed: Dictionary = valid.receipt.duplicate(true)
		if kind=="trigger": changed.envelope.world.task_event.started=false
		elif kind=="unknown": changed.envelope.world.task_event.extra=true
		else: changed.envelope.world.task_event.resolutions[0].enemy_id=9999
		changed.envelope.world_hash=SurvivalContracts.fingerprint(changed.envelope.world)
		var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
		file.store_string(RecordEncoding.stringify(changed)); file.close()
		_check(journal.read_all().error!=OK,"warm full-byte proof rejects rehashed task event "+kind)
		file=FileAccess.open(path,FileAccess.WRITE); file.store_string(original); file.close()
		_check(journal.read_all().error==OK and FileAccess.get_sha256(path)==digest,"negative restores exact original receipt "+kind)
