extends "res://tests/m48_campaign_flow.gd"
## Capacity widgets receive explicitly synthetic read-only copies, never saved qualification.
## Live input probes use ephemeral Expedition/PowerAuthority proposals, without a journal.

class InputWorld extends Expedition:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(true)
	func _draw() -> void:
		pass
	func _update_ui() -> void:
		pass
	func support_world() -> Dictionary:
		return {"version":SortieSnapshot.POWER_VERSION,"generated":supply.generated.duplicate(true),
			"powers":powers.duplicate(true),"sim":{"elapsed":elapsed,"phase":0},
			"survivors":[{"state":{"health":survivors[0].health}}]}

const UI_BINDING: Dictionary = {
	"run_id":"0123456789abcdef0123456789abcdef", "root_id":"fedcba9876543210fedcba9876543210",
	"transaction_id":"0123456789abcdef0123456789abcdef:1",
	"base_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	"rules_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
}
var ui_layouts: Array[Dictionary] = []

func _journey() -> void:
	if not await _new_trip("scavenge"):
		return
	var original: Dictionary = app.camp_snapshot()
	var digest: String = FileAccess.get_sha256(app.progress_path)
	await _stale_previews(original)
	await _capacity(original)
	await _live_input()
	await _compact_specialty_hud()
	_check(RecordEncoding.fingerprint(app.camp_snapshot()) == RecordEncoding.fingerprint(original)
		and FileAccess.get_sha256(app.progress_path) == digest, "all read-only fixtures and ephemeral input probes leave the real camp and save bytes unchanged")
	_write("ui-layout.json", {"scope":"SYNTHETIC_READ_ONLY_WIDGETS_AND_EPHEMERAL_INPUT","layouts":ui_layouts,
		"real_camp":RecordEncoding.fingerprint(original),"save_sha256":digest,"physical_input":"NOT_TESTED"})

