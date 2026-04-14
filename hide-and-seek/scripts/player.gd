extends CharacterBody3D

# Movement, sensing, and interaction configuration
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
const BLOCK_SLOT_GROUP := "block_slot"
const ACTION_IDLE := 0
const ACTION_FORWARD := 1
const ACTION_TURN_LEFT := 2
const ACTION_TURN_RIGHT := 3
const ACTION_BACKWARD := 4
@export var grab_range := 2.5
@export var carry_offset := Vector3(0.0, 1.2, -2.0)
@export var block_slot_snap_range := 1.75
@export var manual_input_enabled := true
@export var env_ray_length := 15.0
@export var fov_ray_length := 5.0
var fov_rays: Array[RayCast3D] = []
var env_rays: Array[RayCast3D] = []
var carried_box: RigidBody3D
var carried_box_layer := 0
var carried_box_mask := 0
var current_action := ACTION_IDLE
var action_override_enabled := false
var touched_outer_wall := false

# Lifecycle and per-frame control
func _ready() -> void:
	create_fov_rays()
	create_env_rays()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("grab"):
		_toggle_grab()

func _physics_process(delta: float) -> void:
	touched_outer_wall = false
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

	var action := _get_effective_action()

	# --- ROTATION: A/D turn left/right ---
	if action == ACTION_TURN_LEFT:
		rotate_y(turn_speed * delta)
	elif action == ACTION_TURN_RIGHT:
		rotate_y(-turn_speed * delta)

	# --- MOVEMENT: W/S move forward/backward along local forward ---
	var desired_vel := Vector3.ZERO
	var forward := -transform.basis.z

	if action == ACTION_FORWARD:
		desired_vel = forward * move_speed
	elif action == ACTION_BACKWARD:
		desired_vel = -forward * move_speed

	# Smooth velocity toward desired velocity
	velocity.x = move_toward(velocity.x, desired_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired_vel.z, accel * delta)

	move_and_slide()
	_update_wall_contact_state()
	_update_carried_box()

# Ray setup
func create_fov_rays() -> void:
	fov_rays = _create_rays(7, 90.0, fov_ray_length, fov_mask, Color(1.0, 0.0, 0.0))

func create_env_rays() -> void:
	env_rays = _create_rays(16, 360.0, env_ray_length, env_mask, Color(1.0, 0.5, 0.0))

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

# Box carry and placement
func _toggle_grab() -> void:
	if carried_box:
		_release_box()
		return

	var candidate := _find_nearby_box()
	if candidate:
		_grab_box(candidate)

