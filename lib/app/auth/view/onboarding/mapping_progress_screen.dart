import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/cupertino.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/app/childapp/view_model/repository/device_info_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/app/auth/view/onboarding/app_catalog_screen.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class MappingProgressScreen extends StatefulWidget {
  final List<CatalogAppItem> selectedApps;

  const MappingProgressScreen({
    Key? key,
    required this.selectedApps,
  }) : super(key: key);

  @override
  State<MappingProgressScreen> createState() => _MappingProgressScreenState();
}

class _MappingProgressScreenState extends State<MappingProgressScreen> {
  final ChildRepo _childRepo = injector<ChildRepo>();
  final ChildInfoService _childInfoService = injector<ChildInfoService>();

  final Map<CatalogAppItem, String> _mappedTokens = {};
  bool _isInitializing = true;
  bool _isSubmitting = false;
  String _deviceId = "";
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _loadSessionState();
  }

  Future<void> _loadSessionState() async {
    try {
      final id = await _childInfoService.getDeviceId();
      setState(() {
        _deviceId = id;
      });

      // Try resuming session from backend
      final res = await _childRepo.getAppMappings(id);
      if (res.isSuccess && res.data != null) {
        final List<dynamic> existingList = res.data!;
        for (final item in existingList) {
          final token = item['tokenHash'] as String?;
          final appId = item['appId'] as int?;
          final customName = item['customName'] as String?;

          if (token != null) {
            // Find match in selected list
            final match = widget.selectedApps.firstWhere(
              (app) => app.isCustom
                  ? (app.name == customName)
                  : (app.appId == appId),
              orElse: () => CatalogAppItem(name: '', icon: '', category: ''),
            );

            if (match.name.isNotEmpty) {
              _mappedTokens[match] = token;
            }
          }
        }
      }
    } catch (e) {
      AppLogger.error("Failed to restore resume mapping state: $e");
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<void> _mapApp(CatalogAppItem app) async {
    setState(() {
      _validationError = null;
    });

    try {
      // Clear native mappings first to capture this single step fresh
      await _childInfoService.clearAllMappings();

      final selection = await _childInfoService.openFamilyActivityPicker();

      if (selection.isEmpty) {
        setState(() {
          _validationError = "No application selected. Please try again.";
        });
        return;
      }

      if (selection.length > 1) {
        setState(() {
          _validationError =
              "You selected ${selection.length} apps. To correctly identify ${app.name}, please select only ${app.name} in Apple's list.";
        });
        return;
      }

      // Valid selection
      final item = selection.first;
      final token = item['id'] as String;

      setState(() {
        _mappedTokens[app] = token;
      });

      AppLogger.info("Mapped ${app.name} to token: $token");
    } catch (e) {
      AppLogger.error("Error during single mapping: $e");
      setState(() {
        _validationError = "Mapping failed: $e";
      });
    }
  }

  Future<void> _finishMapping() async {
    setState(() {
      _isSubmitting = true;
      _validationError = null;
    });

    try {
      final List<Map<String, dynamic>> mappingPayload = [];
      _mappedTokens.forEach((app, token) {
        mappingPayload.add({
          "appId": app.appId,
          "customName": app.name,
          "icon": app.icon,
          "token": token,
        });
      });

      final body = {
        "deviceId": _deviceId,
        "mappings": mappingPayload,
      };

      final res = await _childRepo.postAppMappings(body);

      if (res.isSuccess) {
        AppLogger.info("Mappings synced to backend successfully.");
        try {
          final prefs = await SharedPreferences.getInstance();
          final mappedAppsJson = mappingPayload.map((e) => jsonEncode(e)).toList();
          await prefs.setStringList('local_mapped_apps', mappedAppsJson);
        } catch (e) {
          AppLogger.error("Failed to save mappings locally: $e");
        }
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        setState(() {
          _validationError = res.message ?? "Failed to save mappings to backend.";
          _isSubmitting = false;
        });
      }
    } catch (e) {
      AppLogger.error("Error submitting mappings: $e");
      setState(() {
        _validationError = "Submission error: $e";
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalCount = widget.selectedApps.length;
    final completedCount = _mappedTokens.length;
    final progress = totalCount > 0 ? (completedCount / totalCount) : 0.0;
    final allComplete = completedCount == totalCount;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text("Mapping Progress", style: TextStyle(color: Colors.white)),
      ),
      body: _isInitializing
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0066FF)),
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Progress Indicator Area
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "$completedCount of $totalCount Completed",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.0.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "${(progress * 100).toInt()}%",
                                style: TextStyle(
                                  color: Color(0xFF0066FF),
                                  fontSize: 15.0.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: const Color(0xFF2C2C2E),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0066FF)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Validation error banner
                    if (_validationError != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Text(
                          _validationError!,
                          style: TextStyle(color: Colors.redAccent, fontSize: 13.0.sp, height: 1.4),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // Active Wizard Steps
                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: totalCount,
                        itemBuilder: (context, index) {
                          final app = widget.selectedApps[index];
                          final isMapped = _mappedTokens.containsKey(app);
                          final isCurrent = !isMapped &&
                              (_mappedTokens.length == index ||
                                  (index == 0 && _mappedTokens.isEmpty));

                          return _buildStepItem(app, index + 1, isMapped, isCurrent);
                        },
                      ),
                    ),

                    // Action Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: allComplete ? const Color(0xFF0066FF) : const Color(0xFF2C2C2E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: (allComplete && !_isSubmitting) ? _finishMapping : null,
                      child: _isSubmitting
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : Text(
                              allComplete ? "Finish Mapping" : "Map remaining apps to complete",
                              style: TextStyle(
                                fontSize: 16.0.sp,
                                fontWeight: FontWeight.w600,
                                color: allComplete ? Colors.white : Colors.grey[550],
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStepItem(CatalogAppItem app, int stepNum, bool isMapped, bool isCurrent) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isCurrent
            ? const Color(0xFF1C1C1E)
            : const Color(0xFF1C1C1E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? const Color(0xFF0066FF).withOpacity(0.5)
              : const Color(0xFF2C2C2E),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Step circle indicator
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isMapped
                  ? Colors.green.withOpacity(0.15)
                  : (isCurrent
                      ? const Color(0xFF0066FF).withOpacity(0.15)
                      : const Color(0xFF2C2C2E)),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isMapped
                  ? const Icon(CupertinoIcons.checkmark_alt, color: Colors.green, size: 18)
                  : Text(
                      "$stepNum",
                      style: TextStyle(
                        color: isCurrent ? const Color(0xFF0066FF) : Colors.grey[500],
                        fontSize: 14.0.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),

          // App Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.name,
                  style: TextStyle(
                    color: isMapped || isCurrent ? Colors.white : Colors.grey[500],
                    fontSize: 15.0.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isMapped
                      ? "Mapped Successfully"
                      : (isCurrent ? "Ready to map" : "Pending"),
                  style: TextStyle(
                    color: isMapped
                        ? Colors.green[400]
                        : (isCurrent ? const Color(0xFF0066FF) : Colors.grey[600]),
                    fontSize: 12.0.sp,
                  ),
                ),
              ],
            ),
          ),

          // Action Button / State
          if (isCurrent)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0066FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: () => _mapApp(app),
              child: Text(
                "Map",
                style: TextStyle(fontSize: 13.0.sp, fontWeight: FontWeight.bold),
              ),
            )
          else if (!isMapped)
            Icon(CupertinoIcons.padlock_solid, color: Colors.grey[700], size: 18)
          else
            TextButton(
              onPressed: () => _mapApp(app),
              child: Text("Redo", style: TextStyle(color: Colors.grey, fontSize: 13.0.sp)),
            ),
        ],
      ),
    );
  }
}
