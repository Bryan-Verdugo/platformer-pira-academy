extends Control

@onready var menu_box = $MenuBox
@onready var play_button = $MenuBox/VBoxContainer/PlayButton
@onready var quit_button = $MenuBox/VBoxContainer/QuitButton

func _ready() -> void:
	await get_tree().process_frame

	# Método directo por posición y tamaño (más agresivo)
	var screen_size = get_viewport().get_visible_rect().size
	menu_box.size = Vector2(300, 140)
	menu_box.position = Vector2(
		(screen_size.x - menu_box.size.x) / 2.0,
		screen_size.y - menu_box.size.y - 50
	)

	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	play_button.grab_focus()

func _on_play_pressed() -> void:
	# Fade out de la música
	if title_music and title_music.playing:
		var tween := create_tween()
		tween.tween_property(title_music, "volume_db", -40.0, 0.8)
		await tween.finished
		title_music.stop()

	get_tree().change_scene_to_file("res://scenes/levels/level_01.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

@onready var title_music: AudioStreamPlayer = $TitleMusic
