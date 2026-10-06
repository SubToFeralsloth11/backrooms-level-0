class_name Player
extends CharacterBody3D
## First-person survivor. No meters on screen: stamina is heard (breathing),
## battery is seen (beam dims and stutters). Every step is a sound entities hear.

signal prompt_changed(text: String)
signal reading_changed(on: bool)

const WALK := 1.75
const RUN := 4.4
const CROUCH := 0.85
const STAND_H := 1.75
const CROUCH_H := 1.05
const EYE_STAND := 1.62
const EYE_CROUCH := 0.92
const MAX_BOTTLES := 3
const BATTERY_LIFE := 210.0  # seconds of light per battery pair
const REACH := 1.9
const LEAN_DIST := 0.34
const LEAN_ROLL := 0.13
## Noise radii (m) of a footstep by gait.
const STEP_NOISE := {"crouch": 1.2, "walk": 6.5, "run": 19.0}
## Gait from actual horizontal speed (m/s): below WALK_MIN steps are crouch-quiet.
const WALK_MIN := 1.2
const RUN_MIN := 3.0
const FEAR_RANGE := 14.0

var spare_batteries := 0
var bottles := 0
var battery := 1.0
var flashlight_on := false
var stamina := 1.0
var exhausted := false
var crouching := false
var alive := true
var journal: Array[Dictionary] = []
## 0..1: entity proximity / being hunted. Drives hand tremor and the heartbeat.
var fear := 0.0
## True while a journal page is held up.
var reading: bool:
	get:
		return _reading_idx >= 0

var head: Node3D
var camera: Camera3D
var hands: Hands
var _shape: CapsuleShape3D
var _col: CollisionShape3D
var _breath: AudioStreamPlayer
var _pitch := 0.0
var _step_phase := 0.0
var _last_step_sign := 1.0
var _look_delta := Vector2.ZERO
var _tilt := 0.0
var _target: Interactable
var _reading_idx := -1
var _bob := Vector3.ZERO
var _land_dip := 0.0
var _was_on_floor := true
var _breath_noise_t := 0.0
var _shake := 0.0
var _dark_t := 0.0
var _lean := 0.0
var _base_fov := 78.0
var _fear_boost := 0.0
var _fear_t := 0.0
var _fumble_t := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	_col = CollisionShape3D.new()
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.3
	_shape.height = STAND_H
	_col.shape = _shape
	_col.position.y = STAND_H * 0.5
	add_child(_col)
	head = Node3D.new()
	head.position.y = EYE_STAND
	add_child(head)
	camera = Camera3D.new()
	camera.fov = _base_fov
	camera.near = 0.015
	camera.far = 80.0
	head.add_child(camera)
	hands = Hands.new()
	camera.add_child(hands)
	_breath = AudioStreamPlayer.new()
	_breath.stream = Audio.loop_stream("breath_exhausted")
	_breath.bus = "SFX"
	_breath.volume_db = -60.0
	add_child(_breath)
	hands.set_flashlight_visual(false, 0.0)
	for a in [["lean_left", KEY_Q], ["lean_right", KEY_Z]]:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0])
			var ev := InputEventKey.new()
			ev.physical_keycode = a[1]
			InputMap.action_add_event(a[0], ev)
	Game.player = self


## Base field of view (settings). Kept separate so effects can add on top.
func set_fov(v: float) -> void:
	_base_fov = v
	camera.fov = v


## Entities call this while hunting/close; decays on its own.
func add_fear(amount: float) -> void:
	_fear_boost = clampf(maxf(_fear_boost, amount), 0.0, 1.0)


## Failed action: pocket pat, a dull knock, and a short thought.
func fumble(text: String) -> void:
	hands.fumble()
	Audio.play_2d("fumble", -12.0, 0.08)
	if _fumble_t <= 0.0 and Game.subtitles_enabled:
		Game.subtitle.emit(text, 1.8)
	_fumble_t = 1.5


