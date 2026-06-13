# res://scripts/checkpoint.gd
# Kit Out — Checkpoint (reusable scene)
#
# Drop instances of checkpoint.tscn into a level. No configuration needed:
# checkpoints self-order by their X position along the track, so reaching a
# checkpoint further along always wins, and back-tracking can't regress.
#
# On first activation it reports its respawn position to the GameState autoload
# and turns green. One-shot per run.

class_name Checkpoint
extends Area3D


## Where the player respawns. Defaults to the child RespawnPoint marker.
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
	# Use X position as the ordering key — no manual index to keep in sync
	GameState.set_checkpoint(pos, global_position.x)
	_set_active_visual(true)


func _set_active_visual(active: bool) -> void:
	if not _flag_mesh:
		return
	var mat := _flag_mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		var unique := mat.duplicate() as StandardMaterial3D
		unique.albedo_color = Color(0.2, 0.9, 0.3) if active else Color(0.5, 0.5, 0.5)
		unique.emission_enabled = active
		unique.emission = Color(0.1, 0.6, 0.2)
		_flag_mesh.set_surface_override_material(0, unique)
