extends Entity
## THE SMILER: exists only in darkness. A shape you can barely make out, two
## pale eyes, and a grin far too wide.
## Strengths: unstoppable in the dark; drifts toward you whenever you are in
## an unlit cell; faster when your light is off.
## Weaknesses: cannot enter lit areas; holding the flashlight beam on its face
## for ~2 s makes it recoil and vanish (but batteries run out).

const STALK_DARK := 2.3
const STALK_LIT := 1.35
const RECOIL_TIME := 2.0

var _exposure := 0.0
var _grin: Node3D
var _grin_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _shade_mat: StandardMaterial3D
var _static: AudioStreamPlayer3D
var _whisper: AudioStreamPlayer3D
var _giggle_t := 6.0
var _fade := 1.0
var _hidden := false  ## recoiled / caught in light: fading out, harmless, waiting to relocate
var _relocate_t := 0.0
var _lure := Vector3.INF  ## lever / alarm it heard, drifted toward through the dark
var _lure_t := 0.0


func _ready() -> void:
	super._ready()
	cause = "smiler"
	_build_visual()
	_static = Audio.make_3d_player(Audio.loop_stream("smiler_static"), -6.0, 18.0)
	add_child(_static)
	_static.position.y = 1.7
	_whisper = Audio.make_3d_player(Audio.loop_stream("smiler_whisper"), -8.0, 10.0)
	add_child(_whisper)
	_whisper.position.y = 1.7
	_static.play(randf() * 2.0)
	Game.noise.connect(_on_noise)


func _build_visual() -> void:
	# A body made of shadow: matte near-black shape inside a dark fog volume.
	_shade_mat = StandardMaterial3D.new()
	_shade_mat.albedo_color = Color(0.005, 0.004, 0.004)
	_shade_mat.roughness = 1.0
	_shade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shade_mat.albedo_color.a = 0.92
	for p in [[Vector3(0, 1.15, 0), Vector3(0.28, 0.7, 0.18)], [Vector3(0, 1.85, 0.02), Vector3(0.17, 0.2, 0.17)], [Vector3(-0.3, 1.1, 0), Vector3(0.07, 0.6, 0.07)], [Vector3(0.3, 1.1, 0), Vector3(0.07, 0.6, 0.07)], [Vector3(0, 0.45, 0), Vector3(0.2, 0.45, 0.14)]]:
		var s := SphereMesh.new()
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = _shade_mat
		mi.position = p[0]
		mi.scale = p[1] * 2.0
		add_child(mi)
	var fog := FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fog.size = Vector3(0.9, 2.2, 0.5)
	fog.position = Vector3(0, 1.1, -0.12)  # behind the face so the grin isn't swallowed
	var fm := FogMaterial.new()
	fm.density = 1.6
	fm.albedo = Color(0, 0, 0)
	fm.height_falloff = 0.0
	fm.edge_fade = 0.8
	fog.material = fm
	add_child(fog)

	_grin = Node3D.new()
	_grin.position = Vector3(0, 1.8, 0.27)
	_grin.scale = Vector3.ONE * 1.45
	add_child(_grin)
	_grin_mat = StandardMaterial3D.new()
	_grin_mat.albedo_color = Color(0.92, 0.9, 0.78)
	_grin_mat.roughness = 0.25
	_grin_mat.emission_enabled = true
	_grin_mat.emission = Color(0.95, 0.92, 0.75)
	_grin_mat.emission_energy_multiplier = 0.9
	var gum := StandardMaterial3D.new()
	gum.albedo_color = Color(0.25, 0.02, 0.03)
	gum.emission_enabled = true
	gum.emission = Color(0.3, 0.02, 0.03)
	gum.emission_energy_multiplier = 0.25
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Two rows of ~26 crowded, uneven, too-long teeth along an exaggerated arc.
	for row in 2:
		var n := 26
		for i in n:
			var t := (float(i) / (n - 1)) * 2.0 - 1.0
			var a := t * 1.15
			var curve := 0.09 * t * t
			var x := sin(a) * 0.2
			var z := cos(a) * 0.06 - 0.06
			var y := curve + (0.0 if row == 0 else -0.045) + 0.02 * (1.0 - t * t) * (1.0 if row == 0 else -1.0)
			var tooth := BoxMesh.new()
			var len := rng.randf_range(0.022, 0.04) * (1.0 - absf(t) * 0.35)
			tooth.size = Vector3(rng.randf_range(0.009, 0.014), len, 0.006)
			var mi := MeshInstance3D.new()
			mi.mesh = tooth
			mi.material_override = _grin_mat
			mi.position = Vector3(x, y - (len * 0.5 if row == 0 else -len * 0.5), z)
			mi.rotation = Vector3(0, a, rng.randf_range(-0.12, 0.12))
			_grin.add_child(mi)
		var g := BoxMesh.new()
		g.size = Vector3(0.012, 0.012, 0.008)
		for i in 30:
			var t := (float(i) / 29.0) * 2.0 - 1.0
			var a := t * 1.15
			var gm := MeshInstance3D.new()
			gm.mesh = g
			gm.material_override = gum
			gm.position = Vector3(sin(a) * 0.2, 0.09 * t * t + (0.012 if row == 0 else -0.057) + 0.02 * (1.0 - t * t) * (1.0 if row == 0 else -1.0), cos(a) * 0.06 - 0.065)
			gm.rotation.y = a
			gm.scale = Vector3(1.6, 1, 1)
			_grin.add_child(gm)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.9, 0.9, 0.82)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(0.95, 0.93, 0.8)
	_eye_mat.emission_energy_multiplier = 1.4
	for s in [-1.0, 1.0]:
		var e := SphereMesh.new()
		e.radius = 0.011
		e.height = 0.016
		var mi := MeshInstance3D.new()
		mi.mesh = e
		mi.material_override = _eye_mat
		mi.position = Vector3(s * 0.075, 0.17, -0.02)
		_grin.add_child(mi)


