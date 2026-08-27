extends Area2D

@export var zoom_amount: float = 1.9
@export var zoom_duration: float = 1.4
@export var ghost_duration: float = 5.0

@onready var music_player: AudioStreamPlayer = get_node_or_null("/root/MusicPlayer")  # ajustá el path si es diferente

var activated: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if activated:
		return
	if body.is_in_group("player"):
		activated = true
		_start_victory_cutscene(body)

func _start_victory_cutscene(player: CharacterBody2D) -> void:
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO

	var camera: Camera2D = player.get_node_or_null("Camera2D")
	var sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D")

	# Reproducir la risa tenebrosa
	if has_node("CreepyLaugh"):
		$CreepyLaugh.play()

	# Atenuar música actual (si tenés un nodo de música)
	# ...

	# Zoom de cámara
	if camera:
		var cam_tween := create_tween()
		cam_tween.set_ease(Tween.EASE_IN_OUT)
		cam_tween.set_trans(Tween.TRANS_SINE)
		cam_tween.tween_property(camera, "zoom", Vector2(zoom_amount, zoom_amount), zoom_duration)

	await get_tree().create_timer(0.5).timeout

	if sprite:
		sprite.play("ghost")

	await get_tree().create_timer(ghost_duration).timeout
	_show_victory_text()

func _show_victory_text() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	get_tree().current_scene.add_child(canvas)

	var label := Label.new()
	label.text = "Magaleta esta agradecida.\nThanks for playing."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Posicionamos el texto más arriba
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.0
	label.anchor_bottom = 0.0
	label.offset_top = 80          # ← bajá este número si querés más arriba
	label.offset_bottom = 220
	label.offset_left = 40
	label.offset_right = -40

	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.845, 0.0, 0.166, 1.0))
	canvas.add_child(label)
