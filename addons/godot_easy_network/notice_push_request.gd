extends Message

## 客户端把请求提交给服务器的通知。
##
## Notice used by a client to submit a request to the server.
class_name NoticePushRequest

## 要提交的请求。
##
## The request to submit.
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
