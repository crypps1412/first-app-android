/// Plain-text rendering of a [CardReadResult], used by "Copy report".
library;

import 'hex.dart';
import 'models.dart';

String buildTextReport(CardReadResult r) {
  final b = StringBuffer()
    ..writeln(r.title)
    ..writeln('Read at ${r.readAt.toLocal()}')
    ..writeln();

  for (final w in r.warnings) {
    b.writeln('! $w');
  }
  if (r.warnings.isNotEmpty) b.writeln();

  for (final s in r.sections) {
    b.writeln('== ${s.title} ==');
    for (final f in s.fields) {
      b.writeln('${f.label}: ${f.value}');
    }
    b.writeln();
  }

  if (r.records.isNotEmpty) {
    b.writeln('== NDEF content (${r.records.length} record${r.records.length == 1 ? '' : 's'}) ==');
    for (var i = 0; i < r.records.length; i++) {
      final rec = r.records[i];
      b.writeln('#${i + 1} ${rec.kind}: ${rec.headline}');
      for (final f in rec.details) {
        b.writeln('   ${f.label}: ${f.value}');
      }
    }
    b.writeln();
  }

  for (final area in r.memory) {
    b.writeln('== ${area.title}${area.status == null ? '' : ' - ${area.status}'} ==');
    for (final block in area.blocks) {
      b.writeln(
        '${block.index.toString().padLeft(3)}  ${bytesToHex(block.bytes, separator: ' ')}'
        '  |${bytesToAscii(block.bytes)}|'
        '${block.note == null ? '' : '  ${block.note}'}',
      );
    }
  }
  return b.toString().trimRight();
}
