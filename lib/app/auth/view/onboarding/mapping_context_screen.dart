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
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // App logo / icon representation
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066FF).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.shield_fill,
                    color: Color(0xFF0066FF),
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(height: 32),

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
              const SizedBox(height: 12),

              // Subheadline
              Text(
                "Because of Apple's strict privacy policies, iOS hides the names and icons of your child's applications from tracking services.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[400],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),

              // Benefit Cards (using rich aesthetic container style)
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildInfoCard(
                      icon: CupertinoIcons.checkmark_shield_fill,
                      title: "Standard Privacy Compliance",
                      subtitle:
                          "We don't read personal details or messages. Only time limits are synchronized.",
                    ),
                    const SizedBox(height: 16),
                    _buildInfoCard(
                      icon: CupertinoIcons.eye_fill,
                      title: "Beautiful Dashboard",
                      subtitle:
                          "Manual mapping replaces meaningless system hashes with recognizable app names & icons.",
                    ),
                    const SizedBox(height: 16),
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
                  backgroundColor: const Color(0xFF0066FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: onContinue,
                child: Text(
                  "Get Started",
                  style: TextStyle(fontSize: 16.0.sp, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 10),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2C2C2E), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0066FF), size: 24),
          const SizedBox(width: 16),
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
                const SizedBox(height: 6),
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
