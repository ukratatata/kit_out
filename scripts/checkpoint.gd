# res://scripts/checkpoint.gd
# Kit Out — Checkpoint (reusable scene)
#
# Drop instances of checkpoint.tscn into a level wherever you want a respawn
# point. Set each one's `index` in the Inspector in ascending order along the
# track (0, 1, 2, …) so out-of-order back-tracking can't regress progress.
#
# On first activation it reports its position to the GameState autoload and
# changes colour (grey → green) as feedback. Activation is one-shot per run.

class_name Checkpoint
extends Area3D


## Order along the track. Must ascend (0, 1, 2…). GameState ignores any
## checkpoint whose index isn't higher than the current one.
@export var index: int = 0
## Where the player respawns. If unset, uses this node's own position.
## Use a child Marker3D or a manual offset if you want them to land slightly
## ahead of the trigger rather than inside it.
@export var respawn_point: Node3D

@onready var _flag_mesh: MeshInstance3D = $FlagMesh

var _activated: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask  = 2  # Player layer
	body_entered.connect(_on_body_entered)
	_set_active_visual(false)


func _on_body_entered(body: Node3D) -> void:
	if _activated or not body is KitOutPlayer:
		return
	_activated = true
	var pos := respawn_point.global_position if respawn_point else global_position
	GameState.set_checkpoint(pos, index)
	_set_active_visual(true)


func _set_active_visual(active: bool) -> void:
	if not _flag_mesh:
		return
	var mat := _flag_mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		# Duplicate so multiple checkpoints don't share one material instance
		var unique := mat.duplicate() as StandardMaterial3D
		unique.albedo_color = Color(0.2, 0.9, 0.3) if active else Color(0.5, 0.5, 0.5)
		unique.emission_enabled = active
		unique.emission = Color(0.1, 0.6, 0.2)
		_flag_mesh.set_surface_override_material(0, unique)
