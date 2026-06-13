# res://scripts/trampoline.gd
# Kit Out — Trampoline (Phase 3, obstacle #4)
#
# A bouncy pad that launches the player upward on contact, overriding their
# fall speed entirely so the bounce height is consistent no matter how hard
# they came down. The signature "boing" of a Crash Course course.
#
# SETUP: place the scene root where the pad surface should sit, centred on the
# track. The pad is thin; the BounceZone Area3D just above it does the launch.
#
# HOW IT LAUNCHES: the trampoline calls player.bounce(force), a public method
# that sets velocity.y directly and drops the player into FALL/JUMP air state.
# This bypasses knockback/stun — a trampoline is friendly, not a hazard.
#
# DESIGN NOTES:
# • bounce_force is an absolute upward velocity, not additive — every bounce
#   reaches the same apex. With the player's jump_velocity of 20, a force of
#   34 roughly doubles jump height; 45+ clears tall obstacles.
# • horizontal_keep (0–1) preserves run momentum through the bounce. 1.0 keeps
#   all of it (great for flinging the player forward across a gap); lower values
#   bleed speed so the bounce is more vertical.
# • A row of trampolines at increasing heights makes a natural "staircase" the
#   player bounces up — a classic vertical traversal section.

class_name Trampoline
extends Node3D


## Minimum upward launch, used when the player lands gently or steps on.
@export var min_bounce: float   = 18.0
## Incoming fall speed converted back into upward speed. 1.0 = perfect rebound;
## >1.0 gains energy each bounce (1.15 = a super-bounce that ramps you higher).
@export var bounce_multiplier: float = 1.1
## Hard ceiling so a huge fall can't fling the player offscreen.
@export var max_bounce: float   = 70.0
## Fraction of horizontal speed kept through the bounce (0 = vertical, 1 = all).
@export_range(0.0, 1.0, 0.05) var horizontal_keep: float = 1.0
## Minimum seconds between launches — stops double-triggering on one contact.
@export var bounce_cooldown: float = 0.15
## The Area3D just above the pad surface. Assign in the Inspector.
@export var bounce_zone: Area3D

@onready var _pad: Node3D = $Pad

var _cooldown: float = 0.0
var _squash_t: float = 0.0  # Drives the pad's compress-and-rebound animation


func _ready() -> void:
	if bounce_zone:
		bounce_zone.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

	# Pad squash animation: snaps down on bounce, springs back out
	if _squash_t > 0.0:
		_squash_t = maxf(_squash_t - delta * 4.0, 0.0)
		var compress := sin(_squash_t * PI)  # 0→1→0 over the window
		_pad.scale.y = 1.0 - compress * 0.6
		_pad.position.y = -compress * 0.15
	else:
		_pad.scale.y = 1.0
		_pad.position.y = 0.0


func _on_body_entered(body: Node3D) -> void:
	if _cooldown > 0.0:
		return
	var player := body as KitOutPlayer
	if not player:
		return
	# Only launch when the player is moving downward or resting on the pad —
	# prevents a trampoline from killing an upward jump passing through it
	if player.velocity.y > 1.0:
		return
	_cooldown = bounce_cooldown
	_squash_t = 1.0
	# Bounce proportional to fall speed: how hard they hit becomes how high they
	# go. abs() because downward velocity is negative. Clamped so a gentle step
	# still pops and a screaming fall doesn't launch to orbit.
	var impact := absf(player.velocity.y)
	var launch := clampf(impact * bounce_multiplier, min_bounce, max_bounce)
	player.bounce(launch, horizontal_keep)
