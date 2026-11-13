extends SceneTree
## DIRECTED_EPHEMERAL: synthetic actors/worlds and component proposals only.
## No save, catalog qualification, resource acquisition, or campaign result is created.

class ClockWorld extends Expedition:
	var completions: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _draw() -> void:
		pass
	func _update_ui() -> void:
		pass
	func _show_notice(message: String) -> void:
		_notice_text = message
	func _hit_effect(_to: Vector2, _damage: float, _survivor_hit: bool) -> void:
		pass
	func _shot_effect(_from: Vector2, _to: Vector2, _damage: float) -> void:
		pass
	func _shot_trace(_from: Vector2, _to: Vector2, _colour: Color) -> void:
		pass
	func _combat_popup(_at: Vector2, _text: String, _colour: Color) -> void:
		pass
	func _update_enemy_paths(_idle_only: bool = false) -> void:
		# Keep the declared test paths. Step still owns movement, freeze, attack and clocks.
		pass
	func _complete_search(actor: FieldActor, site: Expedition.SearchSite) -> bool:
		# Observe the real work integrator without granting loot, XP or inventory.
		completions.append({"member_id":actor.member_id, "elapsed":elapsed, "progress":site.progress})
		site.searched = true
		search_assignments.release_member(actor.member_id)
		return true

