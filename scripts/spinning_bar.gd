# res://scripts/spinning_bar.gd
# Kit Out — Spinning Bar (Phase 3, obstacle #3)
#
# A vertical paddle that rotates around the X axis, sweeping through the Y-Z
# plane. From the 2.5D side camera this reads as a bar swinging up-up-and-over
# toward and away from the screen — and its Z-sweep is what knocks the player
# clean off the track depth-wise.
#
# Why X-axis rotation (not Y): a Z-oriented bar rotating around Y sweeps mostly
# into/out of the screen and looks static from the side. Rotating a Y-oriented
# paddle around X makes the motion fully visible and gives the off-track knock.
#
# SETUP: place the scene root at track centre. The paddle is ~2.4 units tall
# and pivots about its own base, so the root Y should sit near floor level.
#
# DESIGN NOTES:
# • phase_offset (0–1) desynchronises multiple bars on the same stretch.
# • rotation_speed sign flips sweep direction (toward vs away from camera first).
# • Knockback pushes the player along Z (off the track) plus a small upward pop,
#   so a clean hit throws them off the course rather than just back along it.

class_name SpinningBar
extends Node3D


## Radians per second. TAU ≈ one full revolution per second.
@export var rotation_speed: float  = 2.2
## Cycle offset (0–1). Desynchronises multiple bars on the same section.
@export_range(0.0, 1.0, 0.05) var phase_offset: float = 0.0
## Knockback on hit. x = small lateral nudge, z = OFF-TRACK push, y = upward pop.
## The z component is the headline effect — it ejects the player from the lane.
@export var knockback: Vector3     = Vector3(7.0, 16.0, 15.0)
## Per-bar hit cooldown — prevents re-hitting on the same pass.
@export var hit_cooldown: float    = 0.8
## The Area3D surrounding the paddle. Assign in the Inspector.
@export var hitbox: Area3D

@onready var _pivot: AnimatableBody3D = $Pivot

var _cooldown: float = 0.0


func _ready() -> void:
	# Born desynchronised — offset the starting sweep angle
	_pivot.rotation.x = phase_offset * TAU


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_pivot.rotation.x += rotation_speed * delta

	if _cooldown > 0.0 or hitbox == null:
		return
	for body in hitbox.get_overlapping_bodies():
		var player := body as KitOutPlayer
		if player:
			_hit(player)
			break


func _hit(player: KitOutPlayer) -> void:
	_cooldown = hit_cooldown
	# Lateral nudge follows which side the player is on; the big push is +Z (off track)
	var dir := signf(player.global_position.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	player.global_position.y += 0.5
	player.apply_hit_3d(Vector3(dir * knockback.x, knockback.y, knockback.z))
