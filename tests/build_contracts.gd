extends SceneTree
## Pure parameter boundaries complement the real no-state-injection journey.
var checks: int=0
var failures: int=0
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1;printerr("BUILD_CONTRACT_FAIL "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for gun: String in ["carbine","long_rifle"]:
		for item: String in BuildItems.ids():
			var actor: FieldActor=FieldActor.new()
			actor.weapon_instance_id="fixture:"+gun
			var instance: Dictionary=WeaponModifiers.baseline({"weapon_id":gun})
			instance.weapon_level=2;instance.quality="rare";instance.affixes=["quick_v1"]
			actor.weapon_definition=WeaponModifiers.combat_definition(instance)
			actor.magazine=WeaponMagazine.new(actor.weapon_instance_id,gun)
			actor.speed=125.0*1.12
			var old: Dictionary=WeaponModifiers.effective(instance)
			var world: Expedition=Expedition.new()
			world.supply=MissionSupply.new()
			world.supply.generated={"version":7,"build":{"slots":[item,""]}}
			world.apply_build(actor)
			var factors: Dictionary=BuildItems.factors([item,""])
			check(actor.weapon_definition.damage==old.damage*factors.damage,"original quality/level then passive direct damage once "+gun+item)
			check(actor.weapon_definition.interval==old.interval,"quick loader does not change shooting interval")
			check(actor.magazine.seconds()==WeaponMagazine.PARAMETERS[gun].seconds*factors.reload,"reload policy and runtime same factor")
			check(actor.speed==125.0*1.12*factors.move,"trait then passive speed order exact")
			check(BasicSupport.POLICY.airstrike_damage==72.0,"pressure rounds never amplify airstrike")
			actor.free();world.free()
	var support: BasicSupport=BasicSupport.new();support.configure({"transaction_id":"fixture:1"})
	var members: Array[Dictionary]=[{"member_id":1,"health":20.0,"max_health":200.0,"present":true}]
	check(support.plan_heal(members,BuildItems.factors(["medical_pack_v1",""]).heal).amount==60.0,"medical pack actual heal planner cap60")
	check(BasicSupport.POLICY.airstrike_radius*BuildItems.factors(["wide_blast_v1",""]).blast==117.0,"blast planner radius117")
	check(not BuildAuthority.ability_problem({"kind":"defeat","source":"ability","ability_id":"airstrike_v1","request_id":"fixture:1:basic:0","enemy_id":0,"at_ms":0,"junk":1},"fixture:1").is_empty(),"missing ability caller rejected")
	print("BUILD_CONTRACTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
