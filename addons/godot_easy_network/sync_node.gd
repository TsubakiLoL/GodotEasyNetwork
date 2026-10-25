## 同步节点抽象基类：按服务器/客户端与受控/非受控四个维度分发回调。
##
## Abstract base class for synchronized nodes. It dispatches callbacks along
## four dimensions: server/client and controlled/uncontrolled.
@abstract
extends Node
class_name SyncNode


## 是否已完成同步就绪。
##
## Whether the node has finished the sync handshake.
var is_ready:bool=false

## 节点同步就绪时发出。
##
## Emitted when the node becomes synchronized.
signal sync_ready
## 本地受控节点同步就绪时发出。
##
## Emitted when a locally controlled node becomes synchronized.
signal controlled_sync_ready
## 非本地受控节点同步就绪时发出。
##
## Emitted when an uncontrolled node becomes synchronized.
signal uncontrolled_sync_ready
## 服务器端专用就绪信号。
##
## Emitted on the server side when the node becomes synchronized.
signal server_sync_ready
## 客户端专用就绪信号。
##
## Emitted on the client side when the node becomes synchronized.
signal client_sync_ready

## 受控单位的 process 回调列表。
##
## Process callbacks for locally controlled nodes.
@export var controlled_process_callbacks: Array[Callable] = []
## 受控单位的 physics_process 回调列表。
##
## Physics-process callbacks for locally controlled nodes.
@export var controlled_physics_process_callbacks: Array[Callable] = []
## 非受控单位的 process 回调列表。
##
## Process callbacks for uncontrolled nodes.
@export var uncontrolled_process_callbacks: Array[Callable] = []
## 非受控单位的 physics_process 回调列表。
##
## Physics-process callbacks for uncontrolled nodes.
@export var uncontrolled_physics_process_callbacks: Array[Callable] = []

## 服务器端的 process 回调列表。
##
## Server-side process callbacks.
@export var server_process_callbacks: Array[Callable] = []
## 服务器端的 physics_process 回调列表。
##
## Server-side physics-process callbacks.
@export var server_physics_process_callbacks: Array[Callable] = []
## 客户端的 process 回调列表。
##
## Client-side process callbacks.
@export var client_process_callbacks: Array[Callable] = []
## 客户端的 physics_process 回调列表。
##
## Client-side physics-process callbacks.
@export var client_physics_process_callbacks: Array[Callable] = []


## 根据场景路径实例化场景，查找所有 SyncNode 并设置所属 ID，返回根节点（尚未加入场景树）。
##
## Instantiates the scene at [param scene_path], finds every [SyncNode] and sets
## its owner ID, then returns the root node. The node is not added to the scene
## tree yet.
static func instantiate_sync_scene(scene_path: String, belong_to: int) -> Node:
	var packed_scene: PackedScene = load(scene_path)
	if packed_scene == null:
		push_error("SyncNode: 无法加载场景，路径: " + scene_path)
		return null
	var root := packed_scene.instantiate()
	# 递归查找所有类型为 SyncNode 的节点
	var child=root.get_node_or_null("SyncNode")
	#利用根节点的固定路径作为快速搜寻
	if child is SyncNode:
		child.belong_to=belong_to
	else:
		var sync_nodes: Array[Node] = root.find_children("*", "SyncNode", true, false)
		for node in sync_nodes:
			if node is SyncNode:
				node.belong_to = belong_to
	return root


## 当前是否运行在服务器端。
##
## Returns whether this peer is the server.
func is_server() -> bool:
	return get_network().is_server()


## 单位模式枚举，用于区分服务器/客户端以及是否由本地控制。
##
## Unit mode: distinguishes server/client and whether the unit is locally
## controlled.
enum UnitMode {
	## 服务器端，且属于本地玩家。
	##
	## Server side, owned by the local player.
	SERVER_CONTROLLED,
	## 服务器端，不属于本地玩家。
	##
	## Server side, not owned by the local player.
	SERVER_UNCONTROLLED,
	## 客户端，且属于本地玩家。
	##
	## Client side, owned by the local player.
	CLIENT_CONTROLLED,
	## 客户端，不属于本地玩家。
	##
	## Client side, not owned by the local player.
	CLIENT_UNCONTROLLED
}

## 单位所属玩家的网络 ID，0 表示无归属或服务器。
##
## Network ID of the player owning this unit; 0 means unowned or the server.
var belong_to: int = 0

## 尚未上报就绪的客户端 ID 列表（仅服务器端使用）。
##
## Client IDs that have not reported readiness yet (server side only).
var server_clients: Array[int] = []

## 节点加入场景树后的初始化：按网络角色决定等待客户端就绪还是直接就绪。
##
## Initializes the node when it enters the tree: either waits for clients to
## report readiness or becomes ready immediately, depending on the network role.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if get_network().is_server():
		server_clients = get_network().get_peer_array_except_server()
		if server_clients.is_empty():
			# 没有客户端，服务器自己直接就绪
			_sync_ready()
			set_process(true)
			set_physics_process(true)
	else:
		_send_sync_ready()

