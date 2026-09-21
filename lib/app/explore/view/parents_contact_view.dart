import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'add_contact_view.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class ParentsContactView extends StatefulWidget {
  const ParentsContactView({super.key});

  @override
  State<ParentsContactView> createState() => _ParentsContactViewState();
}

class _ParentsContactViewState extends State<ParentsContactView> {
  final SharedPrefsService _sharedPrefsService = injector<SharedPrefsService>();
  List<Map<String, dynamic>> _contacts = [];
  bool _isPrimaryParent = true;
  // Only meaningful while _contacts is still empty: on a first-ever open
  // (nothing cached in SharedPreferences yet), _contacts stays [] for
  // however long the background fetch below takes — without this flag that
  // rendered the "No contacts found." empty state immediately, which then
  // flashed to the real list once data arrived. On a repeat open with a
  // populated cache, _loadContacts() already fills _contacts synchronously
  // before this ever matters.
  bool _isLoadingBackend = true;

  @override
  void initState() {
    super.initState();
    _isPrimaryParent = _sharedPrefsService.isPrimaryParent;
    _loadContacts();
    _fetchContactsFromBackend();
  }

  Future<void> _fetchContactsFromBackend() async {
    try {
      final response = await injector<HomeRepository>().getParentsContacts();
      if (response.isSuccess && response.data != null) {
        final List<dynamic> list = response.data!;
        if (list.isNotEmpty) {
          setState(() {
            _contacts = list.map((e) => Map<String, dynamic>.from(e)).toList();
          });
          _saveContactsToStorage();
        }
      }
    } catch (e) {
      // Fallback silently to SharedPreferences loaded contacts
    } finally {
      if (mounted) setState(() => _isLoadingBackend = false);
    }
  }

  void _loadContacts() {
    final String? contactsJson = _sharedPrefsService.getString('parents_contacts');
    final String parentName = _sharedPrefsService.getString('parent_name') ?? 'Rahul Pandey';
    final String parentPhone = _sharedPrefsService.getString('parent_phone') ?? '+91 87654 32109';

    if (contactsJson != null && contactsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(contactsJson);
        setState(() {
          _contacts = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        });

        // Ensure the default parent matches the current user info
        final defaultIndex = _contacts.indexWhere((e) => e['is_default'] == true);
        if (defaultIndex != -1) {
          setState(() {
            _contacts[defaultIndex]['name'] = parentName;
            _contacts[defaultIndex]['phone'] = parentPhone;
          });
          _saveContactsToStorage();
        }
        return;
      } catch (e) {
        // Fallback
      }
    }

    // Default contact setup
    setState(() {
      _contacts = [
        {
          'id': 'default_parent_contact',
          'name': parentName,
          'phone': parentPhone,
          'relation': 'Parent',
          'is_default': true,
        }
      ];
    });
    _saveContactsToStorage();
  }

  void _saveContactsToStorage() {
    final String encoded = jsonEncode(_contacts);
    _sharedPrefsService.setString('parents_contacts', encoded);
  }

  void _confirmDeleteContact(int index) {
    final contact = _contacts[index];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Contact',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete ${contact['name']} from parents contacts?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.bold)),
            onPressed: () async {
              final contactId = contact['id'];
              Navigator.pop(context);
              
              if (contactId != null && !contactId.toString().startsWith('contact_') && !contactId.toString().startsWith('default_')) {
                final response = await injector<HomeRepository>().deleteParentContact(contactId);
                if (!response.isSuccess) {
                  AppSnackbar.showError(context, response.message.isNotEmpty ? response.message : 'Failed to delete contact from server');
                  return;
                }
              }
              
              setState(() {
                _contacts.removeAt(index);
              });
              _saveContactsToStorage();
              AppSnackbar.showSuccess(context, 'Contact deleted successfully');
            },
          ),
        ],
      ),
    );
  }

  int min(int a, int b) => a < b ? a : b;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leadingWidth: 56,
        leading: Center(
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.chevron_left,
                  color: Colors.black,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Parents Contact',
          style: GoogleFonts.poppins(
            fontSize: 20.0.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1D37),
          ),
        ),
      ),
      body: SafeArea(
        child: _contacts.isEmpty
            ? Center(
                child: _isLoadingBackend
                    ? const CircularProgressIndicator()
                    : Text(
                        'No contacts found.',
                        style: GoogleFonts.poppins(
                          fontSize: 16.0.sp,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: _contacts.length,
                itemBuilder: (context, index) {
                  final contact = _contacts[index];
                  final isDefault = contact['is_default'] == true;
                  final String initials = (contact['name'] ?? 'P')
                      .substring(0, min(2, (contact['name'] ?? 'P').length))
                      .toUpperCase();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0C1D37).withValues(alpha: 0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Initials circle
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF0066FF),
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initials,
                            style: GoogleFonts.poppins(
                              fontSize: 16.0.sp,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0066FF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    contact['name'] ?? '',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16.0.sp,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF0C1D37),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Relation tag
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      contact['relation'] ?? 'Parent',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10.0.sp,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF059669),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    CupertinoIcons.phone,
                                    size: 14,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    contact['phone'] ?? '',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13.0.sp,
                                      color: const Color(0xFF64748B),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Edit / Delete buttons
                        if (_isPrimaryParent) ...[
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddContactView(
                                    contactIndex: index,
                                    contactsList: _contacts,
                                  ),
                                ),
                              ).then((value) {
                                if (value == true) {
                                  _loadContacts();
                                }
                              });
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEFF6FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                CupertinoIcons.pencil,
                                color: Color(0xFF0066FF),
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!isDefault)
                            GestureDetector(
                              onTap: () => _confirmDeleteContact(index),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFEF2F2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  CupertinoIcons.trash,
                                  color: Color(0xFFEF4444),
                                  size: 18,
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 36),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: _isPrimaryParent
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddContactView(
                      contactsList: _contacts,
                    ),
                  ),
                ).then((value) {
                  if (value == true) {
                    _loadContacts();
                  }
                });
              },
              backgroundColor: const Color(0xFF0066FF),
              shape: const CircleBorder(),
              elevation: 4,
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            )
          : null,
    );
  }
}
