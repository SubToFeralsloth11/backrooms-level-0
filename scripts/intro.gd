extends Node
## Level 0 intro: an ordinary dark room, the floor cracks and gives way, a
## fall through blackness, a hard landing on damp carpet and a slow, blurred
## get-up before control returns. Skippable with Esc / E. Uses its own camera
## and post overlay; the player's physics and input are suspended meanwhile.

const ROOM_UP := 300.0  # the "real world" room floats far above the level
const ROOM := 4.0

var _player: Player
var _cam: Camera3D
var _room: Node3D
var _post: ShaderMaterial
var _layer: CanvasLayer
var _skip := false
var _boards: Array[Dictionary] = []
var _crack: Decal
var _t := 0.0
var _shake := 0.0
var _ambience_bus := -1


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		_skip = true
		get_viewport().set_input_as_handled()


func play(player: Player, ui: UI) -> void:
	_player = player
	var had_input := player.is_processing_unhandled_input()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	# Pause entities during intro
	var world := player.get_parent()
	var _paused_entities: Array[Node] = []
	if world:
		for e in world.get_children():
			if e is CharacterBody3D and e.has_method("try_kill"):  # our entities
				e.set_physics_process(false)
				e.set_process(false)
				e.set_process_unhandled_input(false)
				_paused_entities.append(e)
	_build_overlay()
	ui.skip_fade()
	_ambience_bus = AudioServer.get_bus_index("Ambience")
	if _ambience_bus >= 0:
		AudioServer.set_bus_mute(_ambience_bus, true)
	_build_room()
	await _sequence()
	if _skip:
		_set_post(0.0, 0.0, 0.0, 1.0)
		await _run(0.6, func(k: float): _set_post(0.0, 0.0, 0.0, 1.0 - k), false)
	_finish(had_input, _paused_entities)


func _finish(had_input: bool, paused_entities: Array[Node]) -> void:
	if _ambience_bus >= 0:
		AudioServer.set_bus_mute(_ambience_bus, false)
	if is_instance_valid(_player):
		_player.camera.current = true
		_player.set_physics_process(true)
		_player.set_process_unhandled_input(had_input)
	for e in paused_entities:
		if is_instance_valid(e):
			e.set_physics_process(true)
			e.set_process(true)
			e.set_process_unhandled_input(true)
	if _room:
		_room.queue_free()
	if _layer:
		_layer.queue_free()



# ---------------------------------------------------------------- timeline

