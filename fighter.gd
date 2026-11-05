class_name Fighter
extends CharacterBody2D

signal health_changed(new_health: int)
signal super_changed(new_super: int)

const CHIP_SCENE: PackedScene = preload("res://chip_projectile.tscn")

# Configurações de Identidade e Modo
@export var player_id: int = 1
@export var is_dummy: bool = false
@export var is_ai: bool = false
@export var use_fixed_super_damage: bool = false

# Atributos de Física e Combate (Escala Padrão 200 HP)
@export var walk_speed: float = 250.0
@export var jump_velocity: float = -650.0
@export var gravity_multiplier: float = 1.8
@export var health: int = 200
@export var special_cooldown: float = 5.5
@export var chip_cooldown: float = 1.2

enum State { IDLE, WALK, CROUCH, JUMP, ATTACK, HURT, KNOCKDOWN, SPECIAL, BLOCK, SUPER }
var current_state: State = State.IDLE
var facing_direction: int = 1
var original_color: Color
var hitbox_default_pos: Vector2
var current_hitbox_size: Vector2 = Vector2.ONE
var combat_active: bool = true

# Propriedades dinâmicas de cada golpe
var current_attack_damage: int = 4
var current_knockback_x: float = 12.0
var current_knockback_y: float = 0.0
var current_hitstun: float = 0.26
var current_causes_knockdown: bool = false
var current_hit_type: String = "MID"

var can_use_special: bool = true
var can_shoot_chip: bool = true
var can_air_attack: bool = true
var jump_Timer: float = 0.0
var ai_attack_cooldown: float = 0.8

# Controle de Combo e Cancelamento de Rotinas Antigas (state_token)
var combo_step: int = 0
var next_combo_queued: bool = false
var heavy_followup_queued: bool = false
var attack_connected: bool = false
var state_token: int = 0

# Medidor de Super (0 a 100)
var super_meter: int = 0
const MAX_SUPER: int = 100

# Ações dinâmicas de input
var in_left: String
var in_right: String
var in_jump: String
var in_crouch: String
var in_light: String
var in_heavy: String
var in_special1: String
var in_special2: String
var in_grab: String
var in_super: String

@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual_rect: ColorRect = $ColorRect

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready() -> void:
	add_to_group("fighters")
	original_color = modulate
	hitbox_default_pos = hitbox.position
	hitbox.visible = false
	hitbox_shape.disabled = true
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	_setup_inputs()

func _bind_action_key(action_name: String, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey and ev.physical_keycode == key:
			return
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action_name, event)

func _setup_inputs() -> void:
	if player_id == 1:
		in_left = "move_left"
		in_right = "move_right"
		in_jump = "jump"
		in_crouch = "crouch"
		in_light = "attack_light"
		in_heavy = "attack_heavy"
		in_special1 = "special_move"
		in_special2 = "attack_projectile"
		in_grab = "attack_grab"
		in_super = "super_attack"
		
		_bind_action_key(in_light, KEY_J)
		_bind_action_key(in_heavy, KEY_H)
		_bind_action_key(in_special1, KEY_K)
		_bind_action_key(in_special2, KEY_L)
		_bind_action_key(in_grab, KEY_I)
		_bind_action_key(in_super, KEY_U)
	else:
		in_left = "p2_move_left"
		in_right = "p2_move_right"
		in_jump = "p2_jump"
		in_crouch = "p2_crouch"
		in_light = "p2_attack_light"
		in_heavy = "p2_attack_heavy"
		in_special1 = "p2_special_move"
		in_special2 = "p2_attack_projectile"
		in_grab = "p2_attack_grab"
		in_super = "p2_super_attack"
		
		_bind_action_key(in_heavy, KEY_KP_2)
		_bind_action_key(in_grab, KEY_KP_5)

func set_facing(dir: int) -> void:
	if current_state in [State.ATTACK, State.SPECIAL, State.SUPER, State.KNOCKDOWN]:
		return
	facing_direction = dir
	hitbox.scale = Vector2(facing_direction * current_hitbox_size.x, current_hitbox_size.y)

