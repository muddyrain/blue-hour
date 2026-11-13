class_name AppResults
extends RefCounted

var app: AppMain


func _init(owner: AppMain) -> void:
	app = owner


func _present_finished_battle() -> void:
	var frozen: Dictionary = app._pending_settlement
	var durable: bool = false
	if frozen.journey.state == "FAILED":
		durable = app._accept_transaction(app.progress_session.commit_result(), true)
		if durable:
			app._pending_settlement = {}
	app._show_battle_result(frozen, durable)


func _show_battle_result(snapshot: Dictionary, durable: bool) -> void:
	app.phase = app.Phase.RESULT
	app._screen.show()
	app._title.hide()
	app._result.show()
	var ended: bool = snapshot.journey.state == "FAILED" or CampaignState.ended(snapshot)
	var victory: bool = snapshot.journey.get("campaign",{}).get("outcome")=="VICTORY"
	app._set_pump_victory_visible(false)
	if app._pump_details_back != null:
		app._pump_details_back.hide()
	app.get_node("Interface/Screen/Result/Heading").text = ("旅程胜利" if durable else "胜利预览 · 待确认保存") if victory else "旅程结束 · 全员阵亡" if ended else "幸存者归航"
	var text: String = app._playable_result_text(snapshot,durable)
	app.get_node("Interface/Screen/Result/Scroll/Body").text = text
	app.get_node("Interface/Screen/Result/Scroll").scroll_vertical = 0
	app.get_node("Interface/Screen/Result/Scroll/Body").add_theme_font_size_override("font_size", 18)
	app.get_node("Interface/Screen/Result/Continue").text = ("查看旅程记录 →" if durable else "重试保存终局 →") if ended else "返回营地 →"
	app._battle_new_button.visible = ended
	app._battle_new_button.disabled = not durable
	app._status.text = "隔离生存终局" if ended and durable else app._progress_message
	app._status.text = app._progress_message if app._progress_blocked else ("结算已保存。" if durable else "确认结算后保存；保存失败时不会进入下一次行动。")
	app.get_node("Interface/Screen/Result/Continue").text = ("查看旅程记录 →" if durable else "重试保存终局 →") if ended else "确认结算并回营 →"
	if victory and not durable and CampFacilities.enabled(snapshot):
		app.get_node("Interface/Screen/Result/Heading").text = "归航待确认 · 破阵者已倒地"
		app.get_node("Interface/Screen/Result/Continue").text = "确认归航并保存胜利 →" if not app._progress_blocked else "重试保存终局 →"
	if victory and durable and CampaignRules.pump_station_enabled(snapshot.journey.campaign):
		app._show_pump_victory(snapshot)


func _show_pump_victory(snapshot: Dictionary) -> void:
	var inspected: Dictionary = app.progress_session.inspect()
	var receipt: Dictionary = inspected.get("receipt", {})
	var frozen: Dictionary = receipt.get("envelope", {}).get("result", {})
	var generated: Dictionary = frozen.get("rules", {}).get("mission", {}).get("generated", {})
	var battle: Dictionary = frozen.get("battle", {})
	if inspected.error != OK or receipt.get("phase") != "COMMITTED" or receipt.get("transaction_id") != snapshot.last_settlement_id \
			or not PumpStationAction.enabled(generated) or not battle.get("evacuated", false) \
			or not PumpStationAction.stopped(battle.get("site_facts", {})) or battle.get("encounter", {}).get("defeat", {}).is_empty():
		return
	if app._pump_victory == null:
		app._pump_victory = PumpVictoryView.new()
		app._result.add_child(app._pump_victory)
		app._pump_victory.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		app._pump_victory.record_requested.connect(app.return_to_title)
		app._pump_victory.new_journey_requested.connect(app._request_battle_new_journey)
		app._pump_victory.details_requested.connect(app._open_pump_details)
		app._pump_details_back = Button.new()
		app._pump_details_back.text = "返回胜利画面"
		app._result.add_child(app._pump_details_back)
		app._pump_details_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		app._pump_details_back.offset_left = 688
		app._pump_details_back.offset_right = 900
		app._pump_details_back.offset_top = -84
		app._pump_details_back.offset_bottom = -28
		app._pump_details_back.pressed.connect(func() -> void:
			app._pump_details_back.hide()
			app._set_pump_victory_visible(true)
			app._pump_victory.record_button.grab_focus())
		app._pump_details_back.hide()
	var returned: int = battle.member_results.filter(func(member: Dictionary) -> bool: return member.health > 0.0).size()
	app._pump_victory.present(int(snapshot.last_day.day), returned, app._catalog_result_notice(snapshot))
	app._set_pump_victory_visible(true)


func _open_pump_details() -> void:
	app._set_pump_victory_visible(false)
	app._pump_details_back.show()
	app._pump_details_back.grab_focus()