func _capacity(original: Dictionary) -> void:
	var fixture: Dictionary = original.duplicate(true)
	fixture.day = 12
	fixture.cash = 0
	var guns: Array[String] = ["carbine","long_rifle","shotgun_v1","fire_axe_v1",CombatEquipment.HAMMER_ID]
	for index: int in range(30-fixture.weapons.size()):
		fixture.weapons.append(WeaponModifiers.baseline({"instance_id":"read-only-ui:%03d" % index,"weapon_id":guns[index%guns.size()],
			"condition":"damaged" if index%3==0 else "ready","origin":"read-only-ui","acquired_sortie":""}))
	var pool: int = BuildState.pool(fixture)
	fixture.journey.build.owned = BuildItems.ids(pool)
	fixture.journey.build.slots = ["pressure_rounds_v1","quick_loader_v1","light_boots_v1","field_tools_v1"]
	fixture.journey.build.progression = {"version":1,"enhanced":fixture.journey.build.slots.duplicate(),"purchases":[]}
	var inventory: Dictionary = PowerState.initial_progression(SpecialPowers.M48_VERSION)
	inventory.owned = SpecialPowers.policy(SpecialPowers.M48_VERSION).keys()
	inventory.slots = [SpecialPowers.SPEED,SpecialPowers.FREEZE,SpecialPowers.SUPPRESSION]
	inventory.investments = {"second_slot":3,"third_slot":4,"freeze":5,"speed":5,"suppression":5,"radio":5}
	fixture.journey.build.powers = inventory
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 80
	viewport.add_child(layer)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("10232d")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(backdrop)
	var view: CampArmoryView = CampArmoryView.new()
	view.theme = app._screen.theme
	layer.add_child(view)
	var requests: Array[Dictionary] = []
	view.build_panel.requested.connect(func(slot: int,id: String) -> void: requests.append({"kind":"passive","slot":slot,"id":id}))
	view.power_panel.third_requested.connect(func(id: String) -> void: requests.append({"kind":"power","slot":2,"id":id}))
	view.navigation_requested.connect(func(action: StringName) -> void:
		if action == &"camp":
			view.hide()
			app._screen.show())
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1024,576)]:
		viewport.size = dimensions
		# The actual camp is outside this fixture and must not capture its keyboard focus.
		app._screen.hide()
		view.show()
		view.refresh(fixture,"只读容量样本 · 30 件实例 / 四被动三能力 · 不代表实际营地资格",false)
		view.show_inventory()
		await _hold(5)
		var frame: Rect2 = viewport.get_visible_rect()
		_check(view.items.item_count == 30 and frame.encloses(view.items.get_global_rect()) and frame.encloses(view.back_button.get_global_rect()),
			"%s fits all 30 inventory entries and the fixed return control" % dimensions)
		var inventory_center: Vector2 = view.items.get_global_rect().get_center()
		for tick: int in range(55):
			await _ui_mouse(inventory_center,MOUSE_BUTTON_WHEEL_DOWN,true)
			await _ui_mouse(inventory_center,MOUSE_BUTTON_WHEEL_DOWN,false)
		var inventory_bar: VScrollBar = view.items.get_v_scroll_bar()
		_check(inventory_bar.value > 0.0 and _ui_near(inventory_bar.value,inventory_bar.max_value-inventory_bar.page), "mouse wheel reaches the final inventory entry")
		await _shot("fixture-inventory-30-%dx%d" % [dimensions.x,dimensions.y])
		view.search.grab_focus()
		view.search.text = "#027"
		view.search.text_changed.emit(view.search.text)
		await _hold(2)
		_check(view.items.item_count == 1, "search accepts a short identity with a leading hash")
		await _ui_key(KEY_TAB)
		_check(is_instance_valid(viewport.gui_get_focus_owner()) and viewport.gui_get_focus_owner() != view.search and view.is_ancestor_of(viewport.gui_get_focus_owner()), "Tab reaches the next real GUI control")
		view.search.text = ""
		view.search.text_changed.emit("")
		await _tap(view._nav[&"support"])
		await _hold(4)
		_check(view.build_panel.slot_choices.size() == 4 and view.build_panel.slot_choices.all(func(choice: OptionButton) -> bool: return choice.is_visible_in_tree()), "four passive slot selectors are present")
		var fourth: OptionButton = view.build_panel.slot_choices[3]
		await _ui_select(fourth,0)
		_check(not requests.is_empty() and requests.back().kind == "passive" and requests.back().slot == 3,
			"keyboard can request a change in the fourth passive slot without mutating the fixture")
		var support_center: Vector2 = view._support.get_global_rect().get_center()
		for tick: int in range(55):
			await _ui_mouse(support_center,MOUSE_BUTTON_WHEEL_DOWN,true)
			await _ui_mouse(support_center,MOUSE_BUTTON_WHEEL_DOWN,false)
		var support_bar: VScrollBar = view._support.get_v_scroll_bar()
		var radio: Button = view.power_panel.third_choices[SpecialPowers.RADIO]
		_check(view.power_panel._rows[2].is_visible_in_tree() and frame.encloses(radio.get_global_rect()), "scroll exposes third ability slot inside the viewport")
		await _ui_click(radio.get_global_rect().get_center())
		_check(not requests.is_empty() and requests.back().kind == "power" and requests.back().slot == 2 and requests.back().id == SpecialPowers.RADIO,
			"mouse can request the third ability slot in the read-only widget")
		_check(view.power_panel.purchases["radio"].disabled and not view.power_panel.purchases["radio"].tooltip_text.is_empty(), "already enhanced ability exposes a disabled reason")
		_check(view.build_panel._slot_button.disabled and not view.build_panel._slot_button.tooltip_text.is_empty(), "four-slot cap exposes its disabled reason")
		await _shot("fixture-four-passives-three-powers-%dx%d" % [dimensions.x,dimensions.y])
		ui_layouts.append({"viewport":[dimensions.x,dimensions.y],"inventory_count":view.items.item_count,"inventory_scroll":inventory_bar.value,
			"support_scroll":support_bar.value,"third_button_rect":_ui_rect(radio.get_global_rect()),"requests":requests.duplicate(true)})
		await _tap(view.back_button)
		_check(not view.visible and app.camp_scene.is_visible_in_tree(), "read-only view return restores the underlying ordinary camp")
	layer.queue_free()
	app._screen.show()
	viewport.size = Vector2i(1280,720)
	await _hold(3)

