extends Node
## Sound playback: buses, name→stream resolution (with _1.._n variants),
## spatial one-shots with wall occlusion (muffle + attenuation), and loops.

const SFX_DIR := "res://audio/sfx/"
const EXTS := ["wav", "mp3", "ogg"]
const OCCLUSION_INTERVAL := 0.08

var _cache := {}
var _variants := {}
var _tracked: Array[AudioStreamPlayer3D] = []
var _occl_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_add_bus("SFX", [_reverb(0.35, 0.55, 0.14)])
	_add_bus("Ambience", [])
	_add_bus("UI", [])

	_preload_all()


## Load every SFX up front so first playback never hits the disk mid-game.
func _preload_all() -> void:
	for f in ResourceLoader.list_directory(SFX_DIR):
		for e in EXTS:
			if f.ends_with("." + e):
				var path: String = SFX_DIR + f
				if not _cache.has(path):
					_cache[path] = load(path)

func _reverb(room: float, damp: float, wet: float) -> AudioEffectReverb:
	var r := AudioEffectReverb.new()
	r.room_size = room
	r.damping = damp
	r.wet = wet
	r.dry = 1.0
	r.spread = 0.6
	r.predelay_msec = 12.0
	return r


func _add_bus(bus_name: String, effects: Array) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	for e in effects:
		AudioServer.add_bus_effect(idx, e)


func _path_for(sound_name: String) -> String:
	for e in EXTS:
		var p: String = SFX_DIR + sound_name + "." + e
		if ResourceLoader.exists(p):
			return p
	return ""


## Returns the stream for `sound_name`, or a random variant `sound_name_N`.
func stream(sound_name: String) -> AudioStream:
	if not _variants.has(sound_name):
		var list: Array[String] = []
		var direct := _path_for(sound_name)
		if direct != "":
			list.append(direct)
		else:
			var i := 1
			while true:
				var p := _path_for("%s_%d" % [sound_name, i])
				if p == "":
					break
				list.append(p)
				i += 1
		if list.is_empty():
			push_warning("missing sound: " + sound_name)
		_variants[sound_name] = list
	var paths: Array = _variants[sound_name]
	if paths.is_empty():
		return null
	var path: String = paths[randi() % paths.size()]
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## Returns a looping copy of the stream (shared resource left untouched).
func loop_stream(sound_name: String) -> AudioStream:
	var s := stream(sound_name)
	if s == null:
		return null
	var c: AudioStream = s.duplicate()
	if c is AudioStreamWAV:
		var w := c as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	elif c is AudioStreamMP3:
		(c as AudioStreamMP3).loop = true
	elif c is AudioStreamOggVorbis:
		(c as AudioStreamOggVorbis).loop = true
	return c


func _world_root() -> Node:
	return get_tree().current_scene if get_tree().current_scene else self


func play_3d(sound_name: String, pos: Vector3, volume_db := 0.0, max_dist := 40.0, pitch_var := 0.06, bus := "SFX") -> AudioStreamPlayer3D:
	var s := stream(sound_name)
	if s == null:
		return null
	var p := make_3d_player(s, volume_db, max_dist, bus)
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	_world_root().add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p


## Configured 3D player (not added to tree). Tracked for occlusion once in tree.
func make_3d_player(s: AudioStream, volume_db := 0.0, max_dist := 40.0, bus := "SFX") -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 4.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.attenuation_filter_cutoff_hz = 9000.0
	p.attenuation_filter_db = -18.0
	p.set_meta("base_db", volume_db)
	p.tree_entered.connect(func(): _tracked.append(p))
	p.tree_exiting.connect(func(): _tracked.erase(p))
	return p


func play_2d(sound_name: String, volume_db := 0.0, pitch_var := 0.0, bus := "SFX") -> AudioStreamPlayer:
	var s := stream(sound_name)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


func stop_all_world() -> void:
	for p in _tracked.duplicate():
		if is_instance_valid(p):
			p.stop()


## Occlusion: sounds behind walls lose highs and level, like real drywall.
func _physics_process(delta: float) -> void:
	_occl_timer -= delta
	if _occl_timer > 0.0:
		return
	_occl_timer = OCCLUSION_INTERVAL
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null or _tracked.is_empty():
		return
	var space := cam.get_world_3d().direct_space_state
	var ear := cam.global_position
	for p in _tracked:
		if not is_instance_valid(p) or not p.playing:
			continue
		var src := p.global_position
		var walls := 0
		var q := PhysicsRayQueryParameters3D.create(ear, src, 1)
		var from := ear
		# Count up to 3 walls between listener and source.
		for i in 3:
			q.from = from
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			walls += 1
			from = hit.position + (src - ear).normalized() * 0.9
			if from.distance_to(ear) >= src.distance_to(ear):
				break
		var base: float = p.get_meta("base_db", 0.0)
		var target_db := base - 7.0 * walls
		var target_cut := 9000.0 if walls == 0 else (1400.0 if walls == 1 else 650.0)
		p.volume_db = lerpf(p.volume_db, target_db, 0.5)
		p.attenuation_filter_cutoff_hz = lerpf(p.attenuation_filter_cutoff_hz, target_cut, 0.5)
