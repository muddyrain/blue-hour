extends "res://tests/m48_campaign_flow.gd"
## Real old M47 terminal/catalog cold-read followed by ordinary M48 registration.
## Covers M31 unlocked-but-undiscovered state; no discovery or reward is fabricated.

const LEGACY_PROOF_LIMIT: int = 4_194_304
const LEGACY_XP: Dictionary = {"scavenge":2, "firepower":0, "support":0}
const LEGACY_UNLOCK: String = "stride_harness_v1"

var _legacy_proof_path: String = ""
var _legacy_report_path: String = ""
var _legacy_slot: String = ""
var _legacy_proof: Dictionary = {}
var _legacy_report: Dictionary = {}
var _legacy_input_hashes: Dictionary = {}
var _legacy_catalog_before: Dictionary = {}
var _legacy_journal_before: Dictionary = {}
var _legacy_save_before: String = ""
var _legacy_backup_before: String = ""
var _legacy_preflight: Array[String] = []


func _initialize() -> void:
	# Capture source witnesses before main._ready() performs its first catalog refresh.
	_legacy_proof_path = _argument("--legacy-catalog-proof=")
	_legacy_slot = PlayableEntry.progress_path()
	if not _legacy_local(_legacy_slot) or not _legacy_local(_legacy_proof_path):
		_legacy_preflight.append("proof and original bound profile must remain in project .local")
	else:
		_legacy_report_path = _legacy_proof_path.get_base_dir().path_join("report.json")
		_legacy_proof = _legacy_document(_legacy_proof_path)
		_legacy_report = _legacy_document(_legacy_report_path)
		for path: String in [_legacy_proof_path, _legacy_report_path]:
			_legacy_input_hashes[path] = FileAccess.get_sha256(path)
		_legacy_catalog_before = _legacy_manifest(_legacy_slot + ".catalog")
		_legacy_journal_before = _legacy_manifest(_legacy_slot + ".txn")
		_legacy_save_before = FileAccess.get_sha256(_legacy_slot)
		if FileAccess.file_exists(_legacy_slot + ".bak"):
			_legacy_backup_before = FileAccess.get_sha256(_legacy_slot + ".bak")
	super()


func _journey() -> void:
	_check(false, "legacy catalog probe requires --flow-resume and the original completed profile")


