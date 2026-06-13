# res://scripts/skipping_hammer.gd
# Kit Out — Skipping-Rope Hammer (Phase 3, obstacle #5)
#
# A full-circle variant of the swinging hammer. Instead of a pendulum, the arm
# rotates a complete 360° around its anchor, so the head sweeps along the floor
# like a skipping rope — the player must JUMP the moment it passes underfoot.
#
# SETUP: place the scene root at the ANCHOR (the rotation centre, roughly head
# height above the floor). The arm length determines how far out the head
# sweeps; at the bottom of its circle it skims the ground.
#
# DESIGN NOTES:
# • rotation_speed sets the rhythm — slower is a clear "wait… jump" beat, faster
#   demands quick reactions. The bottom of the arc is the danger moment.
# • phase_offset staggers multiple skipping hammers so they form a rolling
#   pattern the player runs through.
# • Pairs well right after a swinging hammer to vary the timing demand: one is a
#   side-to-side dodge, the other a jump-the-rope.

class_name SkippingHammer
extends Node3D


## Radians per second of the full rotation. TAU ≈ one revolution per second.
@export var rotation_speed: float = 3.2
## Cycle offset (0–1). Stagger multiple skipping hammers.
@export_range(0.0, 1.0, 0.05) var phase_offset: float = 0.0
## Knockback on hit: x = push away from anchor, y = upward pop.
@export var knockback: Vector2    = Vector2(30.0, 12.0)
## Per-hammer hit cooldown.
@export var hit_cooldown: float   = 0.6
## The Area3D on the head. Assign in the Inspector.
@export var hitbox: Area3D

@onready var _pivot: AnimatableBody3D = $Pivot

var _cooldown: float = 0.0


func _ready() -> void:
	_pivot.rotation.z = phase_offset * TAU


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	# Full rotation around Z — the head traces a complete circle, skimming the
	# floor at the bottom of the arc like a jump-rope.
	_pivot.rotation.z += rotation_speed * delta

	if _cooldown > 0.0 or hitbox == null:
		return
	for body in hitbox.get_overlapping_bodies():
		var player := body as KitOutPlayer
		if player:
			_hit(player)
			break


func _hit(player: KitOutPlayer) -> void:
	_cooldown = hit_cooldown
	var dir := signf(player.global_position.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	player.apply_hit(Vector2(dir * knockback.x, knockback.y))
