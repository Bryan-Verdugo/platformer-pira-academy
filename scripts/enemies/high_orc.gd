extends CharacterBody2D

## ===== HIGH ORC — patrulla, persecución, pisotón en la cabeza, esquiva =====

@export_group("Movimiento")
@export var patrol_speed: float = 40.0
@export var chase_speed: float = 140.0
@export var gravity: float = 1400.0

@export_group("Patrulla")
@export var patrol_walk_time_min: float = 1.0
@export var patrol_walk_time_max: float = 2.5
@export var patrol_pause_time_min: float = 0.5
@export var patrol_pause_time_max: float = 1.5

@export_group("Combate")
@export var max_hits: int = 3
@export var hurt_duration: float = 0.6
@export var dodge_chance: float = 0.3
@export var dodge_speed: float = 220.0
@export var dodge_duration: float = 0.35
@export var dodge_trigger_range_x: float = 30.0

@export_group("Daño de contacto")
@export var contact_damage_min: int = 430
@export var contact_damage_max: int = 570

@export_group("Ataque")
@export var attack_range: float = 70.0
@export var attack_windup_time: float = 0.35
@export var attack_active_time: float = 0.2
@export var attack_cooldown: float = 1.5
@export var attack_hitbox_offset: float = 45.0
@export var attack_hitbox_reach: float = 55.0
@export var attack_hitbox_height: float = 45.0

@export_group("Persecución")
@export var lose_sight_grace_time: float = 0.7
@export var fallback_chase_range: float = 260.0

enum State { PATROL, CHASE, HURT, DEFEATED, DODGE, ATTACK }
var state: State = State.PATROL

var facing_dir: int = 1
var is_patrol_paused: bool = false
var hit_count: int = 0
var has_been_hit_once: bool = false
var player_ref: CharacterBody2D = null
var stomp_incoming_last_frame: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var debug_label: Label = $DebugLabel
@onready var sfx_player: AudioStreamPlayer2D = $SfxPlayer
@onready var step_player: AudioStreamPlayer2D = $StepPlayer
@onready var step_timer: Timer = $StepTimer

const ATTACK_SOUNDS := [
	preload("res://assets/audio/sfx/ork_warrior_attack1.wav"),
	preload("res://assets/audio/sfx/ork_warrior_attack2.wav"),
]
const STEP_SOUNDS := [
	preload("res://assets/audio/sfx/ork_warrior_step1.wav"),
	preload("res://assets/audio/sfx/ork_warrior_step2.wav"),
]
const DIE_SOUNDS := [
	preload("res://assets/audio/sfx/ork_warrior_die1.wav"),
	preload("res://assets/audio/sfx/ork_warrior_die2.wav"),
]
const DAMAGE_SOUND := preload("res://assets/audio/sfx/ork_warrior_damage.wav")
const ENEMY_HIT_SOUND := preload("res://assets/audio/sfx/misc/Enemy_gets_hit.wav")
const HIT_PARTICLES := preload("res://scripts/effects/hit_particles.gd")
const BREATH_SOUND := preload("res://assets/audio/sfx/ork_warrior_breath.wav")

@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var detection_left: Area2D = $DetectionAreaLeft
@onready var detection_right: Area2D = $DetectionAreaRight
@onready var head_hitbox: Area2D = $HeadHitbox
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var patrol_timer: Timer = $PatrolTimer
@onready var hurt_timer: Timer = $HurtTimer
@onready var dodge_timer: Timer = $DodgeTimer
@onready var lose_sight_timer: Timer = $LoseSightTimer
@onready var attack_cooldown_timer: Timer = $AttackCooldownTimer


func _ready() -> void:
	add_to_group("enemy")
	detection_left.body_entered.connect(_on_detection_left_body_entered)
	detection_left.body_exited.connect(_on_detection_body_exited)
	detection_right.body_entered.connect(_on_detection_right_body_entered)
	detection_right.body_exited.connect(_on_detection_body_exited)
	head_hitbox.body_entered.connect(_on_head_hitbox_body_entered)
	attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)

	# Aseguramos que el hitbox de ataque empiece desactivado
	attack_hitbox_shape.set_deferred("disabled", true)

	if attack_hitbox_shape.shape is RectangleShape2D:
		attack_hitbox_shape.shape = attack_hitbox_shape.shape.duplicate()
		attack_hitbox_shape.shape.size = Vector2(attack_hitbox_reach, attack_hitbox_height)

	patrol_timer.timeout.connect(_on_patrol_timer_timeout)
	hurt_timer.timeout.connect(_on_hurt_timer_timeout)
	dodge_timer.timeout.connect(_on_dodge_timer_timeout)
	lose_sight_timer.timeout.connect(_on_lose_sight_timer_timeout)
	step_timer.timeout.connect(_on_step_timer_timeout)
	_start_patrol_walk()


