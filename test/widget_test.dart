import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiny_mobile_test/main.dart';

void main() {
  testWidgets('park golf scorecard shows base fields and totals', (
    tester,
  ) async {
    await tester.pumpWidget(const ShinyMobileTestApp());

    expect(find.text('파크골프 스코어카드'), findsWidgets);
    expect(find.text('경기장'), findsOneWidget);
    expect(find.text('날짜'), findsOneWidget);
    expect(find.text('플레이어 수'), findsOneWidget);
    expect(find.text('합계'), findsOneWidget);
    expect(find.text('파 72'), findsOneWidget);
    expect(find.text('v0.1.2-test'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(7), '3');
    await tester.pump();

    expect(find.text('플레이어 1 3'), findsOneWidget);
  });
}
