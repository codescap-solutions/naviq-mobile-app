import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/services/maps_proxy_service.dart';
import '../../model/geofence_model.dart';
import '../geofence_repository.dart';
import '../../../home/view_model/home_repo.dart';
import 'geofence_event.dart';
import 'geofence_state.dart';
import 'package:uuid/uuid.dart';

class GeofenceBloc extends Bloc<GeofenceEvent, GeofenceState> {
  final GeofenceRepository _repository;
  final HomeRepository _homeRepository;

  // Autocomplete is billed per request while typing; the debounce drops keystrokes
  // that are superseded within 300 ms, and one session token groups the whole
  // search (autocomplete requests + the final details call) into one billed session.
  final MapsProxyService _maps = MapsProxyService();
  int _searchSeq = 0;
  String? _placesSessionToken;

  GeofenceBloc({
    required GeofenceRepository repository,
    required HomeRepository homeRepository,
  }) : _repository = repository,
       _homeRepository = homeRepository,
       super(const GeofenceInitial()) {
    on<GeofenceInitializationRequested>(_onGeofenceInitializationRequested);
    on<GetGeofencesRequested>(_onGetGeofencesRequested);
    on<CreateGeofenceRequested>(_onCreateGeofenceRequested);
    on<UpdateGeofenceRequested>(_onUpdateGeofenceRequested);
    on<DeleteGeofenceRequested>(_onDeleteGeofenceRequested);
    on<ToggleGeofenceLockRequested>(_onToggleGeofenceLockRequested);
    on<SearchLocationSuggestionsRequested>(
      _onSearchLocationSuggestionsRequested,
    );
    on<GetPlaceCoordinatesRequested>(_onGetPlaceCoordinatesRequested);
    on<FetchChildLocationRequested>(_onFetchChildLocationRequested);
  }

  Future<void> _onGeofenceInitializationRequested(
    GeofenceInitializationRequested event,
    Emitter<GeofenceState> emit,
  ) async {
    emit(const GeofenceLoading());
    try {
      // Initial setup can be done here
      emit(const GeofencesLoaded(geofences: []));
    } catch (e) {
      emit(GeofenceError(message: e.toString()));
    }
  }

  Future<void> _onGetGeofencesRequested(
    GetGeofencesRequested event,
    Emitter<GeofenceState> emit,
  ) async {
    emit(const GeofenceLoading());
    try {
      final response = await _repository.getGeofences(
        event.childId,
        date: event.date,
        startDate: (event.startDate),
        endDate: (event.endDate),
      );

      if (response.isSuccess && response.data != null) {
        emit(GeofencesLoaded(geofences: response.data!));
      } else {
        emit(GeofenceError(message: response.message));
      }
    } catch (e) {
      emit(GeofenceError(message: e.toString()));
    }
  }

  Future<void> _onCreateGeofenceRequested(
    CreateGeofenceRequested event,
    Emitter<GeofenceState> emit,
  ) async {
    emit(const GeofenceLoading());
    try {
      final response = await _repository.createGeofence(event.request);

      if (response.isSuccess && response.data != null) {
        emit(GeofenceCreated(geofence: response.data!));
      } else {
        emit(GeofenceError(message: response.message));
      }
    } catch (e) {
      emit(GeofenceError(message: e.toString()));
    }
  }

  Future<void> _onUpdateGeofenceRequested(
    UpdateGeofenceRequested event,
    Emitter<GeofenceState> emit,
  ) async {
    emit(const GeofenceLoading());
    try {
      final response = await _repository.updateGeofence(
        event.id,
        event.request,
      );

      if (response.isSuccess && response.data != null) {
        emit(GeofenceUpdated(geofence: response.data!));
      } else {
        emit(GeofenceError(message: response.message));
      }
    } catch (e) {
      emit(GeofenceError(message: e.toString()));
    }
  }

  Future<void> _onDeleteGeofenceRequested(
    DeleteGeofenceRequested event,
    Emitter<GeofenceState> emit,
  ) async {
    emit(const GeofenceLoading());
    try {
      final response = await _repository.deleteGeofence(event.id);

      if (response.isSuccess) {
        emit(GeofenceDeleted(geofenceId: event.id));
      } else {
        emit(GeofenceError(message: response.message));
      }
    } catch (e) {
      emit(GeofenceError(message: e.toString()));
    }
  }

  Future<void> _onToggleGeofenceLockRequested(
    ToggleGeofenceLockRequested event,
    Emitter<GeofenceState> emit,
  ) async {
    try {
      final response = await _repository.toggleGeofenceLock(
        event.id,
        event.isLocked,
      );

      if (response.isSuccess && response.data != null) {
        emit(GeofenceLockToggled(geofence: response.data!));
      } else {
        emit(GeofenceError(message: response.message));
      }
    } catch (e) {
      emit(GeofenceError(message: e.toString()));
    }
  }

  Future<void> _onSearchLocationSuggestionsRequested(
    SearchLocationSuggestionsRequested event,
    Emitter<GeofenceState> emit,
  ) async {
    final query = event.query.trim();
    final seq = ++_searchSeq;

    // If empty → clear suggestions
    if (query.isEmpty) {
      emit(const LocationSuggestionsCleared());
      return;
    }

    await Future.delayed(const Duration(milliseconds: 300));
    if (seq != _searchSeq || emit.isDone) return;

    try {
      final predictions = await _maps.autocomplete(
        query,
        session: _placesSessionToken ??= const Uuid().v4(),
      );
      if (seq != _searchSeq || emit.isDone) return;

      if (predictions.isEmpty) {
        emit(const LocationSuggestionsCleared());
        return;
      }

      final suggestions = predictions.map((prediction) {
        return PlaceAutocompleteResult(
          placeId: prediction["place_id"] as String,
          mainText: prediction["main_text"] as String? ?? "",
          secondaryText: prediction["secondary_text"] as String? ?? "",
          description: prediction["description"] as String? ?? "",
        );
      }).toList();

      emit(LocationSuggestionsLoaded(suggestions: suggestions));
    } catch (e) {
      emit(GeofenceError(message: e.toString()));
    }
  }

  Future<void> _onGetPlaceCoordinatesRequested(
    GetPlaceCoordinatesRequested event,
    Emitter<GeofenceState> emit,
  ) async {
    try {
      final coordinates = await getPlaceLatLng(event.placeId);
      if (coordinates != null) {
        emit(PlaceCoordinatesLoaded(coordinates: coordinates));
      } else {
        emit(const GeofenceError(message: "Could not fetch place coordinates"));
      }
    } catch (e) {
      emit(GeofenceError(message: e.toString()));
    }
  }

  Future<LatLng?> getPlaceLatLng(String placeId) async {
    final location = await _maps.placeLocation(
      placeId,
      session: _placesSessionToken,
    );
    _placesSessionToken = null; // the details call ends the billed session
    return location;
  }

  Future<void> _onFetchChildLocationRequested(
    FetchChildLocationRequested event,
    Emitter<GeofenceState> emit,
  ) async {
    try {
      final response = await _homeRepository.getHomeData(
        childId: event.childId,
      );
      if (response.isSuccess && response.data != null) {
        final loc = response.data!.currentLocation;
        if (loc.lat != 0.0 || loc.lng != 0.0) {
          emit(ChildLocationLoaded(coordinates: LatLng(loc.lat, loc.lng)));
          return;
        }
      }
      emit(
        const GeofenceError(
          message: "Could not determine child's current location",
        ),
      );
    } catch (e) {
      emit(GeofenceError(message: e.toString()));
    }
  }
}
