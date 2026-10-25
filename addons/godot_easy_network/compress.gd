## 压缩工具类：在压缩数据前附带原始长度，解压时用于恢复与校验长度。
##
## Compression helper. It prefixes the compressed payload with the original
## length so the decompressed size can be restored when decoding.
class_name Compress

## 压缩数据，返回“原始长度 + 压缩数据”的字节流。
##
## Compresses [param data] and returns the original length followed by the
## compressed payload.
static func com(data:PackedByteArray)->PackedByteArray:
	var bytes:ByteBuffer=ByteBuffer.new()
	bytes.put_int(data.size())
	bytes.put_packed_byte_array(data.compress())
	return bytes.data

## 解压由 [method com] 生成的字节流。
##
## Decompresses a byte stream produced by [method com].
static func decom(data:PackedByteArray)->PackedByteArray:
	var bytes:ByteBuffer=ByteBuffer.new(data)
	var size:int=bytes.get_int()
	var buf:PackedByteArray=bytes.get_packed_byte_array()
	var result:PackedByteArray=buf.decompress(size)
	return result
