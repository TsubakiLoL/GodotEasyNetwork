extends Message

## 房间用户信息：保存用户名称与就绪状态，可整体复制并随房间数据同步。
##
## Information about a room user: the user name and ready state. It can be
## copied as a whole and is synced together with the room data.
class_name UserInformation

## 用户名称，默认“未知”。
##
## The user name, "未知" (unknown) by default.
var user_name:String="未知"
## 用户是否已就绪。
##
## Whether the user is ready.
var is_ready:bool=false


## 从字典导入用户信息。
##
## Imports the user information from [param data].
func import_data(data:Dictionary):
	user_name=data.get("user_name","未知")
	is_ready=data.get("is_ready",false)
## 将用户信息导出为字典。
##
## Exports the user information as a dictionary.
func export_data()->Dictionary:
	return {
		"user_name":user_name,
		"is_ready":is_ready
	}

## 将用户名称导出为字节流。
##
## Exports the user name as a byte stream.
func export_bytes()->PackedByteArray:
	var buffer:ByteBuffer=ByteBuffer.new()
	buffer.put_string(user_name)
	return buffer.data
## 从字节流导入用户名称。
##
## Imports the user name from a byte stream.
func import_bytes(data: PackedByteArray):
	var buffer:ByteBuffer=ByteBuffer.new(data)
	user_name=buffer.get_string()



## 返回便于调试输出的字符串。
##
## Returns a debug-friendly string representation.
func _to_string() -> String:
	return str(export_data())

## 返回一份用户信息的深拷贝。
##
## Returns a deep copy of this user information.
func copy()->UserInformation:
	var new_information:UserInformation=UserInformation.new()
	new_information.user_name=self.user_name
	new_information.is_ready=self.is_ready
	return new_information
