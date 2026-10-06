class_name Entity
extends CharacterBody3D
## Shared entity plumbing: grid pathfinding, steering, contact kill, LOS tests.

const KILL_DIST := 0.85

var frozen := false  ## inspection mode: no AI, idle animation only
var body: Creature
var path := PackedVector3Array()
var path_i := 0
var path_goal := Vector3.INF
var cause := "entity"
var _repath_t := 0.0


func _ready() -> void:
	add_to_group("entity")
	collision_layer = 4
	collision_mask = 1
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


func try_kill() -> bool:
	var p := player()
	if p == null or not p.alive or not Game.is_playing():
		return false
	var d := Vector2(global_position.x - p.global_position.x, global_position.z - p.global_position.z).length()
	if d < KILL_DIST:
		on_kill()
		p.die(body.head_global() if body else global_position + Vector3(0, 1.6, 0), cause)
		return true
	return false


func on_kill() -> void:
	pass


func clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## True if the player can currently see point `p` (in view, unoccluded, and lit).
func player_sees(p: Vector3, need_light := true) -> bool:
	var pl := player()
	if pl == null:
		return false
	var cam := pl.camera
	if not cam.is_position_in_frustum(p):
		return false
	if not clear_line(cam.global_position, p):
		return false
	if not need_light:
		return true
	return not level().is_dark(level().world_to_cell(p)) or flashlight_on_me(p)


func flashlight_on_me(p: Vector3) -> bool:
	var pl := player()
	if pl == null or not pl.flashlight_on or not pl.hands.flashlight.visible:
		return false
	var fl := pl.hands.flashlight
	var to := p - fl.global_position
	if to.length() > fl.spot_range:
		return false
	var ang := rad_to_deg((-fl.global_basis.z).angle_to(to))
	return ang < fl.spot_angle * 0.9 and clear_line(fl.global_position, p)
