extends SceneTree

## 联机集成测试控制器：拉起 1 个服务器进程与若干客户端进程，
## 通过真实 ENet 连接验证「建房间 → 加入 → 下发请求 → 各端执行 → 队列结束」。
##
## Integration test controller: spawns one server process and several client
## processes, verifies the real ENet flow (create room, join, dispatch request,
## execute on every peer, finish the queue).

const OUT := "res://tests/integration/out"
const PORT := 19939
const CLIENT_COUNT := 3
const PEER_SCRIPT := "res://tests/integration/peer.gd"

var failures: int = 0
var children: Array[int] = []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean_out()
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")

	print("spawning server on port ", PORT)
	children.append(_spawn(exe, project, "server", "server", CLIENT_COUNT))
	check(await _wait_file(OUT + "/ready.json", 15000), "server is listening")

	for i in CLIENT_COUNT:
		var client_name := "c%d" % (i + 1)
		print("spawning client ", client_name)
		children.append(_spawn(exe, project, "client", client_name, CLIENT_COUNT))

	var server_ok := await _wait_file(OUT + "/server_server.json", 25000)
	check(server_ok, "server reported")
	var clients_ok := true
	for i in CLIENT_COUNT:
		var client_name := "c%d" % (i + 1)
		if not await _wait_file("%s/client_%s.json" % [OUT, client_name], 25000):
			clients_ok = false
	check(clients_ok, "all clients reported")

	var server_result = _read_json(OUT + "/server_server.json")
	check(server_result != null, "server result readable")
	if server_result != null:
		check(server_result.get("create_ok", false), "server created room")
		check(server_result.get("joined", 0) == CLIENT_COUNT,
			"server saw %d clients (saw %d)" % [CLIENT_COUNT, server_result.get("joined", 0)])
		check(server_result.get("finished", false), "server queue finished the request")
		check(server_result.get("log", []) == ["hello"], "server executed the request")
		check(server_result.get("sync_ok", false), "server sync node became ready")
		if server_result.has("error"):
			print("server error: ", server_result["error"])

	for i in CLIENT_COUNT:
		var client_name := "c%d" % (i + 1)
		var client_result = _read_json("%s/client_%s.json" % [OUT, client_name])
		check(client_result != null, "client %s result readable" % client_name)
		if client_result != null:
			check(client_result.get("joined", false), "client %s joined" % client_name)
			check(client_result.get("log", []) == ["hello"],
				"client %s executed the request" % client_name)
			check(client_result.get("sync_ok", false),
				"client %s sync node became ready" % client_name)
			if client_result.has("error"):
				print("client %s error: %s" % [client_name, client_result["error"]])

	for pid in children:
		if OS.is_process_running(pid):
			OS.kill(pid)
	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)


func _spawn(exe: String, project: String, role: String, peer_name: String, clients: int) -> int:
	var log_path := "%s/%s_%s.log" % [ProjectSettings.globalize_path(OUT), role, peer_name]
	return OS.create_process(exe, [
		"--headless",
		"--path", project,
		"--script", PEER_SCRIPT,
		"--log-file", log_path,
		"--",
		"--role=" + role,
		"--port=%d" % PORT,
		"--clients=%d" % clients,
		"--name=" + peer_name,
	])


func _wait_file(path: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path):
			return true
		await process_frame
	return false


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return JSON.parse_string(text)


func _clean_out() -> void:
	var absolute := ProjectSettings.globalize_path(OUT)
	if DirAccess.dir_exists_absolute(absolute):
		var dir := DirAccess.open(absolute)
		for file_name in dir.get_files():
			dir.remove(file_name)
	else:
		DirAccess.make_dir_recursive_absolute(absolute)
