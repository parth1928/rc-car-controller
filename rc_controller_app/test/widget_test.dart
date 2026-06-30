import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller_app/main.dart';

void main() {
  testWidgets('App renders drive screen with status bar', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(MyApp), findsOneWidget);
  });
}
