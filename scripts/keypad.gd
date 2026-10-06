extends Node3D
## Six-digit keypad beside the exit door. Dead until power is restored; then its
## screen shows the six symbols in the order the code must be entered.
## Three wrong codes: alarm that every entity hears, 25 s lockout.

const MAX_TRIES := 3
const LOCKOUT := 25.0

var puzzle: Puzzle
var door: Node3D
var entry := ""
var tries := 0
var _locked := false
var _done := false
var _screen_lbl: Label3D
var _symbols: Array[Sprite3D] = []
var _led: StandardMaterial3D
var _screen_mat: StandardMaterial3D


func _ready() -> void:
	var housing := StandardMaterial3D.new()
	housing.albedo_color = Color(0.18, 0.19, 0.2)
	housing.metallic = 0.6
	housing.roughness = 0.45
	_box(Vector3(0.17, 0.27, 0.035), Vector3(0, 0, 0.0175), housing)
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = Color(0.02, 0.03, 0.02)
	_screen_mat.roughness = 0.15
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color(0.1, 0.5, 0.25)
	_screen_mat.emission_energy_multiplier = 0.0
	_box(Vector3(0.14, 0.06, 0.004), Vector3(0, 0.09, 0.036), _screen_mat)
	_led = StandardMaterial3D.new()
	_led.albedo_color = Color(0.1, 0.02, 0.02)
	_led.emission_enabled = true
	_led.emission = Color(1, 0.1, 0.05)
	_led.emission_energy_multiplier = 0.0
	_box(Vector3(0.01, 0.01, 0.006), Vector3(0.065, 0.125, 0.037), _led)

	for i in Puzzle.SYMBOL_COUNT:
		var s := Sprite3D.new()
		s.texture = load("res://textures/symbols/sym_%d.png" % puzzle.symbol_order[i])
		s.pixel_size = 0.016 / 512.0
		s.modulate = Color(0.45, 1.0, 0.6)
		s.shaded = false
		s.position = Vector3(-0.055 + i * 0.022, 0.1, 0.0385)
		s.visible = false
		add_child(s)
		_symbols.append(s)
	_screen_lbl = Label3D.new()
	_screen_lbl.font_size = 40
	_screen_lbl.pixel_size = 0.0004
	_screen_lbl.modulate = Color(0.45, 1.0, 0.6)
	_screen_lbl.outline_size = 0
	_screen_lbl.shaded = false
	_screen_lbl.position = Vector3(0, 0.075, 0.0385)
	if ResourceLoader.exists("res://fonts/ui.ttf"):
		_screen_lbl.font = load("res://fonts/ui.ttf")
	add_child(_screen_lbl)

	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK"]
	var keymat := StandardMaterial3D.new()
	keymat.albedo_color = Color(0.55, 0.56, 0.55)
	keymat.metallic = 0.8
	keymat.roughness = 0.35
	for i in keys.size():
		var col := i % 3
		var row := i / 3
		var p := Vector3(-0.045 + col * 0.045, 0.025 - row * 0.042, 0.04)
		_box(Vector3(0.036, 0.032, 0.01), p, keymat)
		var l := Label3D.new()
		l.text = keys[i]
		l.font_size = 40
		l.pixel_size = 0.00035
		l.modulate = Color(0.08, 0.08, 0.08)
		l.outline_size = 0
		l.shaded = true
		l.position = p + Vector3(0, 0, 0.0055)
		add_child(l)
		var hit := Interactable.new("Press " + keys[i], _press.bind(keys[i]))
		hit.add_box(Vector3(0.04, 0.036, 0.02))
		hit.position = p
		add_child(hit)
	Game.power_changed.connect(_on_state)
	Game.blackout_changed.connect(_on_state)
	_refresh()


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	add_child(mi)


func _on_state(_v: bool) -> void:
	_refresh()


func powered() -> bool:
	return Game.power_on and not Game.blackout


func _refresh() -> void:
	var on := powered()
	_screen_mat.emission_energy_multiplier = 0.9 if on else 0.0
	for s in _symbols:
		s.visible = on
	_screen_lbl.visible = on
	_screen_lbl.text = ("*".repeat(entry.length()) + "_".repeat(6 - entry.length())) if not _locked else "LOCKED"
	_led.emission_energy_multiplier = 2.0 if on else 0.0


func _press(_player: Node, key: String) -> void:
	if not powered():
		Audio.play_3d("ui_click", global_position, -16.0, 6.0)
		return
	if _locked or _done:
		return
	Audio.play_3d("keypad_beep", global_position, -6.0, 15.0, 0.02)
	Game.emit_noise(global_position, 3.0, "keypad")
	match key:
		"C":
			entry = ""
		"OK":
			_submit()
		_:
			if entry.length() < 6:
				entry += key
	_refresh()


func _submit() -> void:
	if entry == puzzle.code_string():
		_done = true
		_led.emission = Color(0.1, 1.0, 0.2)
		Audio.play_3d("keypad_accept", global_position, -2.0, 20.0, 0.0)
		_screen_lbl.text = "OPEN"
		Game.say("exit")
		door.open()
		return
	tries += 1
	entry = ""
	Audio.play_3d("keypad_error", global_position, 0.0, 25.0, 0.0)
	Game.emit_noise(global_position, 10.0, "keypad")
	Game.say("keypad_wrong")
	if tries >= MAX_TRIES:
		_locked = true
		tries = 0
		_refresh()
		Audio.play_3d("alarm", global_position + Vector3(0, 1.0, 0), 8.0, 120.0, 0.0)
		Game.emit_noise(global_position, 400.0, "alarm")
		await get_tree().create_timer(LOCKOUT).timeout
		_locked = false
	_refresh()
