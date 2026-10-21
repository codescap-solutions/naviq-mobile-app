import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:flutter/material.dart';

/// The Figma "Device" screen for a parent who has no tracker yet: hero banner,
/// "Key Features" panel with price + quantity, Buy / Activate card,
/// "How It Works" and the reassurance card. All sizes are Figma px.
class DevicePitch extends StatefulWidget {
  final VoidCallback onBuy;
  final VoidCallback onActivate;

  const DevicePitch({super.key, required this.onBuy, required this.onActivate});

  @override
  State<DevicePitch> createState() => _DevicePitchState();
}

class _DevicePitchState extends State<DevicePitch> {
  int _quantity = 1;

  static const _ink = Color(0xFF16181A);
  static const _grey = Color(0xFF707784);
  static const _blue = FigmaColors.primary;

  BoxDecoration get _whiteCard => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24.w),
    border: Border.all(color: const Color(0xFFEEF0F4)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 10.w,
        offset: Offset(0, 2.w),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        12.w,
        12.w,
        12.w,
        40.w + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        children: [
          _hero(),
          SizedBox(height: 12.w),
          _keyFeatures(),
          SizedBox(height: 12.w),
          _buyCard(),
          SizedBox(height: 12.w),
          _howItWorks(),
          SizedBox(height: 12.w),
          _assurances(),
        ],
      ),
    );
  }

  // ── Hero ────────────────────────────────────────────────────────────────
  Widget _hero() {
    return Container(
      height: 136.w,
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      decoration: BoxDecoration(
        color: const Color(0xFFB9D3F6),
        borderRadius: BorderRadius.circular(24.w),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS TRACKER',
                  style: FigmaText.bodySmall.copyWith(
                    color: const Color(0xFF2F6BF2),
                    height: 1.2,
                  ),
                ),
                Text(
                  'TrackPod Pro',
                  style: FigmaText.poppins(
                    24,
                    weight: FontWeight.w700,
                    lineHeight: 32,
                    color: const Color(0xFF0F1320),
                  ),
                ),
                Text(
                  'For safer tomorrow',
                  style: FigmaText.bodyMedium.copyWith(color: _ink),
                ),
              ],
            ),
          ),
          Image.asset(
            'assets/images/trackpod_device.png',
            width: 104.w,
            height: 104.w,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  // ── Key Features ────────────────────────────────────────────────────────
  Widget _keyFeatures() {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 18.w, 16.w, 18.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28.w),
        gradient: const LinearGradient(
          colors: [Color(0xFF01429C), Color(0xFF0068F2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Key Features',
                  style: FigmaText.poppins(
                    16,
                    weight: FontWeight.w600,
                    lineHeight: 24,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 20.w),
            ],
          ),
          SizedBox(height: 6.w),
          _divider(),
          SizedBox(height: 10.w),
          Row(
            children: [
              Expanded(
                child: _feature(Icons.location_on_rounded, 'Live GPS Tracking'),
              ),
              SizedBox(width: 10.w),
              Expanded(child: _feature(null, 'SOS Button', badge: 'SOS')),
            ],
          ),
          SizedBox(height: 10.w),
          Row(
            children: [
              Expanded(
                child: _feature(Icons.shield_rounded, 'Safe Zone Alerts'),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _feature(
                  Icons.battery_full_rounded,
                  'Long Battery Life',
                ),
              ),
            ],
          ),
          SizedBox(height: 14.w),
          Text(
            'TrackPod Pro',
            style: FigmaText.bodyLarge.copyWith(color: Colors.white),
          ),
          SizedBox(height: 2.w),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '₹2,499',
                style: FigmaText.poppins(
                  28,
                  weight: FontWeight.w700,
                  lineHeight: 36,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 6.w),
              Text(
                '₹3,099',
                style: FigmaText.bodyMedium.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  decoration: TextDecoration.lineThrough,
                  decorationColor: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.w),
                decoration: BoxDecoration(
                  color: const Color(0xFFD3262E),
                  borderRadius: BorderRadius.circular(8.w),
                ),
                child: Text(
                  'Save 20%',
                  style: FigmaText.labelSmall.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.w),
          _divider(),
          SizedBox(height: 8.w),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _perk(Icons.inventory_2_outlined, 'Free shipping'),
              _perkDivider(),
              _perk(Icons.verified_user_outlined, '1 year warranty'),
              _perkDivider(),
              _perk(Icons.sync_rounded, '30-day return'),
            ],
          ),
          SizedBox(height: 8.w),
          _divider(),
          SizedBox(height: 18.w),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Quantity',
                  style: FigmaText.poppins(
                    16,
                    weight: FontWeight.w600,
                    lineHeight: 24,
                    color: Colors.white,
                  ),
                ),
              ),
              _stepper(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(height: 1, color: Colors.white.withValues(alpha: 0.85));

  Widget _feature(IconData? icon, String label, {String? badge}) {
    return Container(
      height: 48.w,
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14.w),
      ),
      child: Row(
        children: [
          Container(
            width: 32.w,
            height: 32.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _ink, width: 1),
            ),
            child: badge != null
                ? Text(
                    badge,
                    style: FigmaText.poppins(
                      10,
                      weight: FontWeight.w700,
                      lineHeight: 10,
                      color: _ink,
                    ),
                  )
                : Icon(icon, size: 16.w, color: _ink),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FigmaText.bodySmall.copyWith(color: _ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _perk(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14.w, color: Colors.white),
        SizedBox(width: 4.w),
        Text(text, style: FigmaText.bodySmall.copyWith(color: Colors.white)),
      ],
    );
  }

  Widget _perkDivider() => Container(
    width: 1,
    height: 18.w,
    color: Colors.white.withValues(alpha: 0.85),
  );

  Widget _stepper() {
    Widget btn(IconData icon, VoidCallback onTap) => InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 36.w,
        height: 36.w,
        child: Icon(icon, size: 16.w, color: _ink),
      ),
    );
    return Container(
      height: 36.w,
      decoration: BoxDecoration(
        color: const Color(0xFFD6E4F7),
        borderRadius: BorderRadius.circular(18.w),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded, () {
            if (_quantity > 1) setState(() => _quantity--);
          }),
          SizedBox(
            width: 28.w,
            child: Text(
              '$_quantity',
              textAlign: TextAlign.center,
              style: FigmaText.poppins(
                16,
                weight: FontWeight.w600,
                lineHeight: 24,
                color: _ink,
              ),
            ),
          ),
          btn(Icons.add_rounded, () {
            if (_quantity < 10) setState(() => _quantity++);
          }),
        ],
      ),
    );
  }

  // ── Buy / Activate ──────────────────────────────────────────────────────
  Widget _buyCard() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: _whiteCard,
      child: Column(
        children: [
          Material(
            color: _blue,
            borderRadius: BorderRadius.circular(16.w),
            child: InkWell(
              borderRadius: BorderRadius.circular(16.w),
              onTap: widget.onBuy,
              child: SizedBox(
                height: 50.w,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      color: Colors.white,
                      size: 20.w,
                    ),
                    SizedBox(width: 10.w),
                    Text(
                      'Buy & Activate',
                      style: FigmaText.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 10.w),
          InkWell(
            borderRadius: BorderRadius.circular(14.w),
            onTap: widget.onActivate,
            child: Container(
              height: 44.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14.w),
                border: Border.all(color: const Color(0xFFDDE1EA)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have a device? ',
                    style: FigmaText.bodySmall.copyWith(
                      color: const Color(0xFF2D3035),
                    ),
                  ),
                  Text(
                    'Activate it',
                    style: FigmaText.bodySmall.copyWith(
                      color: _blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 16.w, color: _blue),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── How It Works ────────────────────────────────────────────────────────
  Widget _howItWorks() {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 16.w, 16.w, 16.w),
      decoration: _whiteCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How It Works',
            style: FigmaText.poppins(
              20,
              weight: FontWeight.w700,
              lineHeight: 28,
              color: _ink,
            ),
          ),
          SizedBox(height: 14.w),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _step(
                  Icons.shopping_cart_outlined,
                  1,
                  'Buy device',
                  'Order TrackPod Pro\nfrom the app',
                ),
              ),
              _arrow(),
              Expanded(
                child: _step(
                  Icons.local_shipping_outlined,
                  2,
                  'Receive',
                  'Get it delivered to\nyour home',
                ),
              ),
              _arrow(),
              Expanded(
                child: _step(
                  Icons.smartphone_rounded,
                  3,
                  'Link App',
                  'Follow simple steps\nto get started',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _arrow() => Padding(
    padding: EdgeInsets.only(top: 16.w),
    child: Icon(Icons.arrow_forward_rounded, size: 16.w, color: _blue),
  );

  Widget _step(IconData icon, int n, String title, String caption) {
    return Column(
      children: [
        Container(
          width: 48.w,
          height: 48.w,
          decoration: const BoxDecoration(
            color: Color(0xFFF3F4F6),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22.w, color: _ink),
        ),
        SizedBox(height: 10.w),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 16.w,
              height: 16.w,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: _blue,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$n',
                style: FigmaText.poppins(
                  10,
                  weight: FontWeight.w600,
                  lineHeight: 10,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(width: 4.w),
            Flexible(
              child: Text(
                title,
                style: FigmaText.poppins(
                  12,
                  weight: FontWeight.w600,
                  lineHeight: 16,
                  color: _ink,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 4.w),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: FigmaText.poppins(
            10,
            lineHeight: 14,
            letterSpacing: 0.2,
            color: _grey,
          ),
        ),
      ],
    );
  }

  // ── SIM + payment assurances ────────────────────────────────────────────
  Widget _assurances() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.w),
      decoration: _whiteCard,
      child: Column(
        children: [
          _assurance(
            Icons.inventory_2_outlined,
            const Color(0xFFEAF2FF),
            _blue,
            'SIM / device setup instructions included',
            'Everything you need will be in the box',
          ),
          Container(height: 1, color: const Color(0xFFEEF0F4)),
          _assurance(
            Icons.lock_outline_rounded,
            const Color(0xFFE6F6EE),
            FigmaColors.success,
            '100% Secure Payment',
            'Your payment information is encrypted',
            footer: Row(
              children: [
                Text(
                  'UPI',
                  style: FigmaText.poppins(
                    10,
                    weight: FontWeight.w700,
                    lineHeight: 14,
                    color: const Color(0xFF3D4A66),
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
                SizedBox(width: 8.w),
                Text(
                  'VISA',
                  style: FigmaText.poppins(
                    10,
                    weight: FontWeight.w700,
                    lineHeight: 14,
                    color: const Color(0xFF1A4FA3),
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
                SizedBox(width: 8.w),
                SizedBox(
                  width: 22.w,
                  height: 14.w,
                  child: Stack(
                    children: [
                      Positioned(left: 0, child: _dot(const Color(0xFFEB001B))),
                      Positioned(
                        left: 8.w,
                        child: _dot(const Color(0xFFF79E1B)),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                Text(
                  'RuPay',
                  style: FigmaText.poppins(
                    10,
                    weight: FontWeight.w700,
                    lineHeight: 14,
                    color: const Color(0xFF1A4FA3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 14.w,
    height: 14.w,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  Widget _assurance(
    IconData icon,
    Color bg,
    Color fg,
    String title,
    String subtitle, {
    Widget? footer,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32.w,
            height: 32.w,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10.w),
            ),
            child: Icon(icon, size: 16.w, color: fg),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: FigmaText.poppins(
                    14,
                    weight: FontWeight.w600,
                    lineHeight: 20,
                    color: _ink,
                  ),
                ),
                Text(
                  subtitle,
                  style: FigmaText.bodySmall.copyWith(
                    color: const Color(0xFF2D3035),
                  ),
                ),
                if (footer != null) ...[SizedBox(height: 4.w), footer],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
