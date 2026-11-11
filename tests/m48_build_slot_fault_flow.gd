extends "res://tests/m48_campaign_flow.gd"
## Genuine recovered common camp and normal widget/button paths; only I/O faults are directed.
## --flow-resume --build-slot-common=/absolute/repo/.local/.../setup/common.json
## Fresh journal objects below are same-PID readers, not a claimed process restart.

var slot_fault_cases: Array[Dictionary] = []
var slot_wait_paints: Dictionary = {}
var slot_active_case: String = ""
var slot_active_stage: String = ""
var slot_input_usec: int = 0


func _initialize() -> void:
	super()
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(_observe_slot_wait)


func _journey() -> void:
	_check(false,"build-slot fault flow requires the original restored common profile")


func _resume() -> void:
	_check(DisplayServer.get_name() != "headless","build-slot retry evidence requires native rendering")
	if DisplayServer.get_name() == "headless": return
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var common_path: String = _argument("--build-slot-common=")
	if common_path.is_empty(): common_path = output.get_base_dir().path_join("setup/common.json")
	var common: Variant = JSON.parse_string(FileAccess.get_file_as_string(common_path)) if FileAccess.file_exists(common_path) else null
	var original: Dictionary = app.camp_snapshot()
	var authentic: bool = (common_path.is_absolute_path() and "/.local/" in common_path and common is Dictionary
		and common.get("camp") == RecordEncoding.fingerprint(original) and EconomyBuildV1.enabled(original)
		and app.expedition == null and not app._progress_blocked and not app._progress_dirty)
	_check(authentic,"normal Continue restores the exact genuine common camp and original bound path")
	if not authentic: return
	_check(original.journey.build.slots.size() >= 2 and original.journey.build.slots[1] == "",
		"the real second passive slot starts empty")
	if original.journey.build.slots.size() < 2 or original.journey.build.slots[1] != "": return
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var armory: CampArmoryView = app.loadout_panel.armory
	await _tap(armory._nav[&"support"])
	for point: String in ["before_camp_write","after_record_publish"]:
		var before: Dictionary = app.camp_snapshot()
		var item_id: String = ""
		for owned_id: String in before.journey.build.owned:
			if owned_id not in before.journey.build.slots:
				item_id = owned_id
				break
		_check(not item_id.is_empty(),"a different genuinely owned unassigned passive exists for " + point)
		if item_id.is_empty(): return
		if not await _exercise_slot_fault(point,item_id): return
	await _tap(app.loadout_panel.back_button)
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_dirty and not app._progress_blocked,
		"both real retry loops return normally to the confirmed camp")
	var total_faults: int = 0
	for row: Dictionary in slot_fault_cases:
		total_faults += int(row.fault_count)
	_check(slot_fault_cases.size() == 2 and total_faults == 2,"both requested boundaries inject and recover exactly one real failure")
	_write_build_exact("build-slot-fault-proof.json",{"scope":"NORMAL_SOURCE_NATIVE_WIDGETS_DIRECTED_IO_FAULTS",
		"pid":OS.get_process_id(),"common_source":common_path,"initial":original,"cases":slot_fault_cases,
		"wait_paints":slot_wait_paints,"final":app.camp_snapshot(),"final_hash":RecordEncoding.fingerprint(app.camp_snapshot()),
		"profile_path":app.progress_path,"independent_reader_scope":"fresh ReceiptJournal in same PID; no restart claimed",
		"physical_input":"NOT_TESTED"})
	_write("build-slot-fault.json",{"scope":"NORMAL_SOURCE_NATIVE_WIDGETS_DIRECTED_IO_FAULTS","pid":OS.get_process_id(),
		"case_count":slot_fault_cases.size(),"fault_count":total_faults,"wait_paints":slot_wait_paints,"exact_proof":"build-slot-fault-proof.json"})


