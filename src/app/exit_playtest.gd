class_name ExitPlaytest
extends SurvivalPilotPlaytest
## Opt-in native viewport proof. No OS input or production progress access.

var samples: Array[Dictionary] = []
var mode: String = "play"


func _run() -> void:
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\", "/").to_lower() or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--exit-case="):
			mode = arg.trim_prefix("--exit-case=")
		if arg == "--exit-map=market":
			_map = 1
	await _settle()
	print("BH_EXIT_DIAGNOSTIC ", {"home_visible":app._home_button.is_visible_in_tree(),"home_disabled":app._home_button.disabled,"blocked":app._progress_blocked,"continue":app._requires_continue,"camp":app._camp_open,"message":app._progress_message,"user":OS.get_user_data_dir()})
	if mode == "blocked":
		_expect(app._progress_blocked and not app._requires_continue, "fresh process refuses unfinished original journey")
		app.request_exit("quit")
		_expect("阻塞" in app.pause_menu.body.text, "blocked close has separate honest text")
		await _capture("blocked.png")
		await _key_battle(KEY_ESCAPE)
	else:
		if app._requires_continue:
			await _continue_probe()
		else:
			await _enter()
		_initial = app.camp_snapshot()
		if mode == "window":
			await _window_close()
			return
		if mode != "continue":
			await _play_exit()
	await _finish_proof()


func _window_close() -> void:
	await _open_map(_map)
	var digest: String = _digest()
	for attempt: int in range(2):
		_write(output_dir.path_join("wm-close-" + str(attempt) + ".json"), {"pid":OS.get_process_id()})
		for frame: int in range(1800):
			if app.pause_menu.confirming:
				break
			await get_tree().process_frame
		_expect(app.pause_menu.confirming and "原旅程无法继续" in app.pause_menu.body.text, "actual Windows WM_CLOSE reaches unfinished warning " + str(attempt))
		await _capture("wm-close-" + str(attempt) + ".png")
		if attempt == 0:
			await _key_battle(KEY_ESCAPE)
			_expect(not app.pause_menu.root.visible and not app.expedition.is_paused and digest == _digest(), "WM_CLOSE cancel preserves disk and world")
		else:
			_write(output_dir.path_join("report.json"), {"pid":OS.get_process_id(),"checks":_checks,"failures":_failures,"mode":mode,"camp":app.camp_snapshot(),"display":DisplayServer.get_name(),"input_layer":"Windows PostMessage WM_CLOSE to owned HWND; cancellation/confirmation viewport, NOT physical X/Alt+F4"})
			if app.safe_suspend:
				_expect(app.pause_menu.buttons[2].visible and "安全暂存" in app.pause_menu.buttons[2].text,"real WM_CLOSE provides safe quit before danger")
				_write(output_dir.path_join("snapshot.json"),SortieSnapshot.capture(app.expedition))
				_write(output_dir.path_join("report.json"), {"pid":OS.get_process_id(),"checks":_checks,"failures":_failures,"mode":mode,"input_layer":"real WM_CLOSE / viewport safety choice, NOT physical X"})
				await _tap(app.pause_menu.buttons[2])
			else:
				await _tap(app.pause_menu.buttons[1])


func _continue_probe() -> void:
	var digest: String = _digest()
	for attempt: int in range(3):
		var button: Button = app._continue_button
		samples.append({"attempt":attempt,"visible":button.is_visible_in_tree(),"disabled":button.disabled,"rect":str(button.get_global_rect()),"focus":str(get_viewport().gui_get_focus_owner()),"window_focused":DisplayServer.window_is_focused(),"modal":str(app._hunger_confirmation.visible)})
		await _tap(button)
		_expect(app._hunger_confirmation.visible, "first/successive viewport Continue opens policy: " + str(attempt))
		await _capture("continue-" + str(attempt) + ".png")
		if attempt < 2:
			if attempt == 0:
				await _tap(app._hunger_confirmation.get_cancel_button())
			else:
				# Native Window viewport route; not a physical Esc claim.
				var dialog: Window = app._hunger_confirmation
				var key: InputEventKey = InputEventKey.new()
				key.keycode = KEY_ESCAPE
				key.physical_keycode = KEY_ESCAPE
				key.pressed = true
				dialog.push_input(key, true)
				await _settle()
				# Some native Window close handling precedes push_input; preserve result.
				if dialog.visible:
					await _tap(app._hunger_confirmation.get_cancel_button())
			_expect(digest == _digest(), "policy cancellation preserves exact progress and head")
		else:
			await _tap(app._hunger_confirmation.get_ok_button())
	_expect(not app._progress_blocked, "continue activates only existing camp or frozen READY")


