# res://scenes/player/hazard_handler.gd
extends Node

@export_group("Hazards & I-Frames")
## Controls-locked duration after being hit by a hazard.
@export var stun_duration: float   = 0.8
## Invincibility window after a hit — should be >= stun_duration.
@export var iframe_duration: float = 1.5

var stun_timer: float  = 0.0
var iframe_timer: float = 0.0

@onready var player: KitOutPlayer = get_parent()


func tick_timers(delta: float) -> void:
	stun_timer   = maxf(stun_timer   - delta, 0.0)
	iframe_timer = maxf(iframe_timer - delta, 0.0)


func apply_hit(knockback: Vector2) -> void:
	if iframe_timer > 0.0:
		return
	player.velocity.x = knockback.x
	player.velocity.y = knockback.y
	stun_timer   = stun_duration
	iframe_timer = iframe_duration
	player.took_damage.emit()
	# enter_stunned() is a public method on the player — HazardHandler never
	# calls _to() directly so the state machine stays fully private to player.gd
	player.enter_stunned()
