extends Node
## Sound playback: buses, name→stream resolution (with _1.._n variants),
## spatial one-shots with wall occlusion (muffle + attenuation), and loops.

const SFX_DIR := "res://audio/sfx/"
const EXTS := ["wav", "mp3", "ogg"]
const OCCLUSION_INTERVAL := 0.08
const PATH_RECHECK := 0.5
## Reverb per acoustic zone: [room_size, damping, wet, predelay_ms].
const REVERB := {
	"hall": [0.35, 0.55, 0.14, 12.0],
	"wing": [0.55, 0.45, 0.2, 18.0],
	"breaker": [0.18, 0.25, 0.24, 5.0],
	"stairwell": [0.8, 0.12, 0.36, 22.0],
}

var _cache := {}
var _variants := {}
var _tracked: Array[AudioStreamPlayer3D] = []
var _occl_timer := 0.0
var _reverb_fx: AudioEffectReverb
var _heart: AudioStreamPlayer
var _dread_breath: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reverb_fx = _reverb(0.35, 0.55, 0.14)
	_add_bus("SFX", [_reverb_fx])
	_add_bus("Ambience", [])
	_add_bus("UI", [])

	_preload_all()
	_heart = _loop_2d("heartbeat")
	_dread_breath = _loop_2d("breath_scared")


func _loop_2d(sound_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = loop_stream(sound_name)
	p.bus = "SFX"
	p.volume_db = -80.0
	add_child(p)
	return p


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


## Level the occlusion pass aims a tracked 3D player at. Looping entity sounds
## must set this instead of writing volume_db (occlusion owns volume_db).
func set_base_db(p: AudioStreamPlayer3D, db: float) -> void:
	p.set_meta("base_db", db)


## Acoustic zone of a world position: "breaker", "stairwell", "wing" or "hall".
func zone_at(pos: Vector3) -> String:
	var lv: Level = Game.level
	if lv == null:
		return "hall"
	if pos.z > (Level.H - 1) * Level.CELL:
		return "stairwell"
	var c := lv.world_to_cell(pos)
	if Level.BREAKER.has_point(c):
		return "breaker"
	if lv.zone_of(c) == Level.Zone.DARK:
		return "wing"
	return "hall"


## Floor surface under a world position (footstep material).
func floor_at(pos: Vector3) -> String:
	var z := zone_at(pos)
	return "concrete" if z == "breaker" or z == "stairwell" else "carpet"


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
## Rays are cast at three heights (doorway tops/bottoms, low furniture gaps);
## a source behind walls whose walking route is short (open doorway around a
## corner) is treated as diffracted: mild muffle, not full wall loss.
func _physics_process(delta: float) -> void:
	_update_dread(delta)
	_occl_timer -= delta
	if _occl_timer > 0.0:
		return
	_occl_timer = OCCLUSION_INTERVAL
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		return
	var ear := cam.global_position
	_update_reverb(ear)
	if _tracked.is_empty():
		return
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(ear, ear, 1)
	var now := Time.get_ticks_msec()
	for p in _tracked:
		if not is_instance_valid(p) or not p.playing:
			continue
		var src := p.global_position
		var walls := 3
		for h in [0.0, -0.6, 0.5]:
			var w := _count_walls(space, q, ear + Vector3(0, h, 0), src + Vector3(0, h * 0.5, 0))
			walls = mini(walls, w)
			if walls == 0:
				break
		var diffracted := false
		if walls > 0:
			if now >= int(p.get_meta("path_t", 0)):
				p.set_meta("path_t", now + int(PATH_RECHECK * 1000.0))
				p.set_meta("path_open", _short_route(ear, src))
			diffracted = p.get_meta("path_open", false)
		var base: float = p.get_meta("base_db", 0.0)
		var target_db := base - (3.0 if diffracted else 7.0 * walls)
		var target_cut := 9000.0 if walls == 0 else (3200.0 if diffracted else (1400.0 if walls == 1 else 650.0))
		p.volume_db = lerpf(p.volume_db, target_db, 0.5)
		p.attenuation_filter_cutoff_hz = lerpf(p.attenuation_filter_cutoff_hz, target_cut, 0.5)


## Walls (max 3) crossed on the straight line a→b.
func _count_walls(space: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D, a: Vector3, b: Vector3) -> int:
	var walls := 0
	var from := a
	var step := (b - a).normalized() * 0.9
	var total := a.distance_to(b)
	q.to = b
	for i in 3:
		q.from = from
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		walls += 1
		from = hit.position + step
		if from.distance_to(a) >= total:
			break
	return walls


## True when the walkable route ear→src is barely longer than the straight
## line, i.e. sound can bend through an open doorway.
func _short_route(ear: Vector3, src: Vector3) -> bool:
	var lv: Level = Game.level
	if lv == null:
		return false
	var straight := Vector2(ear.x - src.x, ear.z - src.z).length()
	if straight > 24.0:
		return false
	var a := lv.world_to_cell(ear)
	var b := lv.world_to_cell(src)
	if lv.is_wall(a) or lv.is_wall(b):
		return false
	var ids := lv.astar.get_id_path(a, b)
	if ids.is_empty():
		return false
	return (ids.size() - 1) * Level.CELL <= straight * 1.45 + 1.5


func _update_reverb(ear: Vector3) -> void:
	var z := zone_at(ear)
	var r: Array = REVERB[z]
	_reverb_fx.room_size = lerpf(_reverb_fx.room_size, r[0], 0.25)
	_reverb_fx.damping = lerpf(_reverb_fx.damping, r[1], 0.25)
	_reverb_fx.wet = lerpf(_reverb_fx.wet, r[2], 0.25)
	_reverb_fx.predelay_msec = lerpf(_reverb_fx.predelay_msec, r[3], 0.25)


## Low heartbeat + held breath under everything while something hunts you
## (player.fear, fed by entity proximity and entity hunt states).
func _update_dread(delta: float) -> void:
	var pl: Node = Game.player
	var fear := 0.0
	if pl != null and is_instance_valid(pl) and pl.alive and Game.is_playing():
		fear = pl.fear
	var k := 1.0 - exp(-2.0 * delta)
	var heart_db := -80.0 if fear < 0.05 else lerpf(-30.0, -9.0, fear)
	var breath_db := -80.0 if fear < 0.45 else lerpf(-30.0, -15.0, (fear - 0.45) / 0.55)
	for pair in [[_heart, heart_db], [_dread_breath, breath_db]]:
		var p: AudioStreamPlayer = pair[0]
		if p.stream == null:
			continue
		p.volume_db = lerpf(p.volume_db, pair[1], k)
		if pair[1] > -70.0 and not p.playing:
			p.play()
		elif p.playing and p.volume_db < -70.0:
			p.stop()
	_heart.pitch_scale = lerpf(0.9, 1.45, fear)
