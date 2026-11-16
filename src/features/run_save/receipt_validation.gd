class_name ReceiptValidation
extends RefCounted
## Pure decode/source proofs may run independently. Journal transitions stay ordered.

const MIN_RECORDS: int = 12
const MAX_WORKERS: int = 3

var _journal: ReceiptJournal
var _raw: Array[PackedByteArray]
var _results: Array[Dictionary] = []
var _mutex: Mutex = Mutex.new()
var _worker_usec: int = 0


func _init(journal: ReceiptJournal, raw: Array[PackedByteArray]) -> void:
	_journal = journal
	_raw = raw
	for index: int in range(raw.size()):
		_results.append({})


func decode_from(first: int) -> Array[Dictionary]:
	# Reject a damaged first record before scheduling the remainder. No worker
	# reads files, appends records, publishes a prefix or changes journal order.
	_decode_range(first, first + 1)
	if _results[first].error != OK:
		return _results
	var workers: int = mini(MAX_WORKERS, maxi(1, OS.get_processor_count()))
	var count: int = _raw.size() - first - 1
	var threads: Array[Thread] = []
	for index: int in range(workers - 1):
		var begin: int = first + 1 + count * index / workers
		var end: int = first + 1 + count * (index + 1) / workers
		var thread: Thread = Thread.new()
		if thread.start(_decode_range.bind(begin, end)) == OK:
			threads.append(thread)
		else:
			_decode_range(begin, end)
	_decode_range(first + 1 + count * (workers - 1) / workers, _raw.size())
	for thread: Thread in threads:
		thread.wait_to_finish()
	FreezeProfile.scale("journal_validation_workers", threads.size() + 1)
	FreezeProfile.scale("journal_validation_records", _raw.size() - first)
	# Sum of concurrent task elapsed times, not CPU time or additive wall time.
	FreezeProfile.scale("journal_validation_worker_usec", _worker_usec)
	return _results


func _decode_range(begin: int, end: int) -> void:
	for index: int in range(begin, end):
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = _journal._decode_record(_raw[index], false)
		var elapsed: int = Time.get_ticks_usec() - started
		_mutex.lock()
		# Do not retain every expanded historical payload. Ordered consumption
		# restores from the existing byte-bounded DTO cache, or fully revalidates
		# an evicted entry. Invalid results retain their original error/reason.
		_results[index] = {"error":OK} if result.error == OK else result
		_worker_usec += elapsed
		_mutex.unlock()
