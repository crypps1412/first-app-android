import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../nfc/hex.dart';
import '../nfc/models.dart';

/// Scrollable, sectioned presentation of one card read.
class ResultView extends StatelessWidget {
  const ResultView({super.key, required this.result});

  final CardReadResult result;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _Header(result: result),
        for (final w in result.warnings) _WarningCard(text: w),
        if (result.records.isNotEmpty) ...[
          _SectionTitle('Content on the card', Icons.article_outlined),
          for (var i = 0; i < result.records.length; i++)
            _RecordCard(record: result.records[i], index: i + 1),
        ] else if (result.memory.isEmpty)
          const _HintCard(
            'No readable content was found. The card may be blank, '
            'or its data may be encrypted. The card details are shown below.',
          ),
        for (final s in result.sections) ...[
          _SectionTitle(s.title, _iconFor(s.title)),
          _FieldsCard(fields: s.fields),
        ],
        if (result.memory.isNotEmpty) ...[
          _SectionTitle('Memory', Icons.memory),
          for (final area in result.memory) _MemoryCard(area: area),
        ],
      ],
    );
  }

  static IconData _iconFor(String title) => switch (title) {
    'Identity' => Icons.badge_outlined,
    'Protocol details' => Icons.settings_input_antenna,
    'Storage' => Icons.sd_storage_outlined,
    _ => Icons.info_outline,
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.result});

  final CardReadResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = result.readAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.contactless, size: 40, color: scheme.onPrimaryContainer),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Read at ${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
                    '  •  ${result.records.length} record${result.records.length == 1 ? '' : 's'}',
                    style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.icon);

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: style?.color),
          const SizedBox(width: 8),
          Text(text, style: style),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.index});

  final ParsedRecord record;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(record.kind), size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('#$index  ${record.kind}', style: theme.textTheme.labelLarge)),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copy(context, record.headline),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SelectableText(
                record.headline.isEmpty ? '(empty)' : record.headline,
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (record.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Details', style: theme.textTheme.bodySmall),
                  childrenPadding: const EdgeInsets.only(right: 8, bottom: 4),
                  children: [for (final f in record.details) _FieldRow(field: f)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('web') || k.contains('link') || k.contains('poster')) return Icons.link;
    if (k.contains('phone')) return Icons.phone;
    if (k.contains('email')) return Icons.email_outlined;
    if (k.contains('sms')) return Icons.sms_outlined;
    if (k.contains('location')) return Icons.place_outlined;
    if (k.contains('contact')) return Icons.contact_page_outlined;
    if (k.contains('wi-fi')) return Icons.wifi;
    if (k.contains('bluetooth')) return Icons.bluetooth;
    if (k.contains('android')) return Icons.android;
    if (k.contains('text')) return Icons.notes;
    return Icons.data_object;
  }
}

class _FieldsCard extends StatelessWidget {
  const _FieldsCard({required this.fields});

  final List<InfoField> fields;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: [for (final f in fields) _FieldRow(field: f)]),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final InfoField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onLongPress: () => _copy(context, field.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                field.label,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                field.value,
                style: field.monospace
                    ? theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')
                    : theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.area});

  final MemoryArea area;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final locked = area.blocks.isEmpty;
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        leading: Icon(locked ? Icons.lock_outline : Icons.lock_open, size: 20),
        title: Text(area.title),
        subtitle: area.status == null ? null : Text(area.status!),
        enabled: !locked,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final block in area.blocks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      '${block.index.toString().padLeft(3)}  '
                      '${bytesToHex(block.bytes, separator: ' ')}  ${bytesToAscii(block.bytes)}',
                      style: mono,
                    ),
                  ),
                  if (block.note != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 28, top: 2),
                      child: Text(
                        block.note!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
        title: Text(text, style: TextStyle(color: scheme.onTertiaryContainer)),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(leading: const Icon(Icons.help_outline), title: Text(text)),
    );
  }
}

void _copy(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
}
