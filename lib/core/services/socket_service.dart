import 'dart:async';

import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  static final SocketService _instance = SocketService._internal();

  factory SocketService() {
    return _instance;
  }

  SocketService._internal();

  io.Socket? _socket;
  final String _serverUrl = "https://naviq-server.codescap.com:443";
  final SharedPrefsService _sharedPrefsService = SharedPrefsService();
  String? _pendingChildIdForRoom;
  // The room we want to be in. Socket.IO rooms are per-connection on the
  // server, so every (re)connect — network blip, server redeploy, OS
  // resuming a suspended socket — lands in NO room. Without remembering this
  // and rejoining in onConnect, the parent only ever got live updates until
  // the first reconnect, then silently nothing until a manual refresh.
  String? _activeRoomChildId;

  // Streams
  final _locationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _tripController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get locationStream => _locationController.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<Map<String, dynamic>> get tripStream => _tripController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void initSocket() {
    if (_socket != null) {
      AppLogger.info('[SocketService] Disposing existing socket...');
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    // Get auth token for connection
    final token = _sharedPrefsService.getAuthToken();

    final url = _serverUrl;

    final extraHeaders = <String, String>{};
    if (token != null && token.isNotEmpty) {
      extraHeaders['Authorization'] = 'Bearer $token';
    }

    _socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .setReconnectionAttempts(double.infinity)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(30000)
          .enableForceNew()
          .setExtraHeaders(extraHeaders)
          .build(),
    );

    _setupListeners();
    connect();
  }

  void connect() {
    if (_socket == null) return;
    _socket!.connect();
  }

  void disconnect() {
    if (_socket == null) return;
    _socket!.disconnect();
  }

  void _setupListeners() {
    if (_socket == null) return;

    _socket!.onConnect((_) {
      AppLogger.info('[SocketService] Connected: ${_socket!.id}');
      _connectionStatusController.add(true);

      final roomToJoin = _pendingChildIdForRoom ?? _activeRoomChildId;
      _pendingChildIdForRoom = null;
      if (roomToJoin != null) {
        joinRoom(roomToJoin);
      }
    });

    _socket!.onDisconnect((reason) {
      AppLogger.error('[SocketService] Disconnected: $reason');
      _connectionStatusController.add(false);
    });

    _socket!.onConnectError((data) {
      AppLogger.error('[SocketService] Connection Error: $data');
      _connectionStatusController.add(false);
    });

    // --- Location Events ---
    void handleLocationUpdate(dynamic data) {
      if (data != null && data is Map) {
        try {
          final mapData = Map<String, dynamic>.from(data);
          AppLogger.info(
            '[SocketService] Location received: ${mapData['lat']}, ${mapData['lng']}',
          ); // Reduced verbosity
          _locationController.add(mapData);
        } catch (e) {
          AppLogger.error('[SocketService] Error parsing location data: $e');
        }
      }
    }

    _socket!.on('location_update', handleLocationUpdate);
    _socket!.on(
      'Websocket send_location',
      handleLocationUpdate,
    ); // Legacy/Alternative event

    // --- Status Events ---
    void handleStatusUpdate(dynamic data) {
      if (data != null && data is Map) {
        _statusController.add(Map<String, dynamic>.from(data));
      }
    }

    _socket!.on('status_update', handleStatusUpdate);
    _socket!.on('websocket send_status', handleStatusUpdate);

    // --- Trip Events ---
    void handleTripEvent(dynamic data) {
      if (data != null && data is Map) {
        _tripController.add(Map<String, dynamic>.from(data));
      }
    }

    _socket!.on('trip_update', handleTripEvent);
    _socket!.on('trip_started', handleTripEvent);
    _socket!.on('trip_ended', handleTripEvent);

    // --- Room Events ---
    _socket!.on(
      'joined_room',
      (data) => AppLogger.info('[SocketService] Joined room data: $data'),
    );
    _socket!.on(
      'room_join_error',
      (data) => AppLogger.error('[SocketService] Room join error: $data'),
    );
  }

  void joinRoom(String childId) {
    _activeRoomChildId = childId;
    if (_socket == null || !_socket!.connected) {
      _pendingChildIdForRoom = childId;
      return;
    }

    final joinData = {'childId': childId};
    AppLogger.info('[SocketService] Joining room: $joinData');
    _socket!.emit('join_child_room', joinData);
  }

  void leaveRoom(String childId) {
    if (_activeRoomChildId == childId) _activeRoomChildId = null;
    if (_pendingChildIdForRoom == childId) _pendingChildIdForRoom = null;
    if (_socket == null || !_socket!.connected) return;
    _socket!.emit('leave_child_room', {'childId': childId});
  }

  // Emitters
  void sendLocation(Map<String, dynamic> locationData) {
    if (_socket == null || !_socket!.connected) return;
    AppLogger.info('[SocketService] Sending location: $locationData');
    _socket!.emit('Websocket send_location', locationData);
  }

  void sendStatus(Map<String, dynamic> statusData) {
    if (_socket == null || !_socket!.connected) return;
    AppLogger.info('[SocketService] Sending status: $statusData');
    _socket!.emit('websocket send_status', statusData);
  }

  void emitTripEvent(String eventName, Map<String, dynamic> tripData) {
    if (_socket == null || !_socket!.connected) return;
    AppLogger.info('[SocketService] Emitting trip event: $eventName');
    _socket!.emit(eventName, tripData);
  }
}
