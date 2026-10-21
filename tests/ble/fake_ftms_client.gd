extends FtmsClient
## FtmsClient double for FtmsConnectionManager tests: records attach() and begin(), and
## answers begin() with client_ready (or nothing, for timeout tests). Never writes.

var attached: Array[BleTransport] = []
var begin_count: int = 0
## begin(): "ready", "control_lost", "fail" or "silent"
var begin_result: String = "ready"
var fail_reason: String = "subscribe failed"


func attach(transport: BleTransport) -> void:
	attached.append(transport)


func begin() -> void:
	begin_count += 1
	match begin_result:
		"ready":
			client_ready.emit()
		"control_lost":
			control_lost.emit("Request Control: control not permitted (0x05)")
		"fail":
			failed.emit(fail_reason)
		_:
			pass
