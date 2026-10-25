extends Message

## 客户端要求服务器立即执行请求的通知。
##
## Notice used by a client to ask the server to execute a request immediately.
class_name NoticePushRequestImmediately

## 需要立即执行的请求。
##
## The request to execute immediately.
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
