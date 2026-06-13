# res://scripts/kill_zone.gd
# Kit Out — Kill Zone (reusable scene)
#
# A volume that "kills" the player on contact and respawns them at the last
# checkpoint (or the level's start if none reached). Drop instances below the
# track, in pits, or anywhere falling should reset the run.
#
# SETUP: place and scale the scene so its collision volume covers the fall area.
# A single long, wide, deep box under the whole level works fine — make it big.
#
# Respawn rule:
#   • GameState has a checkpoint → teleport the player there, zero velocity.
#   • No checkpoint yet          → reload the scene (clean restart from spawn).

class_name KillZone
extends Area3D


## Brief screen-shake-style feedback on death via the player's took_damage
## signal. Off by default — death already reads clearly via the teleport.
@export var shake_on_death: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask  = 2  # Player layer
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var player := body as KitOutPlayer
	if not player:
		return
	_respawn(player)


func _respawn(player: KitOutPlayer) -> void:
	if GameState.has_checkpoint():
		player.respawn_at(GameState.last_checkpoint)
		if shake_on_death:
			player.took_damage.emit()
	else:
		# No checkpoint reached — restart the level cleanly
		get_tree().reload_current_scene()