func _stale_previews(original: Dictionary) -> void:
	var changed: Dictionary = CampEdit.propose(original,{"kind":"rename","member_id":1,"value":"前态变化"})
	_check(not changed.is_empty() and not TransactionReceipt.same(original,changed), "stale preview fixture uses a legal pure camp edit without saving it")
	if changed.is_empty():
		return
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 80
	viewport.add_child(layer)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.position = Vector2(30,30)
	panel.size = Vector2(850,550)
	layer.add_child(panel)
	var passive: BuildItemsPanel = BuildItemsPanel.new()
	panel.add_child(passive)
	var power: PowerLoadoutPanel = PowerLoadoutPanel.new()
	panel.add_child(power)
	var values: Array[String] = []
	passive.investment_requested.connect(func(value: String) -> void: values.append(value))
	power.investment_requested.connect(func(value: String) -> void: values.append(value))
	passive.present(original.journey.build.owned,original.journey.build.slots,true,true,OpeningBuild.plan(original),BuildState.pool(original),original)
	passive._confirm_investment("next_slot")
	passive.present(changed.journey.build.owned,changed.journey.build.slots,true,true,OpeningBuild.plan(changed),BuildState.pool(changed),changed)
	passive._confirmation.confirmed.emit()
	passive._confirmation.hide()
	_check(values.size() == 1 and BuildState.investment_intent(original,values.back()) == "next_slot"
		and CampEdit.propose(changed,{"kind":"build_invest","member_id":0,"value":values.back()}).is_empty(),
		"refresh cannot rebind an open passive purchase preview to a newer camp")
	power.present(original,true)
	power._confirm(PowerState.SECOND_SLOT)
	power.present(changed,true)
	power.confirmation.confirmed.emit()
	power.confirmation.hide()
	_check(values.size() == 2 and BuildState.investment_intent(original,values.back()) == PowerState.SECOND_SLOT
		and CampEdit.propose(changed,{"kind":"power_invest","member_id":0,"value":values.back()}).is_empty(),
		"refresh cannot rebind an open power purchase preview to a newer camp")
	layer.queue_free()
	await _hold(3)

