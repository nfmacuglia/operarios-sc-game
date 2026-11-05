extends Node2D

@onready var p1: Fighter = $Fighter
@onready var p2: Fighter = $Fighter2
@onready var timer_label: Label = $UI/TimerLabel
@onready var center_message: Label = $UI/CenterMessage

@onready var hp_bar1: ProgressBar = $UI/HealthBar_P1
@onready var hp_bar2: ProgressBar = $UI/HealthBar_P2
@onready var super_bar1: ProgressBar = $UI/SuperBar_P1
@onready var super_bar2: ProgressBar = $UI/SuperBar_P2

var time_left: float = 99.0
var round_over: bool = false
var match_over: bool = false

var current_round: int = 1
var p1_wins: int = 0
var p2_wins: int = 0
var max_wins: int = 2

var time_freeze_token: int = 0
var freeze_end_time_ms: int = 0

func _ready() -> void:
	if hp_bar1:
		hp_bar1.max_value = 200
		hp_bar1.value = 200
	if hp_bar2:
		hp_bar2.max_value = 200
		hp_bar2.value = 200

	p1.health_changed.connect(func(val):
		if hp_bar1: hp_bar1.value = val
		_check_ko()
	)
	p2.health_changed.connect(func(val):
		if hp_bar2: hp_bar2.value = val
		_check_ko()
	)
	
	p1.super_changed.connect(func(val): if super_bar1: super_bar1.value = val)
	p2.super_changed.connect(func(val): if super_bar2: super_bar2.value = val)
	
	p1.reset_for_round(Vector2(300, 557), 1)
	p2.reset_for_round(Vector2(850, 557), -1)
	_start_round_sequence()

func _process(delta: float) -> void:
	if round_over:
		if Input.is_action_just_pressed("ui_accept"):
			Engine.time_scale = 1.0
			freeze_end_time_ms = 0
			if match_over:
				get_tree().reload_current_scene()
			else:
				_reset_round()
		return

	if p1.combat_active and time_left > 0:
		time_left -= delta
		timer_label.text = str(ceil(time_left))
	elif p1.combat_active and time_left <= 0:
		_end_round_by_time()

	_update_facing_direction()

func trigger_time_freeze(duration: float, scale_value: float = 0.02) -> void:
	var now_ms: int = Time.get_ticks_msec()
	var new_end_ms: int = now_ms + int(duration * 1000.0)
	
	var target_scale = scale_value
	if Engine.time_scale < 1.0:
		target_scale = minf(Engine.time_scale, scale_value)
		
	freeze_end_time_ms = maxi(freeze_end_time_ms, new_end_ms)
	time_freeze_token += 1
	var current_token: int = time_freeze_token
	
	Engine.time_scale = target_scale
	
	await get_tree().create_timer(duration, true, false, true).timeout
	
	if current_token == time_freeze_token:
		Engine.time_scale = 1.0
		freeze_end_time_ms = 0

func _update_facing_direction() -> void:
	if p1.global_position.x < p2.global_position.x:
		p1.set_facing(1)
		p2.set_facing(-1)
	else:
		p1.set_facing(-1)
		p2.set_facing(1)

func _check_ko() -> void:
	# Só processa se o round ainda estiver rolando e os dois lutadores estiverem ativos
	if round_over or not p1.combat_active or not p2.combat_active:
		return
	
	if p1.health <= 0:
		_declare_winner(2)
	elif p2.health <= 0:
		_declare_winner(1)

func _end_round_by_time() -> void:
	if round_over:
		return
	
	if p1.health > p2.health:
		_declare_winner(1)
	elif p2.health > p1.health:
		_declare_winner(2)
	else:
		_declare_winner(0)

func _declare_winner(winner_id: int) -> void:
	round_over = true
	time_freeze_token += 1
	freeze_end_time_ms = 0
	Engine.time_scale = 1.0
	
	p1.on_round_end()
	p2.on_round_end()

	var msg: String = ""
	if winner_id == 1:
		p1_wins += 1
		msg = "PLAYER 1 VENCEU O ROUND!"
	elif winner_id == 2:
		p2_wins += 1
		msg = "PLAYER 2 VENCEU O ROUND!"
	else:
		msg = "EMPATE!"

	if p1_wins >= max_wins:
		msg = "PLAYER 1 VENCEU A LUTA!\n(Aperte Enter para nova luta)"
		match_over = true
	elif p2_wins >= max_wins:
		msg = "PLAYER 2 VENCEU A LUTA!\n(Aperte Enter para nova luta)"
		match_over = true
	else:
		msg += "\nPlacar: P1 " + str(p1_wins) + " x " + str(p2_wins) + " P2\n(Aperte Enter)"

	center_message.text = "K.O.!\n" + msg
	center_message.visible = true

func _reset_round() -> void:
	current_round += 1
	time_left = 99.0
	timer_label.text = "99"

	for child in get_children():
		if child is Area2D and child != p1 and child != p2:
			child.queue_free()

	# Restaura os dois lutadores primeiro
	p1.reset_for_round(Vector2(300, 557), 1)
	p2.reset_for_round(Vector2(850, 557), -1)

	if hp_bar1: hp_bar1.value = p1.health
	if hp_bar2: hp_bar2.value = p2.health

	# Libera o round apenas com ambos os personagens restaurados com 200 de HP
	round_over = false
	_start_round_sequence()

func _start_round_sequence() -> void:
	p1.combat_active = false
	p2.combat_active = false
	center_message.text = "ROUND " + str(current_round) + "\nPREPARE-SE..."
	center_message.visible = true
	
	await get_tree().create_timer(1.0).timeout
	if not round_over:
		center_message.text = "LUTE!"
		p1.combat_active = true
		p2.combat_active = true
		await get_tree().create_timer(0.5).timeout
		if not round_over:
			center_message.visible = false
