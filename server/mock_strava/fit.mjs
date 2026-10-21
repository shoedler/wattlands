// FIT header and CRC check for the mock Strava server (BRIEF 3.8). Zero dependencies.
//
// fitCrc16 is the FIT SDK's CRC-16 (CRC-16/ARC: reflected polynomial 0xA001, initial 0),
// computed a nibble at a time with the SDK's table. checkFit validates the file header
// (12 or 14 bytes, ".FIT", the header CRC when present and non-zero), the data size and the
// file CRC. It does not decode messages; tools/fit_check does that.

const CRC_TABLE = [
  0x0000, 0xcc01, 0xd801, 0x1400, 0xf001, 0x3c00, 0x2800, 0xe401,
  0xa001, 0x6c00, 0x7800, 0xb401, 0x5000, 0x9c01, 0x8801, 0x4400,
];

/** CRC-16 of buf[start, end), continuing from `crc`. */
export function fitCrc16(buf, start = 0, end = buf.length, crc = 0) {
  for (let i = start; i < end; i++) {
    const byte = buf[i];
    let tmp = CRC_TABLE[crc & 0xf];
    crc = (crc >> 4) & 0x0fff;
    crc = crc ^ tmp ^ CRC_TABLE[byte & 0xf];
    tmp = CRC_TABLE[crc & 0xf];
    crc = (crc >> 4) & 0x0fff;
    crc = crc ^ tmp ^ CRC_TABLE[(byte >> 4) & 0xf];
  }
  return crc & 0xffff;
}

/**
 * Checks a FIT file's header and CRCs.
 * @param {Uint8Array} buf
 * @returns {{ok: boolean, error: string|null, headerSize?: number, dataSize?: number,
 *   protocolVersion?: number, profileVersion?: number}}
 */
export function checkFit(buf) {
  if (!buf || buf.length < 12) return { ok: false, error: 'too short for a FIT header' };
  const headerSize = buf[0];
  if (headerSize !== 12 && headerSize !== 14) {
    return { ok: false, error: `bad header size ${headerSize}` };
  }
  if (buf.length < headerSize + 2) return { ok: false, error: 'too short' };
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const protocolVersion = buf[1];
  const profileVersion = view.getUint16(2, true);
  const dataSize = view.getUint32(4, true);
  const dataType = String.fromCharCode(buf[8], buf[9], buf[10], buf[11]);
  const info = { headerSize, dataSize, protocolVersion, profileVersion };
  if (dataType !== '.FIT') return { ok: false, error: `bad data type ${JSON.stringify(dataType)}`, ...info };
  if (headerSize === 14) {
    const headerCrc = view.getUint16(12, true);
    if (headerCrc !== 0 && headerCrc !== fitCrc16(buf, 0, 12)) {
      return { ok: false, error: 'header CRC mismatch', ...info };
    }
  }
  const end = headerSize + dataSize;
  if (buf.length < end + 2) return { ok: false, error: 'data size exceeds the file', ...info };
  const fileCrc = view.getUint16(end, true);
  if (fileCrc !== fitCrc16(buf, 0, end)) return { ok: false, error: 'file CRC mismatch', ...info };
  return { ok: true, error: null, ...info };
}
