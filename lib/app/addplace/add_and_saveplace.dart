import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:child_track/app/addplace/model/saved_place_model.dart';
import 'package:child_track/app/addplace/service/geocoding_service.dart';
import 'package:child_track/app/addplace/service/saved_places_service.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/widgets/common_button.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:intl/intl.dart';
import 'package:child_track/core/widgets/saved_places_shimmer.dart';

class AddandSavePlace extends StatefulWidget {
  final LatLng? initialLocation;

  const AddandSavePlace({super.key, this.initialLocation});

  @override
  State<AddandSavePlace> createState() => _AddandSavePlaceState();
}

class _AddandSavePlaceState extends State<AddandSavePlace> {
  late final SavedPlacesService _savedPlacesService;
  List<SavedPlace> _savedPlaces = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _savedPlacesService = injector<SavedPlacesService>();
    _loadSavedPlaces();
  }

  Future<void> _loadSavedPlaces() async {
    setState(() {
      _isLoading = true;
    });

    final places = await _savedPlacesService.getSavedPlaces();

    if (mounted) {
      setState(() {
        _savedPlaces = places;
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddPlaceDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _AddPlaceDialog(initialLocation: widget.initialLocation),
    );

    if (result == true) {
      _loadSavedPlaces();
    }
  }

  Future<void> _deletePlace(SavedPlace place) async {
    if (place.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Place'),
        content: Text('Are you sure you want to delete "${place.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _savedPlacesService.deletePlace(place.id!);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Place deleted successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadSavedPlaces();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceColor,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text('Saved Places', style: AppTextStyles.headline5),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const SavedPlacesShimmer()
          : _savedPlaces.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 64,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppSizes.spacingM),
                  Text(
                    'No saved places yet',
                    style: AppTextStyles.headline6.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSizes.spacingS),
                  Text(
                    'Tap the + button to add a place',
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadSavedPlaces,
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                itemCount: _savedPlaces.length,
                itemBuilder: (context, index) {
                  final place = _savedPlaces[index];
                  return _buildPlaceCard(place);
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddPlaceDialog,
        backgroundColor: AppColors.primaryColor,
        icon: const Icon(Icons.add, color: AppColors.surfaceColor),
        label: Text(
          'Add Place',
          style: AppTextStyles.button.copyWith(color: AppColors.surfaceColor),
        ),
      ),
    );
  }

  IconData _getPlaceIcon(String name) {
    final lowerName = name.toLowerCase();

    if (lowerName.contains('home')) {
      return Icons.home;
    } else if (lowerName.contains('school')) {
      return Icons.school;
    } else if (lowerName.contains('tuition')) {
      return Icons.menu_book;
    } else {
      return Icons.place;
    }
  }

  Widget _buildPlaceCard(SavedPlace place) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSizes.spacingM),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingM),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              child: Icon(
                _getPlaceIcon(place.name),
                color: AppColors.primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: AppTextStyles.subtitle1.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSizes.spacingXS),
                  Text(
                    place.address,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSizes.spacingXS),
                  if (place.savedAt != null)
                    Text(
                      'Saved on ${DateFormat('MMM dd, yyyy').format(place.savedAt!)}',
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: () => _deletePlace(place),
            ),
          ],
        ),
      ),
    );
  }
}

// Dialog for adding a new place
class _AddPlaceDialog extends StatefulWidget {
  final LatLng? initialLocation;

  const _AddPlaceDialog({this.initialLocation});

  @override
  State<_AddPlaceDialog> createState() => _AddPlaceDialogState();
}

