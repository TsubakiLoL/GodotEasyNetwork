extends SceneTree

## ByteBuffer 序列化测试：基础类型、游标读取、边界与 Variant 往返。
##
## ByteBuffer serialization tests: primitives, cursor reads, edge cases and
## Variant round-trips.

var failures: int = 0


## 记录一条断言结果。
##
## Records one assertion result.
func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


## 启动测试。
##
## Starts the tests.
func _initialize() -> void:
	_run.call_deferred()


## 依次执行所有用例。
##
## Runs every test case.
func _run() -> void:
	_test_ints()
	_test_floats()
	_test_strings()
	_test_bool_bytes()
	_test_cursor()
	_test_insufficient()
	_test_object()
	_test_variant()
	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)


func _test_ints() -> void:
	var b := ByteBuffer.new()
	var values := [
		0, 1, -1, 63, 64, -64, -65, 127, 128, -128, -129,
		123456789, -123456789,
		9223372036854775807, -9223372036854775807 - 1,
	]
	for v in values:
		b.put_int(v)
	for v in values:
		check(b.get_int() == v, "int roundtrip %d" % v)
	check(b.is_read_finished(), "int buffer fully read")


func _test_floats() -> void:
	var b := ByteBuffer.new()
	b.put_float(3.5)
	b.put_float(-0.25)
	b.put_float(0.0)
	check(is_equal_approx(b.get_float(), 3.5), "float 3.5")
	check(is_equal_approx(b.get_float(), -0.25), "float -0.25")
	check(b.get_float() == 0.0, "float 0.0")
	check(b.is_read_finished(), "float buffer fully read")


func _test_strings() -> void:
	var b := ByteBuffer.new()
	var values := ["", "hello", "中文测试", "a".repeat(1024)]
	for s in values:
		b.put_string(s)
	for s in values:
		check(b.get_string() == s, "string roundtrip len=%d" % s.length())
	check(b.is_read_finished(), "string buffer fully read")


func _test_bool_bytes() -> void:
	var b := ByteBuffer.new()
	b.put_bool(true)
	b.put_bool(false)
	check(b.get_bool() == true, "bool true")
	check(b.get_bool() == false, "bool false")

	var c := ByteBuffer.new()
	var payload := PackedByteArray([0, 1, 2, 255])
	c.put_packed_byte_array(payload)
	c.put_packed_byte_array(PackedByteArray())
	check(c.get_packed_byte_array() == payload, "packed bytes roundtrip")
	check(c.get_packed_byte_array().is_empty(), "empty packed bytes")
	check(c.is_read_finished(), "bytes buffer fully read")


func _test_cursor() -> void:
	var b := ByteBuffer.new()
	b.put_int(7)
	b.put_string("abc")
	b.put_float(1.0)
	var total := b.data.size()
	check(b.read_position == 0, "cursor starts at 0")
	check(b.get_int() == 7, "cursor reads int")
	check(b.read_position > 0, "cursor advanced")
	check(b.data.size() == total, "read does not modify data")
	check(b.get_string() == "abc", "cursor reads string")
	check(b.get_float() == 1.0, "cursor reads float")
	check(b.data.size() == total, "data size stable at end")
	check(b.remaining() == 0 and b.is_read_finished(), "remaining is 0")

	b.reset_read_position()
	check(b.get_int() == 7, "re-read after reset")
	var pos := b.read_position
	check(b.peek_byte() == b.data[pos], "peek returns same byte")
	check(b.read_position == pos, "peek does not advance")
	check(b.skip(4) == 4 and b.read_position == pos + 4, "skip advances")


func _test_insufficient() -> void:
	var incomplete_int := ByteBuffer.new(PackedByteArray([0x80]))
	check(incomplete_int.get_int() == 0, "incomplete int returns 0")
	check(incomplete_int.read_position == 0, "incomplete int keeps cursor")

	var incomplete_str := ByteBuffer.new(PackedByteArray([4, 65]))
	check(incomplete_str.get_string() == "", "incomplete string returns empty")
	check(incomplete_str.read_position == 0, "incomplete string keeps cursor")

	var empty := ByteBuffer.new()
	check(empty.get_float() == 0.0, "empty float")
	check(empty.get_bool() == false, "empty bool")
	check(empty.get_vector2() == Vector2.ZERO, "empty vector2")
	check(empty.get_byte() == 0, "empty byte")


func _test_object() -> void:
	var info := UserInformation.new()
	info.user_name = "Alice"
	var b := ByteBuffer.new()
	b.put_object(info)
	var obj = b.get_object()
	check(obj is UserInformation, "object restores class")
	if obj is UserInformation:
		check(obj.user_name == "Alice", "object restores payload")


func _test_variant() -> void:
	var value := {
		"i": -5,
		"f": 1.25,
		"s": "中文",
		"v": Vector2(1.5, -2.25),
		"b": [1, "x", null, true],
		"d": {"bytes": PackedByteArray([1, 2, 3])},
	}
	var b := ByteBuffer.new()
	b.put_variant(value)
	var back = b.get_variant()
	check(back == value, "variant roundtrip")
	check(b.is_read_finished(), "variant buffer fully read")
