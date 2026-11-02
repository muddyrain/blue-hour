class_name RunSave
extends RefCounted
## Disk boundary only. No scene objects, combat rules or implicit player paths.

const SCHEMA_VERSION: int = 5
const DefaultRules: CampRules = preload("res://src/features/camp/camp_rules.tres")
const MAX_BYTES: int = 1_048_576
const MAX_COUNTER: int = 1_000_000_000

var path: String
var diagnostic: String = ""
var snapshot: Dictionary = {}
var migrated_from: int = 0
var _battle_format: bool = false
var _survival_format: bool = false
var _rescue_format: bool = false
var _growth_format: bool = false
var _field_format: bool = false
var _trait_format: bool = false
var _training_format: bool = false
var _pool_format: bool = false
var _roster_format: bool = false
var _enemy_format: bool = false
var _quality_format: bool = false


func _init(save_path: String, battle_format: bool = false, survival_format: bool = false, rescue_format: bool = false, growth_format: bool = false, field_format: bool = false, trait_format: bool = false, training_format: bool = false, pool_format: bool = false, roster_format: bool = false, quality_format: bool = false, enemy_format: bool = false) -> void:
	path = ProjectSettings.globalize_path(save_path)
	_battle_format = battle_format
	_survival_format = survival_format
	_rescue_format = rescue_format
	_growth_format = growth_format
	_field_format = field_format
	_trait_format = trait_format
	_training_format = training_format
	_pool_format = pool_format
	_roster_format = roster_format
	_quality_format = quality_format
	_enemy_format = enemy_format


static func new_profile_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


static func validate(data: Variant) -> String:
	if not data is Dictionary:
		return "根数据必须是对象"
	if not data.has("schema_version") or not _integer(data.schema_version, 1, SCHEMA_VERSION):
		return "不支持的存档版本"
	var required: Array[String] = ["schema_version", "profile_id", "day", "cash", "crew", "settled_sorties", "last_settlement_id"]
	if data.schema_version >= 2:
		required.append_array(["food", "last_day"])
	if data.schema_version >= 3:
		required.append_array(["weapons", "loadout", "camp_spending"])
	if data.size() != required.size():
		return "存档字段不完整或包含未知字段"
	for key: String in required:
		if not data.has(key):
			return "缺少字段：" + key
	if not data.profile_id is String or data.profile_id.length() != 32 or not data.profile_id.is_valid_hex_number(false):
		return "存档身份无效"
	if not _integer(data.day, 2, MAX_COUNTER) or not _integer(data.cash, 0, MAX_COUNTER):
		return "天数或货币无效"
	if not _integer(data.settled_sorties, 0, MAX_COUNTER - 2) or data.day != data.settled_sorties + 2:
		return "结算次数与天数不一致"
	var expected: String = "" if data.settled_sorties == 0 else "%s:%d" % [data.profile_id, int(data.settled_sorties)]
	if not data.last_settlement_id is String or data.last_settlement_id != expected:
		return "结算标识不一致"
	if not data.crew is Array or data.crew.size() != 2:
		return "队员人数无效"
	var seen: Array[int] = []
	for member: Variant in data.crew:
		if not member is Dictionary or member.size() != (7 if data.schema_version >= 5 else (6 if data.schema_version == 4 else 2)) or not member.has("id") or not member.has("health"):
			return "队员字段无效"
		if not _integer(member.id, 1, 2) or int(member.id) in seen:
			return "队员身份重复或未知"
		if not _number(member.health) or member.health < 0.0 or member.health > 200.0:
			return "队员生命无效"
		seen.append(int(member.id))
		if data.schema_version >= 4:
			var member_problem: String = SurvivorRoster.validate(member, data)
			if not member_problem.is_empty():
				return member_problem
	if data.schema_version >= 3:
		var inventory_problem: String = WeaponInventory.validate(data)
		if not inventory_problem.is_empty():
			return inventory_problem
	if data.schema_version >= 5:
		for member: Dictionary in data.crew:
			var growth_problem: String = SurvivorGrowth.validate_member(member,data)
			if not growth_problem.is_empty():
				return growth_problem
		var duplicate_problem: String = SurvivorGrowth.validate_crew(data.crew)
		if not duplicate_problem.is_empty():
			return duplicate_problem
	if data.schema_version >= 2:
		if not _integer(data.food, 0, CampRules.FOOD_LIMIT):
			return "食物库存必须是合法非负整数"
		return _validate_day(data)
	return ""


