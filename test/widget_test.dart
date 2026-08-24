import 'package:flutter_test/flutter_test.dart';
import 'package:shiny_mobile_test/main.dart';

void main() {
  testWidgets('park golf scorecard shows base setup fields', (
    tester,
  ) async {
    await tester.pumpWidget(const ShinyMobileTestApp());

    expect(find.text('파크골프 스코어카드'), findsWidgets);
    expect(find.text('경기장'), findsOneWidget);
    expect(find.text('날짜'), findsOneWidget);
    expect(find.text('A-B 기본'), findsOneWidget);
  });
}
