class_name AppPresentation
extends RefCounted

var app: AppMain


func _init(owner: AppMain) -> void:
	app = owner


func _setup_presentation() -> void:
	app._screen.theme = CampStyle.theme(app._screen.theme)
	app.get_node("Interface/Screen/Result/Scroll/Body").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	app._title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app._camp_backdrop = CampBackdrop.new()
	app._title.add_child(app._camp_backdrop)
	app._title.move_child(app._camp_backdrop, 0)
	app.get_node("Interface/Screen/Rule").hide()
	app.get_node("Interface/Screen/Brand").text = "BLUE HOUR / 救援候选试运行 · PROJECT_TEMP"
	app.get_node("Interface/Screen/Brand").add_theme_font_size_override("font_size", 16)
	CampStyle.place(app.get_node("Interface/Screen/Brand"), Rect2(64,32,600,28))
	app._screen.move_child(app._status, app._screen.get_child_count() - 1)
	app._title.visibility_changed.connect(func() -> void: app._status.visible = app._title.visible and (app._progress_dirty or app._progress_blocked))
	app._status.add_theme_font_size_override("font_size", 16)
	CampStyle.place(app._status, Rect2(64,646,1152,68))
	app._home_button = Button.new()
	app._home_button.text = "开始旅程 →"
	app._home_button.pressed.connect(app._enter_camp)
	app._title.add_child(app._home_button)
	app._home_return = Button.new()
	app._home_return.text = "返回首页"
	app._home_return.pressed.connect(func() -> void:
		app._camp_open = false
		app._refresh_presentation()
		app._request_audio(&"ui_back")
	)
	app._title.add_child(app._home_return)
	app._battle_new_button = Button.new()
	app._battle_new_button.text = "开始新旅程…"
	CampStyle.place(app._battle_new_button,Rect2(480,538,280,56))
	app._battle_new_button.pressed.connect(app._request_battle_new_journey)
	app._result.add_child(app._battle_new_button)
	app._battle_new_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	app._battle_new_button.offset_left = 380
	app._battle_new_button.offset_right = 660
	app._battle_new_button.offset_top = -84
	app._battle_new_button.offset_bottom = -28
	app._battle_new_button.hide()
	app._new_game_confirmation.canceled.connect(func() -> void:
		if app._battle_meta.get("state") == "FAILED":
			app._show_battle_result(app.camp_snapshot(),true))