func _play_exit() -> void:
	await _open_map(_map)
	var sortie: Expedition = app.expedition
	if sortie == null:
		_expect(false, "sortie exists")
		return
	sortie.set_physics_process(false)
	await _key_battle(KEY_ESCAPE)
	_expect(app.pause_menu.root.visible and sortie.is_paused, "Esc opens real menu and pauses")
	await _layout("pause")
	var press: InputEventKey = InputEventKey.new()
	press.keycode = KEY_SPACE
	press.physical_keycode = KEY_SPACE
	press.pressed = true
	get_viewport().push_input(press, true)
	app.get_window().focus_exited.emit()
	press = press.duplicate() as InputEventKey
	press.pressed = false
	get_viewport().push_input(press, true)
	await _settle()
	_expect(app.pause_menu.root.visible, "focus loss cancels an armed Space activation (synthetic focus signal)")
	await _capture("active-menu.png")
	await _frozen(sortie, "ACTIVE")
	await _key_battle(KEY_ESCAPE)
	_expect(not app.pause_menu.root.visible and not sortie.is_paused, "Esc resumes running state")
	sortie.toggle_pause()
	await _key_battle(KEY_ESCAPE)
	await _tap(app.pause_menu.buttons[0])
	_expect(sortie.is_paused, "already paused remains paused after menu continue")
	sortie.toggle_pause()
	await _tap(sortie._hud.view._help_button)
	await _key_battle(KEY_ESCAPE)
	_expect(not sortie._hud.view._help.visible and not app.pause_menu.root.visible, "one Esc closes help without opening menu")
	sortie.request_search(&"food" if _map == 1 else &"cash")
	for frame: int in range(1000):
		if sortie.search_actor != null and sortie.search_actor.activity == FieldActor.Activity.SEARCHING:
			break
		await _step(sortie)
	await _key_battle(KEY_ESCAPE)
	await _frozen(sortie, "worker")
	await _key_battle(KEY_TAB)
	_expect(get_viewport().gui_get_focus_owner() == app.pause_menu.buttons[1], "Tab reaches bus location action")
	var worker: FieldActor = sortie.search_actor
	var goal: Vector2 = sortie.goal
	await _key_battle(KEY_SPACE)
	_expect(not app.pause_menu.root.visible and not sortie.is_paused and sortie.search_actor == worker and sortie.goal == goal and sortie.phase == Expedition.Phase.ACTIVE, "Space only locates bus; no search cancel, start or gather")
	while sortie.elapsed < sortie.tuning.bus_ready_seconds:
		await _step(sortie)
	await _tap(sortie._hud.view._bus_button)
	_expect(sortie.phase == Expedition.Phase.ENGINE and not sortie.boarding_status().ordered, "actual HUD engine start never recalls")
	await _key_battle(KEY_ESCAPE)
	await _frozen(sortie, "ENGINE")
	await _key_battle(KEY_ESCAPE)
	for frame: int in range(180):
		if sortie.phase == Expedition.Phase.BOARDING:
			break
		await _step(sortie)
	await _key_battle(KEY_ESCAPE)
	await _frozen(sortie, "BOARDING")
	await _tap(app.pause_menu.buttons[2])
	_expect(app.pause_menu.confirming and "原旅程无法继续" in app.pause_menu.body.text and "阵亡" in app.pause_menu.body.text, "unfinished home requires accurate irreversible-risk text")
	await _layout("danger")
	await _capture("danger-confirm.png")
	await _key_battle(KEY_ESCAPE)
	_expect(app.pause_menu.root.visible and not app.pause_menu.confirming and sortie.is_paused, "Esc cancels only confirmation")
	await _key_battle(KEY_ESCAPE)
	var digest: String = _digest()
	# Signal route is a separate synthetic check; real WM_CLOSE is driven externally.
	app.get_window().close_requested.emit()
	await _settle()
	_expect(app.pause_menu.confirming and sortie.is_paused and not get_tree().auto_accept_quit, "close signal enters warning instead of auto quit")
	await _key_battle(KEY_ESCAPE)
	_expect(not app.pause_menu.root.visible and not sortie.is_paused and digest == _digest(), "close cancel returns to exact world and disk")
	if mode == "home":
		await _key_battle(KEY_ESCAPE)
		await _tap(app.pause_menu.buttons[2])
		await _tap(app.pause_menu.buttons[1])
		_expect(app.phase == app.Phase.TITLE and app._progress_blocked and not app._camp_open and app.expedition == null and digest == _digest(), "confirmed home is blocked; never a free camp or synthesized READY")
		await _capture("home-blocked.png")
		return
	sortie.request_bus_gather()
	for frame: int in range(3600):
		if sortie.phase == Expedition.Phase.FINISHED:
			break
		await _step(sortie)
	_expect(app.phase == app.Phase.RESULT and not app._pending_settlement.is_empty(), "real search and evacuation creates existing frozen result")
	app.request_exit("quit")
	_expect("冻结" in app.pause_menu.heading.text, "READY close uses frozen-result text")
	await _capture("ready-close.png")
	await _key_battle(KEY_ESCAPE)
	if mode == "ready":
		return
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	var after: Dictionary = app.camp_snapshot()
	app.return_to_title()
	_expect(TransactionReceipt.same(after, app.camp_snapshot()) and after.day == _initial.day + 1, "commit advances once, repeated return changes nothing")
	await _capture("camp.png")


