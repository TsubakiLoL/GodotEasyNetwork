extends Message

## 服务器要求客户端执行一个请求的通知。
##
## Server-to-client notice asking a client to execute a request.
class_name NoticeExecRequest

## 待执行的请求。
##
## The request to execute.
var request:Request


## 从字节流反序列化出请求对象。
##
## Deserializes the request from [param data].
func import_bytes(data:PackedByteArray):
	var req=Message.from_bytes(data)
	if req is Request:
		request=req


## 将请求序列化为字节流，没有请求时返回空数组。
##
## Serializes the request, returning an empty array when there is none.
func export_bytes()->PackedByteArray:
	if request==null:
		return PackedByteArray()
	else:
		return request.to_bytes()
