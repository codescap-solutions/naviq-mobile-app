enum SubscriptionTier {
  starter('starter'),
  basic('basic'),
  smart('smart'),
  premium('premium');

  final String id;
  const SubscriptionTier(this.id);

  static SubscriptionTier fromId(String id) {
    final lowerId = id.toLowerCase();
    if (lowerId.contains('premium') || lowerId.contains('ultimate')) {
      return SubscriptionTier.premium;
    }
    if (lowerId.contains('smart') || lowerId.contains('plus')) {
      return SubscriptionTier.smart;
    }
    if (lowerId.contains('basic')) return SubscriptionTier.basic;
    return SubscriptionTier.starter;
  }
}

class SubscriptionFeature {
  final String name;
  final bool included;

  const SubscriptionFeature({required this.name, this.included = true});

  factory SubscriptionFeature.fromJson(Map<String, dynamic> json) {
    return SubscriptionFeature(
      name: json['name'] as String,
      included: json['included'] as bool? ?? true,
    );
  }
}

class SubscriptionPlan {
  final String id;
  final String name;
  final String? badge;
  final String? tagline;
  final double monthlyPrice;
  final String? monthlyAppleProductId;
  final String? monthlyGoogleProductId;
  final double? yearlyPrice;
  final String? yearlyAppleProductId;
  final String? yearlyGoogleProductId;
  final String? yearlyDiscountBadge;
  final List<SubscriptionFeature> features;
  final String ctaText;

  SubscriptionTier get tier => SubscriptionTier.fromId(id);

  const SubscriptionPlan({
    required this.id,
    required this.name,
    this.badge,
    this.tagline,
    required this.monthlyPrice,
    this.monthlyAppleProductId,
    this.monthlyGoogleProductId,
    this.yearlyPrice,
    this.yearlyAppleProductId,
    this.yearlyGoogleProductId,
    this.yearlyDiscountBadge,
    required this.features,
    this.ctaText = 'Get Started',
  });

  bool get isFree => monthlyPrice == 0;

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    double monthly = 0;
    String? monthlyApple;
    String? monthlyGoogle;

    double? yearly;
    String? yearlyApple;
    String? yearlyGoogle;
    String? yearlyDiscount;

    if (json['pricing'] != null) {
      if (json['pricing']['monthly'] != null) {
        if (json['pricing']['monthly']['amount'] != null) {
          monthly = (json['pricing']['monthly']['amount'] as num).toDouble();
        }
        monthlyApple =
            json['pricing']['monthly']['apple_product_id'] as String?;
        monthlyGoogle =
            json['pricing']['monthly']['google_product_id'] as String?;
      }
      if (json['pricing']['yearly'] != null) {
        if (json['pricing']['yearly']['amount'] != null) {
          yearly = (json['pricing']['yearly']['amount'] as num).toDouble();
        }
        yearlyApple = json['pricing']['yearly']['apple_product_id'] as String?;
        yearlyGoogle =
            json['pricing']['yearly']['google_product_id'] as String?;
        if (json['pricing']['yearly']['discount_percentage'] != null) {
          yearlyDiscount =
              'Save ${json['pricing']['yearly']['discount_percentage']}%';
        }
      }
    }

    List<SubscriptionFeature> featureList = [];
    if (json['features'] != null) {
      featureList = (json['features'] as List)
          .map((f) => SubscriptionFeature.fromJson(f as Map<String, dynamic>))
          .toList();
    }

    final cta = switch (SubscriptionTier.fromId(
      (json['id'] ?? json['name'] ?? '') as String,
    )) {
      SubscriptionTier.starter => 'Choose Free',
      SubscriptionTier.basic => 'Choose Basic',
      SubscriptionTier.smart => 'Choose Smart',
      SubscriptionTier.premium => 'Choose Premium',
    };

    return SubscriptionPlan(
      id: json['id'] as String,
      name: json['name'] as String,
      badge: json['badge'] as String?,
      tagline: json['tagline'] as String?,
      monthlyPrice: monthly,
      monthlyAppleProductId: monthlyApple,
      monthlyGoogleProductId: monthlyGoogle,
      yearlyPrice: yearly,
      yearlyAppleProductId: yearlyApple,
      yearlyGoogleProductId: yearlyGoogle,
      yearlyDiscountBadge: yearlyDiscount,
      features: featureList,
      ctaText: cta,
    );
  }
}
