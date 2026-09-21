import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class LocationDisclosureDialog extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDeny;

  const LocationDisclosureDialog({
    super.key,
    required this.onAccept,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Location Usage Disclosure'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_on,
              size: 48,
              color: AppColors.primaryColor,
            ),
            const SizedBox(height: 16),
            const Text(
              'NaviQ collects location data to enable parent-child location tracking, '
              'even when the app is closed or not in use.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('This data is used to:'),
            const SizedBox(height: 8),
            _buildBulletPoint(
              'Display your child\'s real-time location to parents.',
            ),
            _buildBulletPoint('Create location history and safe zone alerts.'),
            const SizedBox(height: 12),
            Text(
              'Your location data is securely transmitted and stored on our servers. '
              'It is shared only with linked parent accounts.',
              style: TextStyle(fontSize: 12.0.sp, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: onDeny, child: const Text('Deny')),
        ElevatedButton(
          onPressed: onAccept,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Accept'),
        ),
      ],
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
