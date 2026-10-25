extends SceneTree

## 请求执行测试：过滤器链、集中执行接口与请求的实际执行效果。
##
## Request execution tests: the filter chain, the centralized execution entry
## point and the actual effect of executing requests.

var failures: int = 0

const CALL_TARGET_SCRIPT := "res://tests/fixtures/call_target.gd"


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


class ProbeRequest extends Request:
	var log_ref: Array = []
	var allow: bool = true
	var executed: int = 0
	func can_execute() -> bool:
		log_ref.append("request")
		return allow
	func execute() -> void:
		executed += 1


class BlockedRequest extends Request:
	var executed: int = 0
	func can_execute() -> bool:
		return false
	func execute() -> void:
		executed += 1


class AsyncRequest extends Request:
	var finished: bool = false
	func execute() -> void:
		await Engine.get_main_loop().create_timer(0.02).timeout
		finished = true


class ProbeFilter extends RequestFilter:
	var log_ref: Array = []
	var tag: String = "filter"
	var allow: bool = true
	func can_execute(_request: Request) -> bool:
		log_ref.append(tag)
		return allow


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_filters_and_execution()
	await _test_request_effects()
	_test_exec_ignored_before_ready()
	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)


func _test_exec_ignored_before_ready() -> void:
	var net := NetworkInstance.new()
	net.network_mode = NetworkInstance.NetworkMode.CLIENT_JOINING

	var request := ProbeRequest.new()
	request.log_ref = []
	var notice := NoticeExecRequest.new()
	notice.request = request
	net.get_notice(NetworkInstance.SERVER_ID, notice)
	check(request.executed == 0, "exec request ignored while joining")

	var immediate_request := ProbeRequest.new()
	immediate_request.log_ref = []
	var immediate := NoticeExecRequestImmediately.new()
	immediate.request = immediate_request
	net.get_notice(NetworkInstance.SERVER_ID, immediate)
	check(immediate_request.executed == 0, "immediate exec ignored while joining")


func _test_filters_and_execution() -> void:
	var net := NetworkInstance.new()
	var log: Array = []

	# 无过滤器：询问请求自身后执行
	var req := ProbeRequest.new()
	req.log_ref = log
	check(await net.execute_request(req) == true, "no filter: executed")
	check(req.executed == 1, "no filter: execute called once")
	check(log == ["request"], "no filter: request can_execute asked")

	# 过滤器按顺序询问，全部同意才询问请求
	log.clear()
	var allow_a := ProbeFilter.new()
	allow_a.log_ref = log
	allow_a.tag = "a"
	var allow_b := ProbeFilter.new()
	allow_b.log_ref = log
	allow_b.tag = "b"
	net.add_request_filter(allow_a)
	net.add_request_filter(allow_b)
	var req2 := ProbeRequest.new()
	req2.log_ref = log
	check(await net.execute_request(req2) == true, "all filters allow: executed")
	check(log == ["a", "b", "request"], "filter order: a -> b -> request")

	# 任一过滤器拒绝：短路，不询问后续过滤器与请求自身
	log.clear()
	allow_a.allow = false
	var req3 := ProbeRequest.new()
	req3.log_ref = log
	check(await net.execute_request(req3) == false, "deny filter: returns false")
	check(req3.executed == 0, "deny filter: not executed")
	check(log == ["a"], "deny filter: short-circuits")

	# 请求自身拒绝执行
	log.clear()
	allow_a.allow = true
	var req4 := ProbeRequest.new()
	req4.log_ref = log
	req4.allow = false
	check(await net.execute_request(req4) == false, "request can_execute false: returns false")
	check(req4.executed == 0, "request can_execute false: not executed")

	# 阻塞型请求
	var blocked := BlockedRequest.new()
	check(await net.execute_request(blocked) == false, "blocked request: returns false")
	check(blocked.executed == 0, "blocked request: not executed")

	# null 请求
	check(await net.execute_request(null) == false, "null request returns false")

	# 异步 execute 会被 await 等待完成
	var async_req := AsyncRequest.new()
	check(await net.execute_request(async_req) == true, "async request: returns true")
	check(async_req.finished, "async request: awaited until finished")

	# 过滤器重复添加与移除
	var dup := ProbeFilter.new()
	net.add_request_filter(dup)
	net.add_request_filter(dup)
	check(net.request_filters.count(dup) == 1, "duplicate filter ignored")
	net.remove_request_filter(dup)
	check(not net.request_filters.has(dup), "filter removed")


func _test_request_effects() -> void:
	var net := NetworkInstance.new()
	var target_script: Script = load(CALL_TARGET_SCRIPT)
	var target = target_script.new()
	target.name = "CallTarget"
	root.add_child(target)

	# RequestCall：按顺序调用节点方法
	var request := RequestCall.new()
	request.add_call(target, "record", 1)
	request.add_call(target, "record", "two")
	check(await net.execute_request(request) == true, "RequestCall executed")
	check(target.log == [1, "two"], "RequestCall calls in order")

	# RequestPacked：多个请求按顺序执行
	var first := RequestCall.new()
	first.add_call(target, "record", "A")
	var second := RequestCall.new()
	second.add_call(target, "record", "B")
	var packed: Request = net.pack_request(first, second)
	check(packed is RequestPacked, "requests packed")
	check(await net.execute_request(packed) == true, "RequestPacked executed")
	check(target.log == [1, "two", "A", "B"], "RequestPacked preserves order")

	# 过滤器拦截 RequestCall 时不会产生副作用
	var deny := ProbeFilter.new()
	deny.allow = false
	net.add_request_filter(deny)
	var blocked_call := RequestCall.new()
	blocked_call.add_call(target, "record", "blocked")
	check(await net.execute_request(blocked_call) == false, "denied RequestCall blocked")
	check(target.log == [1, "two", "A", "B"], "denied RequestCall has no effect")
	net.remove_request_filter(deny)

	# RequestFreeNode：下一帧真正释放节点
	var victim = target_script.new()
	victim.name = "Victim"
	root.add_child(victim)
	var free_request := RequestFreeNode.new()
	free_request.node_path = victim.get_path()
	check(await net.execute_request(free_request) == true, "RequestFreeNode executed")
	check(is_instance_valid(victim), "RequestFreeNode queued (still valid this frame)")
	await process_frame
	await process_frame
	check(not is_instance_valid(victim), "RequestFreeNode freed target")
