## 同步场景抽象基类：负责场景切换前的多端就绪同步。
##
## Abstract base class for synchronized scenes. It performs the multi-peer
## readiness handshake before a scene switch.
@abstract
extends Node
class_name SyncScene

## 场景同步完成时发出。
##
## Emitted when the scene sync finishes.
signal sync_finished
## 是否已完成同步就绪。
##
## Whether the scene has finished the sync handshake.
var is_ready:bool=false

## 尚未上报就绪的客户端 ID 列表（仅服务器端使用）。
##
## Client IDs that have not reported readiness yet (server side only).
var server_clients:Array[int]=[]

## 节点加入场景树后的初始化：按网络角色决定等待客户端就绪还是直接就绪。
##
## Initializes the node when it enters the tree: either waits for clients to
## report readiness or becomes ready immediately, depending on the network role.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if get_network().is_server():
		server_clients=get_network().get_peer_array_except_server()
		if server_clients.is_empty():
			sync_ready()
			is_ready=true
			sync_finished.emit()
			set_process(true)
			set_physics_process(true)
	else:
		_send_sync_ready()

## 客户端发送同步就绪通知给服务器。
##
## Client side: sends the sync-ready notice to the server.
func _send_sync_ready() -> void:
	var notice := NoticeSyncReady.new()
	notice.kind = NoticeSyncReady.Kind.SCENE
	notice.node_path = str(get_path())
	get_network().put_notice(NetworkInstance.SERVER_ID, notice)

## 服务器广播场景已就绪通知。
##
## Server side: broadcasts the scene-ready notice to every client.
func _broadcast_sync_ready() -> void:
	var notice := NoticeSyncReady.new()
	notice.kind = NoticeSyncReady.Kind.SCENE
	notice.node_path = str(get_path())
	get_network().put_notice_to_players(notice)

## 处理同步就绪通知（由 [NetworkInstance] 按节点路径派发）。
##
## [param from_peer] 为可信注入的发送者：服务器侧是上报就绪的客户端，
## 客户端侧是服务器。
##
## Handles a sync-ready notice dispatched by [NetworkInstance] through the node
## path. [param from_peer] is the trusted sender: the reporting client on the
## server side, or the server on the client side.
func handle_sync_ready(kind: int, from_peer: int) -> void:
	if kind != NoticeSyncReady.Kind.SCENE:
		return
	if get_network().is_server():
		## 仅接受已验证 peer 的就绪通知
		if not get_network().is_peer_validated(from_peer):
			return
		server_clients.erase(from_peer)
		if server_clients.is_empty():
			sync_ready()
			is_ready = true
			sync_finished.emit()
			set_process(true)
			set_physics_process(true)
			_broadcast_sync_ready()
	else:
		if from_peer != NetworkInstance.SERVER_ID:
			return
		sync_ready()
		is_ready = true
		sync_finished.emit()
		set_process(true)
		set_physics_process(true)
	
## 子类重写：场景同步就绪时的自定义处理。
##
## Overridden by subclasses: custom handling when the scene becomes ready.
func sync_ready()->void:
	
	pass


## 抽象方法：返回当前场景所属的网络实例。
##
## Abstract method: returns the network instance this scene belongs to.
@abstract func get_network()->NetworkInstance
