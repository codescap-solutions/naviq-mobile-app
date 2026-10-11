import 'dart:convert';

import 'package:child_track/app/childapp/view_model/repository/logout_request_repository.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/core/di/injector.dart';
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
  static const _pageSize = 20;
  static const _hiddenKey = 'hidden_notification_ids';

  final SharedPrefsService _prefs = SharedPrefsService();
  final ScrollController _scroll = ScrollController();

  /// Newest first. Comes from the server feed; falls back to the pushes saved
  /// on this phone when the feed can't be reached.
  List<Map<String, dynamic>> _notifications = [];
  Set<String> _hidden = {};
  int _page = 1;
  bool _hasNext = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _offline = false;

  /// Child logout requests still waiting for this parent's decision. A request
  /// resolved on this screen stays here (shown with its result) until the next
  /// refresh, so the card doesn't vanish the moment a button is tapped.
  List<Map<String, dynamic>> _pending = [];
  final Set<String> _resolving = {};

  /// Decided logout requests: request id → 'approved' | 'denied'.
  final Map<String, String> _logoutStatus = {};

  @override
  void initState() {
    super.initState();
    _hidden = _readHidden();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Set<String> _readHidden() {
    try {
      final raw = _prefs.getString(_hiddenKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _hide(Iterable<String> ids) async {
    _hidden = {..._hidden, ...ids};
    await _prefs.setString(_hiddenKey, jsonEncode(_hidden.toList()));
  }

  /// Server row → the shape the list renders (same keys as the local pushes).
  Map<String, dynamic> _fromServer(Map<String, dynamic> log) => {
    'id': log['id']?.toString() ?? '',
    'title': log['title'] ?? 'NaviQ',
    'body': log['body'] ?? '',
    'timestamp': log['created_at'],
    'type': log['type'] ?? log['notification_type'],
    'request_id': log['data'] is Map ? log['data']['request_id'] : null,
  };

  /// Server rows → list items. Re-checks "visible" locally so an older server
  /// that ignores `visible=true` (and returns silent / failed rows too) still
  /// shows a clean list.
  List<Map<String, dynamic>> _parseLogs(dynamic raw) {
    const delivered = {'SENT_SUCCESS', 'SENT_PARTIAL'};
    return (raw as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where(
          (l) =>
              l['is_silent'] != true &&
              (l['title'] ?? '').toString().isNotEmpty &&
              (l['status'] == null || delivered.contains(l['status'])),
        )
        .map(_fromServer)
        .toList();
  }

  /// Fetches pages from [from] until at least [want] visible items are found
  /// (an older server that ignores `visible=true` can return whole pages of
  /// silent rows), the feed ends, or 5 pages were read. Null = request failed.
  Future<({List<Map<String, dynamic>> items, bool hasNext, int page})?> _fetch(
    int from, {
    int want = 8,
  }) async {
    final items = <Map<String, dynamic>>[];
    var page = from - 1;
    var hasNext = true;
    while (hasNext && items.length < want && page - (from - 1) < 5) {
      page += 1;
      final response = await injector<HomeRepository>().getNotificationFeed(
        page: page,
        pageSize: _pageSize,
      );
      if (!response.isSuccess || response.data == null) {
        return items.isEmpty && page == from
            ? null
            : (items: items, hasNext: false, page: page);
      }
      items.addAll(_parseLogs(response.data!['logs']));
      hasNext = response.data!['pagination']?['has_next'] == true;
    }
    return (items: items, hasNext: hasNext, page: page);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await _fetch(1);
    if (!mounted) return;
    setState(() {
      if (result != null) {
        _notifications = result.items;
        _page = result.page;
        _hasNext = result.hasNext;
        _offline = false;
      } else {
        _notifications = _prefs.getNotifications();
        _hasNext = false;
        _offline = true;
      }
      _loading = false;
    });
    _loadPending();
  }

  Future<void> _loadPending() async {
    final repo = injector<LogoutRequestRepository>();
    final results = await Future.wait([
      repo.listPending(),
      repo.listByStatus('approved'),
      repo.listByStatus('denied'),
    ]);
    if (!mounted) return;
    final pending = results[0];
    setState(() {
      if (pending.isSuccess) {
        _pending = (pending.data ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      for (final entry in {
        'approved': results[1],
        'denied': results[2],
      }.entries) {
        if (!entry.value.isSuccess) continue;
        for (final r in entry.value.data ?? const []) {
          _logoutStatus[(r as Map)['_id'].toString()] = entry.key;
        }
      }
    });
  }

  String _childName(String? childId) {
    for (final c in _prefs.getChildren()) {
      if (c.childId == childId) return c.childName;
    }
    return 'Your child';
  }

  Future<void> _resolveLogout(
    Map<String, dynamic> request,
    bool approve,
  ) async {
    final id = request['_id'].toString();
    final name = _childName(request['child_id']?.toString());
    setState(() => _resolving.add(id));
    final response = await injector<LogoutRequestRepository>()
        .resolveLogoutRequest(requestId: id, approve: approve);
    if (!mounted) return;
    setState(() => _resolving.remove(id));
    if (response.isSuccess) {
      // Keep the card, now showing the result; the next refresh moves it into
      // the list where it keeps the same Approved / Rejected tag.
      setState(() => _logoutStatus[id] = approve ? 'approved' : 'denied');
      AppSnackbar.showSuccess(
        context,
        approve ? '$name is being logged out' : 'Logout request denied',
      );
    } else {
      // Already handled elsewhere (e.g. from the push) — drop the stale card.
      AppSnackbar.showError(
        context,
        response.message.isEmpty ? 'Something went wrong' : response.message,
      );
      _loadPending();
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (!_hasNext || _loadingMore || _loading || _offline) return;
    setState(() => _loadingMore = true);
    final result = await _fetch(_page + 1);
    if (!mounted) return;
    setState(() {
      if (result != null) {
        _notifications = [..._notifications, ...result.items];
        _page = result.page;
        _hasNext = result.hasNext;
      }
      _loadingMore = false;
    });
  }

  /// Hidden-by-me rows, minus logout requests already shown as an actionable
  /// card above the list.
  List<Map<String, dynamic>> get _visible {
    final pendingIds = _pending.map((r) => r['_id'].toString()).toSet();
    return _notifications
        .where(
          (n) =>
              !_hidden.contains(n['id']) &&
              !(n['type'] == 'LOGOUT_REQUEST' &&
                  pendingIds.contains(n['request_id']?.toString())),
        )
        .toList();
  }

  Future<void> _clearAllNotifications() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18.w),
        ),
        title: Text(
          'Clear Notifications',
          style: GoogleFonts.poppins(
            fontSize: 18.0.sp,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0C1D37),
          ),
        ),
        content: Text(
          'Are you sure you want to clear all notifications?',
          style: GoogleFonts.poppins(
            fontSize: 14.0.sp,
            fontWeight: FontWeight.w500,
            color: Color(0xFF475569),
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
                color: Color(0xFF64748B),
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
                color: Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _hide(_notifications.map((n) => n['id'].toString()));
      await _prefs.clearNotifications();
      setState(() {});
    }
  }

  Future<void> _deleteNotification(String id) async {
    await _hide([id]);
    setState(() {});
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
      } else if (dateTime.day == now.subtract(Duration(days: 1)).day &&
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
      case 'GEOFENCE_ENTRY':
      case 'GEOFENCE_EXIT':
      case 'GEOFENCE_ALERT':
        return Icons.location_on_rounded;
      case 'GEOFENCE_IDLE':
        return Icons.hourglass_bottom_rounded;
      case 'LOGOUT_REQUEST':
        return Icons.logout_rounded;
      case 'TIME_EXTENSION_REQUEST':
      case 'TIME_EXTENSION_RESULT':
      case 'APP_TIME_LIMIT_REACHED':
        return Icons.timer_rounded;
      case 'LOCATION_SHARE_REQUEST':
      case 'LOCATION_SHARE_ACCEPTED':
        return Icons.share_location_rounded;
      case 'CUSTOM':
        return Icons.campaign_rounded;
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
        return Color(0xFFEF4444); // Red
      case 'SAFE_PLACE_ARRIVAL':
      case 'GEOFENCE_ENTRY':
        return Color(0xFF10B981); // Green
      case 'SAFE_PLACE_DEPARTURE':
      case 'GEOFENCE_EXIT':
      case 'GEOFENCE_ALERT':
        return Color(0xFF0066FF); // Blue
      case 'LOGOUT_REQUEST':
      case 'TIME_EXTENSION_REQUEST':
        return Color(0xFFF97316); // Orange: needs the parent's decision
      case 'CUSTOM':
        return Color(0xFF8B5CF6); // Purple: announcements
      case 'TRIP_STARTED':
      case 'TRIP_ENDED':
        return Color(0xFF6366F1); // Indigo
      case 'LOW_BATTERY':
        return Color(0xFFF59E0B); // Amber
      case 'DEVICE_OFFLINE':
        return Color(0xFF64748B); // Slate/Grey
      case 'CHAT_MESSAGE':
        return Color(0xFFF97316); // Orange
      default:
        return Color(0xFF0066FF); // Default Blue
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF7F8FA),
      appBar: figmaAppBar(
        context,
        title: 'Notifications',
        trailing: _visible.isEmpty
            ? null
            : FigmaCircleButton(
                onTap: _clearAllNotifications,
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444),
                  size: 24.w,
                ),
              ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _visible.isEmpty && _pending.isEmpty
                  ? ListView(
                      physics: AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.25,
                        ),
                        _buildEmptyState(),
                      ],
                    )
                  : _buildList(),
            ),
    );
  }

  Widget _buildList() {
    final items = _visible;
    return ListView.builder(
      controller: _scroll,
      physics: AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 24.w, 16.w, 16.w),
      itemCount: _pending.length + items.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < _pending.length) {
          return _buildLogoutRequestCard(_pending[index]);
        }
        index -= _pending.length;
        if (index >= items.length) {
          return Padding(
            padding: EdgeInsets.all(16.w),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final notification = items[index];
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
            padding: EdgeInsets.only(right: 20.w),
            margin: EdgeInsets.only(bottom: 12.w),
            decoration: BoxDecoration(
              color: Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(14.w),
            ),
            child: Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
          ),
          onDismissed: (_) => _deleteNotification(id),
          child: Container(
            margin: EdgeInsets.only(bottom: 12.w),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14.w),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4.w,
                  offset: Offset(0, 2.w),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 2.w),
                  child: Container(
                    height: 36.w,
                    width: 36.w,
                    decoration: BoxDecoration(
                      color: _getColorForType(type),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getIconForType(type),
                      color: Colors.white,
                      size: 18.w,
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: FigmaText.poppins(
                          16,
                          color: Color(0xFF0F1320),
                          lineHeight: 24,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 2.w),
                        child: Text(
                          body,
                          style: FigmaText.poppins(
                            12,
                            color: Color(0xFF6B7280),
                            lineHeight: 20,
                          ),
                        ),
                      ),
                      if (type == 'LOGOUT_REQUEST' &&
                          _logoutStatus[notification['request_id']
                                  ?.toString()] !=
                              null)
                        Padding(
                          padding: EdgeInsets.only(top: 8.w),
                          child: _statusChip(
                            _logoutStatus[notification['request_id']
                                ?.toString()]!,
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.only(top: 8.w),
                        child: Text(
                          _formatTimestamp(timestamp),
                          style: FigmaText.poppins(
                            11,
                            color: Color(0xFF9BA4B5),
                            lineHeight: 16,
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
                    padding: EdgeInsets.only(left: 4.w, top: 2.w),
                    child: Text(
                      '×',
                      style: GoogleFonts.poppins(
                        fontSize: 16.0.sp,
                        fontWeight: FontWeight.w500,
                        height: 1.0,
                        color: Color(0xFFD1D5DC),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// "<child> wants to log out" with the parent's decision buttons.
  Widget _buildLogoutRequestCard(Map<String, dynamic> request) {
    final id = request['_id'].toString();
    final name = _childName(request['child_id']?.toString());
    final busy = _resolving.contains(id);
    Widget button(String label, bool approve) => Expanded(
      child: Padding(
        padding: EdgeInsets.zero,
        child: approve
            ? ElevatedButton(
                onPressed: busy ? null : () => _resolveLogout(request, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF0069F9),
                  minimumSize: Size.fromHeight(40.w),
                  padding: EdgeInsets.symmetric(vertical: 10.w),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.w),
                  ),
                ),
                child: busy
                    ? SizedBox(
                        width: 18.w,
                        height: 18.w,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(label, style: _buttonStyle(Colors.white)),
              )
            : OutlinedButton(
                onPressed: busy ? null : () => _resolveLogout(request, false),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(40.w),
                  padding: EdgeInsets.symmetric(vertical: 10.w),
                  side: BorderSide(color: Color(0xFFEF4444)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.w),
                  ),
                ),
                child: Text(label, style: _buttonStyle(Color(0xFFEF4444))),
              ),
      ),
    );

    return Container(
      margin: EdgeInsets.only(bottom: 12.w),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.w),
        border: Border.all(color: Color(0xFFFED7AA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4.w,
            offset: Offset(0, 2.w),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 36.w,
                width: 36.w,
                decoration: BoxDecoration(
                  color: _getColorForType('LOGOUT_REQUEST'),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getIconForType('LOGOUT_REQUEST'),
                  color: Colors.white,
                  size: 18.w,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name wants to log out',
                      style: FigmaText.poppins(
                        16,
                        color: Color(0xFF0F1320),
                        lineHeight: 24,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 2.w),
                      child: Text(
                        'Allow $name to log out of the app?',
                        style: FigmaText.poppins(
                          12,
                          color: Color(0xFF6B7280),
                          lineHeight: 20,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 6.w),
                      child: Text(
                        _formatTimestamp(request['created_at']?.toString()),
                        style: FigmaText.poppins(
                          11,
                          color: Color(0xFF9BA4B5),
                          lineHeight: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.w),
          if (_logoutStatus[id] != null)
            Align(
              alignment: Alignment.centerLeft,
              child: _statusChip(_logoutStatus[id]!),
            )
          else
            Row(
              children: [
                button('Reject', false),
                SizedBox(width: 12.w),
                button('Accept', true),
              ],
            ),
        ],
      ),
    );
  }

  /// "Approved" / "Rejected" tag for a decided logout request.
  Widget _statusChip(String status) {
    final approved = status == 'approved';
    final color = approved ? Color(0xFF10B981) : Color(0xFFEF4444);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.w),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            approved ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 14.w,
            color: color,
          ),
          SizedBox(width: 4.w),
          Text(
            approved ? 'Approved' : 'Rejected',
            style: GoogleFonts.poppins(
              fontSize: 11.0.sp,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _buttonStyle(Color color) => GoogleFonts.poppins(
    fontSize: 13.0.sp,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: color,
  );

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 100.w,
              width: 100.w,
              decoration: BoxDecoration(
                color: Color(0xFFEFF6FF), // soft blue background
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: Color(0xFF0066FF),
                  size: 48.w,
                ),
              ),
            ),
            SizedBox(height: 24.w),
            Text(
              'No Notifications Yet',
              style: GoogleFonts.poppins(
                fontSize: 18.0.sp,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0C1D37),
              ),
            ),
            SizedBox(height: 10.w),
            Text(
              'All caught up! You will see real-time updates and alerts about your child here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14.0.sp,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