func _exercise_slot_fault(point: String, item_id: String) -> bool:
	var progress: ProductionProgress = app.progress_session
	var armory: CampArmoryView = app.loadout_panel.armory
	var panel: BuildItemsPanel = armory.build_panel
	var before: Dictionary = app.camp_snapshot().duplicate(true)
	var request: Dictionary = {"kind":"build_slot","member_id":1,"value":item_id}
	var expected: Dictionary = CampEdit.propose(before,request)
	var previous: Dictionary = progress._transaction.recover()
	_check(not expected.is_empty() and not TransactionReceipt.same(before,expected),
		"the exact owned passive proposal changes the real slot before fault injection")
	if expected.is_empty() or TransactionReceipt.same(before,expected): return false
	var injected: Dictionary = {"publishes":0,"failures":0,"observed":[]}
	progress.fault_hook = func(boundary: String) -> Error:
		if boundary == "after_record_publish": injected.publishes += 1
		if boundary == point and (point != "after_record_publish" or injected.publishes == 2):
			injected.failures += 1
			injected.observed.append({"point":boundary,"pending_edit":progress._pending_edit,"publish_number":injected.publishes})
			return ERR_CANT_CREATE
		return OK
	slot_active_case = point
	slot_active_stage = "attempt"
	await _select_real_passive(panel.slot_choices[1],item_id)
	await _slot_idle()
	progress.fault_hook = Callable()
	var identity: String = progress._pending_edit
	var durable: Dictionary = progress._transaction.recover()
	var disk: Dictionary = progress._transaction._save.read_transaction_exact()
	var expected_phase: String = "EDIT_READY" if point == "before_camp_write" else "EDIT_COMMITTED"
	_check(injected.failures == 1 and not identity.is_empty() and app._progress_dirty and app._progress_blocked,
		"one actual I/O fault retains the pending edit and reports a failed acknowledgment: " + point)
	_check(TransactionReceipt.same(progress._pending_edit_request,request) and progress._pending_edit_head == previous.hash,
		"the failed UI operation retains its original complete request and confirmed before-head")
	_check(slot_wait_paints.has(point+":attempt"),"the actual passive request renders a waiting frame before durable work")
	_check(durable.error == OK and durable.receipt.phase == expected_phase and disk.error == OK
		and TransactionReceipt.same(disk.data,before if point == "before_camp_write" else expected),
		"fault boundary preserves its exact original durable phase and camp bytes")
	_check(TransactionReceipt.same(app.camp_snapshot(),before) and panel._slots == before.journey.build.slots,
		"failed passive acknowledgment exposes only the old confirmed complete camp and slot values")
	var retry: Button = armory._retry_button
	_check(retry.is_visible_in_tree() and not retry.disabled and retry.focus_mode == Control.FOCUS_ALL
		and retry.has_focus() and viewport.gui_get_focus_owner() == retry,
		"the failed build-slot edit exposes and focuses its real armory retry button")
	_check(panel.slot_choices.all(func(choice: OptionButton) -> bool: return not choice.is_visible_in_tree() or choice.disabled)
		and panel._slot_button.disabled and panel._upgrade_button.disabled
		and armory.power_panel.purchases[PowerState.SECOND_SLOT].disabled,
		"other normally available passive and power edits disable while the original slot save is pending")
	_check(panel.status.text.contains("保存未确认") and panel._camp.get("journey",{}).get("build",{}).get("owned",[]) == before.journey.build.owned,
		"failed build panel retains the full original camp for disabled reasons and retry")
	var failed_message: String = armory.message.text
	var failed_panel_status: String = panel.status.text
	await _shot("build-slot-%s-failed-retry" % point)
	if identity.is_empty() or not retry.is_visible_in_tree() or retry.disabled: return false
	slot_active_stage = "retry"
	await _click_slot_button(retry)
	_check(app._camp_commit_busy and progress._pending_edit == identity,
		"the actual retry button retains the original pending edit during its native wait")
	await _slot_idle()
	var committed: Dictionary = progress._transaction.recover()
	var independent: Dictionary = ReceiptJournal.new(progress._transaction._journal.directory).read_all()
	_check(slot_wait_paints.has(point+":retry"),"retry renders its own real wait frame before confirming the same edit")
	_check(committed.error == OK and committed.receipt.phase == "EDIT_COMMITTED"
		and committed.receipt.transaction_id == identity and TransactionReceipt.same(committed.receipt.rules.request,request)
		and independent.error == OK and independent.hash == committed.hash
		and TransactionReceipt.same(TransactionReceipt.camp(independent.receipt),expected)
		and TransactionReceipt.same(app.camp_snapshot(),expected),
		"actual UI retry and fresh full journal replay converge on the one original complete result")
	_check(not app._progress_dirty and not app._progress_blocked and progress._pending_edit.is_empty()
		and not retry.visible and not panel.slot_choices[1].disabled and panel._slots[1] == item_id,
		"successful acknowledgment clears pending state hides retry and enables the saved passive slot")
	_check(int(committed.receipt.revision) == int(previous.receipt.revision)+2
		and before.cash == expected.cash and before.food == expected.food and before.camp_spending == expected.camp_spending,
		"both fault boundaries add exactly one ready/committed pair without money or resource effects")
	var generations: Array[Dictionary] = []
	for revision: int in range(int(previous.receipt.revision)+1,int(committed.receipt.revision)+1):
		var record: Dictionary = progress._transaction._journal._read_record(progress._transaction._journal.directory.path_join("%08d/record.json" % revision))
		_check(record.error == OK and record.receipt.transaction_id == identity
			and TransactionReceipt.same(record.receipt.rules.request,request),"each actual appended generation retains the original request identity")
		generations.append({"revision":revision,"hash":record.get("hash",""),"phase":record.get("receipt",{}).get("phase","")})
	var sources: Dictionary = _slot_sources(progress._transaction)
	var repeated: Dictionary = progress._transaction.commit_edit(identity)
	var stale: Dictionary = progress.edit(before,request)
	slot_active_stage = "repeat_noop"
	await _select_real_passive(panel.slot_choices[1],item_id)
	await _hold(3)
	_check(repeated.error == OK and repeated.hash == committed.hash and stale.error != OK
		and TransactionReceipt.same(app.camp_snapshot(),expected) and _slot_sources(progress._transaction) == sources
		and not app._camp_commit_busy and progress._pending_edit.is_empty(),
		"repeated acknowledgment stale before-state and selecting the same saved option cannot append another edit")
	await _shot("build-slot-%s-confirmed" % point)
	slot_fault_cases.append({"scope":"DIRECTED_IO_FAULT_ONLY_NORMAL_WIDGET_AND_BUTTON_PATH","point":point,
		"pid":OS.get_process_id(),"request":request,"edit_id":identity,"before":before,"expected":expected,
		"before_hash":RecordEncoding.fingerprint(before),"after_hash":RecordEncoding.fingerprint(expected),
		"fault_count":injected.failures,"publish_count_until_failure":injected.publishes,"fault_observations":injected.observed,
		"durable_after_failure":{"error":durable.error,"reason":durable.get("reason",""),"hash":durable.get("hash",""),"receipt":durable.get("receipt",{})},
		"disk_after_failure":{"error":disk.error,"reason":disk.get("reason",""),"data":disk.get("data",{})},
		"app_failure_message":failed_message,"build_panel_failure_status":failed_panel_status,
		"receipt_hash":committed.hash,"independent_journal_hash":independent.get("hash",""),
		"repeat_receipt_hash":repeated.get("hash",""),"stale_before_error":stale.error,"generations":generations,
		"source_manifest":sources,"profile_path":progress._transaction._save.path,"journal_directory":progress._transaction._journal.directory})
	slot_active_stage = ""
	return not app._progress_dirty and not app._progress_blocked


