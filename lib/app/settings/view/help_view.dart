import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'help_detail_view.dart';

class HelpView extends StatelessWidget {
  const HelpView({super.key});

  @override
  Widget build(BuildContext context) {
    final topics = [
      'Location Problems',
      'How do I cancel my subscription',
      'How do I add a new family member',
    ];
    // title is what HelpDetailView receives; label/icon are Figma's display.
    final tiles = <_HelpTile>[
      const _HelpTile(
        'Troubleshooting',
        'Troubleshooting',
        'troubleshooting',
        40,
      ),
      const _HelpTile(
        'Subscription & Billing',
        'Subscription',
        'subscription',
        40,
      ),
      const _HelpTile('Account & Data', 'Account & Data', 'account', 40),
      const _HelpTile('How do I use the app', 'Using App', 'using_app', 40),
      const _HelpTile(
        'Getting Started',
        'Getting Started',
        'getting_started',
        50,
      ),
      const _HelpTile('GPS Device', 'GPS Device', 'gps_device', 50),
      const _HelpTile('Privacy & Security', 'Privacy', 'privacy', 40),
      const _HelpTile('The App on a Computer', 'Desktop', 'desktop', 40),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: figmaAppBar(
        context,
        title: 'Help',
        trailing: FigmaCircleButton(
          child: SvgPicture.asset(
            'assets/help/help_search.svg',
            width: 24,
            height: 24,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(26, 18, 26, 32),
        children: [
          for (final t in topics) _topicRow(t),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              'All Articles',
              style: GoogleFonts.poppins(
                fontSize: 16.0.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < tiles.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _articleTile(context, tiles[i]),
                  const SizedBox(width: 11),
                  _articleTile(context, tiles[i + 1]),
                ],
              ),
            ),
          const SizedBox(height: 13),
          Center(
            child: GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat support coming soon')),
                );
              },
              child: Container(
                width: 335,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 5.6,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  'None of the above',
                  style: GoogleFonts.poppins(
                    fontSize: 20.0.sp,
                    fontWeight: FontWeight.w400,
                    height: 28 / 20,
                    letterSpacing: 0.2,
                    color: const Color(0xFF0069F9),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topicRow(String label) {
    return Container(
      constraints: const BoxConstraints(minHeight: 55),
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 40),
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 16.0.sp,
                  fontWeight: FontWeight.w400,
                  height: 24 / 16,
                  letterSpacing: 0.2,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          RotatedBox(
            quarterTurns: 2,
            child: Image.asset(
              'assets/icons/auth_back.png',
              width: 26,
              height: 26,
            ),
          ),
        ],
      ),
    );
  }

  Widget _articleTile(BuildContext context, _HelpTile tile) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HelpDetailView(title: tile.title)),
      ),
      child: Container(
        width: 159,
        height: 159,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 7.8,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 17),
            Container(
              width: 73,
              height: 73,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFEBF3FF),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/help/help_${tile.icon}.png',
                width: tile.iconSize,
                height: tile.iconSize,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Text(
                tile.label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 16.0.sp,
                  fontWeight: FontWeight.w400,
                  height: 24 / 16,
                  letterSpacing: 0.2,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpTile {
  final String title;
  final String label;
  final String icon;
  final double iconSize;
  const _HelpTile(this.title, this.label, this.icon, this.iconSize);
}
