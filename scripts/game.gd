extends Node
## Global game state, input map, noise propagation and the player's thoughts (subtitles).

signal subtitle(text: String, duration: float)
## A sound in the world entities can hear. radius = metres it carries in open air.
signal noise(pos: Vector3, radius: float, source: String)
signal power_changed(on: bool)
signal blackout_changed(active: bool)
signal player_died(cause: String)
## Wrong breaker pattern pulled (before the blackout starts).
signal wrong_lever
signal escaped
signal note_read(id: String)

enum State { MENU, PLAYING, PAUSED, DEAD, ESCAPED }

var state: State = State.MENU
var seed_value: int = 0
## Puzzle seed for this run; -1 = derive from seed_value. Retry keeps the layout
## (seed_value) but rolls a new puzzle_seed: new clues, new code, new spawns.
var puzzle_seed := -1
var player: Node3D
var level: Node3D
var power_on := false
var blackout := false
var run_start_msec := 0
const SETTINGS_PATH := "user://settings.cfg"
var mouse_sensitivity := 0.0022
var subtitles_enabled := true
var master_volume := 1.0  # linear 0..1
var fov := 78.0

var _lines := {}
var _said := {}

## Dynamic resolution: keeps frame rate >= ~30 by scaling the 3D render
## resolution (FSR upscaled; UI stays native). Target band 40-55 fps.
const RES_TARGET_PIXELS := 1_600_000.0
const RES_MIN := 0.45
const RES_MAX := 1.0
var render_scale := 1.0
var _fps_acc := 0.0
var _fps_frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lines.json"))
	if parsed is Dictionary:
		_lines = parsed
	else:
		push_error("data/lines.json failed to parse")
	new_seed()
	load_settings()
	get_viewport().size_changed.connect(_initial_scale)
	_initial_scale()


func _initial_scale() -> void:
	var px := Vector2(get_viewport().size)
	render_scale = clampf(sqrt(RES_TARGET_PIXELS / maxf(px.x * px.y, 1.0)), RES_MIN, RES_MAX)
	_apply_scale()


func _apply_scale() -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = render_scale
	vp.fsr_sharpness = 0.35


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	_fps_acc += delta
	_fps_frames += 1
	if _fps_acc < 1.0:
		return
	var fps := _fps_frames / _fps_acc
	_fps_acc = 0.0
	_fps_frames = 0
	var s := render_scale
	if fps < 33.0:
		s -= 0.12
	elif fps < 40.0:
		s -= 0.05
	elif fps > 56.0:
		s += 0.04
	s = clampf(s, RES_MIN, RES_MAX)
	if not is_equal_approx(s, render_scale):
		render_scale = s
		_apply_scale()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		mouse_sensitivity = cfg.get_value("input", "sensitivity", mouse_sensitivity)
		subtitles_enabled = cfg.get_value("ui", "subtitles", subtitles_enabled)
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
		fov = cfg.get_value("video", "fov", fov)
	apply_volume()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "sensitivity", mouse_sensitivity)
	cfg.set_value("ui", "subtitles", subtitles_enabled)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "fov", fov)
	cfg.save(SETTINGS_PATH)


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


func apply_fov() -> void:
	if player and is_instance_valid(player):
		player.set_fov(fov)


## Text of a line from data/lines.json (no subtitle).
func line(id: String) -> String:
	return _lines.get(id, "")


## Called when a Smiler is close to the player in the dark.
func smiler_near_dark() -> void:
	say("whisper_quiet")


func death_line(cause: String) -> String:
	var t := line("death_" + cause)
	return t if t != "" else "You were found."


func new_seed() -> void:
	seed_value = randi() % 1000000


func start_run() -> void:
	power_on = false
	blackout = false
	_said.clear()
	run_start_msec = Time.get_ticks_msec()
	state = State.PLAYING
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func elapsed_text() -> String:
	var s := (Time.get_ticks_msec() - run_start_msec) / 1000
	return "%d:%02d" % [s / 60, s % 60]


func is_playing() -> bool:
	return state == State.PLAYING


## The character's thought as a subtitle (no voice audio). once=true: at most once per run.
func say(id: String, once := true) -> void:
	if once and _said.has(id):
		return
	if not _lines.has(id):
		push_error("unknown line " + id)
		return
	_said[id] = true
	var text: String = _lines[id]
	if subtitles_enabled:
		subtitle.emit(text, 1.6 + text.length() * 0.06)


func emit_noise(pos: Vector3, radius: float, source: String) -> void:
	noise.emit(pos, radius, source)


func set_power(on: bool) -> void:
	power_on = on
	power_changed.emit(on)


func set_blackout(active: bool) -> void:
	blackout = active
	blackout_changed.emit(active)


func kill_player(cause: String) -> void:
	if state != State.PLAYING:
		return
	state = State.DEAD
	player_died.emit(cause)


func win() -> void:
	if state != State.PLAYING:
		return
	state = State.ESCAPED
	escaped.emit()


func _setup_input() -> void:
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("crouch", [KEY_CTRL, KEY_C])
	_bind_keys("interact", [KEY_E])
	_bind_keys("flashlight", [KEY_F])
	_bind_keys("throw", [KEY_G])
	_bind_keys("reload", [KEY_R])
	_bind_keys("journal", [KEY_TAB, KEY_J])
	_bind_keys("pause", [KEY_ESCAPE, KEY_P])
	_bind_mouse("interact", MOUSE_BUTTON_LEFT)
	_bind_mouse("throw", MOUSE_BUTTON_RIGHT)


func _bind_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _bind_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
