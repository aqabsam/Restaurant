import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_new_app/main.dart';

void main() {
  testWidgets('shows core restaurant home sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Restaurant'), findsOneWidget);
    expect(find.text('Online Order'), findsOneWidget);
    expect(find.text('Book Your Order'), findsOneWidget);
    expect(find.text('Starter'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Main Course'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Main Course'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Desserts'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Desserts'), findsOneWidget);
  });
}
