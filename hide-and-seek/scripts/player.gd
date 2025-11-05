extends CharacterBody3D

@export var move_speed := 5.0        # forward speed (m/s)
@export var turn_speed := 2.5        # yaw turn speed (rad/s)
@export var accel := 20.0            # accel for smoothing X/Z

func _physics_process(delta: float) -> void:
	# Apply gravity if not grounded
	if not is_on_floor():
		velocity += get_gravity() * delta

	# --- ROTATION: A/D turn left/right ---
	if Input.is_action_pressed("left"):
		rotate_y(turn_speed * delta)
	elif Input.is_action_pressed("right"):
		rotate_y(-turn_speed * delta)

	# --- MOVEMENT: W/S move forward/backward along local forward ---
	var desired_vel := Vector3.ZERO
	var forward := -transform.basis.z  # Godot’s forward direction is -Z

	if Input.is_action_pressed("forward"):
		desired_vel = forward * move_speed
	elif Input.is_action_pressed("backward"):
		desired_vel = -forward * move_speed   # move backward

	# Smooth velocity toward desired velocity
	velocity.x = move_toward(velocity.x, desired_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired_vel.z, accel * delta)

	move_and_slide()
