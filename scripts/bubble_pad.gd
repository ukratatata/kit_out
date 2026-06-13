# res://scripts/bubble_pad.gd
# Kit Out — Bubble Pad (Phase 3, obstacle #6)
#
# A floating bounce pad that launches the player up, then POPS and vanishes for
# a few seconds before reforming. Unlike the trampoline (always available, fall-
# proportional), the bubble is a one-use stepping stone: cross a gap by hopping
# bubble to bubble, but each one is gone the instant you use it.
#
# SETUP: place the scene root where the bubble floats. Mid-air placement is the
# point — chains of bubbles across a pit make a timing-and-rhythm traversal.
#
# DESIGN NOTES:
# • bounce_force is a fixed upward launch (not fall-proportional) so bubble
#   chains are predictable to plan around.
# • respawn_time governs the risk: short = forgiving, long = you must keep
#   moving because backtracking onto a popped bubble drops you.
# • Place bubbles at rising heights for a climb, or level for a horizontal hop.

class_name BubblePad
extends Node3D


## Upward launch velocity applied on contact (absolute, not fall-proportional).
@export var bounce_force: float   = 26.0
## Fraction of horizontal speed kept through the bounce.
@export_range(0.0, 1.0, 0.05) var horizontal_keep: float = 1.0
## Seconds the bubble stays popped before reforming.
@export var respawn_time: float   = 2.5
## The Area3D that detects the player. Assign in the Inspector.
@export var bounce_zone: Area3D

@onready var _visual: Node3D = $Visual

var _popped: bool = false
var _timer: float = 0.0
var _reform_t: float = 0.0  # 0→1 grow animation when reforming


func _ready() -> void:
	if bounce_zone:
		bounce_zone.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _popped:
		_timer -= delta
		if _timer <= 0.0:
			_reform()
		return

	# Reform grow-in animation
	if _reform_t < 1.0:
		_reform_t = minf(_reform_t + delta * 4.0, 1.0)
		_visual.scale = Vector3.ONE * _reform_t
	else:
		# Gentle idle bob so it reads as floating
		_visual.position.y = sin(Time.get_ticks_msec() * 0.003) * 0.08


func _on_body_entered(body: Node3D) -> void:
	if _popped:
		return
	var player := body as KitOutPlayer
	if not player:
		return
	# Only pop when descending or level — don't pop on an upward pass-through
	if player.velocity.y > 1.0:
		return
	player.bounce(bounce_force, horizontal_keep)
	_pop()


func _pop() -> void:
	_popped = true
	_timer  = respawn_time
	_visual.visible = false


func _reform() -> void:
	_popped = false
	_reform_t = 0.0
	_visual.scale = Vector3.ZERO
	_visual.position.y = 0.0
	_visual.visible = true
