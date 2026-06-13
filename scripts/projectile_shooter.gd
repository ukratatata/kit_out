# res://scripts/projectile_shooter.gd
# Kit Out — Projectile Shooter (Phase 3, obstacle #7)
#
# A turret that fires Projectile instances across the track at a fixed interval.
# Each projectile flies straight, stuns on contact, and self-destructs on a
# solid hit or after its lifetime. The player dodges by jumping over, ducking
# under, or threading the gap between shots.
#
# SETUP: place the scene root at the muzzle. `fire_direction` aims the shots
# (default -X, firing left toward an approaching player). Muzzle Y picks the
# dodge type: low = jump over, high = duck under.
#
# DESIGN NOTES:
# • Pair a low shooter (jump) with a high one (duck) on offset intervals for an
#   alternating rhythm.
# • projectile_speed vs fire_interval controls how many shots are in flight.
# • The projectile scene is assigned in the Inspector so its look/size is editable.

class_name ProjectileShooter
extends Node3D


## Seconds between shots.
@export var fire_interval: float    = 1.8
## Direction the projectile travels (normalised internally). Default: left.
@export var fire_direction: Vector3 = Vector3(-1, 0, 0)
## Projectile travel speed (units/sec).
@export var projectile_speed: float = 16.0
## Knockback dealt on hit: x = away from impact, y = upward pop.
@export var knockback: Vector2      = Vector2(26.0, 10.0)
## Seconds a projectile lives before self-destructing if it hits nothing.
@export var projectile_lifetime: float = 4.0
## The projectile scene to spawn. Assign projectile.tscn in the Inspector.
@export var projectile_scene: PackedScene
## Optional muzzle flash/visual cue — purely cosmetic, can be left empty.
@export var muzzle: Node3D

var _timer: float = 0.0
var _dir: Vector3 = Vector3.LEFT


func _ready() -> void:
	_dir = fire_direction.normalized()
	_timer = fire_interval * 0.5  # Small offset so it doesn't fire on frame 0


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = fire_interval
		_fire()


func _fire() -> void:
	if projectile_scene == null:
		push_warning("ProjectileShooter has no projectile_scene assigned.")
		return
	var proj := projectile_scene.instantiate() as Projectile
	if proj == null:
		push_warning("projectile_scene root is not a Projectile.")
		return
	# Add to the level first, THEN set the world position (so it isn't parented
	# to the shooter and dragged around if the shooter ever moves).
	get_tree().current_scene.add_child(proj)
	proj.global_position = global_position
	proj.setup(_dir * projectile_speed, knockback, projectile_lifetime)