func _unhandled_input(event: InputEvent) -> void:
	if not alive or not Game.is_playing():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := (event as InputEventMouseMotion).relative
		rotate_y(-m.x * Game.mouse_sensitivity)
		_pitch = clampf(_pitch - m.y * Game.mouse_sensitivity, -1.45, 1.45)
		_look_delta += m
	elif event.is_action_pressed("flashlight"):
		_toggle_flashlight()
	elif event.is_action_pressed("reload"):
		_swap_batteries()
	elif event.is_action_pressed("journal"):
		_cycle_journal()
	elif event.is_action_pressed("throw"):
		_throw()
	elif event.is_action_pressed("interact"):
		if _reading_idx >= 0:
			_stop_reading()
		elif _target:
			hands.reach()
			_target.interact(self)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	var playing := Game.is_playing()
	# --- crouch ---
	var want_crouch := playing and Input.is_action_pressed("crouch")
	if not want_crouch and crouching:
		want_crouch = test_move(global_transform, Vector3(0, STAND_H - CROUCH_H, 0))  # blocked overhead
	crouching = want_crouch
	var h := lerpf(_shape.height, CROUCH_H if crouching else STAND_H, 1.0 - exp(-10.0 * delta))
	_shape.height = h
	_col.position.y = h * 0.5
	var eye := lerpf(head.position.y, EYE_CROUCH if crouching else EYE_STAND, 1.0 - exp(-9.0 * delta))
	head.position.y = eye

	# --- movement ---
	var input := Vector2.ZERO
	if playing:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var running := playing and Input.is_action_pressed("sprint") and not crouching and not exhausted and input.y < -0.3 and _reading_idx < 0
	var speed := CROUCH if crouching else (RUN if running else WALK)
	if _reading_idx >= 0:
		speed = minf(speed, CROUCH)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var target := dir * speed
	var accel := 9.0 if target.length() > hv.length() else 11.0
	hv = hv.lerp(target, 1.0 - exp(-accel * delta))
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	move_and_slide()

	if is_on_floor() and not _was_on_floor and velocity.y < -2.0:
		_land_dip = 0.06
	_was_on_floor = is_on_floor()

	# --- stamina (no bar: you hear it) ---
	var moving := hv.length() > 0.4
	if running and moving:
		stamina = maxf(0.0, stamina - delta / 9.0)
		if stamina <= 0.0 and not exhausted:
			exhausted = true
			Game.say("exhausted")
	else:
		stamina = minf(1.0, stamina + delta / (14.0 if moving else 8.0))
		if exhausted and stamina > 0.45:
			exhausted = false
	var breath_target := -60.0
	if stamina < 0.6:
		breath_target = lerpf(-30.0, -8.0, 1.0 - stamina / 0.6)
	_breath.volume_db = lerpf(_breath.volume_db, breath_target, 1.0 - exp(-2.0 * delta))
	if _breath.stream and not _breath.playing and breath_target > -50.0:
		_breath.play()
	elif _breath.playing and _breath.volume_db < -55.0:
		_breath.stop()
	# Heavy breathing is audible to things nearby.
	if stamina < 0.35:
		_breath_noise_t -= delta
		if _breath_noise_t <= 0.0:
			_breath_noise_t = 1.2
			Game.emit_noise(global_position, 3.5, "breath")

	# --- gait (from actual speed), head bob, footsteps ---
	var spd := hv.length()
	var gait := "run" if spd > RUN_MIN else ("walk" if spd > WALK_MIN else "crouch")
	var speed01 := clampf(spd / RUN, 0.0, 1.0)
	if moving and is_on_floor():
		var freq := lerpf(1.7, 2.6, clampf((spd - CROUCH) / (RUN - CROUCH), 0.0, 1.0))
		_step_phase += delta * freq * PI
		var s := signf(sin(_step_phase))
		if s != _last_step_sign:
			_last_step_sign = s
			_footstep(gait)
	else:
		_step_phase = lerpf(_step_phase, roundf(_step_phase / PI) * PI, 1.0 - exp(-6.0 * delta))
	var amp := {"crouch": 0.012, "walk": 0.024, "run": 0.045}[gait] as float
	var bob_target := Vector3(cos(_step_phase) * amp * 0.6, -absf(sin(_step_phase)) * amp, 0) if moving else Vector3.ZERO
	_bob = _bob.lerp(bob_target, 1.0 - exp(-12.0 * delta))
	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-8.0 * delta))
	_tilt = lerpf(_tilt, -input.x * 0.02 + (sin(_step_phase) * 0.006 if gait == "run" else 0.0), 1.0 - exp(-6.0 * delta))
	_shake = maxf(0.0, _shake - delta * 1.5)
	var shake_v := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.02
	camera.position = _bob + Vector3(0, -_land_dip, 0) + shake_v
	_update_lean(delta, playing and not running)
	head.rotation = Vector3(_pitch, 0, _tilt - _lean * LEAN_ROLL)
	_update_fear(delta)

	# --- flashlight battery ---
	if flashlight_on:
		battery = maxf(0.0, battery - delta / BATTERY_LIFE)
		if battery <= 0.0:
			flashlight_on = false
			Audio.play_2d("flashlight_off", -12.0)
		elif battery < 0.15:
			Game.say("battery_low")
	var level := 1.0
	if battery < 0.2:
		level = lerpf(0.25, 1.0, battery / 0.2)
		if randf() < 0.08 * (1.0 - battery / 0.2):
			level *= randf_range(0.0, 0.5)
	hands.set_flashlight_visual(flashlight_on, level)

	# --- darkness comment ---
	if Game.level and Game.level.is_dark(Game.level.world_to_cell(global_position)) and not flashlight_on:
		_dark_t += delta
		if _dark_t > 2.5:
			Game.say("dark")
	else:
		_dark_t = 0.0

	# --- look target ---
	_update_target()
	var wall_close := 0.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 0.55, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		wall_close = 1.0 - camera.global_position.distance_to(hit.position) / 0.55
	if _reading_idx >= 0:
		var lit := 0.9 if (flashlight_on or not Game.level.is_dark(Game.level.world_to_cell(global_position))) else 0.1
		hands.set_paper_light(lit)
	hands.animate(delta, _step_phase, speed01 if moving else 0.0, 1.0 if crouching else 0.0, _look_delta, wall_close, fear)
	_look_delta = Vector2.ZERO


