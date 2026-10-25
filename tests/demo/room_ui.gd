extends Control

## 简易房间界面测试用例：创建 / 加入房间、玩家列表、准备、开始与请求同步。
##
## Simple room UI test scene: create / join a room, player list, ready state,
## start and request synchronization.

## 默认端口。
##
## Default port.
const DEFAULT_PORT := 9939

@onready var _network: NetworkInstance = $Network
@onready var _name_edit: LineEdit = %NameEdit
@onready var _port_spin: SpinBox = %PortSpin
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _create_button: Button = %CreateButton
@onready var _join_button: Button = %JoinButton
@onready var _leave_button: Button = %LeaveButton
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _test_button: Button = %TestButton
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _status_label: Label = %StatusLabel
@onready var _log_label: RichTextLabel = %LogLabel


func _ready() -> void:
	_port_spin.value = DEFAULT_PORT
	_network.create_room_finished.connect(_on_create_room_finished)
	_network.join_room_finished.connect(_on_join_room_finished)
	_network.room_data_update.connect(_on_room_data_update)
	_network.user_join.connect(_on_user_join)
	_network.user_left.connect(_on_user_left)
	_network.user_update.connect(_on_user_update)
	_network.client_room_destroy.connect(_on_client_room_destroy)
	_log("等待操作：创建或加入房间")
	_update_ui()


func _on_create_pressed() -> void:
	if _network.is_ready():
		return
	_create_button.disabled = true
	_join_button.disabled = true
	_log("正在创建房间，端口 %d" % int(_port_spin.value))
	_network.request_create_room(_make_self_information(), int(_port_spin.value))


func _on_join_pressed() -> void:
	if _network.is_ready():
		return
	_create_button.disabled = true
	_join_button.disabled = true
	_log("正在加入房间 %s:%d" % [_address_edit.text, int(_port_spin.value)])
	_network.request_join_room(_make_self_information(), _address_edit.text, int(_port_spin.value))


func _on_leave_pressed() -> void:
	_network.clear()
	_clear_player_list()
	_log("已离开房间")
	_update_ui()


func _on_ready_pressed() -> void:
	var information := _network.get_self_information()
	if information == null:
		return
	information.is_ready = not information.is_ready
	_network.request_change_self_information(information)
	_update_ui()


func _on_start_pressed() -> void:
	if not _network.is_server():
		_log("只有房主可以开始游戏")
		return
	for information: UserInformation in _network.get_all_user_information().values():
		if not information.is_ready:
			_log("还有玩家未准备")
			return
	var request := RequestCall.new()
	request.add_call(self, "_on_sync_message", "房主开始了游戏（请求同步测试）")
	_network.push_request(request)


func _on_test_pressed() -> void:
	if not _network.is_ready():
		return
	var request := RequestCall.new()
	request.add_call(self, "_on_sync_message", "%s 发送了一条同步测试请求" % _name_edit.text)
	_network.push_request(request)


## 由同步请求在所有端调用。
##
## Called on every peer by the synchronized request.
func _on_sync_message(text: String) -> void:
	_log(text)


func _make_self_information() -> UserInformation:
	var information := UserInformation.new()
	information.user_name = _name_edit.text.strip_edges()
	if information.user_name.is_empty():
		information.user_name = "Player"
	information.is_ready = false
	return information


func _on_create_room_finished(success: bool) -> void:
	_log("创建房间%s" % ("成功" if success else "失败"))
	_update_ui()


func _on_join_room_finished(success: bool) -> void:
	_log("加入房间%s" % ("成功" if success else "失败"))
	_update_ui()


func _on_room_data_update(room_data: Dictionary[int, UserInformation]) -> void:
	_refresh_player_list(room_data)
	_update_ui()


func _on_user_join(peer_id: int, information: UserInformation) -> void:
	_log("用户加入：%s（ID %d）" % [information.user_name, peer_id])
	_refresh_player_list(_network.get_all_user_information())


func _on_user_left(peer_id: int, information: UserInformation) -> void:
	_log("用户离开：%s（ID %d）" % [information.user_name, peer_id])
	_refresh_player_list(_network.get_all_user_information())


func _on_user_update(peer_id: int, information: UserInformation) -> void:
	_log("用户更新：%s（ID %d）" % [information.user_name, peer_id])
	_refresh_player_list(_network.get_all_user_information())


func _on_client_room_destroy() -> void:
	_clear_player_list()
	_log("房主断开连接")
	_update_ui()


func _refresh_player_list(room_data: Dictionary[int, UserInformation]) -> void:
	_clear_player_list()
	for peer_id in room_data:
		_player_list.add_child(_make_player_row(peer_id, room_data[peer_id]))


func _make_player_row(peer_id: int, information: UserInformation) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = information.user_name
	if peer_id == _network.get_self_id():
		name_label.text += "（你）"
	row.add_child(name_label)
	var id_label := Label.new()
	id_label.text = "ID %d" % peer_id
	id_label.custom_minimum_size.x = 70
	row.add_child(id_label)
	var role_label := Label.new()
	role_label.text = "房主" if peer_id == NetworkInstance.SERVER_ID else "成员"
	role_label.custom_minimum_size.x = 50
	row.add_child(role_label)
	var ready_label := Label.new()
	ready_label.text = "已准备" if information.is_ready else "未准备"
	ready_label.custom_minimum_size.x = 70
	row.add_child(ready_label)
	return row


func _clear_player_list() -> void:
	for child in _player_list.get_children():
		child.queue_free()


func _update_ui() -> void:
	var ready := _network.is_ready()
	var is_server := ready and _network.is_server()
	_create_button.disabled = ready
	_join_button.disabled = ready
	_leave_button.disabled = not ready
	_ready_button.disabled = not ready
	_test_button.disabled = not ready
	_start_button.disabled = not is_server
	if ready:
		_status_label.text = "%s（ID %d）" % ["服务器" if is_server else "客户端", _network.get_self_id()]
	else:
		_status_label.text = "未连接"
	var self_information := _network.get_self_information()
	_ready_button.text = "取消准备" if self_information != null and self_information.is_ready else "准备"


func _log(text: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), text]
	_log_label.append_text(line + "\n")
	print(line)
