extends RefCounted
## Wall-clock native button dispatch through the complete rendered result.

static func measure(app: Node, viewport: SubViewport, button: BaseButton, complete: Callable, offset: Vector2 = Vector2.ZERO) -> Dictionary:
	viewport.gui_release_focus()
	await RenderingServer.frame_post_draw
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center() + offset
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	viewport.push_input(event, true)
	await RenderingServer.frame_post_draw
	var began: int = Time.get_ticks_usec()
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)
	var dispatch: int = Time.get_ticks_usec() - began
	var previous: int = began
	var intervals: Array[int] = []
	var probes: Array[Dictionary] = []
	var feedback: int = -1
	while Time.get_ticks_usec() - began < 600000000:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		intervals.append(now - previous)
		previous = now
		var done: bool = complete.call()
		var overlay: Variant = app.get("_operation_overlay")
		if feedback < 0 and (done or (is_instance_valid(overlay) and overlay.is_visible_in_tree())):
			feedback = now - began
		if not done and intervals.size() % 15 == 0:
			var probe: InputEventMouseMotion = InputEventMouseMotion.new()
			probe.position = Vector2(20, 20)
			var sent: int = Time.get_ticks_usec()
			viewport.push_input(probe, true)
			probes.append({"processing_usec":Time.get_ticks_usec() - sent, "handled":viewport.is_input_handled()})
		if done:
			var sorted: Array[int] = intervals.duplicate()
			sorted.sort()
			return {"started_usec":began, "feedback_ms":feedback / 1000.0, "complete_ms":(now - began) / 1000.0,
				"dispatch_usec":dispatch, "frame_intervals_usec":intervals, "probes":probes,
				"p95_frame_ms":sorted[int(ceil(sorted.size() * 0.95)) - 1] / 1000.0,
				"max_frame_ms":sorted[-1] / 1000.0, "worker_timing":app.get("_progress_last_timing"),
				"scope":"native actual mouse release through caller's complete rendered predicate; no PNG in interval"}
	return {"timeout":true, "frame_intervals_usec":intervals, "probes":probes}
