extends Node

## 网络实例基础类：自动加载为 [code]Network[/code]，负责建房 / 加入、用户信息、
## 通知分发，以及服务器端的请求队列。
##
## Base class of a network instance, auto-loaded as [code]Network[/code]. It
## handles room creation/joining, user information, notice dispatch and the
## server-side request queue.
class_name NetworkInstance

## 服务器端的固定 ID（始终为 1）。
##
## Fixed ID of the server, always 1.
const SERVER_ID = 1
## 服务器的默认端口。
##
## Default server port.
const DEFAULT_PORT=9939

## 创建房间的请求完成时发出，参数表示是否成功。
##
## Emitted when a room creation request finishes; the parameter tells whether it
## succeeded.
signal create_room_finished(success: bool)
## 加入房间的请求完成时发出，参数表示是否成功。
##
## Emitted when a room joining request finishes; the parameter tells whether it
## succeeded.
signal join_room_finished(success: bool)
## 房间信息更新时发出，携带房间内所有用户的信息。
##
## Emitted when the room data changes, carrying the information of every user in
## the room.
signal room_data_update(room_data: Dictionary[int, UserInformation])

## 作为客户端时，服务端销毁了房间时发出。
##
## Emitted on a client when the server destroys the room.
signal client_room_destroy()

## 新用户加入房间时发出，携带用户 ID 和用户信息。
##
## Emitted when a new user joins the room, carrying the peer ID and user
## information.
signal user_join(peer_id: int, mes: UserInformation)
## 用户离开房间时发出，携带用户 ID 和用户信息。
##
## Emitted when a user leaves the room, carrying the peer ID and user
## information.
signal user_left(peer_id: int, mes: UserInformation)
## 用户信息更新时发出，携带用户 ID 和用户信息。
##
## Emitted when a user's information is updated, carrying the peer ID and user
## information.
signal user_update(peer_id: int, mes: UserInformation)

## 当本端获取到通知时发出。
##
## Emitted when this peer receives a notice.
signal notice_get(peer_id:int,notice:Message)

## 请求结束之后发出。
##
## Emitted after a request finishes.
signal request_finished(request:Request)

## 是否拒绝新的连接（服务端有用），开启后新连接会被立即断开。
##
## Whether new connections are refused (server side). When enabled, new
## connections are disconnected immediately.
var refuse_new_connections:bool=false

## 打印带有自身网络 ID 的信息。
##
## Prints a message prefixed with this peer's network ID.
func p(message:String):
	print(str(get_self_id())+":"+message)
	pass


## 获取底层使用的多媒体 API（SceneMultiplayer）。
##
## Returns the underlying multiplayer API ([SceneMultiplayer]).
func get_multiplayer_api()->SceneMultiplayer:
	return multiplayer

## 将通知发送给某个用户；peer ID 为 0 时执行广播。
##
## 发送前若 [member Message.sender] 尚未标注（为 0），自动填入本端 ID；
## 服务端转发时可以先显式写入原作者 ID，客户端会信任服务器写入的值。
##
## Sends a notice to one peer, or broadcasts when [param peer_id] is 0. Before
## sending, an unset [member Message.sender] (0) is filled with this peer's ID;
## the server may set the original author ID explicitly when relaying, and
## clients trust the value written by the server.
func put_notice(peer_id:int,notice:Message):
	if not is_ready():
		push_error("当前网络未能连接")
		return
	if notice.sender == 0:
		notice.sender = get_self_id()
	get_multiplayer_api().send_bytes(Compress.com(notice.to_bytes()),peer_id)

## 向房间内所有已验证玩家广播通知（不含服务器自己，也不会发给仍在加入中的 peer）。
##
## Broadcasts a notice to every validated player in the room. The server itself
## and peers that are still joining are excluded.
func put_notice_to_players(notice: Message) -> void:
	for peer_id in get_peer_array_except_server():
		put_notice(peer_id, notice)