static func _validate_day(data: Dictionary, maximum_member_id: int = 2) -> String:
	if not data.last_day is Dictionary:
		return "每日结算记录无效"
	var entry: Dictionary = data.last_day
	# Empty history is honest for new games and v1 migration: never invent past rations.
	if entry.is_empty():
		return "缺少维修支出对应的归航记录" if int(data.get("camp_spending", 0)) != 0 else ""
	var numbers: Array[String] = ["day", "food_before", "food_found", "food_stored", "food_overflow",
		"ration_per_member", "food_required", "food_consumed", "food_shortage", "food_after",
		"cash_before", "cash_gained", "cash_after"]
	if entry.size() != numbers.size() + 3:
		return "每日结算字段不完整"
	for key: String in numbers:
		if not entry.has(key) or not _integer(entry[key], 0, MAX_COUNTER):
			return "每日结算数字无效：" + key
	if not entry.get("settlement_id") is String or not entry.get("evacuated") is bool or not entry.get("ration_member_ids") is Array:
		return "每日结算身份或口粮名单无效"
	var ids: Array[int] = []
	for member_id: Variant in entry.ration_member_ids:
		if not _integer(member_id, 1, maximum_member_id) or int(member_id) in ids:
			return "口粮成员身份重复或未知"
		ids.append(int(member_id))
	if entry.ration_per_member < 1 or entry.food_required != ids.size() * entry.ration_per_member:
		return "口粮需求与名单不一致"
	if entry.day != data.day - 1 or entry.settlement_id != data.last_settlement_id or data.settled_sorties == 0:
		return "每日结算与存档身份不一致"
	if (entry.food_stored != mini(int(entry.food_found), CampRules.FOOD_LIMIT - int(entry.food_before))
			or entry.food_stored + entry.food_overflow != entry.food_found
			or entry.food_consumed != mini(int(entry.food_before + entry.food_stored), int(entry.food_required))
			or entry.food_required - entry.food_consumed != entry.food_shortage
			or entry.food_before + entry.food_stored - entry.food_consumed != entry.food_after
			or entry.food_after != data.food
			or entry.cash_before + entry.cash_gained != entry.cash_after
			or entry.cash_after - int(data.get("camp_spending", 0)) != data.cash):
		return "每日资源收支不一致"
	if not entry.evacuated and (entry.food_found != 0 or entry.cash_gained != 0):
		return "未撤离不能带回资源"
	return ""


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


func load_save(backup: bool = false) -> Error:
	if transaction_namespace(path) or DirAccess.dir_exists_absolute(path + ".txn") or FileAccess.file_exists(path + ".txn"):
		snapshot = {}
		return _fail(ERR_UNAVAILABLE, "此营地要求事务协调；请使用已登记旅程入口，原件保留")
	var source: String = path + ".bak" if backup else path
	var result: Dictionary = _read(source)
	diagnostic = result.message
	snapshot = result.data.duplicate(true)
	migrated_from = int(result.get("migration", 0))
	return result.error as Error


func has_files() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


func read_v5_exact() -> Dictionary:
	if _battle_format or _survival_format or _rescue_format or _growth_format or _field_format or _trait_format or _training_format or _pool_format or _roster_format or _quality_format or _enemy_format:
		return {"error":ERR_INVALID_DATA,"message":"隔离生存格式不是v5","data":{}}
	return read_transaction_exact()


func read_transaction_exact() -> Dictionary:
	var result: Dictionary = _read(path)
	if result.error == OK and int(result.get("migration", 0)) != 0:
		return {"error":ERR_INVALID_DATA, "message":"事务适配器只接受现有v5；旧档须单独审核", "data":{}}
	return result


func save(data: Dictionary, allow_invalid_replacement: bool = false, writer: ProgressWriter = null, transition_hook: Callable = Callable()) -> Error:
	var owner: ProgressWriter = writer if writer != null else ProgressWriter.new(path)
	var error: Error = OK if writer != null and writer.owns(path) else (ERR_UNAUTHORIZED if writer != null else owner.acquire())
	if error != OK:
		return _fail(error, "进度写入正被占用或无法确认写者；原档保留，可重试。" + owner.reason)
	if transition_hook.is_valid() and writer == null:
		owner.release()
		return _fail(ERR_UNAUTHORIZED, "事务写入钩子要求已持有写者能力")
	if writer == null and (transaction_namespace(path) or DirAccess.dir_exists_absolute(path + ".txn") or FileAccess.file_exists(path + ".txn")):
		error = _fail(ERR_UNAVAILABLE, "此营地只能通过绑定事务协调器写入")
	else:
		error = _save_owned(data, allow_invalid_replacement, transition_hook)
	if writer == null:
		owner.release()
	return error


