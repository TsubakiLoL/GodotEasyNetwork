extends Node

## 测试用生成器：通过 RequestCall 在所有端创建测试同步节点。
##
## Test spawner: creates the test synchronized node on every peer through a
## RequestCall.


## 在场景树根下创建一个测试同步节点。
##
## Creates a test synchronized node under the scene tree root.
func spawn_sync_node() -> void:
	var script: Script = load("res://tests/fixtures/test_sync_node.gd")
	var node = script.new()
	node.name = "SyncTarget"
	Engine.get_main_loop().root.add_child(node)
