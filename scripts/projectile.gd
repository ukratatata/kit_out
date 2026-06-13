# res://scripts/projectile.gd
# Kit Out — Projectile (fired by ProjectileShooter)
#
# A self-contained flying hazard. Moves in a straight line, stuns the player on
# contact, and self-destructs on any solid hit or after its lifetime expires.
# Each projectile owns its own movement — no external manager iterating a group.

class_name Projectile
extends Area3D


var velocity: Vector3 = Vector3.ZERO
var knockback: Vector2 = Vector2(26.0, 10.0)
var _life: float = 4.0


func setup(vel: Vector3, kb: Vector2, lifetime: float) -> void:
	velocity = vel
	knockback = kb
	_life = lifetime


func _ready() -> void:
	collision_layer = 0
	collision_mask  = 1 | 2  # World + Player
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	var player := body as KitOutPlayer
	if player:
		var dir := signf(player.global_position.x - global_position.x)
		if dir == 0.0:
			dir = 1.0
		player.apply_hit(Vector2(dir * knockback.x, knockback.y))
	# Player or wall — either way the projectile is spent
	queue_free()
