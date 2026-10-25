extends SceneTree

## 联机集成测试端：以服务器或客户端身份加入本地 ENet 房间，
## 由服务器下发一次 RequestCall，所有端执行后回执。
##
## Network integration peer: joins a local ENet room as server or client, then
## the server dispatches one RequestCall that every peer executes and reports
## finished.

const OUT := "res://tests/integration/out"
const TARGET_SCRIPT := "res://tests/fixtures/call_target.gd"
const SPAWNER_SCRIPT := "res://tests/fixtures/sync_spawner.gd"

## 角色：server 或 client。
##
## Role: server or client.
var role := "server"
## 监听 / 连接端口。
##
## Listening / connecting port.
var port := 19939
## 预期客户端数量（仅服务器使用）。
##
## Expected client count (server only).
var expected_clients := 3
## 本进程名称，用于结果文件名与客户端用户名。
##
## This process' name, used for the result file and the client user name.
var peer_name := "server"

var result: Dictionary = {}
var target: Node

var _create_ok := false
var _finished := false
var _joined_count := 0
var _join_reported := false
var _join_ok := false
var _notices: Array = []


func _initialize() -> void:
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--clients="):
			expected_clients = int(arg.trim_prefix("--clients="))
		elif arg.begins_with("--name="):
			peer_name = arg.trim_prefix("--name=")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var script: Script = load(TARGET_SCRIPT)
	target = script.new()
	target.name = "Target"
	root.add_child(target)

	var spawner_script: Script = load(SPAWNER_SCRIPT)
	var spawner = spawner_script.new()
	spawner.name = "Spawner"
	root.add_child(spawner)

	var net: NetworkInstance = root.get_node_or_null("Network")
	if net == null:
		net = NetworkInstance.new()
		net.name = "Network"
		root.add_child(net)

	if role == "server":
		result = {"role": "server", "create_ok": false, "joined": 0, "finished": false, "sync_ok": false, "log": []}
		await _run_server(net, spawner)
	else:
		result = {"role": "client", "joined": false, "sync_ok": false, "log": []}
		await _run_client(net)
	_finish()


func _run_server(net: Node, spawner: Node) -> void:
	net.create_room_finished.connect(_on_create_room_finished)
	net.user_join.connect(_on_user_join)
	net.request_finished.connect(_on_request_finished)
	net.notice_get.connect(_on_notice_get)

	var info := UserInformation.new()
	info.user_name = "server"
	net.request_create_room(info, port)

	var deadline := Time.get_ticks_msec() + 15000
	while not _create_ok and Time.get_ticks_msec() < deadline:
		await process_frame
	result["create_ok"] = _create_ok
	if not _create_ok:
		result["error"] = "create room failed"
		return
	_write_json(OUT + "/ready.json", {"ready": true})

	while _joined_count < expected_clients and Time.get_ticks_msec() < deadline:
		await process_frame
	result["joined"] = _joined_count
	result["notices"] = _notices.duplicate()
	result["room_size"] = net.room_user_information.size()
	result["peer_without_name"] = net.peer_without_name.duplicate()
	if _joined_count < expected_clients:
		result["error"] = "not all clients joined (%d/%d)" % [_joined_count, expected_clients]
		return

	var request := RequestCall.new()
	request.add_call(spawner, "spawn_sync_node")
	request.add_call(target, "record", "hello")
	net.push_request(request)

	while not _finished and Time.get_ticks_msec() < deadline:
		await process_frame

	result["joined"] = _joined_count
	result["finished"] = _finished
	result["log"] = target.log.duplicate()
	result["sync_ok"] = await _wait_sync_ready(deadline)
	if not _finished:
		result["error"] = "request did not finish"


func _run_client(net: Node) -> void:
	net.join_room_finished.connect(_on_join_room_finished)

	var info := UserInformation.new()
	info.user_name = peer_name
	net.request_join_room(info, "127.0.0.1", port, 10)

	var deadline := Time.get_ticks_msec() + 15000
	while not _join_reported and Time.get_ticks_msec() < deadline:
		await process_frame
	result["joined"] = _join_ok
	if not _join_ok:
		result["error"] = "join failed"
		return

	while target.log.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	result["log"] = target.log.duplicate()
	result["sync_ok"] = await _wait_sync_ready(deadline)
	if target.log.is_empty():
		result["error"] = "request not received"


## 等待测试同步节点就绪。
##
## Waits until the test synchronized node reports ready.
func _wait_sync_ready(deadline: int) -> bool:
	while Time.get_ticks_msec() < deadline:
		var node := root.get_node_or_null("SyncTarget")
		if node != null and node.is_ready:
			return true
		await process_frame
	return false


func _on_create_room_finished(success: bool) -> void:
	_create_ok = success


func _on_user_join(_peer_id: int, _mes: UserInformation) -> void:
	_joined_count += 1


func _on_request_finished(_request: Request) -> void:
	_finished = true


func _on_notice_get(peer_id: int, notice: Message) -> void:
	var script: Script = notice.get_script()
	_notices.append("%d:%s" % [peer_id, script.get_global_name() if script != null else "?"])


func _on_join_room_finished(success: bool) -> void:
	_join_reported = true
	_join_ok = success


func _finish() -> void:
	_write_json("%s/%s_%s.json" % [OUT, role, peer_name], result)
	quit()


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入结果文件: " + path)
		return
	file.store_string(JSON.stringify(data))
	file.close()
