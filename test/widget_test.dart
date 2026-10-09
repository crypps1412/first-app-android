import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/nfc/card_reader.dart';
import 'package:flutter_application_1/nfc/models.dart';
import 'package:flutter_application_1/ui/home_screen.dart';

class FakeReader extends CardReader {
  FakeReader(this.state);

  final NFCAvailability state;

  @override
  Future<NFCAvailability> availability() async => state;

  @override
  Future<CardReadResult> readCard({Duration timeout = const Duration(seconds: 30)}) async =>
      CardReadResult(
        readAt: DateTime(2026, 1, 1, 12),
        title: 'NTAG215',
        sections: const [
          InfoSection('Identity', [InfoField('UID (hex)', '04:A2:B3:C4:D5:E6:80')]),
        ],
        records: const [ParsedRecord(kind: 'Web link', headline: 'https://example.com')],
      );

  @override
  Future<void> cancel() async {}
}

Widget app(CardReader reader) => MaterialApp(home: HomeScreen(reader: reader));

void main() {
  testWidgets('scanning shows parsed card content', (tester) async {
    await tester.pumpWidget(app(FakeReader(NFCAvailability.available)));
    await tester.pumpAndSettle();
    expect(find.text('Ready to scan'), findsOneWidget);

    await tester.tap(find.text('Scan card'));
    await tester.pumpAndSettle();

    expect(find.text('NTAG215'), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);
    expect(find.text('04:A2:B3:C4:D5:E6:80'), findsOneWidget);
    expect(find.text('Scan another'), findsOneWidget);
  });

  testWidgets('disabled NFC shows guidance and no scan button', (tester) async {
    await tester.pumpWidget(app(FakeReader(NFCAvailability.disabled)));
    await tester.pumpAndSettle();
    expect(find.text('NFC is turned off'), findsOneWidget);
    expect(find.text('Scan card'), findsNothing);
  });
}
