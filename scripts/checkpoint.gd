extends Area2D

var already_activated: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if already_activated:
		return
	
	if body.is_in_group("player"):
		already_activated = true
		
		# Guardamos la posición actual del jugador (más confiable)
		GameManager.set_checkpoint(body.global_position)
		print("Checkpoint activado en: ", body.global_position)
		
		set_deferred("monitoring", false)
