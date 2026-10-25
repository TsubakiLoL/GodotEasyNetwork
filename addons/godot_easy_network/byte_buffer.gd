## 基于 PackedByteArray 的变长编码字节流工具。
##
## 写入为追加（append）模式，所有 put_* 都写到 [member data] 末尾；
## 读取为游标（cursor）模式，[member read_position] 记录下一次读取的下标，
## 读取成功后游标前进，不会通过切片弹出前方字节。
## [member data] 始终是完整的字节数组，读取不会修改它。
##
## Variable-length byte stream helper built on [PackedByteArray]. Writing uses
## append mode: every [code]put_*[/code] appends to [member data]. Reading uses
## cursor mode: [member read_position] points at the next byte and advances after
## a successful read, so no slicing is needed. [member data] always keeps the
## full byte array and reading never modifies it.
class_name ByteBuffer


## 完整的字节数组（写入追加到这里）。
##
## The full byte array. Writes append here.
var data: PackedByteArray = PackedByteArray()
## 读取游标：下一次 get_* / peek_* 从这里开始。
##
## Read cursor: the next [code]get_*[/code] / [code]peek_*[/code] starts here.
var read_position: int = 0

## 创建一个字节缓冲区，可附带初始数据与初始读取位置。
##
## Creates a byte buffer, optionally with initial data and read position.
func _init(initial_data: PackedByteArray = PackedByteArray(), initial_read_position: int = 0):
	data = initial_data
	read_position = clampi(initial_read_position, 0, data.size())

# ----- 游标辅助 -----

## 剩余可读字节数。
##
## Number of bytes left to read.
func remaining() -> int:
	return maxi(data.size() - read_position, 0)

## 是否已读到末尾。
##
## Returns whether the cursor has reached the end.
func is_read_finished() -> bool:
	return read_position >= data.size()

## 可读字节数（[method remaining] 的别名）。
##
## Number of readable bytes, an alias of [method remaining].
func size() -> int:
	return remaining()

## 将读取游标重置到开头（重新解析同一份数据时使用）。
##
## Resets the read cursor to the beginning, e.g. to parse the same data again.
func reset_read_position() -> void:
	read_position = 0

## 清空数据并把游标归零。
##
## Clears the data and resets the cursor.
func clear() -> void:
	data = PackedByteArray()
	read_position = 0

## 跳过 n 个字节，返回实际跳过的字节数（不足时只跳到末尾）。
##
## Skips [param n] bytes and returns how many were actually skipped; when fewer
## remain, it stops at the end.
func skip(n: int) -> int:
	var step := clampi(n, 0, remaining())
	read_position += step
	return step

## 读取一个原始字节（不做任何编码），失败返回 0 且不移动游标。
##
## Reads one raw byte without any decoding. Returns 0 and keeps the cursor in
## place when no byte is left.
func get_byte() -> int:
	if remaining() < 1:
		return 0
	var byte := data[read_position]
	read_position += 1
	return byte

## 窥探下一个原始字节，不移动游标。
##
## Peeks at the next raw byte without moving the cursor.
func peek_byte() -> int:
	if remaining() < 1:
		return 0
	return data[read_position]

# ----- int -----

## 写入一个整数（ZigZag + LEB128 变长编码）。
##
## Writes an integer using ZigZag and variable-length LEB128 encoding.
func put_int(value: int) -> void:
	# ZigZag 编码：将有符号数映射为无符号数
	var zigzag: int = (value << 1) ^ (value >> 63)
	_write_uleb128(zigzag)

## 读取一个整数；数据不足时返回 0 且不移动游标。
##
## Reads an integer. Returns 0 without moving the cursor when data is
## insufficient.
func get_int() -> int:
	var peek = _peek_uleb128()
	if not peek.success:
		return 0
	# 游标前进，跳过已读取的字节
	read_position += peek.bytes_consumed
	# ZigZag 解码
	return _logical_shift_right(peek.value, 1) ^ -(peek.value & 1)

# ----- float -----

## 写入一个单精度浮点数。
##
## Writes a single-precision float.
func put_float(value: float) -> void:
	var fbytes = PackedByteArray()
	fbytes.resize(4)
	fbytes.encode_float(0, value)   # 单精度存储
	data.append_array(fbytes)

## 读取一个单精度浮点数；数据不足时返回 0.0 且不移动游标。
##
## Reads a single-precision float. Returns 0.0 without moving the cursor when
## data is insufficient.
func get_float() -> float:
	if remaining() < 4:
		return 0.0
	var val := data.decode_float(read_position)
	read_position += 4
	return val

# ----- Vector2 -----

## 写入一个 Vector2（两个单精度浮点数）。
##
## Writes a [Vector2] as two single-precision floats.
func put_vector2(vec: Vector2) -> void:
	put_float(vec.x)
	put_float(vec.y)

## 读取一个 Vector2；数据不足时返回 [constant Vector2.ZERO] 且不移动游标。
##
## Reads a [Vector2]. Returns [constant Vector2.ZERO] without moving the cursor
## when data is insufficient.
func get_vector2() -> Vector2:
	if remaining() < 8:
		return Vector2.ZERO
	var x = get_float()
	var y = get_float()
	return Vector2(x, y)

