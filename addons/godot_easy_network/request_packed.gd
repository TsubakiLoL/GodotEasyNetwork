extends Request

## 打包后的请求：把多个请求合并成一个整体，在服务器队列的同一位置按顺序执行。
##
## Packed request: bundles several requests into one unit that executes them in
## order at a single position in the server queue.
class_name RequestPacked

## 被合并的请求列表，按顺序执行。
##
## The bundled requests, executed in order.
var request_array:Array[Request]=[]


## 返回日志友好的字符串。
##
## Returns a debug-friendly string representation.
func _to_string()->String:
	return "RequestPacked(requests=%s)" % [str(request_array)]


## 依次执行所有被合并的请求。
##
## Executes every bundled request in order.
func execute():
	for i in request_array:
		i.execute()

## 把一个请求追加到打包列表末尾。
##
## Appends a request to the end of the bundle.
func append_request(request:Request):
	request_array.append(request)
	pass




## 序列化打包请求：请求数量 + 每个请求的字节。
##
## Serializes the bundle: the request count followed by each request's bytes.
func export_bytes()->PackedByteArray:
	var bytes:ByteBuffer=ByteBuffer.new()
	bytes.put_int(request_array.size())
	for i in request_array:
		bytes.put_packed_byte_array(i.to_bytes())
	return bytes.data
## 反序列化打包请求。
##
## Deserializes the bundle.
func import_bytes(data:PackedByteArray):
	request_array.clear()
	var bytes:ByteBuffer=ByteBuffer.new(data)
	var num:int=bytes.get_int()
	for i in num:
		var request:Request=Request.from_bytes(bytes.get_packed_byte_array())
		if request!=null:
			request_array.append(request)
