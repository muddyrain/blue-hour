class_name ActionMemo
extends RefCounted
## Optional shared proofs. Callers compute outside the lock and publish read-only values.

static var _mutex: Mutex = Mutex.new()


static func lookup(cache: Dictionary, key: String) -> Variant:
	_mutex.lock()
	var value: Variant = cache.get(key)
	_mutex.unlock()
	return value


static func store(cache: Dictionary, key: String, value: Variant,
		limit: int = 0, evict_oldest: bool = false) -> void:
	_mutex.lock()
	if not cache.has(key):
		if limit > 0 and cache.size() >= limit:
			if evict_oldest:
				cache.erase(cache.keys()[0])
			else:
				cache.clear()
		cache[key] = value
	_mutex.unlock()
