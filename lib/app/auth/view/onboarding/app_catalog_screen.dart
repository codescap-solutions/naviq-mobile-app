import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/app/auth/view/onboarding/mapping_progress_screen.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class CatalogAppItem {
  final int? appId;
  final String name;
  final String icon;
  final String category;
  final bool isCustom;

  CatalogAppItem({
    this.appId,
    required this.name,
    required this.icon,
    required this.category,
    this.isCustom = false,
  });

  factory CatalogAppItem.fromJson(Map<String, dynamic> json) {
    return CatalogAppItem(
      appId: json['appId'] as int?,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? 'custom_app',
      category: json['category'] as String? ?? 'General',
    );
  }
}

class AppCatalogScreen extends StatefulWidget {
  const AppCatalogScreen({Key? key}) : super(key: key);

  @override
  State<AppCatalogScreen> createState() => _AppCatalogScreenState();
}

class _AppCatalogScreenState extends State<AppCatalogScreen> {
  final ChildRepo _childRepo = injector<ChildRepo>();
  Map<String, List<CatalogAppItem>> _groupedApps = {};
  List<CatalogAppItem> _customApps = [];
  bool _isLoading = true;
  // A failed/unsuccessful catalog fetch used to leave _groupedApps empty
  // with no signal why — the screen just rendered near-blank (only the
  // "+ Add Custom App" link, since the empty-state message only shows when
  // there's an active search query). A child landing here right after
  // granting Screen Time access, on a flaky connection, had no way to tell
  // "nothing to pick from" apart from "still broken", and no way to retry
  // short of leaving and re-entering the whole flow.
  bool _hasError = false;
  String _searchQuery = "";
  final Set<CatalogAppItem> _selectedApps = {};

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customAppController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customAppController.dispose();
    super.dispose();
  }

  Future<void> _fetchCatalog() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final res = await _childRepo.getScreenTimeApps();
      if (res.isSuccess && res.data != null) {
        final Map<String, List<CatalogAppItem>> grouped = {};
        res.data!.forEach((category, list) {
          if (list is List) {
            grouped[category] = list
                .map(
                  (e) => CatalogAppItem.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList();
          }
        });
        setState(() {
          _groupedApps = grouped;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (e) {
      AppLogger.error("Failed to load catalog: $e");
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _showAddCustomDialog() {
    _customAppController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.w),
          ),
          title: Text("Add Custom App", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: _customAppController,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Enter application name (e.g. Pinterest)",
              hintStyle: TextStyle(color: Colors.grey[500]),
              filled: true,
              fillColor: Color(0xFF2C2C2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.w),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                final name = _customAppController.text.trim();
                if (name.isNotEmpty) {
                  final newApp = CatalogAppItem(
                    name: name,
                    icon: 'custom_app',
                    category: 'Custom',
                    isCustom: true,
                  );
                  setState(() {
                    _customApps.add(newApp);
                    _selectedApps.add(newApp);
                  });
                  Navigator.pop(context);
                }
              },
              child: Text(
                "Add",
                style: TextStyle(
                  color: Color(0xFF0066FF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<CatalogAppItem> _getFilteredApps(List<CatalogAppItem> apps) {
    if (_searchQuery.isEmpty) return apps;
    return apps
        .where(
          (app) => app.name.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // Compute total filtered count to show "+ Add Custom" fallback inside list
    int totalMatches = 0;
    _groupedApps.forEach((cat, list) {
      totalMatches += _getFilteredApps(list).length;
    });
    totalMatches += _getFilteredApps(_customApps).length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          "Select Apps to Monitor",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          // Previously this button only existed when _selectedApps was
          // non-empty — a child who didn't want to lock/monitor any
          // specific app yet had no way off this screen except the back
          // arrow, which unwound the whole onboarding step (see
          // permission_sequence_screen.dart's fix). Monitoring specific
          // apps is optional (configurable later from Settings), so not
          // selecting any is a valid choice, not a dead end.
          TextButton(
            onPressed: () {
              if (_selectedApps.isEmpty) {
                Navigator.pop(context, true);
                return;
              }
              Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (context) => MappingProgressScreen(
                    selectedApps: _selectedApps.toList(),
                  ),
                ),
              ).then((success) {
                if (success == true && mounted) {
                  Navigator.pop(context);
                }
              });
            },
            child: Text(
              _selectedApps.isEmpty
                  ? "Skip for now"
                  : "Next (${_selectedApps.length})",
              style: TextStyle(
                color: Color(0xFF0066FF),
                fontSize: 16.0.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0066FF)),
              ),
            )
          : _hasError
          ? Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.0.w),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      color: Colors.grey[500],
                      size: 36.w,
                    ),
                    SizedBox(height: 16.w),
                    Text(
                      "Couldn't load the app list",
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 16.0.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 6.w),
                    Text(
                      "Check your connection and try again — or skip this for now and add apps later from Settings.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13.0.sp,
                      ),
                    ),
                    SizedBox(height: 20.w),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF0066FF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.w),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 24.w,
                          vertical: 12.w,
                        ),
                      ),
                      onPressed: _fetchCatalog,
                      child: Text(
                        "Retry",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(height: 12.w),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        "Skip for now",
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // This step no longer blocks onboarding on its own (see
                    // permission_sequence_screen.dart) — the "Skip for now"
                    // button above makes that possible, but a child staring
                    // at a full app grid with no explanation could still
                    // assume they *must* pick something to continue.
                    Padding(
                      padding: EdgeInsets.only(bottom: 12.0.w),
                      child: Text(
                        "Optional — pick apps to monitor now, or skip and add them later from Settings.",
                        style: TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 12.5.sp,
                        ),
                      ),
                    ),
                    // Search bar
                    Container(
                      height: 48.w,
                      decoration: BoxDecoration(
                        color: Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(14.w),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: Colors.white),
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                        decoration: InputDecoration(
                          prefixIcon: Icon(
                            CupertinoIcons.search,
                            color: Colors.grey,
                          ),
                          hintText: "Search apps...",
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14.w),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.w),

                    // List view displaying categories and matching grid items
                    Expanded(
                      child: ListView(
                        physics: BouncingScrollPhysics(),
                        children: [
                          // Categories
                          ..._groupedApps.entries.map((entry) {
                            final category = entry.key;
                            final filteredList = _getFilteredApps(entry.value);

                            if (filteredList.isEmpty) return SizedBox.shrink();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: 12.0.w,
                                    horizontal: 4.0.w,
                                  ),
                                  child: Text(
                                    category.toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 13.0.sp,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        mainAxisSpacing: 12,
                                        crossAxisSpacing: 12,
                                        childAspectRatio: 2.8,
                                      ),
                                  itemCount: filteredList.length,
                                  itemBuilder: (context, idx) {
                                    final app = filteredList[idx];
                                    final isSelected = _selectedApps.contains(
                                      app,
                                    );
                                    return _buildAppCard(app, isSelected);
                                  },
                                ),
                              ],
                            );
                          }).toList(),

                          // Custom app list
                          if (_customApps.isNotEmpty) ...[
                            Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 12.0.w,
                                horizontal: 4.0.w,
                              ),
                              child: Text(
                                "CUSTOM APPS",
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 13.0.sp,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 2.8,
                                  ),
                              itemCount: _getFilteredApps(_customApps).length,
                              itemBuilder: (context, idx) {
                                final app = _getFilteredApps(_customApps)[idx];
                                final isSelected = _selectedApps.contains(app);
                                return _buildAppCard(app, isSelected);
                              },
                            ),
                          ],

                          // Empty / Fallback state
                          if (totalMatches == 0 && _searchQuery.isNotEmpty) ...[
                            SizedBox(height: 60.w),
                            Text(
                              "Can't find your app?",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 14.0.sp,
                              ),
                            ),
                            SizedBox(height: 12.w),
                            Center(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF1C1C1E),
                                  foregroundColor: Color(0xFF0066FF),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 20.w,
                                    vertical: 12.w,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.w),
                                    side: BorderSide(color: Color(0xFF2C2C2E)),
                                  ),
                                ),
                                onPressed: _showAddCustomDialog,
                                icon: Icon(CupertinoIcons.plus, size: 16.w),
                                label: Text(
                                  "Add Custom App",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ] else ...[
                            SizedBox(height: 24.w),
                            Center(
                              child: TextButton.icon(
                                onPressed: _showAddCustomDialog,
                                icon: Icon(
                                  CupertinoIcons.plus,
                                  size: 16.w,
                                  color: Color(0xFF0066FF),
                                ),
                                label: Text(
                                  "Add Custom App",
                                  style: TextStyle(
                                    color: Color(0xFF0066FF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          SizedBox(height: 40.w),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAppCard(CatalogAppItem app, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedApps.remove(app);
          } else {
            _selectedApps.add(app);
          }
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.w),
        decoration: BoxDecoration(
          color: isSelected
              ? Color(0xFF0066FF).withOpacity(0.15)
              : Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16.w),
          border: Border.all(
            color: isSelected ? Color(0xFF0066FF) : Color(0xFF2C2C2E),
            width: 1.5.w,
          ),
        ),
        child: Row(
          children: [
            // Mock Icon loaded locally
            Container(
              width: 32.w,
              height: 32.w,
              decoration: BoxDecoration(
                color: Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(8.w),
              ),
              child: Icon(
                CupertinoIcons.app_fill,
                color: Colors.grey,
                size: 18.w,
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                app.name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.0.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: Color(0xFF0066FF),
                size: 18.w,
              ),
          ],
        ),
      ),
    );
  }
}