func _refresh_presentation() -> void:
	if not is_instance_valid(app._home_button):
		return
	if is_instance_valid(app.camp_scene) and app.camp_scene.visible:
		for child: Node in app._title.get_children():
			if child is CanvasItem and child != app.camp_scene:
				child.show()
	var shown: Dictionary = app._pending_save if app._requires_continue else app.camp_snapshot()
	app._camp_backdrop.show_roster(true, [] if app._progress_blocked else shown.get("crew",[]),
		[] if app._progress_blocked else shown.get("journey", {}).get("active_member_ids", []))
	var heading: Label = app.get_node("Interface/Screen/Title/Heading")
	var eyebrow: Label = app.get_node("Interface/Screen/Title/Eyebrow")
	var description: Label = app.get_node("Interface/Screen/Title/Description")
	var camp: Label = app.get_node("Interface/Screen/Title/Camp")
	var start: Button = app.get_node("Interface/Screen/Title/Start")
	var reset: Button = app.get_node("Interface/Screen/Title/Reset")
	var sound: Button = app.get_node("Interface/Screen/Title/Sound")
	var exit: Button = app.get_node("Interface/Screen/Title/Quit")
	heading.text = "蓝时驿站" if app._camp_open else "蓝时归航"
	heading.add_theme_font_size_override("font_size", 48 if app._camp_open else 64)
	eyebrow.text = "归来之后，准备下一次启程。" if app._camp_open else "在天色暗下之前，找到归途。"
	eyebrow.add_theme_font_size_override("font_size", 16)
	description.text = "整备队伍 · 收拢补给 · 穿过旧街" if app._camp_open else "穿过寂静的街口。带上同伴，一起回来。"
	description.add_theme_font_size_override("font_size", 18)
	CampStyle.place(eyebrow, Rect2(64,120 if app._camp_open else 144,680,28))
	CampStyle.place(heading, Rect2(60,160 if app._camp_open else 184,680,88))
	CampStyle.place(description, Rect2(64,252 if app._camp_open else 280,680,32))
	CampStyle.place(camp, Rect2(64,304 if app._camp_open else 338,850 if app._camp_open else 500,120 if app._camp_open else 88))
	camp.add_theme_font_size_override("font_size", 17)
	camp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not app._camp_open and not app._requires_continue and not app._progress_blocked:
		camp.text = "第 %d 天 · %d 位同伴\n货币 %d · 食物 %d" % [app.day,app.crew.size(),app.cash,app.food]
	if app._camp_open and not app._requires_continue and not app._progress_blocked:
		var daily: Dictionary = CampEconomy.rations(app.day, app.crew, app.food, app.camp_rules)
		camp.text = "第 %d 天  /  货币 %d  /  食物 %d  /  武器 %d件" % [app.day,app.cash,app.food,app.weapons.size()]
		for member_id: int in app._battle_meta.get("active_member_ids", [1, 2]):
			var entry: Dictionary = SurvivorRoster.member(app.crew,member_id)
			camp.text += "\n%02d  %s  ·  生命 %.0f" % [member_id,entry.call_sign,float(entry.health)]
			camp.text += "/%.0f · Lv%d · %d XP" % [GrowthRules.maximum(entry),int(entry.growth.level),int(entry.growth.xp_total)]
			if entry.condition == "dead":
				camp.text += " · 已阵亡"
		camp.text += "\n今日口粮 %d · %s" % [int(daily.required),"库存足够" if daily.shortage == 0 else "缺口%d，建议前往超市" % int(daily.shortage)]
		if not app.last_day.is_empty() and app.last_day.food_shortage > 0:
			camp.text += " · 上餐缺口%d已结算" % int(app.last_day.food_shortage)
	app._status.visible = app._title.visible
	start.visible = app._camp_open
	eyebrow.text = "同场救援试运行 · PROJECT_TEMP · 正式门禁未开放"
	if app._battle_meta.get("seed") == "LOW_HP_4_FOOD_12":
		eyebrow.text += " · 演练种子4HP/12食物"
	if app._battle_meta.get("state") == "FAILED":
		heading.text = "旅程已结束"
		start.visible = false
	app._continue_button.text = "查看已结束旅程 →" if app._pending_save.get("journey",{}).get("state") == "FAILED" else "继续隔离旅程 →"
	if app._pending_save.get("journey", {}).get("state") != "FAILED":
		app._continue_button.text = "继续生存旅程（测试） →"
	if app._requires_continue and app._pending_save.is_empty():
		app._continue_button.text = "继续未完成的出击 →"
	app._roster_button.visible = app._camp_open
	app._loadout_button.visible = app._camp_open
	app._home_return.visible = app._camp_open
	app._continue_button.visible = not app._camp_open and app._requires_continue
	app._backup_button.visible = not app._camp_open and app._progress_blocked and not app._backup_save.is_empty()
	app._home_button.visible = not app._camp_open and not app._requires_continue and not app._progress_blocked
	app._home_button.text = "返回营地 →" if app.run_save.has_files() else "开始旅程 →"
	if not app.run_save.has_files():
		app._home_button.text = "新生存旅程（测试） →"
	CampStyle.place(app._continue_button, Rect2(64,446,320,56))
	CampStyle.place(app._backup_button, Rect2(64,446,400,56))
	CampStyle.place(app._home_button, Rect2(64,446,320,56))
	CampStyle.place(app._retry_button, Rect2(840,556,356,44))
	reset.text = "新游戏…"
	reset.visible = app.run_save.has_files() or app._progress_blocked
	reset.text = "新生存旅程…"
	CampStyle.place(reset, Rect2(260 if app._camp_open else 64,556 if app._camp_open else 514,180 if app._camp_open else 320,44))
	CampStyle.place(sound, Rect2(64,556 if app._camp_open else 574,180 if app._camp_open else 148,44))
	CampStyle.place(exit, Rect2(456 if app._camp_open else 224,556 if app._camp_open else 574,140 if app._camp_open else 160,44))
	CampStyle.place(app._home_return, Rect2(612,556,180,44))
	start.text = "01  行动地图\n选择出击目标 →"
	app._roster_button.text = "02  幸存者\n查看同伴与战绩 →"
	app._loadout_button.text = "03  武器整备\n维修与出击配装 →"
	for index: int in range(3):
		var button: Button = [start, app._roster_button, app._loadout_button][index]
		CampStyle.place(button, Rect2(64 + index * 352,432,336,100))
		button.add_theme_font_size_override("font_size", 22)

	app._refresh_playable_presentation()
	if is_instance_valid(app._blue_hour_title_art):
		app._refresh_blue_hour_title()
	app._sync_camp_scene()


