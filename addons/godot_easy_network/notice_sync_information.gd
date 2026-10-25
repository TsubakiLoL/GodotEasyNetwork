extends Message

## 客户端上报或更新自身用户信息（注册流程）。
##
## 发送者身份不放在负载里，接收端以可信注入的 [member Message.sender] 为准，
## 防止其它客户端顶替。
##
## Client-to-server notice reporting or updating the sender's own user
## information (registration flow). The sender identity is not part of the
## payload: the server uses the trusted [member Message.sender] injected on
## receive, so another client cannot impersonate it.
class_name NoticeSyncInformation

## 用户信息（[method UserInformation.export_data] 的结果）。
##
## User information (the result of [method UserInformation.export_data]).
var information: Dictionary = {}


func export_bytes() -> PackedByteArray:
	var bytes := ByteBuffer.new()
	bytes.put_packed_byte_array(Factory.dict_to_bytes(information))
	return bytes.data


func import_bytes(data: PackedByteArray) -> void:
	var bytes := ByteBuffer.new(data)
	information = Factory.bytes_to_dict(bytes.get_packed_byte_array())
