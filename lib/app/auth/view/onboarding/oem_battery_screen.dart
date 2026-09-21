import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/services/oem_battery_helper.dart';
import 'package:child_track/core/utils/responsive_font.dart';

/// Shown once after the standard battery-optimization prompt, only on
/// devices from manufacturers known to run their own background-kill
/// managers beyond stock Android (see OemBatteryHelper). Non-blocking by
/// design — this is guidance, not a permission gate; a child.currentLocation
/// can't be fully guaranteed regardless of what the user picks here, so
/// there's always a way to continue.
class OemBatteryScreen extends StatefulWidget {
  final OemInfo oem;
  // Takes this screen's own BuildContext rather than being a plain
  // VoidCallback — the caller (permission_sequence_screen.dart) used to
  // close over its OWN context/mounted instead, which silently broke: that
  // screen gets pushReplacement'd out (and disposed) the moment this one is
  // shown, so by the time the user actually taps Skip/Continue, the
  // captured `mounted` was already false and the whole navigation call
  // no-opped with no error. Passing this screen's context (always valid at
  // the moment it's actually used, since it's the currently-active route)
  // avoids that entirely.
  final void Function(BuildContext) onContinue;

  const OemBatteryScreen({super.key, required this.oem, required this.onContinue});

  @override
  State<OemBatteryScreen> createState() => _OemBatteryScreenState();
}

class _OemBatteryScreenState extends State<OemBatteryScreen> {
  final _helper = OemBatteryHelper();
  bool _showManualSteps = false;
  bool _isOpening = false;

  Future<void> _openSettings() async {
    setState(() => _isOpening = true);
    final opened = await _helper.openOemSettings(widget.oem);
    if (!mounted) return;
    setState(() {
      _isOpening = false;
      if (!opened) _showManualSteps = true;
    });
  }

  void _finish() {
    _helper.markAcknowledged();
    // Fire-and-forget — telemetry only, never blocks navigation on network.
    _helper.syncOnboardingStatusToBackend();
    widget.onContinue(context);
  }

  // Deliberately does NOT call markAcknowledged() — the home-screen nudge
  // (see HomePage's OEM battery banner) checks this same flag on every
  // cold start, so skipping here means the user gets a low-friction
  // reminder later instead of the step silently being forgotten.
  void _skip() {
    _helper.syncOnboardingStatusToBackend();
    widget.onContinue(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE6EFFF), Color(0xFFF1F7FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.battery_charging_full_rounded, color: AppColors.primaryColor, size: 32),
                ),
                const SizedBox(height: 20),
                Text(
                  'One more step for ${widget.oem.displayName}',
                  style: GoogleFonts.poppins(fontSize: 22.0.sp, fontWeight: FontWeight.w800, color: const Color(0xFF0C1D37)),
                ),
                const SizedBox(height: 10),
                Text(
                  '${widget.oem.displayName} devices have their own battery manager that can stop location '
                  'tracking in the background even after the previous permission — this whitelists NaviQ so '
                  'it keeps working when the app isn\'t open.',
                  style: GoogleFonts.poppins(fontSize: 14.0.sp, color: const Color(0xFF64748B), height: 1.5),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_showManualSteps)
                          ElevatedButton(
                            onPressed: _isOpening ? null : _openSettings,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryColor,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isOpening
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text('Open ${widget.oem.settingLabel} Settings',
                                    style: TextStyle(fontSize: 15.0.sp, fontWeight: FontWeight.w700)),
                          ),
                        if (_showManualSteps) ...[
                          Text(
                            "Couldn't open settings directly — do this manually instead:",
                            style: GoogleFonts.poppins(fontSize: 13.0.sp, fontWeight: FontWeight.w700, color: const Color(0xFF0C1D37)),
                          ),
                          const SizedBox(height: 12),
                          ...widget.oem.manualSteps.asMap().entries.map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        margin: const EdgeInsets.only(top: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryColor.withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text('${entry.key + 1}',
                                              style: TextStyle(fontSize: 11.0.sp, fontWeight: FontWeight.w700, color: AppColors.primaryColor)),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(entry.value,
                                            style: GoogleFonts.poppins(fontSize: 13.0.sp, color: const Color(0xFF334155), height: 1.4)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                        if (!_showManualSteps)
                          TextButton(
                            onPressed: () => setState(() => _showManualSteps = true),
                            child: Text(
                              "I'll do it manually instead",
                              style: GoogleFonts.poppins(fontSize: 13.0.sp, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _finish,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.primaryColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text("I've done this — Continue",
                        style: TextStyle(fontSize: 15.0.sp, fontWeight: FontWeight.w700, color: AppColors.primaryColor)),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _skip,
                    child: Text('Skip for now', style: GoogleFonts.poppins(fontSize: 13.0.sp, color: const Color(0xFF94A3B8))),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
