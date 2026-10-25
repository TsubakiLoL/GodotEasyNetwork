## 序列化工厂：在对象、字典、数组和字节流之间互相转换。
##
## Serialization factory: converts between objects, dictionaries, arrays and
## byte streams.
class_name Factory

## 将可序列化对象转换为字典。
##
## 返回的字典包含类型标记和实际数据。
##
## Converts a serializable object into a dictionary. The returned dictionary
## contains a type marker and the exported data.
static func serialize(obj: Object) -> Dictionary:
	if not obj.has_method("export_data"):
		push_error("对象未实现 export_data() 方法，无法序列化")
		return {}
	var script = obj.get_script()
	if not script:
		push_error("对象无关联脚本，无法在反序列化时重新创建")
		return {}
	return {
		"__type__": script.resource_path,
		"__data__": obj.export_data()
	}

## 从字典反序列化为对象。
##
## 字典必须是由 serialize() 生成的格式。
##
## Deserializes an object from a dictionary. The dictionary must follow the
## format produced by [method serialize].
static func deserialize(dict: Dictionary):
	if not dict.has("__type__") or not dict.has("__data__"):
		push_error("字典格式无效，缺少 __type__ 或 __data__ 字段")
		return null
	var type_path: String = dict["__type__"]
	if not ResourceLoader.exists(type_path):
		push_error("找不到脚本资源: " + type_path)
		return null
	var script = load(type_path)
	var instance = script.new()
	if not instance.has_method("import_data"):
		push_error("实例未实现 import_data() 方法，无法导入数据")
		return null
	instance.import_data(dict["__data__"])
	return instance
 

## 检测对象是否为可序列化实例。
##
## 需要实现 export_data() 和 import_data() 两个方法。
##
## Returns whether the object is a serializable instance. It must implement
## both [code]export_data()[/code] and [code]import_data()[/code].
static func is_serializable(obj: Object) -> bool:
	return obj.has_method("export_data") and obj.has_method("import_data")


## 深度遍历数据结构，将可序列化对象转换为字典。
##
## 对于 Godot 基础类型直接保留，可序列化对象替换为字典，不可序列化对象变为 null；
## 支持嵌套的字典和数组。
##
## Deep-walks a data structure and converts serializable objects into
## dictionaries. Built-in Godot types are kept as-is, serializable objects are
## replaced with dictionaries, and non-serializable objects become null.
## Nested dictionaries and arrays are supported.
static func deep_serialize(value):
	match typeof(value):
		TYPE_DICTIONARY:
			var new_dict := {}
			for key in value.keys():
				new_dict[key] = deep_serialize(value[key])
			return new_dict
		TYPE_ARRAY:
			var new_array := []
			for element in value:
				new_array.append(deep_serialize(element))
			return new_array
		TYPE_OBJECT:
			if is_serializable(value):
				return serialize(value)
			else:
				return null
		_:
			return value


## 深度遍历数据结构，将带有 __type__ 和 __data__ 的字典还原为对象。
##
## 支持嵌套的字典和数组。
##
## Deep-walks a data structure and restores dictionaries carrying
## [code]__type__[/code] and [code]__data__[/code] back into objects. Nested
## dictionaries and arrays are supported.
static func deep_deserialize(value):
	match typeof(value):
		TYPE_DICTIONARY:
			# 检查是否为序列化的对象表示
			if value.has("__type__") and value.has("__data__"):
				return deserialize(value)
			var new_dict := {}
			for key in value.keys():
				new_dict[key] = deep_deserialize(value[key])
			return new_dict
		TYPE_ARRAY:
			var new_array := []
			for element in value:
				new_array.append(deep_deserialize(element))
			return new_array
		_:
			return value





## 检测对象是否为可序列化实例（字节流版本）。
##
## 需要实现 export_bytes() 和 import_bytes() 两个方法。
##
## Returns whether the object is a serializable instance for the byte-stream
## API. It must implement both [code]export_bytes()[/code] and
## [code]import_bytes()[/code].
static func is_serializable_bytes(obj: Object) -> bool:
	return obj.has_method("export_bytes") and obj.has_method("import_bytes")


## 字节流中的值类型标记。
##
## Value type tags used inside the byte stream.
enum ValueType {
	## 空值。
	##
	## Null.
	NULL_VAL  = 0,
	## 布尔值。
	##
	## Boolean.
	BOOL      = 1,
	## 整数。
	##
	## Integer.
	INT       = 2,
	## 浮点数。
	##
	## Float.
	FLOAT     = 3,
	## 字符串。
	##
	## String.
	STRING    = 4,
	## 二维向量。
	##
	## Vector2.
	VECTOR2   = 5,
	## 字节数组。
	##
	## Packed byte array.
	PACKED_BYTE_ARRAY = 6,
	## 字典。
	##
	## Dictionary.
	DICT      = 18,
	## 数组。
	##
	## Array.
	ARRAY     = 19,
	## 可序列化对象。
	##
	## Serializable object.
	OBJECT    = 20       # 可序列化对象
}

## 将字典序列化为 PackedByteArray（支持嵌套对象）。
##
## Serializes a dictionary into a [PackedByteArray], supporting nested objects.
static func dict_to_bytes(dict: Dictionary) -> PackedByteArray:
	var buf = ByteBuffer.new()
	_write_dict(buf, dict)
	return buf.data

