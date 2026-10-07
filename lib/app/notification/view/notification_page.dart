import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:intl/intl.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  final SharedPrefsService _prefs = SharedPrefsService();
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  void _loadNotifications() {
    setState(() {
      _notifications = _prefs.getNotifications();
    });
  }

  Future<void> _clearAllNotifications() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Clear Notifications',
          style: GoogleFonts.poppins(
            fontSize: 18.0.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1D37),
          ),
        ),
        content: Text(
          'Are you sure you want to clear all notifications?',
          style: GoogleFonts.poppins(
            fontSize: 14.0.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                fontSize: 14.0.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear All',
              style: GoogleFonts.poppins(
                fontSize: 14.0.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _prefs.clearNotifications();
      _loadNotifications();
    }
  }

  Future<void> _deleteNotification(String id) async {
    final updated = _notifications.where((n) => n['id'] != id).toList();
    await _prefs.saveNotifications(updated);
    _loadNotifications();
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return '';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24 && dateTime.day == now.day) {
        return DateFormat('hh:mm a').format(dateTime);
      } else if (dateTime.day == now.subtract(const Duration(days: 1)).day &&
          dateTime.month == now.month &&
          dateTime.year == now.year) {
        return 'Yesterday, ${DateFormat('hh:mm a').format(dateTime)}';
      } else {
        return DateFormat('MMM d, hh:mm a').format(dateTime);
      }
    } catch (e) {
      return '';
    }
  }

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'SOS':
        return Icons.emergency_rounded;
      case 'SAFE_PLACE_ARRIVAL':
      case 'SAFE_PLACE_DEPARTURE':
        return Icons.location_on_rounded;
      case 'TRIP_STARTED':
      case 'TRIP_ENDED':
        return Icons.navigation_rounded;
      case 'LOW_BATTERY':
        return Icons.battery_alert_rounded;
      case 'DEVICE_OFFLINE':
        return Icons.signal_cellular_connected_no_internet_4_bar_rounded;
      case 'CHAT_MESSAGE':
        return Icons.chat_bubble_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getColorForType(String? type) {
    switch (type) {
      case 'SOS':
        return const Color(0xFFEF4444); // Red
      case 'SAFE_PLACE_ARRIVAL':
        return const Color(0xFF10B981); // Green
      case 'SAFE_PLACE_DEPARTURE':
        return const Color(0xFF0066FF); // Blue
      case 'TRIP_STARTED':
      case 'TRIP_ENDED':
        return const Color(0xFF6366F1); // Indigo
      case 'LOW_BATTERY':
        return const Color(0xFFF59E0B); // Amber
      case 'DEVICE_OFFLINE':
        return const Color(0xFF64748B); // Slate/Grey
      case 'CHAT_MESSAGE':
        return const Color(0xFFF97316); // Orange
      default:
        return const Color(0xFF0066FF); // Default Blue
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: figmaAppBar(
        context,
        title: 'Notifications',
        titleSize: 24,
        titleColor: const Color(0xFF0F1320),
        trailing: _notifications.isEmpty
            ? null
            : GestureDetector(
                onTap: _clearAllNotifications,
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  color: Colors.transparent,
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
      ),
      body: _notifications.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                final id = notification['id'] as String? ?? '';
                final title = notification['title'] as String? ?? 'NaviQ';
                final body = notification['body'] as String? ?? '';
                final timestamp = notification['timestamp'] as String?;
                final type = notification['type'] as String?;

                return Dismissible(
                  key: Key(id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  onDismissed: (_) => _deleteNotification(id),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Container(
                            height: 36,
                            width: 36,
                            decoration: BoxDecoration(
                              color: _getColorForType(type),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getIconForType(type),
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.poppins(
                                  fontSize: 13.0.sp,
                                  fontWeight: FontWeight.w700,
                                  height: 19.5 / 13,
                                  color: const Color(0xFF0F1320),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  body,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.0.sp,
                                    fontWeight: FontWeight.w400,
                                    height: 16.5 / 11,
                                    color: const Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _formatTimestamp(timestamp),
                                  style: GoogleFonts.poppins(
                                    fontSize: 10.0.sp,
                                    fontWeight: FontWeight.w400,
                                    height: 15 / 10,
                                    color: const Color(0xFF9BA4B5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _deleteNotification(id),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, top: 2),
                            child: Text(
                              '×',
                              style: GoogleFonts.poppins(
                                fontSize: 16.0.sp,
                                fontWeight: FontWeight.w500,
                                height: 1.0,
                                color: const Color(0xFFD1D5DC),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 100,
              width: 100,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF), // soft blue background
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: Color(0xFF0066FF),
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Notifications Yet',
              style: GoogleFonts.poppins(
                fontSize: 18.0.sp,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0C1D37),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'All caught up! You will see real-time updates and alerts about your child here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14.0.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
