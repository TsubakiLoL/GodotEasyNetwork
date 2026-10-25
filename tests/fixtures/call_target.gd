extends Node

## 测试用调用目标：记录收到的调用参数，供 RequestCall 执行测试使用。
##
## Test call target: records the arguments it receives, used by the RequestCall
## execution tests.

## 按调用顺序记录收到的参数。
##
## Received arguments, in call order.
var log: Array = []


## 记录一次调用。
##
## Records one call.
func record(value) -> void:
	log.append(value)