## 注入可信发送者。
##
## 规则：
## - 服务器直接收到客户端的包时，以网络层实际来源覆盖 [member Message.sender]，
##   客户端伪造的值不会被采用；
## - 客户端收到服务器（[constant SERVER_ID]）发来的包时，信任包内由服务器
##   写入的发送者；若包内未标注则回退为服务器 ID；
## - 其余直连来源一律以网络层实际来源为准。
##
## Injects the trusted sender. When the server receives a packet directly from a
## client, the real network source overwrites [member Message.sender], so a
## forged value is never accepted. A client receiving a packet from the server
## ([constant SERVER_ID]) trusts the sender written by the server, falling back
## to the server ID when it is unset. Any other direct source is always taken
## from the network layer.
func _inject_trusted_sender(message: Message, from_peer: int) -> void:
	if from_peer == SERVER_ID and not is_server():
		if message.sender == 0:
			message.sender = SERVER_ID
		return
	message.sender = from_peer

## 处理来自其它端的通知。
##
## Handles a notice received from another peer.
## [param from_peer] 来源 peer 的 ID。
##
## [param from_peer] is the sender peer ID, [param notice] is the notice itself.
func get_notice(from_peer:int,notice:Message):
	if is_server():
		## 注册通知：来源 peer 可能尚未验证，身份以可信注入的 sender 为准
		if notice is NoticeSyncInformation:
			_apply_information(notice.sender, notice.information)
			return
		## 其余通知只接受已经完成注册（已验证）的 peer
		if not is_peer_validated(from_peer):
			return
		if notice is NoticeExecuteFinished:
			if not request_finished_id_cache.has(from_peer):
				request_finished_id_cache.append(from_peer)
				_try_advance_queue()
		elif notice is NoticePushRequest:
			if notice.request!=null:
				server_push_request(notice.request)
			pass
		elif notice is NoticePushRequestImmediately:
			if notice.request!=null:
				push_request_immediately(notice.request)
		elif notice is NoticeSyncReady:
			_dispatch_sync_ready(notice)
	else:
		if notice is NoticeServerAccept:
			##收到服务器的合法确认包后才进入已加入状态并同步自身信息
			if from_peer!=SERVER_ID:
				return
			_on_server_accept()
		elif notice is NoticeUserChanged:
			if from_peer!=SERVER_ID:
				return
			_apply_user_changed(notice)
		elif notice is NoticeRoomInformation:
			if from_peer!=SERVER_ID:
				return
			room_user_information = dic_to_information(notice.information)
			room_data_update.emit(room_user_information)
		elif notice is NoticeSyncReady:
			if from_peer!=SERVER_ID:
				return
			_dispatch_sync_ready(notice)
		elif notice is NoticeExecRequest:
			if from_peer!=SERVER_ID or not is_ready():
				return
			## 统一走 execute_request：过滤器 -> request.can_execute() -> 执行
			execute_request(notice.request)
			put_notice(SERVER_ID,NoticeExecuteFinished.new())
		elif notice is NoticeExecRequestImmediately:
			if from_peer!=SERVER_ID or not is_ready():
				return
			execute_request(notice.request)
			pass

## 当获取到其它端发来的数据包时触发。
##
## Called when a packet arrives from another peer.
func _peer_packet(from_peer:int,data:PackedByteArray):
	##接收端校验：服务器只接受已连接 peer 的包（注册阶段的 peer 尚未验证，
	##具体通知在 get_notice 中按类型再校验），客户端只接受服务器发来的包
	if is_server():
		if not has_peer(from_peer):
			return
	elif from_peer != SERVER_ID:
		return
	var buffer:PackedByteArray=Compress.decom(data)
	var mes:Message=Message.from_bytes(buffer)
	## 按来源规则注入可信发送者，不直接信任包内字段
	_inject_trusted_sender(mes, from_peer)
	get_notice(from_peer,mes)
	notice_get.emit(from_peer,mes)

## 加入房间的超时计时器引用。
##
## Timeout timer reference for joining a room.
var join_room_timeout_timer:Timer

## 节点就绪时初始化类缓存、计时器与网络包回调。
##
## Initializes the class cache, the timer and the packet callbacks when the node
## becomes ready.
func _ready() -> void:
	
	Message.initialize_class_cache()
	set_up_join_room_timer()
	user_left.connect(_on_user_left_process)
	var api:SceneMultiplayer=get_tree().get_multiplayer()
	api.peer_packet.connect(_peer_packet)





## ENetMultiplayerPeer 实例，用于网络通信。
##
## The [ENetMultiplayerPeer] instance used for network communication.
var peer: ENetMultiplayerPeer
## 尚未同步名称信息的客户端 ID 列表（已连接但还未发送用户信息）。
##
## Client IDs that are connected but have not synced their name information yet.
var peer_without_name: Array[int]