func _refresh_playable_presentation() -> void:
	app.get_node("Interface/Screen/Brand").text = "BLUE HOUR · 开发试玩版"
	app.get_node("Interface/Screen/Title/Eyebrow").text = "开发试玩版 · 整备队伍，再次启程。" if app._camp_open else "开发试玩版 · 独立进度 · 阵亡与缺粮损失会保存"
	app._home_button.text = "进入营地 →" if app.run_save.has_files() else "开始试玩 →"
	app._continue_button.text = "继续试玩 →" if not app._pending_save.is_empty() else "继续出击 →"
	if app._pending_save.get("journey",{}).get("state")=="FAILED" or CampaignState.ended(app._pending_save): app._continue_button.text = "查看旅程记录 →"
	app.get_node("Interface/Screen/Title/Reset").text = "新的试玩旅程…"
	if app._battle_meta.has("campaign") and not app._requires_continue:
		var display: Dictionary=CampaignRules.display(app._battle_meta.campaign)
		app.get_node("Interface/Screen/Title/Eyebrow").text=display.title+" · "+display.progress
	app.get_node("Interface/Screen/Title/Sound").text = "设置"
	if app._requires_continue and not app._pending_save.is_empty():
		app.get_node("Interface/Screen/Title/Camp").text = "已保存：第%d天 · 货币%d · 食物%d\n继续同一旅程，或明确开始新的试玩。" % [app._pending_save.day,app._pending_save.cash,app._pending_save.food]


func _setup_blue_hour_title() -> void:
	app._title.theme = CampStyle.blue_hour_theme(app._screen.theme)
	app._blue_hour_title_art = CampStyle.blue_hour_background(app.BLUE_HOUR_TITLE_ART)
	app._blue_hour_title_art.name = "BlueHourTitleArt"
	app._title.add_child(app._blue_hour_title_art)
	app._title.move_child(app._blue_hour_title_art, 0)
	app._catalog_button = Button.new()
	app._catalog_button.text = "专精 / 图鉴"
	app._catalog_button.pressed.connect(func() -> void: app._show_equipment_catalog(app.progress_session.refresh_catalog()))
	app._title.add_child(app._catalog_button)
	var title_font: SystemFont = SystemFont.new()
	title_font.font_names = PackedStringArray(["STZhongsong", "SimSun", "Noto Serif CJK SC", "Microsoft YaHei"])
	title_font.font_weight = 700
	app.get_node("Interface/Screen/Title/Heading").add_theme_font_override("font", title_font)
	var english_font: FontVariation = FontVariation.new()
	english_font.base_font = ThemeDB.fallback_font
	english_font.spacing_glyph = 7
	app.get_node("Interface/Screen/Title/Eyebrow").add_theme_font_override("font", english_font)
	for button: Button in app._blue_hour_title_buttons():
		app._style_blue_hour_title_button(button)
		button.focus_entered.connect(app._remember_blue_hour_title_focus.bind(button))
	app._title.visibility_changed.connect(func() -> void: app._restore_blue_hour_title_focus.call_deferred())
	app._new_game_confirmation.canceled.connect(func() -> void: app._restore_blue_hour_title_focus.call_deferred())
	app._hunger_confirmation.canceled.connect(func() -> void: app._restore_blue_hour_title_focus.call_deferred())


