extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,720)
	var hud: C1ExpeditionHud = ExpeditionHud.HudScene.instantiate() as C1ExpeditionHud
	root.add_child(hud)
	var rows: Array = []
	var failures: int = 0
	for count: int in [2,3,4]:
		var members: Array = []
		for i: int in range(count): members.append({"id":i+1,"call_sign":"夏之遥","label":"夏之遥 · 搜集中","hp":205,"max_hp":210,"level":3,"status":"搜集中"})
		hud.refresh({"mission_title":"青禾市场环路","day_text":"第 3 天","currency_text":"57","currency_delta_text":"+4 携带 · 食物2（携带+3）· 武器+1","survivors":members})
		for tick: int in range(5): await process_frame
		var lines: Array = []
		for member: Dictionary in hud._members:
			if member.box.visible: lines.append(member.health.get_line_count())
		var height: float = hud.get_node("MissionPanel").size.y
		var ok: bool = height<=144 and hud._members.all(func(v: Dictionary) -> bool:return not v.box.visible or (v.title.get_line_count()==1 and v.status.get_line_count()==1)) and lines.all(func(n: int) -> bool: return n==1)
		rows.append({"count":count,"height":height,"health_lines":lines,"pass":ok})
		if not ok: failures+=1
	print("HUD_PROBE "+JSON.stringify({"rows":rows,"failures":failures}))
	hud.queue_free()
	await process_frame
	quit(1 if failures else 0)
