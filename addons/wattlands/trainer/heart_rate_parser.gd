class_name HeartRateParser
extends RefCounted
## Parses the Bluetooth Heart Rate Measurement characteristic 0x2A37 (Heart Rate service
## 0x180D), the profile chest straps and watches broadcasting heart rate share. Pure.
##
## Layout: flags (uint8), then the heart rate (uint8, or uint16 little-endian when flags
## bit 0 is set), then the energy expended (uint16, kJ, when bit 3 is set), then RR intervals
## (uint16 each, when bit 4 is set; ignored). Flags bits 1-2 are the sensor contact status:
## bit 2 says the sensor supports contact detection, bit 1 then says whether it has contact.

const FLAG_HR_UINT16 := 0x01
const FLAG_CONTACT_DETECTED := 0x02
const FLAG_CONTACT_SUPPORTED := 0x04
const FLAG_ENERGY := 0x08
const FLAG_RR := 0x10


## {ok, bpm, contact_supported, contact, energy_j (-1 when absent)}. ok is false (with a
## push_warning) for data too short for its flags.
static func parse(data: PackedByteArray) -> Dictionary:
	var out := {"ok": false, "bpm": 0, "contact_supported": false, "contact": false, "energy_j": -1}
	if data.is_empty():
		push_warning("HeartRateParser: empty heart rate measurement")
		return out
	var flags := data[0]
	var wide := (flags & FLAG_HR_UINT16) != 0
	var i := 1
	var need := i + (2 if wide else 1)
	if data.size() < need:
		push_warning("HeartRateParser: heart rate measurement too short (%d bytes)" % data.size())
		return out
	var bpm := data.decode_u16(i) if wide else data[i]
	i = need
	var energy := -1
	if (flags & FLAG_ENERGY) != 0:
		if data.size() < i + 2:
			push_warning("HeartRateParser: energy expended field missing")
			return out
		energy = data.decode_u16(i) * 1000
		i += 2
	out["ok"] = true
	out["bpm"] = bpm
	out["contact_supported"] = (flags & FLAG_CONTACT_SUPPORTED) != 0
	out["contact"] = (flags & FLAG_CONTACT_DETECTED) != 0
	out["energy_j"] = energy
	return out
