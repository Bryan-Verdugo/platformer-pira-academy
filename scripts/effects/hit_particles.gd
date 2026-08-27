extends Node2D
class_name HitParticles

@export var particle_color: Color = Color(1.0, 0.95, 0.3, 1.0)
@export var amount: int = 14
@export var lifetime: float = 0.45

static func spawn(tree: SceneTree, world_position: Vector2, color: Color = Color(1.0, 0.95, 0.3, 1.0)) -> void:
	if tree == null or tree.current_scene == null:
		return

	var instance := HitParticles.new()
	instance.particle_color = color
	instance.z_index = 100  # que quede por encima de casi todo

	# Usamos call_deferred para evitar problemas de timing
	tree.current_scene.call_deferred("add_child", instance)
	instance.global_position = world_position


func _ready() -> void:
	var particles := CPUParticles2D.new()
	add_child(particles)

	particles.texture = _make_dot_texture()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = lifetime
	particles.explosiveness = 0.95
	particles.direction = Vector2(0, -1)
	particles.spread = 160.0
	particles.initial_velocity_min = 80.0
	particles.initial_velocity_max = 180.0
	particles.gravity = Vector2(0, 280)
	particles.scale_amount_min = 0.8
	particles.scale_amount_max = 1.6
	particles.color = particle_color
	particles.emitting = true

	await get_tree().create_timer(lifetime + 0.2).timeout
	queue_free()


static func _make_dot_texture() -> ImageTexture:
	# Textura un poco más grande para que se note mejor
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)