func _sequence() -> void:
	var base := _room.global_position
	var yaw := _player.rotation.y
	var look := func(pitch: float, extra_yaw := 0.0, h := 1.6) -> Transform3D:
		var b := Basis(Vector3.UP, yaw + extra_yaw) * Basis(Vector3.RIGHT, pitch)
		return Transform3D(b, base + Vector3(0, h, 0))
	_cam.global_transform = look.call(-0.2, 0.35)
	_cam.current = true
	# 1. wake into a dim bedroom-ish room
	if not await _run(2.2, func(k: float):
		_cam.global_transform = look.call(-0.2 - 0.05 * k, 0.35 - 0.3 * k)
		_set_post(0.0, 0.0, 0.0, 1.0 - k)):
		return
	Audio.play_2d("distant_creak", -6.0)
	# 2. creaking, first crack at your feet
	if not await _run(1.6, func(k: float):
		_cam.global_transform = look.call(lerpf(-0.25, -1.15, smoothstep(0.2, 1.0, k)), 0.05)
		_set_post(0.0, 0.0, 0.0, 0.0)):
		return
	Audio.play_2d("watcher_crack_1", 0.0, 0.1)
	_shake = 0.4
	if not await _run(1.3, func(k: float):
		_crack.size = Vector3(lerpf(0.5, 2.2, k), 0.4, lerpf(0.5, 2.2, k))
		_cam.global_transform = look.call(-1.15, 0.05)):
		return
	Audio.play_2d("watcher_crack_2", 2.0, 0.1)
	Audio.play_2d("distant_thud", 2.0)
	_shake = 1.0
	if not await _run(0.6, func(k: float):
		_crack.size = Vector3(lerpf(2.2, 3.6, k), 0.4, lerpf(2.2, 3.6, k))
		_cam.global_transform = look.call(-1.15, 0.05)):
		return
	# 3. the floor gives way
	Audio.play_2d("watcher_crack_3", 4.0, 0.05)
	var wind := AudioStreamPlayer.new()
	wind.stream = Audio.stream("throw_whoosh")
	wind.pitch_scale = 0.32
	wind.volume_db = 4.0
	wind.bus = "SFX"
	add_child(wind)
	wind.play()
	for b in _boards:
		b.falling = true
	_shake = 1.4
	var y0 := base.y + 1.6
	if not await _run(2.4, func(k: float):
		var t: float = k * 2.4
		var y: float = y0 - 0.5 * 9.0 * t * t
		var pitch: float = lerpf(-1.15, 0.9, smoothstep(0.0, 0.7, k))  # look back up at the hole
		var b: Basis = Basis(Vector3.UP, yaw + 0.05 + t * 0.6) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, sin(t * 3.0) * 0.25)
		_cam.global_transform = Transform3D(b, Vector3(base.x, y, base.z))
		_set_post(k * 1.5, 0.0, 0.0, smoothstep(0.55, 1.0, k))):
		return
	# 4. through the dark into Level 0
	var land := _player.global_position
	_room.visible = false
	if not await _run(0.35, func(k: float):
		var b := Basis(Vector3.UP, yaw + 1.2) * Basis(Vector3.RIGHT, lerpf(0.6, -1.3, k)) * Basis(Vector3.BACK, 0.4)
		_cam.global_transform = Transform3D(b, land + Vector3(0, lerpf(Level.WALL_H - 0.15, 0.2, k * k), 0))
		_set_post(2.0, 0.0, 0.0, 0.35)):
		return
	Audio.play_2d("body_fall", 4.0)
	Audio.play_2d("death_impact", -8.0, 0.1)
	_shake = 0.0
	var lying := Transform3D(Basis(Vector3.UP, yaw + 0.9) * Basis(Vector3.RIGHT, 0.25) * Basis(Vector3.BACK, 1.35), land + Vector3(0, 0.17, 0))
	_cam.global_transform = lying
	if not await _run(0.25, func(k: float): _set_post(3.0, 0.0, 0.0, 0.0, 1.0 - k)):
		return
	if not await _run(1.4, func(_k: float): _set_post(4.0, 0.0, 1.0, 1.0)):
		return
	# 5. come to: blinking, blurred, ringing quiet
	Audio.play_2d("breath_scared", -4.0)
	if _ambience_bus >= 0:
		AudioServer.set_bus_mute(_ambience_bus, false)
	if not await _run(3.0, func(k: float):
		var lid: float = 0.5 + 0.5 * cos(k * TAU * 1.5) * (1.0 - k)
		_cam.global_transform = lying.rotated_local(Vector3.UP, sin(k * 2.0) * 0.05)
		_set_post(lerpf(4.0, 2.5, k), 0.012 * (1.0 - k * 0.5), lid, lerpf(0.7, 0.0, minf(k * 3.0, 1.0)))):
		return
	# 6. slowly get up into the player's view
	var target := _player.camera.global_transform
	var kneel := Transform3D(Basis(Vector3.UP, yaw + 0.3) * Basis(Vector3.RIGHT, -0.5) * Basis(Vector3.BACK, 0.2), land + Vector3(0, 0.9, 0))
	if not await _run(1.5, func(k: float):
		_cam.global_transform = lying.interpolate_with(kneel, smoothstep(0.0, 1.0, k))
		_set_post(lerpf(2.5, 1.6, k), 0.006, 0.0, 0.0)):
		return
	await _run(1.8, func(k: float):
		_cam.global_transform = kneel.interpolate_with(target, smoothstep(0.0, 1.0, k))
		_set_post(lerpf(1.6, 0.0, k), 0.006 * (1.0 - k), 0.0, 0.0))


## Runs `step(k)` each frame for `secs`, k in 0..1. Returns false when skipped.
func _run(secs: float, step: Callable, skippable := true) -> bool:
	var t := 0.0
	while t < secs:
		if _skip and skippable:
			return false
		step.call(t / secs)
		await get_tree().process_frame
		t += get_process_delta_time()
	step.call(1.0)
	return true



func _process(delta: float) -> void:
	_t += delta
	if _cam and _shake > 0.0:
		_shake = maxf(_shake - delta * 0.5, 0.0)
		_cam.h_offset = randf_range(-1, 1) * 0.02 * _shake
		_cam.v_offset = randf_range(-1, 1) * 0.02 * _shake
	elif _cam:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0
	for b in _boards:
		if not b.falling:
			continue
		var n: Node3D = b.node
		b.vel += Vector3(0, -9.0 * b.drag, 0) * delta
		n.position += b.vel * delta
		n.rotate(b.axis, b.spin * delta)


func _set_post(blur: float, dv: float, lid: float, black: float, flash := 0.0) -> void:
	_post.set_shader_parameter("blur", blur)
	_post.set_shader_parameter("double_vision", dv)
	_post.set_shader_parameter("lid", lid)
	_post.set_shader_parameter("black", black)
	_post.set_shader_parameter("flash", flash)


# ---------------------------------------------------------------- build

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post = ShaderMaterial.new()
	_post.shader = load("res://shaders/intro_fall.gdshader")
	rect.material = _post
	_layer.add_child(rect)
	_set_post(0.0, 0.0, 0.0, 1.0)