func _resume() -> void:
	_check(DisplayServer.get_name() != "headless", "legacy catalog evidence uses a native rendered viewport")
	_check(_legacy_preflight.is_empty(), "explicit original proof and report are readable: " + str(_legacy_preflight))
	if DisplayServer.get_name() == "headless" or not _legacy_preflight.is_empty(): return
	var expected_unlock: Variant = _legacy_proof.get("unlock")
	var expected_hash: Variant = _legacy_proof.get("unlock_hash")
	var expected_old: Variant = _legacy_report.get("camp")
	var valid_proof: bool = _legacy_proof.get("error") == OK and expected_unlock is Dictionary \
		and not expected_unlock.is_empty() and expected_hash is String and expected_hash.length() == 64 \
		and _legacy_xp(_legacy_proof.get("specialties")) and _legacy_proof.get("discovery") == {} \
		and _legacy_proof.get("specialty_discoveries") == {} and expected_old is Dictionary \
		and _legacy_report.get("failures") == 0 and SurvivalContracts.integer(_legacy_report.get("pid"), 1, 2_147_483_647)
	_check(valid_proof, "baseline proof contains a real nonempty unlock, scavenge XP2 and no discoveries")
	if not valid_proof: return
	_check(int(_legacy_report.pid) != OS.get_process_id(), "current reader is an independent PID from the baseline victory")
	_check(app.progress_path == _legacy_slot and app.progress_session._writer.owns(_legacy_slot),
		"current reader retains the exact original canonical path and writer")
	var state: Dictionary = app.progress_session.inspect()
	var old: Dictionary = state.get("camp", {})
	var old_is_m47: bool = state.get("error") == OK and state.get("state") == "ENDED" \
		and old.get("journey", {}).get("campaign", {}).get("outcome") == "VICTORY" \
		and OpeningBuild.is_m47(old) and not old.journey.campaign.has("economy") \
		and not old.journey.build.has("progression") \
		and SurvivalContracts.integer(old.journey.build.powers.get("version"), SpecialPowers.M47_VERSION, SpecialPowers.M47_VERSION)
	_check(old_is_m47, "cold reader authenticates an actually completed M47 source without adding M48 fields")
	if not old_is_m47: return
	_check(old.profile_id == expected_old.profile_id and old.journey.root_id == expected_old.journey.root_id
		and old.last_settlement_id == expected_old.last_settlement_id,
		"cold terminal identities match the baseline victory report")
	_check(expected_unlock.run_id == old.profile_id and expected_unlock.root_id == old.journey.root_id,
		"old M31 unlock is bound to the actual old run and root")
	_check(expected_unlock.receipt.get("hash") == state.get("hash"), "old unlock names the exact confirmed terminal receipt")
	_check(RecordEncoding.fingerprint(expected_unlock) == expected_hash, "baseline unlock hash authenticates its full exact event")
	var canonical_unlock: Dictionary = RecordEncoding.pack_v1(expected_unlock)
	_check(_legacy_catalog_before.get("unlock.json") == String(canonical_unlock.get("text", "")).sha256_text(),
		"nonempty unlock existed in canonical old V1 bytes before current startup")
	var specialty_file: String = "specialty-" + String(old.profile_id) + ".json"
	_check(_legacy_catalog_before.has(specialty_file) and not _legacy_catalog_before.has("discovery.json"),
		"actual old specialty file exists while the old discovery file is absent")
	_check(not _legacy_journal_before.is_empty() and not _legacy_save_before.is_empty(),
		"the actual old save and complete original journal existed before startup")
	_legacy_check_originals("cold startup")
	if failures > 0: return
	var projection: Dictionary = app.progress_session.catalog_state()
	_legacy_check_projection(projection, expected_hash, "cold current catalog")
	_check(TransactionReceipt.same(projection, _legacy_proof), "complete cold catalog projection equals the baseline projection")
	_check(TransactionReceipt.same(projection, app.progress_session.refresh_catalog()),
		"repeated current refresh reuses the same old confirmed progress")
	_legacy_check_originals("explicit cold refresh")
	_write("cold-read.json", {"scope":"AUTHENTIC_M47_NONEMPTY_CATALOG_COLD_READ", "source_proof":_legacy_proof_path,
		"source_report":_legacy_report_path, "source_pid":_legacy_report.pid, "pid":OS.get_process_id(),
		"original_slot":_legacy_slot, "original_terminal_hash":state.hash, "catalog":projection,
		"catalog_manifest_before_main_ready":_legacy_catalog_before, "journal_manifest_before_main_ready":_legacy_journal_before,
		"old_save_sha256":_legacy_save_before, "old_backup_sha256":_legacy_backup_before,
		"discovered_state_coverage":"NOT_TESTED; original discovery.json is absent"})
	if failures > 0: return
	await _legacy_show_catalog(projection)
	_legacy_check_originals("real catalog UI")
	if failures > 0: return
	await _legacy_register_next(old, state, projection, expected_hash)


func _legacy_show_catalog(projection: Dictionary) -> void:
	await _tap(app._catalog_button)
	var view: EquipmentCatalog = app._equipment_catalog
	_check(is_instance_valid(view) and view.is_visible_in_tree(), "ordinary title opens the real specialty and equipment catalog")
	if not is_instance_valid(view) or not view.is_visible_in_tree(): return
	_check(TransactionReceipt.same(view._state, projection), "real catalog view presents authenticated source state")
	await _legacy_select_row(view, SpecialtyPresentation.PLANS.find("scavenge"))
	_check(view.status.text == "2 经验 · 本专精已开放 · 未发现" and not view.retry_button.visible,
		"real specialty UI shows earned XP2, own-plan access and no false discovery")
	await _shot("legacy-specialty-two-xp")
	_check(FileAccess.file_exists(output.path_join("legacy-specialty-two-xp.png")), "native specialty screenshot is retained")
	var mask_index: int = SpecialtyPresentation.PLANS.size() + view._ids.find(BuildItems.FILTER)
	await _legacy_select_row(view, mask_index)
	_check(view._name.text == "滤毒面罩" and view.status.text == "已解锁 · 未发现",
		"M31 mask page preserves the true unlocked-but-undiscovered state")
	await _shot("legacy-mask-unlocked-undiscovered")
	_check(FileAccess.file_exists(output.path_join("legacy-mask-unlocked-undiscovered.png")), "native M31 state screenshot is retained")
	await _tap(view.close_button)
	_check(not view.visible and app._title.visible, "catalog return restores the ordinary title")


