extends "res://tests/ble/fake_transport.gd"
## A heart rate sensor behind the scriptable transport double: discover_services() answers
## with the Heart Rate service (or `services` when set), and every GATT call is recorded, so
## tests can assert that the sensor is subscribed to and never written to.

const HR_SERVICE := "0000180d-0000-1000-8000-00805f9b34fb"
const HR_MEASUREMENT := "00002a37-0000-1000-8000-00805f9b34fb"

## What discover_services() reports; null means the standard Heart Rate service.
var services: Variant = null


func discover_services() -> void:
	calls.append(["discover_services"])
	var list: Array = (
		services
		if services is Array
		else [
			{
				"uuid": HR_SERVICE,
				"characteristics": [{"uuid": HR_MEASUREMENT, "properties": ["notify"]}]
			}
		]
	)
	services_discovered.emit(list)


func subscribe_characteristic(service_uuid: String, char_uuid: String) -> void:
	calls.append(["subscribe_characteristic", service_uuid, char_uuid])


func read_characteristic(service_uuid: String, char_uuid: String) -> void:
	calls.append(["read_characteristic", service_uuid, char_uuid])


func write_characteristic(
	service_uuid: String, char_uuid: String, data: PackedByteArray, with_response: bool
) -> void:
	calls.append(["write_characteristic", service_uuid, char_uuid, data, with_response])


## A Heart Rate Measurement notification.
func measure(data: PackedByteArray) -> void:
	characteristic_notified.emit(HR_MEASUREMENT, data)
