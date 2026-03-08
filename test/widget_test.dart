import 'package:flutter_test/flutter_test.dart';
import 'package:kams_bot/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const KamsBotApp());
    expect(find.byType(KamsBotApp), findsOneWidget);
  });
}