## 房间内所有用户的详细信息，键为用户 ID，值为 UserInformation 对象。
##
## Detailed information of every user in the room, keyed by peer ID.
var room_user_information: Dictionary[int, UserInformation] = {}


## 将用户信息字典（值为 UserInformation 对象）转换为可网络传输的字典（值为 Dictionary）。
##
## Converts a user-information dictionary (values are [UserInformation]) into a
## network-transferable dictionary (values are [Dictionary]).
func information_to_dic(information: Dictionary[int, UserInformation]) -> Dictionary[int, Dictionary]:
	var new_dic: Dictionary[int, Dictionary]
	for i in information.keys():
		new_dic[i] = information[i].export_data()
	return new_dic

## 将网络传输的用户信息字典（值为 Dictionary）还原为 UserInformation 对象字典。
##
## Restores a network-transferable dictionary into a dictionary of
## [UserInformation] objects.
func dic_to_information(dic: Dictionary[int, Dictionary]) -> Dictionary[int, UserInformation]:
	var new_dic: Dictionary[int, UserInformation]
	for i in dic.keys():
		var new_information: UserInformation = UserInformation.new()
		new_information.import_data(dic[i])
		new_dic[i] = new_information
	return new_dic

## 当前网络模式（空闲 / 服务器 / 加入中 / 已加入）。
##
## The current network mode (idle / server / joining / joined).
var network_mode: NetworkMode = NetworkMode.FREE

## 网络模式枚举。
##
## Network mode.
enum NetworkMode {
	## 空闲，未加入任何网络。
	##
	## Idle; not part of any network.
	FREE,
	## 作为服务器运行。
	##
	## Running as the server.
	SERVER,
	## 正在尝试加入房间。
	##
	## Trying to join a room.
	CLIENT_JOINING,
	## 已成功加入房间。
	##
	## Successfully joined a room.
	CLIENT_JOINED
}

## 网络通讯是否可用（处于服务器模式或已加入客户端模式）。
##
## Returns whether networking is usable, i.e. running as the server or as a
## joined client.
func is_ready() -> bool:
	return network_mode == NetworkMode.SERVER or network_mode == NetworkMode.CLIENT_JOINED

## 请求更改自身的用户信息。
##
## Requests changing this peer's own user information.
func request_change_self_information(information:UserInformation):
	if not is_ready():
		return
	if is_server():
		room_user_information[SERVER_ID]=information
		_notice_room_information()
		room_data_update.emit(room_user_information)
	else:
		client_sync_self_information(information)


## 获取自身当前的用户信息（返回副本，网络未就绪时返回 null）。
##
## Returns the current information of this peer (a copy), or null when the
## network is not ready.
func get_self_information()->UserInformation:
	if not is_ready():
		return null
	if room_user_information.has(get_self_id()):
		return room_user_information[get_self_id()].copy()
	return null


## 请求创建房间（作为服务器），传入自身的用户信息。
##
## Requests creating a room as the server with this peer's user information.
## [param port] 监听端口。
##
## [param port] is the listening port.
func request_create_room(information: UserInformation,port:int=DEFAULT_PORT):
	if network_mode != NetworkMode.FREE:
		printerr("网络非空闲")
		pass
	network_mode = NetworkMode.SERVER
	peer = ENetMultiplayerPeer.new()
	peer.transfer_channel=32
	var err = peer.create_server(port, 3)
	if err == OK:
		peer.peer_connected.connect(_on_server_peer_connected)
		peer.peer_disconnected.connect(_on_server_peer_disconnected)

		multiplayer.multiplayer_peer = peer
		create_room_finished.emit(true)
		server_sync_self_information(information)
	else:
		create_room_finished.emit(false)
		clear()

## 服务器端：新客户端连接成功时的回调，记录尚未同步名称的客户端 ID。
##
## Server side: callback for a newly connected client; records the client ID
## whose name information has not been synced yet.
func _on_server_peer_connected(id: int):
	if refuse_new_connections:
		if peer!=null:
			peer.disconnect_peer(id)
		return
	if not peer_without_name.has(id):
		peer_without_name.append(id)
	##向新加入的合法客户端发送确认包，客户端收到后才开始同步自身信息
	##延迟到下一帧发送，确保该peer的id缓存已在服务器侧就绪
	_accept_peer.call_deferred(id)

