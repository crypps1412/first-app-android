/// Talks to the phone's NFC controller: waits for a card, then pulls out
/// everything readable without secret keys and runs it through the parsers.
library;

import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

import 'memory_parser.dart';
import 'models.dart';
import 'ndef_parser.dart';
import 'tag_parser.dart';

/// Well-known, publicly documented MIFARE Classic keys: factory default,
/// MIFARE Application Directory and NFC Forum (NDEF) keys. Sectors protected
/// by any other key are reported as locked rather than attacked.
const List<String> publicClassicKeys = [
  'FFFFFFFFFFFF',
  'A0A1A2A3A4A5',
  'D3F7D3F7D3F7',
  '000000000000',
];

class CardReader {
  const CardReader();

  Future<NFCAvailability> availability() => FlutterNfcKit.nfcAvailability;

  /// Waits up to [timeout] for a card, reads it and ends the NFC session.
  Future<CardReadResult> readCard({Duration timeout = const Duration(seconds: 30)}) async {
    final tag = await FlutterNfcKit.poll(
      timeout: timeout,
      readIso18092: true, // FeliCa; also needed by some Samsung phones.
      iosAlertMessage: 'Hold your card near the top of the phone',
    );
    final warnings = <String>[];
    var records = <ParsedRecord>[];
    var memory = <MemoryArea>[];
    try {
      if (tag.ndefAvailable == true) {
        try {
          records = parseNdefRecords(await FlutterNfcKit.readNDEFRawRecords());
        } on PlatformException catch (e) {
          warnings.add('Could not read NDEF message: ${e.message ?? e.code}');
        }
      }
      if (tag.type == NFCTagType.mifare_classic) {
        memory = await _readClassic(tag, warnings);
      } else if (tag.type == NFCTagType.mifare_ultralight) {
        memory = await _readUltralight(tag, warnings);
      }
    } finally {
      await _finish();
    }

    if (tag.type == NFCTagType.iso7816) {
      warnings.add(
        'This is a secure smart card (bank, ID, transit or access card). '
        'Its data is protected and only its public identifiers are shown.',
      );
    }
    if (tag.id.length == 8 && tag.id.toUpperCase().startsWith('08')) {
      warnings.add('The card uses a random UID, so the UID changes on every tap.');
    }

    return CardReadResult(
      readAt: DateTime.now(),
      title: cardTitle(tag),
      sections: describeTag(tag),
      records: records,
      memory: memory,
      warnings: warnings,
    );
  }

  /// Ends a session left open by an interrupted read.
  Future<void> cancel() => _finish();

  Future<void> _finish() async {
    try {
      await FlutterNfcKit.finish();
    } catch (_) {
      // No session open.
    }
  }

  Future<List<MemoryArea>> _readClassic(NFCTag tag, List<String> warnings) async {
    final sectors = tag.mifareInfo?.sectorCount ?? 0;
    final areas = <MemoryArea>[];
    var locked = 0;
    for (var s = 0; s < sectors; s++) {
      String? usedKey;
      try {
        for (final key in publicClassicKeys) {
          if (await FlutterNfcKit.authenticateSector<String>(s, keyA: key)) {
            usedKey = key;
            break;
          }
        }
      } on PlatformException catch (e) {
        // Most often: the phone's NFC chip isn't made by NXP and cannot
        // speak MIFARE Classic's proprietary crypto at all.
        warnings.add(
          'This phone cannot read MIFARE Classic memory '
          '(${e.message ?? e.code}). Only the card identity is shown.',
        );
        return areas;
      }
      if (usedKey == null) {
        locked++;
        areas.add(MemoryArea('Sector $s', const [], status: 'Locked - protected by a private key'));
        continue;
      }
      try {
        final data = await FlutterNfcKit.readSector(s);
        areas.add(MemoryArea(
          'Sector $s',
          parseClassicSector(s, data),
          status: 'Opened with ${_keyName(usedKey)}',
        ));
      } on PlatformException catch (e) {
        areas.add(MemoryArea('Sector $s', const [], status: 'Read failed: ${e.message ?? e.code}'));
      }
    }
    if (locked > 0) {
      warnings.add('$locked of $sectors sectors are protected by private keys and were not read.');
    }
    return areas;
  }

  Future<List<MemoryArea>> _readUltralight(NFCTag tag, List<String> warnings) async {
    final pages = tag.mifareInfo?.blockCount ?? -1;
    if (pages <= 0) return const [];
    final bytes = <int>[];
    // Each read returns 4 pages (16 bytes).
    for (var p = 0; p < pages; p += 4) {
      try {
        final chunk = await FlutterNfcKit.readBlock(p);
        final wanted = (pages - p).clamp(0, 4) * 4;
        bytes.addAll(chunk.take(wanted));
      } on PlatformException catch (e) {
        warnings.add('Stopped reading at page $p: ${e.message ?? e.code} (page may be password protected).');
        break;
      }
    }
    return [MemoryArea('Pages 0-${bytes.length ~/ 4 - 1}', parseUltralightPages(bytes))];
  }

  String _keyName(String key) => switch (key) {
    'FFFFFFFFFFFF' => 'factory default key',
    'A0A1A2A3A4A5' => 'MAD public key',
    'D3F7D3F7D3F7' => 'NFC Forum public key',
    '000000000000' => 'all-zero key',
    _ => 'key $key',
  };
}

/// Turns plugin error codes into a sentence for the user.
String describeNfcError(Object error) {
  if (error is PlatformException) {
    return switch (error.code) {
      '408' => 'No card detected. Hold the card against the back of the phone and try again.',
      '404' => 'NFC is not available on this device.',
      '500' || '503' =>
        'The card moved away before reading finished. Keep it still against the phone and try again.',
      _ => error.message ?? 'NFC error ${error.code}',
    };
  }
  return error.toString();
}
