extends CharacterBody3D
@onready var head: Node3D = $head
@export var move_speed := 5.0 #m/s
@export var turn_speed := 2.5 #rad/s
@export var accel := 20.0
@onready var camera_3d: Camera3D = $head/Camera3D
var spotted_by_seeker: bool = false
var seeker_pos: Vector3 = Vector3.ZERO
@export var move_towards_speed_factor := 1.5
const rayScene = preload("res://scenes/raycast.tscn")
const LAYER_WORLD := 1
const LAYER_BOXES := 2
const LAYER_HIDER := 4
const LAYER_SEEKER := 8
@export_flags_3d_physics var env_mask := LAYER_WORLD | LAYER_BOXES
var env_rays: Array[RayCast3D] = []

func set_spotted(pos: Vector3) -> void:
	spotted_by_seeker = true
	seeker_pos = pos

func _ready() -> void:
	create_env_rays()

func _physics_process(delta: float) -> void:
	var current_move_speed = move_speed
	var forward := -transform.basis.z
	var desired_vel := Vector3.ZERO

	if spotted_by_seeker:
		current_move_speed *= move_towards_speed_factor

		var direction = (seeker_pos - global_position).normalized()

		desired_vel = direction * current_move_speed
		look_at(seeker_pos, Vector3.UP)
	else:
		# --- ROTATION: A/D turn left/right ---
		if Input.is_action_pressed("arrow_left"):
			rotate_y(turn_speed * delta)
		elif Input.is_action_pressed("arrow_right"):
			rotate_y(-turn_speed * delta)

		# --- MOVEMENT: W/S move forward/backward along local forward ---
		if Input.is_action_pressed("arrow_up"):
			desired_vel = forward * move_speed
		elif Input.is_action_pressed("arrow_down"):
			desired_vel = -forward * move_speed

	if not is_on_floor():
		velocity += get_gravity() * delta

	# Smooth velocity toward desired velocity
	velocity.x = move_toward(velocity.x, desired_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired_vel.z, accel * delta)

	move_and_slide()

func create_env_rays() -> void:
	env_rays = _create_rays(16, 360.0, 5.0, env_mask, Color(1.0, 0.0, 0.0))

func _create_rays(num_rays: int, spread_deg: float, ray_length: float, mask: int, debug_color: Color) -> Array[RayCast3D]:
	var created_rays: Array[RayCast3D] = []
	var half_spread: float = deg_to_rad(spread_deg / 2.0)

	for i in range(num_rays):
		var ray := rayScene.instantiate()
		ray.position = camera_3d.position

		var w: float = float(i) / float(num_rays - 1)
		var angle: float = lerp(-half_spread, half_spread, w)
		var dir_local: Vector3 = Vector3(sin(angle), 0.0, -cos(angle))

		ray.target_position = dir_local * ray_length
		ray.debug_shape_custom_color = debug_color
		ray.debug_shape_thickness = 1
		ray.enabled = true
		ray.collide_with_areas = true
		ray.collide_with_bodies = true
		ray.collision_mask = mask

		head.add_child(ray)
		created_rays.append(ray)

	return created_rays
