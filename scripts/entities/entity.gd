class_name Entity
extends CharacterBody3D
## Shared entity plumbing: grid pathfinding, steering, contact kill, LOS tests,
## wall-attenuated hearing.

const KILL_DIST := 0.85
## Physics layers: 1 = world, 4 = entities. Entities bump into each other but
## never the player (the kill check is a distance test).
const LAYER_ENTITY := 4
## Hearing loses as much per wall as the player's ears do (-7 dB ≈ x0.45 range).
const WALL_HEARING := 0.45

var frozen := false  ## inspection mode: no AI, idle animation only
var body: Creature
var path := PackedVector3Array()
var path_i := 0
var path_goal := Vector3.INF
var cause := "entity"
var _repath_t := 0.0
var _stuck_t := 0.0


func _ready() -> void:
	add_to_group("entity")
	collision_layer = LAYER_ENTITY
	collision_mask = 1 | LAYER_ENTITY
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.24
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	add_child(cs)


func level() -> Level:
	return Game.level


func player() -> Player:
	return Game.player as Player


func set_goal(p: Vector3, force := false) -> void:
	if not force and path_goal != Vector3.INF and p.distance_to(path_goal) < 0.8 and path_i < path.size():
		return
	path_goal = p
	path = level().find_path(global_position, p)
	path_i = 1 if path.size() > 1 else 0


func clear_path() -> void:
	path = PackedVector3Array()
	path_i = 0
	path_goal = Vector3.INF


func at_goal() -> bool:
	return path_i >= path.size()


## Steer along the path at `spd`; returns actual horizontal speed.
func follow(delta: float, spd: float, turn := 8.0) -> float:
	var v := Vector3.ZERO
	if path_i < path.size():
		var target := path[path_i]
		var to := target - global_position
		to.y = 0
		if to.length() < 0.35:
			path_i += 1
		else:
			v = to.normalized() * spd
	velocity.x = lerpf(velocity.x, v.x, 1.0 - exp(-10.0 * delta))
	velocity.z = lerpf(velocity.z, v.z, 1.0 - exp(-10.0 * delta))
	velocity.y = -2.0
	move_and_slide()
	var hv := Vector3(velocity.x, 0, velocity.z)
	# Blocked by another entity in a one-cell corridor: give up this leg.
	if v.length() > 0.5 and hv.length() < 0.1:
		_stuck_t += delta
		if _stuck_t > 1.5:
			_stuck_t = 0.0
			path_i = path.size()
	else:
		_stuck_t = 0.0
	if hv.length() > 0.15:
		face(global_position + hv, delta, turn)
	return hv.length()


func face(p: Vector3, delta: float, turn := 8.0) -> void:
	var to := p - global_position
	var yaw := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn * delta))


func dist_to_player() -> float:
	var p := player()
	return INF if p == null else global_position.distance_to(p.global_position)


func flat_dist_to_player() -> float:
	var p := player()
	if p == null:
		return INF
	return Vector2(global_position.x - p.global_position.x, global_position.z - p.global_position.z).length()


func try_kill() -> bool:
	var p := player()
	if p == null or not p.alive or not Game.is_playing():
		return false
	if flat_dist_to_player() < KILL_DIST:
		on_kill()
		p.die(body.head_global() if body else global_position + Vector3(0, 1.6, 0), cause)
		return true
	return false


func on_kill() -> void:
	pass


func clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Walls (max 3) between two points, counted like Audio's occlusion.
func walls_between(a: Vector3, b: Vector3) -> int:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	var dir := (b - a).normalized()
	var walls := 0
	for i in 3:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		walls += 1
		q.from = hit.position + dir * 0.9
		if q.from.distance_to(a) >= b.distance_to(a):
			break
	return walls


## How loud a noise is at `ear`: 0 = inaudible, 1 = right next to it.
## A sound carries either straight through the walls (losing range per wall)
## or around them along the corridors, whichever is louder.
func loudness(ear: Vector3, pos: Vector3, radius: float) -> float:
	var d := ear.distance_to(pos)
	if d > radius:
		return 0.0
	var direct := radius * pow(WALL_HEARING, walls_between(ear, pos + Vector3(0, 0.5, 0)))
	var best := 1.0 - d / direct if d < direct else 0.0
	if best < 0.5:
		var route := level().find_path(global_position, pos)
		if route.size() > 0:
			var walk := 0.0
			for i in range(1, route.size()):
				walk += route[i - 1].distance_to(route[i])
			if walk < radius:
				best = maxf(best, 1.0 - walk / radius)
	return clampf(best, 0.0, 1.0)


## True if the player can currently see point `p` (in view, unoccluded, and lit).
## `cone` (degrees, half-angle from view centre) and `max_dist` narrow it further.
func player_sees(p: Vector3, need_light := true, cone := 180.0, max_dist := INF) -> bool:
	var pl := player()
	if pl == null:
		return false
	var cam := pl.camera
	if not cam.is_position_in_frustum(p):
		return false
	var to := p - cam.global_position
	if to.length() > max_dist:
		return false
	if cone < 180.0 and rad_to_deg((-cam.global_basis.z).angle_to(to)) > cone:
		return false
	if not clear_line(cam.global_position, p):
		return false
	if not need_light:
		return true
	return not level().is_dark(level().world_to_cell(p)) or flashlight_on_me(p) > 0.3


## Beam intensity (0..1, battery dimming included) falling on `p`; 0 if unlit.
func flashlight_on_me(p: Vector3) -> float:
	var pl := player()
	if pl == null or not pl.flashlight_on or not pl.hands.flashlight.visible:
		return 0.0
	var fl := pl.hands.flashlight
	var to := p - fl.global_position
	if to.length() > fl.spot_range:
		return 0.0
	var ang := rad_to_deg((-fl.global_basis.z).angle_to(to))
	if ang >= fl.spot_angle * 0.9 or not clear_line(fl.global_position, p):
		return 0.0
	return clampf(fl.light_energy / 2.4, 0.0, 1.0)
