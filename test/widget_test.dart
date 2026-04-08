import 'package:flutter_test/flutter_test.dart';
import 'package:snore_cost/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SnoreCostApp());
    expect(find.text('ХрапОмстр'), findsOneWidget);
  });
}
