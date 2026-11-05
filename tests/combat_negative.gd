extends "res://tests/combat_flow.gd"
## Controlled negative: actual restored zone/source and original death owner; ordinary AI is not stepped during poison-only fatality isolation.
func _resume() -> void:
 await _tap(app._continue_button)
 if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
 var w:Expedition=app.expedition
 _check(w!=null,"negative uses real authenticated combat checkpoint")
 if w==null:return
 w.set_physics_process(false);w.set_process(false)
 if app.pause_menu.visible:await _tap(app.pause_menu.buttons[0])
 if w.is_paused:w.toggle_pause()
 var caster:FieldActor=null
 for enemy:FieldActor in w.enemies:
  if enemy.enemy_behavior.kind==CombatEnemyRules.TOXIC:caster=enemy
 _check(caster!=null,"negative retained actual living natural toxic source")
 if caster==null:return
 var point:Vector2=SortieSnapshot._vec(w.combat.toxic.zones[0].point)
 w.command_move(point)
 for i:int in range(300):
  w.step(1.0/30.0)
  if w.combat.toxic.zones.any(func(z:Dictionary)->bool:return w.survivors.all(func(a:FieldActor)->bool:return a.position.distance_to(SortieSnapshot._vec(z.point))<=60.0)):break
  if i%30==0:await _frame()
 var b:FieldActor=w.survivors[1]
 var original:Callable=b.damage_gate
 var failure:Dictionary={"once":true}
 b.damage_gate=func(a:FieldActor,p:Dictionary)->Error:
  if failure.once:failure.once=false;return ERR_CANT_CREATE
  return original.call(a,p) as Error
 # This loop isolates the actual zone clock; it never assigns HP, death, inventory or outcome.
 var partial:bool=false
 for i:int in range(300):
  w.elapsed+=0.05;w.basic_support.advance(0.05,true);w.combat.advance_toxic(w,0.05)
  if w.is_paused:partial=true;break
 _check(partial and not w.combat.toxic.pending.is_empty(),"necessary damage rejection pauses with fixed pending facts")
 if not partial:return
 var hp:float=w.survivors[0].health
 var second:float=b.health
 w.toggle_pause();w.step(0.0)
 _check(w.survivors[0].health==hp and b.health==second-6.0 and w.combat.toxic.pending.is_empty(),"retry only remaining target once without first-target replay")
 b.damage_gate=original
 var death_failure:Dictionary={"used":false}
 app.progress_session.fault_hook=func(p:String)->Error:
  if p=="after_record_flush" and not death_failure.used:death_failure.used=true;return ERR_CANT_CREATE
  return OK
 var retries:int=0
 for i:int in range(4000):
  if w.living_count()==0:break
  if w.is_paused:
   app.progress_session.fault_hook=Callable();w.toggle_pause();retries+=1
   w.combat.advance_toxic(w,0.0)
   continue
  w.elapsed+=0.05;w.basic_support.advance(0.05,true);w.combat.advance_toxic(w,0.05)
  if i%100==0:await _frame()
 _check(w.living_count()==0 and w.survivors.all(func(a:FieldActor)->bool:return a.permanent_death),"actual toxic ticks commit permanent deaths through original gate")
 _check(death_failure.used and retries>0,"actual lethal publication failure preserves and retries original damage")
 app.progress_session.fault_hook=Callable()
 w.step(0.0)
 _check(app.phase==app.Phase.RESULT and not app._progress_blocked,"original automatic all-dead failure settles once")
 _check(app.camp_snapshot().journey.campaign.outcome=="DEFEAT","original journey owner persists defeat")
 _write("negative-state.json",{"death_failure":death_failure,"retries":retries,"camp":app.camp_snapshot(),"events":events})
