# res://scripts/swinging_hammer.gd
# Kit Out — Swinging Hammer (Phase 3, obstacle #1)
#
# Pendulum hazard. Place the scene root at the ANCHOR (top) point; the arm
# hangs down and swings around Z, staying in the 2.5D gameplay plane.
#
# STRUCTURE:
# • Pivot IS the AnimatableBody3D (solid handle, World layer) and the script
#   rotates it directly. This matters: sync_to_physics only tracks transform
#   changes made ON the body — parent-driven motion desyncs it (the collision
#   and its child mesh lag behind). Rotating the body itself is the canonical
#   moving-platform pattern and keeps the push velocity-aware.
# • The handle is BOTH solid (the body's collision blocks the player) AND a
#   hit zone (ArmHitBox Area3D) — touching any part of the hammer stuns.
# • Head (HitBox): pass-through Area3D damage zone.
#
# HIT RULES:
# • Knockback is identical on every hit: the player's velocity is SET to the
#   knockback vector (see player.apply_hit), so prior momentum is irrelevant.
# • Direction is away from the hammer's anchor X — stable and predictable,
#   not dependent on where the swinging head happens to be.
# • Every hit stuns: controls locked for the player's stun_duration.
#
# DESIGN NOTES:
# • phase_offset is the level-design superpower: place 3 hammers in a row
#   with offsets 0.0 / 0.33 / 0.66 and they sweep as a wave — the moving gap
#   between them becomes the player's path. Synced hammers (all 0.0) are boring.
# • The sin() pendulum slows naturally at the arc ends like a real swing,
#   so the safe moment to pass is when a hammer hovers at its extreme.

class_name SwingingHammer
extends Node3D


## Degrees the arm swings to each side of vertical.
@export var swing_arc: float = 70.0
## Seconds for one full back-and-forth cycle.
@export var swing_period: float = 2.4
## Cycle offset (0–1). Stagger multiple hammers so they never sync up.
@export_range(0.0, 1.0, 0.05) var phase_offset: float = 0.0
## Knockback applied on hit: x = push away from the anchor, y = upward pop.
## Always identical — the player's velocity is set, not added to.
@export var knockback: Vector2 = Vector2(15.0, 15.0)
## Seconds of immunity from THIS hammer after it lands a hit.
@export var hit_cooldown: float = 0.6
## The Area3D on the hammer head that detects the player (mask = Player layer).
@export var hitbox: Area3D
## The Area3D along the handle — touching the handle also stuns.
@export var arm_hitbox: Area3D

@onready var _pivot: Node3D = $Pivot

var _time: float = 0.0
var _cooldown: float = 0.0


func _ready() -> void:
	_time = phase_offset * swing_period


func _physics_process(delta: float) -> void:
	_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)

	# sin() pendulum — fast through the middle, hovering at the arc ends
	var t := (_time / swing_period) * TAU
	_pivot.rotation.z = deg_to_rad(swing_arc) * sin(t)

	# Overlap polling instead of body_entered: a player standing in the
	# hammer's path keeps getting hit each time the cooldown expires, and a
	# sweeping hammer catches players reliably even at high relative speed.
	if _cooldown > 0.0:
		return
	for box in [hitbox, arm_hitbox]:
		if box == null:
			continue
		for body in box.get_overlapping_bodies():
			var player := body as KitOutPlayer
			if player:
				_hit(player)
				return


func _hit(player: KitOutPlayer) -> void:
	_cooldown = hit_cooldown
	# Push away from the hammer's ANCHOR x — deterministic, the same on every
	# hit from a given side, regardless of where the head is in its swing
	var dir := signf(player.global_position.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	player.hazards.apply_hit(Vector2(dir * knockback.x, knockback.y))
