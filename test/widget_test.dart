import 'package:flutter_test/flutter_test.dart';
import 'package:jewel_pos/main.dart';

void main() {
  testWidgets('JewelPOSApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const JewelPOSApp());
    expect(find.byType(JewelPOSApp), findsOneWidget);
  });
}
