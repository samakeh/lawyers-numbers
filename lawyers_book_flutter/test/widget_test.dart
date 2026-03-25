import 'package:flutter_test/flutter_test.dart';

import 'package:lawyers_book_flutter/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const LawyersBookApp());
    expect(find.textContaining('دليل المحامين'), findsOneWidget);
  });
}
