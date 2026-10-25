extends SceneTree

## Factory 序列化测试：字典 / 数组 / 可序列化对象、深度转换与空数据。
##
## Factory serialization tests: dictionaries, arrays, serializable objects,
## deep conversion and empty input.

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
	_test_dict()
	_test_array()
	_test_object_value()
	_test_deep()
	_test_serialize_api()
	_test_empty()
	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)


func _test_dict() -> void:
	var dict := {
		"nil": null,
		"bool": true,
		"int": -123456,
		"float": -2.5,
		"string": "中文",
		"vector2": Vector2(1, 2),
		"bytes": PackedByteArray([9, 8, 7]),
		"array": [1, "two", null, false],
		"nested": {"deep": {"deeper": [1, 2, 3]}},
	}
	var back := Factory.bytes_to_dict(Factory.dict_to_bytes(dict))
	check(back == dict, "dict roundtrip")


func _test_array() -> void:
	var arr := [1, "x", {"k": [true, 2.5]}, PackedByteArray([4, 5])]
	var back := Factory.bytes_to_array(Factory.array_to_bytes(arr))
	check(back == arr, "array roundtrip")


func _test_object_value() -> void:
	var info := UserInformation.new()
	info.user_name = "Alice"
	var dict := {"user": info, "list": [info]}
	var back := Factory.bytes_to_dict(Factory.dict_to_bytes(dict))
	check(back["user"] is UserInformation, "dict object restores class")
	check(back["list"][0] is UserInformation, "array object restores class")
	if back["user"] is UserInformation:
		check(back["user"].user_name == "Alice", "dict object restores payload")


func _test_deep() -> void:
	var info := UserInformation.new()
	info.user_name = "Bob"
	var value := {"one": info, "many": [info, {"inner": info}]}
	var deep: Dictionary = Factory.deep_serialize(value)
	check(deep["one"] is Dictionary and deep["one"].has("__type__"), "deep serialize to dict")
	var back: Dictionary = Factory.deep_deserialize(deep)
	check(back["one"] is UserInformation, "deep deserialize object")
	check(back["many"][0] is UserInformation, "deep deserialize nested array object")
	check(back["many"][1]["inner"] is UserInformation, "deep deserialize nested dict object")
	if back["one"] is UserInformation:
		check(back["one"].user_name == "Bob", "deep deserialize payload")


func _test_serialize_api() -> void:
	var info := UserInformation.new()
	info.user_name = "Carol"
	info.is_ready = true
	var data := Factory.serialize(info)
	check(data.has("__type__") and data.has("__data__"), "serialize keys")
	var back = Factory.deserialize(data)
	check(back is UserInformation, "deserialize class")
	if back is UserInformation:
		check(back.user_name == "Carol" and back.is_ready, "deserialize payload")
	check(Factory.is_serializable(info), "is_serializable")
	check(Factory.is_serializable_bytes(info), "is_serializable_bytes")


func _test_empty() -> void:
	check(Factory.bytes_to_dict(PackedByteArray()) == {}, "empty dict bytes")
	check(Factory.bytes_to_array(PackedByteArray()) == [], "empty array bytes")
