extends SceneTree

## Compress 压缩测试：不同大小的数据往返以及消息包往返。
##
## Compress tests: round-trips for data of various sizes and for a message
## payload.

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
	_test_small()
	_test_large()
	_test_message_payload()
	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)


func _test_small() -> void:
	var raw := "Hello Hello Hello Hello".to_utf8_buffer()
	check(Compress.decom(Compress.com(raw)) == raw, "small text roundtrip")


func _test_large() -> void:
	var raw := PackedByteArray()
	raw.resize(100000)
	for i in raw.size():
		raw[i] = (i * 31 + 7) % 256
	check(Compress.decom(Compress.com(raw)) == raw, "100KB binary roundtrip")


func _test_message_payload() -> void:
	Message.initialize_class_cache()
	var info := UserInformation.new()
	info.user_name = "CompressUser"
	var packed := Compress.com(info.to_bytes())
	var restored: Message = Message.from_bytes(Compress.decom(packed))
	check(restored is UserInformation, "message through compress: class restored")
	if restored is UserInformation:
		check(restored.user_name == "CompressUser", "message through compress: payload restored")