func _find_nearby_box() -> RigidBody3D:
	var shape := SphereShape3D.new()
	shape.radius = grab_range

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = LAYER_BOXES
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [self]

	var space_state := get_world_3d().direct_space_state
	var results := space_state.intersect_shape(query, 8)
	var nearest_box: RigidBody3D
	var nearest_distance := INF

	for result in results:
		var body = result.get("collider")
		if body is RigidBody3D:
			var distance := global_position.distance_to(body.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_box = body

	return nearest_box

func _grab_box(box: RigidBody3D) -> void:
	carried_box = box
	carried_box_layer = box.collision_layer
	carried_box_mask = box.collision_mask
	box.freeze = true
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	box.collision_layer = 0
	box.collision_mask = 0

func _release_box() -> void:
	if not carried_box:
		return

	_try_snap_to_block_slot(carried_box)
	carried_box.freeze = false
	carried_box.collision_layer = carried_box_layer
	carried_box.collision_mask = carried_box_mask
	carried_box = null
	carried_box_layer = 0
	carried_box_mask = 0

func _update_carried_box() -> void:
	if not carried_box:
		return

	var origin := carried_box.global_position
	var desired_pos := to_global(carry_offset)
	var clamped_pos := _get_clamped_carry_position(origin, desired_pos)
	var carry_error := desired_pos - clamped_pos

	if carry_error.length_squared() > 0.0001:
		global_position -= Vector3(carry_error.x, 0.0, carry_error.z)
		velocity.x = 0.0
		velocity.z = 0.0

	carried_box.global_position = clamped_pos
	carried_box.linear_velocity = Vector3.ZERO
	carried_box.angular_velocity = Vector3.ZERO

func _get_clamped_carry_position(origin: Vector3, desired_pos: Vector3) -> Vector3:
	var collider := carried_box.get_node("CollisionShape3D") as CollisionShape3D
	if collider == null or collider.shape == null:
		return desired_pos

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.collision_mask = LAYER_WORLD | LAYER_BOXES
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [self, carried_box]

	var basis := carried_box.global_transform.basis
	var steps := 24

	for i in range(steps, -1, -1):
		var t := float(i) / float(steps)
		var candidate := origin.lerp(desired_pos, t)
		query.transform = Transform3D(basis, candidate)
		var hits := get_world_3d().direct_space_state.intersect_shape(query, 1)
		if hits.is_empty():
			return candidate

	return carried_box.global_position

func _try_snap_to_block_slot(box: RigidBody3D) -> bool:
	var nearest_slot: Area3D
	var nearest_distance := block_slot_snap_range

	for node in get_tree().get_nodes_in_group(BLOCK_SLOT_GROUP):
		if node is Area3D:
			var distance := box.global_position.distance_to(node.global_position)
			if distance <= nearest_distance:
				nearest_distance = distance
				nearest_slot = node

	if nearest_slot == null:
		return false

	var snap_position: Vector3 = nearest_slot.get_meta("snap_position", nearest_slot.global_position)
	var snap_yaw: float = nearest_slot.get_meta("snap_yaw", nearest_slot.global_rotation.y)
	box.global_position = snap_position
	box.rotation.y = snap_yaw
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	return true

# External control API
func set_action(action_id: int) -> void:
	current_action = clampi(action_id, ACTION_IDLE, ACTION_BACKWARD)
	action_override_enabled = true

func clear_action_override() -> void:
	action_override_enabled = false
	current_action = ACTION_IDLE

func set_manual_input_enabled(enabled: bool) -> void:
	manual_input_enabled = enabled

func _get_effective_action() -> int:
	if action_override_enabled:
		return current_action
	if manual_input_enabled:
		return _get_manual_action()
	return ACTION_IDLE

func _get_manual_action() -> int:
	if Input.is_action_pressed("left"):
		return ACTION_TURN_LEFT
	if Input.is_action_pressed("right"):
		return ACTION_TURN_RIGHT
	if Input.is_action_pressed("forward"):
		return ACTION_FORWARD
	if Input.is_action_pressed("backward"):
		return ACTION_BACKWARD
	return ACTION_IDLE

# Observation helpers
func get_observation() -> Array[float]:
	var observation: Array[float] = []
	observation.append(velocity.x / move_speed)
	observation.append(velocity.z / move_speed)
	observation.append(sin(rotation.y))
	observation.append(cos(rotation.y))
	observation.append(1.0 if carried_box else 0.0)
	observation.append_array(_get_ray_distance_observations(env_rays, env_ray_length))
	observation.append_array(_get_ray_distance_observations(fov_rays, fov_ray_length))
	observation.append(1.0 if _can_see_hider() else 0.0)
	return observation

func _get_ray_distance_observations(rays: Array[RayCast3D], max_length: float) -> Array[float]:
	var distances: Array[float] = []

	for ray in rays:
		ray.force_raycast_update()
		if ray.is_colliding():
			var hit_distance := ray.global_position.distance_to(ray.get_collision_point())
			distances.append(clampf(hit_distance / max_length, 0.0, 1.0))
		else:
			distances.append(1.0)

	return distances

func _can_see_hider() -> bool:
	for ray in fov_rays:
		ray.force_raycast_update()
		if ray.is_colliding() and ray.get_collider() == hider_ref:
			return true
	return false

func _update_wall_contact_state() -> void:
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider = collision.get_collider()
		if collider is Node and str(collider.name).begins_with("Wall_") and str(collider.name) != "Wall_Inner":
			touched_outer_wall = true
			return

# Environment queries and reset support
func sees_hider() -> bool:
	return _can_see_hider()

func is_touching_outer_wall() -> bool:
	return touched_outer_wall

func reset_agent_state(position: Vector3, yaw: float = 0.0) -> void:
	if carried_box:
		_release_box()
	clear_action_override()
	velocity = Vector3.ZERO
	global_position = position
	rotation = Vector3(0.0, yaw, 0.0)
