extends CharacterBody3D
@onready var head: Node3D = $head
@export var move_speed := 5.0 #m/s
@export var turn_speed := 2.5 #rad/s
@export var accel := 20.0
@onready var camera_3d: Camera3D = $head/Camera3D
@export var hider_ref: CharacterBody3D
const rayScene = preload("res://scenes/raycast.tscn")
const LAYER_WORLD := 1
const LAYER_BOXES := 2
const LAYER_HIDER := 4
const LAYER_SEEKER := 8
@export_flags_3d_physics var fov_mask := LAYER_WORLD | LAYER_BOXES | LAYER_HIDER
@export_flags_3d_physics var env_mask := LAYER_WORLD | LAYER_BOXES
var fov_rays: Array[RayCast3D] = []
var env_rays: Array[RayCast3D] = []

func _ready() -> void:
	create_fov_rays()
	create_env_rays()

func _physics_process(delta: float) -> void:
	var hider_spotted = false
	for r in fov_rays:
		r.force_raycast_update()
		if r.is_colliding():
			var collider := r.get_collider()
			if collider == hider_ref:
				hider_ref.set_spotted(global_position)
				hider_spotted = true
				break

	if not is_on_floor():
		velocity += get_gravity() * delta

	# --- ROTATION: A/D turn left/right ---
	if Input.is_action_pressed("left"):
		rotate_y(turn_speed * delta)
	elif Input.is_action_pressed("right"):
		rotate_y(-turn_speed * delta)

	# --- MOVEMENT: W/S move forward/backward along local forward ---
	var desired_vel := Vector3.ZERO
	var forward := -transform.basis.z

	if Input.is_action_pressed("forward"):
		desired_vel = forward * move_speed
	elif Input.is_action_pressed("backward"):
		desired_vel = -forward * move_speed

	# Smooth velocity toward desired velocity
	velocity.x = move_toward(velocity.x, desired_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired_vel.z, accel * delta)

	move_and_slide()

func create_fov_rays() -> void:
	fov_rays = _create_rays(7, 90.0, 5.0, fov_mask, Color(1.0, 0.0, 0.0))

func create_env_rays() -> void:
	env_rays = _create_rays(16, 360.0, 5.0, env_mask, Color(1.0, 0.5, 0.0))

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
