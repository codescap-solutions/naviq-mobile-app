import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:google_fonts/google_fonts.dart';
import 'location_selections.dart';
import 'widgets/preset_place_card_body.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class PlaceSelectionScreen extends StatefulWidget {
  final String? childId;
  final String? parentId;

  const PlaceSelectionScreen({super.key, this.childId, this.parentId});

  @override
  State<PlaceSelectionScreen> createState() => _PlaceSelectionScreenState();
}

class _PlaceSelectionScreenState extends State<PlaceSelectionScreen> {
  final TextEditingController _customPlaceController = TextEditingController();
  bool _canCreate = false;

  @override
  void initState() {
    super.initState();
    _customPlaceController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _customPlaceController.removeListener(_onTextChanged);
    _customPlaceController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _canCreate = _customPlaceController.text.trim().isNotEmpty;
    });
  }

  void _navigateToMap({
    required String category,
    required String customName,
    bool isCurrentLocation = false,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationSelectionScreen(
          childId: widget.childId,
          parentId: widget.parentId,
          selectedCategory: category,
          customName: customName,
          isCurrentLocation: isCurrentLocation,
        ),
      ),
    ).then((result) {
      if (result != null && mounted) {
        Navigator.pop(context, result);
      }
    });
  }

  Widget _buildPresetCard({
    required String label,
    required String emoji,
    required Color circleBg,
    required String category,
    bool isCurrentLocation = false,
  }) {
    return GestureDetector(
      onTap: () => _navigateToMap(
        category: category,
        customName: label,
        isCurrentLocation: isCurrentLocation,
      ),
      child: PresetPlaceCardBody(label: label, emoji: emoji, color: circleBg),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Figma "New Fencing": a bottom sheet over the Geofencing list — white,
    // 12px top radius, preset grid, custom-place card, Create button.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 12,
                  childAspectRatio:
                      (MediaQuery.of(context).size.width - 36) / 2 / 102,
                  children: [
                    _buildPresetCard(
                      label: "School",
                      emoji: '🏫',
                      circleBg: const Color(0xFF0DBF75),
                      category: "school",
                    ),
                    _buildPresetCard(
                      label: "Coaching",
                      emoji: '🎓',
                      circleBg: const Color(0xFFF5A623),
                      category: "tuition",
                    ),
                    _buildPresetCard(
                      label: "Grandma's",
                      emoji: '👵',
                      circleBg: const Color(0xFFF03E3E),
                      category: "other",
                    ),
                    _buildPresetCard(
                      label: "Temple/Masjid",
                      emoji: '⛪',
                      circleBg: const Color(0xFF0069F9),
                      category: "other",
                    ),
                    _buildPresetCard(
                      label: "Sports Ground",
                      emoji: '🏏',
                      circleBg: const Color(0xFF003A8C),
                      category: "other",
                    ),
                    _buildPresetCard(
                      label: "Current Location",
                      emoji: '📍',
                      circleBg: const Color(0xFF9BA4B5),
                      category: "other",
                      isCurrentLocation: true,
                    ),
                  ],
                ),
              ),
              // Add Custom Place: white card, 12px padding, soft shadow, with a
              // 50px bordered input (Figma "AddItemCard").
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFDDE1EA)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 6,
                        spreadRadius: -1,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        spreadRadius: -2,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _customPlaceController,
                    style: GoogleFonts.poppins(
                      fontSize: 16.0.sp,
                      fontWeight: FontWeight.w400,
                      height: 24 / 16,
                      letterSpacing: 0.2,
                      color: const Color(0xFF0F1320),
                    ),
                    decoration: InputDecoration(
                      hintText: "Add Custom Place",
                      hintStyle: GoogleFonts.poppins(
                        fontSize: 16.0.sp,
                        fontWeight: FontWeight.w400,
                        height: 24 / 16,
                        letterSpacing: 0.2,
                        color: const Color(0xFF9BA4B5),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isCollapsed: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              // Create button row
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                alignment: Alignment.centerRight,
                color: Colors.white,
                child: GestureDetector(
                  onTap: _canCreate
                      ? () {
                          _navigateToMap(
                            category: "other",
                            customName: _customPlaceController.text.trim(),
                          );
                        }
                      : null,
                  child: Opacity(
                    opacity: _canCreate ? 1 : 0.5,
                    child: Container(
                      width: 75,
                      padding: const EdgeInsets.all(10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0069F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Create",
                        style: GoogleFonts.poppins(
                          fontSize: 10.0.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 38 + MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }
}
