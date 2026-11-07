class_name ValueProofCache
extends RefCounted
## Process-local pure results only. A hit requires full native recursive value equality
## against a private deep copy of a previously validated input. No object identity keys.
const MAX_ENTRIES: int=512
const MAX_BYTES: int=16_777_216
static var _entries: Dictionary={}
static var _bytes: int=0
static var _count: int=0

static func lookup(scope: String, value: Dictionary) -> Dictionary:
	var stamp: int=FreezeProfile.enter("value_proof.lookup")
	# Finite validated copies bound comparison depth even when the new input is invalid.
	# Dictionary equality compares all nested typed values and ignores insertion order.
	var rows: Array=_entries.get(scope,[])
	for index: int in range(rows.size()-1,-1,-1):
		var row: Dictionary=rows[index]
		if row.input==value:
			FreezeProfile.count("value_proof_hits")
			FreezeProfile.leave("value_proof.lookup",stamp)
			return {"hit":true,"result":row.result.duplicate(true) if row.result is Dictionary else row.result}
	FreezeProfile.count("value_proof_misses")
	FreezeProfile.leave("value_proof.lookup",stamp)
	return {"hit":false,"scope":scope,"input":value}

static func remember(key: Dictionary, result: Variant) -> void:
	if key.hit:
		return
	var bytes: int=var_to_bytes(key.input).size()+var_to_bytes(result).size()
	if bytes>MAX_BYTES:
		return
	if _count>=MAX_ENTRIES or _bytes+bytes>MAX_BYTES:
		_entries.clear()
		_bytes=0
		_count=0
	if not _entries.has(key.scope):
		_entries[key.scope]=[]
	_entries[key.scope].append({"input":key.input.duplicate(true),"result":result.duplicate(true) if result is Dictionary else result})
	_bytes+=bytes
	_count+=1
