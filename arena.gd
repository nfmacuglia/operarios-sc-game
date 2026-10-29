extends Node2D

@onready var p1: CharacterBody2D = $Fighter
@onready var p2: CharacterBody2D = $Fighter2
@onready var timer_label: Label = $UI/TimerLabel
@onready var center_message: Label = $UI/CenterMessage

var time_left: float = 99.0
var round_over: bool = false

func _ready() -> void:
	# Conecta a vida dos lutadores ao juiz da arena
	p1.health_changed.connect(_on_fighter_health_changed)
	p2.health_changed.connect(_on_fighter_health_changed)
	
	# Mostra "LUTE!" por 1 segundo no início
	center_message.text = "LUTE!"
	center_message.visible = true
	await get_tree().create_timer(1.0).timeout
	center_message.visible = false

func _process(delta: float) -> void:
	if round_over:
		# Aperte ENTER para reiniciar a luta após o K.O.
		if Input.is_action_just_pressed("ui_accept"):
			get_tree().reload_current_scene()
		return

	# Conta o relógio regressivo
	if time_left > 0:
		time_left -= delta
		timer_label.text = str(ceil(time_left))
	else:
		_end_round_by_time()

	# Faz os lutadores sempre olharem um para o outro (Auto-Flip estilo Street Fighter)
	_update_facing_direction()

func _update_facing_direction() -> void:
	if p1.global_position.x < p2.global_position.x:
		p1.facing_direction = 1
		p1.hitbox.scale.x = 1
		p2.facing_direction = -1
		p2.hitbox.scale.x = -1
	else:
		p1.facing_direction = -1
		p1.hitbox.scale.x = -1
		p2.facing_direction = 1
		p2.hitbox.scale.x = 1

func _on_fighter_health_changed(_new_health: int) -> void:
	if p1.health <= 0:
		_declare_winner("PLAYER 2 VENCEU!\n(Aperte Enter)")
	elif p2.health <= 0:
		_declare_winner("PLAYER 1 VENCEU!\n(Aperte Enter)")

func _end_round_by_time() -> void:
	if p1.health > p2.health:
		_declare_winner("TEMPO ESGOTADO!\nPLAYER 1 VENCEU!")
	elif p2.health > p1.health:
		_declare_winner("TEMPO ESGOTADO!\nPLAYER 2 VENCEU!")
	else:
		_declare_winner("EMPATE!\n(Aperte Enter)")

func _declare_winner(text_msg: String) -> void:
	round_over = true
	center_message.text = "K.O.!\n" + text_msg
	center_message.visible = true