func _set_pump_victory_visible(enabled: bool) -> void:
	if app._pump_victory == null:
		return
	app._pump_victory.visible = enabled
	app.get_node("Interface/Screen/Result/Heading").visible = not enabled
	app.get_node("Interface/Screen/Result/Scroll").visible = not enabled
	app.get_node("Interface/Screen/Result/Continue").visible = not enabled
	app._battle_new_button.visible = not enabled


func _hunger_policy_text() -> String:
	return "开发试玩版：战斗阵亡不可恢复；归航时每名原出发存活者消耗1粮。每缺1粮会失去1名队员，最多至全灭。\n新救援同伴本餐不参食，下一次按实际存活者计粮；死者的原武器保留库存。\n搜刮后须发动巴士并集合存活者，确认结算才入账。中途请使用安全暂存；未保存的中断可能无法继续。\n试玩进度独立，旧档不会自动转换。"


func _member_fate(snapshot: Dictionary, id: int) -> String:
	for death: Dictionary in snapshot.journey.deaths:
		if int(death.member_id) == id:
			return "饥饿死亡 / STARVATION" if death.cause == "STARVATION" else "战斗阵亡 / BATTLE"
	return "存活"


func _request_battle_new_journey() -> void:
	if app.phase == app.Phase.RESULT:
		if not app._battle_new_button.disabled and not app._new_game_confirmation.visible:
			app._open_opening_choice()
		return
	if app.phase == app.Phase.TITLE:
		app.reset_demo()