func on_round_end() -> void:
	combat_active = false
	state_token += 1
	velocity.x = 0
	combo_step = 0
	next_combo_queued = false
	heavy_followup_queued = false
	_reset_hitbox()
	if health > 0:
		_reset_posture()
		modulate = original_color
		current_state = State.IDLE

func reset_for_round(spawn_pos: Vector2, initial_facing: int) -> void:
	state_token += 1
	combat_active = false
	health = 200
	super_meter = 0
	velocity = Vector2.ZERO
	global_position = spawn_pos
	
	can_use_special = true
	can_shoot_chip = true
	can_air_attack = true
	combo_step = 0
	next_combo_queued = false
	heavy_followup_queued = false
	attack_connected = false
	jump_Timer = 0.0
	ai_attack_cooldown = 0.8
	
	modulate = original_color
	current_state = State.IDLE
	_reset_posture()
	_reset_hitbox()
	set_facing(initial_facing)
	health_changed.emit(health)
	super_changed.emit(super_meter)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * gravity_multiplier * delta

	if is_on_floor() and current_state in [State.HURT, State.KNOCKDOWN, State.BLOCK]:
		velocity.x = move_toward(velocity.x, 0, 18.0)

	if not combat_active or is_dummy:
		if is_on_floor() and not combat_active:
			velocity.x = move_toward(velocity.x, 0, 25.0)
		move_and_slide()
		return

	if is_ai:
		_process_ai(delta)
		move_and_slide()
		return

	match current_state:
		State.IDLE:
			_state_idle()
		State.WALK:
			_state_walk()
		State.CROUCH:
			_state_crouch()
		State.JUMP:
			_state_jump(delta)
		State.ATTACK:
			if Input.is_action_just_pressed(in_light) and combo_step in [1, 2]:
				next_combo_queued = true
			elif Input.is_action_just_pressed(in_heavy) and combo_step in [1, 2]:
				heavy_followup_queued = true
		State.HURT, State.KNOCKDOWN, State.SPECIAL, State.BLOCK, State.SUPER:
			pass

	move_and_slide()

func _check_combat_inputs(is_crouching: bool = false) -> bool:
	if Input.is_action_just_pressed(in_super) and super_meter >= MAX_SUPER:
		_reset_posture()
		_perform_all_in_super()
		return true
	if Input.is_action_just_pressed(in_special1) and can_use_special:
		_reset_posture()
		_perform_time_loop_leap()
		return true
	if Input.is_action_just_pressed(in_special2) and can_shoot_chip:
		_reset_posture()
		_shoot_chip()
		return true
	if Input.is_action_just_pressed(in_grab):
		_reset_posture()
		_perform_grab()
		return true
	if Input.is_action_just_pressed(in_heavy):
		if is_crouching:
			_perform_crouch_heavy()
		elif Input.is_action_pressed(in_jump):
			_perform_uppercut()
		else:
			_perform_heavy_attack()
		return true
	if Input.is_action_just_pressed(in_light):
		if is_crouching:
			_perform_crouch_light()
		elif Input.is_action_pressed(in_jump):
			_perform_uppercut()
		else:
			_perform_light_combo()
		return true
	return false

func _state_idle() -> void:
	velocity.x = 0
	if _check_combat_inputs(false):
		return
	if Input.is_action_just_pressed(in_jump) and is_on_floor():
		_initiate_jump()
	elif Input.is_action_pressed(in_crouch):
		current_state = State.CROUCH
	elif Input.get_axis(in_left, in_right) != 0:
		current_state = State.WALK

func _state_walk() -> void:
	var direction: float = Input.get_axis(in_left, in_right)
	velocity.x = direction * walk_speed
	
	if _check_combat_inputs(false):
		return
	if Input.is_action_just_pressed(in_jump) and is_on_floor():
		_initiate_jump()
	elif Input.is_action_pressed(in_crouch):
		current_state = State.CROUCH
	elif direction == 0:
		current_state = State.IDLE

func _reset_posture() -> void:
	if visual_rect:
		visual_rect.scale.y = 1.0
		visual_rect.position.y = 0.0
	if collision_shape:
		collision_shape.scale.y = 1.0
		collision_shape.position.y = 0.0

