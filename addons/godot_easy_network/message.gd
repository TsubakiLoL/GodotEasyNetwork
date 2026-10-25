## 可序列化消息的总类：按脚本 UID 或全局类名在远端还原出具体消息对象。
##
## Base class for serializable messages. A message is restored on the remote
## side from either its script UID or its global class name.
class_name Message


## 脚本标识类型的枚举：决定序列化时用 UID 还是全局类名标识消息脚本。
##
## Script identifier type: whether a message script is identified by its
## resource UID or its global class name when serialized.
enum ScriptIdentifierType {
	## 资源 UID（"uid://..."），通常比全局类名更短。
	##
	## Resource UID ("uid://..."), usually shorter than the global class name.
	UID = 0,
	## 全局类名（class_name），在 UID 缺失或更长时使用。
	##
	## Global class name, used when the UID is missing or longer.
	GLOBAL_NAME = 1
}

## 发送者的网络 ID（peer ID），随消息一起序列化。
##
## 0 表示尚未标注；发送时会由 [method NetworkInstance.put_notice] 自动填写。
## 接收时不会无条件信任该字段：
## - 服务器直连收到客户端的包时，以网络层实际来源覆盖该字段，防止客户端顶替；
## - 客户端收到服务器的包时，信任服务器写入的该字段（服务器已校验 / 转发背书）。
##
## Network ID (peer ID) of the sender, serialized together with the message.
## 0 means unset; [method NetworkInstance.put_notice] fills it when sending.
## The value is not trusted blindly on receive: a server that receives a packet
## directly from a client overwrites it with the real network source, while a
## client trusts the value written by the server, which validates and relays
## messages on its behalf.
var sender: int = 0

## 全局类名到脚本的缓存：StringName(global_name) -> GDScript。
##
## Cache from global class name to script (StringName(global_name) -> GDScript).
static var class_cache :Dictionary[StringName,GDScript]= {}


## 构建 [member class_cache]：遍历全局类列表，缓存所有 Message 的子类。
##
## Builds [member class_cache] by walking the global class list and caching
## every subclass of [Message].
static func initialize_class_cache() -> void:
	class_cache.clear()
	var global_classes: Array[Dictionary] = ProjectSettings.get_global_class_list()

	# 先找到 Message 自身的脚本资源，用于判断继承关系
	var message_script: Script = null
	for entry in global_classes:
		if entry["class"] == "Message":
			message_script = load(entry["path"])
			break
	if not message_script:
		push_error("Message: Message class not found in global class list, cache not built.")
		return

	# 遍历所有全局类，筛选出 Message 的子类
	for entry in global_classes:
		if entry["class"] == "Message":
			continue
		var path: String = entry.path
		if not ResourceLoader.exists(path, "GDScript"):
			continue
		var script: Script = load(path)
		if not script:
			continue

		# 检查继承链是否包含 Message
		var base: Script = script.get_base_script()
		while base:
			if base == message_script:
				class_cache[entry["class"]] = script
				break
			base = base.get_base_script()
	#print(class_cache)

## 导出消息负载，子类按需重写。
##
## Exports the message payload. Subclasses override it as needed.
func export_bytes() -> PackedByteArray:
	return PackedByteArray()

## 导入消息负载，子类按需重写。
##
## Imports the message payload. Subclasses override it as needed.
func import_bytes(data: PackedByteArray):
	pass

## 将消息序列化为字节流：脚本标识（UID 或全局类名）+ 消息负载。
##
## Serializes the message into a byte stream: the script identifier (UID or
## global class name) followed by the message payload.
func to_bytes() -> PackedByteArray:
	var bytes: ByteBuffer = ByteBuffer.new()

	var script: Script = get_script()
	var uid: String = ResourceUID.path_to_uid(script.resource_path)
	var global_name: String = script.get_global_name()

	# 选择更短的字符串存储，并写入对应类型标志
	if global_name.is_empty() or uid.length() <= global_name.length():
		bytes.put_int(ScriptIdentifierType.UID)
		bytes.put_string(uid)
	else:
		bytes.put_int(ScriptIdentifierType.GLOBAL_NAME)
		bytes.put_string(global_name)

	# 写入发送者（0 表示未标注，接收端会按可信规则注入）
	bytes.put_int(sender)

	var sub_bytes: PackedByteArray = export_bytes()
	bytes.put_packed_byte_array(sub_bytes)
	return bytes.data

## 从字节流还原消息对象；无法确定脚本时回退为基类 [Message]。
##
## Restores a message object from a byte stream. Falls back to the base
## [Message] class when the script cannot be determined.
static func from_bytes(data: PackedByteArray) -> Message:
	var bytes: ByteBuffer = ByteBuffer.new(data)
	var script_path: String = ""
	var script: Script = null

	var identifier_type: int = bytes.get_int()
	if identifier_type == ScriptIdentifierType.UID:
		var uid: String = bytes.get_string()
		if not uid.is_empty():
			script_path = uid
	elif identifier_type == ScriptIdentifierType.GLOBAL_NAME:
		var global_name: String = bytes.get_string()
		# 优先使用缓存
		if class_cache.has(global_name):
			script = class_cache.get(global_name)
			pass
		else:
			# 缓存未命中，回退到原始遍历方式
			var global_classes: Array[Dictionary] = ProjectSettings.get_global_class_list()
			for entry: Dictionary in global_classes:
				if entry["class"] == global_name:
					script_path = entry["path"]
					break
	var sender_id: int = bytes.get_int()
	var sub_data: PackedByteArray = bytes.get_packed_byte_array()
	var instance: Message
	if script:
		# 缓存命中，直接使用已加载的脚本创建实例
		instance = script.new()
	elif not script_path.is_empty() and ResourceLoader.exists(script_path, "GDScript"):
		instance = load(script_path).new()
	else:
		instance = Message.new()
	instance.sender = sender_id
	instance.import_bytes(sub_data)
	return instance