## 延迟向指定 peer 发送合法确认包（延迟确保 peer ID 缓存已就绪）。
##
## Sends the acceptance notice to the given peer, deferred to make sure the peer
## ID cache is ready on the server side.
func _accept_peer(id: int):
	if peer==null or not has_peer(id):
		return
	put_notice(id, NoticeServerAccept.new())

## 服务器端：客户端断开连接时的回调，清理相关数据并通知其他客户端。
##
## Server side: callback for a disconnected client; cleans up related data and
## notifies the other clients.
func _on_server_peer_disconnected(id: int):
	if peer_without_name.has(id):
		peer_without_name.pop_at(peer_without_name.find(id))
	if room_user_information.has(id):
		var information: UserInformation = room_user_information[id]
		room_user_information.erase(id)
		_notice_room_information.call_deferred()
		user_left.emit(id, information)
		await get_tree().process_frame
		_notice_user_changed(NoticeUserChanged.ChangeType.LEFT, id, information.export_data())
	room_data_update.emit(room_user_information)

## 初始化加入房间的超时计时器。
##
## Sets up the timeout timer for joining a room.
func set_up_join_room_timer():
	join_room_timeout_timer=Timer.new()
	join_room_timeout_timer.one_shot=true
	join_room_timeout_timer.autostart=false
	join_room_timeout_timer.timeout.connect(_on_join_room_timeout_timer_timeout)
	add_child(join_room_timeout_timer)
	pass

## 加入房间时缓存的本端用户信息，加入成功后同步给服务器。
##
## This peer's user information cached while joining, synced to the server after
## joining succeeds.
var client_join_information_cache:UserInformation
## 请求加入房间（作为客户端），传入自身用户信息、服务器地址和端口。
##
## Requests joining a room as a client with this peer's user information, the
## server address and port.
## [param timeout] 超时时间，设置为负数或零则永不超时。
##
## [param timeout] is the timeout in seconds; a negative or zero value means it
## never times out.
func request_join_room(information: UserInformation, address: String, port: int = DEFAULT_PORT,timeout:float=10):
	if network_mode != NetworkMode.FREE:
		printerr("网络非空闲")
		pass
	network_mode = NetworkMode.CLIENT_JOINING
	peer = ENetMultiplayerPeer.new()
	peer.transfer_channel=32
	var err = peer.create_client(address, port)
	if err == OK:
		client_join_information_cache=information
		multiplayer.multiplayer_peer = peer
		peer.peer_disconnected.connect(_on_client_peer_disconnected)
		if timeout>0:
			join_room_timeout_timer.start(timeout)
	else:
		join_room_finished.emit(false)
		clear()
## 加入房间超时时的回调：报告失败并清理状态。
##
## Callback for a join-room timeout: reports failure and clears the state.
func _on_join_room_timeout_timer_timeout():
	if network_mode == NetworkMode.CLIENT_JOINING:
		join_room_finished.emit(false)
		clear()
		


## 每帧检查客户端连接状态，连接断开时清理并发出房间销毁信号。
##
## Checks the client connection state every frame; when it drops, clears the
## state and emits [signal client_room_destroy].
func _process(delta: float) -> void:
	
	match network_mode:
		NetworkMode.CLIENT_JOINED:
			if peer !=null and peer.get_connection_status()!=MultiplayerPeer.ConnectionStatus.CONNECTION_CONNECTED:
				clear()
				client_room_destroy.emit()
			pass

## 客户端收到服务器合法确认包后调用：进入已加入状态并同步自身信息。
##
## Called on a client after receiving the server's acceptance notice: switches
## to the joined state and syncs its own information.
func _on_server_accept():
	if network_mode != NetworkMode.CLIENT_JOINING:
		return
	#关闭加入房间的超时计时器
	if join_room_timeout_timer!=null:
		join_room_timeout_timer.stop()
	network_mode = NetworkMode.CLIENT_JOINED
	join_room_finished.emit(true)
	client_sync_self_information.call_deferred(client_join_information_cache)
	client_join_information_cache=null



## 客户端断开连接时的回调（包括服务器断开）。
##
## Callback for a client disconnecting, including the server going away.
func _on_client_peer_disconnected(peer_id: int):
	if network_mode == NetworkMode.SERVER:
		return
	if peer_id == SERVER_ID:
		await get_tree().create_timer(0.5).timeout
		if network_mode == NetworkMode.CLIENT_JOINING:
			#加入过程中被服务器拒绝/断开，报告加入失败
			join_room_finished.emit(false)
			clear()

