import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/app/auth/view/onboarding/mapping_progress_screen.dart';

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
    try {
      final res = await _childRepo.getScreenTimeApps();
      if (res.isSuccess && res.data != null) {
        final Map<String, List<CatalogAppItem>> grouped = {};
        res.data!.forEach((category, list) {
          if (list is List) {
            grouped[category] = list
                .map((e) => CatalogAppItem.fromJson(Map<String, dynamic>.from(e as Map)))
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
        });
      }
    } catch (e) {
      AppLogger.error("Failed to load catalog: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAddCustomDialog() {
    _customAppController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Add Custom App", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: _customAppController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Enter application name (e.g. Pinterest)",
              hintStyle: TextStyle(color: Colors.grey[500]),
              filled: true,
              fillColor: const Color(0xFF2C2C2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
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
              child: const Text("Add", style: TextStyle(color: Color(0xFF0066FF), fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  List<CatalogAppItem> _getFilteredApps(List<CatalogAppItem> apps) {
    if (_searchQuery.isEmpty) return apps;
    return apps
        .where((app) => app.name.toLowerCase().contains(_searchQuery.toLowerCase()))
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
        title: const Text(
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
              _selectedApps.isEmpty ? "Skip for now" : "Next",
              style: const TextStyle(
                color: Color(0xFF0066FF),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0066FF)),
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search bar
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                        decoration: InputDecoration(
                          prefixIcon: const Icon(CupertinoIcons.search, color: Colors.grey),
                          hintText: "Search apps...",
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // List view displaying categories and matching grid items
                    Expanded(
                      child: ListView(
                        physics: const BouncingScrollPhysics(),
                        children: [
                          // Categories
                          ..._groupedApps.entries.map((entry) {
                            final category = entry.key;
                            final filteredList = _getFilteredApps(entry.value);
                            
                            if (filteredList.isEmpty) return const SizedBox.shrink();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
                                  child: Text(
                                    category.toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 2.8,
                                  ),
                                  itemCount: filteredList.length,
                                  itemBuilder: (context, idx) {
                                    final app = filteredList[idx];
                                    final isSelected = _selectedApps.contains(app);
                                    return _buildAppCard(app, isSelected);
                                  },
                                ),
                              ],
                            );
                          }).toList(),

                          // Custom app list
                          if (_customApps.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
                              child: Text(
                                "CUSTOM APPS",
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                            const SizedBox(height: 60),
                            Text(
                              "Can't find your app?",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[500], fontSize: 14),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1C1C1E),
                                  foregroundColor: const Color(0xFF0066FF),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(color: Color(0xFF2C2C2E)),
                                  ),
                                ),
                                onPressed: _showAddCustomDialog,
                                icon: const Icon(CupertinoIcons.plus, size: 16),
                                label: const Text("Add Custom App", style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 24),
                            Center(
                              child: TextButton.icon(
                                onPressed: _showAddCustomDialog,
                                icon: const Icon(CupertinoIcons.plus, size: 16, color: Color(0xFF0066FF)),
                                label: const Text(
                                  "Add Custom App",
                                  style: TextStyle(
                                    color: Color(0xFF0066FF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 40),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0066FF).withOpacity(0.15) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF0066FF) : const Color(0xFF2C2C2E),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Mock Icon loaded locally
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(CupertinoIcons.app_fill, color: Colors.grey, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                app.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              const Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: Color(0xFF0066FF),
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
