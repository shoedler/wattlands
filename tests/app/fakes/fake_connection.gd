extends FtmsConnectionManager
## Test double of FtmsConnectionManager: records scans, connects and disconnects.

var scans: Array[float] = []
var connects: Array[String] = []
var disconnects: int = 0


func scan(seconds: float = 10.0) -> void:
	scans.append(seconds)


func connect_to(address: String) -> void:
	connects.append(address)


func disconnect_trainer() -> void:
	disconnects += 1