func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi


## A plain dark room with a lamp: hardwood boards (the middle ones fall away),
## painted walls, a door, a curtained window with streetlight behind it.
func _build_room() -> void:
	_room = Node3D.new()
	_room.name = "IntroRoom"
	_player.get_parent().add_child(_room)
	_room.global_position = _player.global_position + Vector3(0, ROOM_UP, 0)
	_room.rotation.y = _player.rotation.y
	var wood := _mat(Color(0.33, 0.2, 0.11), 0.55)
	var wood2 := _mat(Color(0.28, 0.17, 0.09), 0.6)
	var paint := _mat(Color(0.36, 0.38, 0.4), 0.9)
	var h := ROOM * 0.5
	var bw := 0.25
	var i := 0
	for zi in int(ROOM / bw):
		var z := -h + (zi + 0.5) * bw
		var x_start := -h - (0.5 if zi % 2 == 1 else 0.0)
		for j in 5:
			var x0 := maxf(x_start + j, -h)
			var x1 := minf(x_start + j + 1.0, h)
			if x1 - x0 < 0.05:
				continue
			var x := (x0 + x1) * 0.5
			var mi := _box(_room, Vector3(x1 - x0 - 0.005, 0.04, bw - 0.005), Vector3(x, -0.02, z), wood if i % 3 else wood2)
			i += 1
			if Vector2(x, z).length() < 1.05:
				_boards.append({"node": mi, "falling": false, "vel": Vector3(randf_range(-0.3, 0.3), randf_range(-0.5, 0.5), randf_range(-0.3, 0.3)),
					"axis": Vector3(randf_range(-1, 1), randf_range(-0.2, 0.2), randf_range(-1, 1)).normalized(), "spin": randf_range(0.5, 2.5), "drag": randf_range(0.8, 1.05)})
	for s in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
		var size := Vector3(ROOM, 2.6, 0.1) if s.x == 0 else Vector3(0.1, 2.6, ROOM)
		_box(_room, size, s * (h + 0.05) + Vector3(0, 1.3, 0), paint)
		var bsize := Vector3(ROOM, 0.1, 0.02) if s.x == 0 else Vector3(0.02, 0.1, ROOM)
		_box(_room, bsize, s * (h - 0.01) + Vector3(0, 0.05, 0), _mat(Color(0.8, 0.78, 0.72)))
	_box(_room, Vector3(ROOM, 0.1, ROOM), Vector3(0, 2.65, 0), _mat(Color(0.5, 0.5, 0.5)))
	# door (closed) and a window with cold streetlight
	_box(_room, Vector3(0.9, 2.05, 0.03), Vector3(-0.8, 1.025, -h + 0.01), _mat(Color(0.42, 0.3, 0.2), 0.6))
	var win := _box(_room, Vector3(1.0, 0.9, 0.02), Vector3(h - 0.01, 1.5, 0.6), null)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.02, 0.03, 0.05)
	wm.emission_enabled = true
	wm.emission = Color(0.25, 0.35, 0.5)
	wm.emission_energy_multiplier = 0.25
	win.mesh.surface_set_material(0, wm)
	win.rotation.y = PI * 0.5
	var moon := SpotLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.85)
	moon.light_energy = 1.2
	moon.spot_range = 6.0
	moon.spot_angle = 35.0
	moon.shadow_enabled = true
	_room.add_child(moon)
	moon.position = Vector3(h + 0.3, 1.8, 0.6)
	moon.look_at(_room.global_position + _room.global_basis * Vector3(-0.5, 0, 0.3))
	# bedside table with a warm lamp
	_box(_room, Vector3(0.5, 0.55, 0.4), Vector3(-h + 0.35, 0.275, 1.2), wood2)
	var shade := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.15
	cm.height = 0.2
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.95, 0.85, 0.6)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.7, 0.4)
	sm.emission_energy_multiplier = 1.5
	cm.material = sm
	shade.mesh = cm
	_room.add_child(shade)
	shade.position = Vector3(-h + 0.35, 0.85, 1.2)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.45)
	lamp.light_energy = 2.6
	lamp.omni_range = 6.0
	lamp.shadow_enabled = true
	_room.add_child(lamp)
	lamp.position = Vector3(-h + 0.35, 0.8, 1.2)
	# crack spreading through the boards at your feet
	_crack = Decal.new()
	_crack.texture_albedo = load("res://textures/props/crack_2.png")
	_crack.size = Vector3(0.3, 0.4, 0.3)
	_crack.modulate = Color(0.0, 0.0, 0.0)
	_room.add_child(_crack)
	_crack.position = Vector3(0, 0, 0)
	_cam = Camera3D.new()
	_cam.fov = 78.0
	_cam.near = 0.02
	_cam.far = 80.0
	add_child(_cam)
