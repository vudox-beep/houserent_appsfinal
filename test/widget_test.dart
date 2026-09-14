// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:houserent/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const HouseRentApp());

    // Verify that the title is present
    expect(find.text('HouseRent Africa'), findsWidgets);
  });

  testWidgets('Theme can change without rebuilding stale dependencies', (
    WidgetTester tester,
  ) async {
    appThemeNotifier.value = ThemeMode.light;
    await tester.pumpWidget(const HouseRentApp());
    await tester.pump();

    setAppThemeMode(ThemeMode.dark);
    await tester.pump();
    await tester.pump();

    expect(appThemeNotifier.value, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });
}