func _refresh_blue_hour_title() -> void:
	app._blue_hour_title_art.visible = not app._camp_open
	app._camp_backdrop.visible = app._camp_open
	app.get_node("Interface/Screen/Brand").hide()
	if app._camp_open:
		app._catalog_button.hide()
		CampStyle.place(app._status, Rect2(64, 646, 1152, 68))
		return
	var heading: Label = app.get_node("Interface/Screen/Title/Heading")
	var english: Label = app.get_node("Interface/Screen/Title/Eyebrow")
	var camp: Label = app.get_node("Interface/Screen/Title/Camp")
	var reset: Button = app.get_node("Interface/Screen/Title/Reset")
	var sound: Button = app.get_node("Interface/Screen/Title/Sound")
	var exit: Button = app.get_node("Interface/Screen/Title/Quit")
	heading.text = "蓝时归航"
	heading.add_theme_font_size_override("font_size", 76)
	heading.add_theme_color_override("font_color", Color("f3e7d1"))
	CampStyle.place(heading, Rect2(90, 144, 426, 94))
	english.text = "BLUE HOUR"
	english.add_theme_color_override("font_color", Color("f3e7d1"))
	CampStyle.place(english, Rect2(99, 242, 334, 28))
	app.get_node("Interface/Screen/Title/Description").hide()
	var live_camp: bool = app._home_button.visible and app.run_save.has_files()
	app._continue_button.visible = not live_camp
	app._continue_button.disabled = not app._requires_continue or app._progress_blocked
	if app._pending_save.get("journey", {}).get("state") != "FAILED" and not CampaignState.ended(app._pending_save):
		app._continue_button.text = "继续出击" if app._requires_continue and app._pending_save.is_empty() else "继续旅程"
	app._home_button.text = "继续旅程" if live_camp else "新旅程"
	reset.text = "新旅程"
	reset.visible = not app._home_button.visible or live_camp
	sound.text = "设置"
	exit.text = "退出游戏"
	CampStyle.place(app._continue_button, Rect2(91, 316, 276, 44))
	CampStyle.place(app._home_button, Rect2(91, 316 if live_camp else 367, 276, 44))
	CampStyle.place(reset, Rect2(91, 367, 276, 44))
	CampStyle.place(sound, Rect2(91, 418, 126, 44))
	var catalog_ready: bool = app.progress_session.catalog_state().get("error", FAILED) == OK
	app._catalog_button.text = "专精 / 图鉴" if catalog_ready else "专精待同步"
	app._catalog_button.tooltip_text = "" if catalog_ready else "打开专精资料，重试读取与同步"
	app._catalog_button.show()
	CampStyle.place(app._catalog_button, Rect2(223, 418, 144, 44))
	CampStyle.place(exit, Rect2(91, 469, 276, 44))
	CampStyle.place(app._backup_button, Rect2(91, 524, 365, 38))
	CampStyle.place(app._retry_button, Rect2(91, 569 if app._backup_button.visible else 524, 365, 38))
	camp.visible = app._requires_continue and not app._pending_save.is_empty() and not app._progress_blocked
	camp.add_theme_color_override("font_color", Color("cad7d6"))
	CampStyle.place(camp, Rect2(103, 532, 426, 68))
	CampStyle.place(app._status, Rect2(103, 633, 490, 74))
	app._status.add_theme_color_override("font_color", CampStyle.AMBER if app._progress_blocked else Color("c5d3d1"))
	var focusable: Array[Button] = []
	for button: Button in app._blue_hour_title_buttons():
		if button.visible and not button.disabled:
			focusable.append(button)
	for index: int in range(focusable.size()):
		focusable[index].focus_next = focusable[(index + 1) % focusable.size()].get_path()
		focusable[index].focus_previous = focusable[(index + focusable.size() - 1) % focusable.size()].get_path()
	app._restore_blue_hour_title_focus.call_deferred()


func _blue_hour_title_buttons() -> Array[Button]:
	return [app._continue_button, app._home_button, app.get_node("Interface/Screen/Title/Reset"), app.get_node("Interface/Screen/Title/Sound"),
		app._catalog_button, app.get_node("Interface/Screen/Title/Quit"), app._backup_button, app._retry_button]


func _style_blue_hour_title_button(button: Button) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", CampStyle.box(Color(0.06, 0.14, 0.2, 0.40), Color.TRANSPARENT, 8))
	button.add_theme_stylebox_override("hover", CampStyle.box(Color(0.10, 0.24, 0.33, 0.92), CampStyle.TEAL, 8))
	button.add_theme_stylebox_override("pressed", CampStyle.box(Color(0.10, 0.17, 0.22, 0.96), CampStyle.AMBER, 8))
	button.add_theme_stylebox_override("disabled", CampStyle.box(Color(0.06, 0.14, 0.2, 0.35), Color.TRANSPARENT, 8))
	var focus: StyleBoxFlat = CampStyle.box(Color.TRANSPARENT, CampStyle.AMBER, 0)
	focus.border_width_left = 4
	button.add_theme_stylebox_override("focus", focus)


func _remember_blue_hour_title_focus(button: Button) -> void:
	if not app._camp_open:
		app._blue_hour_title_focus = button


func _restore_blue_hour_title_focus() -> void:
	if app._camp_open or app.phase != app.Phase.TITLE or not app._title.is_visible_in_tree() or app._settings_open():
		return
	if is_instance_valid(app._blue_hour_title_focus) and app._blue_hour_title_focus.is_visible_in_tree() and not app._blue_hour_title_focus.disabled:
		app._blue_hour_title_focus.grab_focus()
		return
	for button: Button in app._blue_hour_title_buttons():
		if button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()
			return
