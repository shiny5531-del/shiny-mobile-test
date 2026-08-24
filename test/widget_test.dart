import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiny_mobile_test/main.dart';

void main() {
  testWidgets('park golf scorecard shows base setup fields', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ShinyMobileTestApp());
    await tester.pumpAndSettle();

    expect(find.text('파크골프 스코어카드'), findsWidgets);
    expect(find.text('경기 설정'), findsOneWidget);
    expect(find.text('날짜'), findsOneWidget);
    expect(find.text('경기 시작'), findsOneWidget);
    expect(find.text('A-B 기본'), findsOneWidget);
  });
}
