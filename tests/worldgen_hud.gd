extends SceneTree
## Controlled field HUD. Only read-only DTOs and viewport events; no player progress.
const HUD: PackedScene = preload("res://src/features/expedition_hud/expedition_hud.tscn")
var failures: int = 0
var checks: Array[Dictionary] = []
var metrics: Array[Dictionary] = []

func _initialize() -> void:
	root.unfocusable = true
	call_deferred("run")

func run() -> void:
	var base: Dictionary = _camp()
	var fingerprint: String = SurvivalContracts.fingerprint(base)
	for size: Vector2i in [Vector2i(1280,720), Vector2i(1024,576)]:
		for count: int in [3,4]:
			await _case(base,size,count)
	_check(SurvivalContracts.fingerprint(base)==fingerprint,"HUD never mutates its camp source")
	print("WORLDGEN_HUD "+JSON.stringify({"checks":checks,"metrics":metrics,"failures":failures,"scope":"controlled read-only HUD with viewport keyboard events; no physical input"}))
	quit(1 if failures else 0)

func _case(base: Dictionary, size: Vector2i, count: int) -> void:
	var tag: String="%dx%d/%d"%[size.x,size.y,count]
	var viewport: SubViewport=SubViewport.new()
	viewport.size=size
	viewport.gui_embed_subwindows=true
	root.add_child(viewport)
	var hud: C1ExpeditionHud=HUD.instantiate() as C1ExpeditionHud
	viewport.add_child(hud)
	var support: BasicSupportPanel=BasicSupportPanel.new()
	hud.add_child(support)
	support.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	support.offset_left=-220
	support.offset_right=220
	support.offset_top=-76
	support.offset_bottom=-8
	var members: Array[Dictionary]=[]
	for id: int in range(1,count+1):
		var model: Dictionary=PersonaViewModel.camp(base,id,"camp" if id<=2 else "candidate")
		model.scope="field"
		model.editable=false
		model.status="搜寻·街角便利03" if id==1 else "前往·停放车辆02"
		members.append({"id":id,"persona":model})
	var objectives: Array[Dictionary]=[
		{"id":"primary","title":"搜寻主装备点","optional":false,"done":0,"total":1,"complete":false,"hint":"真实站点目标"},
		{"id":"vehicles","title":"搜完停放车辆","optional":true,"done":1,"total":3,"complete":false,"hint":"真实车辆进度"},
		{"id":"trees","title":"采完本图果树","optional":true,"done":2,"total":2,"complete":true,"hint":"真实果树进度"}]
	var before: String=SurvivalContracts.fingerprint({"rows":objectives})
	var located: Array[String]=[]
	var pauses: Array[bool]=[]
	hud.objective_locate_requested.connect(func(id: String)->void:located.append(id))
	hud.pause_requested.connect(func()->void:pauses.append(true))
	hud.refresh({"mission_title":"商业街区","objective":"","day_text":"第 2 天","survivors":members,"exploration_objectives":objectives,"time":{"text":"01:40","compact_hint":"威胁 1","hint":"暮色 · 增援加快"},"resource_text":"货币 53 · 食物 2\n携带：钱1 · 粮0 · 武器0","bus_status_text":"巴士就绪","bus_action_label":"发动巴士","bus_action_enabled":true})
	support.present("8.3s","空槽",false,false)
	await _settle()
	var bounds: Rect2=Rect2(Vector2.ZERO,Vector2(size)).grow(.5)
	var clear_center: Rect2=Rect2(300,160,size.x-520,size.y-280)
	var panel_metrics: Array[Dictionary]=[]
	var clear: bool=true
	for node_name: String in ["MissionPanel","TimePanel","ResourcesPanel","MembersPanel","ActionsPanel"]:
		var panel: Control=hud.get_node(node_name) as Control
		var rect: Rect2=panel.get_global_rect()
		clear=clear and bounds.encloses(rect) and not clear_center.intersects(rect)
		panel_metrics.append({"name":node_name,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
	_check(clear,tag+" required panels remain bounded and leave the continuous play area clear")
	_check(not hud.persona_details.visible and not hud._member_details_panel.visible,tag+" full details stay closed by default")
	var compact: bool=true
	for card: PersonaCard in hud._persona_cards:
		hud._member_scroll.ensure_control_visible(card)
		await _settle()
		compact=compact and card.size.x<=160 and card.size.y<=82 and bounds.encloses(card.get_global_rect())
		compact=compact and card.portrait.visible and card.health_bar.visible and card.status_label.visible
		compact=compact and not card.name_label.visible and not card.health_label.visible and not card.ammo_label.visible and not card.positive_label.get_parent().visible
	_check(compact,tag+" all three/four portraits, health bars and work states fit in compact rows")
	var keys: Array[Control]=[support.rally_button,support.focus_button,support.heal_button,support.special_button]
	_check(support.size.x<=448 and support.size.y<=80 and keys.all(func(button: Control)->bool: return bounds.encloses(button.get_global_rect())) and not clear_center.intersects(support.get_global_rect()),tag+" Q/W/E/R stay on a compact bottom strip outside the play area")
	_check(support.rally_button.text.contains("集合") and support.focus_button.text.contains("集火") and support.heal_button.text.contains("8.3s") and support.special_button.text.contains("空槽"),tag+" cooldown and empty special states keep their actual meaning")
	await _activate(viewport,hud._persona_cards[0].info_button)
	await _settle()
	_check(hud.persona_details.visible and hud.persona_details.name_label.text.contains(members[0].persona.name) and hud.persona_details.weapon_label.text==members[0].persona.weapon_detail and hud.persona_details.positive_label.text.contains(members[0].persona.positive.name),tag+" keyboard selection reveals the original complete identity and loadout")
	_check(bounds.encloses(hud.persona_details.get_global_rect()) and hud.persona_details.mouse_filter==Control.MOUSE_FILTER_STOP and not hud.persona_details.mouse_force_pass_scroll_events,tag+" open details own clicks and wheel events inside their bounds")
	await _activate(viewport,hud.persona_details.close_button)
	_check(not hud.persona_details.visible and hud._persona_id==0,tag+" keyboard close releases detail selection")
	await _activate(viewport,hud._exploration_objectives.locate_buttons[1])
	var expanded: float=(hud.get_node("MissionPanel") as Control).size.y
	await _activate(viewport,hud._objective_toggle)
	await _settle()
	_check(located==["vehicles"] and not hud._exploration_objectives.visible and (hud.get_node("MissionPanel") as Control).size.y<expanded and pauses.is_empty() and SurvivalContracts.fingerprint({"rows":objectives})==before,tag+" keyboard locate/fold preserves source facts and never requests pause")
	metrics.append({"case":tag,"panels":panel_metrics,"clear_center":[clear_center.position.x,clear_center.position.y,clear_center.size.x,clear_center.size.y]})
	viewport.queue_free()
	await process_frame

func _activate(viewport: SubViewport, button: Button) -> void:
	button.grab_focus()
	await _settle()
	for down: bool in [true,false]:
		var event: InputEventKey=InputEventKey.new()
		event.keycode=KEY_ENTER
		event.physical_keycode=KEY_ENTER
		event.pressed=down
		viewport.push_input(event,true)
		await process_frame

func _settle() -> void:
	for tick: int in range(4): await process_frame

func _check(passed: bool,label: String) -> void:
	checks.append({"pass":passed,"label":label})
	if not passed:
		failures+=1
		printerr("WORLDGEN_HUD_FAIL "+label)

func _camp() -> Dictionary:
	var crew: Array[Dictionary]=SurvivorRoster.new_crew()
	GrowthRules.initialize(crew)
	TraitRules.initialize(crew)
	TrainingState.initialize(crew)
	var value: Dictionary={"schema_version":5,"profile_id":"0123456789abcdef0123456789abcdef","day":2,"cash":53,"food":RunSave.DefaultRules.initial_food,"last_day":{},"settled_sorties":0,"last_settlement_id":"","crew":crew}
	WeaponInventory.initialize(value,"initial")
	for index: int in range(value.weapons.size()): value.weapons[index]=WeaponModifiers.baseline(value.weapons[index])
	var journey: Dictionary=EnemyState.initial("m14-hud")
	journey.campaign=CampaignRules.initial(value.profile_id)
	journey.build=PersonaState.initial_build(journey.seed)
	return EnemyState.snapshot(value,journey,[],[])