static func transaction_namespace(save_path: String) -> bool:
	var file_name: String = save_path.replace("\\", "/").get_file().to_lower()
	return file_name == "run.enemy-v1.json" or file_name.begins_with("run.enemy-v1.json.") or file_name == "run.weapon-quality-v1.json" or file_name.begins_with("run.weapon-quality-v1.json.") or file_name == "run.roster-v1.json" or file_name.begins_with("run.roster-v1.json.") or file_name == "run.rescue-pool-v1.json" or file_name.begins_with("run.rescue-pool-v1.json.") or file_name == "run.training-v1.json" or file_name.begins_with("run.training-v1.json.") or file_name == "run.trait-v1.json" or file_name.begins_with("run.trait-v1.json.") or file_name == "run.field-join-v1.json" or file_name.begins_with("run.field-join-v1.json.") or file_name == "run.growth-v1.json" or file_name.begins_with("run.growth-v1.json.") or file_name == "run.rescue-v1.json" or file_name.begins_with("run.rescue-v1.json.") or file_name == "run.txn-v1.json" or file_name.begins_with("run.txn-v1.json.") or file_name == "run.battle-v1.json" or file_name.begins_with("run.battle-v1.json.") or file_name == "run.survival-v1.json" or file_name.begins_with("run.survival-v1.json.")


func _save_owned(data: Dictionary, allow_invalid_replacement: bool = false, transition_hook: Callable = Callable()) -> Error:
	diagnostic = _format_problem(data)
	if not diagnostic.is_empty():
		return ERR_INVALID_DATA
	if not _battle_format and not _survival_format and not _rescue_format and not _growth_format and not _field_format and not _trait_format and not _training_format and not _pool_format and not _roster_format and not _quality_format and not _enemy_format and data.schema_version != SCHEMA_VERSION:
		return _fail(ERR_INVALID_DATA, "写入只支持v5；旧版请先读取迁移")
	var serialized: String = JSON.stringify(data, "\t", true, true) + "\n"
	if serialized.to_utf8_buffer().size() > MAX_BYTES:
		return _fail(ERR_INVALID_DATA, "库存存档超过工程大小保护上限；当前营地保留在内存")
	var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return _fail(error, "无法建立存档目录")
	# Unique staging files leave interrupted/foreign staging bytes untouched.
	var temporary: String = path + ".tmp-" + new_profile_id()
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail(FileAccess.get_open_error(), "无法写入临时存档")
	file.store_string(serialized)
	file.flush()
	error = file.get_error()
	file.close()
	var checked: Dictionary = _read(temporary)
	if error != OK or checked.error != OK or FileAccess.get_file_as_string(temporary) != serialized:
		DirAccess.remove_absolute(temporary)
		return _fail(ERR_FILE_CORRUPT, "临时存档写入校验失败，旧档未改")
	var current: Dictionary = _read(path)
	# Only a verified save boundary may archive legacy bytes; reads never write.
	if current.error == OK and int(current.get("migration", 0)) > 0:
		error = _retain_legacy(path, int(current.migration))
	if error == OK and FileAccess.file_exists(path + ".bak"):
		var legacy_backup: Dictionary = _read(path + ".bak")
		if legacy_backup.error == OK and int(legacy_backup.get("migration", 0)) > 0:
			error = _retain_legacy(path + ".bak", int(legacy_backup.migration))
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return _fail(error, "无法保留旧版原件，旧档未改")
	var rollback: String = ""
	var old_backup: String = ""
	var discard_backup: bool = false
	if current.error == OK:
		# At every step a validated current or backup remains. This is not fsync.
		if FileAccess.file_exists(path + ".bak"):
			var previous: Dictionary = _read(path + ".bak")
			old_backup = path + ".bak.rejected-" + new_profile_id()
			discard_backup = previous.error == OK
			error = DirAccess.rename_absolute(path + ".bak", old_backup)
			if error != OK:
				DirAccess.remove_absolute(temporary)
				return _fail(error, "无法保留备份，旧档未改")
		error = DirAccess.rename_absolute(path, path + ".bak")
		rollback = path + ".bak"
	elif current.error != ERR_FILE_NOT_FOUND:
		if not allow_invalid_replacement:
			DirAccess.remove_absolute(temporary)
			return _fail(ERR_FILE_CORRUPT, "旧档异常，需先明确选择备份或新游戏；原字节已保留")
		rollback = path + ".rejected-" + new_profile_id()
		error = DirAccess.rename_absolute(path, rollback)
	if error == OK and transition_hook.is_valid():
		error = int(transition_hook.call("after_base_to_backup")) as Error
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		if not rollback.is_empty() and not FileAccess.file_exists(path) and FileAccess.file_exists(rollback):
			DirAccess.rename_absolute(rollback, path)
		if not old_backup.is_empty() and not FileAccess.file_exists(path + ".bak"):
			DirAccess.rename_absolute(old_backup, path + ".bak")
		DirAccess.remove_absolute(temporary)
		return _fail(error, "替换存档失败；保留旧档/备份，当前营地仍在内存中")
	if discard_backup:
		DirAccess.remove_absolute(old_backup)
	snapshot = checked.data.duplicate(true)
	migrated_from = 0
	diagnostic = "已保存营地进度"
	return OK


