import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:flutter/material.dart';

/// Building blocks for the Figma "Device for new user" / "Device for owner"
/// screens. All sizes are Figma px, scaled with `.w` / `.sp`.

const _ink = Color(0xFF0F1320);
const _muted = Color(0xFF6B7280);

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(16.w),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 12.w,
      offset: Offset(0, 2.w),
    ),
  ],
);

/// 36px rounded-square icon badge used by every card.
class DeviceIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;

  const DeviceIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.background = const Color(0xFFF3F5F8),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36.w,
      height: 36.w,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12.w),
      ),
      child: Icon(icon, size: 18.w, color: color),
    );
  }
}

/// Section heading ("Features", "Today's Tracking").
class DeviceSectionTitle extends StatelessWidget {
  final String text;
  final double size;

  const DeviceSectionTitle(this.text, {super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: 2.w),
    child: Text(
      text,
      style: FigmaText.poppins(
        size,
        weight: FontWeight.w700,
        color: _ink,
        lineHeight: size == 20 ? 22.5 : 23,
      ),
    ),
  );
}

/// 361x306 tracker hero: blue gradient, label + name, live pill, product
/// image and a translucent pod with three metrics.
class DeviceHeroCard extends StatelessWidget {
  final String label;
  final bool uppercaseLabel;
  final String name;
  final double nameSize;
  final bool isLive;
  final List<(String, String)> metrics;

  const DeviceHeroCard({
    super.key,
    required this.label,
    required this.name,
    required this.metrics,
    this.uppercaseLabel = false,
    this.nameSize = 24,
    this.isLive = true,
  });

  @override
  Widget build(BuildContext context) {
    final liveColor = isLive ? Color(0xFF10B981) : Color(0xFF94A3B8);
    return Container(
      height: 306.w,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.w),
        border: Border.all(color: Color(0xFFBFDBFE)),
        gradient: LinearGradient(
          colors: [Color(0xFFDBEAFE), Color(0xFF93C5FD)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(8.w, 8.w, 8.w, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: FigmaText.poppins(
                          12,
                          weight: uppercaseLabel
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: FigmaColors.primary,
                          lineHeight: 20,
                          letterSpacing: uppercaseLabel ? 0.4 : 0,
                        ),
                      ),
                      Text(
                        name,
                        style: FigmaText.poppins(
                          nameSize,
                          weight: FontWeight.w700,
                          color: _ink,
                          lineHeight: nameSize + 4,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 26.w,
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13.w),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6.w,
                        height: 6.w,
                        decoration: BoxDecoration(
                          color: liveColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        isLive ? 'Live' : 'Offline',
                        style: FigmaText.poppins(
                          12,
                          weight: FontWeight.w600,
                          color: liveColor,
                          lineHeight: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Image.asset(
                'assets/images/device.png',
                height: 100.w,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.watch_rounded,
                  size: 80.w,
                  color: FigmaColors.primary,
                ),
              ),
            ),
          ),
          Container(
            height: 62.3.w,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(16.w),
            ),
            child: Row(
              children: [
                for (final m in metrics)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          m.$1,
                          style: FigmaText.poppins(
                            16,
                            weight: FontWeight.w700,
                            color: _ink,
                            lineHeight: 20,
                          ),
                        ),
                        Text(
                          m.$2,
                          style: FigmaText.poppins(
                            12,
                            color: _muted,
                            lineHeight: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 174.5x113 feature tile (icon badge, title, subtitle). The Figma file has
/// the second row slightly smaller than the first, hence [compact].
class DeviceFeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final bool compact;

  const DeviceFeatureCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 113.w,
      padding: EdgeInsets.all(16.w),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeviceIconBadge(
            icon: icon,
            color: iconColor,
            background: iconBackground,
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FigmaText.poppins(
              compact ? 14 : 16,
              weight: FontWeight.w700,
              color: _ink,
              lineHeight: 24,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FigmaText.poppins(
              compact ? 11 : 12,
              color: _muted,
              lineHeight: 17,
            ),
          ),
        ],
      ),
    );
  }
}

/// 2x2 grid of [DeviceFeatureCard]s with the Figma 12px gaps.
class DeviceFeatureGrid extends StatelessWidget {
  final List<DeviceFeatureCard> cards;

  const DeviceFeatureGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    Widget row(int i) => Row(
      children: [
        Expanded(child: cards[i]),
        SizedBox(width: 12.w),
        Expanded(child: cards[i + 1]),
      ],
    );
    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) SizedBox(height: 12.w),
          row(i),
        ],
      ],
    );
  }
}

/// Blue "TrackPod Pro rs 2499" card with perks and the Buy Now button.
class DevicePurchaseCard extends StatelessWidget {
  final VoidCallback onBuy;

