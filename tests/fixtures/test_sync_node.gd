extends SyncNode

## 测试用同步节点：就绪状态由集成测试轮询检查。
##
## Test synchronized node; its ready state is polled by the integration test.

## 返回自动加载的网络实例。
##
## Returns the auto-loaded network instance.
func get_network() -> NetworkInstance:
	return Engine.get_main_loop().root.get_node("Network")
