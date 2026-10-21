import 'package:flutter/material.dart';
import 'package:child_track/app/auth/view/login_screen.dart';
import 'package:child_track/app/auth/view/onboarding/all_set_content.dart';

/// Answers picked on the two Parent Profile pages; registered with the
/// account once the Sign Up OTP is verified and the number turns out new.
class ParentSignUpProfile {
  final String parentingSituation;
  final String parentRoutine;

  const ParentSignUpProfile({
    required this.parentingSituation,
    required this.parentRoutine,
  });
}

/// Trust page between Parent Profile and Sign Up.
class ParentAllSetScreen extends StatelessWidget {
  final ParentSignUpProfile profile;

  const ParentAllSetScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFBFCFE), Color(0xFFEDF4FE)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: AllSetContent(
            onGoHome: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LoginScreen(profile: profile)),
            ),
          ),
        ),
      ),
    );
  }
}