# ----- String -----

## 写入一个字符串：长度（UTF-8 字节数）+ UTF-8 数据。
##
## Writes a string: its length in UTF-8 bytes followed by the UTF-8 data.
func put_string(s: String) -> void:
	var utf8: PackedByteArray = s.to_utf8_buffer()
	put_int(utf8.size())          # 先写入字节长度
	data.append_array(utf8)       # 再写入数据

## 读取一个字符串；数据不足时返回空字符串且不移动游标。
##
## Reads a string. Returns an empty string without moving the cursor when data
## is insufficient.
func get_string() -> String:
	# 先窥探长度，数据不足则不移动游标
	var peek_len = _peek_uleb128()
	if not peek_len.success:
		return ""
	var str_len: int = (peek_len.value >> 1) ^ -(peek_len.value & 1)
	if str_len < 0 or remaining() < peek_len.bytes_consumed + str_len:
		return ""
	# 跳过长度字段，再截取字符串数据
	read_position += peek_len.bytes_consumed
	var str_bytes := data.slice(read_position, read_position + str_len)
	read_position += str_len
	return str_bytes.get_string_from_utf8()

# ----- bool -----

## 写入一个布尔值（1 字节）。
##
## Writes a boolean as one byte.
func put_bool(b: bool) -> void:
	data.append(1 if b else 0)

## 读取一个布尔值；数据不足时返回 false 且不移动游标。
##
## Reads a boolean. Returns false without moving the cursor when data is
## insufficient.
func get_bool() -> bool:
	if remaining() < 1:
		return false
	var val = data[read_position] != 0
	read_position += 1
	return val

## 写入一个 PackedByteArray，先写长度再写数据。
##
## Writes a [PackedByteArray]: its length followed by the data.
func put_packed_byte_array(arr: PackedByteArray) -> void:
	put_int(arr.size())
	data.append_array(arr)

## 读取一个 PackedByteArray；数据不足时返回空数组且不移动游标。
##
## Reads a [PackedByteArray]. Returns an empty array without moving the cursor
## when data is insufficient.
func get_packed_byte_array() -> PackedByteArray:
	var peek_len = _peek_uleb128()
	if not peek_len.success:
		return PackedByteArray()
	var len_val: int = (peek_len.value >> 1) ^ -(peek_len.value & 1)
	if len_val < 0 or remaining() < peek_len.bytes_consumed + len_val:
		return PackedByteArray()
	# 跳过长度字段，再截取数据
	read_position += peek_len.bytes_consumed
	var arr := data.slice(read_position, read_position + len_val)
	read_position += len_val
	return arr

# ----- Object -----

## 写入一个具备 export_bytes / import_bytes 的对象：
##
## 脚本 UID 字符串（[method ResourceUID.path_to_uid] 有 UID 返回 "uid://xxx"，
## 否则原样返回路径）+ 对象自身导出的字节。
##
## Writes an object that implements [code]export_bytes()[/code] and
## [code]import_bytes()[/code]: the script UID string (or the resource path when
## there is no UID) followed by the bytes exported by the object itself.
func put_object(obj: Object) -> void:
	var script: Script = obj.get_script()
	var uid_text: String = ""
	if script != null:
		uid_text = ResourceUID.path_to_uid(script.resource_path)
	put_string(uid_text)
	put_packed_byte_array(obj.export_bytes())

## 读取一个由 [method put_object] 写入的对象。
##
## Reads an object written by [method put_object].
func get_object() -> Object:
	var uid_text := get_string()
	var bytes := get_packed_byte_array()
	if uid_text.is_empty():
		push_warning("ByteBuffer.get_object: 缺少脚本 UID")
		return null
	var script = load(uid_text)        # "uid://..." 或 "res://..." 都能吃
	if script == null:
		push_warning("ByteBuffer.get_object: 无法加载 '%s'" % uid_text)
		return null
	var obj = script.new()
	if obj == null or not obj.has_method("import_bytes"):
		push_warning("ByteBuffer.get_object: '%s' 不能反序列化" % uid_text)
		return null
	obj.import_bytes(bytes)
	return obj


# ----- 内部辅助方法 -----

## 写入无符号 LEB128 变长整数。
##
## Writes an unsigned LEB128 variable-length integer.
func _write_uleb128(val: int) -> void:
	while true:
		var byte = val & 0x7F
		# Treat the signed int as an unsigned 64-bit bit pattern. An arithmetic
		# right shift would keep a negative value at -1 and loop forever.
		val = _logical_shift_right(val, 7)
		if val != 0:
			byte |= 0x80
		data.append(byte)
		if val == 0:
			break

## 将保存在有符号 int 中的无符号 64 位位模式逻辑右移。
##
## Logically shifts an unsigned 64-bit bit pattern stored in a signed int.
func _logical_shift_right(value: int, shift: int) -> int:
	if shift <= 0:
		return value
	if shift >= 64:
		return 0
	var shifted: int = value >> shift
	if value >= 0:
		return shifted
	var remaining_bits: int = 64 - shift
	var mask: int
	if remaining_bits == 63:
		mask = 0x7FFFFFFFFFFFFFFF
	else:
		mask = (1 << remaining_bits) - 1
	return shifted & mask

