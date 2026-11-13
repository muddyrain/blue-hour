class_name ExpeditionFeedback
extends RefCounted
## Presentation hooks for future hitstop, camera shake, animation and audio.

var _atmosphere: ExpeditionAtmosphere = ExpeditionAtmosphere.new()
var x: Expedition


func _init(owner: Expedition) -> void:
	x = owner


func _draw() -> void:
	if x.combat.burst != null:
		x.combat.burst.draw_warning(x)
	for job: Dictionary in x.search_assignments.ordered():
		var actor: FieldActor = x.search_member(int(job.member_id))
		if actor != null and actor.activity == FieldActor.Activity.MOVING:
			x.draw_dashed_line(actor.position, x.search_site(StringName(job.site_id)).door, Color("e3c879"), 1.5, 8.0)
	if x.phase == Expedition.Phase.BOARDING:
		x.draw_circle(x.layout.bus_door, x.tuning.boarding_radius, Color(0.9, 0.75, 0.3, 0.2))
		x.draw_arc(x.layout.bus_door, x.tuning.boarding_radius, 0.0, TAU, 48, Color("e3c879"), 2.0)
	if x.goal != Vector2.ZERO and x.phase != Expedition.Phase.FINISHED:
		x.draw_arc(x.goal, 13.0, 0.0, TAU, 24, Color("b3e8d9"), 2.0, true)
		x.draw_line(x.goal - Vector2(6, 0), x.goal + Vector2(6, 0), Color("b3e8d9"), 2.0)
		for actor: FieldActor in x.survivors:
			if actor.activity == FieldActor.Activity.MOVING and not x.has_search_job(actor.member_id):
				x.draw_dashed_line(actor.position, x.goal, Color(0.8, 0.95, 0.91, 0.4), 1.0, 8.0)


func _shot_effect(from: Vector2, to: Vector2, damage: float) -> void:
	x._shot_trace(from, to + Vector2.UP * AttackRules.HIT_HEIGHT, Color("f1d5a1"))
	x._hit_effect(to, damage, false)


func _shot_trace(from: Vector2, to: Vector2, colour: Color) -> void:
	var line: Line2D = Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 1.5
	line.default_color = colour
	x._effects.add_child(line)
	var tween: Tween = line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.09)
	tween.tween_callback(line.queue_free)


func _hit_effect(to: Vector2, damage: float, survivor_hit: bool) -> void:
	_draw_hit_effect(to, damage, survivor_hit, "")


func _draw_hit_effect(to: Vector2, damage: float, survivor_hit: bool, prefix: String) -> void:
	var impact: Node2D = Node2D.new()
	impact.position = to + Vector2(0, -30)
	x._effects.add_child(impact)
	for index: int in range(4):
		var spark: Line2D = Line2D.new()
		var direction: Vector2 = Vector2.RIGHT.rotated(float(index) * TAU / 4.0 + 0.4)
		spark.points = PackedVector2Array([direction * 4.0, direction * 9.0])
		spark.width = 2.0
		spark.default_color = Color("f1ac80") if survivor_hit else Color("f5dda0")
		impact.add_child(spark)
	var fade: Tween = impact.create_tween()
	fade.tween_property(impact, "modulate:a", 0.0, 0.18)
	fade.tween_callback(impact.queue_free)
	var amount_text: String = str(int(damage)) if is_equal_approx(damage,roundf(damage)) else "%.2f" % damage
	var text: String = prefix + ("−" if survivor_hit else "") + amount_text
	_combat_popup(to + Vector2(-38 if survivor_hit else 8, -108), text,
		Color("f8b491") if survivor_hit else Color("f1dfbd"))


func _combat_popup(at: Vector2, text: String, colour: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color("142d36"))
	label.add_theme_constant_override("outline_size", 3)
	label.position = at
	x._effects.add_child(label)
	var popup: Tween = label.create_tween()
	popup.tween_property(label, "position:y", label.position.y - 18.0, 0.5)
	popup.tween_callback(label.queue_free)


