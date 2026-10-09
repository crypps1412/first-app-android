/// Decodes NDEF records (the standard "message" format written on NFC tags)
/// into human-readable [ParsedRecord]s.
library;

import 'dart:convert';

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

import 'hex.dart';
import 'models.dart';

/// Parses every raw record independently, so one malformed record does not
/// hide the others.
List<ParsedRecord> parseNdefRecords(List<NDEFRawRecord> raws) =>
    raws.map(parseNdefRecord).toList();

ParsedRecord parseNdefRecord(NDEFRawRecord raw) {
  final payload = hexToBytes(raw.payload);
  ndef.NDEFRecord? decoded;
  try {
    decoded = NDEFRecordConvert.fromRaw(raw);
  } catch (_) {
    // Fall through to the generic decoder below.
  }

  final common = <InfoField>[
    InfoField('Record format', _tnfName(raw.typeNameFormat)),
    if (raw.identifier.isNotEmpty)
      InfoField('Record ID', _textOrHex(hexToBytes(raw.identifier)), monospace: true),
    InfoField('Payload size', '${payload.length} bytes'),
  ];

  final parsed = decoded == null ? null : _parseDecoded(decoded, payload);
  final result = parsed ?? _parseGeneric(raw, payload);
  return ParsedRecord(
    kind: result.kind,
    headline: result.headline,
    details: [...result.details, ...common],
  );
}

ParsedRecord? _parseDecoded(ndef.NDEFRecord r, List<int> payload) {
  // Order matters: subclasses before their parents.
  switch (r) {
    case ndef.SmartPosterRecord():
      return _smartPoster(r);
    case ndef.TextRecord():
      return ParsedRecord(
        kind: 'Text',
        headline: r.text ?? '',
        details: [
          if (r.language != null && r.language!.isNotEmpty)
            InfoField('Language', r.language!),
          InfoField('Encoding', r.encoding == ndef.TextEncoding.UTF8 ? 'UTF-8' : 'UTF-16'),
        ],
      );
    case ndef.UriRecord():
      return describeUri(r.uriString ?? r.iriString ?? '');
    case ndef.AbsoluteUriRecord():
      return describeUri(r.uri ?? '');
    case ndef.AARRecord():
      return ParsedRecord(
        kind: 'Android app launcher',
        headline: r.packageName ?? '',
        details: const [InfoField('Effect', 'Opens (or installs) this Android app when tapped')],
      );
    case ndef.WifiRecord():
      return ParsedRecord(
        kind: 'Wi-Fi network',
        headline: r.ssid ?? '(hidden network)',
        details: [
          InfoField('Security', r.authenticationType.name),
          InfoField('Encryption', r.encryptionType.name),
          if (r.networkKey != null && r.networkKey!.isNotEmpty)
            InfoField('Password', r.networkKey!, monospace: true),
          if (r.macAddress != null && r.macAddress!.isNotEmpty)
            InfoField('MAC address', r.macAddress!, monospace: true),
        ],
      );
    case ndef.BluetoothEasyPairingRecord():
      return ParsedRecord(
        kind: 'Bluetooth pairing',
        headline: _safe(() => r.deviceName) ?? 'Bluetooth device',
        details: [
          if (r.address != null) InfoField('Address', r.address!.address, monospace: true),
        ],
      );
    case ndef.BluetoothLowEnergyRecord():
      return ParsedRecord(
        kind: 'Bluetooth LE pairing',
        headline: _safe(() => r.deviceName) ?? 'Bluetooth LE device',
        details: [
          if (_safe(() => r.address?.address) case final a?)
            InfoField('Address', a, monospace: true),
          if (_safe(() => r.roleCapabilities) case final role?) InfoField('Role', role),
          if (_safe(() => r.appearance) case final app?) InfoField('Appearance', app),
        ],
      );
    case ndef.MimeRecord():
      return _mime(r.decodedType ?? 'application/octet-stream', payload);
    case ndef.ExternalRecord():
      return ParsedRecord(
        kind: 'Custom data (external type)',
        headline: _textOrHex(payload),
        details: [InfoField('Type', r.decodedType ?? '')],
      );
    default:
      return null;
  }
}

ParsedRecord _smartPoster(ndef.SmartPosterRecord r) {
  final uri = _safe(() => r.uri?.toString()) ?? '';
  final title = _safe(() => r.title);
  return ParsedRecord(
    kind: 'Smart poster',
    headline: title?.isNotEmpty == true ? title! : uri,
    details: [
      if (uri.isNotEmpty) InfoField('Link', uri),
      if (_safe(() => r.action) case final a?) InfoField('Action', a.name),
      if (_safe(() => r.typeInfo) case final t?) InfoField('Content type', t),
      if (_safe(() => r.size) case final s?) InfoField('Content size', '$s bytes'),
    ],
  );
}

