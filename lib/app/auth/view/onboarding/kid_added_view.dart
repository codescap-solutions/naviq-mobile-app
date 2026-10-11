import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/widgets/figma_primary_button.dart';
import 'package:flutter/material.dart';

/// Shown after a kid is added with a tracker serial number: nothing more to
/// set up on a phone, so the only action is to go Home.
class KidAddedView extends StatelessWidget {
  final String kidName;
  final String serial;

  const KidAddedView({super.key, required this.kidName, required this.serial});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Column(
            children: [
              Spacer(),
              Container(
                width: 96.w,
                height: 96.w,
                decoration: BoxDecoration(
                  color: Color(0xFFE6F7EC),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 56.w,
                  color: Color(0xFF57BC7B),
                ),
              ),
              SizedBox(height: 32.w),
              Text(
                'Kid added successfully',
                textAlign: TextAlign.center,
                style: FigmaText.poppins(
                  24,
                  weight: FontWeight.w700,
                  lineHeight: 33,
                ),
              ),
              SizedBox(height: 12.w),
              Text(
                '$kidName is linked to tracker $serial. Location appears on '
                'Home as soon as the tracker is switched on.',
                textAlign: TextAlign.center,
                style: FigmaText.poppins(
                  14,
                  color: FigmaColors.body,
                  lineHeight: 20,
                ),
              ),
              Spacer(),
              FigmaPrimaryButton(
                label: 'Go to Home',
                onPressed: () => Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(RouteNames.home, (route) => false),
              ),
              SizedBox(height: 33.w),
            ],
          ),
        ),
      ),
    );
  }
}
