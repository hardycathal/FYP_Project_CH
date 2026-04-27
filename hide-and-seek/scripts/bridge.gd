extends Node

# ─── Configuration ───────────────────────────────────────────────────────────

@export var bridge_port := 19000
@export var bridge_enabled := true

# ─── State ───────────────────────────────────────────────────────────────────

var _main: Node
var _server := TCPServer.new()
var _client: StreamPeerTCP
var _buffer := ""
var _busy := false

# ─── Public API ──────────────────────────────────────────────────────────────

func init(main_node: Node) -> void:
	_main = main_node

func start() -> void:
	if not bridge_enabled:
		return
	var err := _server.listen(bridge_port)
	if err == OK:
		print("[BRIDGE] Listening on port %d" % bridge_port)
	else:
		push_warning("[BRIDGE] Failed to listen on port %d (error %d)" % [bridge_port, err])

func poll() -> void:
	if not bridge_enabled or not _server.is_listening():
		return
	_accept_connection()
	_read_client()

# ─── Connection handling ──────────────────────────────────────────────────────

func _accept_connection() -> void:
	if _client == null and _server.is_connection_available():
		_client = _server.take_connection()
		_buffer = ""
		_busy = false
		print("[BRIDGE] Client connected")

func _read_client() -> void:
	if _client == null:
		return

	_client.poll()
	var status := _client.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		print("[BRIDGE] Client disconnected")
		_client = null
		_buffer = ""
		_busy = false
		return

	if _busy:
		return

	var available := _client.get_available_bytes()
	if available <= 0:
		return

	_buffer += _client.get_utf8_string(available)
	while _buffer.contains("\n") and not _busy:
		var newline_index := _buffer.find("\n")
		var raw_line := _buffer.substr(0, newline_index).strip_edges()
		_buffer = _buffer.substr(newline_index + 1)
		if raw_line.is_empty():
			continue
		_handle_line(raw_line)

# ─── Command dispatch ─────────────────────────────────────────────────────────

func _handle_line(raw_line: String) -> void:
	var json := JSON.new()
	if json.parse(raw_line) != OK:
		_respond({"ok": false, "error": "invalid_json"})
		return

	var message = json.data
	if typeof(message) != TYPE_DICTIONARY:
		_respond({"ok": false, "error": "invalid_message"})
		return

	var command := str(message.get("cmd", ""))
	match command:
		"reset":
			_busy = true
			_handle_reset()
		"step":
			var seeker_action := int(message.get("seeker_action", message.get("action", 0)))
			var hider_action := int(message.get("hider_action", 0))
			_busy = true
			_handle_step(seeker_action, hider_action)
		_:
			_respond({"ok": false, "error": "unknown_command"})

func _handle_reset() -> void:
	var result = await _main.reset_episode_async()
	_respond({"ok": true, "result": result})
	_busy = false

func _handle_step(seeker_action: int, hider_action: int) -> void:
	var result = await _main.step(seeker_action, hider_action)
	_respond({"ok": true, "result": result})
	_busy = false

# ─── Response ─────────────────────────────────────────────────────────────────

func _respond(payload: Dictionary) -> void:
	if _client == null:
		return
	_client.poll()
	var line := JSON.stringify(payload) + "\n"
	_client.put_data(line.to_utf8_buffer())
