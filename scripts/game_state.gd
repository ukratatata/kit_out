# res://scripts/game_state.gd
# Kit Out — Global Game State (Autoload Singleton)
#
# REGISTER AS AUTOLOAD: Project Settings → Globals/Autoload
#   Path: res://scripts/game_state.gd   Name: GameState
#
# Survives get_tree().reload_current_scene(), which is what makes checkpoints
# work: the level reloads fresh but GameState still remembers the last one.

extends Node

## World-space respawn position of the most recent checkpoint reached.
## Vector3.INF = no checkpoint yet → spawn at the level's default position.
var last_checkpoint: Vector3 = Vector3.INF

## Progress measure of the active checkpoint (its X position along the track).
## Checkpoints only override if they're FURTHER than this, so back-tracking
## through an earlier checkpoint can't regress the respawn point.
var checkpoint_progress: float = -INF


## Called by a Checkpoint when the player reaches it. `progress` is the
## checkpoint's X coordinate; only forward progress is accepted.
func set_checkpoint(world_pos: Vector3, progress: float) -> void:
	if progress <= checkpoint_progress:
		return
	last_checkpoint     = world_pos
	checkpoint_progress = progress


func has_checkpoint() -> bool:
	return last_checkpoint != Vector3.INF


## Wipe progress — call when restarting the level from the very start.
func clear_checkpoints() -> void:
	last_checkpoint     = Vector3.INF
	checkpoint_progress = -INF