## Q/Z lean: the head slides sideways around a corner, stopping short of walls.
func _update_lean(delta: float, allowed: bool) -> void:
	var want := 0.0
	if allowed:
		want = Input.get_action_strength("lean_right") - Input.get_action_strength("lean_left")
	if want != 0.0:
		var side := global_basis.x * signf(want)
		var from := global_position + Vector3(0, head.position.y, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + side * (LEAN_DIST + 0.2), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var room := maxf(0.0, from.distance_to(hit.position) - 0.2)
			want = signf(want) * minf(absf(want), room / LEAN_DIST)
	_lean = lerpf(_lean, want, 1.0 - exp(-8.0 * delta))
	head.position.x = _lean * LEAN_DIST


## Fear from nearby entities (closer and in sight = stronger) plus entity hunts.
func _update_fear(delta: float) -> void:
	_fumble_t -= delta
	_fear_boost = maxf(0.0, _fear_boost - delta * 0.12)
	_fear_t -= delta
	if _fear_t <= 0.0:
		_fear_t = 0.25
		var near := 0.0
		var eye := camera.global_position
		var space := get_world_3d().direct_space_state
		for node in get_tree().get_nodes_in_group("entity"):
			var e := node as Node3D
			if e == null or not e.is_visible_in_tree():
				continue
			var d := eye.distance_to(e.global_position)
			if d > FEAR_RANGE:
				continue
			var f := 1.0 - d / FEAR_RANGE
			var q := PhysicsRayQueryParameters3D.create(eye, e.global_position + Vector3(0, 1.2, 0), 1)
			if not space.intersect_ray(q).is_empty():
				f *= 0.45  # felt, not seen
			near = maxf(near, f)
		set_meta("fear_near", near)
	var target := maxf(_fear_boost, get_meta("fear_near", 0.0))
	fear = lerpf(fear, target, 1.0 - exp(-(3.0 if target > fear else 0.6) * delta))


func _footstep(gait: String) -> void:
	var feet := global_position + Vector3(0, 0.05, 0)
	var vol := {"crouch": -22.0, "walk": -11.0, "run": -4.0}[gait] as float
	var radius: float = STEP_NOISE[gait]
	if Audio.floor_at(feet) == "concrete":
		var p := Audio.play_3d("footstep_concrete", feet, vol + (1.5 if gait == "run" else -1.0), 30.0, 0.1)
		if p and gait == "run":
			p.pitch_scale *= 1.08
		radius *= 1.25  # hard floors carry
	else:
		Audio.play_3d("footstep_carpet_run" if gait == "run" else "footstep_carpet", feet, vol, 25.0, 0.08)
	Game.emit_noise(global_position, radius, "step")


func _update_target() -> void:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * REACH, 1 | Interactable.LAYER)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	var t: Interactable = null
	if not hit.is_empty() and hit.collider is Interactable and (hit.collider as Interactable).enabled:
		t = hit.collider
	if t != _target:
		_target = t
		prompt_changed.emit(t.prompt if t else "")


