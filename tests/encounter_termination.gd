extends SceneTree
## Owner-seam fixture, not a journey/win proof. Real requests, damage and fatal-shot/XP owners.
class ComponentWorld extends Expedition:
	func _ready() -> void: pass
	func _shot_effect(_from:Vector2,_to:Vector2,_damage:float) -> void: pass
	func _hit_effect(_to:Vector2,_damage:float,_survivor_hit:bool) -> void: pass

var checks:int=0
var failures:int=0
var results:Array[Dictionary]=[]

func _initialize() -> void:call_deferred("run")

func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("ENCOUNTER_TERMINATION_FAIL "+label)

func run() -> void:
	assert("/.local/" in OS.get_user_data_dir().replace("\\","/"))
	for mode:String in ["zero","partial","retry","freeze"]:await scenario(mode)
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--termination-output="):
			var path:String=arg.trim_prefix("--termination-output=")
			assert(path.is_absolute_path() and "/.local/" in path)
			FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":results},"\t"))
	print("ENCOUNTER_TERMINATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func scenario(mode:String) -> void:
	var world:ComponentWorld=ComponentWorld.new()
	world.set_process(false);world.set_physics_process(false);root.add_child(world)
	world._effects=Node2D.new();world.add_child(world._effects)
	world.growth_mode=true
	var camp:Dictionary={"profile_id":"0123456789abcdef0123456789abcdef","crew":SurvivorRoster.new_crew()}
	WeaponInventory.initialize(camp,"initial")
	world.loadout_snapshot=WeaponInventory.snapshot(camp)
	world.sortie_id=camp.profile_id+":1"
	world.growth_inputs.configure(camp.crew)
	world.xp_inputs.configure({"transaction_id":world.sortie_id})
	for index:int in range(2):
		var member:FieldActor=FieldActor.new()
		member.actor_id=index;member.member_id=index+1
		member.position=Vector2(index*20,100)
		member.weapon_definition=WeaponInventory.Definitions[index]
		member.weapon_instance_id=world.loadout_snapshot[index].instance.instance_id
		world.add_child(member);member.visual.set_weapon(member.weapon_definition.presentation)
		member.magazine=WeaponMagazine.new(member.weapon_instance_id,String(member.weapon_definition.id))
		world.survivors.append(member)
	var boss:FieldActor=FieldActor.new()
	boss.is_enemy=true;boss.actor_id=0;boss.position=Vector2(100,100)
	boss.max_health=BossDefinition.POLICY.health;boss.health=boss.max_health
	world.add_child(boss);world.enemies.append(boss);world._spawn_count=1
	var runtime:EncounterRuntime=EncounterRuntime.new()
	runtime.world=world;runtime.actor=boss
	runtime.definition={"boss_id":world.sortie_id+":breacher"}
	runtime.behavior.configure(runtime.definition.boss_id);world.encounter=runtime
	var reject_id:int=1 if mode=="zero" else 2
	var fault:Dictionary={"fired":false}
	for member:FieldActor in world.survivors:
		member.damage_gate=func(target:FieldActor,_proposal:Dictionary)->Error:
			if target.member_id==reject_id and not fault.fired:
				fault.fired=true;return ERR_CANT_OPEN
			return OK
	runtime.advance(0.0);runtime.advance(BossDefinition.POLICY.slam_windup)
	check(fault.fired and world.is_paused,"actual request pauses at rejected damage: "+mode)
	check(runtime.handling.get("hits",[]).size()==(0 if mode=="zero" else 1),"partial handling records only applied damage: "+mode)
	var before:Dictionary=runtime.snapshot()
	var health_before:Array=world.survivors.map(func(member:FieldActor)->float:return member.health)
	world.toggle_pause()
	if mode=="freeze":
		world.power_frozen=true
		runtime.advance(3.0)
		check(TransactionReceipt.same(before,runtime.snapshot()),"frozen live boss retains original pending/windup/handling without applying damage")
	if mode=="retry":
		runtime.advance(0.0);runtime.advance(0.0)
		check(world.survivors.all(func(member:FieldActor)->bool:return member.health==200.0-BossDefinition.POLICY.slam_damage),"live retry hits each target exactly once")
		check(runtime.handling.is_empty() and runtime.behavior.snapshot().pending.is_empty(),"live retry acknowledges original request")
	else:
		# Same call order as Expedition.step: accepted legal shots before encounter.advance.
		for tick:int in range(100):
			if boss.health<=0:break
			world.elapsed+=1.0
			for member:FieldActor in world.survivors:
				member.advance(1.0,false,false);member.magazine.advance(1.0)
			world._update_combat()
			if mode=="freeze" and boss.health>0:
				var action_before:Dictionary=runtime.behavior.snapshot()
				runtime.observe_frozen_health()
				var observed:Dictionary=runtime.behavior.snapshot()
				check(observed.remaining==action_before.remaining and observed.melee_cooldown==action_before.melee_cooldown and observed.slam_cooldown==action_before.slam_cooldown and observed.state==action_before.state,"nonlethal frozen boss damage records health without advancing actions")
				check(EncounterRuntime.facts_problem(runtime.snapshot(),{"encounter":runtime.definition},world.xp_inputs.snapshot(world)).is_empty(),"nonlethal frozen boss remains strictly authenticatable before thaw/death")
		check(boss.health==0 and not runtime.defeat.is_empty(),"original shots and XP owner confirm real defeat: "+mode)
		check(runtime.behavior.snapshot().pending.is_empty(),"death terminates pending requests: "+mode)
		check(runtime.handling.is_empty(),"death terminates handling alongside pending: "+mode)
		var issue:String=EncounterRuntime.facts_problem(runtime.snapshot(),{"encounter":runtime.definition},world.xp_inputs.snapshot(world))
		check(issue.is_empty(),"terminated encounter stays authentic: "+mode+" "+issue)
		var stale:Dictionary=runtime.snapshot();stale.handling=before.handling.duplicate(true)
		check(EncounterRuntime.facts_problem(stale,{"encounter":runtime.definition},world.xp_inputs.snapshot(world))=="ENCOUNTER_HANDLING_SOURCE","inconsistent terminal handling is still rejected: "+mode)
		runtime.advance(1.0)
		check(world.survivors.map(func(member:FieldActor)->float:return member.health)==health_before,"death cancels only unapplied damage: "+mode)
		check(world.xp_inputs.events.size()==1 and world.kills==1,"one original defeat and XP input: "+mode)
	results.append({"mode":mode,"before":before,"after":runtime.snapshot(),"health":world.survivors.map(func(member:FieldActor)->float:return member.health),"xp":world.xp_inputs.events})
	world.queue_free();await process_frame
