class_name ActionGenerationMemo
extends RefCounted
## Private process-local deterministic results, including failed generation attempts.
## The caller supplies all inputs and the rule context; no disk proof is accepted.

const MAX_ENTRIES: int = 64
const MAX_BYTES: int = 16_777_216
var _mutex: Mutex = Mutex.new()
var _entries: Dictionary = {}
var _pending: Dictionary = {}
var _bytes: int = 0


func resolve(input: Dictionary, generate: Callable) -> Dictionary:
	var identity: String = RecordEncoding.fingerprint(input)
	if identity.is_empty():
		return generate.call()
	_mutex.lock()
	if not _pending.has(identity):
		_pending[identity] = {"gate":Mutex.new(), "users":0}
	_pending[identity].users += 1
	var gate: Mutex = _pending[identity].gate
	_mutex.unlock()
	# Concurrent receipts for the same source share one completed computation.
	# Different sources can still use the journal's existing bounded workers.
	gate.lock()
	_mutex.lock()
	var entry: Dictionary = _entries.get(identity, {})
	if not entry.is_empty() and entry.input == input:
		_entries.erase(identity)
		_entries[identity] = entry
		_release_locked(identity)
		_mutex.unlock()
		gate.unlock()
		FreezeProfile.count("action_map_hits")
		return entry.result.duplicate(true)
	_mutex.unlock()
	FreezeProfile.count("action_map_builds")
	var result: Dictionary = generate.call()
	var bytes: int = var_to_bytes(input).size() + var_to_bytes(result).size()
	_mutex.lock()
	if bytes <= MAX_BYTES:
		if _entries.has(identity):
			_bytes -= int(_entries[identity].bytes)
			_entries.erase(identity)
		while not _entries.is_empty() and (_entries.size() >= MAX_ENTRIES or _bytes + bytes > MAX_BYTES):
			var oldest: String = _entries.keys()[0]
			_bytes -= int(_entries[oldest].bytes)
			_entries.erase(oldest)
		_entries[identity] = {"input":input.duplicate(true), "result":result.duplicate(true), "bytes":bytes}
		_bytes += bytes
	_release_locked(identity)
	_mutex.unlock()
	gate.unlock()
	return result


func _release_locked(identity: String) -> void:
	_pending[identity].users -= 1
	if _pending[identity].users == 0:
		_pending.erase(identity)
