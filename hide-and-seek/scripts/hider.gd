extends CharacterBody3D
@onready var head: Node3D = $head
@export var move_speed := 5.0 #m/s
@export var turn_speed := 2.5 #rad/s
@export var accel := 20.0          
@onready var camera_3d: Camera3D = $head/Camera3D

const rayScene = preload("res://scenes/raycast.tscn")
var ray: RayCast3D
var rays: Array[RayCast3D] = []

func _ready() -> void:
	createRays()

func _physics_process(delta: float) -> void:
	#for r in rays:
		#r.force_raycast_update()
		#if r.is_colliding():
			#var collider := r.get_collider()
			#print("HiderHit:", collider)
	
	
	if not is_on_floor():
		velocity += get_gravity() * delta

	# --- ROTATION: A/D turn left/right ---
	if Input.is_action_pressed("arrow_left"):
		rotate_y(turn_speed * delta)
	elif Input.is_action_pressed("arrow_right"):
		rotate_y(-turn_speed * delta)

	# --- MOVEMENT: W/S move forward/backward along local forward ---
	var desired_vel := Vector3.ZERO
	var forward := -transform.basis.z

	if Input.is_action_pressed("arrow_up"):
		desired_vel = forward * move_speed
	elif Input.is_action_pressed("arrow_down"):
		desired_vel = -forward * move_speed

	# Smooth velocity toward desired velocity
	velocity.x = move_toward(velocity.x, desired_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired_vel.z, accel * delta)
	
	move_and_slide()

func createRays() -> void:
	var num_rays: int = 16
	var spread_deg: float = 360
	var half_spread: float = deg_to_rad(spread_deg / 2.0)

	for i in range(num_rays):
		ray= rayScene.instantiate()

		ray.position = camera_3d.position

		var w: float = float(i) / float(num_rays - 1)   # 0..1
		var angle: float = lerp(-half_spread, half_spread, w)

		var dir_local: Vector3 = Vector3(sin(angle), 0.0, -cos(angle))
		ray.target_position = dir_local * 5.0   # length

		ray.debug_shape_custom_color = Color(1.0, 0.0, 0.0)
		ray.debug_shape_thickness = 1

		ray.enabled = true
		ray.collide_with_areas = true
		ray.collide_with_bodies = true
		ray.collision_mask = 1 | 2

		head.add_child(ray)
		rays.append(ray)
