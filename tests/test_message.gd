extends SceneTree

## Message 序列化测试：消息 / 请求 / 通知的字节流往返。
##
## Message serialization tests: byte-stream round-trips for messages, requests
## and notices.

var failures: int = 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Message.initialize_class_cache()
	_test_user_information()
	_test_sender_roundtrip()
	_test_sender_injection()
	_test_request_call()
	_test_request_free_node()
	_test_request_instantiate_scene()
	_test_request_packed()
	_test_notices()
	_test_info_notices()
	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)


func _test_user_information() -> void:
	var info := UserInformation.new()
	info.user_name = "Alice"
	var back: Message = Message.from_bytes(info.to_bytes())
	check(back is UserInformation, "UserInformation class restored")
	if back is UserInformation:
		check(back.user_name == "Alice", "UserInformation name restored")


func _test_sender_roundtrip() -> void:
	var info := UserInformation.new()
	info.user_name = "Sender"
	info.sender = 42
	var back: Message = Message.from_bytes(info.to_bytes())
	check(back.sender == 42, "sender participates in serialization")


func _test_sender_injection() -> void:
	var net := NetworkInstance.new()

	# 服务器直收客户端包：以网络来源为准，覆盖伪造值
	net.network_mode = NetworkInstance.NetworkMode.SERVER
	var from_client := NoticeExecuteFinished.new()
	from_client.sender = 999
	net._inject_trusted_sender(from_client, 7)
	check(from_client.sender == 7, "server overrides sender with network source")

	# 客户端收到服务器转发：信任服务器写入的发送者
	net.network_mode = NetworkInstance.NetworkMode.CLIENT_JOINED
	var relayed := NoticeExecuteFinished.new()
	relayed.sender = 42
	net._inject_trusted_sender(relayed, NetworkInstance.SERVER_ID)
	check(relayed.sender == 42, "client trusts server-provided sender")

	# 客户端收到未标注发送者的服务器包：回退为服务器 ID
	var unset := NoticeExecuteFinished.new()
	net._inject_trusted_sender(unset, NetworkInstance.SERVER_ID)
	check(unset.sender == NetworkInstance.SERVER_ID, "client falls back to server id")

	# 其它直连来源：同样以网络来源为准
	var direct := NoticeExecuteFinished.new()
	direct.sender = 42
	net._inject_trusted_sender(direct, 5)
	check(direct.sender == 5, "direct source overrides sender")


func _test_request_call() -> void:
	var call := RequestCall.Call.new()
	call.node_path = "/root/Test"
	call.func_name = "do_something"
	call.call_args = [1, 2.5, "s", true, Vector2(3, 4), PackedByteArray([7, 8]), null, Color.RED]
	var request := RequestCall.new()
	request.call_array = [call]

	var back: Message = Message.from_bytes(request.to_bytes())
	check(back is RequestCall, "RequestCall class restored")
	if back is RequestCall:
		var restored_call: RequestCall.Call = back.call_array[0]
		check(restored_call.node_path == "/root/Test", "RequestCall node path")
		check(restored_call.func_name == "do_something", "RequestCall func name")
		check(restored_call.call_args == [1, 2.5, "s", true, Vector2(3, 4), PackedByteArray([7, 8]), null, null],
			"RequestCall args (unsupported type becomes null)")


func _test_request_free_node() -> void:
	var request := RequestFreeNode.new()
	request.node_path = NodePath("/root/Target")
	var back: Message = Message.from_bytes(request.to_bytes())
	check(back is RequestFreeNode, "RequestFreeNode class restored")
	if back is RequestFreeNode:
		check(back.node_path == NodePath("/root/Target"), "RequestFreeNode path restored")


func _test_request_instantiate_scene() -> void:
	var source_path := "res://addons/godot_easy_network/request_call.gd"
	var request := RequestInstantiateScene.new()
	request.scene_path = source_path
	request.parent = NodePath("/root/Main")
	request.node_name = "Hero"
	request.belong_to = 2
	request.init_value = {
		"hp": 10,
		"speed": 2.5,
		"pos": Vector2(1, 2),
		"tags": ["a", "b"],
		"nested": {"alive": true},
	}
	var back: Message = Message.from_bytes(request.to_bytes())
	check(back is RequestInstantiateScene, "RequestInstantiateScene class restored")
	if back is RequestInstantiateScene:
		check(back.scene_path == ResourceUID.path_to_uid(source_path), "instantiate scene path (uid)")
		check(back.parent == NodePath("/root/Main"), "instantiate parent restored")
		check(back.node_name == "Hero", "instantiate node name restored")
		check(back.belong_to == 2, "instantiate belong_to restored")
		check(back.init_value == request.init_value, "instantiate init_value restored")


