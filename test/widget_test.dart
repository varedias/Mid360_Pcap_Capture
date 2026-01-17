// This is a basic Flutter widget test.

import 'package:flutter_test/flutter_test.dart';

import 'package:mid360_capture/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MID360CaptureApp());

    // Verify that the app title is shown.
    expect(find.text('MID-360 点云采集'), findsOneWidget);

    // Verify that the start capture button exists.
    expect(find.text('开始采集'), findsOneWidget);
    expect(find.text('停止采集'), findsOneWidget);
  });
}