func _state_crouch() -> void:
	velocity.x = 0
	if visual_rect:
		visual_rect.scale.y = 0.7
		visual_rect.position.y = 15.0
	if collision_shape:
		collision_shape.scale.y = 0.6
		collision_shape.position.y = 10.0
	
	if _check_combat_inputs(true):
		return
	if not Input.is_action_pressed(in_crouch):
		_reset_posture()
		current_state = State.IDLE

func _state_jump(delta: float) -> void:
	jump_Timer += delta
	var dir_x: float = Input.get_axis(in_left, in_right)
	
	if not can_air_attack and dir_x != 0.0:
		velocity.x = move_toward(velocity.x, dir_x * (walk_speed * 0.65), 15.0)
	
	if Input.is_action_just_pressed(in_light) or Input.is_action_just_pressed(in_heavy):
		if jump_Timer <= 0.06 and Input.is_action_pressed(in_jump) and dir_x == 0.0:
			_perform_uppercut()
			return
		elif can_air_attack:
			var is_heavy_air: bool = Input.is_action_just_pressed(in_heavy)
			_perform_air_attack(is_heavy_air)

	if is_on_floor() and velocity.y >= 0:
		_reset_hitbox()
		can_air_attack = true
		current_state = State.IDLE

func _process_ai(delta: float) -> void:
	if health <= 0 or current_state in [State.HURT, State.KNOCKDOWN, State.ATTACK, State.SPECIAL, State.SUPER]:
		return

	var opponent: Fighter = _get_opponent()
	if not opponent or opponent.health <= 0:
		velocity.x = 0
		return

	var distance_x: float = opponent.global_position.x - global_position.x
	var abs_distance: float = abs(distance_x)

	if super_meter >= MAX_SUPER and abs_distance < 120.0:
		_perform_all_in_super()
		return

	if abs_distance > 220.0:
		ai_attack_cooldown -= delta
		if ai_attack_cooldown <= 0.0:
			if can_shoot_chip and randf() < 0.5:
				_shoot_chip()
				ai_attack_cooldown = 1.0
				return
			elif can_use_special and randf() < 0.35:
				_perform_time_loop_leap()
				ai_attack_cooldown = 1.2
				return

	if abs_distance > 65.0:
		velocity.x = sign(distance_x) * (walk_speed * 0.75)
		current_state = State.WALK
	else:
		velocity.x = 0
		current_state = State.IDLE
		ai_attack_cooldown -= delta
		if ai_attack_cooldown <= 0.0:
			var roll: float = randf()
			if not opponent.is_on_floor() or roll < 0.15:
				_perform_uppercut()
			elif roll < 0.30:
				_perform_grab()
			elif roll < 0.50:
				_perform_heavy_attack()
			elif roll < 0.70:
				_perform_crouch_heavy()
			else:
				_perform_light_combo()
				next_combo_queued = randf() < 0.75
			ai_attack_cooldown = randf_range(0.6, 1.2)

func add_super(amount: int) -> void:
	super_meter = mini(MAX_SUPER, super_meter + amount)
	super_changed.emit(super_meter)

func _set_attack_data(dmg: int, kb_x: float, kb_y: float, stun: float, knockdown: bool, type: String = "MID") -> void:
	current_attack_damage = dmg
	current_knockback_x = kb_x
	current_knockback_y = kb_y
	current_hitstun = stun
	current_causes_knockdown = knockdown
	current_hit_type = type
	attack_connected = false

func _activate_hitbox(offset: Vector2, size_scale: Vector2) -> void:
	current_hitbox_size = size_scale
	hitbox.position = hitbox_default_pos + Vector2(offset.x * facing_direction, offset.y)
	hitbox.scale = Vector2(facing_direction * size_scale.x, size_scale.y)
	hitbox.visible = true
	hitbox_shape.set_deferred("disabled", false)

func _reset_hitbox() -> void:
	current_hitbox_size = Vector2.ONE
	hitbox.visible = false
	hitbox_shape.set_deferred("disabled", true)
	hitbox.position = hitbox_default_pos
	hitbox.scale = Vector2(facing_direction, 1.0)
	_set_attack_data(4, 12.0, 0.0, 0.26, false, "MID")

