extends Request

## 请求：在指定父节点下实例化并同步一个场景，可携带初始化属性。
##
## Request that instantiates and syncs a scene under the given parent node,
## optionally carrying initial properties.
class_name RequestInstantiateScene

## 要实例化的场景路径。
##
## Path of the scene to instantiate.
var scene_path: String
## 实例化到的父节点路径，各端必须一致。
##
## Path of the parent node the scene is added to; it must match on every peer.
var parent: NodePath
## 实例化后的节点名称。
##
## Name of the instantiated node.
var node_name: String
## 初始化属性字典，创建后逐项 set 到节点上。
##
## Dictionary of initial properties, applied to the node after instantiation.
var init_value: Dictionary = {}
## 实例化出的场景所属玩家的网络 ID。
##
## Network ID of the player owning the instantiated scene.
var belong_to:int

## 获取执行完毕的节点，如果还未执行完则返回 [code]null[/code]。
##
## Returns the instantiated node, or [code]null[/code] if it is not ready yet.
func get_instantiate_node()->Node:
	var root: Window = Engine.get_main_loop().root
	var node: Node = root.get_node_or_null(parent)
	if node == null:
		return null
	var child:Node=node.get_node_or_null(node_name)
	return child


## 执行请求：实例化并同步场景，设置名称与初始属性后加入父节点。
##
## Executes the request: instantiates the synced scene, applies its name and
## initial properties, then adds it to the parent.
func execute():
	var root: Window = Engine.get_main_loop().root
	var node: Node = root.get_node_or_null(parent)
	if node == null:
		return
	var scene_instantiate = SyncNode.instantiate_sync_scene(scene_path,belong_to)
	if scene_instantiate==null:
		return
	scene_instantiate.name = node_name
	for i in init_value.keys():
		scene_instantiate.set(i, init_value[i])
	node.add_child(scene_instantiate)

## 以字典形式导出请求数据。
##
## Exports the request data as a dictionary.
func export_data() -> Dictionary:
	var data = {
		"scene_path": scene_path,
		"parent": str(parent),
		"node_name": node_name,
		"belong_to":belong_to,
		"init_value": Factory.deep_serialize(init_value)
	}
	return data

## 从字典导入请求数据。
##
## Imports the request data from a dictionary.
func import_data(data: Dictionary) -> void:
	scene_path = data.get("scene_path", "")
	parent = NodePath(str(data.get("parent", "")))
	node_name = data.get("node_name", "")
	belong_to=data.get("belong_to",0)
	init_value = Factory.deep_deserialize(data.get("init_value", {}))

## 序列化请求。
##
## Serializes the request.
func export_bytes()->PackedByteArray:
	var bytes:ByteBuffer=ByteBuffer.new()
	bytes.put_string(str(ResourceUID.path_to_uid(scene_path)))
	bytes.put_string(str(parent))
	bytes.put_string(node_name)
	bytes.put_int(belong_to)
	var init_data:PackedByteArray=Factory.dict_to_bytes(init_value)
	bytes.put_packed_byte_array(init_data)
	return bytes.data
## 反序列化请求。
##
## Deserializes the request.
func import_bytes(data:PackedByteArray):
	var bytes:ByteBuffer=ByteBuffer.new(data)
	scene_path=bytes.get_string()
	parent=NodePath(bytes.get_string())
	node_name=bytes.get_string()
	belong_to=bytes.get_int()
	init_value=Factory.bytes_to_dict(bytes.get_packed_byte_array())




## 返回日志友好的字符串。
##
## Returns a debug-friendly string representation.
func _to_string() -> String:
	
	return str(export_data())
