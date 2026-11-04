extends SceneTree
## Fixed seeds, actual conservative navigation and version/binding negatives.
var checks: int=0
var failures: int=0
var output: String=""
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-data-output="):output=arg.trim_prefix("--rogue-data-output=")
	call_deferred("run")
func expect(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("ROGUE_DATA_FAIL "+label)
func model(seed_value: String) -> Dictionary:
	return {"schema_version":111,"journey":{"seed":seed_value.md5_text()},"day":2,"settled_sorties":0,"profile_id":"a".repeat(32),"crew":[{"id":1,"health":200},{"id":2,"health":200}],"food":2,"cash":53}
func run() -> void:
	var rows: Array[Dictionary]=[]
	var geometries: Dictionary={"straight":{},"fork":{},"ring":{}}
	var footprints: Dictionary={"straight":{},"fork":{},"ring":{}}
	var fallback_count: int=0
	for index: int in range(100):
		var base: Dictionary=model("fixed-seed-%03d"%index)
		var offers: Array[Dictionary]=RogueActions.offers(base)
		expect(offers.size()==3,"three per day")
		var kinds: Dictionary={}
		var food: bool=false
		for item: Dictionary in offers:
			var issue: String=RogueActions.problem(item)
			expect(issue.is_empty(),"canonical data/navigation "+str(index)+": "+issue)
			expect(RogueActions.matches(base,item),"current camp candidate binding")
			kinds[item.type]=true;food=food or item.food>0
			var geometry: String=RogueLayout.geometry_hash(item.layout)
			geometries[item.layout.bone][geometry]=true
			footprints[item.layout.bone][RogueLayout.footprint_hash(item.layout)]=true
			fallback_count+=int(item.layout.fallback)
			rows.append({"seed":base.journey.seed,"day":base.day,"task_id":item.id,"type":item.type,"generator":item.layout.version,"bone":item.layout.bone,"geometry":geometry,"footprint":RogueLayout.footprint_hash(item.layout),"fallback":item.layout.fallback,"attempt":item.layout.attempt,"cash":item.cash,"food":item.food,"weapons":item.weapons,"layout":item.layout})
			var wrong: Dictionary=item.duplicate(true);wrong.cash+=1
			expect(not RogueActions.problem(wrong).is_empty(),"altered reward rejected")
			wrong=item.duplicate(true);wrong.layout.entities[0].rect[0]+=16
			expect(not RogueActions.problem(wrong).is_empty(),"altered geometry rejected")
			wrong=item.duplicate(true);wrong.version=77
			expect(not RogueActions.problem(wrong).is_empty(),"unknown task version rejected")
			wrong=item.duplicate(true);wrong.layout.resource_path="res://arbitrary.tscn"
			expect(not RogueActions.problem(wrong).is_empty(),"resource paths rejected")
		expect(food and kinds.size()>=2,"food option and two types")
		var edited: Dictionary=base.duplicate(true);edited.food=1;edited.cash=3;edited.crew[0].health=150
		expect(TransactionReceipt.same({"v":offers},{"v":RogueActions.offers(edited)}),"camp economy/repair cannot reroll")
		edited=base.duplicate(true);edited.day+=1;edited.settled_sorties+=1
		expect(not TransactionReceipt.same({"v":offers},{"v":RogueActions.offers(edited)}),"next day differs")
		offers[0].cash=999
		expect(RogueActions.offers(base)[0].cash<999,"cached values never leaked as mutable decisions")
	var distinct: Dictionary={}
	var physical: Dictionary={}
	for bone: String in geometries:
		physical[bone]=footprints[bone].size();expect(physical[bone]>1,"physical building/road footprints vary: "+bone)
		distinct[bone]=geometries[bone].size();expect(distinct[bone]>1,"substantive same-bone variants: "+bone)
		var fallback: Dictionary=RogueLayout.generate("force-finite",bone,true)
		expect(fallback.fallback and fallback.fallback_reason.split(";").size()==RogueLayout.MAX_ATTEMPTS and RogueLayout.validate(fallback).is_empty(),"bounded verified fallback: "+bone)
	var full: Dictionary=model("capacity");full.crew.append_array([{"id":3,"health":200},{"id":4,"health":200}])
	var full_offers: Array[Dictionary]=RogueActions.offers(full)
	expect(full_offers.all(func(v: Dictionary) -> bool:return v.type!="rescue"),"ineligible rescue replaced, not disabled dead end")
	seed(5241);var expected: float=randf();seed(5241);RogueActions.offers(model("separate-rng"));expect(randf()==expected,"dedicated random stream preserves global RNG")
	var result: Dictionary={"checks":checks,"failures":failures,"seeds":100,"cases":rows,"distinct_geometry":distinct,"distinct_footprints":physical,"normal_fallback_count":fallback_count}
	if not output.is_empty():
		assert(output.is_absolute_path() and "/.local/" in output and not FileAccess.file_exists(output))
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var file: FileAccess=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"))
	print("ROGUE_DATA "+JSON.stringify({"checks":checks,"failures":failures,"seeds":100,"distinct_geometry":distinct,"distinct_footprints":physical,"fallback_count":fallback_count}))
	quit(1 if failures else 0)
