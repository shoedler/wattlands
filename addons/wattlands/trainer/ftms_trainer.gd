class_name FtmsTrainer
extends TrainerDevice
## A real FTMS trainer (KICKR CORE, KICKR CORE 2) behind the TrainerDevice interface
## (BRIEF 4.1). Owned by trainer-core; public API frozen after W0.
## Turns setter calls into FtmsCodec control-point payloads and hands them to
## FtmsClient.write_control() (the only caller, 4.6.11); turns bike data into
## TrainerSamples (cadence estimated from speed when absent or stale, BRIEF 4.5).


static func create(_client: FtmsClient, _name: String = "") -> FtmsTrainer:
	return FtmsTrainer.new()


func client() -> FtmsClient:
	return null
