# M8-BUILD-01 WIN-R1 shared integration contract

Baseline main d209d5ef430f3edce2f4393b49f103cbb16c8cd0 includes #11 merge 135f01ff89a3e456f12a5390984fad9a0ddadd96 and #12 merge d209d5e. Their trees equal the reviewed heads; development integration, not production approval.

A owns all existing entrypoints, actors, expedition, snapshots, transactions, campaign, growth, version dispatch and final acceptance. B owns only src/features/items/ and tests/build_items.gd. C owns only src/features/basic_support/ and tests/basic_support.gd. Independent worktrees/caches/.local profiles. No agent pushes except A.

## Frozen API B

BuildItems extends RefCounted, pure static methods, no disk/global RNG:
- definitions() -> Dictionary keyed by six exact WIN-R1 IDs; name/effect/factor.
- ids() -> Array[String] stable definition order.
- drop(context: Dictionary, owned: Array) -> Array[String]. Context has run_id, seed, day, action_id, site_id, version:1; stable local hash/RNG only, excludes owned, <=2 distinct IDs. Equipping never affects drop.
- problem(owned: Variant, slots: Variant) -> String. Owned is Array[String], unique known IDs; slots exactly two Strings (empty allowed), unique nonempty, subset owned. Unknown/missing fields rejected by A's enclosing version.
- factors(slots: Array) -> Dictionary with damage/reload/move/work/blast/heal (all 1.0 by default). PROJECT_TEMP: 1.20/.75/1.15/.75/1.30/1.50 respectively.
- BuildItemsPanel extends VBoxContainer; signal requested(slot: int, item_id: String); present(owned: Array, slots: Array, saved: bool, enabled: bool=true) -> void. Does not optimistically mutate authoritative state. At least three items can replace either slot.

## Frozen API C

BasicSupport extends RefCounted, pure request/cooldown component:
- POLICY {heal_amount:40.0,heal_cooldown:30.0,airstrike_range:320.0,airstrike_radius:90.0,airstrike_damage:72.0,airstrike_cooldown:20.0} PROJECT_TEMP.
- configure(binding: Dictionary) -> void. Binding is original RunTransaction token.
- snapshot() -> Dictionary {version:1,binding:Dictionary,sequence:int,cooldowns:{heal:float,airstrike:float},accepted:Array[Dictionary]}.
- restore(value: Dictionary) -> void; static problem(value: Variant, binding: Dictionary) -> String.
- advance(delta: float, active: bool) -> void (authority simulation only).
- plan_heal(members: Array[Dictionary], factor: float=1.0) -> Dictionary. Rows member_id,health,max_health,present; returns {} or {member_id,amount}, lowest health ratio then ID.
- request(kind: String, payload: Dictionary) -> Dictionary. Returns {} if cooldown; otherwise {id,kind,payload}, id token transaction_id + ':basic:' + sequence. Pure pending planning; does not consume sequence/cooldown.
- accept(request: Dictionary, facts: Dictionary) -> bool. Only A calls after authoritative durable acceptance. Dedupe same accepted ID; append {id,kind,payload,facts}, advance sequence once, cooldown once. Restored exact cooldowns; no charges.
- BasicSupportPanel extends HBoxContainer; signals heal_requested(), airstrike_requested(); present(heal_text:String,airstrike_text:String,heal_enabled:bool,airstrike_enabled:bool) -> void.
- BasicSupportAim extends Node2D; present(point:Vector2,radius:float,legal:bool,aiming:bool) -> void; optional read-only impact animation API documented on delivery. No direct actor/HP/XP/save mutation.
C may add pure airstrike caller/target planning helpers with input dictionaries/LOS callbacks; A supplies actual navigation/LOS.

## A persistence/authority shape

New-only journey.build={version:1,owned:Array[String],slots:[String,String],sources:Array[Dictionary]}; each acquisition source binds item ID, action/site and original departure-owned context. Old journey without build remains exact old mode. New generated version7 adds build {version:1,run_id,owned,slots,drop_context,drops,policy}; original V6 projection preserved and authenticated separately. New rules data_version8, world10, new compatibility fingerprint includes definitions/support policy/frozen configuration. Old V6/rules7/world9 keeps old authentication.

Healing owner records accepted actual positive healing in original transaction before exposing HP/cooldown; current HP + cumulative actual damage = departure HP + accepted actual healing. No negative damage or checkpoint relaxation for old versions. Atomic support acceptance uses original RunTransaction journal; failed commit pauses/retries original request and leaves original effective state. Deaths never reverse.

Airstrike is an explicit ability defeat branch: kind defeat, source ability, ability_id airstrike_v1, request_id, enemy_id, at_ms, member_id (no weapon/instance fabrication). Original gun receipt shape unchanged. Preflight all targets, capacity, request/source then stable enemy order. Boss defeat stores its own exact lethal event; dead boss cancels pending/handling as R1. A routes service/XP through original owners, 10XP per lethal event credited to frozen caller on surviving return.

Acquisition only on real completed equipment cash site; carried-only until original confirmed return. Freeze departure-owned context and slots in original rules; original camp editing owner persists two-slot changes. No second writer, no new reward settlement. Work factor affects search/outdoor recovery only. Apply original weapon/Trait values then item factor once, including rescued members.

Q heal, E aim, left confirm, right/Esc cancel, UI blocks world inputs. New action ready; paused/arrival/departure/frozen/finished stop clocks. Active and gathering advance. No max uses. Not Special Power.
