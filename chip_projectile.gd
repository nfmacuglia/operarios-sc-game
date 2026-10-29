extends Area2D

@export var speed: float = 550.0
@export var damage: int = 12

var direction: int = 1
var shooter: Node2D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(2.5).timeout.connect(queue_free)
	
func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta
	rotation += 18.0 * delta
	
func _on_body_entered(body: Node2D) -> void:
	if body == shooter:
		return
	
	if body.has_method("take_damage"):
		body.take_damage(damage, direction)
		queue_free()
	elif body is StaticBody2D:
		queue_free()
