extends CharacterBody3D

@onready var visual_container: Node3D = $VisualContainer


# Usamos export para ajustar valores desde el editor sin tocar el código
@export_group("Horizontal Movement")
@export var speed: float = 14.0
@export var acceleration: float = 100.0
@export var friction: float = 80.0

@export_group("Vertical Movement")
@export var jump_velocity: float = 20.0
@export var gravity_multiplier: float = 4.0

# Obtener la gravedad de la configuración del proyecto es más profesional
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(delta: float) -> void:
	# 1. Gravedad (Solo si no estamos en el suelo)
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta

	# 2. Salto (Usando la acción agnóstica que creamos)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# 3. Dirección de entrada (Agnóstica al Input Map)
	var input_dir := Input.get_axis("move_left", "move_right")
	
	# 4. Aplicar movimiento o fricción
	if input_dir!= 0:
		velocity.x = move_toward(velocity.x, input_dir * speed, acceleration * delta)
		# Rotación visual (usando la "nariz" que creamos)
		var target_rotation := PI/2 if input_dir > 0 else -PI/2
		visual_container.rotation.y = lerp_angle(visual_container.rotation.y, target_rotation, 0.2)
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)

	# 5. Forzar Z a cero por seguridad (Refuerzo del Axis Lock)
	velocity.z = 0.0

	# 6. Ejecutar el movimiento físico
	move_and_slide()