  const DevicePurchaseCard({super.key, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.w),
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1D4ED8).withValues(alpha: 0.25),
            blurRadius: 16.w,
            offset: Offset(0, 8.w),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TrackPod Pro',
                      style: FigmaText.poppins(
                        13,
                        color: Colors.white70,
                        lineHeight: 20,
                      ),
                    ),
                    SizedBox(height: 2.w),
                    Text(
                      'rs 2499',
                      style: FigmaText.poppins(
                        24,
                        weight: FontWeight.w700,
                        color: Colors.white,
                        lineHeight: 27,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 36.w,
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18.w),
                ),
                child: Text(
                  'SAVE 20%',
                  style: FigmaText.poppins(
                    12,
                    weight: FontWeight.w700,
                    color: Colors.white,
                    lineHeight: 18,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.w),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final perk in const [
                'Free shipping',
                '1yr warranty',
                '30d returns',
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 11.w,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      perk,
                      style: FigmaText.poppins(
                        11,
                        color: Colors.white70,
                        lineHeight: 15,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          SizedBox(height: 16.w),
          Semantics(
            button: true,
            label: 'Buy Now',
            child: InkWell(
              onTap: onBuy,
              borderRadius: BorderRadius.circular(16.w),
              child: Container(
                height: 54.5.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.w),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      size: 18.w,
                      color: Color(0xFF1D4ED8),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Buy Now',
                      style: FigmaText.poppins(
                        16,
                        weight: FontWeight.w700,
                        color: Color(0xFF1D4ED8),
                        lineHeight: 22.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Battery Life" card: badge, title + percentage, progress bar, caption.
class DeviceBatteryCard extends StatelessWidget {
  final int? percent;
  final String caption;

  const DeviceBatteryCard({
    super.key,
    required this.percent,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFF59E0B);
    return Container(
      height: 80.w,
      padding: EdgeInsets.fromLTRB(16.w, 14.w, 16.w, 0),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 8.w),
            child: DeviceIconBadge(
              icon: Icons.battery_5_bar_rounded,
              color: orange,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Battery Life',
                        style: FigmaText.poppins(
                          14,
                          weight: FontWeight.w600,
                          color: _ink,
                          lineHeight: 19.5,
                        ),
                      ),
                    ),
                    Text(
                      percent != null ? '$percent%' : '—',
                      style: FigmaText.poppins(
                        14,
                        weight: FontWeight.w600,
                        color: orange,
                        lineHeight: 19.5,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6.w),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3.w),
                  child: LinearProgressIndicator(
                    value: ((percent ?? 0) / 100).clamp(0.0, 1.0),
                    minHeight: 6.w,
                    backgroundColor: Color(0xFFEDEEF1),
                    valueColor: AlwaysStoppedAnimation<Color>(orange),
                  ),
                ),
                SizedBox(height: 4.w),
                Text(
                  caption,
                  style: FigmaText.poppins(12, color: _muted, lineHeight: 16.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "GPS Signal" card with the four signal bars.
class DeviceGpsCard extends StatelessWidget {
  final String caption;

  const DeviceGpsCard({super.key, required this.caption});

  @override
  Widget build(BuildContext context) {
    Widget bar(double h, bool on) => Container(
      width: 4.w,
      height: h.w,
      decoration: BoxDecoration(
        color: on ? Color(0xFF1A73F5) : Color(0xFFE6E8EC),
        borderRadius: BorderRadius.circular(1.w),
      ),
    );
    return Container(
      height: 69.5.w,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          DeviceIconBadge(
            icon: Icons.location_on_outlined,
            color: FigmaColors.primary,
            background: Color(0xFFEFF5FF),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS Signal',
                  style: FigmaText.poppins(
                    14,
                    weight: FontWeight.w600,
                    color: _ink,
                    lineHeight: 20,
                  ),
                ),
                Text(
                  caption,
                  style: FigmaText.poppins(12, color: _muted, lineHeight: 16.5),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              bar(8, true),
              SizedBox(width: 4.w),
              bar(12, true),
              SizedBox(width: 4.w),
              bar(16, true),
              SizedBox(width: 4.w),
              bar(20, false),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Activity (24H)" card: title / View All, 24 bars (Figma heights), axis labels.
class DeviceActivityCard extends StatelessWidget {
  final VoidCallback onViewAll;

  const DeviceActivityCard({super.key, required this.onViewAll});

  static const _heights = <double>[
    8,
    12,
    6,
    16,
    24,
    32,
    36,
    34,
    28,
    30,
    35,
    38,
    40,
    36,
    33,
    30,
    24,
    20,
    16,
    22,
    28,
    18,
    12,
    8,
  ];

  @override
  Widget build(BuildContext context) {
    final axis = FigmaText.poppins(
      11,
      color: Color(0xFF9BA4B5),
      lineHeight: 15,
    );
    return Container(
      height: 123.w,
      padding: EdgeInsets.all(16.w),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Activity (24H)',
                style: FigmaText.poppins(
                  12,
                  weight: FontWeight.w600,
                  color: _muted,
                  lineHeight: 18,
                ),
              ),
              GestureDetector(
                onTap: onViewAll,
                child: Text(
                  'View All',
                  style: FigmaText.poppins(
                    12,
                    weight: FontWeight.w600,
                    color: FigmaColors.primary,
                    lineHeight: 18,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.w),
          SizedBox(
            height: 40.w,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < _heights.length; i++)
                  Container(
                    width: 11.8.w,
                    height: _heights[i].w,
                    decoration: BoxDecoration(
                      color: (i >= 4 && i <= 20)
                          ? FigmaColors.primary.withValues(
                              alpha: (i >= 6 && i <= 18) ? 1 : 0.6,
                            )
                          : Color(0xFFEEF0F4),
                      borderRadius: BorderRadius.circular(3.w),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 10.w),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('12AM', style: axis),
              Text('12PM', style: axis),
              Text('Now', style: axis),
            ],
          ),
        ],
      ),
    );
  }
}
