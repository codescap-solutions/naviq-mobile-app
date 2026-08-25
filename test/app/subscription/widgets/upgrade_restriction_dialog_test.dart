import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:child_track/app/subscription/models/subscription_plan.dart';
import 'package:child_track/app/subscription/widgets/upgrade_restriction_dialog.dart';

/// Widget tests for the shared restriction dialog every gated screen
/// (geofencing cap, screen-time actions, trip-history window, help
/// channels) opens via [UpgradeRestrictionDialog.show]. Covers the two
/// user-facing outcomes: dismissing without navigating, and the dialog
/// rendering the exact title/message/CTA it was given (the per-screen
/// gates are individually unit-tested via SubscriptionFeatureGate; this
/// verifies the shared UI they all funnel into).
void main() {
  Future<void> pumpWithShowButton(
    WidgetTester tester, {
    required String title,
    required String message,
    required SubscriptionTier suggestedTier,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => UpgradeRestrictionDialog.show(
                context,
                title: title,
                message: message,
                suggestedTier: suggestedTier,
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the given title, message, and CTA text', (tester) async {
    await pumpWithShowButton(
      tester,
      title: 'Geofence Limit Reached',
      message: 'Your current plan allows up to 3 geofence zones. Upgrade to add more.',
      suggestedTier: SubscriptionTier.smart,
    );

    expect(find.text('Geofence Limit Reached'), findsOneWidget);
    expect(
      find.text('Your current plan allows up to 3 geofence zones. Upgrade to add more.'),
      findsOneWidget,
    );
    expect(find.text('View Plans'), findsOneWidget);
    expect(find.text('Not Now'), findsOneWidget);
  });

  testWidgets('"Not Now" dismisses the dialog without opening the plans sheet', (
    tester,
  ) async {
    await pumpWithShowButton(
      tester,
      title: 'Upgrade to Take Action',
      message: 'Upgrade to Smart or Premium to lock apps and set screen-time limits.',
      suggestedTier: SubscriptionTier.smart,
    );

    expect(find.text('Upgrade to Take Action'), findsOneWidget);

    await tester.tap(find.text('Not Now'));
    await tester.pumpAndSettle();

    expect(find.text('Upgrade to Take Action'), findsNothing);
    // Didn't navigate anywhere else — still on the trigger screen.
    expect(find.text('trigger'), findsOneWidget);
  });

  testWidgets('uses a custom ctaText when provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => UpgradeRestrictionDialog.show(
                context,
                title: 'Trip History Limit',
                message: 'Your current plan shows the last 24 hours of trip history.',
                suggestedTier: SubscriptionTier.basic,
                ctaText: 'See Upgrade Options',
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('See Upgrade Options'), findsOneWidget);
    expect(find.text('View Plans'), findsNothing);
  });
}