## 客户端将自己的信息同步给服务器（发送 [NoticeSyncInformation]）。
##
## Client side: syncs this peer's information to the server with
## [NoticeSyncInformation].
func client_sync_self_information(information: UserInformation):
	var notice := NoticeSyncInformation.new()
	notice.information = information.export_data()
	put_notice(SERVER_ID, notice)

## 服务器将自己的信息同步给所有客户端（本地应用并广播）。
##
## Server side: applies the server's own information locally and broadcasts it.
func server_sync_self_information(information: UserInformation):
	_apply_information(SERVER_ID, information.export_data())

## 服务器应用一条用户信息（注册或更新），并广播给所有客户端。
##
## [param peer_id] 必须来自可信来源（接收端注入的发送者），不能取自负载。
##
## Server side: applies one user's information (registration or update) and
## broadcasts it to every client. [param peer_id] must come from a trusted
## source (the sender injected on receive), never from the payload.
func _apply_information(peer_id: int, information: Dictionary) -> void:
	if not is_server():
		return
	var info := _build_information(information)
	room_user_information[peer_id] = info
	if peer_without_name.has(peer_id):
		peer_without_name.pop_at(peer_without_name.find(peer_id))
		user_join.emit(peer_id, info)
		_notice_user_changed(NoticeUserChanged.ChangeType.JOIN, peer_id, information)
	else:
		user_update.emit(peer_id, info)
		_notice_user_changed(NoticeUserChanged.ChangeType.UPDATE, peer_id, information)
	_notice_room_information()
	room_data_update.emit(room_user_information)

## 客户端应用服务器广播的用户变更，并发出对应信号。
##
## Client side: applies a user-change broadcast from the server and emits the
## matching signal.
func _apply_user_changed(notice: NoticeUserChanged) -> void:
	var information := _build_information(notice.information)
	match notice.change_type:
		NoticeUserChanged.ChangeType.JOIN:
			user_join.emit(notice.peer_id, information)
		NoticeUserChanged.ChangeType.LEFT:
			user_left.emit(notice.peer_id, information)
		_:
			user_update.emit(notice.peer_id, information)

## 用字典构造 [UserInformation]。
##
## Builds a [UserInformation] from a dictionary.
func _build_information(information: Dictionary) -> UserInformation:
	var info := UserInformation.new()
	info.import_data(information)
	return info

## 广播用户加入 / 离开 / 更新通知。
##
## Broadcasts a user joined / left / updated notice.
func _notice_user_changed(change_type: int, peer_id: int, information: Dictionary) -> void:
	var notice := NoticeUserChanged.new()
	notice.change_type = change_type
	notice.peer_id = peer_id
	notice.information = information
	put_notice_to_players(notice)

## 广播当前房间内所有用户的信息。
##
## Broadcasts the information of every user in the room.
func _notice_room_information() -> void:
	var notice := NoticeRoomInformation.new()
	notice.information = information_to_dic(room_user_information)
	put_notice_to_players(notice)

## 派发同步就绪通知给对应的同步节点 / 场景。
##
## Dispatches a sync-ready notice to the matching synchronized node or scene.
func _dispatch_sync_ready(notice: NoticeSyncReady) -> void:
	var node := get_tree().root.get_node_or_null(notice.node_path)
	if node != null and node.has_method("handle_sync_ready"):
		node.handle_sync_ready(notice.kind, notice.sender)

## 根据用户 ID 获取其用户信息，若不存在则返回一个新的空 UserInformation 对象。
##
## Returns the information of the given peer ID, or a new empty
## [UserInformation] when it does not exist.
func get_peer_information(peer_id: int) -> UserInformation:
	if room_user_information.has(peer_id):
		return room_user_information[peer_id]
	return UserInformation.new()

## （服务器）设置是否拒绝新客户端连接。
##
## Server side: sets whether new client connections are refused.
func server_set_refuse_new_connection(enable: bool):
	if network_mode != NetworkMode.SERVER:
		return
	refuse_new_connections=enable
	#peer.refuse_new_connections = enable
	pass

## （服务器）清理所有尚未同步名称的客户端连接（强制断开）。
##
## Server side: clears all client connections that have not synced their name
## information yet (forcing them to disconnect).
func server_clear_peer_without_name():
	if network_mode != NetworkMode.SERVER:
		return
	for i in peer_without_name:
		peer.disconnect_peer(i)
	peer_without_name.clear()