func _physics_process(delta: float) -> void:
	if Game.level == null:
		return
	var here_dark := level().is_dark(global_position)
	# In light it simply isn't there.
	var visible_target := 1.0 if here_dark and not _hidden else 0.0
	_fade = move_toward(_fade, visible_target, delta * (0.6 if visible_target > _fade else 3.0))
	_apply_fade()
	if frozen:
		return
	if not Game.is_playing():
		return
	if not here_dark:
		_hidden = true
	if _hidden:
		# Fade out completely, then re-form somewhere you aren't looking.
		velocity = Vector3.ZERO
		_whisper.stop()
		_relocate_t -= delta
		if _fade <= 0.01 and _relocate_t <= 0.0:
			_relocate_t = 0.5
			_relocate()
		return
	var pl := player()
	var face_pos := _grin.global_position
	var beam := flashlight_on_me(face_pos)
	if beam > 0.0:
		# a dying, stuttering beam barely hurts it
		_exposure += delta * beam * beam
		velocity = Vector3.ZERO
		_grin.position.x = randf_range(-0.004, 0.004)  # shudders under the light
		if _exposure > RECOIL_TIME:
			_exposure = 0.0
			Audio.play_3d("smiler_giggle", face_pos, 0.0, 25.0, 0.1)
			_hidden = true
			_relocate_t = 1.0
		return
	_exposure = maxf(0.0, _exposure - delta * 0.5)
	_lure_t -= delta
	var spd := 0.0
	if pl and level().is_dark(pl.global_position) and dist_to_player() < 32.0:
		_repath_t -= delta
		if _repath_t <= 0.0:
			_repath_t = 0.5
			set_goal(pl.global_position, true)
			_trim_path_to_dark()
		spd = follow(delta, STALK_LIT if pl.flashlight_on else STALK_DARK, 6.0)
	elif _lure_t > 0.0:
		# drawn to the clunk of the breakers or the alarm, as far as the dark goes
		_repath_t -= delta
		if _repath_t <= 0.0:
			_repath_t = 1.0
			set_goal(_lure, true)
			_trim_path_to_dark()
		follow(delta, STALK_DARK, 6.0)
		if at_goal():
			_lure_t = 0.0
	else:
		# wait in the dark, turned toward the player
		follow(delta, 0.0)
		if pl:
			face(pl.global_position, delta, 2.0)
	_giggle_t -= delta
	var d := dist_to_player()
	if _giggle_t <= 0.0 and d < 14.0:
		_giggle_t = randf_range(8.0, 18.0)
		Audio.play_3d("smiler_giggle", face_pos, -6.0, 20.0, 0.1)
	Audio.set_base_db(_whisper, lerpf(-30.0, -4.0, clampf(1.0 - d / 10.0, 0.0, 1.0)))
	if d < 10.0 and not _whisper.playing:
		_whisper.play()
	elif d >= 12.0 and _whisper.playing:
		_whisper.stop()
	if d < 6.0 and pl and level().is_dark(pl.global_position):
		pl.add_fear(delta * 0.2)
	if spd > 0.0 and _fade > 0.6:
		try_kill()


func _on_noise(pos: Vector3, radius: float, source: String) -> void:
	if frozen or not Game.is_playing() or not (source in ["lever", "alarm"]):
		return
	if global_position.distance_to(pos) > radius:
		return
	_lure = pos
	_lure_t = 15.0
	_repath_t = 0.0


func _trim_path_to_dark() -> void:
	for i in path.size():
		if not level().is_dark(path[i]):
			path.resize(i)
			return


func _apply_fade() -> void:
	_grin_mat.emission_energy_multiplier = 0.9 * _fade
	_grin_mat.albedo_color.a = _fade
	_eye_mat.emission_energy_multiplier = 1.4 * _fade
	_shade_mat.albedo_color.a = 0.92 * _fade
	visible = _fade > 0.01
	var db := -6.0 if _fade > 0.5 else -40.0
	if not is_equal_approx(_static.get_meta("base_db", 0.0), db):
		Audio.set_base_db(_static, db)


## Re-materialise somewhere dark, at least 18 m away, out of the player's
## view. Stays hidden (and retries) if no such spot exists right now.
func _relocate() -> void:
	var pl := player()
	var avoid := pl.global_position if pl else Vector3.INF
	for i in 60:
		var c := level().random_open_cell(-1, avoid, 18.0)
		if not level().is_dark(c):
			continue
		var p := level().cell_center(c)
		if pl and (player_sees(p + Vector3(0, 1.7, 0), false) or player_sees(p + Vector3(0, 0.9, 0), false)):
			continue
		global_position = p
		clear_path()
		_exposure = 0.0
		_hidden = false
		_fade = 0.0
		return


func on_kill() -> void:
	Audio.play_3d("smiler_giggle", _grin.global_position, 6.0, 30.0, 0.0)


func head_global() -> Vector3:
	return _grin.global_position