func _physics_process(delta: float) -> void:
	if state == State.DEFEATED:
		return

	if not is_on_floor():
		velocity.y += gravity * delta

	match state:
		State.PATROL:
			velocity.x = 0.0 if is_patrol_paused else patrol_speed * facing_dir
		State.CHASE:
			_chase_player()
			_check_attack_trigger()
		State.DODGE:
			pass
		State.ATTACK:
			velocity.x = 0.0
		State.HURT, State.DEFEATED:
			velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)

	_check_dodge_trigger()
	_update_facing_and_animation()
	move_and_slide()

	if debug_label:
		debug_label.text = "st:%s fd:%d vx:%.0f x:%.0f" % [State.keys()[state], facing_dir, velocity.x, global_position.x]


func _chase_player() -> void:
	if player_ref == null or not is_instance_valid(player_ref):
		_enter_patrol()
		return
	velocity.x = chase_speed * facing_dir


func _update_facing_and_animation() -> void:
	animated_sprite.flip_h = facing_dir < 0

	if state == State.HURT:
		animated_sprite.modulate.a = 1.0 if int(Time.get_ticks_msec() / 80) % 2 == 0 else 0.3
	else:
		animated_sprite.modulate.a = 1.0

	match state:
		State.HURT:
			animated_sprite.play("hurt")
		State.DEFEATED:
			animated_sprite.play("defeated")
		State.ATTACK:
			animated_sprite.play("attack")
		_:
			if is_on_wall():
				animated_sprite.play("idle")
			elif abs(velocity.x) > 5.0:
				animated_sprite.play("walk")
			else:
				animated_sprite.play("idle")


# ===== PATRULLA =====

func _start_patrol_walk() -> void:
	is_patrol_paused = false
	facing_dir = [-1, 1].pick_random()
	patrol_timer.start(randf_range(patrol_walk_time_min, patrol_walk_time_max))


func _start_patrol_pause() -> void:
	is_patrol_paused = true
	velocity.x = 0.0
	patrol_timer.start(randf_range(patrol_pause_time_min, patrol_pause_time_max))
	if randf() < 0.35:
		sfx_player.stream = BREATH_SOUND
		sfx_player.play()


func _on_patrol_timer_timeout() -> void:
	if state != State.PATROL:
		return
	if is_patrol_paused:
		_start_patrol_walk()
	else:
		_start_patrol_pause()


func _enter_patrol() -> void:
	state = State.PATROL
	player_ref = null
	_start_patrol_walk()


# ===== DETECCIÓN / PERSECUCIÓN =====

func _on_detection_left_body_entered(body: Node) -> void:
	if body.is_in_group("player") and state != State.HURT and state != State.DEFEATED:
		player_ref = body
		state = State.CHASE
		facing_dir = -1
		lose_sight_timer.stop()


func _on_detection_right_body_entered(body: Node) -> void:
	if body.is_in_group("player") and state != State.HURT and state != State.DEFEATED:
		player_ref = body
		state = State.CHASE
		facing_dir = 1
		lose_sight_timer.stop()


func _on_detection_body_exited(body: Node) -> void:
	if body != player_ref:
		return
	if state == State.HURT or state == State.DEFEATED or state == State.ATTACK:
		return

	var still_detected := detection_left.overlaps_body(body) or detection_right.overlaps_body(body)
	if not still_detected:
		lose_sight_timer.start(lose_sight_grace_time)


func _on_lose_sight_timer_timeout() -> void:
	player_ref = null
	if state == State.CHASE:
		_enter_patrol()


# ===== RECIBIR DAÑO (PISOTÓN) =====

func _on_head_hitbox_body_entered(body: Node) -> void:
	if state == State.DEFEATED:
		return
	if not body.is_in_group("player"):
		return
	if body.velocity.y <= 0.0:
		return

	hit_count += 1
	has_been_hit_once = true

	if body.has_method("bounce_off_enemy"):
		body.bounce_off_enemy(global_position)

	sfx_player.stream = ENEMY_HIT_SOUND
	sfx_player.play()
	HIT_PARTICLES.spawn(get_tree(), global_position + Vector2(0, -40), Color(1.0, 1.0, 0.4))

	if hit_count >= max_hits:
		_enter_defeated()
	else:
		_enter_hurt()


