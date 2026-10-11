import 'package:child_track/app/subscription/models/subscription_plan.dart';
import 'package:flutter_test/flutter_test.dart';

SubscriptionPlan plan(String id, String name) => SubscriptionPlan.fromJson({
  'id': id,
  'name': name,
  'features': [],
  'pricing': {'monthly': {'amount': 0}},
});

void main() {
  test('plan button text follows the plan id, whatever the display name', () {
    expect(plan('starter', 'Free').ctaText, 'Choose Free');
    expect(plan('basic', 'Basic').ctaText, 'Choose Basic');
    expect(plan('smart', 'Smart').ctaText, 'Choose Smart');
    expect(plan('premium', 'Premium').ctaText, 'Choose Premium');
    // Older server data named the top plan "Ultimate".
    expect(plan('premium', 'Ultimate').ctaText, 'Choose Premium');
  });
}
