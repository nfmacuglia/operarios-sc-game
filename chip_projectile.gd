class_name ChipProjectile
extends Area2D

@export var speed: float = 500.0
@export var damage: int = 7
@export var knockback_x: float = 140.0
@export var hitstun: float = 0.28

var direction: int = 1
var shooter: Node2D = null
var has_hit: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(2.5).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta
	rotation += 18.0 * delta

func _on_body_entered(body: Node2D) -> void:
	if has_hit or body == shooter:
		return

	if body is Fighter and not body.combat_active:
		has_hit = true
		queue_free()
		return

	if body.has_method("take_damage"):
		has_hit = true
		set_deferred("monitoring", false)
		
		if get_parent() and get_parent().has_method("trigger_time_freeze"):
			get_parent().trigger_time_freeze(0.03, 0.02)
		
		body.take_damage(damage, direction, 0.0, "MID", knockback_x, hitstun, false)
		
		if is_instance_valid(shooter) and shooter.has_method("add_super"):
			shooter.add_super(6)
			
		queue_free()
	elif body is StaticBody2D:
		has_hit = true
		queue_free()
