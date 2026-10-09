import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class MappingContextScreen extends StatelessWidget {
  final VoidCallback onContinue;

  const MappingContextScreen({Key? key, required this.onContinue})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.0.w, vertical: 16.0.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 20.w),
              // App logo / icon representation
              Center(
                child: Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: Color(0xFF0066FF).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.shield_fill,
                    color: Color(0xFF0066FF),
                    size: 48.w,
                  ),
                ),
              ),
              SizedBox(height: 32.w),

              // Headline
              Text(
                "Why App Mapping?",
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 12.w),

              // Subheadline
              Text(
                "Because of Apple's strict privacy policies, iOS hides the names and icons of your child's applications from tracking services.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[400],
                  height: 1.5,
                ),
              ),
              SizedBox(height: 40.w),

              // Benefit Cards (using rich aesthetic container style)
              Expanded(
                child: ListView(
                  physics: BouncingScrollPhysics(),
                  children: [
                    _buildInfoCard(
                      icon: CupertinoIcons.checkmark_shield_fill,
                      title: "Standard Privacy Compliance",
                      subtitle:
                          "We don't read personal details or messages. Only time limits are synchronized.",
                    ),
                    SizedBox(height: 16.w),
                    _buildInfoCard(
                      icon: CupertinoIcons.eye_fill,
                      title: "Beautiful Dashboard",
                      subtitle:
                          "Manual mapping replaces meaningless system hashes with recognizable app names & icons.",
                    ),
                    SizedBox(height: 16.w),
                    _buildInfoCard(
                      icon: CupertinoIcons.device_phone_portrait,
                      title: "Simple One-Time Mapping",
                      subtitle:
                          "You select target apps one-by-one in the Apple sheet to pair them correctly.",
                    ),
                  ],
                ),
              ),

              // Action Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF0066FF),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16.w),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.w),
                  ),
                  elevation: 0,
                ),
                onPressed: onContinue,
                child: Text(
                  "Get Started",
                  style: TextStyle(
                    fontSize: 16.0.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: 10.w),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(18.w),
        border: Border.all(color: Color(0xFF2C2C2E), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Color(0xFF0066FF), size: 24.w),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.0.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 6.w),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 13.0.sp,
                    height: 1.4,
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
