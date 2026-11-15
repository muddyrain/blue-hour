class_name B1AudioService
extends Node
## Receives completed events only. No game rules, global buses or Autoloads.

signal diagnosed(message: String)

const WORLD_VOICES: int = 6
const UI_VOICES: int = 2
const COMBAT_VOICES: int = 4
# PROJECT_TEMP mix: eight 0.55-peak assets sum to at most 0.88 (-1.1 dBFS).
const VOICE_GAIN: float = 0.20
const CUES: Dictionary = {
	&"ui_confirm": {"channel": &"ui", "gap_ms": 60},
	&"ui_back": {"channel": &"ui", "gap_ms": 60},
	&"fire": {"channel": &"world", "gap_ms": 45},
	&"melee_swing": {"channel": &"world", "gap_ms": 75},
	&"hit": {"channel": &"world", "gap_ms": 55},
	&"survivor_hit": {"channel": &"world", "gap_ms": 120},
	&"collect_complete": {"channel": &"world", "gap_ms": 150, "priority": 1},
	&"bus_start": {"channel": &"world", "gap_ms": 350, "priority": 2},
	&"bus_board": {"channel": &"world", "gap_ms": 180, "priority": 2},
	&"bus_depart": {"channel": &"world", "gap_ms": 350, "priority": 2},
	&"screamer_warning": {"channel": &"world", "gap_ms": 400, "priority": 3},
	&"toxic_warning": {"channel": &"world", "gap_ms": 400, "priority": 3},
	&"burst_warning": {"channel": &"world", "gap_ms": 400, "priority": 3},
	&"hound_warning": {"channel": &"world", "gap_ms": 400, "priority": 3},
	&"nightfall": {"channel": &"world", "gap_ms": 1000, "priority": 3},
}

var _preferences: AudioPreferences
var _asset_root: String
var _streams: Dictionary[StringName, AudioStream] = {}
var _ui_players: Array[AudioStreamPlayer] = []
var _world_players: Array[AudioStreamPlayer] = []
var _last_played: Dictionary[StringName, int] = {}
var _warned: Dictionary[StringName, bool] = {}
var _world_paused: bool = false
var _closed: bool = false


func _init(preferences: AudioPreferences, asset_root: String = "res://assets/audio/b1") -> void:
	_preferences = preferences
	_asset_root = asset_root
	process_mode = Node.PROCESS_MODE_ALWAYS
	for cue: StringName in CUES:
		var path: String = asset_root.path_join(String(cue) + ".wav")
		if ResourceLoader.exists(path, "AudioStreamWAV"):
			var stream: AudioStream = load(path) as AudioStream
			if stream != null:
				_streams[cue] = stream


func _ready() -> void:
	if _closed:
		return
	_make_players(_world_players, WORLD_VOICES, "World")
	_make_players(_ui_players, UI_VOICES, "Ui")
	for cue: StringName in CUES:
		if not _streams.has(cue):
			_warn_once(cue, "Missing audio resource: " + _asset_root.path_join(String(cue) + ".wav"))
	_preferences.changed.connect(_apply_preferences)
	_apply_preferences()


func _exit_tree() -> void:
	shutdown()


func play_ui(cue: StringName) -> bool:
	return _play(cue, &"ui", _ui_players)


func play_world(cue: StringName) -> bool:
	if _world_paused:
		return false
	return _play(cue, &"world", _world_players)


func set_world_paused(value: bool) -> void:
	_world_paused = value
	for player: AudioStreamPlayer in _world_players:
		player.stream_paused = value


func stop_world() -> void:
	for player: AudioStreamPlayer in _world_players:
		player.stop()
	# Stopping is not resuming. The caller sets the next sortie's pause state.
	for cue: StringName in CUES:
		if CUES[cue]["channel"] == &"world":
			_last_played.erase(cue)


func shutdown() -> void:
	if _closed:
		return
	_closed = true
	stop_world()
	for player: AudioStreamPlayer in _world_players + _ui_players:
		player.stop()
		player.stream = null
	if _preferences.changed.is_connected(_apply_preferences):
		_preferences.changed.disconnect(_apply_preferences)
	_streams.clear()
	_last_played.clear()


func available_cues() -> Array[StringName]:
	return _streams.keys()


func _make_players(players: Array[AudioStreamPlayer], count: int, prefix: String) -> void:
	for index: int in range(count):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = prefix + str(index)
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.max_polyphony = 1
		add_child(player)
		players.append(player)


func _apply_preferences() -> void:
	var state: Dictionary = _preferences.snapshot()
	var master: float = 0.0 if state["muted"] else float(state["master_volume"])
	for player: AudioStreamPlayer in _world_players:
		player.volume_linear = master * float(state["sfx_volume"]) * VOICE_GAIN
		if player.volume_linear <= 0.0:
			player.stop()
	for player: AudioStreamPlayer in _ui_players:
		player.volume_linear = master * float(state["ui_volume"]) * VOICE_GAIN
		if player.volume_linear <= 0.0:
			player.stop()


func _play(cue: StringName, channel: StringName, players: Array[AudioStreamPlayer]) -> bool:
	if _closed or not is_inside_tree():
		return false
	if not CUES.has(cue):
		# One diagnostic for arbitrary IDs prevents unbounded per-ID bookkeeping.
		_warn_once(&"unknown_cue", "Unknown cue: " + String(cue))
		return false
	if CUES[cue]["channel"] != channel or not _streams.has(cue):
		_warn_once(cue, "Unavailable cue or wrong channel: " + String(cue))
		return false
	# Silent requests consume neither a voice nor the retrigger interval.
	if players.is_empty() or players[0].volume_linear <= 0.0:
		return false
	var now: int = Time.get_ticks_msec()
	if now - _last_played.get(cue, -100000) < int(CUES[cue]["gap_ms"]):
		return false
	var priority: int = int(CUES[cue].get("priority", 0))
	var player: AudioStreamPlayer = _voice(players, channel, priority)
	if player == null:
		return false
	player.stream = _streams[cue]
	player.stream_paused = false
	player.set_meta(&"priority", priority)
	player.play()
	_last_played[cue] = now
	return true


func _voice(players: Array[AudioStreamPlayer], channel: StringName, priority: int) -> AudioStreamPlayer:
	# Two world slots stay free of routine combat. Alerts can also use spare combat slots.
	if channel == &"world" and priority > 0:
		for index: int in range(COMBAT_VOICES, players.size()):
			if not players[index].playing:
				return players[index]
	var limit: int = COMBAT_VOICES if channel == &"world" and priority == 0 else players.size()
	for index: int in range(limit):
		if not players[index].playing:
			return players[index]
	if priority > 0:
		for player: AudioStreamPlayer in players:
			if int(player.get_meta(&"priority", 0)) < priority:
				return player
	# No queue or new nodes. A full set of equal-priority alerts coalesces by dropping newest.
	return null


func _warn_once(key: StringName, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	print("BH_AUDIO " + message)
	diagnosed.emit(message)
