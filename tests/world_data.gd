extends SceneTree
var checks: int = 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var seen: Dictionary = {}
	for seed: int in range(24):
		for bone: String in WorldLayout.BONES:
			var data: Dictionary = WorldLayout.generate(str(seed),bone)
			var issue: String = WorldLayout.validate(data)
			assert(issue.is_empty(),issue)
			seen[data.id]=true
			for food: int in [0,2,6]:
				var defs: Array = WorldSites.definitions(data,4,food,1)
				assert(defs.size()>=4 and defs.size()<=6)
				var cash_total: int = 0
				var food_total: int = 0
				var weapons: int = 0
				for d: Dictionary in defs:
					if d.kind=="cash": cash_total+=int(d.amount)
					else: food_total+=int(d.amount)
					weapons+=int(d.weapon)
				assert(cash_total==4 and food_total==food and weapons==1)
				checks+=1
	print("WORLD_DATA_PASS checks=",checks," distinct=",seen.size())
	quit()
