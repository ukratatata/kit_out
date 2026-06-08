# res://scripts/camera_follow.gd
extends Camera3D

@export_group("Target Definition")
@export var target: Node3D 

@export_group("Cinematic Framing")
@export var follow_speed: float = 3.0
@export var framing_offset_x: float = 3.0   
@export var height_offset: float = 3.5      

var current_look_offset: float = 0.0
var current_rotation := Vector3(
func _ready() -> void:
	current_look_offset = framing_offset_x 

func _physics_process(delta: float) -> void:
	if not target:
		return

	# 1. Base position
	var target_pos := target.global_position
	target_pos.y += height_offset

	# 2. Rule of Thirds Logic
	if target.velocity.x > 0.5:
		current_look_offset = framing_offset_x
		current_rotation.y = right_camera
	elif target.velocity.x < -0.5:
		current_look_offset = -framing_offset_x
		
	target_pos.x += current_look_offset

	# 3. Smooth Lerp (Only on X and Y)
	global_position.x = lerp(global_position.x, target_pos.x, follow_speed * delta)
	global_position.y = lerp(global_position.y, target_pos.y, follow_speed * delta)