func _perform_light_combo() -> void:
	state_token += 1
	var my_token: int = state_token
	current_state = State.ATTACK
	velocity.x = 0
	combo_step = 1
	next_combo_queued = false
	heavy_followup_queued = false
	
	_set_attack_data(4, 12.0, 0.0, 0.26, false, "MID")
	_activate_hitbox(Vector2.ZERO, Vector2(1.0, 1.0))
	await get_tree().create_timer(0.08).timeout
	if my_token != state_token: return
	_reset_hitbox()
	
	await get_tree().create_timer(0.05).timeout
	if my_token != state_token: return
	var action_1: String = await _wait_combo_window(0.25, my_token)
	if my_token != state_token: return
	
	if action_1 == "HEAVY" and current_state == State.ATTACK:
		await _execute_heavy_strike(my_token)
		return
	elif action_1 == "LIGHT" and current_state == State.ATTACK:
		combo_step = 2
		next_combo_queued = false
		
		_set_attack_data(5, 18.0, 0.0, 0.28, false, "MID")
		velocity.x = facing_direction * 80.0
		_activate_hitbox(Vector2(8, 0), Vector2(1.1, 1.0))
		await get_tree().create_timer(0.09).timeout
		if my_token != state_token: return
		velocity.x = 0
		_reset_hitbox()
		
		await get_tree().create_timer(0.05).timeout
		if my_token != state_token: return
		var action_2: String = await _wait_combo_window(0.26, my_token)
		if my_token != state_token: return
		
		if action_2 == "HEAVY" and current_state == State.ATTACK:
			await _execute_heavy_strike(my_token)
			return
		elif action_2 == "LIGHT" and current_state == State.ATTACK:
			combo_step = 3
			next_combo_queued = false
			
			_set_attack_data(7, 280.0, 0.0, 0.35, false, "MID")
			velocity.x = facing_direction * 100.0
			_activate_hitbox(Vector2(14, -4), Vector2(1.25, 1.15))
			await get_tree().create_timer(0.11).timeout
			if my_token != state_token: return
			velocity.x = 0
			_reset_hitbox()
			await get_tree().create_timer(0.22).timeout
		else:
			await get_tree().create_timer(0.14).timeout
	else:
		await get_tree().create_timer(0.12).timeout
	
	if my_token != state_token: return
	combo_step = 0
	next_combo_queued = false
	heavy_followup_queued = false
	if current_state == State.ATTACK:
		current_state = State.IDLE

func _wait_combo_window(duration: float, my_token: int) -> String:
	var t: float = duration
	while t > 0.0:
		if my_token != state_token or current_state != State.ATTACK:
			return "NONE"
		if heavy_followup_queued:
			return "HEAVY"
		if next_combo_queued:
			return "LIGHT"
		await get_tree().process_frame
		t -= get_process_delta_time()
	return "NONE"

func _perform_crouch_light() -> void:
	state_token += 1
	var my_token: int = state_token
	current_state = State.ATTACK
	velocity.x = 0
	
	_set_attack_data(4, 20.0, 0.0, 0.24, false, "LOW")
	_activate_hitbox(Vector2(0, 24), Vector2(1.1, 0.7))
	await get_tree().create_timer(0.09).timeout
	if my_token != state_token: return
	
	_reset_hitbox()
	await get_tree().create_timer(0.15).timeout
	if my_token != state_token: return
	
	if current_state == State.ATTACK:
		if Input.is_action_pressed(in_crouch):
			current_state = State.CROUCH
		else:
			_reset_posture()
			current_state = State.IDLE

func _perform_heavy_attack() -> void:
	state_token += 1
	var my_token: int = state_token
	current_state = State.ATTACK
	combo_step = 0
	await _execute_heavy_strike(my_token)

