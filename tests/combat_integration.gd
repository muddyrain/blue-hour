extends SceneTree
## Controlled geometry/commit fixture. This does not claim normal acquisition or persistent journey evidence.
var checks: int=0
var failures: int=0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
 checks+=1
 if not value: failures+=1;printerr("COMBAT_INTEGRATION_FAIL "+label)
func actor(id: int,point: Vector2,enemy: bool=false) -> FieldActor:
 var a: FieldActor=FieldActor.new()
 a.actor_id=id;a.member_id=0 if enemy else id;a.is_enemy=enemy;a.position=point
 a.health=54.0 if enemy else 200.0;a.max_health=a.health
 root.add_child(a)
 return a
func weapon(a: FieldActor,id: String) -> void:
 a.weapon_instance_id="controlled:"+id
 a.weapon_definition=CombatEquipment.definition(id).duplicate() as WeaponDefinition
 a.visual.set_weapon(a.weapon_definition.presentation)
 a.magazine=null if id=="fire_axe_v1" else WeaponMagazine.new(a.weapon_instance_id,id)
 a.cooldown=0.0
func run() -> void:
 if not OS.get_user_data_dir().replace("\\","/").begins_with(ProjectSettings.globalize_path("res://.local/")): quit(2);return
 check(CombatRuntime.problem({"version":1,"actions":{},"toxic":ToxicV1.initial(),"spawns":{}},{"survivors":[],"enemies":[{"behavior":1}]},{"base":{"journey":{"build":{"combat_version":1}}}})=="COMBAT_ENEMY_FIELDS","malformed enemy behavior returns error before method dispatch")
 for id:String in ["fire_axe_v1","shotgun_v1"]:
  check(WeaponState.problem({"schema_version":110,"journey":{"format":WeaponState.FORMAT},"weapons":[{"weapon_id":id,"drop":"bad"}]} )=="COMBAT_WEAPON_SOURCE","malformed new drop rejects before field dispatch "+id)
  check(not WeaponInventory.validate({"schema_version":5,"weapons":[{"instance_id":"fixture:starter:2","weapon_id":id,"condition":"ready","origin":"initial","acquired_sortie":""}],"loadout":[],"camp_spending":0}).is_empty(),"legacy starter authentication never accepts new weapon "+id)
 var w: Expedition=Expedition.new()
 w.supply=MissionSupply.new();w.supply.generated={"version":8,"build":{"slots":["",""]}}
 w._effects=Node2D.new();root.add_child(w._effects)
 var a: FieldActor=actor(1,Vector2(400,400))
 w.survivors=[a]
 w.growth_inputs.configure([{"id":1}]);w.xp_inputs.configure({"transaction_id":"controlled:1"})
 weapon(a,"fire_axe_v1")
 for i: int in range(3):w.enemies.append(actor(i,Vector2(430+i*3,394+i*6),true))
 w.combat.attack(w,a,0.0)
 check(w.combat.action(a).remaining==0.18 and a.magazine==null,"axe locks real windup with no magazine")
 w.combat.attack(w,a,0.18)
 check(w.enemies.all(func(e:FieldActor)->bool:return e.health==20.0),"one actual swing damages three targets exactly once")
 w.combat.attack(w,a,0.0)
 check(w.enemies.all(func(e:FieldActor)->bool:return e.health==20.0),"recovery cannot hit again")
 a.cooldown=0;w.elapsed=1.0
 w.combat.attack(w,a,0.0);w.combat.attack(w,a,0.18)
 check(w.kills==3 and a.confirmed_kills==3 and w.xp_inputs.events.size()==3,"three actual axe fatalities yield one receipt/XP each")
 for e:FieldActor in w.enemies:e.free()
 w.enemies.clear()
 weapon(a,"shotgun_v1")
 var target:FieldActor=actor(4,Vector2(455,400),true);w.enemies.append(target)
 w.combat.attack(w,a,0.0)
 check(a.magazine.rounds==3 and target.health==9.0,"five actual pellets aggregate45 and consume one shell")
 a.cooldown=0;w.elapsed=2.0;w.combat.attack(w,a,0.0)
 check(a.magazine.rounds==2 and w.xp_inputs.events.size()==4 and a.confirmed_kills==4,"aggregate fatality gives one XP event with actual instance")
 var saved:Dictionary=a.magazine.snapshot()
 a.magazine=WeaponMagazine.new(a.weapon_instance_id,"shotgun_v1");a.magazine.restore(saved)
 check(a.magazine.rounds==2,"partial shell count restores without refill")
 target.free();w.enemies.clear()
 var caster:FieldActor=actor(5,Vector2(450,400),true)
 caster.enemy_behavior=EnemyBehavior.new();caster.enemy_behavior.kind=CombatEnemyRules.TOXIC
 w.enemies.append(caster)
 var b:FieldActor=actor(2,Vector2(405,400));w.survivors.append(b)
 w.combat.setup(w)
 var release:Dictionary=ToxicV1.plan(ToxicV1.initial(),0.0,w.combat.rows(w.enemies),w.combat.rows(w.survivors),w.shot_obstacles)
 w.combat.toxic=ToxicV1.plan(release.state,0.9,w.combat.rows(w.enemies),w.combat.rows(w.survivors),w.shot_obstacles).state
 check(w.combat.toxic.zones.size()==1 and a.health==200.0,"actual poison release has no birth damage")
 b.damage_gate=func(_actor:FieldActor,_proposal:Dictionary)->Error:return ERR_CANT_CREATE
 # Avoid UI access in this explicitly controlled fixture; gate failure is observed directly.
 var planned:Dictionary=ToxicV1.plan(w.combat.toxic,0.75,w.combat.rows(w.enemies),w.combat.rows(w.survivors),w.shot_obstacles)
 w.combat.toxic=planned.state
 check(planned.hits.size()==2,"one actual zone tick freezes both targets")
 check(a.take_damage(6.0),"first target actual damage commits")
 w.combat.toxic=ToxicV1.ack(w.combat.toxic,planned.hits[0])
 check(not b.take_damage(6.0) and b.health==200.0,"second original actor damage gate rejects without HP mutation")
 var partial:Dictionary=w.combat.snapshot()
 var recovered:CombatRuntime=CombatRuntime.new();recovered.restore(partial)
 var retry:Dictionary=ToxicV1.plan(recovered.toxic,30.0,[],[],[])
 check(retry.hits.size()==1 and retry.hits[0].member_id==2 and recovered.toxic.pending.cursor==1,"restored partial commit retries only remaining original target without clocks")
 b.damage_gate=Callable()
 check(b.take_damage(6.0),"retry accepted through same actor API")
 recovered.toxic=ToxicV1.ack(recovered.toxic,retry.hits[0])
 check(a.health==194.0 and b.health==194.0 and recovered.toxic.pending.is_empty(),"retry neither repeats prior target nor loses pending acknowledgement")
 for gun:String in ["fire_axe_v1","shotgun_v1"]:
  for item:String in BuildItems.ids():
   weapon(a,gun)
   var instance:Dictionary=WeaponModifiers.baseline({"weapon_id":gun})
   instance.weapon_level=2;instance.quality="rare";instance.affixes=["quick_v1"]
   a.weapon_definition=WeaponModifiers.combat_definition(instance)
   w.supply.generated.build.slots=[item,""]
   var base:float=a.weapon_definition.damage
   w.apply_build(a)
   check(a.weapon_definition.damage==base*(1.0 if gun=="fire_axe_v1" else BuildItems.factors([item,""]).damage),"passive exact dispatch "+gun+item)
 check(WeaponMagazine.problem(saved,"controlled:shotgun_v1","shotgun_v1").is_empty(),"new shotgun magazine has strict original shape")
 # R1 representative: actual actor death plus the same support capture cleanup.
 # This controlled component does not claim an authenticated persistent journey.
 weapon(a,"fire_axe_v1")
 caster.position=a.position+Vector2(30,0)
 w.combat.attack(w,a,0.0)
 var sequence:int=w.combat.action(a).sequence
 var xp_count:int=w.xp_inputs.events.size()
 check(w.combat.action(a).remaining>0 and a.take_damage(a.health),"real actor damage interrupts an unfinished axe windup")
 w.support_world()
 check(w.combat.action(a).remaining==0 and w.combat.action(a).sequence==sequence and w.xp_inputs.events.size()==xp_count,"support capture cancels dead axe without replay or sequence change")
 var camera:FieldCamera=FieldCamera.new();root.add_child(camera)
 camera.zoom_at(Vector2(640,360),0.01)
 check(camera.zoom.x>=0.7,"R1 minimum float32 zoom remains inside strict snapshot bound")
 camera.free()
 for member:FieldActor in w.survivors:member.free()
 for enemy:FieldActor in w.enemies:enemy.free()
 w._effects.free();w.free()
 print("COMBAT_INTEGRATION checks=%d failures=%d"%[checks,failures])
 quit(1 if failures else 0)