func _show_notice(message: String) -> void:
	x._notice_text = message
	x._notice_clock = 7.0


func _refresh_night_lighting() -> void:
	if x._night_lighting == null:
		return
	var daylight: float = maxf(1.0, x.tuning.daylight_seconds)
	var amount: float = clampf(x.elapsed / daylight, 0.0, 1.0)
	_atmosphere.refresh(x, amount)
	x._night_lighting.refresh(amount, x._bus_sprite.get_global_transform_with_canvas().origin, x.camera.zoom.x)


func _street_camera_start() -> Vector2:
	if ReconActionV1.enabled(x.supply.generated):
		return x.layout.bus_door
	var view_size: Vector2 = x.get_viewport_rect().size / x.camera.zoom
	var yard: Dictionary = x.layout.world_data.get("loading_yard", x.layout.world_data.get("rescue_court", {}))
	if not yard.is_empty():
		var scene: Rect2 = WorldLayout.rect(yard.bounds).expand(x.layout.bus_door + Vector2(0, 42))
		if scene.size.x <= view_size.x - 144 and scene.size.y <= view_size.y - 160:
			return scene.get_center() - Vector2(0, 32)
	if x._supply_entrances.is_empty():
		return x.layout.camera_start
	var focus: Rect2 = Rect2(x.layout.bus_door, Vector2.ZERO).expand(x._supply_entrances[0])
	var both: Rect2 = focus.expand(x._supply_entrances[1])
	if both.size.x <= view_size.x - 192 and both.size.y <= view_size.y - 192:
		focus = both
	var roof_room: float = clampf((view_size.y - focus.size.y) * 0.5 - 96, 0, 72)
	return focus.get_center() - Vector2(0, roof_room)

func _present_support() -> void:
	if not x.build_mode() or x.support_panel==null: return
	if not x.support_available(): x.support_aiming=false
	var state: Dictionary=x.basic_support.snapshot()
	var members: Array[Dictionary]=[]
	for actor: FieldActor in x.survivors: members.append({"member_id":actor.member_id,"health":actor.health,"max_health":actor.max_health,"present":actor.activity!=FieldActor.Activity.DOWN})
	var plan: Dictionary=x.basic_support.plan_heal(members,BuildItems.frozen_factors(x.supply.generated.build).heal)
	var heal_text: String="Q 治疗 · %.1fs"%state.cooldowns.heal if state.cooldowns.heal>0 else "Q 治疗 · 队员%d +%.0fHP"%[plan.member_id,plan.amount] if not plan.is_empty() else "Q 治疗 · 无受伤存活者"
	var strike_text: String="E 空袭 · %.1fs"%state.cooldowns.airstrike if state.cooldowns.airstrike>0 else "左键确认 · 右键/Esc取消" if x.support_aiming else "E 空袭 · 就绪"
	if not x.support_available(): heal_text="治疗 · 当前阶段不可用"; strike_text="空袭 · 当前阶段不可用"
	var point: Vector2=x.get_global_mouse_position()
	var aim_plan: Dictionary = x.support_plan_airstrike(point) if x.support_aiming else {}
	var legal: bool = not aim_plan.is_empty()
	if x._barricade_view != null:
		x._barricade_view.present(x.barricade_open, x.support_aiming and not x.barricade_open)
		if not x.barricade_open and legal and BarricadeState.hits(x.supply.generated, aim_plan, x.layout):
			strike_text = "可炸开路障 · 左键确认"
	x.support_panel.present(heal_text,strike_text,x.support_available() and state.cooldowns.heal==0 and not plan.is_empty(),x.support_available() and state.cooldowns.airstrike==0)
	if x.support_aiming:
		var caller: FieldActor=null
		for actor: FieldActor in x.survivors:
			if actor.health>0 and actor.visible and actor.activity not in [2,3,4] and (caller==null or actor.position.distance_to(point)<caller.position.distance_to(point) or (actor.position.distance_to(point)==caller.position.distance_to(point) and actor.member_id<caller.member_id)): caller=actor
		if caller!=null: x.support_aim.present_caller(caller.position)
	x.support_aim.present(point,BasicSupport.POLICY.airstrike_radius*BuildItems.frozen_factors(x.supply.generated.build).blast,legal,x.support_aiming)