## 窥探（不移动游标）从 [member read_position] 开始的无符号 LEB128 整数。
##
## 返回字典：{ success: bool, value: int, bytes_consumed: int }。
##
## Peeks at the unsigned LEB128 integer starting at [member read_position]
## without moving the cursor. Returns a dictionary with [code]success[/code],
## [code]value[/code] and [code]bytes_consumed[/code].
func _peek_uleb128() -> Dictionary:
	var value := 0
	var shift := 0
	var bytes_read := 0
	var max_bytes := 10   # 64位整数的最大 LEB128 长度
	var available := remaining()

	for i in range(mini(available, max_bytes)):
		var byte = data[read_position + bytes_read]
		bytes_read += 1
		value |= (byte & 0x7F) << shift
		if (byte & 0x80) == 0:
			return { "success": true, "value": value, "bytes_consumed": bytes_read }
		shift += 7
		if shift >= 64:
			break
	return { "success": false, "value": 0, "bytes_consumed": 0 }


# ---------- Variant 通用读写 ----------
##
## tag 用 [method put_int] 写（LEB128 变长，小 tag 只占 1 字节）。
## 支持的类型：
##   null / bool / int / float / String / Vector2 / PackedByteArray
##   Array / Dictionary（递归）
##   Object（具备 export_bytes / import_bytes 的对象）
##
## Generic Variant read/write. The tag is written with [method put_int]
## (variable-length LEB128, so small tags take one byte). Supported types:
## null, bool, int, float, String, Vector2, PackedByteArray, Array, Dictionary
## (recursive) and Object (implementing export_bytes / import_bytes).
enum VariantTag {
	## 空值。
	##
	## Null.
	TAG_NULL,
	## 布尔值。
	##
	## Boolean.
	TAG_BOOL,
	## 整数。
	##
	## Integer.
	TAG_INT,
	## 浮点数。
	##
	## Float.
	TAG_FLOAT,
	## 字符串。
	##
	## String.
	TAG_STRING,
	## 二维向量。
	##
	## Vector2.
	TAG_VECTOR2,
	## 字节数组。
	##
	## Packed byte array.
	TAG_BYTES,
	## 数组。
	##
	## Array.
	TAG_ARRAY,
	## 字典。
	##
	## Dictionary.
	TAG_DICT,
	## 可序列化对象。
	##
	## Serializable object.
	TAG_OBJECT,
}

## 写入任意 Variant：先写类型标记，再写具体数据。
##
## Writes an arbitrary Variant: the type tag followed by its payload.
func put_variant(v: Variant) -> void:
	if v == null:
		put_int(VariantTag.TAG_NULL)
	elif v is bool:
		put_int(VariantTag.TAG_BOOL); put_bool(v)
	elif v is int:
		put_int(VariantTag.TAG_INT); put_int(v)
	elif v is float:
		put_int(VariantTag.TAG_FLOAT); put_float(v)
	elif v is String:
		put_int(VariantTag.TAG_STRING); put_string(v)
	elif v is Vector2:
		put_int(VariantTag.TAG_VECTOR2); put_vector2(v)
	elif v is PackedByteArray:
		put_int(VariantTag.TAG_BYTES); put_packed_byte_array(v)
	elif v is Array:
		put_int(VariantTag.TAG_ARRAY)
		put_int(v.size())
		for e in v: put_variant(e)
	elif v is Dictionary:
		put_int(VariantTag.TAG_DICT)
		put_int(v.size())
		for k in v.keys():
			put_string(str(k))
			put_variant(v[k])
	elif v is Object and v.has_method("export_bytes") and v.has_method("import_bytes"):
		put_int(VariantTag.TAG_OBJECT)
		put_object(v)
	else:
		push_warning("ByteBuffer.put_variant: 未支持类型 %s" % str(typeof(v)))
		put_int(VariantTag.TAG_NULL)

## 读取一个由 [method put_variant] 写入的 Variant。
##
## Reads a Variant written by [method put_variant].
func get_variant() -> Variant:
	var t := get_int()
	match t:
		VariantTag.TAG_NULL:    return null
		VariantTag.TAG_BOOL:    return get_bool()
		VariantTag.TAG_INT:     return get_int()
		VariantTag.TAG_FLOAT:   return get_float()
		VariantTag.TAG_STRING:  return get_string()
		VariantTag.TAG_VECTOR2: return get_vector2()
		VariantTag.TAG_BYTES:   return get_packed_byte_array()
		VariantTag.TAG_ARRAY:
			var n := get_int()
			var a: Array = []
			for i in n: a.append(get_variant())
			return a
		VariantTag.TAG_DICT:
			var m := get_int()
			var d: Dictionary = {}
			for i in m:
				var k := get_string()
				d[k] = get_variant()
			return d
		VariantTag.TAG_OBJECT:
			return get_object()
	push_warning("ByteBuffer.get_variant: 未知 tag %d" % t)
	return null
