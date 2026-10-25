extends Message

## 可序列化请求的总类：所有由网络层分发的操作都继承自它。
##
## Base class for serializable requests. Every operation dispatched by the
## network layer derives from it.
class_name Request


## 请求自身是否允许执行（例如目标节点是否仍然存在）。
##
## Returns whether the request is allowed to execute on its own, for example
## whether its target node still exists.
func can_execute()->bool:
	
	return true

## 执行请求的实际逻辑，由子类按需重写；可以是协程。
##
## Executes the request. Subclasses override it as needed; it may be a
## coroutine.
func execute():
	pass
