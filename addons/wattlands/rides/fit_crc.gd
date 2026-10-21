class_name FitCrc
extends RefCounted
## The FIT SDK's CRC-16 (BRIEF 3.8): CRC-16/ARC (reflected polynomial 0xA001, initial value 0),
## computed a nibble at a time with the SDK's 16-entry table. Used for the 14-byte header's CRC
## (over bytes 0..11) and the file CRC (over the header and every data byte). Pure and
## deterministic.

const TABLE: Array[int] = [
	0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
	0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
]


## The CRC after one more byte.
static func update(crc: int, byte: int) -> int:
	var tmp: int = TABLE[crc & 0xF]
	crc = (crc >> 4) & 0x0FFF
	crc = crc ^ tmp ^ TABLE[byte & 0xF]
	tmp = TABLE[crc & 0xF]
	crc = (crc >> 4) & 0x0FFF
	crc = crc ^ tmp ^ TABLE[(byte >> 4) & 0xF]
	return crc & 0xFFFF


## CRC of bytes[from, to) (to = -1: the end), continuing from `crc`.
static func compute(bytes: PackedByteArray, from: int = 0, to: int = -1, crc: int = 0) -> int:
	var end := bytes.size() if to < 0 else mini(to, bytes.size())
	for i in range(maxi(from, 0), end):
		crc = update(crc, bytes[i])
	return crc


## True if `bytes` is a FIT file whose header CRC (when not zero) and file CRC are valid.
static func file_is_valid(bytes: PackedByteArray) -> bool:
	if bytes.size() < 14:
		return false
	var header_size := bytes[0]
	if header_size != 12 and header_size != 14:
		return false
	var data_size := bytes.decode_u32(4)
	if bytes.size() < header_size + data_size + 2:
		return false
	if header_size == 14:
		var hcrc := bytes.decode_u16(12)
		if hcrc != 0 and hcrc != compute(bytes, 0, 12):
			return false
	var end := header_size + data_size
	return bytes.decode_u16(end) == compute(bytes, 0, end)