func _legacy_register_next(old: Dictionary, terminal: Dictionary, projection: Dictionary, unlock_hash: String) -> void:
	var old_camp_hash: String = RecordEncoding.fingerprint(old)
	await _tap(_legacy_new_button())
	_check(app._new_game_confirmation.visible, "ordinary new-journey control opens the original three-card dialog")
	if not app._new_game_confirmation.visible: return
	await _tap(app._opening_picker.choices["firepower"])
	_check(app._opening_picker.selected_plan == "firepower", "cancel probe really selects a different ordinary opening card")
	await _tap(app._new_game_confirmation.get_cancel_button())
	var cancelled: Dictionary = app.progress_session.inspect()
	_check(not app._new_game_confirmation.visible and cancelled.get("hash") == terminal.hash
		and cancelled.get("state") == "ENDED", "cancelling a different opening card preserves the exact old terminal")
	_legacy_check_originals("cancelled new journey")
	if failures > 0: return
	await _tap(_legacy_new_button())
	_check(app._new_game_confirmation.visible and app._opening_picker.selected_plan == "scavenge",
		"reopening resets the choice without publishing a new root")
	if not app._new_game_confirmation.visible: return
	_check(app._opening_picker._availability["scavenge"].text == SpecialtyPresentation.access_text([LEGACY_UNLOCK])
		and app._opening_picker._availability["firepower"].text == SpecialtyPresentation.access_text([])
		and app._opening_picker._availability["support"].text == SpecialtyPresentation.access_text([]),
		"the ordinary three cards show only the actually earned same-plan specialty eligibility")
	await _shot("legacy-reopened-eligible-opening")
	_check(FileAccess.file_exists(output.path_join("legacy-reopened-eligible-opening.png")), "native reopened eligibility cards are retained")
	_legacy_check_originals("reopened new journey before confirmation")
	if failures > 0: return
	await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	var fresh: Dictionary = app.camp_snapshot()
	var current: Dictionary = app.progress_session.inspect()
	var created: bool = current.get("error") == OK and current.get("state") == "CAMP" \
		and app.camp_scene.is_visible_in_tree() and not app._progress_blocked and EconomyBuildV1.enabled(fresh)
	_check(created, "ordinary confirmation registers a new M48 camp through the real transaction")
	if not created: return
	_check(fresh.profile_id != old.profile_id and fresh.journey.root_id != old.journey.root_id
		and fresh.day == 2 and fresh.settled_sorties == 0, "new registration has a distinct real root and no inherited outing rewards")
	_check(fresh.journey.build.catalog.unlock == unlock_hash and OpeningBuild.eligible(fresh) == [LEGACY_UNLOCK],
		"M48 registration freezes the exact old M31 unlock and earned M47 eligibility")
	_check(BuildState.pool(fresh) == BuildItems.M48_CATALOG_POOL and BuildItems.FILTER in BuildItems.ids(BuildState.pool(fresh)),
		"old mask unlock opens the explicit M48 catalog pool without granting the mask")
	_check(fresh.journey.build.owned == ["field_tools_v1"] and fresh.journey.build.slots == ["field_tools_v1", ""]
		and BuildItems.FILTER not in fresh.journey.build.owned and LEGACY_UNLOCK not in fresh.journey.build.owned,
		"normal initial inventory contains only the starter, with neither unlocked item falsely acquired")
	var archive: String = _legacy_slot + SpecializationProgress.ARCHIVE_PREFIX + String(old.profile_id)
	var archived_manifest: Dictionary = _legacy_manifest(archive)
	_check(TransactionReceipt.same(archived_manifest, _legacy_journal_before),
		"normal new registration archives every original M47 journal byte unchanged")
	var history: Dictionary = CatalogProgress.new(_legacy_slot)._history(archive)
	_check(not history.has("reason") and history.get("run_id") == old.profile_id
		and history.get("root_id") == old.journey.root_id and history.get("tip", {}).get("phase") == "COMMITTED",
		"current full catalog validator authenticates the normally archived old terminal source")
	if not history.has("reason") and history.has("tip"):
		_check(RecordEncoding.fingerprint(TransactionReceipt.camp(history.tip)) == old_camp_hash,
			"archived exact terminal camp is identical to the original cold-read camp")
	var after: Dictionary = app.progress_session.refresh_catalog()
	_legacy_check_projection(after, unlock_hash, "catalog after normal archival")
	_check(TransactionReceipt.same(after.get("unlock", {}), projection.unlock) and _legacy_xp(after.get("specialties"))
		and after.get("specialty_discoveries") == {} and after.get("specialization_result") == {},
		"archiving retains earned progress once and gives the new unplayed journey no XP")
	_legacy_check_catalog_unchanged("after normal M48 registration")
	_legacy_check_input_unchanged()
	await _shot("new-m48-with-old-catalog-eligibility")
	_write("legacy-catalog.json", {"scope":"REAL_OLD_M47_CATALOG_TO_ORDINARY_M48_REGISTRATION",
		"source_proof":_legacy_proof_path, "source_pid":_legacy_report.pid, "pid":OS.get_process_id(),
		"original_slot":_legacy_slot, "old_run_id":old.profile_id, "old_root_id":old.journey.root_id,
		"old_terminal_hash":terminal.hash, "old_camp_fingerprint":old_camp_hash, "archive":archive,
		"old_catalog_manifest":_legacy_catalog_before, "catalog_manifest_after":_legacy_manifest(_legacy_slot + ".catalog"),
		"old_journal_manifest":_legacy_journal_before, "archived_journal_manifest":archived_manifest,
		"input_sha256":_legacy_input_hashes, "catalog_before":projection, "catalog_after":after,
		"fresh_camp":fresh, "fresh_receipt_hash":current.hash,
		"mutations":"Only ordinary confirmed new-journey registration; the old source was normally archived.",
		"discovery_coverage":"UNLOCKED_UNDISCOVERED_ONLY; actual mask and specialty discovery acquisition NOT_TESTED",
		"physical_input":"NOT_TESTED", "native":DisplayServer.get_name() != "headless"})