func _layout(label: String) -> void:
	await _settle()
	var menu: SortiePauseMenu = app.pause_menu
	var rect: Rect2 = menu.panel.get_global_rect()
	_expect(get_viewport().get_visible_rect().encloses(rect) and menu.body.get_minimum_size().y <= menu.body.size.y, label + " panel and wrapped Chinese fit actual viewport")
	for button: Button in menu.buttons:
		if not button.visible:
			continue
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = button.get_global_rect().get_center()
		get_viewport().push_input(motion, true)
		var hit: Control = get_viewport().gui_get_hovered_control()
		await _settle()
		print("BH_MENU_HIT ", {"stage":label,"target":str(button.get_path()),"point":str(motion.position),"immediate":str(hit),"after_frames":str(get_viewport().gui_get_hovered_control()),"inside":rect.encloses(button.get_global_rect())})
		_expect(hit == button and rect.encloses(button.get_global_rect()), label + " actual top GUI hit at dispatched event is menu button, inside panel")


func _frozen(sortie: Expedition, label: String) -> void:
	var before: String = _world(sortie)
	var disk: String = _digest()
	for frame: int in range(30):
		await _step(sortie)
	await _mouse_battle(Vector2(40, 300), MOUSE_BUTTON_LEFT)
	await _mouse_battle(Vector2(40, 300), MOUSE_BUTTON_WHEEL_UP)
	await _key_battle(KEY_W)
	_expect(_world(sortie) == before and _digest() == disk, label + " freezes timers, search, actors, cooldowns, camera and commands; overlay blocks click/wheel/W")
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	await _key_battle(KEY_TAB)
	_expect(get_viewport().gui_get_focus_owner() == app.pause_menu.buttons[0], label + " Tab from lost focus enters menu, never underlying HUD")
	var panel_rect: Rect2 = app.pause_menu.panel.get_global_rect()
	_expect(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(panel_rect), label + " panel inside viewport")
	for button: Button in app.pause_menu.buttons:
		if button.visible:
			_expect(panel_rect.encloses(button.get_global_rect()), label + " button inside panel")
	samples.append({"stage":label,"panel":str(panel_rect),"world":JSON.parse_string(before)})


func _world(sortie: Expedition) -> String:
	var actors: Array[Dictionary] = []
	for actor: FieldActor in sortie.survivors + sortie.enemies:
		actors.append({"id":actor.actor_id,"p":str(actor.position),"hp":actor.health,"cooldown":actor.cooldown,"path":str(actor.path),"activity":actor.activity})
	return JSON.stringify({"elapsed":sortie.elapsed,"spawn":sortie._spawn_clock,"ai":sortie._ai_clock,"engine":sortie._engine_clock,"cash_search":sortie.search_progress,"food_search":sortie.search_site(&"food").progress,"actors":actors,"goal":str(sortie.goal),"camera":str(sortie.camera.position),"zoom":str(sortie.camera.zoom),"boarding":sortie.boarding_status()})


func _finish_proof() -> void:
	_write(output_dir.path_join("report.json"), {"pid":OS.get_process_id(),"checks":_checks,"failures":_failures,"mode":mode,"samples":samples,"camp":app.camp_snapshot(),"initial":_initial,"display":DisplayServer.get_name(),"window_size":DisplayServer.window_get_size(),"input_layer":"native viewport events / gameplay intents; synthetic close signal, NOT OS"})
	app.audio.shutdown()
	OS.delay_msec(150)
	# Let deferred focus release and the removed sortie finish before engine teardown.
	await _settle()
	get_tree().quit(0 if _failures == 0 else 1)
