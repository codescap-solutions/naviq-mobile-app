import 'package:child_track/core/di/injector.dart';
import 'package:child_track/main.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    // ChildTrackApp resolves its blocs from GetIt, which main() fills in
    // before runApp — the test has to do the same.
    SharedPreferences.setMockInitialValues({});
    await injector.reset();
    await initializeDependencies();
  });

  testWidgets('App starts with splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ChildTrackApp());

    // The splash is the logo image with the tagline under it.
    expect(find.text('Accuracy. Safety. Protection'), findsOneWidget);

    // Unmount, then let the splash's 2 s auth-check timer fire harmlessly.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
