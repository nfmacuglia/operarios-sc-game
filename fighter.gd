extends CharacterBody2D

signal health_changed(new_health)

# Cena do Projétil
const CHIP_SCENE: PackedScene = preload("res://chip_projectile.tscn")

# Configurações de Identidade e Modo
@export var player_id: int = 1 # 1 para Player 1, 2 para Player 2
@export var is_dummy: bool = false
@export var is_ai: bool = false

# Atributos de Física e Combate
@export var walk_speed: float = 250.0
@export var jump_velocity: float = -650.0
@export var gravity_multiplier: float = 1.8
@export var health: int = 100
@export var special_cooldown: float = 3.0

enum State { IDLE, WALK, CROUCH, JUMP, ATTACK, HURT, SPECIAL, BLOCK }
var current_state: State = State.IDLE
var facing_direction: int = 1
var original_color: Color
var current_attack_damage: int = 10
var can_use_special: bool = true
var ai_attack_cooldown: float = 0.8

# Ações dinâmicas de input
var in_left: String
var in_right: String
var in_jump: String
var in_crouch: String
var in_attack: String
var in_special: String
var in_projectile: String

@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready() -> void:
	add_to_group("fighters")
	original_color = modulate
	hitbox.visible = false
	hitbox_shape.disabled = true
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	_setup_inputs()

func _setup_inputs() -> void:
	if player_id == 1:
		in_left = "move_left"
		in_right = "move_right"
		in_jump = "jump"
		in_crouch = "crouch"
		in_attack = "attack_light"
		in_special = "special_move"
		in_projectile = "attack_projectile"
	else:
		in_left = "p2_move_left"
		in_right = "p2_move_right"
		in_jump = "p2_jump"
		in_crouch = "p2_crouch"
		in_attack = "p2_attack_light"
		in_special = "p2_special_move"
		in_projectile = "p2_attack_projectile"

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * gravity_multiplier * delta

	# 1. Modo Saco de Pancadas
	if is_dummy:
		if is_on_floor() and current_state != State.HURT:
			velocity.x = move_toward(velocity.x, 0, 20.0)
		move_and_slide()
		return

	# 2. Modo IA Autônoma
	if is_ai:
		_process_ai(delta)
		move_and_slide()
		return

	# 3. Modo Jogador Humano (P1 ou P2)
	match current_state:
		State.IDLE:
			_state_idle()
		State.WALK:
			_state_walk()
		State.CROUCH:
			_state_crouch()
		State.JUMP:
			_state_jump()
		State.ATTACK, State.HURT, State.SPECIAL, State.BLOCK:
			pass

	move_and_slide()

# --- MÁQUINA DE ESTADOS ---

func _state_idle() -> void:
	velocity.x = 0
	if Input.is_action_just_pressed(in_special) and can_use_special:
		_perform_time_loop_leap()
	elif Input.is_action_just_pressed(in_projectile):
		_shoot_chip()
	elif Input.is_action_just_pressed(in_attack):
		_perform_attack()
	elif Input.is_action_just_pressed(in_jump) and is_on_floor():
		_initiate_jump()
	elif Input.is_action_pressed(in_crouch):
		current_state = State.CROUCH
	elif Input.get_axis(in_left, in_right) != 0:
		current_state = State.WALK

func _state_walk() -> void:
	var direction := Input.get_axis(in_left, in_right)
	velocity.x = direction * walk_speed
	
	if direction != 0:
		facing_direction = int(sign(direction))
		hitbox.scale.x = facing_direction
	
	if Input.is_action_just_pressed(in_special) and can_use_special:
		_perform_time_loop_leap()
	elif Input.is_action_just_pressed(in_projectile):
		_shoot_chip()
	elif Input.is_action_just_pressed(in_attack):
		_perform_attack()
	elif Input.is_action_just_pressed(in_jump) and is_on_floor():
		_initiate_jump()
	elif Input.is_action_pressed(in_crouch):
		current_state = State.CROUCH
	elif direction == 0:
		current_state = State.IDLE

func _state_crouch() -> void:
	velocity.x = 0
	if Input.is_action_just_pressed(in_special) and can_use_special:
		_perform_time_loop_leap()
	elif Input.is_action_just_pressed(in_projectile):
		_shoot_chip()
	elif Input.is_action_just_pressed(in_attack):
		_perform_attack()
	elif not Input.is_action_pressed(in_crouch):
		current_state = State.IDLE

func _state_jump() -> void:
	if is_on_floor() and velocity.y >= 0:
		current_state = State.IDLE

# --- IA ---

