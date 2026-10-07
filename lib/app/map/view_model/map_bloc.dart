import 'dart:async';
import 'package:child_track/core/constants/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/utils/app_logger.dart';

part 'map_event.dart';
part 'map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  GoogleMapController? _mapController;
  final Completer<GoogleMapController> _controllerCompleter = Completer();
  final PolylinePoints _polylinePoints = PolylinePoints(
    apiKey: AppStrings.googleMapsApiKey,
  );

  MapBloc() : super(const MapInitial()) {
    on<MapCreated>(_onMapCreated);
    on<MarkerAdded>(_onMarkerAdded);
    on<MarkerTapped>(_onMarkerTapped);
    on<UpdateChildLocation>(_onUpdateChildLocation);
  }

  Future<void> _onMapCreated(MapCreated event, Emitter<MapState> emit) async {
    _mapController = event.controller;
    if (!_controllerCompleter.isCompleted) {
      _controllerCompleter.complete(event.controller);
    }
  }

  Future<void> _onMarkerAdded(MarkerAdded event, Emitter<MapState> emit) async {
    final currentState = state;
    if (currentState is! MapLoaded) return;

    final newMarker = Marker(
      consumeTapEvents: true,
      markerId: MarkerId(event.position.toString()),
      position: event.position,
      onTap: () {
        add(MarkerTapped(event.position));
      },
    );

    final updatedMarkers = [...currentState.markers, newMarker];

    emit(currentState.copyWith(markers: updatedMarkers, isLoading: true));

    // If we have more than one marker, calculate directions
    if (updatedMarkers.length > 1) {
      await _getDirections(updatedMarkers, emit);
    } else {
      emit(currentState.copyWith(markers: updatedMarkers, isLoading: false));
    }
  }

  Future<void> _onMarkerTapped(
    MarkerTapped event,
    Emitter<MapState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MapLoaded) return;

    final updatedMarkers = currentState.markers
        .where((marker) => marker.position != event.position)
        .toList();

    if (updatedMarkers.length > 1) {
      emit(
        currentState.copyWith(
          markers: updatedMarkers,
          polylines: {},
          isLoading: true,
        ),
      );
      await _getDirections(updatedMarkers, emit);
    } else {
      emit(
        currentState.copyWith(
          markers: updatedMarkers,
          polylines: {},
          isLoading: false,
        ),
      );
    }
  }

  Future<void> _getDirections(
    List<Marker> markers,
    Emitter<MapState> emit,
  ) async {
    try {
      final currentState = state;
      if (currentState is! MapLoaded) return;

      final polylineCoordinates = <LatLng>[];
      final polylineWayPoints = <PolylineWayPoint>[];

      for (var marker in markers) {
        polylineWayPoints.add(
          PolylineWayPoint(
            location:
                "${marker.position.latitude},${marker.position.longitude}",
            stopOver: true,
          ),
        );
      }

      // Get route between coordinates
      final result = await _polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(
            markers.first.position.latitude,
            markers.first.position.longitude,
          ),
          destination: PointLatLng(
            markers.last.position.latitude,
            markers.last.position.longitude,
          ),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty) {
        for (var point in result.points) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }
      } else {
        final errorMessage = result.errorMessage ?? 'Unknown error';
        AppLogger.warning('No route found: $errorMessage');

        // Check if it's an API key authorization error
        if (errorMessage.contains('not authorized') ||
            errorMessage.contains('API key') ||
            errorMessage.contains('IP')) {
          AppLogger.error(
            'API Key Authorization Error: Please check Google Cloud Console settings. '
            'Remove IP restrictions or add your IP to allowed list. '
            'For mobile apps, use Application restrictions instead of IP restrictions.',
          );
        }
      }

      final updatedPolylines = _addPolyLine(polylineCoordinates);

      emit(
        currentState.copyWith(polylines: updatedPolylines, isLoading: false),
      );
    } catch (e) {
      AppLogger.error('Error getting directions: $e');
      final currentState = state;
      if (currentState is MapLoaded) {
        emit(currentState.copyWith(isLoading: false));
      }
    }
  }

  Map<PolylineId, Polyline> _addPolyLine(List<LatLng> polylineCoordinates) {
    final id = const PolylineId("poly");
    final polyline = Polyline(
      polylineId: id,
      color: Colors.blue,
      points: polylineCoordinates,
      width: 4,
    );
    return {id: polyline};
  }

  Future<void> _onUpdateChildLocation(
    UpdateChildLocation event,
    Emitter<MapState> emit,
  ) async {
    final currentState = state;

    List<Marker> currentMarkers = [];
    if (currentState is MapLoaded) {
      currentMarkers = currentState.markers;
    }

    // Replace the existing child location marker instead of adding a new one
    const childMarkerId = MarkerId('child_location');
    final existingMarkers = currentMarkers
        .where((marker) => marker.markerId != childMarkerId)
        .toList();

    final newMarker = Marker(
      consumeTapEvents: false,
      markerId: childMarkerId,
      position: event.currentLocation,
    );

    final updatedMarkers = [...existingMarkers, newMarker];

    // Animate camera to new location
    if (_mapController != null) {
      try {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(event.currentLocation, event.zoom),
        );
      } catch (e) {
        AppLogger.debug('MapController animateCamera error: $e');
        _mapController = null;
      }
    }

    if (currentState is MapLoaded) {
      emit(
        currentState.copyWith(
          markers: updatedMarkers,
          isLoading: false,
          currentPosition: event.currentLocation,
        ),
      );
    } else {
      emit(
        MapLoaded(
          markers: updatedMarkers,
          polylines: const {},
          isLoading: false,
          currentPosition: event.currentLocation,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    _mapController?.dispose();
    return super.close();
  }

  Future<Map<PolylineId, Polyline>> getPolyLines(List<Marker> markers) async {
    // Needs at least 2 points for a route — was previously looping once per
    // marker and firing an *identical* origin=first/dest=last Directions API
    // request on every iteration (the loop variable `marker` was never
    // actually used in the request), so any caller with 3+ markers billed
    // up to 2-3x for the exact same route on a single call. One request is
    // enough.
    if (markers.length < 2) return {};

    final polylineCoordinates = <LatLng>[];
    final result = await _polylinePoints.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(
          markers.first.position.latitude,
          markers.first.position.longitude,
        ),
        destination: PointLatLng(
          markers.last.position.latitude,
          markers.last.position.longitude,
        ),
        mode: TravelMode.driving,
      ),
    );
    if (result.points.isNotEmpty) {
      for (var point in result.points) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      }
      return _addPolyLine(polylineCoordinates);
    }
    return {};
  }
}
