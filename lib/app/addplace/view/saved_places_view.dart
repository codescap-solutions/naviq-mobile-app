import 'package:flutter/material.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/app/addplace/model/saved_place_model.dart';
import 'package:child_track/app/addplace/service/saved_places_service.dart';
import 'package:child_track/app/addplace/add_and_saveplace.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:intl/intl.dart';
import 'package:child_track/core/widgets/saved_places_shimmer.dart';

class SavedPlacesView extends StatefulWidget {
  const SavedPlacesView({super.key});

  @override
  State<SavedPlacesView> createState() => _SavedPlacesViewState();
}

class _SavedPlacesViewState extends State<SavedPlacesView> {
  final SavedPlacesService _savedPlacesService = SavedPlacesService();
  List<SavedPlace> _savedPlaces = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedPlaces();
  }

  Future<void> _loadSavedPlaces() async {
    setState(() {
      _isLoading = true;
    });

    final places = await _savedPlacesService.getSavedPlaces();

    setState(() {
      _savedPlaces = places;
      _isLoading = false;
    });
  }

  Future<void> _deletePlace(SavedPlace place) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Place'),
        content: Text('Are you sure you want to delete "${place.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _savedPlacesService.deletePlace(place.id ?? "");
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
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
          icon: Icon(Icons.arrow_back_ios_new, size: 18.w),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: AppColors.primaryColor),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddandSavePlace()),
              );
              if (result == true) {
                _loadSavedPlaces();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? SavedPlacesShimmer()
          : _savedPlaces.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 64.w,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: AppSizes.spacingM.w),
                  Text(
                    'No saved places yet',
                    style: AppTextStyles.headline6.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: AppSizes.spacingS.w),
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
                padding: EdgeInsets.all(AppSizes.paddingM.w),
                itemCount: _savedPlaces.length,
                itemBuilder: (context, index) {
                  final place = _savedPlaces[index];
                  return _buildPlaceCard(place);
                },
              ),
            ),
    );
  }

  Widget _buildPlaceCard(SavedPlace place) {
    return Card(
      margin: EdgeInsets.only(bottom: AppSizes.spacingM.w),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM.w),
      ),
      child: InkWell(
        onTap: () {
          // Navigate to map view or detail view
          Navigator.pop(context, place);
        },
        borderRadius: BorderRadius.circular(AppSizes.radiusM.w),
        child: Padding(
          padding: EdgeInsets.all(AppSizes.paddingM.w),
          child: Row(
            children: [
              Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSizes.radiusM.w),
                ),
                child: Icon(
                  Icons.place,
                  color: AppColors.primaryColor,
                  size: 24.w,
                ),
              ),
              SizedBox(width: AppSizes.spacingM.w),
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
                    SizedBox(height: AppSizes.spacingXS.w),
                    Text(
                      place.address,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: AppSizes.spacingXS.w),
                    Text(
                      'Saved on ${DateFormat('MMM dd, yyyy').format(place.savedAt ?? DateTime.now())}',
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () => _deletePlace(place),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
