extends SceneTree
## Live provenance must retain strict prefix equality after Exact receipt decoding.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	var generated: Dictionary = {"layout":{"bounds":[0, 0, 1024, 1024]}, "recon":{"version":ReconActionV1.SOURCE_VERSION}}
	var knowledge: ReconKnowledge = ReconKnowledge.new(generated)
	_expect(knowledge.observe(2, Vector2(128, 128), 1.0), "first actual observation creates provenance")
	knowledge.record_work(2, Vector2(128, 128), 0.5, 1.0)
	var before: Dictionary = _wire(knowledge.snapshot(0.5))
	before.elapsed = 1.0
	_expect(ReconKnowledge.history_problem(before, _next(knowledge.snapshot(0.5), 1.0)).is_empty(),
		"live reveal and work prefixes equal the acknowledged Exact representation")
	_expect(knowledge.observe(2, Vector2(768, 768), 2.0), "later movement records additional exploration")
	knowledge.record_work(2, Vector2(128, 128), 1.0, 1.5)
	var after: Dictionary = knowledge.snapshot(1.0)
	_expect(ReconKnowledge.history_problem(before, _next(after, 2.0)).is_empty(),
		"strict old prefix permits only legal append and contiguous work extension")
	var restored: ReconKnowledge = ReconKnowledge.new(generated)
	restored.restore(_wire(after))
	var claimed: Dictionary = _wire(after)
	claimed.elapsed = 2.0
	_expect(restored.observe(1, Vector2(768, 128), 3.0), "restored provenance accepts a new member observation")
	_expect(ReconKnowledge.history_problem(claimed, _next(restored.snapshot(1.0), 3.0)).is_empty(),
		"restored and newly generated history use the same strict canonical number representation")
	var bad: Dictionary = after.duplicate(true)
	bad.reveals[0][0] = 1.0
	_expect(ReconKnowledge.history_problem(before, _next(bad, 2.0)) == "RECON_HISTORY_BITS",
		"changing an already acknowledged member still rejects")
	bad = after.duplicate(true)
	bad.reveals.remove_at(0)
	_expect(ReconKnowledge.history_problem(before, _next(bad, 2.0)) == "RECON_HISTORY_BITS",
		"removing acknowledged exploration still rejects")
	bad = after.duplicate(true)
	bad.work[0][3] += 1.0
	_expect(ReconKnowledge.history_problem(before, _next(bad, 2.0)) == "RECON_HISTORY_PROGRESS",
		"rewriting an acknowledged work point still rejects")
	print(JSON.stringify({"suite":"m49_recon_prefix", "checks":checks, "failures":failures,
		"scope":"PURE_LIVE_PROVENANCE_AND_UNCHANGED_STRICT_HISTORY_VALIDATION"}))
	quit(1 if failures else 0)


func _wire(value: Dictionary) -> Dictionary:
	return RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(value))).payload


func _next(state: Dictionary, elapsed: float) -> Dictionary:
	return {"phase":"SUSPEND_READY", "envelope":{"world":{"recon":state, "sim":{"elapsed":elapsed}}}}


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("M49_RECON_PREFIX_FAIL " + label)
