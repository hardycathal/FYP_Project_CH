extends Node3D

# ─── Exports ──────────────────────────────────────────────────────────────────

@export var arena_size := 20.0
@export var wall_height := 3.0
@export var wall_thickness := 0.5
@export var episode_length_steps := 180
@export var preparation_steps := 0
@export var catch_reward := 10.0
@export var catch_distance := 2.5
@export var step_penalty := 0.0
@export var timeout_penalty := -5.0
@export var outer_wall_penalty := 0.0
@export var debug_step_logging := true
@export var action_repeat := 5
@export var bridge_port := 19000
@export var bridge_enabled := true
@export var spawn_boxes := false
@export var easy_training_mode := false
@export var easy_arena_size := 12.0
@export var easy_preparation_steps := 0
@export var randomize_hider_spawn := true
@export var randomize_seeker_spawn := true

# ─── Constants ────────────────────────────────────────────────────────────────

const boxScene := preload("res://scenes/box.tscn")
const hiderScene := preload("res://scenes/hider.tscn")
const seekerScene := preload("res://scenes/seeker.tscn")
const SLOT_GROUP := "block_slot"
const ACTION_IDLE := 0
const MIN_SPAWN_SEPARATION := 8.0

# ─── Scene references ─────────────────────────────────────────────────────────

var player_cam: Camera3D
var hider_cam: Camera3D
@onready var stage_cam: Camera3D = $stage/stageCam

var player
var hider

# ─── Spawn positions ──────────────────────────────────────────────────────────

var seekerPos := Vector3(0, 1, 8)
var hiderPos := Vector3(0, 1, -8)
var hiderYaw := PI

var seeker_spawn_points := [
	Vector3(-4, 1, 7),
	Vector3(0, 1, 7),
	Vector3(4, 1, 7),
	Vector3(0, 1, 4),
]
var hider_spawn_points := [
	Vector3(-4, 1, -7),
	Vector3(0, 1, -7),
	Vector3(4, 1, -7),
	Vector3(0, 1, -4),
]
var all_spawn_points: Array[Vector3] = []

# ─── Arena state ──────────────────────────────────────────────────────────────

var layout_nodes: Array[Node] = []
var box_nodes: Array[RigidBody3D] = []
var box_spawn_positions: Array[Vector3] = []
var current_layout_index := 2

var layouts = [
	{
		"name": "default_room",
		"inner_walls": [
			{ "pos": Vector2(-7, 0), "length": 6.0, "horizontal": true },
			{ "pos": Vector2(-1, 0), "length": 2.0, "horizontal": true },
			{ "pos": Vector2(0, -7), "length": 6.0, "horizontal": false },
			{ "pos": Vector2(0, -1), "length": 2.0, "horizontal": false },
		],
		"boxes": [
			Vector3(2, 0.5, 2),
			Vector3(-3, 0.5, -1),
		],
		"block_slots": [
			{ "pos": Vector3(-3, 1.0, 0), "size": Vector3(3.0, 2.4, 1.5), "yaw": 0.0 },
		],
	},
	{
		"name": "simple_room",
		"inner_walls": [
			{ "pos": Vector2(-1, 0), "length": 5.0, "horizontal": true },
			{ "pos": Vector2(5, 4), "length": 4.0, "horizontal": false },
		],
		"boxes": [
			Vector3(-5, 0.5, -4),
			Vector3(-6, 0.5, 4),
		],
		"block_slots": [],
	},
	{
		"name": "empty_room",
		"inner_walls": [],
		"boxes": [],
		"block_slots": [],
	}
]

# ─── Episode state ────────────────────────────────────────────────────────────

var episode_step := 0
var episode_active := false
var previous_seeker_hider_distance := 0.0

# ─── Bridge ───────────────────────────────────────────────────────────────────

var bridge: Node

# ═════════════════════════════════════════════════════════════════════════════
# Scene lifecycle
# ═════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_parse_cmdline_args()
	_apply_environment_config()
	_create_outer_walls()
	load_layout(current_layout_index)
	_spawn_agents()
	stage_cam.current = true
	_reset_state()
	_start_bridge()

func _process(_delta: float) -> void:
	bridge.poll()