func _enter_hurt() -> void:
	state = State.HURT
	velocity.x = 0.0
	attack_hitbox_shape.set_deferred("disabled", true)  # ← corregido
	lose_sight_timer.stop()
	hurt_timer.start(hurt_duration)


func _on_hurt_timer_timeout() -> void:
	if state == State.DEFEATED:
		return
	_try_resume_chase()


func _try_resume_chase() -> void:
	for body in detection_left.get_overlapping_bodies():
		if body.is_in_group("player"):
			player_ref = body
			facing_dir = -1
			state = State.CHASE
			return
	for body in detection_right.get_overlapping_bodies():
		if body.is_in_group("player"):
			player_ref = body
			facing_dir = 1
			state = State.CHASE
			return

	if player_ref != null and is_instance_valid(player_ref):
		state = State.CHASE
		return

	var fallback_player := get_tree().get_first_node_in_group("player")
	if fallback_player != null:
		var offset: Vector2 = fallback_player.global_position - global_position
		if offset.length() < fallback_chase_range:
			player_ref = fallback_player
			facing_dir = 1 if offset.x > 0.0 else -1
			state = State.CHASE
			return

	_enter_patrol()


func _enter_defeated() -> void:
	state = State.DEFEATED
	velocity = Vector2.ZERO
	sfx_player.stream = DIE_SOUNDS.pick_random()
	sfx_player.play()

	hurt_timer.stop()
	dodge_timer.stop()
	lose_sight_timer.stop()
	attack_cooldown_timer.stop()

	head_hitbox.set_deferred("monitoring", false)
	detection_left.set_deferred("monitoring", false)
	detection_right.set_deferred("monitoring", false)
	attack_hitbox_shape.set_deferred("disabled", true)  # ← corregido

	animated_sprite.modulate.a = 1.0
	animated_sprite.play("defeated")

	await get_tree().create_timer(0.6).timeout
	var fade_tween := create_tween()
	fade_tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.6)
	await fade_tween.finished
	queue_free()


# ===== ESQUIVAR =====

func _check_dodge_trigger() -> void:
	if not has_been_hit_once or state == State.HURT or state == State.DEFEATED or state == State.DODGE or state == State.ATTACK:
		stomp_incoming_last_frame = false
		return
	if player_ref == null or not is_instance_valid(player_ref):
		stomp_incoming_last_frame = false
		return

	var stomp_incoming := absf(player_ref.global_position.x - global_position.x) < dodge_trigger_range_x \
		and player_ref.global_position.y < global_position.y \
		and player_ref.velocity.y > 0.0

	if stomp_incoming and not stomp_incoming_last_frame:
		if randf() < dodge_chance:
			_start_dodge()

	stomp_incoming_last_frame = stomp_incoming


func _start_dodge() -> void:
	state = State.DODGE
	var away_dir := signf(global_position.x - player_ref.global_position.x)
	if away_dir != 0.0:
		facing_dir = int(away_dir)
	velocity.x = dodge_speed * facing_dir
	dodge_timer.start(dodge_duration)


func _on_dodge_timer_timeout() -> void:
	if state == State.DEFEATED:
		return
	_try_resume_chase()


func _on_step_timer_timeout() -> void:
	var is_walking := (state == State.PATROL and not is_patrol_paused) or state == State.CHASE
	if is_walking and is_on_floor() and absf(velocity.x) > 5.0:
		step_player.stream = STEP_SOUNDS.pick_random()
		step_player.play()


func get_contact_damage() -> int:
	return randi_range(contact_damage_min, contact_damage_max)


# ===== ATAQUE =====

func _check_attack_trigger() -> void:
	if player_ref == null or not is_instance_valid(player_ref) or not attack_cooldown_timer.is_stopped():
		return
	var distance := absf(player_ref.global_position.x - global_position.x)
	if distance <= attack_range:
		_enter_attack()


func _enter_attack() -> void:
	state = State.ATTACK
	velocity.x = 0.0
	lose_sight_timer.stop()
	attack_hitbox.position.x = attack_hitbox_offset * facing_dir
	_run_attack_sequence()


func _run_attack_sequence() -> void:
	await get_tree().create_timer(attack_windup_time).timeout
	if state != State.ATTACK:
		return

	attack_hitbox_shape.set_deferred("disabled", false)  # ← corregido
	sfx_player.stream = ATTACK_SOUNDS.pick_random()
	sfx_player.play()

	await get_tree().create_timer(attack_active_time).timeout
	attack_hitbox_shape.set_deferred("disabled", true)   # ← corregido

	attack_cooldown_timer.start(attack_cooldown)

	if state == State.ATTACK:
		_try_resume_chase()


func _on_attack_hitbox_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(get_contact_damage(), global_position)