## 客户端发送同步就绪通知给服务器。
##
## Client side: sends the sync-ready notice to the server.
func _send_sync_ready() -> void:
	var notice := NoticeSyncReady.new()
	notice.kind = NoticeSyncReady.Kind.NODE
	notice.node_path = str(get_path())
	get_network().put_notice(NetworkInstance.SERVER_ID, notice)

## 服务器广播节点已就绪通知。
##
## Server side: broadcasts the node-ready notice to every client.
func _broadcast_sync_ready() -> void:
	var notice := NoticeSyncReady.new()
	notice.kind = NoticeSyncReady.Kind.NODE
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
	if kind != NoticeSyncReady.Kind.NODE:
		return
	if get_network().is_server():
		## 仅接受已验证 peer 的就绪通知
		if not get_network().is_peer_validated(from_peer):
			return
		server_clients.erase(from_peer)
		if server_clients.is_empty():
			_sync_ready()
			set_process(true)
			set_physics_process(true)
			is_ready = true
			_broadcast_sync_ready()
	else:
		if from_peer != NetworkInstance.SERVER_ID:
			return
		_sync_ready()
		set_process(true)
		set_physics_process(true)
		is_ready = true


## 获取当前单位所处的模式（组合维度）。
##
## Returns the current unit mode (combined dimensions).
func get_unit_mode() -> UnitMode:
	if belong_to == get_network().get_self_id():
		if get_network().is_server():
			return UnitMode.SERVER_CONTROLLED
		else:
			return UnitMode.CLIENT_CONTROLLED
	else:
		if get_network().is_server():
			return UnitMode.SERVER_UNCONTROLLED
		else:
			return UnitMode.CLIENT_UNCONTROLLED


## 当前单位是否被本机拥有。
##
## Returns whether this unit is owned by the local peer.
func own() -> bool:
	return belong_to == get_network().get_self_id()


## 节点就绪时调用，根据网络角色和控制权分发到各维度的 _ready 回调。
##
## Called when the node becomes ready; dispatches to the per-dimension readiness
## callbacks according to the network role and control ownership.
func _sync_ready() -> void:
	# 单维度回调
	if get_network().is_server():
		_server_ready()
	else:
		_client_ready()

	if belong_to == get_network().get_self_id():
		_controlled_ready()
	else:
		_uncontrolled_ready()


	# 最后发射全局就绪信号
	sync_ready.emit()


## 每帧更新时调用，根据网络角色和控制权分发到各维度的 _process 回调。
##
## Called every frame; dispatches to the per-dimension process callbacks
## according to the network role and control ownership.
func _process(delta: float) -> void:
	if get_network().is_server():
		_server_process(delta)
	else:
		_client_process(delta)

	if belong_to == get_network().get_self_id():
		_controlled_process(delta)
	else:
		_uncontrolled_process(delta)



## 物理帧更新时调用，根据网络角色和控制权分发到各维度的 _physics_process 回调。
##
## Called every physics frame; dispatches to the per-dimension physics-process
## callbacks according to the network role and control ownership.
func _physics_process(delta: float) -> void:
	if get_network().is_server():
		_server_physics_process(delta)
	else:
		_client_physics_process(delta)

	if belong_to == get_network().get_self_id():
		_controlled_physics_process(delta)
	else:
		_uncontrolled_physics_process(delta)



# ------ 单维度回调 (Server/Client/Controlled/Uncontrolled) ------
## 服务器端专用：节点就绪时调用（仅服务器执行）。
##
## Server-only: called when the node becomes ready.
func _server_ready() -> void:
	server_sync_ready.emit()

## 服务器端专用：每帧更新（仅服务器执行）。
##
## Server-only: called every frame.
func _server_process(delta: float) -> void:
	for callable in server_process_callbacks:
		if callable.is_valid():
			callable.call(delta)

## 服务器端专用：物理帧更新（仅服务器执行）。
##
## Server-only: called every physics frame.
func _server_physics_process(delta: float) -> void:
	for callable in server_physics_process_callbacks:
		if callable.is_valid():
			callable.call(delta)


## 客户端专用：节点就绪时调用（仅客户端执行）。
##
## Client-only: called when the node becomes ready.
func _client_ready() -> void:
	client_sync_ready.emit()

## 客户端专用：每帧更新（仅客户端执行）。
##
## Client-only: called every frame.
func _client_process(delta: float) -> void:
	for callable in client_process_callbacks:
		if callable.is_valid():
			callable.call(delta)

## 客户端专用：物理帧更新（仅客户端执行）。
##
## Client-only: called every physics frame.
func _client_physics_process(delta: float) -> void:
	for callable in client_physics_process_callbacks:
		if callable.is_valid():
			callable.call(delta)


## 本地控制权专用：节点就绪时调用（仅当 belong_to == 本地玩家时执行）。
##
## Local-control only: called when the node becomes ready (only when
## [member belong_to] equals the local peer ID).
func _controlled_ready() -> void:
	controlled_sync_ready.emit()

