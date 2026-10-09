import 'dart:convert';

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ndef/ndef.dart' show TypeNameFormat;

import 'package:flutter_application_1/nfc/hex.dart';
import 'package:flutter_application_1/nfc/memory_parser.dart';
import 'package:flutter_application_1/nfc/ndef_parser.dart';
import 'package:flutter_application_1/nfc/tag_parser.dart';

String hexOf(String s) => bytesToHex(utf8.encode(s), separator: '');

NFCTag tag({
  NFCTagType type = NFCTagType.mifare_ultralight,
  String id = '04A2B3C4D5E680',
  String? sak = '00',
  MifareInfo? mifare,
}) => NFCTag(type, id, 'ISO 14443-3 (Type A)', '4400', sak, null, null, null, null,
    null, null, null, true, 'org.nfcforum.ndef.type2', 492, true, true, null, mifare);

void main() {
  group('hex', () {
    test('round trip and decimal', () {
      expect(hexToBytes('04:a2 ff'), [0x04, 0xA2, 0xFF]);
      expect(hexToBytes('unknown'), isEmpty);
      expect(bytesToHex([0x04, 0xA2]), '04:A2');
      expect(bytesToDecimal([0x01, 0x00]), '256');
      expect(bytesToAscii([0x41, 0x00, 0x42]), 'A.B');
    });
  });

  group('NDEF', () {
    test('text record', () {
      final r = parseNdefRecord(NDEFRawRecord(
        '', '02${hexOf('en')}${hexOf('Hello world')}', '54', TypeNameFormat.nfcWellKnown));
      expect(r.kind, 'Text');
      expect(r.headline, 'Hello world');
      expect(r.details.any((f) => f.label == 'Language' && f.value == 'en'), isTrue);
    });

    test('URI record expands prefix', () {
      final r = parseNdefRecord(NDEFRawRecord(
        '', '04${hexOf('example.com/a')}', '55', TypeNameFormat.nfcWellKnown));
      expect(r.kind, 'Web link');
      expect(r.headline, 'https://example.com/a');
    });

    test('phone URI', () {
      final r = parseNdefRecord(NDEFRawRecord(
        '', '05${hexOf('+15551234')}', '55', TypeNameFormat.nfcWellKnown));
      expect(r.kind, 'Phone number');
      expect(r.headline, '+15551234');
    });

    test('vCard', () {
      const card = 'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ada Lovelace\r\nTEL;TYPE=CELL:+441234\r\n'
          'EMAIL:ada@example.com\r\nEND:VCARD';
      final r = parseNdefRecord(NDEFRawRecord('', hexOf(card), hexOf('text/vcard'), TypeNameFormat.media));
      expect(r.kind, 'Contact card');
      expect(r.headline, 'Ada Lovelace');
      expect(r.details.map((f) => f.value), containsAll(['+441234', 'ada@example.com']));
    });

    test('Android app record', () {
      final r = parseNdefRecord(NDEFRawRecord(
        '', hexOf('com.example.app'), hexOf('android.com:pkg'), TypeNameFormat.nfcExternal));
      expect(r.kind, 'Android app launcher');
      expect(r.headline, 'com.example.app');
    });

    test('malformed record falls back instead of throwing', () {
      final r = parseNdefRecord(NDEFRawRecord('', '', '55', TypeNameFormat.nfcWellKnown));
      expect(r.kind, isNotEmpty);
    });
  });

  group('tag', () {
    test('NXP manufacturer, SAK and title', () {
      final t = tag(mifare: MifareInfo('ultralight', 64, 4, 16, null));
      final fields = describeTag(t).expand((s) => s.fields).toList();
      expect(fields.firstWhere((f) => f.label == 'Chip manufacturer').value, 'NXP Semiconductors');
      expect(fields.firstWhere((f) => f.label == 'SAK').value, contains('Ultralight'));
      expect(cardTitle(t), 'MIFARE Ultralight / NTAG');
    });

    test('Classic 1K title from size', () {
      final t = tag(type: NFCTagType.mifare_classic, id: 'DEADBEEF', sak: '08',
          mifare: MifareInfo('classic', 1024, 16, 64, 16));
      expect(cardTitle(t), 'MIFARE Classic 1K');
    });
  });

  group('MIFARE memory', () {
    test('default trailer access bits', () {
      final access = decodeAccessBits([0xFF, 0x07, 0x80]);
      expect(access, [0, 0, 0, 1]);
      expect(decodeAccessBits([0xFF, 0x07, 0x81]), isNull);
    });

    test('value block', () {
      // 100 = 0x64, address 5.
      final b = [0x64, 0, 0, 0, 0x9B, 0xFF, 0xFF, 0xFF, 0x64, 0, 0, 0, 5, 0xFA, 5, 0xFA];
      expect(decodeValueBlock(b), (100, 5));
      expect(describeDataBlock(b), contains('Value block: 100'));
    });

    test('sector 0 annotations', () {
      final sector = [
        0xDE, 0xAD, 0xBE, 0xEF, 0xDE ^ 0xAD ^ 0xBE ^ 0xEF, ...List.filled(11, 0),
        ...utf8.encode('Hello card').followedBy(List.filled(6, 0)),
        ...List.filled(16, 0),
        ...List.filled(6, 0), 0xFF, 0x07, 0x80, 0x69, ...List.filled(6, 0xFF),
      ];
      final blocks = parseClassicSector(0, sector);
      expect(blocks, hasLength(4));
      expect(blocks[0].note, contains('check byte valid'));
      expect(blocks[1].note, 'Text: "Hello card"');
      expect(blocks[2].note, 'Empty (all zeros)');
      expect(blocks[3].note, contains('transport'));
    });

    test('Ultralight capability container', () {
      expect(describeCapabilityContainer([0xE1, 0x10, 0x3E, 0x00]),
          'Capability container: NDEF v1.0, 496 bytes data area, read/write');
    });
  });
}
