import 'package:flutter_test/flutter_test.dart';
import 'package:vakil/main.dart';

void main() {
  testWidgets(
    'Vakil app starts correctly',
    (WidgetTester tester) async {
      await tester.pumpWidget(const VakilApp());

      expect(find.text('وکیل'), findsOneWidget);
      expect(
        find.text('عبارت موردنظر را وارد کنید'),
        findsOneWidget,
      );
    },
  );
}
