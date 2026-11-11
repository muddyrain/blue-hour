extends "res://tests/m48_campaign_flow.gd"
## Real ordinary new journey, native viewport clicks and an unmodified async worker.
## No delay, resource, qualification, thread-result or timing injection is used.
## Run fresh with --flow-output=/absolute/repo/.local/...; native renderer required.

var stale_timing: Dictionary = {}
var write_observations: Array[Dictionary] = []

func _journey() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false,"stale-card native-paint driver requires a native renderer")
		return
	if not await _new_trip("scavenge"):
		return
	var before: Dictionary = app.camp_snapshot()
	var before_hash: String = RecordEncoding.fingerprint(before)
	var purchase: Dictionary = BuildState.investment_offer(before,"next_slot")
	_check(EconomyBuildV1.enabled(before) and before.journey.build.slots.size() == 2 and purchase.available and purchase.cost == 16,
		"ordinary opening genuinely funds the third passive slot without injected resources")
	if not purchase.available:
		return
	var opened_at: int = await _stale_click(app.camp_scene.hotspots[&"bus"])
	var visible_at: int = -1
	var ready_at: int = -1
	var maximum_frame: int = 0
	var previous_frame: int = opened_at
	while Time.get_ticks_usec()-opened_at < 90000000:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		maximum_frame = maxi(maximum_frame,now-previous_frame)
		previous_frame = now
		if app.mission_select.is_visible_in_tree() and visible_at < 0:
			visible_at = now
		if _stale_cards_ready():
			ready_at = now
		if app.mission_select.cancel_button.is_visible_in_tree() and not app.mission_select.cancel_button.disabled:
			break
	_check(visible_at >= 0 and app.mission_select.cancel_button.is_visible_in_tree() and not app.mission_select.cancel_button.disabled,
		"first native waiting frame exposes an actual enabled return control")
	if visible_at < 0:
		return
	var old_worker: Thread = app.get("_mission_worker")
	var alive_at_first_frame: bool = _stale_worker_alive(old_worker)
	var canceled_at: int = await _stale_click(app.mission_select.cancel_button)
	await RenderingServer.frame_post_draw
	var alive_after_cancel: bool = _stale_worker_alive(old_worker)
	_check(app.camp_scene.is_visible_in_tree() and not app.mission_select.visible and RecordEncoding.fingerprint(app.camp_snapshot()) == before_hash,
		"native return closes the waiting page without changing the confirmed camp")
	stale_timing = {"opening_click_usec":opened_at,"first_visible_feedback_usec":visible_at-opened_at,
		"cards_ready_before_cancel_usec":ready_at-opened_at if ready_at >= 0 else -1,
		"max_rendered_frame_usec_before_cancel":maximum_frame,"cancel_click_usec":canceled_at,
		"worker_alive_first_paint":alive_at_first_frame,"worker_alive_after_cancel":alive_after_cancel}
	await _stale_click(app.camp_scene.hotspots[&"weapons"])
	await RenderingServer.frame_post_draw
	_check(is_instance_valid(app.loadout_panel) and app.loadout_panel.is_visible_in_tree(), "native equipment control opens the ordinary armory")
	if not is_instance_valid(app.loadout_panel) or not app.loadout_panel.is_visible_in_tree():
		return
	await _stale_click(app.loadout_panel.armory._nav[&"support"])
	await RenderingServer.frame_post_draw
	var build_panel: BuildItemsPanel = app.loadout_panel.build_panel
	_check(build_panel._slot_button.is_visible_in_tree() and not build_panel._slot_button.disabled, "third-slot purchase is reachable through the actual support page")
	if not build_panel._slot_button.is_visible_in_tree() or build_panel._slot_button.disabled:
		return
	await _stale_click(build_panel._slot_button)
	await RenderingServer.frame_post_draw
	_check(build_panel._confirmation.visible,"real third-slot preview opens before confirmation")
	if not build_panel._confirmation.visible:
		return
	var previous_hook: Callable = app.progress_session.fault_hook
	app.progress_session.fault_hook = func(point: String) -> Error:
		if point == "before_camp_write":
			write_observations.append({"point":point,"wall_usec":Time.get_ticks_usec(),"old_worker_alive":_stale_worker_alive(old_worker),
				"current_slots":app.camp_snapshot().journey.build.slots.size()})
		return int(previous_hook.call(point)) as Error if previous_hook.is_valid() else OK
	var confirmed_at: int = await _stale_click(build_panel._confirmation.get_ok_button(),Vector2(build_panel._confirmation.position))
	var alive_on_confirm: bool = _stale_worker_alive(old_worker)
	while app._camp_commit_busy and Time.get_ticks_usec()-confirmed_at < 90000000:
		await RenderingServer.frame_post_draw
	app.progress_session.fault_hook = previous_hook
	var after: Dictionary = app.camp_snapshot()
	_check(not app._camp_commit_busy and not app._progress_blocked and not app._progress_dirty
		and after.journey.build.slots.size() == 3 and int(after.cash) == int(before.cash)-16,
		"normal preview confirmation stores exactly one third-slot purchase and its real debit")
	_check(after.journey.build.progression.purchases.size() == before.journey.build.progression.purchases.size()+1,
		"third-slot confirmation has one original investment source")
	stale_timing.purchase_confirmation_click_usec = confirmed_at
	stale_timing.worker_alive_on_confirmation = alive_on_confirm
	stale_timing.purchase_write_observations = write_observations.duplicate(true)
	stale_timing.confirmation_completed_usec = Time.get_ticks_usec()-confirmed_at
	var covered: bool = alive_after_cancel and write_observations.any(func(row: Dictionary) -> bool: return row.old_worker_alive)
	stale_timing.concurrent_mutation_coverage = "COVERED_REAL_WORKER_ALIVE_AT_CAMP_WRITE" if covered else "NOT_COVERED_WORKER_FINISHED_BEFORE_CAMP_WRITE"
	if not covered:
		print("M48_STALE_CARDS_NOT_COVERED " + JSON.stringify(stale_timing))
	var waiting_since: int = Time.get_ticks_usec()
	while app.get("_mission_worker") == old_worker and old_worker != null and Time.get_ticks_usec()-waiting_since < 90000000:
		await RenderingServer.frame_post_draw
	_check(old_worker == null or app.get("_mission_worker") != old_worker, "original async worker reaches its normal completion without injected waiting")
	_check(not app.mission_select.visible,"late completion cannot reopen the canceled task menu")
	if covered:
		_check(app.mission_select.daily_offers.is_empty(),"canceled old two-slot worker cannot publish its obsolete candidates")
	stale_timing.old_worker_discard_finished_usec = Time.get_ticks_usec()
	await _stale_click(app.loadout_panel.back_button)
	await RenderingServer.frame_post_draw
	var saved_hash: String = RecordEncoding.fingerprint(app.camp_snapshot())
	var reopened: Dictionary = await _stale_open_and_measure()
	if reopened.is_empty():
		return
	var offers: Array = app.mission_select.daily_offers.duplicate(true)
	_check(not offers.is_empty() and offers.all(func(action: Dictionary) -> bool:
		return TransactionReceipt.same({"slots":action.build.slots},{"slots":after.journey.build.slots}) and action.build.slots.size() == 3),
		"reopened task cards freeze the exact current three-slot loadout")
	for action: Dictionary in offers:
		_check(DailyActions.matches(after,action),"reopened candidate authenticates against the confirmed post-purchase camp")
	await _shot("reopened-three-slot-cards")
	await _stale_click(app.mission_select.cancel_button)
	await RenderingServer.frame_post_draw
	var repeated: Dictionary = await _stale_open_and_measure()
	_check(TransactionReceipt.same({"offers":offers},{"offers":app.mission_select.daily_offers})
		and RecordEncoding.fingerprint(app.camp_snapshot()) == saved_hash and int(app.cash) == int(before.cash)-16,
		"reopening again keeps the same complete candidates and never charges another slot")
	await _stale_click(app.mission_select.cancel_button)
	await RenderingServer.frame_post_draw
	_write("stale-cards.json",{"scope":"NORMAL_NEW_JOURNEY_NATIVE_INPUT_UNMODIFIED_WORKER","pid":OS.get_process_id(),
		"seed":after.journey.seed,"before":before_hash,"after":saved_hash,"race":stale_timing,
		"reopened":reopened,"repeated":repeated,"offers":offers,"physical_input":"NOT_TESTED"})

