import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_text_styles.dart';

/// Shows a trip/place name, falling back to on-device reverse geocoding
/// when the backend couldn't match a saved place (raw value is the literal
/// string "Unknown Location") but a coordinate is available — e.g. a street
/// address the parent never saved as a place. Mirrors the same fallback
/// already used in trips_view.dart's list rendering, just made reusable so
/// other trip screens (e.g. the detail view) get the same behavior instead
/// of showing the raw "Unknown Location" string with no rescue.
class ResolvedPlaceLabel extends StatefulWidget {
  final String placeName;
  final double? lat;
  final double? lng;
  final Color iconColor;
  final TextStyle? textStyle;
  final bool showDot;

  const ResolvedPlaceLabel({
    super.key,
    required this.placeName,
    required this.lat,
    required this.lng,
    this.iconColor = Colors.grey,
    this.textStyle,
    this.showDot = true,
  });

  @override
  State<ResolvedPlaceLabel> createState() => _ResolvedPlaceLabelState();
}

class _ResolvedPlaceLabelState extends State<ResolvedPlaceLabel> {
  String? _resolvedAddress;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (_shouldResolveAddress()) {
      _resolveAddress();
    }
  }

  bool _shouldResolveAddress() {
    return widget.placeName == "Unknown Location" &&
        widget.lat != null &&
        widget.lng != null &&
        widget.lat != 0.0 &&
        widget.lng != 0.0;
  }

  Future<void> _resolveAddress() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final placemarks = await placemarkFromCoordinates(
        widget.lat!,
        widget.lng!,
      );

      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        setState(() {
          _resolvedAddress = [
            place.street,
            place.subLocality,
            place.locality,
          ].where((e) => e != null && e.isNotEmpty).join(', ');

          if (_resolvedAddress!.isEmpty) {
            _resolvedAddress = place.name;
          }
        });
      }
    } catch (_) {
      // Best-effort fallback — keep showing the raw placeName on failure.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _resolvedAddress ?? widget.placeName;

    return Row(
      children: [
        if (widget.showDot) ...[
          Icon(Icons.circle, size: 8, color: widget.iconColor),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: _isLoading
              ? SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textSecondary,
                  ),
                )
              : Text(
                  displayText,
                  style: widget.textStyle ?? AppTextStyles.body2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }
}
