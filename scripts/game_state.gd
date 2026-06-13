# res://scripts/game_state.gd
# Kit Out — Global Game State (Autoload Singleton)
#
# REGISTER THIS AS AN AUTOLOAD:
#   Project → Project Settings → Globals/Autoload tab
#   Path: res://scripts/game_state.gd   Name: GameState   (Enable: on)
#
# Persists across scene reloads (autoloads survive get_tree().reload_current_scene),
# which is exactly what makes checkpoints work: the level reloads fresh but
# GameState still remembers where the last checkpoint was.

extends Node

## World-space position of the most recent checkpoint the player touched.
## Vector3.INF means "no checkpoint yet" → respawn at the level's start point.
var last_checkpoint: Vector3 = Vector3.INF

## Index of the active checkpoint (for ordering / UI). -1 = none yet.
var checkpoint_index: int = -1


## Called by a Checkpoint when the player first reaches it.
## Ignores out-of-order triggers so running backward can't un-set progress.
func set_checkpoint(world_pos: Vector3, index: int) -> void:
	if index <= checkpoint_index:
		return
	last_checkpoint  = world_pos
	checkpoint_index = index


## True if any checkpoint has been activated this run.
func has_checkpoint() -> bool:
	return last_checkpoint != Vector3.INF


## Wipe checkpoint progress — call when restarting the level from the very start.
func clear_checkpoints() -> void:
	last_checkpoint  = Vector3.INF
	checkpoint_index = -1