func _stale_worker_alive(worker: Thread) -> bool:
	return worker != null and app.get("_mission_worker") == worker and worker.is_alive()

func _stale_cards_ready() -> bool:
	return app.mission_select.is_visible_in_tree() and not app.mission_select.loading and not app.mission_select.daily_offers.is_empty()

func _stale_open_and_measure() -> Dictionary:
	var start: int = await _stale_click(app.camp_scene.hotspots[&"bus"])
	var feedback: int = -1
	var previous: int = start
	var largest: int = 0
	while Time.get_ticks_usec()-start < 90000000:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		largest = maxi(largest,now-previous)
		previous = now
		if app.mission_select.is_visible_in_tree() and feedback < 0:
			feedback = now-start
		if _stale_cards_ready():
			return {"first_visible_feedback_usec":feedback,"cards_ready_usec":now-start,"max_frame_usec":largest,
				"camp":RecordEncoding.fingerprint(app.camp_snapshot()),"slots":app.camp_snapshot().journey.build.slots.duplicate()}
	_check(false,"normal reopened three-slot cards become usable before the measured deadline")
	return {}

func _stale_click(button: BaseButton,dialog_position: Vector2 = Vector2.ZERO) -> int:
	_check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"actual native click has a visible enabled target")
	await RenderingServer.frame_post_draw
	var point: Vector2 = button.get_global_rect().get_center()+dialog_position
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	viewport.push_input(event,true)
	await RenderingServer.frame_post_draw
	var released_at: int = Time.get_ticks_usec()
	last_tap_usec = released_at
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event,true)
	return released_at
