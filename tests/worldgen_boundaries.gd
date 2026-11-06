extends "res://tests/exploration_boundaries.gd"
## Controlled work/damage boundaries against the actual new layout; no earned journey claim.
func _context() -> Dictionary:
	var value: Dictionary=super._context()
	value.journey.build=WorldgenState.initial_build(value.journey.seed)
	return RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(value))).payload

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2);return
	var context: Dictionary=_context()
	expect(TransactionReceipt.camp_problem(context).is_empty(),"strict decoded build6 controlled context")
	var task: Dictionary=_task(context)
	expect(not task.is_empty() and task.layout.version==5 and DailyActions.problem(task).is_empty(),"actual new geometry and frozen sites authenticate")
	if not task.is_empty():
		_work(context,task,true)
		_work(context,task,false)
		_cancel_and_death(context,task)
		_failure_report(context,task)
		_trait_bounds(context,task)
	print(JSON.stringify({"suite":"worldgen_boundaries","checks":checks,"failures":failures,"scope":"CONTROLLED_NEW_LAYOUT_WORK_OUTDOOR_DAMAGE_CANCEL_AND_IDENTITY","observations":observations}))
	quit(0 if failures==0 else 1)
