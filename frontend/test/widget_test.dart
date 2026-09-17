// Basic smoke test for the minimal shader-background app.

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';
import 'package:frontend/shader_background.dart';

void main() {
  testWidgets('renders the animated shader background', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(ShaderBackground), findsOneWidget);
  });
}
