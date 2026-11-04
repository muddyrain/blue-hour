extends SceneTree
## Only the 111 validation context may authorize the new map namespace.
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var failures: int=0
	var checks: int=0
	var context: Dictionary={"profile_id":"a".repeat(32),"settled_sorties":1,"day":3,"weapons":[]}
	var crew: Array[Dictionary]=SurvivorRoster.new_crew()
	SurvivorGrowth.initialize(crew)
	var member: Dictionary=crew[0]
	member.service.sorties=1;member.service.last_settlement_id=context.profile_id+":1"
	member.growth.last_action={"settlement_id":context.profile_id+":1","map_id":"market_loop","duration_ms":0,"total":0,"recent":[],"evacuated":true}
	for schema: int in range(104,111):
		context.schema_version=schema
		member.growth.last_action.map_id="market_loop"
		var control: bool=SurvivorGrowth._validate_legacy_member(member,context).is_empty()
		member.growth.last_action.map_id="rogue_v1_"+"a".repeat(32)
		var rejected: bool=not SurvivorGrowth._validate_legacy_member(member,context).is_empty()
		checks+=2
		if not control or not rejected:failures+=1
		print("ROGUE_LEGACY_SCOPE schema=",schema," fixed_control=",control," generated_rejected=",rejected)
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--scope-old-camp="):continue
		var path: String=argument.trim_prefix("--scope-old-camp=")
		assert(path.is_absolute_path() and "/.local/" in path)
		var old: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path)).camp
		old.schema_version=WeaponState.SCHEMA;old.journey.format=WeaponState.FORMAT
		for schema: int in [110,109]:
			if schema==109:old=WeaponState.projected(old)
			var control: bool=TransactionReceipt.camp_problem(old).is_empty()
			var changed: Dictionary=old.duplicate(true)
			changed.crew[0].growth.last_action.map_id="rogue_v1_"+"a".repeat(32)
			var rejected: bool=not TransactionReceipt.camp_problem(changed).is_empty()
			checks+=2
			if not control or not rejected:failures+=1
			print("ROGUE_LEGACY_ROOT schema=",schema," fixed_control=",control," generated_rejected=",rejected)
	print("ROGUE_LEGACY_SCOPE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