# ═════════════════════════════════════════════════════════════════════════════
# Input
# ═════════════════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reload"):
		_reset_state()

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		_cycle_layout()

	if event.is_action_pressed("debug_reset"):
		_run_debug_reset()

	if event.is_action_pressed("debug_step"):
		_run_debug_step()

	if event.is_action_pressed("hider_cam"):
		stage_cam.current = false
		player_cam.current = false
		hider_cam.current = true

	if event.is_action_pressed("player_cam"):
		stage_cam.current = false
		player_cam.current = true
		hider_cam.current = false

	if event.is_action_pressed("stage_cam"):
		stage_cam.current = true
		player_cam.current = false
		hider_cam.current = false

# ═════════════════════════════════════════════════════════════════════════════
# Arena construction
# ═════════════════════════════════════════════════════════════════════════════

func _create_outer_walls() -> void:
	var half := arena_size / 2.0
	var walls_data = [
		["North", Vector3(0, wall_height / 2, -half), arena_size, wall_thickness],
		["South", Vector3(0, wall_height / 2,  half), arena_size, wall_thickness],
		["East",  Vector3( half, wall_height / 2, 0), wall_thickness, arena_size],
		["West",  Vector3(-half, wall_height / 2, 0), wall_thickness, arena_size],
	]
	for data in walls_data:
		add_child(_create_wall(data[0], data[1], data[2], data[3]))

func _create_wall(wall_name: String, pos: Vector3, size_x: float, size_z: float) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "Wall_" + wall_name
	wall.position = pos

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size_x, wall_height, size_z)
	mesh_instance.mesh = mesh
	wall.add_child(mesh_instance)

	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size_x, wall_height, size_z)
	collider.shape = shape
	wall.add_child(collider)

	return wall

func _create_inner_wall(pos: Vector3, length: float, horizontal: bool) -> void:
	var size_x := length if horizontal else wall_thickness
	var size_z := wall_thickness if horizontal else length
	var wall = _create_wall("Inner", pos, size_x, size_z)
	add_child(wall)
	layout_nodes.append(wall)

func _create_box(pos: Vector3, idx: int) -> void:
	var box := boxScene.instantiate()
	box.name = "Box" + str(idx)

	var mesh_instance := box.get_node("MeshInstance3D")
	mesh_instance.mesh.size = Vector3(2, 2, 2)

	var collider := box.get_node("CollisionShape3D")
	collider.shape.size = Vector3(2, 2, 2)

	box.position = Vector3(pos.x, collider.shape.size.y / 2.0, pos.z)

	add_child(box)
	layout_nodes.append(box)
	box_nodes.append(box)
	box_spawn_positions.append(box.position)

func _create_block_slot(pos: Vector3, size: Vector3, yaw: float) -> void:
	var slot := Area3D.new()
	slot.name = "BlockSlot"
	slot.position = pos
	slot.rotation.y = yaw
	slot.add_to_group(SLOT_GROUP)
	slot.set_meta("snap_position", pos)
	slot.set_meta("snap_yaw", yaw)

	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	slot.add_child(collider)

	add_child(slot)
	layout_nodes.append(slot)

# ═════════════════════════════════════════════════════════════════════════════
# Layout management
# ═════════════════════════════════════════════════════════════════════════════

func load_layout(index: int) -> void:
	current_layout_index = posmod(index, layouts.size())

	for node in layout_nodes:
		if is_instance_valid(node):
			node.queue_free()
	layout_nodes.clear()
	box_nodes.clear()
	box_spawn_positions.clear()

	var layout = layouts[current_layout_index]
	var box_list = layout["boxes"]
	var block_slots = layout.get("block_slots", [])

	if not spawn_boxes or easy_training_mode:
		box_list = []
		block_slots = []

	for w in layout["inner_walls"]:
		var pos3 := Vector3(w["pos"].x, wall_height / 2.0, w["pos"].y)
		_create_inner_wall(pos3, w["length"], w["horizontal"])

	for i in range(box_list.size()):
		_create_box(box_list[i], i + 1)

	for slot_data in block_slots:
		_create_block_slot(slot_data["pos"], slot_data["size"], slot_data["yaw"])

