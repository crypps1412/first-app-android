/// Small byte/hex helpers used by every parser.
library;

import 'dart:typed_data';

/// Parses `"04A2FF"`, `"04:a2:ff"` or `"04 A2 FF"` into bytes.
/// Returns an empty list for empty, `unknown` or malformed input.
Uint8List hexToBytes(String? hex) {
  if (hex == null) return Uint8List(0);
  final clean = hex.replaceAll(RegExp(r'[\s:\-]'), '');
  if (clean.isEmpty ||
      clean.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
    return Uint8List(0);
  }
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// `[0x04, 0xA2]` -> `"04:A2"` (or `"04A2"` with an empty separator).
String bytesToHex(List<int> bytes, {String separator = ':'}) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(separator);

/// Printable ASCII view of [bytes]; non-printable bytes become `.`.
String bytesToAscii(List<int> bytes) => String.fromCharCodes(
  bytes.map((b) => b >= 0x20 && b < 0x7F ? b : 0x2E),
);

/// True when the bytes look like readable text (allows tabs/newlines).
bool isMostlyPrintable(List<int> bytes) {
  if (bytes.isEmpty) return false;
  final printable = bytes
      .where((b) => (b >= 0x20 && b < 0x7F) || b == 0x09 || b == 0x0A || b == 0x0D || b >= 0x80)
      .length;
  return printable / bytes.length >= 0.9;
}

/// Unsigned big-endian integer from [bytes], as a decimal string.
/// Uses BigInt so 7- and 10-byte UIDs don't overflow.
String bytesToDecimal(List<int> bytes) {
  var value = BigInt.zero;
  for (final b in bytes) {
    value = (value << 8) | BigInt.from(b);
  }
  return value.toString();
}
