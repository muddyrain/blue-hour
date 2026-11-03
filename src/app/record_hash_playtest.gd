class_name RecordHashPlaytest
extends EnemyPlaytest
## Reuse the original camp/transaction drivers in the current task's isolated namespace.

func _task_path() -> String:
	return "/.local/p0-record-hash-01/"