## 获取本地用户的唯一 ID。
##
## Returns the unique ID of the local peer.
func get_self_id() -> int:
	if peer == null:
		return -1
	return peer.get_unique_id()

## 判断当前是否为服务器模式。
##
## Returns whether this peer is in server mode.
func is_server() -> bool:
	return network_mode == NetworkMode.SERVER

## 清理网络资源并重置状态。
##
## Clears the network resources and resets the state.
func clear():
	if peer != null:
		peer.close()
		peer = null
		multiplayer.multiplayer_peer = null
	if not join_room_timeout_timer.is_stopped():
		join_room_timeout_timer.stop()
	request_array.clear()
	request_finished_id_cache.clear()
	room_user_information.clear()
	peer_without_name.clear()
	network_mode = NetworkMode.FREE
	refuse_new_connections=false
	pass

## 请求执行过滤器数组：执行请求前按顺序逐个询问，全部同意才继续。
##
## Request execution filters. Every execution asks them in order; all of them
## must agree before the request runs.
var request_filters: Array[RequestFilter] = []

## 添加一个执行过滤器（重复添加会被忽略）。
##
## Adds an execution filter; duplicates are ignored.
func add_request_filter(filter: RequestFilter) -> void:
	if filter == null or request_filters.has(filter):
		return
	request_filters.append(filter)

## 移除一个执行过滤器。
##
## Removes an execution filter.
func remove_request_filter(filter: RequestFilter) -> void:
	request_filters.erase(filter)

## 集中执行接口：所有请求的执行都必须经过这里。
##
## 流程：依次询问所有过滤器 -> 询问 request.can_execute() -> await 执行。
## 返回 true 表示请求真正被执行了，false 表示被过滤器或请求自身拦截。
## 注意：本函数是协程，需要等待执行完成时请使用
## [code]await execute_request(request)[/code]。
##
## Central execution entry point that every request execution must go through.
## It asks every filter in order, then [method Request.can_execute], then awaits
## [method Request.execute]. Returns true when the request really ran, false when
## a filter or the request itself blocked it. This function is a coroutine; use
## [code]await execute_request(request)[/code] to wait for completion.
func execute_request(request: Request) -> bool:
	if request == null:
		return false
	## 过滤器有一票否决权
	for filter: RequestFilter in request_filters:
		if filter != null and not filter.can_execute(request):
			return false
	## 过滤器全部同意后，再询问请求自身是否可执行
	if not request.can_execute():
		return false
	await request.execute()
	return true


## 服务器端的请求队列，按顺序把请求分发到各客户端执行。
##
## Server-side request queue that dispatches requests to the clients in order.
var request_array: Array[Request] = []
## 已完成当前请求的客户端 ID 缓存。
##
## Client IDs that have finished the current request.
var request_finished_id_cache: Array[int] = []

## 当有用户离开时（服务器端），检查请求队列并推进执行。
##
## Server side: when a user leaves, checks the request queue and advances it.
func _on_user_left_process(id: int, information: UserInformation):
	if not is_server():
		return
	if not request_array.is_empty():
		request_finished_id_cache.push_back(id)
		if contains_all(get_peer_array(), request_finished_id_cache):
			request_array.pop_front()
			if request_array.size() != 0:
				request_finished_id_cache.clear()
				## 统一走 execute_request：过滤器 -> request.can_execute() -> 执行
				execute_request(request_array[0])
				request_finished_id_cache.append(SERVER_ID)
				var notice:NoticeExecRequest=NoticeExecRequest.new()
				notice.request=request_array[0]
				put_notice_to_players(notice)

## 获取所有用户的用户信息。
##
## Returns the information of every user.
func get_all_user_information()->Dictionary[int,UserInformation]:
	return room_user_information


## 判断当前代码是否运行在主线程。
##
## Returns whether the current code runs on the main thread.
func is_main_thread() -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id()

## 提交请求：服务器端直接入队，客户端通过通知把请求交给服务器。
##
## 支持从子线程调用：若不在主线程，会先延迟到主线程再推入。
##
## Submits a request. The server enqueues it directly; a client sends it to the
## server with a notice. It can be called from a worker thread: the call is
## deferred to the main thread when needed.
func push_request(request: Request):
	## 从子线程推入时延迟到主线程，避免非线程安全的场景树/网络操作
	if not is_main_thread():
		call_deferred("push_request", request)
		return
	if not is_ready():
		return
	if is_server():
		server_push_request(request)
	else:
		var notice:NoticePushRequest=NoticePushRequest.new()
		notice.request=request
		put_notice(SERVER_ID,notice)