func _read(source: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(source):
		return {"error": ERR_FILE_CANT_OPEN, "message": "存档路径是目录", "data": {}}
	if not FileAccess.file_exists(source):
		return {"error": ERR_FILE_NOT_FOUND, "message": "未找到存档", "data": {}}
	var file: FileAccess = FileAccess.open(source, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error(), "message": "无法读取存档", "data": {}}
	if file.get_length() > MAX_BYTES or file.get_length() == 0:
		file.close()
		return {"error": ERR_FILE_CORRUPT, "message": "存档为空或超过大小上限", "data": {}}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	var content: String = bytes.get_string_from_utf8()
	if content.to_utf8_buffer() != bytes:
		return {"error": ERR_FILE_CORRUPT, "message": "存档不是有效 UTF-8", "data": {}}
	var parser: JSON = JSON.new()
	if parser.parse(content) != OK:
		return {"error": ERR_PARSE_ERROR, "message": "JSON 无效（第 %d 行）" % parser.get_error_line(), "data": {}}
	var problem: String = _format_problem(parser.data)
	if not problem.is_empty():
		return {"error": ERR_INVALID_DATA, "message": problem, "data": {}}
	if _battle_format or _survival_format or _rescue_format or _growth_format or _field_format or _trait_format or _training_format or _pool_format or _roster_format or _quality_format or _enemy_format:
		return {"error":OK,"message":"隔离生存格式校验通过，无旧档迁移","data":parser.data,"migration":0}
	# Godot JSON numbers are floats; normalize only after strict range/integer checks.
	var data: Dictionary = parser.data
	var migration: int = int(data.schema_version) if int(data.schema_version) < SCHEMA_VERSION else 0
	if data.schema_version == 1:
		data.food = DefaultRules.v1_migration_food
		data.last_day = {}
	if migration > 0:
		if migration < 3:
			WeaponInventory.initialize(data, "migration-v%d" % migration)
		if migration < 4:
			SurvivorRoster.initialize(data.crew)
		else:
			SurvivorGrowth.initialize(data.crew)
		data.schema_version = SCHEMA_VERSION
	for key: String in ["schema_version", "day", "cash", "settled_sorties"]:
		data[key] = int(data[key])
	for member: Dictionary in data.crew:
		member.id = int(member.id)
		member.health = float(member.health)
		member.service.sorties = int(member.service.sorties)
		member.service.kills = int(member.service.kills)
		member.service.damage_received = float(member.service.damage_received)
		SurvivorGrowth.normalize(member.growth)
	data.food = int(data.food)
	data.camp_spending = int(data.camp_spending)
	for entry: Dictionary in data.loadout:
		entry.member_id = int(entry.member_id)
	if not data.last_day.is_empty():
		for key: String in data.last_day:
			if data.last_day[key] is float:
				data.last_day[key] = int(data.last_day[key])
		var members: Array[int] = []
		for member_id: Variant in data.last_day.ration_member_ids:
			members.append(int(member_id))
		data.last_day.ration_member_ids = members
	var message: String = "存档校验通过"
	if migration > 0:
		message = "旧版v%d：队员档案使用迁移默认呼号；战绩从v4首次归航开始记录，不补写历史经验。" % migration
		if migration == 4:
			message = "v4档已读：呼号、战绩、钱粮和装备保留；成长状态待校准，行动明细从本版本实际出击开始记录。"
		if migration < 3:
			message += "原有默认两枪初始化为独立实例，非历史战利品。"
		if migration == 1:
			message += "食物初始化为%d（迁移默认值，非历史库存）。" % DefaultRules.v1_migration_food
	return {"error": OK, "message": message, "data": data, "migration":migration}


func _format_problem(data: Variant) -> String:
	if _enemy_format:
		var name: String = path.replace("\\","/").get_file().to_lower()
		if name!="run.enemy-v1.json" and not name.begins_with("run.enemy-v1.json."):
			return "ENEMY_NAMESPACE_REQUIRED"
		return EnemyState.problem(data) if data is Dictionary else "ENEMY_FORMAT"
	if _quality_format:
		var name: String = path.replace("\\","/").get_file().to_lower()
		if name!="run.weapon-quality-v1.json" and not name.begins_with("run.weapon-quality-v1.json."):
			return "WEAPON_QUALITY_NAMESPACE_REQUIRED"
		return WeaponState.problem(data) if data is Dictionary else "WEAPON_QUALITY_FORMAT"
	if _roster_format:
		var name: String = path.replace("\\","/").get_file().to_lower()
		if name!="run.roster-v1.json" and not name.begins_with("run.roster-v1.json."):
			return "ROSTER_NAMESPACE_REQUIRED"
		return RosterState.problem(data) if data is Dictionary else "ROSTER_FORMAT"
	if _pool_format:
		var name: String = path.replace("\\","/").get_file().to_lower()
		if name!="run.rescue-pool-v1.json" and not name.begins_with("run.rescue-pool-v1.json."):
			return "POOL_NAMESPACE_REQUIRED"
		return TrainingState.family_problem(data,true) if data is Dictionary else "POOL_FORMAT"
	if _training_format:
		var name: String = path.replace("\\","/").get_file().to_lower()
		if name != "run.training-v1.json" and not name.begins_with("run.training-v1.json."):
			return "TRAINING_NAMESPACE_REQUIRED"
		return TrainingState.problem(data) if data is Dictionary else "TRAINING_FORMAT"
	if _trait_format:
		var name: String = path.replace("\\","/").get_file().to_lower()
		if name != "run.trait-v1.json" and not name.begins_with("run.trait-v1.json."):
			return "TRAIT_NAMESPACE_REQUIRED"
		return TraitState.problem(data) if data is Dictionary else "TRAIT_FORMAT"
	if _field_format:
		var name: String = path.replace("\\","/").get_file().to_lower()
		if name != "run.field-join-v1.json" and not name.begins_with("run.field-join-v1.json."):
			return "FIELD_JOIN_NAMESPACE_REQUIRED"
		return FieldJoinState.problem(data) if data is Dictionary else "FIELD_JOIN_FORMAT"
	if _growth_format:
		var name: String = path.replace("\\","/").get_file().to_lower()
		if name != "run.growth-v1.json" and not name.begins_with("run.growth-v1.json."):
			return "GROWTH_NAMESPACE_REQUIRED"
		return GrowthState.problem(data) if data is Dictionary else "GROWTH_FORMAT"
	if _rescue_format:
		var name: String = path.replace("\\","/").get_file().to_lower()
		if name != "run.rescue-v1.json" and not name.begins_with("run.rescue-v1.json."):
			return "RESCUE_NAMESPACE_REQUIRED"
		return RescueState.problem(data) if data is Dictionary else "RESCUE_FORMAT"
	if _survival_format:
		var file_name: String = path.replace("\\", "/").get_file().to_lower()
		if file_name != "run.survival-v1.json" and not file_name.begins_with("run.survival-v1.json."):
			return "SURVIVAL_NAMESPACE_REQUIRED"
		return SurvivalState.problem(data) if data is Dictionary else "SURVIVAL_FORMAT"
	if not _battle_format:
		return validate(data)
	if path.replace("\\","/").get_file().to_lower() != "run.battle-v1.json" and not path.replace("\\","/").get_file().to_lower().begins_with("run.battle-v1.json."):
		return "BATTLE_NAMESPACE_REQUIRED"
	return BattleState.problem(data) if data is Dictionary else "BATTLE_FORMAT"


func _retain_legacy(source: String, version: int) -> Error:
	var digest: String = FileAccess.get_sha256(source)
	var archive: String = path + ".v%d-" % version + digest + ".json"
	if FileAccess.file_exists(archive):
		return OK if FileAccess.get_sha256(archive) == digest else ERR_FILE_CORRUPT
	var error: Error = DirAccess.copy_absolute(source, archive)
	if error != OK:
		return error
	return OK if FileAccess.get_sha256(archive) == digest else ERR_FILE_CORRUPT


func _fail(error: Error, message: String) -> Error:
	diagnostic = "%s（错误 %d）" % [message, error]
	return error