class _AddPlaceDialogState extends State<_AddPlaceDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  late final SavedPlacesService _savedPlacesService;
  final GeocodingService _geocodingService = GeocodingService();
  GoogleMapController? _mapController;
  Timer? _searchDebounce;
  int _searchSeq = 0;

  LatLng _selectedLocation = const LatLng(
    13.082680,
    80.270721,
  ); // Default to Chennai
  String _selectedPlaceType = 'home';
  double _radius = 150.0;
  String _selectedAddress = '';
  bool _isLoadingAddress = false;
  bool _isSaving = false;
  List<PlaceSearchResult> _searchResults = [];
  bool _showSearchResults = false;
  Marker? _selectedMarker;

  @override
  void initState() {
    super.initState();
    _savedPlacesService = injector<SavedPlacesService>();
    if (widget.initialLocation != null) {
      _selectedLocation = widget.initialLocation!;
    }
    _loadAddressForLocation(_selectedLocation);
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (_searchController.text.isEmpty) {
      setState(() {
        _showSearchResults = false;
        _searchResults = [];
      });
    }
  }

  Future<void> _loadAddressForLocation(LatLng location) async {
    setState(() {
      _isLoadingAddress = true;
    });

    final address = await _geocodingService.getAddressFromCoordinates(location);

    if (mounted) {
      setState(() {
        _selectedLocation = location;
        _selectedAddress = address ?? 'Address not available';
        _isLoadingAddress = false;
        _selectedMarker = Marker(
          markerId: const MarkerId('selected_location'),
          position: location,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        );
      });
    }
  }

  Future<void> _searchPlaces(String query) async {
    // Debounced: Text Search is billed per request, and this fires on every keystroke.
    _searchDebounce?.cancel();
    final seq = ++_searchSeq;
    if (query.isEmpty) {
      setState(() {
        _showSearchResults = false;
        _searchResults = [];
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await _geocodingService.searchPlaces(query);
      if (mounted && seq == _searchSeq) {
        setState(() {
          _searchResults = results;
          _showSearchResults = true;
        });
      }
    });
  }

  void _onPlaceSelected(PlaceSearchResult place) {
    _searchController.text = place.name;
    setState(() {
      _showSearchResults = false;
    });
    _loadAddressForLocation(place.location);
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(place.location, 15.0),
    );
  }

  Future<void> _onMapTap(LatLng location) async {
    await _loadAddressForLocation(location);
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        location,
        await _mapController!.getZoomLevel(),
      ),
    );
  }

  Future<void> _onCameraIdle() async {
    if (_mapController != null) {
      final position = await _mapController!.getVisibleRegion();
      final center = LatLng(
        (position.northeast.latitude + position.southwest.latitude) / 2,
        (position.northeast.longitude + position.southwest.longitude) / 2,
      );
      await _loadAddressForLocation(center);
    }
  }

  Future<void> _savePlace() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name for this place'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final place = SavedPlace(
      name: _nameController.text.trim(),
      placeType: _selectedPlaceType,
      radius: _radius.toInt(),
      latitude: _selectedLocation.latitude,
      longitude: _selectedLocation.longitude,
      address: _selectedAddress,
      children: [], // Empty = select all children by default
      savedAt: DateTime.now(),
    );

    final success = await _savedPlacesService.savePlace(place);

    if (mounted) {
      setState(() {
        _isSaving = false;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Place saved successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save place. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogHeight = screenHeight * 0.85;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSizes.paddingM),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.radiusXL),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: dialogHeight,
            decoration: BoxDecoration(
              color: AppColors.surfaceColor.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(AppSizes.radiusXL),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(AppSizes.paddingM),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.borderColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Add New Place',
                        style: AppTextStyles.headline6.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                ),
                // Search Bar
                Container(
                  padding: const EdgeInsets.all(AppSizes.paddingM),
                  color: Colors.transparent,
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search for a place...',
                          hintStyle: AppTextStyles.body2.copyWith(
                            color: AppColors.textHint,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.textSecondary,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: AppColors.textSecondary,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _showSearchResults = false;
                                      _searchResults = [];
                                    });
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppColors.containerBackground.withValues(
                            alpha: 0.5,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusM,
                            ),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.paddingM,
                            vertical: AppSizes.paddingM,
                          ),
                        ),
                        style: AppTextStyles.body2,
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            _searchPlaces(value);
                          } else {
                            setState(() {
                              _showSearchResults = false;
                              _searchResults = [];
                            });
                          }
                        },
                      ),
                      // Search Results
                      if (_showSearchResults && _searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: AppSizes.spacingS),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceColor.withValues(
                              alpha: 0.9,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusM,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(maxHeight: 150),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final place = _searchResults[index];
                              return ListTile(
                                leading: const Icon(
                                  Icons.place,
                                  color: AppColors.primaryColor,
                                ),
                                title: Text(
                                  place.name,
                                  style: AppTextStyles.subtitle2,
                                ),
                                subtitle: Text(
                                  place.address,
                                  style: AppTextStyles.caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _onPlaceSelected(place),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                // Map
                Expanded(
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _selectedLocation,
                          zoom: 15.0,
                        ),
                        markers: _selectedMarker != null
                            ? {_selectedMarker!}
                            : {},
                        onMapCreated: (controller) {
                          _mapController = controller;
                        },
                        onTap: _onMapTap,
                        onCameraIdle: _onCameraIdle,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                      ),
                      // Center marker indicator
                      Center(
                        child: Icon(
                          Icons.location_on,
                          size: 48,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
                // Location info and save section
                Container(
                  padding: const EdgeInsets.all(AppSizes.paddingM),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor.withValues(alpha: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected Location',
                        style: AppTextStyles.subtitle2.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSizes.spacingXS),
                      if (_isLoadingAddress)
                        const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: AppSizes.spacingS),
                            Text('Loading address...'),
                          ],
                        )
                      else
                        Text(
                          _selectedAddress,
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      const SizedBox(height: AppSizes.spacingM),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: 'Enter place name',
                          hintStyle: AppTextStyles.body2.copyWith(
                            color: AppColors.textHint,
                          ),
                          filled: true,
                          fillColor: AppColors.containerBackground.withValues(
                            alpha: 0.5,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusM,
                            ),
                            borderSide: BorderSide(
                              color: AppColors.borderColor.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.paddingM,
                            vertical: AppSizes.paddingM,
                          ),
                        ),
                        style: AppTextStyles.body2,
                      ),
                      const SizedBox(height: AppSizes.spacingM),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedPlaceType,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.containerBackground.withValues(
                            alpha: 0.5,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusM,
                            ),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.paddingM,
                            vertical: AppSizes.paddingM,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'home', child: Text('Home')),
                          DropdownMenuItem(
                            value: 'school',
                            child: Text('School'),
                          ),
                          DropdownMenuItem(
                            value: 'tuition',
                            child: Text('Tuition'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedPlaceType = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: AppSizes.spacingM),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Geofence Radius', style: AppTextStyles.body2),
                          Text(
                            '${_radius.toInt()} m',
                            style: AppTextStyles.subtitle2,
                          ),
                        ],
                      ),
                      Slider(
                        value: _radius,
                        min: 50,
                        max: 2000,
                        divisions: 39,
                        label: '${_radius.toInt()} m',
                        activeColor: AppColors.primaryColor,
                        onChanged: (value) {
                          setState(() {
                            _radius = value;
                          });
                        },
                      ),
                      const SizedBox(height: AppSizes.spacingM),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSizes.paddingM,
                                ),
                                side: BorderSide(
                                  color: AppColors.borderColor.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radiusM,
                                  ),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: AppTextStyles.button.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSizes.spacingM),
                          Expanded(
                            flex: 2,
                            child: CommonButton(
                              text: 'Save Place',
                              onPressed: _isSaving ? null : _savePlace,
                              isLoading: _isSaving,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