func _present_power() -> void:
	if not x.power_mode() or x.power_panel==null: return
	_present_power_slot(x.power_panel, 0)
	if x.second_power_panel != null:
		_present_power_slot(x.second_power_panel, 1)
	if x.third_power_panel != null:
		_present_power_slot(x.third_power_panel, 2)
	var members: Array[Dictionary]=[]
	var foes: Array[Dictionary]=[]
	for actor: FieldActor in x.survivors: members.append({"position":actor.position,"moving":actor.activity==FieldActor.Activity.MOVING,"alive":actor.health>0 and actor.visible})
	for actor: FieldActor in x.enemies: foes.append({"position":actor.position,"moving":actor.activity==FieldActor.Activity.MOVING,"alive":actor.health>0 and actor.visible})
	x.power_view.present(members,foes,SpecialPowers.ability_remaining(x.powers,SpecialPowers.SPEED,x.elapsed)>0,x.power_frozen,x.elapsed)

func _present_power_slot(panel: PowerSlotPanel, slot: int) -> void:
	var id: String = SpecialPowers.equipped_at(x.powers, slot)
	var loadout: Variant = x.powers.get("loadout")
	var remaining: float = SpecialPowers.remaining(x.powers, x.elapsed, slot)
	var used: bool = not x.basic_support.ready(id) if id == SpecialPowers.RADIO else not SpecialPowers.event_at(x.powers, slot).is_empty()
	var status: String = "营地装配" if id.is_empty() else "持续 %.1f 秒" % remaining if remaining > 0.0 else "已用" if used else "就绪"
	panel.present("特殊能力空槽" if id.is_empty() else SpecialPowers.definition(id).name,
		status, remaining, (SpecialPowers.effect_duration(loadout, id) if loadout is Dictionary else SpecialPowers.duration(id, false)) if not id.is_empty() else 0.0,
		x.support_available() and not id.is_empty() and not used, id,
		SpecialPowers.radio_amount(loadout) if loadout is Dictionary else 24.0)


func refresh_recon_view() -> void:
	if x._recon_view != null:
		x._recon_view.queue_redraw()


func _present_recon_objectives(rows: Array[Dictionary]) -> void:
	var marker: Dictionary = x.supply.generated.recon
	var primary: Expedition.SearchSite = x.search_site(StringName(marker.primary_id))
	if not x.site_discovered(primary):
		rows[0].title = "装备区域 · 位置待发现"
		rows[0].hint = "定位到大致区域。走近后发现主点，也可先派工侦察。"
	var optional: Expedition.SearchSite = x.search_site(StringName(marker.optional_id))
	for index: int in range(rows.size() - 1, 0, -1):
		var row: Dictionary = rows[index]
		row.site_ids = row.site_ids.filter(func(id: String) -> bool: return x.site_discovered(x.search_site(StringName(id))))
		if row.site_ids.is_empty() or (row.id == "toolbox" and optional == x._toolbox_site()):
			rows.remove_at(index)
	rows.insert(1, {"id":"recon", "title":"侦察 · 已标记 2 处" if x.recon_site.searched else "侦察点 %.1f/6 秒" % x.recon_site.progress,
		"optional":true, "complete":x.recon_site.searched, "done":int(x.recon_site.searched), "total":1, "site_ids":[ReconActionV1.SITE_ID],
		"hint":"到点后派一人侦察。只提供目标信息，可随时取消。"})
	if x.site_discovered(optional):
		var title: String = "可搜建筑 · 工具箱" if optional == x._toolbox_site() else "已发现 · 可搜建筑"
		rows.insert(2, {"id":"recon_optional", "title":title, "optional":true, "complete":optional.searched,
			"done":int(optional.searched), "total":1, "site_ids":[marker.optional_id], "hint":"按原条件搜集此建筑。"})


