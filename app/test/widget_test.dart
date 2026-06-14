import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_maxx_ide/app.dart';

void main() {
  testWidgets('App boots to workspace menu gate', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AiMaxxIdeApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Workspace'), findsWidgets);
    expect(find.text('Authenticate'), findsOneWidget);
  });
}
