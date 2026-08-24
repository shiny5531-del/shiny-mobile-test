import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiny_mobile_test/main.dart';

void main() {
  testWidgets('home screen shows counter and version', (tester) async {
    await tester.pumpWidget(const ShinyMobileTestApp());

    expect(find.text('모바일 앱 테스트'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('v0.1.1-test'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });
}
