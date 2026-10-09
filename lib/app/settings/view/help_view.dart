import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'help_detail_view.dart';
import 'widgets/help_support_sheet.dart';

/// Quick questions shown on the Help screen. The first [_kInitialTopics] are
/// always visible; the rest appear under "Show More".
const _kInitialTopics = 3;
const _kHelpTopics = <String>[
  'Location Problems',
  'How do I cancel my subscription',
  'How do I add a new family member',
  'How do I set up a geofence',
  'Why am I not getting notifications',
  'How do I link a GPS tracker',
  'How do I delete my account',
];

class HelpView extends StatefulWidget {
  const HelpView({super.key});

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  bool _showAllTopics = false;

  void _openTopic(String title) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => HelpDetailView(title: title)),
  );

  @override
  Widget build(BuildContext context) {
    final topics = _showAllTopics
        ? _kHelpTopics
        : _kHelpTopics.take(_kInitialTopics).toList();
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
      backgroundColor: Color(0xFFF7F8FA),
      appBar: figmaAppBar(
        context,
        title: 'Help',
        trailing: FigmaCircleButton(
          onTap: () async {
            final picked = await showSearch<String?>(
              context: context,
              delegate: _HelpSearchDelegate([
                ..._kHelpTopics,
                ...tiles.map((t) => t.title),
              ]),
            );
            if (picked != null && mounted) _openTopic(picked);
          },
          child: SvgPicture.asset(
            'assets/help/help_search.svg',
            width: 24.w,
            height: 24.w,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(26.w, 18.w, 26.w, 32.w),
        children: [
          for (final t in topics) _topicRow(t),
          // Figma: "Show More" sits 21px under the last row, All Articles
          // 40px under it.
          SizedBox(height: 13.w),
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showAllTopics = !_showAllTopics),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 8.w),
                child: Text(
                  _showAllTopics ? 'Show Less' : 'Show More',
                  style: GoogleFonts.poppins(
                    fontSize: 12.0.sp,
                    fontWeight: FontWeight.w400,
                    height: 18 / 12,
                    color: Color(0xFF16181A),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 32.w),
          Padding(
            padding: EdgeInsets.only(left: 10.w),
            child: Text(
              'All Articles',
              style: GoogleFonts.poppins(
                fontSize: 16.0.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(height: 24.w),
          for (var i = 0; i < tiles.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: 13.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _articleTile(context, tiles[i]),
                  SizedBox(width: 11.w),
                  _articleTile(context, tiles[i + 1]),
                ],
              ),
            ),
          SizedBox(height: 13.w),
          Center(
            child: GestureDetector(
              onTap: () => showHelpSupportOptions(context),
              child: Container(
                width: 335.w,
                height: 38.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8.w),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 5.6.w,
                      offset: Offset(0.w, 4.w),
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
                    color: Color(0xFF0069F9),
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
    return GestureDetector(
      onTap: () => _openTopic(label),
      child: Container(
        constraints: BoxConstraints(minHeight: 55.w),
        margin: EdgeInsets.only(bottom: 13.w),
        padding: EdgeInsets.symmetric(horizontal: 17.w, vertical: 8.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.w),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 40.w),
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
                width: 26.w,
                height: 26.w,
              ),
            ),
          ],
        ),
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
        width: 159.w,
        height: 159.w,
        decoration: BoxDecoration(
          color: Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12.w),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 7.8.w,
              spreadRadius: 2.w,
              offset: Offset(0.w, 4.w),
            ),
          ],
        ),
        child: Column(
          children: [
            SizedBox(height: 17.w),
            Container(
              width: 73.w,
              height: 73.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color(0xFFEBF3FF),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/help/help_${tile.icon}.png',
                width: tile.iconSize,
                height: tile.iconSize,
              ),
            ),
            Spacer(),
            Padding(
              padding: EdgeInsets.only(bottom: 22.w),
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

/// Searches the quick questions and article categories; selecting a result
/// opens its help page.
class _HelpSearchDelegate extends SearchDelegate<String?> {
  _HelpSearchDelegate(this._entries);
  final List<String> _entries;

  @override
  String get searchFieldLabel => 'Search help';

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(icon: Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final q = query.trim().toLowerCase();
    final matches = _entries
        .where((e) => q.isEmpty || e.toLowerCase().contains(q))
        .toList();
    if (matches.isEmpty) {
      return Center(
        child: Text('No results', style: GoogleFonts.poppins(fontSize: 14)),
      );
    }
    return ListView(
      children: [
        for (final m in matches)
          ListTile(
            title: Text(m, style: GoogleFonts.poppins(fontSize: 14)),
            trailing: Icon(Icons.chevron_right),
            onTap: () => close(context, m),
          ),
      ],
    );
  }
}