/// Classifies a URI by scheme so the user sees "Phone number: +1..." rather
/// than a bare `tel:` link.
ParsedRecord describeUri(String uri) {
  final lower = uri.toLowerCase();
  String after(String prefix) => Uri.decodeComponent(uri.substring(prefix.length));

  if (lower.startsWith('tel:')) {
    return ParsedRecord(kind: 'Phone number', headline: after('tel:'));
  }
  if (lower.startsWith('mailto:')) {
    final parsed = Uri.tryParse(uri);
    final subject = parsed?.queryParameters['subject'];
    final body = parsed?.queryParameters['body'];
    return ParsedRecord(
      kind: 'Email address',
      headline: parsed?.path ?? after('mailto:'),
      details: [
        if (subject != null) InfoField('Subject', subject),
        if (body != null) InfoField('Body', body),
      ],
    );
  }
  if (lower.startsWith('sms:') || lower.startsWith('smsto:')) {
    final parsed = Uri.tryParse(uri);
    final body = parsed?.queryParameters['body'];
    return ParsedRecord(
      kind: 'SMS',
      headline: parsed?.path ?? uri,
      details: [if (body != null) InfoField('Message', body)],
    );
  }
  if (lower.startsWith('geo:')) {
    final coords = uri.substring(4).split('?').first.split(',');
    return ParsedRecord(
      kind: 'Location',
      headline: uri.substring(4),
      details: [
        if (coords.length >= 2) ...[
          InfoField('Latitude', coords[0]),
          InfoField('Longitude', coords[1]),
        ],
      ],
    );
  }
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    final host = Uri.tryParse(uri)?.host;
    return ParsedRecord(
      kind: 'Web link',
      headline: uri,
      details: [if (host != null && host.isNotEmpty) InfoField('Website', host)],
    );
  }
  if (lower.startsWith('market://')) {
    return ParsedRecord(kind: 'Play Store link', headline: uri);
  }
  return ParsedRecord(kind: 'Link', headline: uri);
}

ParsedRecord _mime(String type, List<int> payload) {
  final lower = type.toLowerCase();
  if (lower == 'text/vcard' || lower == 'text/x-vcard') {
    return parseVCard(utf8.decode(payload, allowMalformed: true));
  }
  final isText = lower.startsWith('text/') ||
      lower.contains('json') ||
      lower.contains('xml') ||
      isMostlyPrintable(payload);
  if (isText) {
    var text = utf8.decode(payload, allowMalformed: true);
    if (lower.contains('json')) {
      try {
        text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
      } catch (_) {}
    }
    return ParsedRecord(
      kind: 'Data ($type)',
      headline: text,
      details: [InfoField('MIME type', type)],
    );
  }
  return ParsedRecord(
    kind: 'Binary data ($type)',
    headline: bytesToHex(payload, separator: ' '),
    details: [InfoField('MIME type', type)],
  );
}

/// Extracts the common vCard (contact card) properties.
ParsedRecord parseVCard(String vcard) {
  // Unfold continuation lines (RFC 6350 §3.2).
  final lines = vcard.replaceAll(RegExp(r'\r?\n[ \t]'), '').split(RegExp(r'\r?\n'));
  const labels = {
    'FN': 'Name',
    'N': 'Structured name',
    'ORG': 'Organisation',
    'TITLE': 'Job title',
    'TEL': 'Phone',
    'EMAIL': 'Email',
    'URL': 'Website',
    'ADR': 'Address',
    'NOTE': 'Note',
    'BDAY': 'Birthday',
  };
  final fields = <InfoField>[];
  String? name;
  for (final line in lines) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final key = line.substring(0, colon).split(';').first.toUpperCase();
    final value = line
        .substring(colon + 1)
        .replaceAll(RegExp(r';+'), ' ')
        .replaceAll(r'\,', ',')
        .trim();
    if (value.isEmpty) continue;
    if (key == 'FN') name = value;
    final label = labels[key];
    if (label != null && !(key == 'N' && name != null)) {
      fields.add(InfoField(label, value));
    }
  }
  return ParsedRecord(kind: 'Contact card', headline: name ?? 'Contact', details: fields);
}

ParsedRecord _parseGeneric(NDEFRawRecord raw, List<int> payload) {
  if (raw.typeNameFormat == ndef.TypeNameFormat.empty) {
    return const ParsedRecord(kind: 'Empty record', headline: '(no data)');
  }
  final type = utf8.decode(hexToBytes(raw.type), allowMalformed: true);
  return ParsedRecord(
    kind: 'Unrecognised record',
    headline: _textOrHex(payload),
    details: [if (type.isNotEmpty) InfoField('Type', type)],
  );
}

String _tnfName(ndef.TypeNameFormat tnf) => switch (tnf) {
  ndef.TypeNameFormat.empty => 'Empty',
  ndef.TypeNameFormat.nfcWellKnown => 'NFC Forum well-known type',
  ndef.TypeNameFormat.media => 'MIME media type',
  ndef.TypeNameFormat.absoluteURI => 'Absolute URI',
  ndef.TypeNameFormat.nfcExternal => 'NFC Forum external type',
  ndef.TypeNameFormat.unknown => 'Unknown',
  ndef.TypeNameFormat.unchanged => 'Chunk continuation',
};

String _textOrHex(List<int> bytes) {
  if (bytes.isEmpty) return '(empty)';
  return isMostlyPrintable(bytes)
      ? utf8.decode(bytes, allowMalformed: true)
      : bytesToHex(bytes, separator: ' ');
}

/// Some ndef getters throw on malformed payloads; treat that as "absent".
T? _safe<T>(T? Function() read) {
  try {
    return read();
  } catch (_) {
    return null;
  }
}