func _legacy_new_button() -> Button:
	return app._home_button if app._home_button.is_visible_in_tree() else app.get_node("Interface/Screen/Title/Reset")


func _legacy_select_row(view: EquipmentCatalog, index: int) -> void:
	_check(index >= 0 and index < view.items.item_count, "requested real catalog row exists")
	if index < 0 or index >= view.items.item_count: return
	view.items.grab_focus()
	await _legacy_key(KEY_HOME)
	for count: int in range(index): await _legacy_key(KEY_DOWN)
	_check(view.items.get_selected_items() == PackedInt32Array([index]), "viewport keyboard selects the real catalog row")


func _legacy_key(keycode: Key) -> void:
	for down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = down
		viewport.push_input(event, true)
		await _frame()
	await _hold(2)


func _legacy_check_projection(value: Dictionary, unlock_hash: String, label: String) -> void:
	_check(value.get("error") == OK and value.get("unlock_hash") == unlock_hash and _legacy_xp(value.get("specialties"))
		and value.get("discovery") == {} and value.get("specialty_discoveries") == {},
		label + " keeps the true nonempty old unlock and XP2 without a discovery")


func _legacy_xp(value: Variant) -> bool:
	return value is Dictionary and TransactionReceipt.same(value, LEGACY_XP)


func _legacy_check_originals(label: String) -> void:
	_legacy_check_catalog_unchanged(label)
	_check(TransactionReceipt.same(_legacy_journal_before, _legacy_manifest(_legacy_slot + ".txn")), label + " leaves every original journal/binding SHA unchanged")
	_check(FileAccess.get_sha256(_legacy_slot) == _legacy_save_before, label + " leaves the original save bytes unchanged")
	var backup: String = FileAccess.get_sha256(_legacy_slot + ".bak") if FileAccess.file_exists(_legacy_slot + ".bak") else ""
	_check(backup == _legacy_backup_before, label + " leaves the original backup bytes unchanged")
	_legacy_check_input_unchanged()


func _legacy_check_catalog_unchanged(label: String) -> void:
	_check(TransactionReceipt.same(_legacy_catalog_before, _legacy_manifest(_legacy_slot + ".catalog")),
		label + " leaves every original catalog filename and SHA unchanged")


func _legacy_check_input_unchanged() -> void:
	for path: String in _legacy_input_hashes:
		_check(FileAccess.get_sha256(path) == _legacy_input_hashes[path], "original baseline evidence stays byte-identical: " + path.get_file())


func _legacy_local(path: String) -> bool:
	var local: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	return path.is_absolute_path() and path.replace("\\", "/").begins_with(local) and ".." not in path and ProgressWriter._unlinked(path)


func _legacy_document(path: String) -> Dictionary:
	if not _legacy_local(path):
		_legacy_preflight.append("unsafe evidence path: " + path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > LEGACY_PROOF_LIMIT:
		if file != null: file.close()
		_legacy_preflight.append("missing or oversized original evidence: " + path)
		return {}
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		_legacy_preflight.append("original evidence is not a JSON object: " + path)
		return {}
	return parser.data


func _legacy_manifest(folder: String) -> Dictionary:
	var result: Dictionary = {}
	_legacy_walk(folder, "", result)
	return result


func _legacy_walk(folder: String, relative: String, result: Dictionary) -> void:
	var access: DirAccess = DirAccess.open(folder.path_join(relative))
	if access == null:
		_legacy_preflight.append("original source directory is unreadable: " + folder.path_join(relative))
		result[relative] = "UNREADABLE"
		return
	access.include_hidden = true
	access.list_dir_begin()
	var name: String = access.get_next()
	while not name.is_empty():
		if name not in [".", ".."]:
			var path: String = relative.path_join(name)
			if access.is_link(name):
				_legacy_preflight.append("source contains a link: " + path)
				result[path] = "LINK"
			elif access.current_is_dir():
				_legacy_walk(folder, path, result)
			else:
				result[path] = FileAccess.get_sha256(folder.path_join(path))
		name = access.get_next()
	access.list_dir_end()
