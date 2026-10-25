extends Message

## 同步就绪通知：客户端上报某个同步节点 / 场景已就绪，服务器在全部就绪后
## 广播给所有客户端。
##
## Sync-ready notice: a client reports that a synchronized node or scene is
## ready; once everyone is ready the server broadcasts it to all clients.
class_name NoticeSyncReady

## 就绪对象类型。
##
## Kind of the ready object.
enum Kind {
	## 同步节点（[SyncNode]）。
	##
	## A synchronized node ([SyncNode]).
	NODE,
	## 同步场景（[SyncScene]）。
	##
	## A synchronized scene ([SyncScene]).
	SCENE,
}

## 就绪对象类型。
##
## Kind of the ready object.
var kind: int = Kind.NODE
## 就绪对象的节点路径，各端必须一致。
##
## Node path of the ready object; it must match on every peer.
var node_path: String = ""


func export_bytes() -> PackedByteArray:
	var bytes := ByteBuffer.new()
	bytes.put_int(kind)
	bytes.put_string(node_path)
	return bytes.data


func import_bytes(data: PackedByteArray) -> void:
	var bytes := ByteBuffer.new(data)
	kind = bytes.get_int()
	node_path = bytes.get_string()
