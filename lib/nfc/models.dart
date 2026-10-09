/// Plain data types shared by the reader, the parsers and the UI.
library;

/// One labelled value, e.g. `UID: 04:A2:...`.
class InfoField {
  const InfoField(this.label, this.value, {this.monospace = false});

  final String label;
  final String value;

  /// Render the value in a fixed-width font (hex, dumps).
  final bool monospace;
}

/// A titled group of fields shown as one card on screen.
class InfoSection {
  const InfoSection(this.title, this.fields, {this.kind = SectionKind.info});

  final String title;
  final List<InfoField> fields;
  final SectionKind kind;
}

enum SectionKind { info, ndef, memory, warning }

/// A decoded NDEF record in human-readable form.
class ParsedRecord {
  const ParsedRecord({
    required this.kind,
    required this.headline,
    this.details = const [],
  });

  /// Short type name, e.g. "Web link", "Text", "Wi-Fi network".
  final String kind;

  /// The main human-readable value (the text, the URL, the SSID...).
  final String headline;

  final List<InfoField> details;
}

/// One 16-byte block (MIFARE Classic) or 4-byte page (Ultralight/NTAG).
class MemoryBlock {
  const MemoryBlock(this.index, this.bytes, {this.note});

  final int index;
  final List<int> bytes;

  /// Human description of what this block holds, if known.
  final String? note;
}

/// A MIFARE Classic sector, or the whole page range of an Ultralight tag.
class MemoryArea {
  const MemoryArea(this.title, this.blocks, {this.status});

  final String title;
  final List<MemoryBlock> blocks;

  /// e.g. "Unlocked with key A FFFFFFFFFFFF" or "Locked - unknown key".
  final String? status;
}

/// Everything collected from one tap of a card.
class CardReadResult {
  const CardReadResult({
    required this.readAt,
    required this.title,
    required this.sections,
    this.records = const [],
    this.memory = const [],
    this.warnings = const [],
  });

  final DateTime readAt;

  /// Best guess at what the card is, e.g. "MIFARE Classic 1K".
  final String title;
  final List<InfoSection> sections;
  final List<ParsedRecord> records;
  final List<MemoryArea> memory;
  final List<String> warnings;
}