func _process_ai(delta: float) -> void:
	if health <= 0 or current_state == State.HURT or current_state == State.ATTACK:
		return

	var opponent := _get_opponent()
	if not opponent or opponent.health <= 0:
		velocity.x = 0
		return

	var distance_x: float = opponent.global_position.x - global_position.x
	var abs_distance: float = abs(distance_x)

	if abs_distance > 65.0:
		velocity.x = sign(distance_x) * (walk_speed * 0.75)
		current_state = State.WALK
	else:
		velocity.x = 0
		current_state = State.IDLE
		ai_attack_cooldown -= delta
		if ai_attack_cooldown <= 0.0:
			_perform_attack()
			ai_attack_cooldown = randf_range(0.6, 1.2)

# --- COMBATE, PROJÉTIL, ESPECIAL E DEFESA ---

func _shoot_chip() -> void:
	current_state = State.ATTACK
	velocity.x = 0
	
	var chip := CHIP_SCENE.instantiate() as Area2D
	chip.direction = facing_direction
	chip.shooter = self
	chip.global_position = global_position + Vector2(facing_direction * 40.0, -10.0)
	get_parent().add_child(chip)
	
	await get_tree().create_timer(0.25).timeout
	if current_state == State.ATTACK:
		current_state = State.IDLE

func _is_blocking() -> bool:
	if not is_on_floor():
		return false
		
	if is_ai:
		return randf() < 0.35

	var move_dir := Input.get_axis(in_left, in_right)
	return move_dir != 0 and sign(move_dir) == -facing_direction

func _perform_attack() -> void:
	current_state = State.ATTACK
	velocity.x = 0
	current_attack_damage = 10
	
	hitbox.visible = true
	hitbox_shape.set_deferred("disabled", false)
	await get_tree().create_timer(0.15).timeout
	
	hitbox.visible = false
	hitbox_shape.set_deferred("disabled", true)
	await get_tree().create_timer(0.1).timeout
	
	if current_state == State.ATTACK:
		current_state = State.IDLE

func _perform_time_loop_leap() -> void:
	can_use_special = false
	_start_cooldown_timer()
	current_state = State.SPECIAL
	velocity = Vector2.ZERO
	
	modulate = Color(0.3, 0.7, 1.0, 0.25)
	await get_tree().create_timer(0.18).timeout
	
	var opponent := _get_opponent()
	if opponent:
		var target_x: float
		if global_position.x < opponent.global_position.x:
			target_x = opponent.global_position.x + 65.0
			facing_direction = -1
		else:
			target_x = opponent.global_position.x - 65.0
			facing_direction = 1
		
		global_position.x = clamp(target_x, 60.0, 1090.0)
		hitbox.scale.x = facing_direction
	
	modulate = original_color
	current_attack_damage = 20
	hitbox.visible = true
	hitbox_shape.set_deferred("disabled", false)
	await get_tree().create_timer(0.18).timeout
	
	hitbox.visible = false
	hitbox_shape.set_deferred("disabled", true)
	await get_tree().create_timer(0.12).timeout
	
	if current_state == State.SPECIAL:
		current_state = State.IDLE

func _get_opponent() -> Node2D:
	var fighters = get_tree().get_nodes_in_group("fighters")
	for f in fighters:
		if f != self and is_instance_valid(f):
			return f
	return null

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body != self and body.has_method("take_damage"):
		body.take_damage(current_attack_damage, facing_direction)

func take_damage(amount: int, hit_direction: int) -> void:
	if health <= 0:
		return

	# --- BLOQUEIO ATIVO (Segurar para trás) ---
	var can_block := current_state in [State.IDLE, State.WALK, State.CROUCH, State.BLOCK]
	if can_block and _is_blocking():
		var blocked_damage: int = maxi(2, int(amount * 0.2))
		health = max(0, health - blocked_damage)
		health_changed.emit(health)
		current_state = State.BLOCK
		
		velocity.x = hit_direction * 140.0
		
		modulate = Color(0.3, 0.8, 1.0)
		await get_tree().create_timer(0.18).timeout
		modulate = original_color
		
		if current_state == State.BLOCK:
			current_state = State.IDLE
		return

	# --- DANO TOTAL (Sem defesa) ---
	health = max(0, health - amount)
	health_changed.emit(health)
	current_state = State.HURT
	
	velocity.x = hit_direction * 300.0
	velocity.y = -200.0
	
	modulate = Color(1, 0.2, 0.2)
	await get_tree().create_timer(0.25).timeout
	modulate = original_color
	
	if health <= 0:
		velocity.x = 0
		return
	
	current_state = State.IDLE

func _initiate_jump() -> void:
	var direction := Input.get_axis(in_left, in_right)
	velocity.x = direction * walk_speed
	velocity.y = jump_velocity
	current_state = State.JUMP

func _start_cooldown_timer() -> void:
	await get_tree().create_timer(special_cooldown).timeout
	can_use_special = true
