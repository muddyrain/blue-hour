class_name WeaponMagazine
extends RefCounted
## PROJECT_TEMP V1. One equipped instance, simulation time only, infinite reserve.
const BUILD: String = "M7-WEAPON-01-1"
const PARAMETERS: Dictionary = WeaponDefinition.MAGAZINES
const DEFEAT_REFUND_ROUNDS: int = 1 # PROJECT_TEMP M33

var instance_id: String
var weapon_id: String
var rounds: int
var reloading: bool = false
var remaining: float = 0.0
var reload_factor: float = 1.0

func _init(identity: String, gun: String) -> void:
	instance_id=identity;weapon_id=gun;rounds=capacity()

func capacity() -> int:
	return CombatEquipment.magazine(weapon_id).capacity

func seconds() -> float:
	return CombatEquipment.magazine(weapon_id).seconds * reload_factor

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
	return {"version":1,"instance_id":instance_id,"rounds":rounds,"reloading":reloading,"remaining":remaining}

func restore(value: Dictionary) -> void:
	rounds=int(value.rounds);reloading=value.reloading;remaining=float(value.remaining)

static func problem(value: Variant, identity: String, gun: String, factor: float = 1.0) -> String:
	if not value is Dictionary or value.size()!=5 or not value.has_all(["version","instance_id","rounds","reloading","remaining"]):return "MAGAZINE_FIELDS"
	if not SurvivalContracts.integer(value.version,1,1) or value.instance_id!=identity or CombatEquipment.magazine(gun).is_empty():return "MAGAZINE_IDENTITY"
	if not SurvivalContracts.integer(value.rounds,0,CombatEquipment.magazine(gun).capacity) or not value.reloading is bool or not SurvivalContracts.number(value.remaining) or value.remaining<0 or value.remaining>CombatEquipment.magazine(gun).seconds*factor:return "MAGAZINE_VALUES"
	if value.reloading!=(value.rounds==0) or value.reloading!=(value.remaining>0):return "MAGAZINE_PHASE"
	return ""