func _cycle_layout() -> void:
	load_layout(current_layout_index + 1)
	_reset_state()

# ═════════════════════════════════════════════════════════════════════════════
# Agent spawning
# ═════════════════════════════════════════════════════════════════════════════

func _spawn_agents() -> void:
	if player == null:
		player = seekerScene.instantiate()
		add_child(player)
	if hider == null:
		hider = hiderScene.instantiate()
		add_child(hider)

	player.hider_ref = hider
	hider.seeker_ref = player
	player.position = seekerPos
	hider.position = hiderPos
	hider.rotation.y = hiderYaw
	hider_cam = hider.get_node("head/Camera3D")
	player_cam = player.get_node("head/Camera3D")

# ═════════════════════════════════════════════════════════════════════════════
# Episode logic
# ═════════════════════════════════════════════════════════════════════════════

func _reset_state() -> void:
	episode_step = 0
	episode_active = true

	_select_spawns()

	if player:
		player.reset_agent_state(seekerPos, randf_range(0.0, TAU))
		player.clear_action_override()
	if hider:
		hider.reset_agent_state(hiderPos, hiderYaw)

	previous_seeker_hider_distance = seekerPos.distance_to(hiderPos)

	for i in range(box_nodes.size()):
		var box := box_nodes[i]
		if not is_instance_valid(box):
			continue
		box.freeze = false
		box.collision_layer = 2
		box.collision_mask = 15
		box.linear_velocity = Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		box.global_position = box_spawn_positions[i]
		box.rotation = Vector3.ZERO

func reset_episode() -> Dictionary:
	_reset_state()
	return {
		"observation": player.get_observation() if player else [],
		"seeker_observation": player.get_observation() if player else [],
		"hider_observation": hider.get_observation() if hider else [],
		"reward": 0.0,
		"seeker_reward": 0.0,
		"hider_reward": 0.0,
		"done": false,
		"info": { "episode_step": episode_step, "in_preparation": true },
	}

func reset_episode_async() -> Dictionary:
	_reset_state()
	if player:
		player.force_update_transform()
	if hider:
		hider.force_update_transform()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var seeker_obs := _augment_observation(player.get_observation() if player else [])
	var hider_obs := _augment_observation(hider.get_observation() if hider else [])
	return {
		"observation": seeker_obs,
		"seeker_observation": seeker_obs,
		"hider_observation": hider_obs,
		"reward": 0.0,
		"seeker_reward": 0.0,
		"hider_reward": 0.0,
		"done": false,
		"info": { "episode_step": episode_step, "in_preparation": true },
	}

func step(seeker_action: int, hider_action: int = ACTION_IDLE) -> Dictionary:
	if not episode_active:
		_reset_state()

	if player:
		player.set_action(ACTION_IDLE if episode_step < _get_preparation_steps() else seeker_action)
	if hider:
		hider.set_action(hider_action)

	for _i in range(action_repeat):
		await get_tree().physics_frame

	if player:
		player.clear_action_override()
	if hider:
		hider.clear_action_override()

	episode_step += 1

	var in_preparation := episode_step <= _get_preparation_steps()
	var sees_hider: bool = player.sees_hider() if player != null else false
	var sees_seeker: bool = hider.sees_seeker() if hider != null else false
	var caught_hider: bool = _is_hider_caught()
	var current_distance: float = _get_seeker_hider_distance()
	var distance_delta: float = max(previous_seeker_hider_distance - current_distance, 0.0)
	var done: bool = false
	var seeker_reward: float = 0.0
	var hider_reward: float = 0.0

	if not in_preparation:
		seeker_reward = 0.05 * distance_delta
		hider_reward = -seeker_reward
		if caught_hider:
			seeker_reward += catch_reward
			hider_reward -= catch_reward
		if player != null and player.is_touching_outer_wall():
			seeker_reward += outer_wall_penalty
		done = caught_hider

	if episode_step >= episode_length_steps:
		if not caught_hider:
			seeker_reward += timeout_penalty
			hider_reward -= timeout_penalty
		done = true

	if done:
		episode_active = false

	previous_seeker_hider_distance = current_distance

	var seeker_obs := _augment_observation(player.get_observation() if player else [])
	var hider_obs := _augment_observation(hider.get_observation() if hider else [])
	return {
		"observation": seeker_obs,
		"seeker_observation": seeker_obs,
		"hider_observation": hider_obs,
		"reward": seeker_reward,
		"seeker_reward": seeker_reward,
		"hider_reward": hider_reward,
		"done": done,
		"info": {
			"episode_step": episode_step,
			"in_preparation": in_preparation,
			"sees_hider": sees_hider,
			"sees_seeker": sees_seeker,
			"caught_hider": caught_hider,
		},
	}

# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

func _apply_environment_config() -> void:
	current_layout_index = 1
	preparation_steps = 40
	catch_reward = 10.0
	spawn_boxes = true
	all_spawn_points = [
		# Corners
		Vector3( 6, 1,  6), Vector3(-4, 1,  7),
		Vector3( 6, 1, -6), Vector3(-6, 1, -6),
		# Edge midpoints
		Vector3( 8, 1,  0), Vector3(-8, 1,  0),
		Vector3( 0, 1,  8), Vector3( 0, 1, -8),
		# Inner ring
		Vector3( 3, 1,  6), Vector3(-4, 1,  4),
		Vector3( 4, 1, -4), Vector3(-4, 1, -6),
	]
	if easy_training_mode:
		arena_size = easy_arena_size

func _get_preparation_steps() -> int:
	return easy_preparation_steps if easy_training_mode else preparation_steps

func _select_spawns() -> void:
	if all_spawn_points.is_empty():
		return
	seekerPos = all_spawn_points[randi() % all_spawn_points.size()]
	var candidates: Array[Vector3] = []
	for p in all_spawn_points:
		if p.distance_to(seekerPos) >= MIN_SPAWN_SEPARATION:
			candidates.append(p)
	if candidates.is_empty():
		candidates = all_spawn_points
	hiderPos = candidates[randi() % candidates.size()]
	hiderYaw = randf_range(0.0, TAU)

func _is_hider_caught() -> bool:
	if player == null or hider == null:
		return false
	return player.global_position.distance_to(hider.global_position) <= catch_distance

func _get_seeker_hider_distance() -> float:
	if player == null or hider == null:
		return 0.0
	return player.global_position.distance_to(hider.global_position)

func _augment_observation(obs: Array) -> Array:
	var augmented := obs.duplicate()
	augmented.append(float(episode_step) / float(episode_length_steps))
	return augmented

func _parse_cmdline_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			var port_str := arg.substr(7)
			if port_str.is_valid_int():
				bridge_port = int(port_str)
				print("[BRIDGE] Port overridden to %d via command line" % bridge_port)

# ═════════════════════════════════════════════════════════════════════════════
# Bridge setup
# ═════════════════════════════════════════════════════════════════════════════

func _start_bridge() -> void:
	bridge = load("res://scripts/bridge.gd").new()
	bridge.bridge_port = bridge_port
	bridge.bridge_enabled = bridge_enabled
	bridge.init(self)
	add_child(bridge)
	bridge.start()

# ═════════════════════════════════════════════════════════════════════════════
# Debug controls (in-editor testing)
# ═════════════════════════════════════════════════════════════════════════════

func _run_debug_step() -> void:
	var seeker_action := randi_range(0, 4)
	var hider_action := randi_range(0, 4)
	var result = await step(seeker_action, hider_action)
	if debug_step_logging:
		_log_step_result("seeker=%d hider=%d" % [seeker_action, hider_action], result)

func _run_debug_reset() -> void:
	var result = await reset_episode_async()
	if debug_step_logging:
		_log_step_result("reset", result)

func _log_step_result(label: String, result: Dictionary) -> void:
	var observation = result.get("observation", [])
	var info: Dictionary = result.get("info", {})
	print(
		"[ENV %s] obs=%d reward=%.3f done=%s prep=%s step=%s sees_hider=%s" % [
			label,
			observation.size(),
			float(result.get("reward", 0.0)),
			str(result.get("done", false)),
			str(info.get("in_preparation", false)),
			str(info.get("episode_step", -1)),
			str(info.get("sees_hider", false)),
		]
	)
