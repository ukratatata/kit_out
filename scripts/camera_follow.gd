# res://scripts/camera_follow.gd
extends Camera3D

@export_group("Target Definition")
@export var target: Node3D 

@export_group("Cinematic Framing")
@export var follow_speed: float = 5.0
@export var framing_offset_x: float = 3.0   
@export var height_offset: float = 3.2     #

@export_group("Dynamic Camera Tilt")
@export var rotation_speed: float = 3.0		# Speed of rotation
@export var look_ahead_angle: float = -22.4   # Degrees to tilt right
@export var look_behind_angle: float = 5 	# Degrees to tilt left
@export var look_up_angle: float = 8.0      # Degrees to tilt up when jumping
@export var look_down_angle: float = -10.0  # Degrees to tilt down when falling

var current_look_offset: float = 0.0
var base_rotation_x: float = 0.0
var target_rot_y: float = 0.0

func _ready() -> void:
	current_look_offset = framing_offset_x 
	
	# We save whatever X rotation you set in the editor as our "default" resting angle
	base_rotation_x = rotation.x
	# Default to looking right
	target_rot_y = deg_to_rad(look_ahead_angle)

func _physics_process(delta: float) -> void:
	if not target:
		return

	# --- 1. POSITION TRACKING (Rule of Thirds) ---
	var target_pos := target.global_position
	target_pos.y += height_offset

	if target.velocity.x > 0.5:
		current_look_offset = framing_offset_x
	elif target.velocity.x < -0.5:
		current_look_offset = 0.0
		
	target_pos.x += current_look_offset

	# Smoothly move position
	global_position.x = lerp(global_position.x, target_pos.x, follow_speed * delta)
	global_position.y = lerp(global_position.y, target_pos.y, follow_speed * delta)

# --- 2. DYNAMIC ROTATION (Tilt) ---
	var target_rot_x := base_rotation_x

	# A. Left/Right Tilt (Y-axis)
	if target.velocity.x > 0.5:
		# Moving Right: Needs NEGATIVE rotation to look right
		target_rot_y = deg_to_rad(look_ahead_angle)
	elif target.velocity.x < -0.5:
		# Moving Left: Needs POSITIVE rotation to look left
		target_rot_y = deg_to_rad(look_behind_angle)

	# B. Up/Down Tilt (X-axis)
	if target.velocity.y > 1.0: 
		# If jumping up, look up slightly
		target_rot_x = base_rotation_x + deg_to_rad(look_up_angle)
	elif target.velocity.y < -1.0: 
		# If falling down, look down slightly
		target_rot_x = base_rotation_x + deg_to_rad(look_down_angle)

	# Smoothly rotate using lerp_angle (crucial for radians!)
	rotation.x = lerp_angle(rotation.x, target_rot_x, rotation_speed * delta)
	rotation.y = lerp_angle(rotation.y, target_rot_y, rotation_speed * delta)
