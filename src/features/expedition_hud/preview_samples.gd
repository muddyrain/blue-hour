class_name C1HudSamples
extends RefCounted
## UI fixtures only. These values are not gameplay rules or new observations.

const TITLES: Array[String] = ["正常出击 / 准备中", "可发动 / 不同生命", "暂停界面样本", "等待集合", "长文本 / 大数值", "可选数据缺失"]


static func make_sample(index: int) -> Dictionary:
	var state: Dictionary = {
		"mission_title": "旧街 · 补给店", "day_text": "第 2 天",
		"search_progress_text": "0 / 1", "defeated_text": "3",
		"currency_text": "53", "currency_delta_text": "+0", "paused": false,
		"survivors": [
			{"id": 1, "label": "队员 1", "hp": 196.0, "max_hp": 200.0},
			{"id": 2, "label": "队员 2", "hp": 128.0, "max_hp": 200.0},
		],
		"time": {"label": "出击时间", "text": "01:32", "tone": "normal", "visible": true},
		"bus_status_text": "巴士准备 · 20 秒", "bus_action_label": "准备中 · 暂不可发动",
		"bus_action_enabled": false, "status_hint": "左键地面下令；搜集时仍可移动其他队员。",
	}
	match index:
		1:
			state["bus_status_text"] = "巴士已准备好"
			state["bus_action_label"] = "发动巴士 →"
			state["bus_action_enabled"] = true
		2:
			state["paused"] = true
			state["bus_status_text"] = "巴士已准备好"
			state["bus_action_label"] = "发动巴士 →"
			state["bus_action_enabled"] = true
			state["status_hint"] = "已暂停，仍可下令。继续后执行。"
		3:
			state["bus_status_text"] = "等待队员集合"
			state["bus_action_label"] = "等待集合"
			state["bus"] = {"tone": "warning"}
			state["time"] = {"label": "出击时间", "text": "00:53", "tone": "warning", "hint": "主线提示样本"}
			state["status_hint"] = "搜集中的队员仍在工作；可下令返回巴士附近。"
		4:
			state["mission_title"] = "蓝灰海岸旧城区 · 东侧临港物资转运站与临时补给点"
			state["day_text"] = "第 128 天"
			state["currency_text"] = "999,999,999"
			state["currency_delta_text"] = "+123,456"
			state["survivors"][1]["label"] = "第二行动队员"
			state["bus_status_text"] = "等待集合 · 仍有队员正在补给店搜集"
			state["bus_action_label"] = "等待全体队员返回巴士"
			state["status_hint"] = "这是较长的主线提示样本：请确认队员的当前工作，再决定继续搜集或下令返回巴士附近集合。"
		5:
			state.erase("currency_delta_text")
			state.erase("time")
			state.erase("status_hint")
			state["survivors"] = [{"id": 1, "hp": 87.0, "max_hp": 200.0}]
	return state
