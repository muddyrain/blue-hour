extends "res://tests/campaign_flow.gd"
## Controlled fault/damage/geometry boundaries in a fresh authenticated synthetic action.
## HP/death/rewards still use the original owners; this is not a natural whole-journey proof.
class NoPath extends FieldNavigation:
	func path_between(_start: Vector2, _goal: Vector2) -> PackedVector2Array:
		return PackedVector2Array()

class RejectSecond extends TraitInputs:
	var calls: int=0
	func accept_search(world: Expedition, actor: FieldActor, kind: StringName, site_id: StringName=&"") -> bool:
		calls+=1
		if calls==2:
			return false
		return super.accept_search(world,actor,kind,site_id)

func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _tap(app.camp_scene.hotspots[&"bus"])
	var slot: int=-1
	var wanted: String="rescue" if output.get_file()=="rescue" else "supply" if output.get_file()=="indoor" else "airdrop"
	for i: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[i].type==wanted:
			slot=i
	_check(slot>=0,"original frozen daily offers include required "+wanted)
	if slot<0:
		_write("offers.json",{"offers":app.mission_select.daily_offers})
		return
	var w: Expedition=await _start(slot)
	if w==null:
		return
	if wanted=="rescue":
		w.rescue_target.request()
		var worker: int=w.rescue_target.worker
		_check(worker>0,"original rescue owns a live participant")
		w.request_search(w.sites[0].id)
		_check(w.rescue_target.worker==worker and w.rescue_target.status=="IN_PROGRESS" and not w.has_search_job(worker) and w.search_assignments.ordered().size()==1,"new house never steals or cancels rescue worker")
		w.request_search(w.sites[1].id)
		_check(w.rescue_target.worker==worker and w.search_assignments.ordered().size()==1,"rescue plus one building exhaust two people without preemption")
		return
	var indoor: Array[Expedition.SearchSite]=[]
	var outdoor: Expedition.SearchSite
	for site: Expedition.SearchSite in w.sites:
		if TaskActions.outdoor_site(w.supply.generated,site.id):
			outdoor=site
		else:
			indoor.append(site)
	if wanted=="airdrop":
		_check(outdoor!=null and not indoor.is_empty(),"original airdrop has outdoor and indoor work sources")
		if outdoor!=null and not indoor.is_empty():
			await outdoor_boundary(w,indoor[0],outdoor)
		return
	_check(indoor.size()>=2,"original supply has independent indoor jobs")
	if indoor.size()<2:
		return
	# Choose unlike indoor categories so the second real trait acknowledgement can fail.
	var a: Expedition.SearchSite=indoor[0]
	var b: Expedition.SearchSite=indoor[1]
	for site: Expedition.SearchSite in indoor:
		if site.kind!=a.kind:
			b=site
	var remaining: Expedition.SearchSite
	for site: Expedition.SearchSite in indoor:
		if site!=a and site!=b:
			remaining=site
	var navigation: FieldNavigation=w.navigation
	w.navigation=NoPath.new()
	w.request_search(a.id)
	_check(w.search_assignments.ordered().is_empty() and "无法到达" in w._notice_text,"unreachable candidates leave all tasks unchanged")
	w.navigation=navigation
	var actor: FieldActor=w.survivors[0]
	_check(actor.take_damage(6.0),"controlled nonfatal damage passes original authenticated damage gate")
	actor.position=a.door
	w.request_search(a.id)
	_check(w.search_assignments.member_for(String(a.id))==actor.member_id,"already-at-door path is reachable, not an unavailable member")
	w.request_search(b.id)
	await _until(w,func()->bool:return a.progress>1.0 and b.progress>0.0)
	_check(w.survivors.all(func(member: FieldActor)->bool:return not member.visible and member.activity==FieldActor.Activity.SEARCHING),"two real indoor tasks retain hiding/protection")
	var before: Dictionary=w.support_world()
	_check(w.request_heal(),"original heal accepts while both members are actually working")
	var after: Dictionary=w.support_world()
	_check(TransactionReceipt.same(before.jobs,after.jobs) and TransactionReceipt.same(before.sites,after.sites) and w.survivors.all(func(member:FieldActor)->bool:return not member.visible),"working heal rebuild preserves both jobs/progress and indoor protection")
	var fault: RejectSecond=RejectSecond.new()
	fault.restore(w.trait_inputs.snapshot(w));w.trait_inputs=fault
	await _until(w,func()->bool:return w.elapsed>=21.1)
	# Explicit completion-boundary fixture; no inventory, identity or HP assignment.
	a.progress=w._site_seconds(a)-0.01;b.progress=w._site_seconds(b)-0.01
	var loot: int=w.loot
	var food: int=w.food_loot
	w.step(0.02)
	_check(w.is_paused and w.search_assignments.ordered().size()==1 and int(a.searched)+int(b.searched)==1,"stable same-frame completion stops at second rejected acknowledgement")
	var confirmed_loot: int=w.loot
	var confirmed_food: int=w.food_loot
	var failed: Expedition.SearchSite=b if not b.searched else a
	_check(failed.progress<w._site_seconds(failed) and app.progress_session.preview_suspend(w.support_world()).error==OK,"only unconfirmed progress rolls back; paused world remains strictly saveable")
	w.toggle_pause();w.step(0.02)
	_check(a.searched and b.searched and w.search_assignments.ordered().is_empty(),"retry completes only the remaining job")
	var paid_loot: int=w.loot
	var paid_food: int=w.food_loot
	w.step(0.02)
	_check(w.loot==paid_loot and w.food_loot==paid_food and (confirmed_loot>loot or confirmed_food>food),"confirmed first reward and retried second never replay")
	_write("boundary.json",{"support":w.basic_support.snapshot(),"sites":WorldSites.facts(w),"fault_calls":fault.calls})

func outdoor_boundary(w: Expedition, remaining: Expedition.SearchSite, outdoor: Expedition.SearchSite) -> void:
	w.request_search(remaining.id);w.request_search(outdoor.id)
	await _until(w,func()->bool:return outdoor.progress>0.0 and remaining.progress>0.0)
	var target: FieldActor=w.search_member(w.search_assignments.member_for(String(outdoor.id)))
	_check(target!=null and target.visible and target.activity==FieldActor.Activity.RECOVERING,"real outdoor recovery remains visible and targetable")
	var hp: float=target.health
	_check(target.take_damage(6.0) and target.health==hp-6.0,"outdoor work accepts original real damage")
	var other: float=remaining.progress
	_check(target.take_damage(target.health) and target.permanent_death,"original PersistedDamageGate confirms permanent death of outdoor worker")
	w.step(0.01)
	_check(outdoor.progress==0.0 and not outdoor.searched and w.search_assignments.ordered().size()==1 and remaining.progress>other,"death resets/releases only its own unfinished work")
	_check(app.progress_session.preview_suspend(w.support_world()).error==OK,"death plus surviving hidden work remains strictly authenticatable")
	_write("boundary.json",{"support":w.basic_support.snapshot(),"jobs":w.search_assignments.snapshot(),"sites":WorldSites.facts(w),"receipt":app.progress_session._transaction.recover().receipt})
