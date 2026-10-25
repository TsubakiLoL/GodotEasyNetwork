extends Request
## 请求：在所有端释放（[method Node.queue_free]）指定路径的节点。
##
## Request that frees the node at the given path on every peer.
class_name RequestFreeNode

## 目标节点路径，各端必须一致。
##
## Target node path; it must be identical on every peer.
var node_path:NodePath


## 返回日志友好的字符串。
##
## Returns a debug-friendly string representation.
func _to_string()->String:
	return "RequestFreeNode(node_path=%s)" % [str(node_path)]


## 执行请求：若节点存在且已在场景树中，则将其释放。
##
## Executes the request: frees the node when it exists and is inside the tree.
func execute():
	var root: Window = Engine.get_main_loop().root
	var node: Node = root.get_node_or_null(node_path)
	if node!=null and node.is_inside_tree():
		node.queue_free()

## 以字典形式导出请求数据。
##
## Exports the request data as a dictionary.
func export_data()->Dictionary:
	return {
		"node_path":str(node_path)
	}

## 从字典导入请求数据。
##
## Imports the request data from a dictionary.
func import_data(data:Dictionary):
	node_path=NodePath(str(data.get("node_path", "")))
	pass


## 序列化请求（仅节点路径）。
##
## Serializes the request (node path only).
func export_bytes()->PackedByteArray:
	var bytes:ByteBuffer=ByteBuffer.new()
	bytes.put_string(str(node_path))
	return bytes.data
## 反序列化请求。
##
## Deserializes the request.
func import_bytes(data:PackedByteArray):
	var bytes:ByteBuffer=ByteBuffer.new(data)
	node_path=NodePath(bytes.get_string())