## 本地控制权专用：每帧更新（仅当 belong_to == 本地玩家时执行）。
##
## Local-control only: called every frame (only when [member belong_to] equals
## the local peer ID).
func _controlled_process(delta: float) -> void:
	for callable in controlled_process_callbacks:
		if callable.is_valid():
			callable.call(delta)

## 本地控制权专用：物理帧更新（仅当 belong_to == 本地玩家时执行）。
##
## Local-control only: called every physics frame (only when
## [member belong_to] equals the local peer ID).
func _controlled_physics_process(delta: float) -> void:
	for callable in controlled_physics_process_callbacks:
		if callable.is_valid():
			callable.call(delta)


## 非本地控制权专用：节点就绪时调用（仅当 belong_to != 本地玩家时执行）。
##
## Non-local-control only: called when the node becomes ready (only when
## [member belong_to] differs from the local peer ID).
func _uncontrolled_ready() -> void:
	uncontrolled_sync_ready.emit()

## 非本地控制权专用：每帧更新（仅当 belong_to != 本地玩家时执行）。
##
## Non-local-control only: called every frame (only when [member belong_to]
## differs from the local peer ID).
func _uncontrolled_process(delta: float) -> void:
	for callable in uncontrolled_process_callbacks:
		if callable.is_valid():
			callable.call(delta)

## 非本地控制权专用：物理帧更新（仅当 belong_to != 本地玩家时执行）。
##
## Non-local-control only: called every physics frame (only when
## [member belong_to] differs from the local peer ID).
func _uncontrolled_physics_process(delta: float) -> void:
	for callable in uncontrolled_physics_process_callbacks:
		if callable.is_valid():
			callable.call(delta)


# ------ 回调数组的增删方法 ------
## 添加服务器 process 回调。
##
## Adds a server-side process callback.
func add_server_process_callback(callback: Callable) -> void:
	server_process_callbacks.append(callback)

## 移除服务器 process 回调。
##
## Removes a server-side process callback.
func remove_server_process_callback(callback: Callable) -> void:
	server_process_callbacks.erase(callback)

## 添加服务器 physics_process 回调。
##
## Adds a server-side physics-process callback.
func add_server_physics_process_callback(callback: Callable) -> void:
	server_physics_process_callbacks.append(callback)

## 移除服务器 physics_process 回调。
##
## Removes a server-side physics-process callback.
func remove_server_physics_process_callback(callback: Callable) -> void:
	server_physics_process_callbacks.erase(callback)


## 添加客户端 process 回调。
##
## Adds a client-side process callback.
func add_client_process_callback(callback: Callable) -> void:
	client_process_callbacks.append(callback)

## 移除客户端 process 回调。
##
## Removes a client-side process callback.
func remove_client_process_callback(callback: Callable) -> void:
	client_process_callbacks.erase(callback)

## 添加客户端 physics_process 回调。
##
## Adds a client-side physics-process callback.
func add_client_physics_process_callback(callback: Callable) -> void:
	client_physics_process_callbacks.append(callback)

## 移除客户端 physics_process 回调。
##
## Removes a client-side physics-process callback.
func remove_client_physics_process_callback(callback: Callable) -> void:
	client_physics_process_callbacks.erase(callback)


## 添加受控单位 process 回调。
##
## Adds a controlled-unit process callback.
func add_controlled_process_callback(callback: Callable) -> void:
	controlled_process_callbacks.append(callback)

## 移除受控单位 process 回调。
##
## Removes a controlled-unit process callback.
func remove_controlled_process_callback(callback: Callable) -> void:
	controlled_process_callbacks.erase(callback)

## 添加受控单位 physics_process 回调。
##
## Adds a controlled-unit physics-process callback.
func add_controlled_physics_process_callback(callback: Callable) -> void:
	controlled_physics_process_callbacks.append(callback)

## 移除受控单位 physics_process 回调。
##
## Removes a controlled-unit physics-process callback.
func remove_controlled_physics_process_callback(callback: Callable) -> void:
	controlled_physics_process_callbacks.erase(callback)


## 添加非受控单位 process 回调。
##
## Adds an uncontrolled-unit process callback.
func add_uncontrolled_process_callback(callback: Callable) -> void:
	uncontrolled_process_callbacks.append(callback)

## 移除非受控单位 process 回调。
##
## Removes an uncontrolled-unit process callback.
func remove_uncontrolled_process_callback(callback: Callable) -> void:
	uncontrolled_process_callbacks.erase(callback)

## 添加非受控单位 physics_process 回调。
##
## Adds an uncontrolled-unit physics-process callback.
func add_uncontrolled_physics_process_callback(callback: Callable) -> void:
	uncontrolled_physics_process_callbacks.append(callback)

## 移除非受控单位 physics_process 回调。
##
## Removes an uncontrolled-unit physics-process callback.
func remove_uncontrolled_physics_process_callback(callback: Callable) -> void:
	uncontrolled_physics_process_callbacks.erase(callback)


## 抽象方法：返回当前节点所属的网络实例。
##
## Abstract method: returns the network instance this node belongs to.
@abstract func get_network()->NetworkInstance
