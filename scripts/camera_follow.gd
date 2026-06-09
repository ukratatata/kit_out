# res://scripts/camera_follow.gd
extends Camera3D

@export_group("Target Definition")
@export var target: Node3D 

@export_group("Framing Window (Deadzone)")
@export var deadzone_width: float = 2.0     # El ancho de la "caja invisible" donde el gato se mueve libremente
@export var max_screen_distance: float = 4.0 # NUEVO: El límite DURO (El muro invisible)
@export var screen_offset_x: float = 4.0    # NEW: Shifts the camera center ahead of the cat
@export var height_offset: float = 3.0      # Altura de la cámara respecto al gato
@export var follow_speed: float = 4.0       # Velocidad de suavizado cuando el gato empuja la caja

@export_group("Dynamic Camera Tilt")
@export var rotation_speed: float = 4.0
@export var look_side_angle: float = 12.0
@export var look_up_angle: float = 8.0
@export var look_down_angle: float = -10.0

# Posición teórica a la que la cámara quiere ir
var target_cam_pos: Vector3
var base_rotation_x: float = 0.0
var target_rot_y: float = 0.0

func _ready() -> void:
	base_rotation_x = rotation.x
	target_rot_y = deg_to_rad(-look_side_angle) # Por defecto miramos a la derecha
	
	# Inicializamos la posición objetivo donde está la cámara ahora mismo
	if target:
		target_cam_pos = global_position
		target_cam_pos.x = target.global_position.x
		target_cam_pos.y = target.global_position.y + height_offset

func _physics_process(delta: float) -> void:
	if not target:
		return

# --- 1. LÓGICA DE DEADZONE (Eje X) ---
	# We create a "Ghost Target" in front of the cat
	var ideal_center_x = target.global_position.x + screen_offset_x
	
	# We calculate distance to the Ghost Target, not the cat itself
	var distance_to_target_x = ideal_center_x - target_cam_pos.x
	var half_deadzone = deadzone_width / 2.0

	# Si el gato empuja el borde DERECHO de la caja invisible...
	if distance_to_target_x > half_deadzone:
		target_cam_pos.x += (distance_to_target_x - half_deadzone)
		
	# Si el gato empuja el borde IZQUIERDO de la caja invisible...
	elif distance_to_target_x < -half_deadzone:
		target_cam_pos.x += (distance_to_target_x + half_deadzone)

	# --- 2. LÓGICA DE ALTURA (Eje Y) ---
	target_cam_pos.y = target.global_position.y + height_offset

	# --- 3. SUAVIZADO (Lerp) ---
	global_position.x = lerp(global_position.x, target_cam_pos.x, follow_speed * delta)
	global_position.y = lerp(global_position.y, target_cam_pos.y, follow_speed * delta)

	# --- 3.5 LÍMITE DURO (HARD CLAMP) ---
	# The invisible wall also needs to respect the new Ghost Target
	var actual_distance_x = ideal_center_x - global_position.x

	if actual_distance_x > max_screen_distance:
		global_position.x = ideal_center_x - max_screen_distance
		target_cam_pos.x = global_position.x 

	elif actual_distance_x < -max_screen_distance:
		global_position.x = ideal_center_x + max_screen_distance
		target_cam_pos.x = global_position.x

	# --- 4. ROTACIÓN DINÁMICA ---
	var target_rot_x := base_rotation_x

	# Inclinación Izquierda/Derecha
	if target.velocity.x > 0.5:
		target_rot_y = deg_to_rad(-look_side_angle)
	elif target.velocity.x < -0.5:
		target_rot_y = deg_to_rad(look_side_angle)

	# Inclinación Arriba/Abajo
	if target.velocity.y > 1.0: 
		target_rot_x = base_rotation_x + deg_to_rad(look_up_angle)
	elif target.velocity.y < -1.0: 
		target_rot_x = base_rotation_x + deg_to_rad(look_down_angle)

	rotation.x = lerp_angle(rotation.x, target_rot_x, rotation_speed * delta)
	rotation.y = lerp_angle(rotation.y, target_rot_y, rotation_speed * delta)
