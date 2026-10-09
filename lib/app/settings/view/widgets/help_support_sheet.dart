import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/app/chat/view/chat_screen.dart';
import 'package:child_track/app/chat/view_model/bloc/chat_bloc.dart';
import 'package:child_track/app/subscription/widgets/upgrade_restriction_dialog.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/subscription_feature_gate.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// Support channels (chat / email / call), gated by the subscription plan.
/// Opened from the Help screen's "None of the above" and the help article
/// page's "Chat With Us".
void showHelpSupportOptions(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.w)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 10.w),
            Container(
              width: 40.w,
              height: 4.w,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2.w),
              ),
            ),
            SizedBox(height: 20.w),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(0xFFFFF3E0),
                child: Icon(Icons.chat, color: Color(0xFFEF6C00)),
              ),
              title: Text('Chat with Support'),
              subtitle: Text('Real-time assistance'),
              onTap: () {
                Navigator.pop(sheetContext);
                if (!SubscriptionFeatureGate.helpChannels().chat) {
                  UpgradeRestrictionDialog.showHelpChannelBlocked(
                    context,
                    'Chat',
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(
                      value: injector<ChatBloc>(),
                      child: ChatScreen(
                        recipientId:
                            '65b2a3f7e1b2c3d4e5f67890', // Placeholder Admin ID
                        recipientName: 'NaviQ Support',
                      ),
                    ),
                  ),
                );
              },
            ),
            Divider(),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.email, color: Color(0xFF2E7D32)),
              ),
              title: Text('Email Support'),
              subtitle: Text('info.truenyx@gmail.com'),
              onTap: () {
                Navigator.pop(sheetContext);
                _launchContactUrl(
                  context,
                  Uri(scheme: 'mailto', path: 'info.truenyx@gmail.com'),
                );
              },
            ),
            Divider(),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.phone, color: Color(0xFF1565C0)),
              ),
              title: Text('Call Support'),
              subtitle: Text('+91 90371 62751'),
              onTap: () {
                Navigator.pop(sheetContext);
                if (!SubscriptionFeatureGate.helpChannels().call) {
                  UpgradeRestrictionDialog.showHelpChannelBlocked(
                    context,
                    'Call',
                  );
                  return;
                }
                _launchContactUrl(
                  context,
                  Uri(scheme: 'tel', path: '+919037162751'),
                );
              },
            ),
            SizedBox(height: 20.w),
          ],
        ),
      );
    },
  );
}

Future<void> _launchContactUrl(BuildContext context, Uri url) async {
  try {
    if (!await launchUrl(url) && context.mounted) {
      AppSnackbar.showError(context, 'Could not launch action');
    }
  } catch (e) {
    if (context.mounted) {
      AppSnackbar.showError(context, 'Error: $e');
    }
  }
}
