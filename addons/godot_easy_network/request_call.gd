extends Request


## 请求：在所有端批量调用若干节点上的方法。
##
## Request that calls methods on nodes on every peer, optionally in batches.
class_name RequestCall

## 本次请求包含的调用列表。
##
## The calls contained in this request.
var call_array:Array[Call]=[]

## 是否所有调用都允许执行。
##
## Returns whether every contained call is allowed to execute.
func can_execute()->bool:
	return call_array.all(can_call_execute)

## 单个调用是否允许执行。
##
## Returns whether the given call is allowed to execute.
func can_call_execute(call:Call)->bool:
	if call==null:
		return false
	return call.can_execute()


## 依次执行所有调用。
##
## Executes every contained call in order.
func execute():
	for i in call_array:
		i.execute()


## 返回日志友好的字符串。
##
## Returns a debug-friendly string representation.
func _to_string()->String:
	return "RequestCall(calls=%s)" % [str(call_array)]


## 添加一次方法调用。
##
## [param node] 目标节点，序列化时只记录其路径。
## [param func_name] 方法名。
## [param args] 作为调用参数的可变参数。
##
## Adds one method call. [param node] is the target node (only its path is
## serialized), [param func_name] is the method name and [param args] are the
## call arguments.
func add_call(node: Node, func_name: String, ...args) -> void:
	var new_call := Call.new()
	new_call.node_path = node.get_path()
	new_call.func_name = func_name
	new_call.call_args = args    # args 本身就是 Array，直接赋值
	call_array.append(new_call)


## 序列化请求：调用数量 + 每个调用的字节。
##
## Serializes the request: the call count followed by each call's bytes.
func export_bytes() -> PackedByteArray:
	var buffer: ByteBuffer = ByteBuffer.new()
	buffer.put_int(call_array.size())
	for call: Call in call_array:
		buffer.put_packed_byte_array(call.to_bytes())
	return buffer.data

## 反序列化请求。
##
## Deserializes the request.
func import_bytes(data: PackedByteArray) -> void:
	var buffer: ByteBuffer = ByteBuffer.new(data)
	call_array.clear()
	var count: int = buffer.get_int()
	for _i: int in range(count):
		var call_data: PackedByteArray = buffer.get_packed_byte_array()
		var call: Call = Call.from_bytes(call_data)
		call_array.append(call)