const BINDING: Dictionary = {
	"run_id":"0123456789abcdef0123456789abcdef", "root_id":"fedcba9876543210fedcba9876543210",
	"transaction_id":"0123456789abcdef0123456789abcdef:1", "base_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "rules_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
}
const STEP: float = 0.001
var checks: int = 0
var failures: int = 0
var observations: Dictionary = {"scope":"DIRECTED_EPHEMERAL", "clock":"simulated seconds", "disk_acceptance":"NOT_TESTED", "campaign":"NOT_TESTED"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(2)
		return
	_movement()
	_work()
	_reload()
	_damage()
	_protection()
	_speed_and_freeze()
	_suppression()
	_healing()
	_power_hud()
	observations.checks = checks
	observations.failures = failures
	observations.pid = OS.get_process_id()
	print("M48_RUNTIME_EFFECTS " + JSON.stringify(observations))
	quit(0 if failures == 0 else 1)

func _world(slots: Array = ["", ""], enhanced: Array = []) -> ClockWorld:
	var world: ClockWorld = ClockWorld.new()
	world.supply = MissionSupply.new()
	world.supply.generated = {"version":8, "type":"equipment", "build":{"version":BuildItems.M48_CATALOG_POOL, "slots":slots.duplicate(), "enhanced":enhanced.duplicate()}, "sites":[{"id":"cash", "point":[400.0,400.0], "building":"directed-building"}]}
	world._spawn_clock = 10000.0
	world._ai_clock = 10000.0
	world.navigation.configure([], Rect2(0,0,6000,2000))
	root.add_child(world)
	world.combat.setup(world)
	world.basic_support.configure(BINDING)
	return world

func _actor(world: ClockWorld, point: Vector2 = Vector2(400,400)) -> FieldActor:
	var actor: FieldActor = FieldActor.new()
	actor.actor_id = 1
	actor.member_id = 1
	actor.definition_id = &"crew_1"
	actor.position = point
	actor.weapon_instance_id = "directed-runtime:carbine"
	actor.weapon_definition = WeaponInventory.definition("carbine").duplicate() as WeaponDefinition
	actor.magazine = WeaponMagazine.new(actor.weapon_instance_id, "carbine")
	world.add_child(actor)
	actor.visual.set_weapon(actor.weapon_definition.presentation)
	world.survivors.append(actor)
	world.apply_build(actor)
	return actor

func _enemy(world: ClockWorld, point: Vector2, kind: String = EnemyRules.NORMAL) -> FieldActor:
	var actor: FieldActor = FieldActor.new()
	actor.actor_id = 21
	actor.is_enemy = true
	actor.position = point
	actor.speed = 34.0
	actor.enemy_behavior = EnemyBehavior.new()
	actor.enemy_behavior.kind = kind
	world.add_child(actor)
	world.enemies.append(actor)
	return actor

func _movement() -> void:
	var rows: Array[Dictionary] = []
	for upgraded: bool in [false, true]:
		var world: ClockWorld = _world(["light_boots_v1", ""], ["light_boots_v1"] if upgraded else [])
		var actor: FieldActor = _actor(world)
		actor.command_path(PackedVector2Array([actor.position, actor.position + Vector2(1000,0)]))
		var start: Vector2 = actor.position
		for tick: int in range(100):
			FieldContacts.move(world.survivors, world.survivors, world.navigation, 0.01)
		rows.append({"upgraded":upgraded,"seconds":1.0,"pixels":actor.position.distance_to(start)})
		world.free()
	_check(_near(rows[0].pixels,143.75,0.01) and _near(rows[1].pixels,156.25,0.01), "same path and clock produce actual enhanced movement")
	observations.movement = rows

func _work() -> void:
	var rows: Array[Dictionary] = []
	for upgraded: bool in [false, true]:
		var world: ClockWorld = _world(["field_tools_v1", ""], ["field_tools_v1"] if upgraded else [])
		var actor: FieldActor = _actor(world)
		var site: Expedition.SearchSite = Expedition.SearchSite.new(&"cash", actor.position)
		site.seconds = 12.0
		world.sites.assign([site])
		world._cash_site = site
		world.search_assignments.assign(actor.member_id, "cash")
		world.search_assignments.begin(actor.member_id)
		actor.activity = FieldActor.Activity.SEARCHING
		actor.hide()
		while world.completions.is_empty() and world.elapsed < 15.0:
			world.elapsed += STEP
			world._update_search(STEP)
		_check(world.completions.size() == 1 and site.searched, "real work integrator completes once")
		rows.append({"upgraded":upgraded,"seconds":world.elapsed,"site_progress":site.progress})
		world._update_search(1.0)
		_check(world.completions.size() == 1, "completed work cannot grant another completion")
		world.free()
	_check(_near(rows[0].seconds,9.0,0.002) and _near(rows[1].seconds,7.2,0.002), "enhancement changes actual work completion from nine to 7.2 seconds")
	observations.work = rows

func _reload() -> void:
	var rows: Array[Dictionary] = []
	for upgraded: bool in [false, true]:
		var world: ClockWorld = _world(["quick_loader_v1", BuildItems.GUIDED_MAG], ["quick_loader_v1", BuildItems.GUIDED_MAG] if upgraded else [])
		var actor: FieldActor = _actor(world)
		var gun: WeaponMagazine = actor.magazine
		for shot: int in range(gun.capacity()):
			gun.commit_shot()
		var clock: float = 0.0
		while gun.reloading and clock < 3.0:
			gun.advance(STEP)
			clock += STEP
		rows.append({"upgraded":upgraded,"seconds":clock,"rounds":gun.rounds,"capacity":gun.capacity()})
		_check(gun.rounds == gun.capacity() and not gun.reloading, "actual magazine reloads to capacity")
		world.free()
	_check(_near(rows[0].seconds,1.08,0.002) and _near(rows[1].seconds,0.768,0.002), "two reload items apply once to actual magazine clock")
	observations.reload = rows

func _damage() -> void:
	var rows: Array[Dictionary] = []
	for upgraded: bool in [false, true]:
		var world: ClockWorld = _world(["pressure_rounds_v1", ""], ["pressure_rounds_v1"] if upgraded else [])
		var actor: FieldActor = _actor(world)
		var target: FieldActor = _enemy(world, Vector2(470,400))
		var before: float = target.health
		var decision: AttackRules.Decision = world.evaluate_attack(actor,target)
		_check(decision.can_fire, "controlled nonlethal target is legally shootable")
		if decision.can_fire:
			world._fire_ranged(actor,target,decision)
		rows.append({"upgraded":upgraded,"hp_lost":before-target.health,"rounds":actor.magazine.rounds,"base_damage":WeaponInventory.definition("carbine").damage})
		_check(actor.magazine.rounds == actor.magazine.capacity()-1 and target.health > 0.0, "real hit consumes exactly one round without death/XP fixture")
		world.free()
	_check(_near(rows[0].hp_lost,rows[0].base_damage*1.20) and _near(rows[1].hp_lost,rows[1].base_damage*1.35), "actual target HP confirms enhanced damage")
	observations.damage = rows

func _protection() -> void:
	var rows: Array[Dictionary] = []
	for upgraded: bool in [false, true]:
		var world: ClockWorld = _world([BuildItems.FILTER,""], [BuildItems.FILTER] if upgraded else [])
		var actor: FieldActor = _actor(world,Vector2(280,400))
		_enemy(world,Vector2(200,400),CombatEnemyRules.TOXIC)
		world.combat.advance_toxic(world,0.0)
		world.combat.advance_toxic(world,0.90)
		var before: float = actor.health
		world.combat.advance_toxic(world,0.75)
		rows.append({"upgraded":upgraded,"tick_seconds":0.75,"hp_lost":before-actor.health,"pending":world.combat.toxic.pending.duplicate(true)})
		_check(world.combat.toxic.pending.is_empty(), "actual poison tick acknowledges its committed victim")
		world.free()
	_check(_near(rows[0].hp_lost,3.0) and _near(rows[1].hp_lost,2.1), "actual poison damage gate applies base and enhanced protection")
	observations.protection = rows

func _equip_power(world: ClockWorld, id: String, upgraded: bool) -> void:
	var inventory: Dictionary = PowerState.initial_progression(SpecialPowers.M48_VERSION)
	inventory.slots[0] = id
	if upgraded:
		inventory.investments[SpecialPowers.upgrade_key(id)] = 3
	var loadout: Dictionary = PowerState.loadout(inventory)
	world.supply.generated.powers = inventory
	world.powers = SpecialPowers.initial(BINDING,loadout)
	if id != SpecialPowers.RADIO:
		world.powers = SpecialPowers.accept(world.powers,SpecialPowers.request(world.powers),0.0)
	world.refresh_power_factors()

func _speed_and_freeze() -> void:
	var speed_rows: Array[Dictionary] = []
	var freeze_rows: Array[Dictionary] = []
	for upgraded: bool in [false,true]:
		var world: ClockWorld = _world()
		var actor: FieldActor = _actor(world)
		_equip_power(world,SpecialPowers.SPEED,upgraded)
		actor.command_path(PackedVector2Array([actor.position,actor.position+Vector2(4000,0)]))
		var start: Vector2 = actor.position
		for tick: int in range(90):
			world.step(0.1)
		speed_rows.append({"upgraded":upgraded,"seconds":world.elapsed,"pixels":actor.position.distance_to(start)})
		world.free()
		world = _world()
		actor = _actor(world,Vector2(200,200))
		actor.cooldown = 100.0
		var enemy: FieldActor = _enemy(world,Vector2(1000,500))
		enemy.command_path(PackedVector2Array([enemy.position,enemy.position+Vector2(500,0)]))
		enemy.cooldown = 5.0
		_equip_power(world,SpecialPowers.FREEZE,upgraded)
		start = enemy.position
		world.step(4.5)
		freeze_rows.append({"upgraded":upgraded,"seconds":world.elapsed,"enemy_pixels":enemy.position.distance_to(start),"enemy_cooldown":enemy.cooldown})
		_check(world.power_frozen == upgraded, "freeze expiry changes actual field lock at 4.5 seconds")
		world.free()
	_check(_near(speed_rows[0].pixels,1625.0,0.05) and _near(speed_rows[1].pixels,1687.5,0.05), "enhanced speed remains active after the base eight-second edge")
	_check(_near(freeze_rows[0].enemy_pixels,17.0,0.02) and freeze_rows[1].enemy_pixels == 0.0 and _near(freeze_rows[0].enemy_cooldown,4.5) and freeze_rows[1].enemy_cooldown == 5.0, "freeze holds actual enemy movement and cooldown until its own expiry")
	observations.speed = speed_rows
	observations.freeze = freeze_rows

func _suppression() -> void:
	var rows: Array[Dictionary] = []
	for upgraded: bool in [false,true]:
		var world: ClockWorld = _world()
		var actor: FieldActor = _actor(world)
		actor.cooldown = 100.0
		var enemy: FieldActor = _enemy(world,actor.position+Vector2(24,0))
		_equip_power(world,SpecialPowers.SUPPRESSION,upgraded)
		world.elapsed = 12.5
		var before: float = actor.health
		world._update_combat()
		rows.append({"upgraded":upgraded,"at":world.elapsed,"hp_lost":before-actor.health})
		enemy.cooldown = 0.0
		world.elapsed = 16.0
		before = actor.health
		world._update_combat()
		_check(_near(before-actor.health,world.tuning.enemy_damage), "suppression stops reducing actual direct melee at sixteen seconds")
		world.free()
	_check(_near(rows[0].hp_lost,4.0) and _near(rows[1].hp_lost,2.0), "enhanced suppression still halves actual normal melee after twelve seconds")
	observations.suppression = rows

func _support_world(id: String, upgraded: bool, item: String = "") -> Dictionary:
	var inventory: Dictionary = PowerState.initial_progression(SpecialPowers.M48_VERSION)
	inventory.slots[0] = id
	if upgraded and not id.is_empty():
		inventory.investments[SpecialPowers.upgrade_key(id)] = 3
	var support: BasicSupport = BasicSupport.new()
	support.configure(BINDING,false,id == SpecialPowers.RADIO)
	return {"version":10,"generated":{"version":8,"powers":inventory,"build":{"version":BuildItems.M48_CATALOG_POOL,"slots":[item,""],"enhanced":[item] if upgraded and not item.is_empty() else []}},"support":support.snapshot(),"sim":{"elapsed":0.0},"survivors":[{"state":{"member_id":1,"health":20.0,"max_health":100.0,"visible":true,"activity":FieldActor.Activity.IDLE,"damage_received":80.0}}]}

func _healing() -> void:
	var rows: Array[Dictionary] = []
	for upgraded: bool in [false,true]:
		for kind: String in ["heal",SpecialPowers.RADIO]:
			var world: Dictionary = _support_world(SpecialPowers.RADIO if kind == SpecialPowers.RADIO else "",upgraded,BuildItems.AID_KIT if kind == "heal" else "")
			var plan: Dictionary = BuildAuthority.plan_heal(world) if kind == "heal" else BuildAuthority.plan_radio(world)
			var component: BasicSupport = BasicSupport.new()
			component.restore(world.support,false,kind == SpecialPowers.RADIO)
			var after: Dictionary = BuildAuthority.propose(world,component.request(kind,plan))
			_check(not after.is_empty(), "real support authority accepts directed " + kind)
			if after.is_empty():
				continue
			component.restore(after.support,false,kind == SpecialPowers.RADIO)
			rows.append({"upgraded":upgraded,"kind":kind,"hp_before":20.0,"hp_after":after.survivors[0].state.health,"cooldown":component.remaining("heal"),"facts":after.support.accepted.back().facts})
			if kind == "heal":
				var expected: float = 24.0 if upgraded else 30.0
				_check(component.remaining("heal") == expected and after.survivors[0].state.health == 68.0, "aid-kit Q applies forty-eight HP and its own frozen cooldown")
				component.advance(expected-0.001,true)
				_check(not component.ready("heal"), "Q rejects before exact cooldown edge")
				component.advance(0.002,true)
				_check(component.ready("heal"), "Q becomes ready after its actual cooldown edge")
			else:
				_check(after.survivors[0].state.health == (60.0 if upgraded else 44.0) and not component.ready(kind), "broadcast changes actual world HP and consumes once")
				world.survivors[0].state.health = 100.0
				_check(BuildAuthority.plan_radio(world).is_empty() and BuildAuthority.propose(world,component.request(kind,{})).is_empty(), "full-health broadcast has no legal accepted proposal")
				var unused: BasicSupport = BasicSupport.new()
				unused.restore(world.support,false,true)
				_check(unused.ready(kind), "no-target proposal does not consume the original charge")
	var clipped: Dictionary = _support_world(SpecialPowers.RADIO,true)
	clipped.survivors[0].state.health = 90.0
	var clip_plan: Dictionary = BuildAuthority.plan_radio(clipped)
	var clip_component: BasicSupport = BasicSupport.new()
	clip_component.restore(clipped.support,false,true)
	var clip_after: Dictionary = BuildAuthority.propose(clipped,clip_component.request(SpecialPowers.RADIO,clip_plan))
	_check(not clip_after.is_empty() and clip_after.survivors[0].state.health == 100.0 and clip_plan.amount == 10.0, "enhanced broadcast clips at maximum health")
	observations.healing = rows

func _power_hud() -> void:
	var rows: Array[Dictionary] = []
	for id: String in [SpecialPowers.SPEED, SpecialPowers.FREEZE, ""]:
		var world: ClockWorld = _world()
		world.powers = SpecialPowers.initial(BINDING,id)
		if not id.is_empty():
			world.powers = SpecialPowers.accept(world.powers,SpecialPowers.request(world.powers),1.0)
		world.elapsed = 2.0
		var panel: PowerSlotPanel = PowerSlotPanel.new()
		world.add_child(panel)
		world._present_power_slot(panel,0)
		_check(not world.powers.has("loadout") and panel.activation_button.tooltip_text.contains("3 或点击立即释放。"), "legacy V1 field HUD renders without progression loadout")
		if id.is_empty():
			_check(panel.activation_button.text == "3  空槽" and panel.activation_button.disabled and not panel.duration_bar.visible, "legacy empty slot keeps its disabled HUD")
		else:
			var duration: float = SpecialPowers.duration(id,false)
			_check(panel.duration_bar.visible and _near(panel.duration_bar.value,(duration-1.0)/duration) and panel.activation_button.disabled, "legacy accepted power retains original independent duration bar")
		rows.append({"scope":"LEGACY_V1_HUD","id":id,"tooltip":panel.activation_button.tooltip_text,"bar":panel.duration_bar.value})
		world.free()
	var legacy_panel: PowerSlotPanel = PowerSlotPanel.new()
	root.add_child(legacy_panel)
	legacy_panel.present("急救广播","就绪",0.0,0.0,true,SpecialPowers.RADIO)
	_check(legacy_panel.activation_button.tooltip_text.contains("最多 24 HP"), "six-argument broadcast HUD keeps the legacy twenty-four HP default")
	legacy_panel.free()
	for upgraded: bool in [false,true]:
		var world: ClockWorld = _world()
		_equip_power(world,SpecialPowers.RADIO,upgraded)
		world.basic_support.configure(BINDING,false,true)
		var panel: PowerSlotPanel = PowerSlotPanel.new()
		world.add_child(panel)
		world._present_power_slot(panel,0)
		var amount: float = SpecialPowers.radio_amount(world.powers.loadout)
		_check(panel.activation_button.tooltip_text.contains("最多 %s HP" % String.num(amount, 0)) and not panel.activation_button.disabled, "field broadcast HUD reports the actual frozen base or upgraded healing cap")
		_check(not panel.duration_bar.visible and panel.activation_button.tooltip_text.contains("没有合格目标时保留次数"), "instant broadcast HUD preserves its no-target rule without a duration bar")
		rows.append({"scope":"M48_FROZEN_HUD","upgraded":upgraded,"radio_amount":amount,"tooltip":panel.activation_button.tooltip_text})
		world.free()
	observations.power_hud = rows

func _near(value: float, expected: float, tolerance: float = 0.000001) -> bool:
	return absf(value-expected) <= tolerance

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("M48_RUNTIME_EFFECTS_FAIL " + message)
