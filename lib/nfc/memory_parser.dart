/// Interprets raw MIFARE Classic / Ultralight memory so that each block
/// carries a plain-language note (trailer, value block, text, empty...).
library;

import 'hex.dart';
import 'models.dart';

/// First block number of a MIFARE Classic sector (sectors 32+ on 4K cards
/// have 16 blocks instead of 4).
int classicFirstBlock(int sector) => sector < 32 ? sector * 4 : 128 + (sector - 32) * 16;

/// Splits a sector's bytes into annotated 16-byte blocks.
List<MemoryBlock> parseClassicSector(int sector, List<int> data) {
  const blockSize = 16;
  final count = data.length ~/ blockSize;
  final first = classicFirstBlock(sector);
  final trailer = count > 0 ? data.sublist((count - 1) * blockSize, count * blockSize) : <int>[];
  final access = trailer.length == 16 ? decodeAccessBits(trailer.sublist(6, 9)) : null;
  final hasMad = sector == 0 && trailer.length == 16 && (trailer[9] & 0x80) != 0;

  return [
    for (var i = 0; i < count; i++)
      MemoryBlock(
        first + i,
        data.sublist(i * blockSize, (i + 1) * blockSize),
        note: i == count - 1
            ? describeTrailer(trailer, access, dataBlocks: count - 1)
            : sector == 0 && i == 0
                ? describeManufacturerBlock(data.sublist(0, 16))
                : hasMad && (i == 1 || i == 2)
                    ? 'MIFARE Application Directory (lists which app owns each sector)'
                    : describeDataBlock(data.sublist(i * blockSize, (i + 1) * blockSize)),
      ),
  ];
}

String describeManufacturerBlock(List<int> b) {
  final uid = b.sublist(0, 4);
  final bccOk = (uid[0] ^ uid[1] ^ uid[2] ^ uid[3]) == b[4];
  return 'Manufacturer block - UID ${bytesToHex(uid)}, '
      'check byte ${bccOk ? 'valid' : 'does not match (7-byte UID or modified card)'}';
}

/// Per-block access conditions decoded from trailer bytes 6-8, or null if
/// the inverted copies don't match (corrupt / unreadable trailer).
List<int>? decodeAccessBits(List<int> b) {
  final c1 = (b[1] >> 4) & 0x0F;
  final c2 = b[2] & 0x0F;
  final c3 = (b[2] >> 4) & 0x0F;
  final c1Inv = b[0] & 0x0F;
  final c2Inv = (b[0] >> 4) & 0x0F;
  final c3Inv = b[1] & 0x0F;
  if (c1 != (~c1Inv & 0x0F) || c2 != (~c2Inv & 0x0F) || c3 != (~c3Inv & 0x0F)) {
    return null;
  }
  // Index 0..2 = data block groups, 3 = trailer; value = C1C2C3 as 3 bits.
  return [
    for (var i = 0; i < 4; i++)
      (((c1 >> i) & 1) << 2) | (((c2 >> i) & 1) << 1) | ((c3 >> i) & 1),
  ];
}

/// Access rights for a data block, per the MIFARE Classic datasheet.
String describeDataAccess(int bits) => switch (bits) {
  0 => 'read/write with key A or B',
  2 => 'read-only (key A or B)',
  4 => 'read with A or B, write with B',
  6 => 'value block: read A/B, increment B, decrement A/B',
  1 => 'value block: read A/B, decrement only',
  3 => 'read/write with key B only',
  5 => 'read with key B only',
  7 => 'no access',
  _ => 'unknown',
};

String describeTrailer(List<int> t, List<int>? access, {required int dataBlocks}) {
  if (t.length != 16) return 'Sector trailer';
  final buf = StringBuffer('Sector trailer (keys + access rules). ');
  if (access == null) {
    buf.write('Access bits are invalid.');
    return buf.toString();
  }
  // On 16-block sectors each access group covers 5 blocks.
  final groupLabel = dataBlocks > 3 ? 'blocks group' : 'block';
  for (var g = 0; g < 3; g++) {
    buf.write('$groupLabel ${g + 1}: ${describeDataAccess(access[g])}. ');
  }
  if (access.take(3).every((a) => a == 0) && access[3] == 1) {
    buf.write('(Factory default "transport" configuration.)');
  }
  return buf.toString().trim();
}

/// Plain-language guess at what a 16-byte data block holds.
String describeDataBlock(List<int> b) {
  if (b.every((x) => x == 0x00)) return 'Empty (all zeros)';
  if (b.every((x) => x == 0xFF)) return 'Empty (all FF)';
  final value = decodeValueBlock(b);
  if (value != null) return 'Value block: ${value.$1} (backup address ${value.$2})';
  final trimmed = _trimPadding(b);
  if (trimmed.length >= 3 && isMostlyPrintable(trimmed)) {
    return 'Text: "${bytesToAscii(trimmed)}"';
  }
  return 'Binary data';
}

/// MIFARE value block format: value, ~value, value, addr, ~addr, addr, ~addr.
/// Returns (signed 32-bit value, address) or null.
(int, int)? decodeValueBlock(List<int> b) {
  if (b.length != 16) return null;
  for (var i = 0; i < 4; i++) {
    if (b[i] != b[i + 8] || b[i] != (~b[i + 4] & 0xFF)) return null;
  }
  if (b[12] != b[14] || b[13] != b[15] || b[12] != (~b[13] & 0xFF)) return null;
  var v = b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24);
  if (v & 0x80000000 != 0) v -= 0x100000000;
  return (v, b[12]);
}

/// Annotates the 4-byte pages of a MIFARE Ultralight / NTAG tag.
List<MemoryBlock> parseUltralightPages(List<int> data) => [
  for (var p = 0; p * 4 + 4 <= data.length; p++)
    MemoryBlock(p, data.sublist(p * 4, p * 4 + 4), note: describeUltralightPage(p, data.sublist(p * 4, p * 4 + 4))),
];

String describeUltralightPage(int page, List<int> b) => switch (page) {
  0 => 'Serial number part 1 (manufacturer + UID) + check byte',
  1 => 'Serial number part 2',
  2 => 'Check byte, internal, lock bytes ${bytesToHex(b.sublist(2))}'
      '${b[2] == 0 && b[3] == 0 ? ' (nothing locked)' : ' (some pages locked)'}',
  3 => describeCapabilityContainer(b),
  _ => b.every((x) => x == 0)
      ? 'Empty'
      : isMostlyPrintable(b)
          ? 'User data: "${bytesToAscii(b)}"'
          : 'User data',
};

/// NFC Forum Type 2 capability container (page 3).
String describeCapabilityContainer(List<int> b) {
  if (b[0] != 0xE1) {
    return b.every((x) => x == 0) ? 'Capability container: empty (not NDEF formatted)' : 'One-time-programmable bytes';
  }
  final access = switch (b[3]) {
    0x00 => 'read/write',
    0x0F => 'read-only',
    _ => 'access 0x${b[3].toRadixString(16).toUpperCase()}',
  };
  return 'Capability container: NDEF v${b[1] >> 4}.${b[1] & 0x0F}, '
      '${b[2] * 8} bytes data area, $access';
}

List<int> _trimPadding(List<int> b) {
  var end = b.length;
  while (end > 0 && (b[end - 1] == 0x00 || b[end - 1] == 0xFF)) {
    end--;
  }
  return b.sublist(0, end);
}