func _toggle_flashlight() -> void:
	if battery <= 0.0:
		Audio.play_2d("flashlight_on", -14.0)
		return
	flashlight_on = not flashlight_on
	Audio.play_2d("flashlight_on" if flashlight_on else "flashlight_off", -10.0, 0.05)


func _swap_batteries() -> void:
	if spare_batteries <= 0:
		fumble("No spare batteries.")
		return
	if battery > 0.5:
		fumble("These still have juice.")
		return
	spare_batteries -= 1
	battery = 1.0
	hands.swap_batteries()
	Audio.play_2d("battery_insert", -6.0, 0.05)


func _throw() -> void:
	if _reading_idx >= 0:
		return
	if bottles <= 0:
		fumble("Nothing left to throw.")
		return
	bottles -= 1
	hands.throw()
	await get_tree().create_timer(Hands.THROW_RELEASE, false).timeout
	if not alive:
		return
	Audio.play_2d("throw_whoosh", -8.0, 0.1)
	var Bottle := preload("res://scripts/thrown_bottle.gd")
	var b: RigidBody3D = Bottle.new()
	get_tree().current_scene.add_child(b)
	b.global_position = camera.global_position - camera.global_basis.z * 0.4 + camera.global_basis.x * -0.1
	b.linear_velocity = -camera.global_basis.z * 8.5 + Vector3.UP * 1.5 + velocity * 0.5
	b.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-4, 4), randf_range(-8, 8))


func read_note(id: String, text: String) -> void:
	var first := journal.is_empty()
	journal.append({"id": id, "text": text})
	_reading_idx = journal.size() - 1
	hands.set_reading(true, text)
	reading_changed.emit(true)
	Game.note_read.emit(id)
	if first or id != "intro":
		get_tree().create_timer(1.5).timeout.connect(func(): Game.say("first_note"))


func _cycle_journal() -> void:
	if journal.is_empty():
		return
	_reading_idx = (_reading_idx + 1) % (journal.size() + 1) if _reading_idx >= 0 else 0
	if _reading_idx >= journal.size():
		_stop_reading()
		return
	Audio.play_2d("paper_rustle", -10.0, 0.08)
	hands.set_reading(true, journal[_reading_idx].text)
	reading_changed.emit(true)


func _stop_reading() -> void:
	_reading_idx = -1
	hands.set_reading(false)
	Audio.play_2d("paper_rustle", -14.0, 0.08)
	reading_changed.emit(false)


func is_reading() -> bool:
	return _reading_idx >= 0


func add_shake(v: float) -> void:
	_shake = maxf(_shake, v)


## Called by an entity on contact. Snaps the view to the attacker.
func die(attacker_head: Vector3, cause: String) -> void:
	if not alive:
		return
	alive = false
	velocity = Vector3.ZERO
	_breath.stop()
	hands.visible = false
	var to := attacker_head - camera.global_position
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation:y", yaw, 0.12).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(head, "rotation:x", pitch, 0.12).set_trans(Tween.TRANS_EXPO)
	_shake = 1.0
	Audio.play_2d("death_impact", 0.0)
	await get_tree().create_timer(0.7).timeout
	Audio.play_2d("body_fall", -2.0)
	var fall := create_tween().set_parallel(true)
	fall.tween_property(head, "position:y", 0.25, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(head, "rotation:z", 1.2, 0.6)
	Game.kill_player(cause)
