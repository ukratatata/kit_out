extends Node

@export_group("Hazards & I-Frames")
## Controls-locked duration after being hit by a hazard (hammer, projectile…).
@export var stun_duration: float = 0.8
## Time (in seconds) the player is invincible and ignores hits after taking damage.
@export var iframe_duration: float = 1.5

var stun_timer: float = 0.0
var iframe_timer: float = 0.0

@onready var player: KitOutPlayer = get_parent()

func tick_timers(delta: float) -> void:
	stun_timer = maxf(stun_timer - delta, 0.0)
	iframe_timer = maxf(iframe_timer - delta, 0.0)



## Public hit interface for hazards (hammers, projectiles, traps…).
## Sets knockback velocity, fires the took_damage signal (camera shake
## auto-connects to it), and staggers the player: grounded horizontal hits
## enter OFF_BALANCE; launched hits go to FALL so air physics handles the arc.
## State exit cleanup runs automatically — a hit during a slide restores the
## standing collision shape, a hit mid-air-crouch resets it, etc.
func apply_hit(knockback: Vector2) -> void:
	# 1. Check if the player is currently invincible. If so, ignore the hit.
	if iframe_timer > 0.0:
		return

	# 2. Apply knockback and lock controls
	player.velocity.x = knockback.x
	player.velocity.y = knockback.y
	stun_timer = stun_duration  
	
	# 3. Start the invincibility window so follow-up hits are ignored
	iframe_timer = iframe_duration  
	
	# Emit the signal from the PLAYER so the camera still shakes!
	player.took_damage.emit()
	player._to(KitOutPlayer.PlayerState.STUNNED)
