class_name ActionMemo
extends RefCounted
## Optional shared proofs. Callers compute outside the lock and publish read-only values.

var _values: Dictionary[String, Variant] = {}
var _mutex: Mutex = Mutex.new()
var _limit: int
var _evict_oldest: bool


func _init(limit: int = 0, evict_oldest: bool = false) -> void:
	_limit = limit
	_evict_oldest = evict_oldest


func lookup(key: String) -> Variant:
	_mutex.lock()
	var value: Variant = _values.get(key)
	_mutex.unlock()
	return value


func store(key: String, value: Variant) -> void:
	_mutex.lock()
	if not _values.has(key):
		if _limit > 0 and _values.size() >= _limit:
			if _evict_oldest:
				_values.erase(_values.keys()[0])
			else:
				_values.clear()
		_values[key] = value
	_mutex.unlock()
