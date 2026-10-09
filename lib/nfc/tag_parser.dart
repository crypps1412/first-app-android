/// Turns the raw [NFCTag] metadata into labelled, human-readable fields.
library;

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

import 'hex.dart';
import 'models.dart';

/// IC manufacturer codes from ISO/IEC 7816-6 (first UID byte of 7-byte
/// ISO 14443-A UIDs and second byte of ISO 15693 UIDs).
const Map<int, String> _manufacturers = {
  0x01: 'Motorola',
  0x02: 'STMicroelectronics',
  0x03: 'Hitachi',
  0x04: 'NXP Semiconductors',
  0x05: 'Infineon Technologies',
  0x06: 'Cylink',
  0x07: 'Texas Instruments',
  0x08: 'Fujitsu',
  0x09: 'Matsushita',
  0x0A: 'NEC',
  0x0B: 'Oki Electric',
  0x0C: 'Toshiba',
  0x0D: 'Mitsubishi Electric',
  0x0E: 'Samsung Electronics',
  0x0F: 'Hynix',
  0x10: 'LG Semiconductors',
  0x16: 'EM Microelectronic-Marin',
  0x1F: 'Melexis',
  0x2B: 'Maxim Integrated',
  0x33: 'AMIC',
  0x44: 'GenTag',
  0x88: 'Infineon Technologies (cascade)',
};

/// SAK byte -> likely chip family (NXP AN10833).
String? describeSak(int sak) => switch (sak) {
  0x00 => 'MIFARE Ultralight / NTAG family',
  0x01 => 'TNP3xxx (MIFARE Classic based)',
  0x08 => 'MIFARE Classic 1K',
  0x09 => 'MIFARE Mini',
  0x10 => 'MIFARE Plus 2K (SL2)',
  0x11 => 'MIFARE Plus 4K (SL2)',
  0x18 => 'MIFARE Classic 4K',
  0x20 => 'ISO 14443-4 smart card (DESFire, Plus SL3, JavaCard, payment card...)',
  0x28 => 'Smart card with MIFARE Classic 1K emulation',
  0x38 => 'Smart card with MIFARE Classic 4K emulation',
  _ => null,
};

/// Friendly name for the technology family reported by the plugin.
String describeTagType(NFCTagType type) => switch (type) {
  NFCTagType.mifare_classic => 'MIFARE Classic',
  NFCTagType.mifare_ultralight => 'MIFARE Ultralight / NTAG',
  NFCTagType.mifare_desfire => 'MIFARE DESFire',
  NFCTagType.mifare_plus => 'MIFARE Plus',
  NFCTagType.iso7816 => 'Smart card (ISO 7816 / ISO-DEP)',
  NFCTagType.iso15693 => 'Vicinity tag (ISO 15693 / NFC-V)',
  NFCTagType.iso18092 => 'FeliCa (ISO 18092 / NFC-F)',
  NFCTagType.webusb => 'WebUSB reader',
  NFCTagType.unknown => 'Unknown tag',
};

/// Manufacturer encoded in the UID, when the UID format carries one.
String? manufacturerFromUid(List<int> uid, NFCTagType type) {
  int? code;
  if (type == NFCTagType.iso15693 && uid.length == 8) {
    // ISO 15693 UIDs start with 0xE0, then the manufacturer. Android may
    // report the bytes least-significant first, so accept both orders.
    if (uid.first == 0xE0) code = uid[1];
    if (uid.last == 0xE0) code = uid[6];
  } else if (uid.length == 7 || uid.length == 10) {
    code = uid.first;
  }
  if (code == null) return null;
  return _manufacturers[code] ??
      'Unknown (code 0x${code.toRadixString(16).padLeft(2, '0').toUpperCase()})';
}

/// Best one-line description of the card for the result header.
String cardTitle(NFCTag tag) {
  final mifare = tag.mifareInfo;
  if (mifare != null) return mifareName(mifare);
  final sak = hexToBytes(tag.sak);
  if (sak.isNotEmpty) {
    final fromSak = describeSak(sak.first);
    if (fromSak != null && !fromSak.contains('...')) return fromSak;
  }
  return describeTagType(tag.type);
}

/// Readable chip name from the plugin's MIFARE type string
/// (`classic`, `plus`, `pro`, `ultralight`, `ultralight_c`, `*_unknown`).
String mifareName(MifareInfo m) {
  final base = switch (m.type) {
    'classic' => 'MIFARE Classic',
    'classic_unknown' => 'MIFARE Classic compatible',
    'plus' => 'MIFARE Plus',
    'pro' => 'MIFARE Pro',
    'ultralight' => 'MIFARE Ultralight / NTAG',
    'ultralight_c' => 'MIFARE Ultralight C',
    'ultralight_unknown' => 'MIFARE Ultralight family',
    _ => 'MIFARE ${m.type}',
  };
  if (m.sectorCount == null) return base;
  final size = switch (m.size) {
    320 => ' Mini',
    1024 => ' 1K',
    2048 => ' 2K',
    4096 => ' 4K',
    _ => '',
  };
  return '$base$size';
}