func _playable_result_text(snapshot: Dictionary, durable: bool) -> String:
	# Presentation reads the already-frozen result; it never recalculates rewards/deaths.
	var state: Dictionary = app.progress_session.inspect()
	var frozen: Dictionary = state.get("receipt",{}).get("envelope",{}).get("result",{})
	var meal: Dictionary = frozen.get("food",snapshot.last_day)
	var battle: Dictionary = frozen.get("battle",{})
	var text: String = "归航结果 · 已入账\n" if durable else "归航预览 · 确认保存后入账\n"
	var catalog_notice: String = app._catalog_result_notice(snapshot) if durable else ""
	if not catalog_notice.is_empty():
		text += catalog_notice + "\n"
	var generated: Dictionary = frozen.get("rules",{}).get("mission",{}).get("generated",{})
	if BillboardActionV1.enabled(generated):
		if not BillboardIntelV1.opportunity(snapshot).is_empty():
			text += "超市广告牌 · 下次选卡保证出现超市补给%s\n" % ("" if durable else "（确认后生效）")
		elif battle.get("billboard", {}).get("completed", false):
			text += "超市广告牌 · 已调查，本次未登记情报\n"
		else:
			text += "超市广告牌 · 调查未完成\n"
	if PumpStationAction.enabled(generated) and not battle.is_empty():
		if battle.encounter.defeat.is_empty():
			text += "河堤泵站 · 提前撤离，未登记胜利。\n" if battle.evacuated else "河堤泵站 · 未能归航。\n"
		else:
			text += "河堤泵站 · 已停机 · 破阵者已倒地\n"
	if snapshot.last_day.has("task") and not generated.get("campaign",{}).get("is_finale",false):
		var title: String = ""
		if generated.get("mission_policy") == 1:
			if generated.has("rare_policy"):
				title = RareSortie.title(generated.type)
			elif generated.has("investigation"):
				title = "调查 · " + CampaignRules.CLUE_NAMES[generated.investigation.clue_id]
			elif generated.type == "airdrop":
				title = "装备 · 露天回收"
		var task: Dictionary = snapshot.last_day.task
		text += TaskActions.summary_text(task, title) + "\n"
		if task.type == "event_sortie":
			var reward: String = "0 粮 · 0 币"
			if task.branch == EventSortieV1.QUIET:
				reward = "%s%d 粮" % ["+" if task.event_food > 0 else "", int(task.event_food)]
			elif task.branch == EventSortieV1.FORCE:
				reward = "%s%d 币" % ["+" if task.event_cash > 0 else "", int(task.event_cash)]
			text += "%s · 本次事件收益\n%s · %s\n" % [EventSortieV1.TITLE, EventSortiePanel.branch_title(task.branch), reward]
	if not meal.is_empty():
		text += ReturnFeedback.food_text(meal) + "\n"
		if meal.food_shortage > 0:
			text += "本次口粮缺口 %d 粮\n" % meal.food_shortage
	text += "带回 %d 币 · %d 件武器\n" % [snapshot.last_day.cash_gained, battle.get("weapons", []).size()]
	if not WorkshopSiteV1.site_id(generated).is_empty():
		var gained: int = int(WorkshopV1.recovered(generated, battle))
		text += "本次工具箱 ×%d · %s %d\n" % [gained, "营地库存" if durable else "确认后库存", WorkshopV1.tools(snapshot)]
	var ended: bool = snapshot.journey.state == "FAILED" or CampaignState.ended(snapshot)
	if not ended:
		var next_rations: Dictionary = CampEconomy.rations(snapshot.day, snapshot.crew, snapshot.food, app.camp_rules)
		if next_rations.shortage > 0:
			text += "下一趟口粮缺口 %d 粮，可优先选择补给。\n" % next_rations.shortage
		if battle.get("weapons", []).any(func(item: Dictionary) -> bool: return item.condition == "damaged"):
			text += "损坏武器可在营地武器整备中先维修，再配装。\n"
	if BuildState.enabled(snapshot) and int(frozen.get("rules",{}).get("data_version",0)) in [8,9,10]:
		var obtained: Array=BuildState.acquired(frozen.rules.mission.generated,battle.site_facts,battle.evacuated)
		var names: PackedStringArray=[]
		for item: String in obtained: names.append(generated.build.policy.items[item].name)
		text+="本次道具："+("、".join(names) if not names.is_empty() else "无")+" · 本局库存%d/%d（"%[snapshot.journey.build.owned.size(), BuildItems.ids(BuildState.pool(snapshot)).size()]+("已保存" if durable else "确认后入库")+"）\n"
	if PowerState.enabled(snapshot) and not battle.is_empty():
		var sample: String=generated.powers.sample if battle.evacuated and battle.site_facts.get("cash",{}).get("searched",false) else ""
		var inventory: Dictionary = snapshot.journey.build.powers
		var count: int = SpecialPowers.policy(int(inventory.version)).size()
		text+="本次能力："+(PowerActions.name_for(sample) if not sample.is_empty() else "无")+" · 本旅程%d/%d（"%[inventory.owned.size(),count]+("已保存" if durable else "确认后入库")+"）\n"
	for item: Dictionary in battle.get("weapons",[]):text+="带回武器："+WeaponInventory.loot_description(item)+"\n"
	if CampaignState.is_short(snapshot):
		var campaign: Dictionary = snapshot.journey.campaign
		var recorded: Dictionary = campaign
		if CampaignRules.is_investigation(campaign):
			if not durable:
				recorded = app.camp_snapshot().journey.campaign
			if not campaign.clues.is_empty():
				var clue: Dictionary = campaign.clues.back()
				if clue.transaction_id == snapshot.last_settlement_id:
					text += "调查线索：%s（%s）\n" % [CampaignRules.CLUE_NAMES[clue.id], "已登记" if durable else "确认后登记"]
		var display: Dictionary = CampaignRules.display(recorded)
		text += display.title + " · " + display.progress + "\n"
		if campaign.outcome == "VICTORY":
			text += "首领真实击败、存活者巴士撤离；" + ("旅程胜利已保存。" if durable else "胜利仅为预览，确认保存成功才结束旅程。") + "\n"
	for member: Dictionary in snapshot.crew:
		var awarded: Dictionary = GrowthRules.member_row(frozen.get("xp",{}).get("members",[]),int(member.id))
		var fate: String = app._member_fate(snapshot,int(member.id)).replace(" / STARVATION", "").replace(" / BATTLE", "")
		text += "\n%02d %s · %s · 生命%.0f/%.0f\nLv%d · %d XP（本次+%d）\n" % [member.id,member.call_sign,fate,member.health,GrowthRules.maximum(member),member.growth.level,member.growth.xp_total,awarded.get("xp_gained",0)]
	text += "\n营地：第%d天 · 货币%d · 存活%d人\n" % [snapshot.day,snapshot.cash,snapshot.journey.active_member_ids.size()]
	text += "旅程已结束，不能再次出击。" if ended else "确认结算后可回营整备，再次出击。"
	return text


func _catalog_result_notice(snapshot: Dictionary) -> String:
	if not snapshot.journey.get("build", {}).has("catalog"):
		return ""
	var catalog: Dictionary = app.progress_session.catalog_state()
	if catalog.get("error", FAILED) != OK:
		return "专精与图鉴待同步 · 可在标题重试" if OpeningBuild.is_m47(snapshot) else "装备图鉴待同步 · 可重启补记"
	var result: Dictionary = catalog.get("specialization_result", {})
	var notices: PackedStringArray = []
	if result.get("run_id") == snapshot.profile_id and result.get("transaction_id") == snapshot.last_settlement_id:
		notices.append(SpecialtyPresentation.result_text(result))
	if catalog.unlock.get("receipt", {}).get("transaction_id") == snapshot.last_settlement_id:
		notices.append("已解锁 · 滤毒面罩")
	return "\n".join(notices)
