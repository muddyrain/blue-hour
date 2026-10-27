class_name ThreatDirector
extends RefCounted
## Reads Expedition.elapsed only. Scheduling remains in the existing spawn countdown.

enum Stage {
	CALM,
	LATE,
	NIGHT,
	DEEP,
}

const LABELS: Array[String] = ["平稳", "暮色逼近", "夜间来袭", "深夜高压"]
const HINTS: Array[String] = ["威胁 · 平稳", "暮色 · 增援加快", "夜间 · 增援密集", "深夜 · 持续高压"]

var rules: ThreatRules = ThreatRules.new()
var stage: Stage = Stage.CALM
var interval: float = 7.0
var transitions: int = 0


func update(elapsed: float, daylight: float, base_interval: float) -> bool:
	var next: Stage = Stage.CALM
	if elapsed >= daylight * rules.deep_fraction:
		next = Stage.DEEP
	elif elapsed >= daylight:
		next = Stage.NIGHT
	elif elapsed >= daylight * rules.late_fraction:
		next = Stage.LATE
	# A fresh sortie creates a fresh director. Rewinds cannot replay a warning.
	var changed: bool = next > stage
	if changed:
		stage = next
		transitions += 1
	interval = base_interval * rules.interval_factors[stage]
	return changed


func snapshot() -> Dictionary:
	return {"stage":stage, "label":LABELS[stage], "hint":HINTS[stage],
		"interval":interval, "transitions":transitions, "source":"PROJECT_TEMP TMP-126..129"}
