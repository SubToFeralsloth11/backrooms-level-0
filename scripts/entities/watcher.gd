extends Entity
## THE WATCHER: a long-limbed crawler, head hanging upside down. Wakes when
## the power comes back.
## Strengths: very fast and nearly silent while unobserved; it is always
## closing in while your back is turned.
## Weaknesses: it physically cannot move while you are looking at it in light.
## Darkness (or a dead flashlight) lets it move freely.

enum S { ROAM, CHASE, LOST, SEARCH }

const SPEED := 6.2
const ROAM_SPEED := 2.6
## It only locks up when you look straight at it: half-angle of the cone
## around the view centre, and how far your eyes can pin it down.
const FREEZE_CONE := 20.0
const FREEZE_DIST := 25.0
## How far it can see you (it needs an unbroken line, like you do).
const SIGHT := 30.0

var state := S.ROAM
var _last_known := Vector3.INF
var _search_cells: Array[Vector3] = []
var _sight_t := 0.0
var _was_moving := false
var _scrape_t := 0.0
var _fold := 0.0


func _ready() -> void:
	super._ready()
	cause = "watcher"
	body = Creature.new()
	add_child(body)
	body.build({"mesh": "watcher", "quad": true, "skin": Color(0.33, 0.3, 0.29), "wet": 0.7, "stride": 0.9})
	var cs: CollisionShape3D = get_child(0)
	(cs.shape as CapsuleShape3D).height = 0.9
	cs.position.y = 0.45
	Game.noise.connect(_on_noise)
	Game.wrong_lever.connect(_on_wrong_lever)


func observed() -> bool:
	var pl := player()
	if pl == null or pl.reading:
		return false  # the journal page covers your view
	var pts := [global_position + Vector3(0, 0.5, 0), body.head_global(), global_position + global_basis.z * 0.5 + Vector3(0, 0.6, 0)]
	for p in pts:
		if player_sees(p, true, FREEZE_CONE, FREEZE_DIST):
			return true
	return false


func _physics_process(delta: float) -> void:
	if frozen or Game.level == null:
		_update_fold(delta)
		body.animate(delta, 0.0, 0.0)
		return
	if not Game.is_playing():
		return
	var pl := player()
	if pl == null:
		return
	if observed():
		velocity = Vector3.ZERO
		if _was_moving:
			_was_moving = false
			_cue("watcher_crack", body.head_global(), -2.0, 0.1)
			pl.add_fear(0.25)
		return  # completely still: no animation while watched
	_sight_t -= delta
	if _sight_t <= 0.0:
		_sight_t = 0.3
		if _sees_player():
			state = S.CHASE
			_last_known = pl.global_position
			set_goal(_last_known, true)
		elif state == S.CHASE:
			state = S.LOST  # lost sight: run to where it last saw you
	var spd := 0.0
	match state:
		S.CHASE, S.LOST:
			spd = follow(delta, SPEED, 14.0)
			if at_goal() and state == S.LOST:
				_begin_search()
		S.SEARCH:
			spd = follow(delta, ROAM_SPEED * 1.4, 10.0)
			if at_goal():
				if _search_cells.is_empty():
					state = S.ROAM
					clear_path()
				else:
					set_goal(_search_cells.pop_back(), true)
		S.ROAM:
			if at_goal():
				set_goal(level().cell_center(level().random_open_cell(-1, global_position, 8.0)))
			spd = follow(delta, ROAM_SPEED, 6.0)
	_was_moving = spd > 0.5
	_update_fold(delta)
	body.animate(delta, spd, 0.8 if state != S.ROAM else 0.3)
	_scrape_t -= delta
	if spd > 0.5 and _scrape_t <= 0.0:
		# The closer it is, the louder and quicker the dragging of its limbs.
		var near := clampf(1.0 - dist_to_player() / 24.0, 0.0, 1.0)
		_scrape_t = lerpf(1.6, 0.45, near) * randf_range(0.8, 1.2)
		_cue("watcher_scrape", global_position, lerpf(-18.0, -4.0, near), 0.15)
		Game.emit_noise(global_position, 9.0, "scrape")
		if randf() < 0.15 + near * 0.35:
			_cue("watcher_crack", body.head_global(), lerpf(-18.0, -6.0, near), 0.15)
	if state == S.CHASE or state == S.LOST:
		try_kill()


func _cue(sound: String, at: Vector3, db: float, pitch_var: float) -> void:
	Audio.play_3d(sound, at, db, 26.0, pitch_var)


func _sees_player() -> bool:
	var pl := player()
	var eye := body.head_global() + Vector3(0, 0.3, 0)
	var target := pl.global_position + Vector3(0, 1.2, 0)
	return eye.distance_to(target) < SIGHT and clear_line(eye, target)


## Sweep 2-3 open cells around where it lost you.
func _begin_search() -> void:
	state = S.SEARCH
	clear_path()
	_search_cells.clear()
	var lv := level()
	var centre := lv.world_to_cell(_last_known if _last_known != Vector3.INF else global_position)
	var want := randi_range(2, 3)
	for i in 30:
		if _search_cells.size() >= want:
			break
		var c := centre + Vector2i(randi_range(-3, 3), randi_range(-3, 3))
		if c == centre or c.x < 1 or c.y < 1 or c.x >= Level.W - 1 or c.y >= Level.H - 1 or not lv.is_open(c):
			continue
		var p := lv.cell_center(c)
		if not _search_cells.has(p):
			_search_cells.append(p)


func _on_noise(pos: Vector3, radius: float, source: String) -> void:
	if frozen or not Game.is_playing() or state == S.CHASE:
		return
	if not (source in ["lever", "alarm", "step", "bottle", "door"]):
		return
	if loudness(body.head_global(), pos, radius) <= 0.0:
		return
	state = S.LOST
	_last_known = pos
	set_goal(pos, true)


func _on_wrong_lever() -> void:
	# A wrong pull wakes it fully: it knows exactly where you are, once.
	var pl := player()
	if frozen or pl == null:
		return
	state = S.LOST
	_last_known = pl.global_position
	set_goal(_last_known, true)


## Fold the front limbs under the body when you are close in front of it,
## so the long arms never reach into the camera.
func _update_fold(delta: float) -> void:
	var pl := player()
	var target := 0.0
	if pl:
		var cam := pl.camera.global_position
		var to := cam - global_position
		to.y = 0.0
		if to.length() < 4.0 and global_basis.z.dot(to.normalized()) > 0.0:
			target = clampf((4.0 - to.length()) / 2.0, 0.0, 1.0)
	_fold = move_toward(_fold, target, delta * 2.0)
	body.fold = _fold


func on_kill() -> void:
	Audio.play_3d("hollow_scream", body.head_global(), 4.0, 40.0, 0.0)
