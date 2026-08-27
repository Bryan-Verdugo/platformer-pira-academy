extends CanvasLayer

@onready var portrait: TextureRect = $MarginContainer/HBoxContainer/Portrait
@onready var health_bar: ProgressBar = $MarginContainer/HBoxContainer/BarsContainer/HealthBar
@onready var mana_bar: ProgressBar = $MarginContainer/HBoxContainer/BarsContainer/ManaBar


func _ready() -> void:
	# call_deferred: esperamos a que TODOS los _ready() del frame terminen
	# (incluido el del Player) antes de buscar el grupo "player" — evita
	# la carrera de que el HUD se inicialice antes de que exista el Player.
	call_deferred("_connect_to_player")


func _connect_to_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		health_bar.max_value = player.max_health
		health_bar.value = player.current_health
		player.health_changed.connect(_on_health_changed)
	# El maná queda siempre casi vacío: es narrativo, no una mecánica activa todavía.
	mana_bar.value = 8.0


func _on_health_changed(current: int, max_hp: int) -> void:
	health_bar.max_value = max_hp
	health_bar.value = current