func _execute_heavy_strike(my_token: int) -> void:
	velocity.x = 0
	modulate = Color(1.2, 0.85, 0.6)
	await get_tree().create_timer(0.12).timeout
	if my_token != state_token or current_state != State.ATTACK:
		modulate = original_color
		return
	modulate = original_color
	
	velocity.x = facing_direction * 130.0
	_set_attack_data(12, 240.0, -220.0, 0.40, true, "HEAVY_MID")
	_activate_hitbox(Vector2(14, -4), Vector2(1.3, 1.2))
	await get_tree().create_timer(0.14).timeout
	if my_token != state_token: return
	
	velocity.x = 0
	_reset_hitbox()
	await get_tree().create_timer(0.35).timeout
	if my_token != state_token: return
	
	combo_step = 0
	next_combo_queued = false
	heavy_followup_queued = false
	if current_state == State.ATTACK:
		current_state = State.IDLE

func _perform_crouch_heavy() -> void:
	state_token += 1
	var my_token: int = state_token
	current_state = State.ATTACK
	velocity.x = 0
	await get_tree().create_timer(0.08).timeout
	if my_token != state_token or current_state != State.ATTACK:
		return
	
	_set_attack_data(10, 110.0, -190.0, 0.38, true, "LOW")
	_activate_hitbox(Vector2(0, 26), Vector2(1.3, 0.7))
	await get_tree().create_timer(0.14).timeout
	if my_token != state_token: return
	
	_reset_hitbox()
	await get_tree().create_timer(0.34).timeout
	if my_token != state_token: return
	
	if current_state == State.ATTACK:
		if Input.is_action_pressed(in_crouch):
			current_state = State.CROUCH
		else:
			_reset_posture()
			current_state = State.IDLE

func _perform_uppercut() -> void:
	state_token += 1
	var my_token: int = state_token
	current_state = State.ATTACK
	velocity.x = 0
	velocity.y = -420.0
	
	_set_attack_data(11, 140.0, -500.0, 0.42, true, "MID")
	_activate_hitbox(Vector2(0, -30), Vector2(0.9, 1.6))
	await get_tree().create_timer(0.16).timeout
	if my_token != state_token: return
	
	_reset_hitbox()
	await get_tree().create_timer(0.38).timeout
	if my_token != state_token: return
	
	if current_state == State.ATTACK:
		current_state = State.IDLE if is_on_floor() else State.JUMP

func _perform_air_attack(is_heavy: bool = false) -> void:
	var my_token: int = state_token
	can_air_attack = false
	velocity.x *= 0.75
	var dmg: int = 10 if is_heavy else 6
	var stun: float = 0.34 if is_heavy else 0.26
	
	_set_attack_data(dmg, 30.0, 0.0, stun, false, "OVERHEAD")
	_activate_hitbox(Vector2(0, 12), Vector2(1.15, 1.1))
	await get_tree().create_timer(0.22).timeout
	if my_token != state_token: return
	
	_reset_hitbox()

func _perform_grab() -> void:
	state_token += 1
	var my_token: int = state_token
	current_state = State.ATTACK
	velocity.x = 0
	
	await get_tree().create_timer(0.06).timeout
	if my_token != state_token or current_state != State.ATTACK:
		return
	
	velocity.x = facing_direction * 40.0
	_set_attack_data(14, 300.0, -280.0, 0.45, true, "GROUND_UNBLOCKABLE")
	_activate_hitbox(Vector2(-6, 0), Vector2(0.65, 0.9))
	await get_tree().create_timer(0.10).timeout
	if my_token != state_token: return
	
	velocity.x = 0
	var grabbed_successfully: bool = attack_connected
	_reset_hitbox()
	
	if grabbed_successfully:
		await get_tree().create_timer(0.20).timeout
	else:
		modulate = Color(0.75, 0.5, 0.95)
		await get_tree().create_timer(0.45).timeout
		if my_token != state_token: return
		modulate = original_color
	
	if my_token != state_token: return
	if current_state == State.ATTACK:
		current_state = State.IDLE

