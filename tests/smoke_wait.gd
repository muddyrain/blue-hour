extends "res://tests/smoke_loop.gd"
## Headless frames are not seconds: a pending worker can outlive 12000 polls.

var _polls: int = 0


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 0
	await _wait(_after_many_frames, "wall-clock wait survives more than 12000 frames", 90)
	print("BH_WAIT_POLLS ", _polls, " elapsed_ms=", Time.get_ticks_msec() - started_ms)
	_check(_polls > 12000, "wait reaches the pending completion instead of exhausting a frame budget")
	_finish()


func _after_many_frames() -> bool:
	_polls += 1
	return _polls > 12000
