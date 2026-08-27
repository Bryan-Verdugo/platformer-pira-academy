extends Area2D

## Poné este script en un Area2D con su CollisionShape2D cubriendo la zona
## letal (precipicios, lava, picos). Al tocarlo, el Player respawnea.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("respawn"):
		body.respawn()