func _perform_time_loop_leap() -> void:
	state_token += 1
	var my_token: int = state_token
	can_use_special = false
	_start_cooldown_timer(my_token)
	current_state = State.SPECIAL
	velocity = Vector2.ZERO
	
	modulate = Color(0.3, 0.7, 1.0, 0.25)
	await get_tree().create_timer(0.18).timeout
	if my_token != state_token: return
	
	var opponent: Fighter = _get_opponent()
	if opponent:
		var target_x: float
		if global_position.x < opponent.global_position.x:
			target_x = opponent.global_position.x + 65.0
			facing_direction = -1
		else:
			target_x = opponent.global_position.x - 65.0
			facing_direction = 1
		
		global_position.x = clamp(target_x, 60.0, 1090.0)
	
	modulate = original_color
	_set_attack_data(14, 200.0, -260.0, 0.38, true, "MID")
	_activate_hitbox(Vector2.ZERO, Vector2(1.0, 1.0))
	await get_tree().create_timer(0.18).timeout
	if my_token != state_token: return
	
	_reset_hitbox()
	await get_tree().create_timer(0.22).timeout
	if my_token != state_token: return
	
	if current_state == State.SPECIAL:
		current_state = State.IDLE

func _shoot_chip() -> void:
	state_token += 1
	var my_token: int = state_token
	can_shoot_chip = false
	_start_chip_cooldown_timer(my_token)
	current_state = State.ATTACK
	velocity.x = 0
	
	var chip: ChipProjectile = CHIP_SCENE.instantiate() as ChipProjectile
	chip.direction = facing_direction
	chip.shooter = self
	
	get_parent().add_child(chip)
	chip.global_position = global_position + Vector2(facing_direction * 40.0, -10.0)
	
	await get_tree().create_timer(0.36).timeout
	if my_token != state_token: return
	if current_state == State.ATTACK:
		current_state = State.IDLE

func _perform_all_in_super() -> void:
	state_token += 1
	var my_token: int = state_token
	current_state = State.SUPER
	velocity = Vector2.ZERO
	super_meter = 0
	super_changed.emit(super_meter)
	
	modulate = Color(1.5, 1.3, 0.2, 1.0)
	if get_parent().has_method("trigger_time_freeze"):
		get_parent().trigger_time_freeze(0.28, 0.15)
	await get_tree().create_timer(0.28, true, false, true).timeout
	if my_token != state_token: return
	
	velocity.x = facing_direction * 750.0
	var super_dmg: int = 35
	if not use_fixed_super_damage:
		super_dmg = 40 if randf() <= 0.75 else 22
	modulate = Color(0.2, 1.0, 0.3) if super_dmg >= 35 else Color(1.0, 0.4, 0.4)
	
	_set_attack_data(super_dmg, 340.0, -360.0, 0.50, true, "MID")
	_activate_hitbox(Vector2.ZERO, Vector2(1.0, 1.2))
	await get_tree().create_timer(0.3).timeout
	if my_token != state_token: return
	
	velocity.x = 0
	_reset_hitbox()
	modulate = original_color
	await get_tree().create_timer(0.28).timeout
	if my_token != state_token: return
	
	if current_state == State.SUPER:
		current_state = State.IDLE

func _is_blocking(hit_type: String = "MID") -> bool:
	if hit_type == "GROUND_UNBLOCKABLE":
		return false
	if not is_on_floor():
		return false
	if is_ai:
		return randf() < 0.35

	var move_dir: float = Input.get_axis(in_left, in_right)
	var holding_back: bool = move_dir != 0 and sign(move_dir) == -facing_direction
	if not holding_back:
		return false

	var crouching: bool = Input.is_action_pressed(in_crouch)
	if hit_type == "LOW" and not crouching:
		return false
	if hit_type == "OVERHEAD" and crouching:
		return false

	return true

func _get_opponent() -> Fighter:
	var fighters: Array[Node] = get_tree().get_nodes_in_group("fighters")
	for f in fighters:
		if f != self and is_instance_valid(f) and f is Fighter:
			return f as Fighter
	return null

