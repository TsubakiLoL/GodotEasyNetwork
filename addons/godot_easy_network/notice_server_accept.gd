extends Message

## 服务端向新加入的合法客户端发送的确认包。
##
## 客户端只有收到该包后才开始同步自身信息，避免在服务器拒绝新连接
## （[member NetworkInstance.refuse_new_connections]）时仍发包导致报错。
##
## Acceptance notice sent by the server to a newly connected client. The client
## starts syncing its own information only after receiving it, so it does not
## send packets while the server is refusing new connections.
class_name NoticeServerAccept
