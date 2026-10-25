extends Message

## 服务器广播：某个用户加入、离开或信息更新。
##
## Server broadcast: a user joined, left or had their information updated.
class_name NoticeUserChanged

## 变更类型。
##
## Change type.
enum ChangeType {
	## 用户加入。
	##
	## The user joined.
	JOIN,
	## 用户离开。
	##
	## The user left.
	LEFT,
	## 用户信息更新。
	##
	## The user's information was updated.
	UPDATE,
}

## 本次变更的类型。
##
## Type of this change.
var change_type: int = ChangeType.UPDATE
## 相关用户的网络 ID。
##
## Network ID of the affected user.
var peer_id: int = 0
## 该用户的用户信息。
##
## The user's information.
var information: Dictionary = {}


func export_bytes() -> PackedByteArray:
	var bytes := ByteBuffer.new()
	bytes.put_int(change_type)
	bytes.put_int(peer_id)
	bytes.put_packed_byte_array(Factory.dict_to_bytes(information))
	return bytes.data


func import_bytes(data: PackedByteArray) -> void:
	var bytes := ByteBuffer.new(data)
	change_type = bytes.get_int()
	peer_id = bytes.get_int()
	information = Factory.bytes_to_dict(bytes.get_packed_byte_array())