## 请求立即在所有端执行一个请求，不做执行完毕同步。
##
## 支持从子线程调用：若不在主线程，会先延迟到主线程再推入。
##
## Requests immediate execution of a request on every peer, without
## finished-notice synchronization. It can be called from a worker thread: the
## call is deferred to the main thread when needed.
func push_request_immediately(request:Request):
	## 从子线程推入时延迟到主线程，避免非线程安全的场景树/网络操作
	if not is_main_thread():
		call_deferred("push_request_immediately", request)
		return
	if not is_ready():
		return
	if is_server():
		execute_request(request)
		var notice:NoticeExecRequestImmediately=NoticeExecRequestImmediately.new()
		notice.request=request
		put_notice_to_players(notice)
	else:
		var notice:NoticePushRequestImmediately=NoticePushRequestImmediately.new()
		notice.request=request
		put_notice(SERVER_ID,notice)



## 服务器端推入请求，若队列为空则立即执行。
##
## Server side: pushes a request and executes it immediately when the queue was
## empty.
func server_push_request(request: Request):
	request_array.append(request)
	if request_array.size() == 1:
		request_finished_id_cache.clear()
		execute_request(request)
		request_finished_id_cache.append(SERVER_ID)
		
		
		var notice:NoticeExecRequest=NoticeExecRequest.new()
		notice.request=request
		put_notice_to_players(notice)
		_try_advance_queue()
	if request_array.size()== 3:
		var request2=request_array.pop_back()
		var request1=request_array.pop_back()
		request_array.append(pack_request(request1,request2))
		pass
## 打包两个请求：若第一个已是打包请求则直接追加，否则新建打包请求。
##
## Packs two requests: appends to the first one when it is already a packed
## request, otherwise creates a new packed request.
func pack_request(request1:Request,request2:Request)->Request:
	if request1 is RequestPacked:
		request1.append_request(request2)
		return request1
	else:
		var request_packed:RequestPacked=RequestPacked.new()
		request_packed.append_request(request1)
		request_packed.append_request(request2)
		return request_packed


## 尝试推进请求队列。
##
## Tries to advance the request queue.
func _try_advance_queue():
	if not is_server():
		return
	if request_array.is_empty():
		return
	if contains_all(get_peer_array(), request_finished_id_cache):
		var request:Request=request_array.pop_front()
		request_finished.emit(request)
		if request is RequestPacked:
			for i in request.request_array:
				request_finished.emit(i)
		if not request_array.is_empty():
			request_finished_id_cache.clear()
			request_finished_id_cache.append(SERVER_ID)
			execute_request(request_array[0])
			
			var notice:NoticeExecRequest=NoticeExecRequest.new()
			notice.request=request_array[0]
			put_notice_to_players(notice)
			_try_advance_queue()
		else:
			request_finished_id_cache.clear()





## 判断第一个数组中的所有元素是否都存在于第二个数组中（不考虑顺序和重复次数）。
##
## Returns whether every element of [param array_a] exists in [param array_b],
## ignoring order and duplicate counts.
func contains_all(array_a: Array, array_b: Array) -> bool:
	for element in array_a:
		if not array_b.has(element):
			return false
	return true





## 获取当前房间内所有用户的 ID 数组（包括服务器）。
##
## Returns the IDs of every user in the room, including the server.
func get_peer_array() -> Array[int]:
	return room_user_information.keys()

## 获取当前房间内除服务器以外的所有用户 ID 数组。
##
## Returns the IDs of every user in the room except the server.
func get_peer_array_except_server() -> Array[int]:
	var result: Array[int] = room_user_information.keys()
	result.erase(1)
	return result


## 当前是否具有对应的 peer（已连接或已验证）。
##
## Returns whether the given peer exists (connected or validated).
func has_peer(id:int)->bool:
	return (peer_without_name.has(id) or room_user_information.has(id))

## 判断 peer 是否已经验证（已成功加入房间并同步了用户信息）。
##
## Returns whether the peer is validated, i.e. it joined the room and synced its
## user information.
func is_peer_validated(id:int)->bool:
	return room_user_information.has(id)
