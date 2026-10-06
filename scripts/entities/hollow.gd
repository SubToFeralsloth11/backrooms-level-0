extends Entity
## THE HOLLOW: 2.5 m, emaciated, eyeless. Hunts purely by sound.
## Strengths: hears footsteps through walls, out-sprints you when hunting.
## Weaknesses: blind; crouch-walking and standing still make you invisible;
## a thrown bottle drags it to the impact.

enum S { WANDER, INVESTIGATE, HUNT, SEARCH }

const WANDER_SPEED := 1.25
const INVESTIGATE_SPEED := 2.4
const HUNT_SPEED := 5.0

var state := S.WANDER
var _search_t := 0.0
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
	var spd := 0.0
	match state:
		S.WANDER:
			if at_goal():
				set_goal(level().cell_center(level().random_open_cell(-1, global_position, 6.0)))
			spd = follow(delta, WANDER_SPEED, 3.0)
		S.INVESTIGATE, S.HUNT:
			spd = follow(delta, INVESTIGATE_SPEED if state == S.INVESTIGATE else HUNT_SPEED, 10.0)
			if at_goal():
				state = S.SEARCH
				_search_t = randf_range(4.0, 7.0)
		S.SEARCH:
			spd = follow(delta, 0.0)
			_search_t -= delta
			if _search_t <= 0.0:
				state = S.WANDER
				path = PackedVector3Array()
				path_i = 0
	body.animate(delta, spd, 1.0 if state == S.HUNT else (0.5 if state == S.SEARCH else 0.1))
	_sounds(delta, spd)
	try_kill()
	_comment(delta)


func _on_noise(pos: Vector3, radius: float, source: String) -> void:
	if frozen or not Game.is_playing():
		return
	var d := global_position.distance_to(pos)
	var ear := global_position + Vector3(0, 2.2, 0)
	var r := radius if clear_line(ear, pos + Vector3(0, 0.5, 0)) else radius * 0.55
	if d > r:
		return
	var from_player := source in ["step", "breath", "voice"]
	var close := d < 10.0
	var new_state := S.INVESTIGATE
	if source in ["lever", "alarm", "bottle", "door"]:
		new_state = S.HUNT if d < 40.0 or source == "alarm" else S.INVESTIGATE
	elif from_player and (close or radius >= 15.0 or state == S.HUNT):
		new_state = S.HUNT
	if new_state == S.HUNT and state != S.HUNT:
		Audio.play_3d("hollow_growl", global_position + Vector3(0, 2.2, 0), 4.0, 35.0, 0.08)
	if new_state >= state or state == S.SEARCH or state == S.WANDER:
		state = new_state
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