/// Identity + low-level protocol fields of the tag.
List<InfoSection> describeTag(NFCTag tag) {
  final uid = hexToBytes(tag.id);
  final identity = <InfoField>[
    InfoField('Card type', describeTagType(tag.type)),
    if (tag.standard.isNotEmpty && tag.standard != 'unknown')
      InfoField('Standard', tag.standard),
    if (uid.isNotEmpty) ...[
      InfoField('UID (hex)', bytesToHex(uid), monospace: true),
      InfoField('UID (decimal)', bytesToDecimal(uid), monospace: true),
      InfoField(
        'UID (decimal, reversed)',
        bytesToDecimal(uid.reversed.toList()),
        monospace: true,
      ),
      InfoField('UID length', '${uid.length} bytes${_uidKind(uid)}'),
    ] else
      const InfoField('UID', 'Not available'),
    if (manufacturerFromUid(uid, tag.type) case final m?)
      InfoField('Chip manufacturer', m),
  ];

  final protocol = <InfoField>[
    if (_nonEmpty(tag.atqa)) InfoField('ATQA', tag.atqa!.toUpperCase(), monospace: true),
    if (_nonEmpty(tag.sak))
      InfoField(
        'SAK',
        '${tag.sak!.toUpperCase()}'
            '${_suffix(describeSak(hexToBytes(tag.sak).firstOrNull ?? -1))}',
        monospace: true,
      ),
    if (_nonEmpty(tag.historicalBytes))
      _hexWithText('Historical bytes', tag.historicalBytes!),
    if (_nonEmpty(tag.hiLayerResponse))
      _hexWithText('Higher-layer response', tag.hiLayerResponse!),
    if (_nonEmpty(tag.protocolInfo))
      InfoField('Protocol info', tag.protocolInfo!.toUpperCase(), monospace: true),
    if (_nonEmpty(tag.applicationData))
      InfoField('Application data', tag.applicationData!.toUpperCase(), monospace: true),
    if (_nonEmpty(tag.manufacturer))
      InfoField('FeliCa manufacturer (PMm)', tag.manufacturer!.toUpperCase(), monospace: true),
    if (_nonEmpty(tag.systemCode))
      InfoField('FeliCa system code', _feliCaSystem(tag.systemCode!)),
    if (_nonEmpty(tag.dsfId)) InfoField('DSFID', tag.dsfId!.toUpperCase(), monospace: true),
  ];

  final mifare = tag.mifareInfo;
  final storage = <InfoField>[
    if (mifare != null) ...[
      InfoField('Chip', mifareName(mifare)),
      if (mifare.size > 0) InfoField('Memory size', _bytes(mifare.size)),
      if (mifare.sectorCount != null && mifare.sectorCount! > 0)
        InfoField('Sectors', '${mifare.sectorCount}'),
      if (mifare.blockCount > 0)
        InfoField(
          tag.type == NFCTagType.mifare_classic ? 'Blocks' : 'Pages',
          '${mifare.blockCount} × ${mifare.blockSize} bytes',
        ),
    ],
    InfoField(
      'NDEF formatted',
      switch (tag.ndefAvailable) {
        true => 'Yes',
        false => 'No',
        null => 'Unknown',
      },
    ),
    if (tag.ndefAvailable == true) ...[
      if (_nonEmpty(tag.ndefType)) InfoField('NDEF tag type', tag.ndefType!),
      if (tag.ndefCapacity != null) InfoField('NDEF capacity', _bytes(tag.ndefCapacity!)),
      if (tag.ndefWritable != null)
        InfoField('Writable', tag.ndefWritable! ? 'Yes' : 'No (read-only)'),
    ],
  ];

  return [
    InfoSection('Identity', identity),
    if (protocol.isNotEmpty) InfoSection('Protocol details', protocol),
    InfoSection('Storage', storage),
  ];
}

bool _nonEmpty(String? s) => s != null && s.isNotEmpty;

String _suffix(String? s) => s == null ? '' : '  ($s)';

String _uidKind(List<int> uid) {
  if (uid.length == 4 && uid.first == 0x08) return ' (random ID, changes every tap)';
  return switch (uid.length) {
    4 => ' (single size)',
    7 => ' (double size)',
    10 => ' (triple size)',
    _ => '',
  };
}

InfoField _hexWithText(String label, String hex) {
  final bytes = hexToBytes(hex);
  final text = isMostlyPrintable(bytes) ? '  "${bytesToAscii(bytes)}"' : '';
  return InfoField(label, '${hex.toUpperCase()}$text', monospace: true);
}

String _feliCaSystem(String hex) {
  final known = switch (hex.toUpperCase()) {
    '0003' => 'Transit IC (Suica, PASMO, ICOCA...)',
    'FE00' => 'Common area (Edy, nanaco, WAON...)',
    '12FC' => 'NFC Forum Type 3 (NDEF)',
    '8008' => 'Octopus',
    _ => null,
  };
  return '${hex.toUpperCase()}${_suffix(known)}';
}

String _bytes(int n) => n >= 1024 && n % 1024 == 0 ? '${n ~/ 1024} KB ($n bytes)' : '$n bytes';
