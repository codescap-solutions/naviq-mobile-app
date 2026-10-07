import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:child_track/app/social_apps/view_model/time_limit_repository.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class AppBlockedScreen extends StatefulWidget {
  final String? appName;
  final String? packageName;

  const AppBlockedScreen({super.key, this.appName, this.packageName});

  @override
  State<AppBlockedScreen> createState() => _AppBlockedScreenState();
}

class _AppBlockedScreenState extends State<AppBlockedScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  bool _requestingExtension = false;
  bool _extensionRequestSent = false;

  Future<void> _askForMoreTime() async {
    if (widget.packageName == null ||
        _requestingExtension ||
        _extensionRequestSent) {
      return;
    }
    setState(() => _requestingExtension = true);

    final response = await injector<TimeLimitRepository>().requestExtension(
      packageName: widget.packageName!,
    );

    if (!mounted) return;
    setState(() {
      _requestingExtension = false;
      _extensionRequestSent = response.isSuccess;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response.isSuccess
              ? 'Request sent — your parent will be notified.'
              : (response.message.isNotEmpty
                    ? response.message
                    : 'Could not send request. Try again.'),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // Pulsing glow animation for the shield icon
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Slide-up + fade-in animation for content
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _slideController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.appName ?? 'This app';

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
            ),
          ),
          child: SafeArea(
            child: SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 2),

                      // ── Animated Shield Icon ──
                      _buildShieldIcon(),

                      const SizedBox(height: 40),

                      // ── Title ──
                      Text(
                        'Access Restricted',
                        style: TextStyle(
                          fontSize: 28.0.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── Subtitle ──
                      Text(
                        '$displayName has been locked by your parent.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16.0.sp,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.7),
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // ── Info Card ──
                      _buildInfoCard(),

                      if (widget.packageName != null) ...[
                        const SizedBox(height: 20),
                        _buildAskForMoreTimeButton(),
                      ],

                      const Spacer(flex: 3),

                      // ── Go Home Button ──
                      _buildGoHomeButton(),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShieldIcon() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(
                  0xFFE94560,
                ).withValues(alpha: 0.3 * _pulseAnimation.value),
                Colors.transparent,
              ],
              radius: 1.2,
            ),
          ),
          child: Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE94560), Color(0xFFC23152)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFFE94560,
                    ).withValues(alpha: 0.4 * _pulseAnimation.value),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            Icons.access_time_rounded,
            'Time limit reached',
            'Ask your parent to unlock this app.',
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.family_restroom_rounded,
            'Parental control active',
            'This restriction was set for your safety.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: 0.1),
          ),
          child: Icon(icon, size: 22, color: const Color(0xFFE94560)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.0.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.0.sp,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAskForMoreTimeButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: (_requestingExtension || _extensionRequestSent)
            ? null
            : _askForMoreTime,
        style: ElevatedButton.styleFrom(
          backgroundColor: _extensionRequestSent
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE94560),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _requestingExtension
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _extensionRequestSent
                        ? Icons.check_circle_outline_rounded
                        : Icons.timer_outlined,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _extensionRequestSent
                        ? 'Request Sent'
                        : 'Ask for More Time',
                    style: TextStyle(
                      fontSize: 16.0.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGoHomeButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () async {
          // Do NOT pop the block screen here.
          // Popping would reveal the SplashScreen underneath (the app's
          // initial home:), which re-runs _checkAuthStatus() and incorrectly
          // redirects the child to the onboarding page.
          // The block screen stays on the stack; the native goHome call
          // sends NaviQ to the background so it's invisible to the child.
          const channel = MethodChannel('com.truenyx.naviq/device_info');
          try {
            await channel.invokeMethod('goHome');
          } catch (_) {
            // Fallback: minimise the app without finishing the activity.
            SystemNavigator.pop(animated: true);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.home_rounded, size: 22),
            const SizedBox(width: 10),
            Text(
              'Go Home',
              style: TextStyle(
                fontSize: 16.0.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
