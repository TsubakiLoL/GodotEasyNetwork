extends Message

## 服务器广播：当前房间内所有用户的信息。
##
## Server broadcast: the information of every user in the room.
class_name NoticeRoomInformation

## 用户 ID 到用户信息字典的映射。
##
## Mapping from peer ID to the user's information dictionary.
var information: Dictionary[int, Dictionary] = {}


func export_bytes() -> PackedByteArray:
	var bytes := ByteBuffer.new()
	bytes.put_int(information.size())
	for peer_id in information.keys():
		bytes.put_int(int(peer_id))
		bytes.put_packed_byte_array(Factory.dict_to_bytes(information[peer_id]))
	return bytes.data


func import_bytes(data: PackedByteArray) -> void:
	var bytes := ByteBuffer.new(data)
	information.clear()
	var count := bytes.get_int()
	for i in count:
		var peer_id := bytes.get_int()
		information[peer_id] = Factory.bytes_to_dict(bytes.get_packed_byte_array())