func _select_real_passive(choice: OptionButton, item_id: String) -> void:
	var index: int = -1
	for position: int in range(choice.item_count):
		if choice.get_item_metadata(position) == item_id:
			index = position
			break
	_check(index >= 0 and not choice.disabled and not choice.is_item_disabled(index),"real passive dropdown contains an enabled owned option")
	if index < 0 or choice.disabled or choice.is_item_disabled(index): return
	await _tap(choice)
	var popup: PopupMenu = choice.get_popup()
	_check(popup.visible,"the actual passive dropdown opens through its normal button")
	if not popup.visible: return
	popup.set_focused_item(index)
	slot_input_usec = Time.get_ticks_usec()
	last_tap_usec = slot_input_usec
	for down: bool in [true,false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = down
		viewport.push_input(key,true)


func _click_slot_button(button: Button) -> void:
	_check(button.is_visible_in_tree() and not button.disabled and viewport.get_visible_rect().encloses(button.get_global_rect()),
		"the actual retry button is enabled and physically inside the native viewport")
	await RenderingServer.frame_post_draw
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.position = button.get_global_rect().get_center()
	mouse.global_position = mouse.position
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	viewport.push_input(mouse,true)
	await RenderingServer.frame_post_draw
	slot_input_usec = Time.get_ticks_usec()
	last_tap_usec = slot_input_usec
	mouse = mouse.duplicate()
	mouse.pressed = false
	viewport.push_input(mouse,true)


func _slot_idle() -> void:
	var deadline: int = Time.get_ticks_msec()+90000
	while app._camp_commit_busy and Time.get_ticks_msec() < deadline:
		await _frame()
	_check(not app._camp_commit_busy,"the actual slot edit or retry leaves its bounded pending wait")
	await _hold(2)


func _observe_slot_wait() -> void:
	if not is_instance_valid(app) or not is_instance_valid(viewport) or slot_active_stage not in ["attempt","retry"]:
		return
	var key: String = slot_active_case+":"+slot_active_stage
	if app.get("_camp_commit_busy") != true or slot_wait_paints.has(key): return
	var armory: CampArmoryView = app.loadout_panel.armory
	if not armory.message.text.contains("正在保存"): return
	var name: String = "build-slot-%s-%s-wait.png" % [slot_active_case,slot_active_stage]
	var painted_usec: int = Time.get_ticks_usec()-slot_input_usec
	var saved: Error = viewport.get_texture().get_image().save_png(output.path_join(name))
	_check(saved == OK,"native wait screenshot records the actual pending slot operation")
	slot_wait_paints[key] = {"first_painted_frame_observer_usec":painted_usec,
		"label":app.get("_camp_commit_label"),"retry_visible":armory._retry_button.is_visible_in_tree(),
		"screenshot":name,"screenshot_error":saved,"timing_scope":"native wait observer including any earlier observers; own screenshot encoding excluded; not a performance comparison"}


func _slot_sources(transaction: RunTransaction) -> Dictionary:
	var result: Dictionary = {}
	for path: String in [transaction._save.path,transaction._save.path+".bak",transaction._save.path+".txn/binding.json"]:
		if FileAccess.file_exists(path): result[path] = FileAccess.get_sha256(path)
	for folder: String in DirAccess.get_directories_at(transaction._journal.directory):
		var path: String = transaction._journal.directory.path_join(folder).path_join("record.json")
		if FileAccess.file_exists(path): result[path] = FileAccess.get_sha256(path)
	return result


func _write_build_exact(name: String, value: Dictionary) -> void:
	var encoded: String = RecordEncoding.stringify(value)
	_check(not encoded.is_empty(),"complete build-slot proof is JSON-safe and Exact-encodable")
	if encoded.is_empty(): return
	var file: FileAccess = FileAccess.open(output.path_join(name),FileAccess.WRITE)
	_check(file != null,"exact complete build-slot retry evidence is writable")
	if file == null: return
	file.store_string(encoded)
	file.close()
