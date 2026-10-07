import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:child_track/core/widgets/figma_toggle.dart';

class NotificationSettingsView extends StatefulWidget {
  const NotificationSettingsView({super.key});

  @override
  State<NotificationSettingsView> createState() =>
      _NotificationSettingsViewState();
}

class _NotificationSettingsViewState extends State<NotificationSettingsView> {
  final _sharedPrefsService = SharedPrefsService();

  // The only toggles on this screen with real backend enforcement today —
  // everything else here is UI-only (see notif_* local prefs below), pending
  // the underlying detection/notification feature actually being built.
  // Maps each toggle's exact label to its NotificationPreferences dot path.
  static const Map<String, String> _backendFieldForTitle = {
    'Entering a Place': 'notifications.safePlaceArrival.enabled',
    'Leaving a Place': 'notifications.safePlaceDeparture.enabled',
    'Starting Trip': 'notifications.tripStarted.enabled',
    'Low Battery Notification': 'notifications.lowBattery.enabled',
    'Signal Loss/GPS Offline Alert': 'notifications.deviceOffline.enabled',
  };

  final Map<String, bool> _backendValues = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBackendPreferences();
  }

  Future<void> _loadBackendPreferences() async {
    try {
      final response = await injector<HomeRepository>()
          .getNotificationPreferences();
      if (response.isSuccess && response.data != null) {
        final notifications =
            response.data!['notifications'] as Map<String, dynamic>? ?? {};
        for (final entry in _backendFieldForTitle.entries) {
          // fieldPath is "notifications.<key>.enabled" — pull "<key>" out.
          final parts = entry.value.split('.');
          final key = parts[1];
          final section = notifications[key] as Map<String, dynamic>?;
          _backendValues[entry.value] = (section?['enabled'] as bool?) ?? true;
        }
      } else if (mounted) {
        // Previously fully silent — defaults (true) still render so the
        // screen isn't broken, but a genuine fetch failure used to give no
        // indication these toggles might not reflect the real saved state.
        AppSnackbar.showError(
          context,
          'Could not load your saved notification settings — showing defaults.',
        );
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.showError(
          context,
          'Could not load your saved notification settings — showing defaults.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleBackendPref(String fieldPath, bool newValue) async {
    final previous = _backendValues[fieldPath] ?? true;
    setState(() => _backendValues[fieldPath] = newValue);

    final response = await injector<HomeRepository>()
        .updateNotificationPreference(fieldPath: fieldPath, enabled: newValue);

    if (!response.isSuccess && mounted) {
      setState(() => _backendValues[fieldPath] = previous);
      AppSnackbar.showError(
        context,
        'Failed to update setting. Please try again.',
      );
    }
  }

  /// Display text per toggle where Figma words it differently from the key.
  /// The key (the title used below) still drives the saved-preference name
  /// and the backend field mapping, so renaming a label never loses a
  /// parent's saved setting.
  static const Map<String, String> _figmaLabel = {
    'Route Deviation': 'Route Ended',
    'Estimated arrival at a place': 'Estimated Arrival at a Place',
    'Movement speed': 'Movement Speed',
    'Geofences Boundary Alerts': 'Geo Fence Boundary Alerts',
    'Signal Loss/GPS Offline Alert': 'Signal Loss / GPS Offline Alert',
    'Scheduled School Delivery': 'Scheduled Reminder Delivery',
    'Manual Whistle Clock': 'Mental Wellness Check',
    'Real-time Accurate Notification': 'Routine Adherence Notification',
    'App Updates/Reminder Alert': 'App Update / Permissions Alert',
  };

  static const List<String> _allTitles = [
    'Entering a Place',
    'Leaving a Place',
    'New Place',
    'Starting Trip',
    'Route Deviation',
    'Estimated arrival at a place',
    'Movement speed',
    'Geofences Boundary Alerts',
    'Route Deviation Warning',
    'Unusual Stop Detection',
    'Low Battery Notification',
    'Signal Loss/GPS Offline Alert',
    'Device Tampering Alert',
    'Connectivity Loss Alert',
    'App Status Alert',
    'New Message Notification',
    'Missed Communication Alert',
    'Scheduled School Delivery',
    'Manual Whistle Clock',
    'Daily Step Count Report',
    'Prolonged Inactivity Alert',
    'Daily Movement Summary',
    'Weekly Safety & Activity Report',
    'Real-time Accurate Notification',
    'Weather Report',
    'New Family Member Alert',
    'App Updates/Reminder Alert',
  ];

  String _prefKey(String title) =>
      'notif_${title.toLowerCase().replaceAll(' ', '_').replaceAll('/', '_').replaceAll('&', '_')}';

  bool _valueFor(String title) {
    final backendField = _backendFieldForTitle[title];
    if (backendField != null) return _backendValues[backendField] ?? true;
    return _sharedPrefsService.getBool(_prefKey(title), defaultValue: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: figmaAppBar(context, title: 'Notifications', titleSize: 24),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildActiveSummary(),
                    const SizedBox(height: 10),
                    _buildSection('Movements', const [
                      'Entering a Place',
                      'Leaving a Place',
                      'New Place',
                      'Starting Trip',
                      'Route Deviation',
                      'Estimated arrival at a place',
                      'Movement speed',
                      'Geofences Boundary Alerts',
                      'Route Deviation Warning',
                      'Unusual Stop Detection',
                    ]),
                    _buildSection('Device & App Health Alerts', const [
                      'Low Battery Notification',
                      'Signal Loss/GPS Offline Alert',
                      'Device Tampering Alert',
                      'Connectivity Loss Alert',
                      'App Status Alert',
                    ]),
                    _buildSection('Communication Alerts', const [
                      'New Message Notification',
                      'Missed Communication Alert',
                      'Scheduled School Delivery',
                      'Manual Whistle Clock',
                    ]),
                    _buildSection('Health, Activity & Wellness', const [
                      'Daily Step Count Report',
                      'Prolonged Inactivity Alert',
                    ]),
                    _buildSection('Daily / Weekly', const [
                      'Daily Movement Summary',
                      'Weekly Safety & Activity Report',
                      'Real-time Accurate Notification',
                      'Weather Report',
                    ]),
                    _buildSection('Family & App Usage', const [
                      'New Family Member Alert',
                      'App Updates/Reminder Alert',
                    ]),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildActiveSummary() {
    final active = _allTitles.where(_valueFor).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Color(0xFF84EBB4),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$active of ${_allTitles.length} notifications active',
            style: GoogleFonts.poppins(
              fontSize: 12.0.sp,
              fontWeight: FontWeight.w400,
              height: 20 / 12,
              letterSpacing: 0.2,
              color: const Color(0xFF2D3035),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String heading, List<String> titles) {
    final rows = <Widget>[];
    for (var i = 0; i < titles.length; i++) {
      if (i > 0) rows.add(_buildDivider());
      rows.add(_buildNotificationTile(titles[i]));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 3.75, bottom: 19.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: SizedBox(
              height: 32,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  heading,
                  style: GoogleFonts.poppins(
                    fontSize: 20.0.sp,
                    fontWeight: FontWeight.w400,
                    height: 28 / 20,
                    letterSpacing: 0.2,
                    color: const Color(0xFF0F1320),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(String title) {
    final backendField = _backendFieldForTitle[title];
    final bool value = _valueFor(title);
    final ValueChanged<bool> onChanged;

    if (backendField != null) {
      onChanged = (newValue) => _toggleBackendPref(backendField, newValue);
    } else {
      final String key = _prefKey(title);
      onChanged = (newValue) {
        _sharedPrefsService.setBool(key, newValue);
        setState(() {});
      };
    }

    return InkWell(
      onTap: () => onChanged(!value),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _figmaLabel[title] ?? title,
                  style: GoogleFonts.poppins(
                    fontSize: 16.0.sp,
                    fontWeight: FontWeight.w400,
                    height: 24 / 16,
                    letterSpacing: 0.2,
                    color: const Color(0xFF4A5267),
                  ),
                ),
              ),
              FigmaToggle(
                value: value,
                onChanged: onChanged,
                activeColor: const Color(0xFF0DBF75),
                width: 50,
                height: 28,
                knob: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Divider(height: 1, thickness: 1, color: Color(0xFFDDE1EA)),
    );
  }
}