## 调用封装类。序列化目前支持 int、float、bool、String、Vector2、
## PackedByteArray 和 null，其余类型会被写成 null。
##
## Call wrapper. Serialization currently supports int, float, bool, String,
## Vector2, PackedByteArray and null; other types are written as null.
class Call:
	## 节点路径。
	##
	## Target node path.
	var node_path:String=""
	## 函数名称。
	##
	## Method name.
	var func_name:String=""
	## 调用参数。
	##
	## Call arguments.
	var call_args:Array=[]
	
	## 参数类型标记枚举。
	##
	## Argument type tags.
	enum ArgsType{
		## 整数。
		##
		## Integer.
		INT,
		## 浮点数。
		##
		## Float.
		FLOAT,
		## 布尔值。
		##
		## Boolean.
		BOOL,
		## 字符串。
		##
		## String.
		STRING,
		## 二维向量。
		##
		## Vector2.
		VECTOR2,
		## 字节数组。
		##
		## Packed byte array.
		PACKED_BYTE_ARRAY,
		## 空值。
		##
		## Null.
		NULL,
	}
	
	
	## 创建一个调用对象（快捷构造）。
	##
	## Creates a call object (shortcut constructor).
	## [param node] 目标节点。
	## [param func_name] 方法名。
	## [param args] 调用参数。
	static func c(node:Node,func_name:String,...args)->Call:
		var new_call:Call=Call.new()
		new_call.node_path=node.get_path()
		new_call.func_name=func_name
		new_call.call_args=args
		return new_call
	## 将调用序列化为字节流。
	##
	## Serializes the call into a byte stream.
	func to_bytes()->PackedByteArray:
		var byte_buffer:ByteBuffer=ByteBuffer.new()
		byte_buffer.put_string(node_path)
		byte_buffer.put_string(func_name)
		byte_buffer.put_int(call_args.size())
		for i in call_args:
			
			if i is int:
				byte_buffer.put_int(ArgsType.INT)
				byte_buffer.put_int(i)
				pass
			elif i is float:
				byte_buffer.put_int(ArgsType.FLOAT)
				byte_buffer.put_float(i)

			elif i is String:
				byte_buffer.put_int(ArgsType.STRING)
				byte_buffer.put_string(i)
			elif i is Vector2:
				byte_buffer.put_int(ArgsType.VECTOR2)
				byte_buffer.put_vector2(i)
			elif i is PackedByteArray:
				byte_buffer.put_int(ArgsType.PACKED_BYTE_ARRAY)
				byte_buffer.put_packed_byte_array(i)
			elif i is bool:
				byte_buffer.put_int(ArgsType.BOOL)
				byte_buffer.put_bool(i)
				pass
			elif i ==null:
				byte_buffer.put_int(ArgsType.NULL)
			else:
				byte_buffer.put_int(ArgsType.NULL)

		return byte_buffer.data
	## 从字节流反序列化出调用对象。
	##
	## Deserializes a call from a byte stream.
	static func from_bytes(bytes: PackedByteArray) -> Call:
		var buf:ByteBuffer = ByteBuffer.new(bytes)
		var new_call:Call = Call.new()
		new_call.node_path = buf.get_string()
		new_call.func_name = buf.get_string()
		var arg_count:int = buf.get_int()
		new_call.call_args = []
		for _i in range(arg_count):
			var arg_type = buf.get_int()  # 类型标记统一按 int 读取
			match arg_type:
				ArgsType.INT:
					new_call.call_args.append(buf.get_int())
				ArgsType.FLOAT:
					new_call.call_args.append(buf.get_float())
				ArgsType.STRING:
					new_call.call_args.append(buf.get_string())
				ArgsType.VECTOR2:
					new_call.call_args.append(buf.get_vector2())
				ArgsType.BOOL:
					new_call.call_args.append(buf.get_bool())
				ArgsType.PACKED_BYTE_ARRAY:
					new_call.call_args.append(buf.get_packed_byte_array())
				ArgsType.NULL, _:
					new_call.call_args.append(null)
		return new_call
	## 严格验证调用是否可执行，可选是否检查参数个数。
	##
	## Strictly validates whether the call can execute, optionally checking the
	## argument count against the target method's signature.
	func can_execute(check_arg_count: bool = false) -> bool:
		var root:Node=Engine.get_main_loop().root
		var target = root.get_node_or_null(node_path)
		if target == null:
			push_error("无法找到节点:%s"%[node_path])
			return false
		if not target.has_method(func_name):
			return false
		if check_arg_count:
			# 获取目标节点的方法列表，找到对应的方法签名
			var method_list: Array = target.get_method_list()
			var matched := false
			for method in method_list:
				if method.name == func_name:
					matched = true
					var args: Array = method.args       # 参数列表
					var defaults: Array = method.default_args   # 默认值列表
					var min_args: int = args.size() - defaults.size()
					# 参数数量必须在 [最小参数数, 总参数数] 区间内
					if call_args.size() < min_args or call_args.size() > args.size():
						return false
					break
			# 如果没找到方法（理论上不会，因为 has_method 已经为 true），认为无效
			if not matched:
				return false
		return true
	## 返回日志友好的字符串。
	##
	## Returns a debug-friendly string representation.
	func _to_string()->String:
		return "Call(node_path=%s, func_name=%s, args=%s)" % [str(node_path), func_name, str(call_args)]

	## 执行调用，默认从场景树的根节点查找目标。
	##
	## Executes the call; the target is looked up from the scene tree root by
	## default.
	## [param p_root] 可选的自定义根节点，留空则使用 Engine.get_main_loop().root
	func execute() -> Variant:
		var root: Node = Engine.get_main_loop().root
		if root == null:
			push_error("Call.execute: 无法获取场景根节点")
			return null
	
		var target: Node = root.get_node_or_null(node_path)
		if target == null:
			push_error("Call.execute: 节点未找到 -> " + node_path)
			return null

		if not target.has_method(func_name):
			push_error("Call.execute: 方法不存在 -> " + func_name)
			return null

		return target.callv(func_name, call_args)
