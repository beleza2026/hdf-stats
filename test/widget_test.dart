import 'package:flutter_test/flutter_test.dart';
import 'package:hdf_stats/main.dart';

void main() {
  testWidgets('HDF STATS smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HDFStatsApp());
  });
}