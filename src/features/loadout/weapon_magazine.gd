class_name WeaponMagazine
extends RefCounted
## PROJECT_TEMP V1. One equipped instance, simulation time only, infinite reserve.
const BUILD: String = "M7-WEAPON-01-1"
const PARAMETERS: Dictionary = WeaponDefinition.MAGAZINES
const DEFEAT_REFUND_ROUNDS: int = 1 # PROJECT_TEMP M33
const EXTENDED: String = "extended_mag"
const QUICK: String = "quick_mag"
const CARBINE_MODS: Dictionary = {
	EXTENDED: {"capacity":16, "seconds":2.20},
	QUICK: {"capacity":9, "seconds":1.05},
}

var instance_id: String
var weapon_id: String
var modification: String
var rounds: int
var reloading: bool = false
var remaining: float = 0.0
var reload_factor: float = 1.0

func _init(identity: String, gun: String, mod: String = "") -> void:
	instance_id = identity
	weapon_id = gun
	modification = mod
	rounds = capacity()

func capacity() -> int:
	return parameters(weapon_id, modification).capacity

func seconds() -> float:
	return parameters(weapon_id, modification).seconds * reload_factor

func can_fire() -> bool:
	return not reloading and rounds>0

func commit_shot(defeat_refund: bool = false) -> int:
	assert(can_fire())
	rounds -= 1
	var refunded: int = clampi(capacity() - rounds, 0, DEFEAT_REFUND_ROUNDS) if defeat_refund else 0
	rounds += refunded
	if rounds == 0:
		reloading = true
		remaining = seconds()
	return refunded

func advance(delta: float) -> void:
	if not reloading:return
	remaining=maxf(0.0,remaining-delta)
	if remaining<=0.000000001:
		reloading=false;remaining=0.0;rounds=capacity()

func snapshot() -> Dictionary:
	var value: Dictionary = {"version":1,"instance_id":instance_id,"rounds":rounds,"reloading":reloading,"remaining":remaining}
	if not modification.is_empty():
		value.mod = modification
	return value

func restore(value: Dictionary) -> void:
	rounds=int(value.rounds);reloading=value.reloading;remaining=float(value.remaining)

static func parameters(gun: String, mod: String = "") -> Dictionary:
	var stock: Dictionary = CombatEquipment.magazine(gun)
	if mod.is_empty():
		return stock
	if gun == "carbine":
		return CARBINE_MODS.get(mod, {})
	if gun == "long_rifle":
		match mod:
			EXTENDED:
				return {"capacity": int(stock.capacity) + 2, "seconds": float(stock.seconds) + 0.35}
			QUICK:
				return {"capacity": maxi(1, int(stock.capacity) - 2), "seconds": maxf(0.60, float(stock.seconds) - 0.35)}
	return {}

static func problem(value: Variant, identity: String, gun: String, factor: float = 1.0, mod: String = "") -> String:
	var modified: bool = not mod.is_empty()
	if not value is Dictionary or value.size() != 5 + int(modified) \
			or not value.has_all(["version","instance_id","rounds","reloading","remaining"]):
		return "MAGAZINE_FIELDS"
	var setup: Dictionary = parameters(gun, mod)
	if not SurvivalContracts.integer(value.version,1,1) or value.instance_id != identity or setup.is_empty() \
			or (modified and (not value.get("mod") is String or value.mod != mod)):
		return "MAGAZINE_IDENTITY"
	if not SurvivalContracts.integer(value.rounds,0,setup.capacity) or not value.reloading is bool \
			or not SurvivalContracts.number(value.remaining) or value.remaining < 0 \
			or value.remaining > setup.seconds * factor:
		return "MAGAZINE_VALUES"
	if value.reloading!=(value.rounds==0) or value.reloading!=(value.remaining>0):return "MAGAZINE_PHASE"
	return ""
