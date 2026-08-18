import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';

void main() {
  testWidgets('App boots to the role-select screen', (WidgetTester tester) async {
    await tester.pumpWidget(const UniMatchApp());
    await tester.pump();
    expect(find.byType(UniMatchApp), findsOneWidget);
  });
}