func _test_request_packed() -> void:
	var first := RequestFreeNode.new()
	first.node_path = NodePath("/root/A")
	var second := RequestFreeNode.new()
	second.node_path = NodePath("/root/B")
	var net := NetworkInstance.new()
	var packed: Request = net.pack_request(first, second)
	check(packed is RequestPacked, "pack_request creates RequestPacked")

	var back: Message = Message.from_bytes(packed.to_bytes())
	check(back is RequestPacked, "RequestPacked class restored")
	if back is RequestPacked:
		check(back.request_array.size() == 2, "RequestPacked child count")
		check(back.request_array[0] is RequestFreeNode, "RequestPacked first child class")
		check(back.request_array[0].node_path == NodePath("/root/A"), "RequestPacked first child data")
		check(back.request_array[1].node_path == NodePath("/root/B"), "RequestPacked second child data")


func _test_notices() -> void:
	var request := RequestCall.new()
	request.call_array = []

	var exec_notice := NoticeExecRequest.new()
	exec_notice.request = request
	var exec_back: Message = Message.from_bytes(exec_notice.to_bytes())
	check(exec_back is NoticeExecRequest, "NoticeExecRequest class restored")
	if exec_back is NoticeExecRequest:
		check(exec_back.request is RequestCall, "NoticeExecRequest payload restored")

	var exec_now := NoticeExecRequestImmediately.new()
	exec_now.request = request
	var exec_now_back: Message = Message.from_bytes(exec_now.to_bytes())
	check(exec_now_back is NoticeExecRequestImmediately, "NoticeExecRequestImmediately restored")

	var push := NoticePushRequest.new()
	push.request = request
	var push_back: Message = Message.from_bytes(push.to_bytes())
	check(push_back is NoticePushRequest, "NoticePushRequest restored")

	var push_now := NoticePushRequestImmediately.new()
	push_now.request = request
	var push_now_back: Message = Message.from_bytes(push_now.to_bytes())
	check(push_now_back is NoticePushRequestImmediately, "NoticePushRequestImmediately restored")

	check(Message.from_bytes(NoticeExecuteFinished.new().to_bytes()) is NoticeExecuteFinished,
		"NoticeExecuteFinished restored")
	check(Message.from_bytes(NoticeServerAccept.new().to_bytes()) is NoticeServerAccept,
		"NoticeServerAccept restored")


func _test_info_notices() -> void:
	var sync_info := NoticeSyncInformation.new()
	sync_info.information = {"user_name": "Alice", "is_ready": true}
	var info_back: Message = Message.from_bytes(sync_info.to_bytes())
	check(info_back is NoticeSyncInformation, "NoticeSyncInformation restored")
	if info_back is NoticeSyncInformation:
		check(info_back.information == sync_info.information, "NoticeSyncInformation payload")

	var changes := [
		NoticeUserChanged.ChangeType.JOIN,
		NoticeUserChanged.ChangeType.LEFT,
		NoticeUserChanged.ChangeType.UPDATE,
	]
	for change_type in changes:
		var changed := NoticeUserChanged.new()
		changed.change_type = change_type
		changed.peer_id = 5
		changed.information = {"user_name": "Bob"}
		var changed_back: Message = Message.from_bytes(changed.to_bytes())
		check(changed_back is NoticeUserChanged, "NoticeUserChanged restored (%d)" % change_type)
		if changed_back is NoticeUserChanged:
			check(changed_back.change_type == change_type, "NoticeUserChanged type (%d)" % change_type)
			check(changed_back.peer_id == 5, "NoticeUserChanged peer id")
			check(changed_back.information == changed.information, "NoticeUserChanged payload")

	var room := NoticeRoomInformation.new()
	room.information = {1: {"user_name": "server"}, 2: {"user_name": "c1"}}
	var room_back: Message = Message.from_bytes(room.to_bytes())
	check(room_back is NoticeRoomInformation, "NoticeRoomInformation restored")
	if room_back is NoticeRoomInformation:
		check(room_back.information == room.information, "NoticeRoomInformation payload (int keys)")

	for kind in [NoticeSyncReady.Kind.NODE, NoticeSyncReady.Kind.SCENE]:
		var ready := NoticeSyncReady.new()
		ready.kind = kind
		ready.node_path = "/root/World/Unit"
		var ready_back: Message = Message.from_bytes(ready.to_bytes())
		check(ready_back is NoticeSyncReady, "NoticeSyncReady restored (%d)" % kind)
		if ready_back is NoticeSyncReady:
			check(ready_back.kind == kind, "NoticeSyncReady kind (%d)" % kind)
			check(ready_back.node_path == ready.node_path, "NoticeSyncReady node path")