## 从 PackedByteArray 还原为字典（对象也会被还原）。
##
## Restores a dictionary from a [PackedByteArray]; nested objects are restored
## as well.
static func bytes_to_dict(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() == 0:
		return {}
	var buf = ByteBuffer.new(bytes)
	return _read_dict(buf)

# ----- 写入 -----

## 写入字典：键值对数量 + 每个键值对。
##
## Writes a dictionary: the entry count followed by every key/value pair.
static func _write_dict(buf: ByteBuffer, dict: Dictionary) -> void:
	buf.put_int(dict.size())
	for key in dict.keys():
		buf.put_string(key)
		_write_value(buf, dict[key])

## 写入数组：元素数量 + 每个元素。
##
## Writes an array: the element count followed by every element.
static func _write_array(buf: ByteBuffer, arr: Array) -> void:
	buf.put_int(arr.size())
	for elem in arr:
		_write_value(buf, elem)

## 写入任意值：先写类型标记，再写具体数据。
##
## Writes an arbitrary value: the type tag followed by its payload.
static func _write_value(buf: ByteBuffer, value) -> void:
	match typeof(value):
		TYPE_NIL:
			buf.data.append(ValueType.NULL_VAL)
		TYPE_BOOL:
			buf.data.append(ValueType.BOOL)
			buf.put_bool(value)
		TYPE_INT:
			buf.data.append(ValueType.INT)
			buf.put_int(value)
		TYPE_FLOAT:
			buf.data.append(ValueType.FLOAT)
			buf.put_float(value)
		TYPE_STRING:
			buf.data.append(ValueType.STRING)
			buf.put_string(value)
		TYPE_VECTOR2:
			buf.data.append(ValueType.VECTOR2)
			buf.put_vector2(value)
		TYPE_PACKED_BYTE_ARRAY:
			buf.data.append(ValueType.PACKED_BYTE_ARRAY)
			buf.put_packed_byte_array(value)
		TYPE_DICTIONARY:
			# 字典可能已经是 {"__type__":..., "__data__":...}，但仍作为普通字典处理
			buf.data.append(ValueType.DICT)
			_write_dict(buf, value)
		TYPE_ARRAY:
			buf.data.append(ValueType.ARRAY)
			_write_array(buf, value)
		TYPE_OBJECT:
			if is_serializable_bytes(value):
				var script = value.get_script()
				if not script:
					push_error("Factory.dict_to_bytes: 对象无脚本，无法序列化，替换为 null")
					buf.data.append(ValueType.NULL_VAL)
					return
				buf.data.append(ValueType.OBJECT)
				buf.put_string(ResourceUID.path_to_uid(script.resource_path))      # 写入脚本路径
				var data = value.export_bytes()            # 获取对象数据（可能是任意类型）
				_write_value(buf, data)                   # 递归写入数据
			else:
				push_error("Factory.dict_to_bytes: 不可序列化对象，替换为 null")
				buf.data.append(ValueType.NULL_VAL)
		_:
			push_error("Factory.dict_to_bytes: 不支持的类型 " + str(typeof(value)) + "，已替换为 null")
			buf.data.append(ValueType.NULL_VAL)

# ----- 读取 -----

## 读取字典。
##
## Reads a dictionary.
static func _read_dict(buf: ByteBuffer) -> Dictionary:
	var dict := {}
	var count = buf.get_int()
	for i in count:
		var key = buf.get_string()
		dict[key] = _read_value(buf)
	return dict

## 读取数组。
##
## Reads an array.
static func _read_array(buf: ByteBuffer) -> Array:
	var arr := []
	var count = buf.get_int()
	for i in count:
		arr.append(_read_value(buf))
	return arr

## 读取任意值：先读类型标记，再按标记读取数据。
##
## Reads an arbitrary value: the type tag followed by its payload.
static func _read_value(buf: ByteBuffer):
	if buf.is_read_finished():
		return null
	var type_byte = buf.get_byte()
	match type_byte:
		ValueType.NULL_VAL:
			return null
		ValueType.BOOL:
			return buf.get_bool()
		ValueType.INT:
			return buf.get_int()
		ValueType.FLOAT:
			return buf.get_float()
		ValueType.STRING:
			return buf.get_string()
		ValueType.VECTOR2:
			return buf.get_vector2()
		ValueType.PACKED_BYTE_ARRAY:
			return buf.get_packed_byte_array()
		ValueType.DICT:
			return _read_dict(buf)
		ValueType.ARRAY:
			return _read_array(buf)
		ValueType.OBJECT:
			var script_path = buf.get_string()
			if not ResourceLoader.exists(script_path):
				push_error("Factory.bytes_to_dict: 找不到脚本: " + script_path + "，返回 null")
				return null
			var script = load(script_path)
			var instance = script.new()
			if not instance.has_method("import_data"):
				push_error("Factory.bytes_to_dict: 实例未实现 import_data()，返回 null")
				return null
			var data = _read_value(buf)   # 递归读取 export_data 保存的数据
			instance.import_bytes(data)
			return instance
		_:
			push_error("Factory.bytes_to_dict: 未知类型标记 " + str(type_byte) + "，返回 null")
			return null





## 将数组序列化为 PackedByteArray（支持嵌套对象）。
##
## Serializes an array into a [PackedByteArray], supporting nested objects.
static func array_to_bytes(arr: Array) -> PackedByteArray:
	var buf = ByteBuffer.new()
	_write_array(buf, arr)
	return buf.data

## 从 PackedByteArray 还原为数组（对象也会被还原）。
##
## Restores an array from a [PackedByteArray]; nested objects are restored as
## well.
static func bytes_to_array(bytes: PackedByteArray) -> Array:
	if bytes.size() == 0:
		return []
	var buf = ByteBuffer.new(bytes)
	return _read_array(buf)
