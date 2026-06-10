# res://scripts/camera_follow.gd
# Kit Out — Camera Controller
#
# What changed from the original:
#   • target is now typed CharacterBody3D (was Node3D — caused silent runtime errors)
#   • Dynamic tilt reads target.camera_velocity, not target.velocity directly.
#     This means per-state filtering in the player (off-balance, slide, wall) is
#     respected — the camera never sees raw physics chaos.
#   • Screen shake via add_trauma(amount). The player's `took_damage` signal
#     connects automatically in _ready(). Call add_trauma() from any other system too.
#
# ── SCENE SETUP ────────────────────────────────────────────────────────────────
# The Camera3D target export will keep the existing assignment automatically,
# since KitOutPlayer extends CharacterBody3D. No re-assignment needed.
# ────────────────────────────────────────────────────────────────────────────────

extends Camera3D


@export_group("Target Definition")
## Typed as CharacterBody3D. Accepts KitOutPlayer since it extends it.
## The camera accesses .camera_velocity via a safe cast — no raw velocity reads.
@export var target: CharacterBody3D


@export_group("Framing Window (Deadzone)")
## Width of the invisible box where the player moves freely without moving the camera.
@export var deadzone_width: float     = 2.0
## Hard clamp — the camera will never let the player get further than this off-center.
@export var max_screen_distance: float = 4.0
## Shifts the camera center ahead of the player to show upcoming obstacles.
@export var screen_offset_x: float   = 4.0
## Camera height above the player.
@export var height_offset: float     = 3.0
## Lerp speed when the player pushes the deadzone edge.
@export var follow_speed: float      = 4.0


@export_group("Dynamic Camera Tilt")
@export var rotation_speed: float    = 4.0
@export var look_side_angle: float   = 12.0
@export var look_up_angle: float     = 8.0
@export var look_down_angle: float   = -10.0


@export_group("Screen Shake")
## Maximum world-unit positional offset at full trauma.
@export var shake_max_offset: float  = 0.35
## How fast trauma decays per second (higher = shorter shake).
@export var shake_decay_rate: float  = 2.5


# ── Runtime ────────────────────────────────────────────────────────────────────
var target_cam_pos: Vector3
var base_rotation_x: float = 0.0
var target_rot_y: float    = 0.0

## Trauma value 0–1. Square it for a non-linear falloff (strong start, quick settle).
var _trauma: float        = 0.0
var _shake_offset: Vector3 = Vector3.ZERO


# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	base_rotation_x = rotation.x
	target_rot_y    = deg_to_rad(-look_side_angle)

	if target:
		target_cam_pos   = global_position
		target_cam_pos.x = target.global_position.x
		target_cam_pos.y = target.global_position.y + height_offset

	# Auto-connect to player damage signal for instant shake without manual wiring
	if target and target.has_signal("took_damage"):
		target.took_damage.connect(_on_player_took_damage)


func _physics_process(delta: float) -> void:
	if not target:
		return

	# ── Read filtered velocity from player ────────────────────────────────────
	# Cast to KitOutPlayer to access camera_velocity.
	# Falls back to raw velocity if target is some other CharacterBody3D.
	var cam_vel := Vector2.ZERO
	var kit_player := target as KitOutPlayer
	if kit_player:
		cam_vel = kit_player.camera_velocity
	else:
		cam_vel = Vector2(target.velocity.x, target.velocity.y)

	# ── 1. Deadzone (X axis) ──────────────────────────────────────────────────
	var ideal_center_x := target.global_position.x + screen_offset_x
	var dist_x         := ideal_center_x - target_cam_pos.x
	var half_dz        := deadzone_width / 2.0

	if dist_x > half_dz:
		target_cam_pos.x += (dist_x - half_dz)
	elif dist_x < -half_dz:
		target_cam_pos.x += (dist_x + half_dz)

	# ── 2. Height (Y axis) ────────────────────────────────────────────────────
	target_cam_pos.y = target.global_position.y + height_offset

	# ── 3. Smooth Follow ──────────────────────────────────────────────────────
	global_position.x = lerp(global_position.x, target_cam_pos.x, follow_speed * delta)
	global_position.y = lerp(global_position.y, target_cam_pos.y, follow_speed * delta)

	# ── 4. Hard Clamp ─────────────────────────────────────────────────────────
	var actual_dist_x := ideal_center_x - global_position.x
	if actual_dist_x > max_screen_distance:
		global_position.x = ideal_center_x - max_screen_distance
		target_cam_pos.x  = global_position.x
	elif actual_dist_x < -max_screen_distance:
		global_position.x = ideal_center_x + max_screen_distance
		target_cam_pos.x  = global_position.x

	# ── 5. Dynamic Tilt (reads camera_velocity, not raw physics) ─────────────
	var target_rot_x := base_rotation_x

	if cam_vel.x > 0.5:
		target_rot_y = deg_to_rad(-look_side_angle)
	elif cam_vel.x < -0.5:
		target_rot_y = deg_to_rad(look_side_angle)

	if cam_vel.y > 1.0:
		target_rot_x = base_rotation_x + deg_to_rad(look_up_angle)
	elif cam_vel.y < -1.0:
		target_rot_x = base_rotation_x + deg_to_rad(look_down_angle)

	rotation.x = lerp_angle(rotation.x, target_rot_x, rotation_speed * delta)
	rotation.y = lerp_angle(rotation.y, target_rot_y, rotation_speed * delta)

	# ── 6. Screen Shake ───────────────────────────────────────────────────────
	_tick_shake(delta)
	global_position += _shake_offset


# ── Public API ────────────────────────────────────────────────────────────────

## Add trauma to trigger a screen shake. Clamps to 1.0.
## amount = 0.3 (light), 0.6 (hit), 1.0 (big impact)
## Call this from any game system — hazard hits, explosions, big landings, etc.
func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


# ── Private Helpers ───────────────────────────────────────────────────────────

func _on_player_took_damage() -> void:
	add_trauma(0.6)


func _tick_shake(delta: float) -> void:
	_trauma = maxf(_trauma - shake_decay_rate * delta, 0.0)
	var shake := _trauma * _trauma  # Square for non-linear decay
	_shake_offset = Vector3(
		randf_range(-1.0, 1.0) * shake_max_offset * shake,
		randf_range(-1.0, 1.0) * shake_max_offset * shake,
		0.0
	)
