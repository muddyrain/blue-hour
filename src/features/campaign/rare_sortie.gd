class_name RareSortie
extends RefCounted
## PROJECT_TEMP selection and authored work for the optional investigation-day slot.

const VERSION: int = 1
const SLOT: int = 2
const NEAR_FOOD: int = 3
const DEEP_FOOD: int = 5
const EQUIPMENT_CASH: int = 6


static func selection(seed: String, day: int, slot: int) -> String:
	if day < 3 or slot != SLOT:
		return ""
	var roll: int = ("rare-sortie:%d:%s:%d:%d" % [VERSION, seed, day, slot]).sha256_text().left(1).hex_to_int()
	if roll >= 4:
		return ""
	return "supply" if roll < 2 else "airdrop"


static func title(type: String) -> String:
	return "断电冷库" if type == "supply" else "封锁军需站"


static func cold_route_fits(level: Dictionary) -> bool:
	var night: float = level.assumptions.night_seconds
	var primary: float = level.single.team_return_seconds
	var extended: float = level.optional.single.team_return_seconds
	# Plan a daylight escape and an extension that can run into the first part of night.
	return primary < level.assumptions.late_seconds and extended >= night - 12.0 \
		and extended <= night + 20.0


static func landmark(type: String, site: String) -> String:
	if type == "supply":
		return {"food":"近处配货间", "food_2":"后装卸区"}.get(site, "")
	return {"cash":"露天武器箱", "cash_2":"器材库"}.get(site, "")


static func card_text(value: Dictionary) -> String:
	var level: Dictionary = value.exploration.level
	if value.type == "supply":
		var near_time: int = ceili(level.routes["bus>food"].length / LevelSummary.SPEED)
		var deep_time: int = ceili(level.optional.routes["food_2>bus"].length / LevelSummary.SPEED)
		return "主目标 · 配货间 %d 粮（单程约 %d 秒）\n额外 · 后装卸区 %d 粮（回车约 %d 秒）\n风险 · 深入搜集会压缩天黑前的回程窗口。\n可先拿近处口粮撤离。" % [
			NEAR_FOOD, near_time, DEEP_FOOD, deep_time]
	return "主目标 · 装卸院露天回收武器 1 件\n额外 · 器材库 %d 币，可维修或建设\n风险 · 首次开工引来增援。实墙可掩护，检修口需绕行。\n可拿到武器就撤离。" % EQUIPMENT_CASH