func _on_hitbox_body_entered(body: Node2D) -> void:
	# Ignora se a luta acabou, se já conectou ou se colidiu com o próprio corpo
	if not combat_active or attack_connected or body == self:
		return
		
	var opponent = body as Fighter
	if opponent:
		if opponent.health <= 0 or opponent.current_state == State.KNOCKDOWN:
			return
			
		if current_hit_type == "GROUND_UNBLOCKABLE" and not opponent.is_on_floor():
			return

		attack_connected = true
		
		var hitstop_time: float = 0.02
		if current_hit_type in ["HEAVY_MID", "GROUND_UNBLOCKABLE"]:
			hitstop_time = 0.06
		elif current_attack_damage >= 8:
			hitstop_time = 0.04
			
		if get_parent().has_method("trigger_time_freeze"):
			get_parent().trigger_time_freeze(hitstop_time, 0.02)
		
		opponent.take_damage(
			current_attack_damage,
			facing_direction,
			current_knockback_y,
			current_hit_type,
			current_knockback_x,
			current_hitstun,
			current_causes_knockdown
		)
		if current_state == State.SPECIAL:
			add_super(12)
		elif current_state in [State.ATTACK, State.JUMP]:
			add_super(7)

func take_damage(
	amount: int,
	hit_direction: int,
	knockback_y: float = 0.0,
	hit_type: String = "MID",
	knockback_x: float = 120.0,
	hitstun: float = 0.25,
	causes_knockdown: bool = false
) -> void:
	if not combat_active or health <= 0 or current_state == State.KNOCKDOWN:
		return

	state_token += 1
	var my_token: int = state_token
	combo_step = 0
	next_combo_queued = false
	heavy_followup_queued = false
	_reset_hitbox()
	_reset_posture()
	modulate = original_color

	if current_state in [State.IDLE, State.WALK, State.CROUCH, State.BLOCK] and _is_blocking(hit_type):
		var chip_Factor: float = 0.20 if hit_type == "HEAVY_MID" else 0.10
		var blocked_damage: int = maxi(1, int(amount * chip_Factor))
		health = maxi(0, health - blocked_damage)
		health_changed.emit(health)
		add_super(5)
		current_state = State.BLOCK
		
		var pushback: float = 175.0 if hit_type == "HEAVY_MID" else 95.0
		var block_time: float = 0.28 if hit_type == "HEAVY_MID" else 0.16
		velocity.x = hit_direction * pushback
		modulate = Color(0.3, 0.8, 1.0)
		await get_tree().create_timer(block_time).timeout
		if my_token != state_token:
			return
		modulate = original_color
		
		if current_state == State.BLOCK:
			current_state = State.CROUCH if Input.is_action_pressed(in_crouch) else State.IDLE
		return

	health = maxi(0, health - amount)
	health_changed.emit(health)
	add_super(10)

	velocity.x = hit_direction * knockback_x
	if knockback_y != 0.0:
		velocity.y = knockback_y

	if health <= 0:
		current_state = State.KNOCKDOWN
		modulate = Color(1, 0.2, 0.2)
		if visual_rect:
			visual_rect.scale.y = 0.35
			visual_rect.position.y = 32.0
		return

	if causes_knockdown:
		current_state = State.KNOCKDOWN
		modulate = Color(1.0, 0.35, 0.1)
		await get_tree().create_timer(0.28).timeout
		if my_token != state_token:
			return
		
		if visual_rect:
			visual_rect.scale.y = 0.35
			visual_rect.position.y = 32.0
		await get_tree().create_timer(0.55).timeout
		if my_token != state_token:
			return
		
		_reset_posture()
		modulate = original_color
		current_state = State.IDLE
		return

	current_state = State.HURT
	modulate = Color(1, 0.2, 0.2)
	await get_tree().create_timer(hitstun).timeout
	if my_token != state_token:
		return
	
	modulate = original_color
	current_state = State.IDLE

func _start_cooldown_timer(round_id: int) -> void:
	await get_tree().create_timer(special_cooldown).timeout
	if round_id == state_token or combat_active:
		can_use_special = true

func _start_chip_cooldown_timer(round_id: int) -> void:
	await get_tree().create_timer(chip_cooldown).timeout
	if round_id == state_token or combat_active:
		can_shoot_chip = true

func _initiate_jump() -> void:
	var direction: float = Input.get_axis(in_left, in_right)
	velocity.x = direction * walk_speed
	velocity.y = jump_velocity
	jump_Timer = 0.0
	can_air_attack = true
	current_state = State.JUMP
