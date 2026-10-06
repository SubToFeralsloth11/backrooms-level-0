extends Entity
## THE WATCHER: a long-limbed crawler, head hanging upside down. Wakes when
## the power comes back.
## Strengths: very fast and nearly silent while unobserved; it is always
## closing in while your back is turned.
## Weaknesses: it physically cannot move while you are looking at it in light.
## Darkness (or a dead flashlight) lets it move freely.

const SPEED := 6.2

var _was_moving := false
var _scrape_t := 0.0


func _ready() -> void:
	super._ready()
	cause = "watcher"
	body = Creature.new()
	add_child(body)
	body.build({"mesh": "watcher", "quad": true, "skin": Color(0.33, 0.3, 0.29), "wet": 0.7, "stride": 0.9})
	var cs: CollisionShape3D = get_child(0)
	(cs.shape as CapsuleShape3D).height = 0.9
	cs.position.y = 0.45


func observed() -> bool:
	var pts := [global_position + Vector3(0, 0.5, 0), body.head_global(), global_position + global_basis.z * 0.5 + Vector3(0, 0.6, 0)]
	for p in pts:
		if player_sees(p):
			return true
	return false


func _physics_process(delta: float) -> void:
	if frozen or Game.level == null:
		body.animate(delta, 0.0, 0.0)
		return
	if not Game.is_playing():
		return
	if observed():
		velocity = Vector3.ZERO
		if _was_moving:
			_was_moving = false
			Audio.play_3d("watcher_crack", body.head_global(), -4.0, 18.0, 0.1)
		return  # completely still: no animation while watched
	var pl := player()
	if pl == null:
		return
	_repath_t -= delta
	if _repath_t <= 0.0:
		_repath_t = 0.3
		set_goal(pl.global_position, true)
	var spd := follow(delta, SPEED, 14.0)
	_was_moving = spd > 0.5
	body.animate(delta, spd, 0.8)
	_scrape_t -= delta
	if spd > 0.5 and _scrape_t <= 0.0:
		_scrape_t = randf_range(0.6, 1.4)
		Audio.play_3d("watcher_scrape", global_position, -10.0, 16.0, 0.15)
		if randf() < 0.3:
			Audio.play_3d("watcher_crack", body.head_global(), -12.0, 14.0, 0.15)
	try_kill()


func on_kill() -> void:
	Audio.play_3d("hollow_scream", body.head_global(), 4.0, 40.0, 0.0)
