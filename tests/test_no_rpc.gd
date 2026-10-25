extends SceneTree

## 无 RPC 测试：网络层所有脚本必须完全不依赖 @rpc，通信全部走通知。
##
## No-RPC test: every network script must avoid @rpc entirely; all communication
## goes through notices.

var failures: int = 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir := DirAccess.open("res://addons/godot_easy_network")
	check(dir != null, "open addons/godot_easy_network")
	if dir == null:
		print("FAILURES=", failures)
		quit(1)
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		var path := "res://addons/godot_easy_network/" + file_name
		var script: Script = load(path)
		check(script != null, "load " + path)
		if script != null:
			check(script.get_rpc_config().is_empty(), path + " has no @rpc methods")
	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)