func _live_input() -> void:
	app._screen.hide()
	for method: String in ["key-five","mouse-button"]:
		var world: InputWorld = InputWorld.new()
		world.supply = MissionSupply.new()
		var inventory: Dictionary = PowerState.initial_progression(SpecialPowers.M48_VERSION)
		inventory.slots = [SpecialPowers.SPEED,SpecialPowers.FREEZE,SpecialPowers.SUPPRESSION]
		inventory.investments.second_slot = 3
		inventory.investments.third_slot = 4
		world.supply.generated = {"version":8,"powers":inventory,"build":{"version":BuildItems.M48_POOL,"slots":["", ""],"enhanced":[]}}
		world.powers = SpecialPowers.initial(UI_BINDING,PowerState.loadout(inventory))
		viewport.add_child(world)
		world._hud = ExpeditionHud.new()
		world.add_child(world._hud)
		var actor: FieldActor = FieldActor.new()
		actor.member_id = 1
		world.add_child(actor)
		world.survivors.append(actor)
		world.power_commit = func(before: Dictionary,request: Dictionary) -> Dictionary:
			var after: Dictionary = PowerAuthority.propose(before,request)
			return {"error":OK,"world":after} if not after.is_empty() else {"error":ERR_INVALID_DATA}
		world.third_power_panel = PowerSlotPanel.new()
		world.third_power_panel.slot_index = 2
		world.third_power_panel.position = Vector2(16,456)
		world.third_power_panel.activation_requested.connect(world.request_power.bind(2))
		world._hud.view.add_child(world.third_power_panel)
		world._present_power_slot(world.third_power_panel,2)
		var caption: Label = CampStyle.label("第三槽输入定向样本 · 临时世界 / 不写存档",18,CampStyle.AMBER)
		caption.position = Vector2(350,550)
		world._hud.view.add_child(caption)
		await _hold(4)
		viewport.gui_release_focus()
		if method == "key-five":
			await _ui_key(KEY_5)
		else:
			await _ui_click(world.third_power_panel.activation_button.get_global_rect().get_center())
		var event: Dictionary = SpecialPowers.event_at(world.powers,2)
		_check(event.get("ability_id") == SpecialPowers.SUPPRESSION and event.get("slot") == 2,
			"live Expedition %s reaches the original third-slot power authority" % method)
		_check(not world.request_power(2) and world.powers.accepted.size() == 1, "same third-slot charge cannot activate twice")
		world._present_power_slot(world.third_power_panel,2)
		_check(world.third_power_panel.activation_button.disabled, "used third-slot button visibly disables")
		_write("ephemeral-input-%s.json" % method,{"scope":"DIRECTED_EPHEMERAL_NO_JOURNAL","input":method,"powers":world.powers})
		await _shot("fixture-third-slot-"+method)
		world.queue_free()
		await _hold(3)
	app._screen.show()

