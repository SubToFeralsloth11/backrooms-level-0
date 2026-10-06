extends Entity
## THE HOLLOW: 2.5 m, emaciated, eyeless. Hunts purely by sound.
## Strengths: hears footsteps through walls, out-sprints you when hunting.
## Weaknesses: blind; crouch-walking and standing still make you invisible;
## a thrown bottle drags it to the impact.

enum S { WANDER, INVESTIGATE, HUNT, SEARCH, SNIFF }

const WANDER_SPEED := 1.25
const INVESTIGATE_SPEED := 2.4
const SEARCH_SPEED := 1.6
const HUNT_SPEED := 5.0
## Alarm level at which footsteps turn curiosity into a hunt.
const HUNT_ALERT := 1.0
## Contact closer than this outside a hunt: it stops and sniffs instead.
const SNIFF_DIST := 1.2

var state := S.WANDER
var _alert := 0.0  ## builds with every sound you make, decays in silence
var _search_cells: Array[Vector3] = []
var _pause_t := 0.0
var _sniff_t := 0.0
var _sniff_cooldown := 0.0
var _last_known := Vector3.INF
var _click_t := 2.0
var _step_phase_prev := 0.0
var _spot_t := 0.0
var _seen_said := false


func _ready() -> void:
	super._ready()
	cause = "hollow"
	body = Creature.new()
	add_child(body)
	body.build({"mesh": "hollow", "skin": Color(0.36, 0.31, 0.29), "wet": 0.5, "stride": 1.25})
	Game.noise.connect(_on_noise)


func _physics_process(delta: float) -> void:
	if frozen or Game.level == null:
		body.animate(delta, 0.0, 0.2)
		return
	if not Game.is_playing():
		body.animate(delta, 0.0)
		return
	_alert = maxf(0.0, _alert - delta * (0.05 if state == S.HUNT else 0.12))
	_sniff_cooldown -= delta
	var spd := 0.0
	match state:
		S.WANDER:
			if at_goal():
				set_goal(level().cell_center(level().random_open_cell(-1, global_position, 6.0)))
			spd = follow(delta, WANDER_SPEED, 3.0)
		S.INVESTIGATE, S.HUNT:
			spd = follow(delta, INVESTIGATE_SPEED if state == S.INVESTIGATE else HUNT_SPEED, 10.0)
			if at_goal():
				_begin_search()
		S.SEARCH:
			if _pause_t > 0.0:
				_pause_t -= delta
				spd = follow(delta, 0.0)
				if _last_known != Vector3.INF:
					face(_last_known, delta, 2.0)
			elif at_goal():
				if _search_cells.is_empty():
					state = S.WANDER
					clear_path()
				else:
					set_goal(_search_cells.pop_back(), true)
					_pause_t = randf_range(0.8, 2.0)
			else:
				spd = follow(delta, SEARCH_SPEED, 5.0)
		S.SNIFF:
			spd = follow(delta, 0.0)
			var pl := player()
			if pl:
				face(pl.global_position, delta, 3.0)
			_sniff_t -= delta
			if _sniff_t <= 0.0:
				_last_known = global_position
				_begin_search()
	if state != S.HUNT and state != S.SNIFF and _sniff_cooldown <= 0.0 and flat_dist_to_player() < SNIFF_DIST:
		_sniff()
	body.animate(delta, spd, 1.0 if state == S.HUNT else (0.6 if state == S.SNIFF else (0.5 if state == S.SEARCH else 0.1)))
	_sounds(delta, spd)
	if state == S.HUNT:
		try_kill()
		if dist_to_player() < 10.0:
			player().add_fear(delta * 0.25)
	_comment(delta)


## It bumped into something warm. It freezes, head cocked, listening:
## one sound from you now and it strikes.
func _sniff() -> void:
	state = S.SNIFF
	_sniff_t = randf_range(2.5, 4.0)
	_sniff_cooldown = _sniff_t + 6.0
	_alert = maxf(_alert, 0.75)
	clear_path()
	_click_t = randf_range(0.2, 0.5)
	Audio.play_3d("hollow_click", global_position + Vector3(0, 2.2, 0), 2.0, 20.0, 0.05)
	if player():
		player().add_fear(0.5)


## Sweep 2-4 cells around the last place it heard something.
func _begin_search() -> void:
	state = S.SEARCH
	_pause_t = randf_range(1.0, 2.5)
	clear_path()
	_search_cells.clear()
	var lv := level()
	var centre := lv.world_to_cell(_last_known if _last_known != Vector3.INF else global_position)
	var want := randi_range(2, 4)
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
	if frozen or not Game.is_playing():
		return
	var heard := loudness(global_position + Vector3(0, 2.2, 0), pos, radius)
	if heard <= 0.0:
		return
	var from_player := source in ["step", "breath", "voice"]
	var new_state := S.INVESTIGATE
	if source in ["lever", "alarm", "bottle", "door"]:
		new_state = S.HUNT if global_position.distance_to(pos) < 40.0 or source == "alarm" else S.INVESTIGATE
	elif from_player:
		# Faint sounds (crouch steps, held breath) only make it curious; it
		# needs repeated or loud steps to commit to a hunt.
		var gain := (0.3 + heard * 0.7) * clampf(radius / 6.5, 0.15, 1.6)
		_alert += gain
		if radius < 3.0:
			_alert = minf(_alert, HUNT_ALERT - 0.05)
		if state == S.HUNT or _alert >= HUNT_ALERT:
			new_state = S.HUNT
	# anything else (scrapes, keypad beeps, breakers) only turns its head
	if new_state == S.HUNT:
		cause = "hollow_heard" if from_player else "hollow"
		if state != S.HUNT:
			Audio.play_3d("hollow_growl", global_position + Vector3(0, 2.2, 0), 4.0, 35.0, 0.08)
	if new_state == S.HUNT or state != S.HUNT:
		state = new_state
		_last_known = pos
		set_goal(pos, true)


func _sounds(delta: float, spd: float) -> void:
	_click_t -= delta
	if _click_t <= 0.0:
		_click_t = randf_range(1.2, 2.8) if state != S.WANDER else randf_range(3.0, 7.0)
		Audio.play_3d("hollow_click", global_position + Vector3(0, 2.2, 0), -2.0 if state != S.WANDER else -6.0, 28.0, 0.12)
	# footfalls synced to gait
	if spd > 0.3:
		var s := signf(sin(body.phase))
		if s != _step_phase_prev:
			_step_phase_prev = s
			Audio.play_3d("hollow_step", global_position, (0.0 if state == S.HUNT else -9.0), 30.0, 0.1)
			if Game.player:
				var d := dist_to_player()
				if d < 8.0 and state == S.HUNT:
					Game.player.add_shake(0.15 * (1.0 - d / 8.0))


func _comment(delta: float) -> void:
	if _seen_said:
		return
	if player_sees(body.head_global()) or player_sees(global_position + Vector3(0, 1.2, 0)):
		_spot_t += delta
		if _spot_t > 0.4:
			_seen_said = true
			Game.say("see_entity")
			Audio.play_2d("breath_scared", -8.0)
	else:
		if dist_to_player() < 25.0 and state != S.WANDER:
			Game.say("heard_something")


func on_kill() -> void:
	Audio.play_3d("hollow_scream", global_position + Vector3(0, 2.2, 0), 6.0, 60.0, 0.0)
