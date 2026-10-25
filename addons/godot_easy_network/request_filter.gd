## 请求执行过滤器抽象基类。
##
## 继承本类并实现 [method can_execute]，再通过
## [method NetworkInstance.add_request_filter] 注册，即可对所有请求的执行入口
## [method NetworkInstance.execute_request] 统一拦截 / 放行请求。
## 过滤器只负责判断、不负责执行；多个过滤器按添加顺序依次询问，
## 任意一个返回 [code]false[/code] 即拦截该请求。
##
## Abstract base class for request execution filters. Extend it, implement
## [method can_execute] and register it with
## [method NetworkInstance.add_request_filter]; every request execution goes
## through [method NetworkInstance.execute_request], which asks the filters
## first. Filters only decide, they never execute. Filters are queried in the
## order they were added, and the first one returning [code]false[/code] blocks
## the request.
@abstract
extends RefCounted
class_name RequestFilter


## 抽象方法：是否允许执行该请求。
##
## [param request] 即将执行的请求。
##
## Abstract method: returns whether [param request] may be executed.
@abstract func can_execute(request: Request) -> bool