func _compact_specialty_hud() -> void:
	# Exercise the original HUD builder, with declared read-only data and no journal.
	app._screen.hide()
	viewport.size = Vector2i(1024,576)
	var world: InputWorld = InputWorld.new()
	world.player_mode = true
	world.layout = StreetLayout.new()
	world.ui_theme = app._screen.theme
	world.supply = MissionSupply.new()
	var inventory: Dictionary = PowerState.initial_progression(SpecialPowers.M48_VERSION)
	inventory.slots = [SpecialPowers.SPEED,SpecialPowers.FREEZE,SpecialPowers.SUPPRESSION]
	inventory.investments.second_slot = 3
	inventory.investments.third_slot = 4
	var specialty: Array[String] = [BuildItems.STRIDE_HARNESS,BuildItems.GUIDED_MAG,BuildItems.AID_KIT]
	world.supply.generated = {"version":8,"powers":inventory,"build":{"version":BuildItems.M48_POOL,
		"slots":[BuildItems.STRIDE_HARNESS,BuildItems.GUIDED_MAG,BuildItems.AID_KIT,""],"enhanced":specialty.duplicate()}}
	world.powers = SpecialPowers.initial(UI_BINDING,PowerState.loadout(inventory))
	world.basic_support.configure(UI_BINDING)
	viewport.add_child(world)
	world._effects = Node2D.new()
	world.add_child(world._effects)
	world._make_ui()
	world._present_power()
	world._present_support()
	var caption: Label = CampStyle.label("只读战场布局样本 · 三强化专精道具 / 三能力 · 不写资格",16,CampStyle.AMBER)
	caption.position = Vector2(330,540)
	world._hud.view.add_child(caption)
	var before: String = RecordEncoding.fingerprint({"generated":world.supply.generated,"powers":world.powers,"support":world.basic_support.snapshot()})
	await _hold(5)
	var frame: Rect2 = viewport.get_visible_rect()
	var power_rects: Array = []
	for panel: PowerSlotPanel in [world.power_panel,world.second_power_panel,world.third_power_panel]:
		_check(panel != null and panel.is_visible_in_tree() and frame.encloses(panel.activation_button.get_global_rect()),
			"1024x576 original HUD keeps each of the three ability buttons inside the viewport")
		if panel != null:
			power_rects.append(_ui_rect(panel.activation_button.get_global_rect()))
	var kit: PanelContainer = null
	var detail: Label = null
	for node: Node in world._hud.view.get_children():
		if not node is PanelContainer:
			continue
		for child: Node in node.get_children():
			if child is Label and child.text == "专精道具 · 3 件":
				kit = node as PanelContainer
				detail = child as Label
	_check(kit != null and detail != null, "1024x576 original HUD replaces the three specialty descriptions with a compact summary")
	if kit != null and detail != null:
		_check(frame.encloses(kit.get_global_rect()) and frame.encloses(detail.get_global_rect())
			and kit.get_global_rect().position.y >= world.third_power_panel.get_global_rect().end.y,
			"compact specialty panel stays below the third ability and wholly inside the viewport")
		var tooltip: String = detail.tooltip_text
		_check(tooltip.contains("步行速度 ×1.20") and tooltip.contains("枪械换弹时长 ×0.80") and tooltip.contains("冷却 24 秒"),
			"compact specialty tooltip reports all actual enhanced movement reload and Q values")
		_check(detail.mouse_filter == Control.MOUSE_FILTER_STOP, "compact specialty label receives native mouse hover for its tooltip")
		await _shot("fixture-compact-specialty-three-powers-1024x576")
		var hover: InputEventMouseMotion = InputEventMouseMotion.new()
		hover.position = detail.get_global_rect().get_center()
		hover.global_position = hover.position
		viewport.push_input(hover,true)
		await _hold(3)
		_check(viewport.gui_get_hovered_control() == detail, "native viewport mouse reaches the compact specialty tooltip label")
		await _ui_click(detail.get_global_rect().get_center())
		var expanded: PanelContainer = world._hud.view.get_node("SpecialtyDetails")
		_check(expanded.visible and frame.encloses(expanded.get_global_rect()), "native click opens the complete enhanced specialty values inside the viewport")
		await _shot("fixture-compact-specialty-expanded-1024x576")
		await _ui_key(KEY_ENTER)
		_check(not expanded.visible, "keyboard confirmation closes the expanded specialty values")
		# Wait only for the real GUI tooltip delay; no gameplay or source state advances.
		await create_timer(0.75).timeout
		await _shot("fixture-compact-specialty-tooltip-1024x576")
		ui_layouts.append({"scope":"SYNTHETIC_READ_ONLY_ORIGINAL_HUD","viewport":[1024,576],"kit_rect":_ui_rect(kit.get_global_rect()),
			"label_rect":_ui_rect(detail.get_global_rect()),"ability_button_rects":power_rects,"text":detail.text,"tooltip":tooltip,
			"hovered_label":viewport.gui_get_hovered_control() == detail,"physical_input":"NOT_TESTED"})
	_check(before == RecordEncoding.fingerprint({"generated":world.supply.generated,"powers":world.powers,"support":world.basic_support.snapshot()}),
		"compact HUD render and hover do not change the ephemeral configuration clocks or uses")
	world.queue_free()
	viewport.size = Vector2i(1280,720)
	app._screen.show()
	await _hold(3)

func _ui_key(code: Key) -> void:
	for down: bool in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		viewport.push_input(event,true)
		await _frame()
	await _hold(2)

func _ui_mouse(point: Vector2,button: MouseButton,down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = down
	viewport.push_input(event,true)
	await _frame()

func _ui_click(point: Vector2) -> void:
	await _ui_mouse(point,MOUSE_BUTTON_LEFT,true)
	await _ui_mouse(point,MOUSE_BUTTON_LEFT,false)
	await _hold(3)

func _ui_select(choice: OptionButton,index: int) -> void:
	await _tap(choice)
	var popup: PopupMenu = choice.get_popup()
	_check(popup.visible,"slot dropdown opens from keyboard focus")
	if not popup.visible:
		return
	popup.set_focused_item(index)
	await _ui_key(KEY_ENTER)

func _ui_near(value: float,expected: float) -> bool:
	return absf(value-expected) < 0.01

func _ui_rect(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