func locate_objective(id: String) -> void:
	if not x.exploration_mode(): return
	if id == "primary" and x.recon_site != null and not x.site_discovered(x.search_site(&"cash")):
		x.camera.position = x.recon_region().get_center()
		x.camera._clamp_position()
		x.camera.force_update_scroll()
		if x._locate_marker != null:
			x._locate_marker.hide()
		return
	var rows: Array[Dictionary] = x._exploration_objective_rows()
	var target: Vector2=Vector2.INF
	var target_prop: FieldProp
	for row: Dictionary in rows:
		if row.id!=id: continue
		var pending: Array[String]=[]
		for site_id: String in row.site_ids:
			var site: Expedition.SearchSite=x.search_site(StringName(site_id))
			if site!=null and not site.searched: pending.append(site_id)
		if pending.is_empty(): pending.assign(row.site_ids)
		if pending.is_empty():
			target=x.layout.rescue_point
		else:
			var index: int=int(x._objective_cursors.get(id,0))%pending.size()
			var site: Expedition.SearchSite = x.search_site(StringName(pending[index]))
			target = site.door
			target_prop = site.prop
			x._objective_cursors[id]=index+1
		break
	if not target.is_finite(): return
	x.camera.position=target
	x.camera._clamp_position()
	x.camera.force_update_scroll()
	if x._locate_marker==null:
		x._locate_marker=Node2D.new()
		x._effects.add_child(x._locate_marker)
		x._locate_ring = Line2D.new()
		x._locate_ring.width=3.0; x._locate_ring.default_color=Color("f2c47c")
		for i: int in range(33):x._locate_ring.add_point(Vector2.from_angle(TAU*i/32.0)*34.0)
		x._locate_marker.add_child(x._locate_ring)
		x._locate_label = Label.new()
		x._locate_label.text="目标位置"; x._locate_label.position=Vector2(-30,-60); x._locate_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		x._locate_label.add_theme_font_size_override("font_size",16)
		x._locate_label.add_theme_color_override("font_color",Color("ffe5a7"))
		x._locate_marker.add_child(x._locate_label)
	var has_badge: bool = target_prop != null and not target_prop.loot_category.is_empty()
	var recon_pin: bool = x.recon_site != null and id in ["primary", "recon_optional", "recon"]
	x._locate_label.visible = not has_badge and not recon_pin and id != BillboardActionV1.SITE_ID
	# Shrink the pulse around the clickable entrance to clear the building badge.
	var ring_scale: float = 0.5 if has_badge and not target_prop is ExplorationProp else 1.0
	x._locate_ring.scale = Vector2.ONE * ring_scale
	x._locate_ring.width = 3.0 / ring_scale
	if x._locate_tween!=null: x._locate_tween.kill()
	x._locate_marker.position=target
	x._locate_marker.show()
	x._locate_marker.modulate.a=1.0
	x._locate_tween=x.create_tween()
	x._locate_tween.tween_interval(0.6)
	x._locate_tween.tween_property(x._locate_marker,"modulate:a",0.0,1.3)


func _make_camera() -> void:
	x.camera = FieldCamera.new()
	x.camera.pan_speed = x.tuning.camera_pan_speed
	x.camera.min_zoom = x.tuning.camera_min_zoom
	x.camera.max_zoom = x.tuning.camera_max_zoom
	x.camera.zoom_step = x.tuning.camera_zoom_step
	x.camera.bounds = x.layout.world_bounds
	x.add_child(x.camera)
	x.camera.pan_by(_street_camera_start() - x.camera.position)


func _stop_camera() -> void:
	x.camera.set_process(false)
	x.camera.set_process_unhandled_input(false)
