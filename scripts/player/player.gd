extends CharacterBody2D

## ===== CONFIGURACIÓN DE MOVIMIENTO =====
## Todos estos valores están pensados como punto de partida "sólido".
## Ajustalos jugando: es la parte más importante del feel del juego.

@export_group("Movimiento horizontal")
@export var speed: float = 220.0          # velocidad máxima en px/s
@export var acceleration: float = 1800.0  # qué tan rápido llega a speed
@export var friction: float = 2000.0      # qué tan rápido frena al soltar input

@export_group("Salto")
@export var jump_velocity: float = -420.0     # negativo = hacia arriba
@export var gravity: float = 1400.0
@export var fall_gravity_multiplier: float = 1.6  # cae más rápido de lo que sube (se siente mejor)
@export var jump_cut_multiplier: float = 0.5       # al soltar salto antes de tiempo, corta el impulso

@export_group("Assist (coyote time / buffer)")
@export var coyote_time: float = 0.12     # margen para saltar tras salir de una plataforma
@export var jump_buffer_time: float = 0.12  # margen para que el salto "espere" al aterrizaje

# ===== ESTADO INTERNO =====
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var was_on_floor: bool = false
var facing_right: bool = true

@export_group("Vida")
@export var max_health: int = 2000
@export var invulnerability_duration: float = 0.8
@export var knockback_force: float = 250.0

@export_group("Screen Shake")
@export var shake_strength: float = 8.0
@export var shake_duration: float = 0.25

var current_health: int = max_health
var is_invulnerable: bool = false
var shake_time_left: float = 0.0

signal health_changed(current: int, max_hp: int)
signal died

# Referencia al sprite animado (frames ya vienen con cabeza+cuerpo pegados)
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var invulnerability_timer: Timer = $InvulnerabilityTimer
@onready var camera: Camera2D = $Camera2D
@onready var sfx_player: AudioStreamPlayer2D = $SfxPlayer

const HIT_PARTICLES := preload("res://scripts/effects/hit_particles.gd")
const PLAYER_HIT_SOUND := preload("res://assets/audio/sfx/player/player_get_hit.wav")

var spawn_position: Vector2


func _ready() -> void:
	add_to_group("player")
	spawn_position = global_position
	if invulnerability_timer:
		invulnerability_timer.timeout.connect(_on_invulnerability_timer_timeout)

	# Invulnerabilidad breve al spawnear
	is_invulnerable = true
	await get_tree().create_timer(0.4).timeout
	is_invulnerable = false
	animated_sprite.visible = true          # ← esta línea es la clave
	animated_sprite.play("idle")            # ← y esta para que empiece en idle


func _physics_process(delta: float) -> void:
	_handle_gravity(delta)
	_handle_coyote_time(delta)
	_handle_jump_buffer(delta)
	_handle_horizontal_movement(delta)
	_handle_jump_input()
	_update_facing()

	was_on_floor = is_on_floor()
	move_and_slide()
	_handle_enemy_contact_damage()

	_update_animation_state()
	_update_invulnerability_flicker()


func _process(delta: float) -> void:
	# El screen shake se actualiza en _process (no en physics) para que se vea
	# suave incluso si el framerate físico y el visual no coinciden exactamente.
	if shake_time_left > 0.0 and camera:
		shake_time_left -= delta
		var falloff := shake_time_left / shake_duration
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_strength * falloff
	elif camera:
		camera.offset = Vector2.ZERO


func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		# Cae más rápido de lo que sube: sensación "arcade" clásica de plataformero
		var g = gravity * fall_gravity_multiplier if velocity.y > 0 else gravity
		velocity.y += g * delta
	else:
		velocity.y = 0.0


func _handle_coyote_time(delta: float) -> void:
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta


func _handle_jump_buffer(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer -= delta


func _handle_horizontal_movement(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")

	if direction != 0:
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _handle_jump_input() -> void:
	# Salto real: hay buffer pendiente Y (está en el piso O dentro del margen de coyote time)
	var can_jump: bool = coyote_timer > 0.0
	if jump_buffer_timer > 0.0 and can_jump:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		
		# Sonido de salto
		$JumpSFX.play()

	# Salto corto: si suelta el botón mientras todavía sube, corta el impulso
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier


func _update_facing() -> void:
	if velocity.x > 5.0:
		facing_right = true
	elif velocity.x < -5.0:
		facing_right = false
	# El arte base mira hacia la IZQUIERDA por defecto (tal como me describiste
	# el sheet de Magaleta), así que flippeamos SOLO al mirar a la derecha.
	animated_sprite.flip_h = facing_right


func bounce_off_enemy(enemy_position: Vector2 = global_position) -> void:
	# Llamado por el enemigo cuando el Player lo pisa en la cabeza.
	# Rebote más alto y con un empujón horizontal alejándose del enemigo,
	# para que el golpe se sienta con peso real, no solo un mini-salto.
	velocity.y = jump_velocity * 0.85
	var push_dir := signf(global_position.x - enemy_position.x)
	if push_dir == 0.0:
		push_dir = -1.0 if facing_right else 1.0
	velocity.x = push_dir * 180.0


# ===== VIDA / DAÑO =====

func _handle_enemy_contact_damage() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider == null or not collider.is_in_group("enemy"):
			continue
		# Solo cuenta como golpe si el contacto es LATERAL (normal casi horizontal).
		# Un contacto mayormente vertical es el pisotón en la cabeza, que ya
		# se resuelve del lado del enemigo (HeadHitbox) y no debe dañarte.
		if absf(collision.get_normal().x) > 0.5:
			var dmg := 500
			if collider.has_method("get_contact_damage"):
				dmg = collider.get_contact_damage()
			take_damage(dmg, collider.global_position)


func take_damage(amount: int, from_position: Vector2 = global_position) -> void:
	if is_invulnerable or current_health <= 0:
		return

	current_health = max(0, current_health - amount)
	health_changed.emit(current_health, max_health)

	sfx_player.stream = PLAYER_HIT_SOUND
	sfx_player.play()
	HIT_PARTICLES.spawn(get_tree(), global_position, Color(1.0, 0.3, 0.3))

	if current_health <= 0:
		died.emit()
		_handle_death()
		return

	is_invulnerable = true
	invulnerability_timer.start(invulnerability_duration)
	shake_time_left = shake_duration

	# Empujón alejándose de la fuente de daño, para poder reposicionarse
	var knockback_dir := signf(global_position.x - from_position.x)
	if knockback_dir == 0.0:
		knockback_dir = -1.0 if facing_right else 1.0
	velocity.x = knockback_dir * knockback_force
	velocity.y = jump_velocity * 0.4


func _handle_death() -> void:
	# Congela control mientras se reproduce la animación de derrota, y respawnea después.
	is_invulnerable = true
	set_physics_process(false)
	velocity = Vector2.ZERO
	animated_sprite.play("defeated")
	await get_tree().create_timer(1.2).timeout
	set_physics_process(true)
	respawn()


func respawn() -> void:
	set_physics_process(false)

	# === Pantalla de muerte ===
	var death_layer := CanvasLayer.new()
	death_layer.layer = 100
	get_tree().current_scene.add_child(death_layer)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_layer.add_child(bg)

	var label1 := Label.new()
	label1.text = "Aún es muy pronto para rendirte."
	label1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label1.set_anchors_preset(Control.PRESET_FULL_RECT)
	label1.add_theme_font_size_override("font_size", 28)
	label1.add_theme_color_override("font_color", Color("ff9ecb"))
	label1.position.y = -30
	death_layer.add_child(label1)

	var label2 := Label.new()
	label2.text = "La muerte solo es una parada en tu camino."
	label2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label2.set_anchors_preset(Control.PRESET_FULL_RECT)
	label2.add_theme_font_size_override("font_size", 22)
	label2.add_theme_color_override("font_color", Color("ff9ecb"))
	label2.position.y = 30
	death_layer.add_child(label2)

	# Efecto de temblor
	var shake_time := 0.0
	while shake_time < 2.2:
		label1.position.x = randf_range(-3, 3)
		label2.position.x = randf_range(-3, 3)
		await get_tree().process_frame
		shake_time += get_process_delta_time()

	# Restaurar posición y vida
	current_health = max_health
	health_changed.emit(current_health, max_health)

	var target_pos: Vector2 = spawn_position
	if is_instance_valid(GameManager) and GameManager.has_checkpoint:
		target_pos = GameManager.checkpoint_position
	global_position = target_pos
	velocity = Vector2.ZERO
	animated_sprite.visible = true
	animated_sprite.play("idle")

	death_layer.queue_free()
	is_invulnerable = false
	set_physics_process(true)


func _on_invulnerability_timer_timeout() -> void:
	is_invulnerable = false
	animated_sprite.visible = true


func _update_invulnerability_flicker() -> void:
	if is_invulnerable:
		# Parpadeo simple: visible/invisible cada ~100ms mientras dura la invulnerabilidad
		animated_sprite.visible = (Time.get_ticks_msec() / 100) % 2 == 0


func _update_animation_state() -> void:
	if is_invulnerable:
		animated_sprite.play("hurt")
		return
	if not is_on_floor():
		if velocity.y < 0:
			animated_sprite.play("jump")
		else:
			animated_sprite.play("fall")
	elif abs(velocity.x) > 10.0:
		animated_sprite.play("walk")
	else:
		animated_sprite.play("idle")
