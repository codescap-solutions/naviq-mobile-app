import 'package:child_track/core/services/api_exception.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/api_endpoints.dart';
import '../utils/app_logger.dart';
import '../utils/structured_logger.dart';
import 'shared_prefs_service.dart';
import 'package:child_track/core/services/connectivity/bloc/connectivity_bloc.dart';
import 'package:flutter/material.dart';
import 'package:child_track/main.dart' show navigatorKey;
import 'package:child_track/core/navigation/route_names.dart';

// Helper class to store pending requests during token refresh
class _PendingRequest {
  final RequestOptions requestOptions;
  final ErrorInterceptorHandler handler;

  _PendingRequest({required this.requestOptions, required this.handler});
}

class DioClient {
  late Dio _dio;
  late final SharedPrefsService _sharedPrefsService;
  final ConnectivityBloc? _connectivityBloc;
  bool _isRefreshing = false;
  final List<_PendingRequest> _pendingRequests = [];

  DioClient({
    ConnectivityBloc? connectivityBloc,
    SharedPrefsService? sharedPrefsService,
  }) : _connectivityBloc = connectivityBloc {
    _sharedPrefsService = sharedPrefsService ?? injector<SharedPrefsService>();
    _dio = Dio(BaseOptions(baseUrl: ApiEndpoints.baseUrl));
    _setupInterceptors();
  }

  int _elapsedMs(RequestOptions options) {
    final startMs = options.extra['_logStartMs'];
    if (startMs is! int) return -1;
    return DateTime.now().millisecondsSinceEpoch - startMs;
  }

  String _describeDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'TIMEOUT';
      case DioExceptionType.connectionError:
        return 'CONNECTION_ERROR';
      case DioExceptionType.cancel:
        return 'CANCELLED';
      case DioExceptionType.badResponse:
        return 'FAILED (${error.response?.statusCode})';
      case DioExceptionType.badCertificate:
        return 'BAD_CERTIFICATE';
      case DioExceptionType.unknown:
        return 'FAILED (unknown)';
    }
  }

  void _forceLogout() {
    _sharedPrefsService.logout();
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Session Expired'),
          content: const Text(
            'Your session has expired or your profile was deleted. Please log in again.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  RouteNames.onBoarding,
                  (route) => false,
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _setupInterceptors() {
    // Request Interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          AppLogger.info('🚀 Request url: ${options.method} ${options.uri}');
          options.extra['_logStartMs'] = DateTime.now().millisecondsSinceEpoch;
          try {
            if (options.data is FormData) {
              AppLogger.debug('Request Data: [FormData]');
            } else {
              AppLogger.debug('Request Data: ${jsonEncode(options.data)}');
            }
            AppLogger.debug('Request Headers: ${jsonEncode(options.headers)}');
          } catch (e) {
            AppLogger.debug('Request Data (raw): ${options.data}');
          }

          // Add auth token if available
          var token = _sharedPrefsService.getAuthToken();

          // Emergency reload if token is missing
          if (token == null || token.isEmpty) {
            await _sharedPrefsService.reloadAuthToken();
            token = _sharedPrefsService.getAuthToken();
          }

          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          handler.next(options);
        },
        onResponse: (response, handler) {
          AppLogger.info(
            '✅ Response: ${response.statusCode} ${response.requestOptions.uri}',
          );
          AppLogger.debug('Response Data: ${response.data}');
          StructuredLogger.log(
            LogTag.API,
            '${response.requestOptions.method} '
            '${response.requestOptions.path} → ${response.statusCode} '
            '(${_elapsedMs(response.requestOptions)}ms)',
            buffered: true,
          );
          handler.next(response);
        },
        onError: (error, handler) async {
          AppLogger.error('❌ Error: ${error.message}');
          AppLogger.debug('Error Response: ${error.response?.data}');
          StructuredLogger.log(
            LogTag.API,
            '${error.requestOptions.method} ${error.requestOptions.path} → '
            '${_describeDioError(error)} '
            '(${_elapsedMs(error.requestOptions)}ms)',
            buffered: true,
          );

          // Handle 401 Unauthorized - Try to refresh token
          if (error.response?.statusCode == 401) {
            final requestOptions = error.requestOptions;

            // Don't retry refresh token endpoint itself
            final path = requestOptions.path.toLowerCase();
            final uri = requestOptions.uri.toString().toLowerCase();
            if (path.contains('refresh-token') ||
                uri.contains('refresh-token')) {
              AppLogger.error(
                'Refresh token failed, user needs to login again',
              );
              _forceLogout();
              handler.next(error);
              return;
            }

            // If already refreshing, queue this request
            if (_isRefreshing) {
              AppLogger.info('Token refresh in progress, queuing request');
              _pendingRequests.add(
                _PendingRequest(
                  requestOptions: requestOptions,
                  handler: handler,
                ),
              );
              return;
            }

            _isRefreshing = true;
            AppLogger.info('Attempting to refresh token...');

            try {
              // 1. Try to reload token from storage first (isolate sync)
              // In background isolates, the token might have been refreshed by the UI
              await _sharedPrefsService.reloadAuthToken();
              final latestToken = _sharedPrefsService.getAuthToken();

              final usedToken = requestOptions.headers['Authorization']
                  ?.toString()
                  .replaceFirst('Bearer ', '');

              if (latestToken != null &&
                  latestToken.isNotEmpty &&
                  latestToken != usedToken) {
                AppLogger.info(
                  'Token was updated elsewhere, retrying with new token',
                );
                // Token was updated by another isolate/process, just retry with it
              } else {
                final currentRefreshToken = _sharedPrefsService
                    .getRefreshToken();
                if (currentRefreshToken == null) {
                  // No refresh token to call — true for every child session
                  // (child JWTs never expire by design), so a 401 landing
                  // here is never "session actually expired". Confirmed from
                  // a real device log: the first API call fired by a
                  // freshly-woken iOS background isolate (silent-push FCM
                  // handler) got 401'd, then the isolate produced no further
                  // API attempts for 2+ hours until the child manually
                  // reopened the app — a transient token-read race / brief
                  // server hiccup right at isolate wake-up, not a dead
                  // session. One retry after a short delay + reloading the
                  // persisted token covers that; the extra flag stops a
                  // second attempt from looping if it 401s again too.
                  final alreadyRetried =
                      requestOptions.extra['_retriedAfterChildAuthRace'] ==
                      true;
                  if (alreadyRetried) {
                    throw Exception('No refresh token available');
                  }
                  requestOptions.extra['_retriedAfterChildAuthRace'] = true;
                  AppLogger.info(
                    'No refresh token (child session) — retrying once after reload',
                  );
                  await Future.delayed(const Duration(seconds: 2));
                  await _sharedPrefsService.reloadAuthToken();
                  // Falls through to the shared retry below with whatever
                  // token is now in storage.
                } else {
                  // Token is still the same, try to refresh via API
                  AppLogger.info('Token is truly expired, calling refresh API');

                  // Note: ApiEndpoints.refreshToken should be called using _dio directly.
                  // The interceptor already handles recursion by checking for 'refresh-token' path.
                  final response = await _dio.post(
                    ApiEndpoints.refreshToken,
                    data: {'refresh_token': currentRefreshToken},
                  );

                  if (response.statusCode == 200 ||
                      response.statusCode == 201) {
                    // Structure based on AuthRepository usage: response.data!['token']
                    // But we use Dio directly so it's response.data['data']['token']
                    // or response.data['token'] depending on server wrapper.
                    final responseData = response.data;
                    dynamic newToken;
                    dynamic newRefreshToken;

                    if (responseData is Map) {
                      if (responseData.containsKey('data') &&
                          responseData['data'] is Map) {
                        newToken = responseData['data']['token'];
                        newRefreshToken = responseData['data']['refresh_token'];
                      } else {
                        newToken = responseData['token'];
                        newRefreshToken = responseData['refresh_token'];
                      }
                    }

                    if (newToken != null && newToken is String) {
                      await _sharedPrefsService.setAuthToken(newToken);
                      if (newRefreshToken != null &&
                          newRefreshToken is String) {
                        await _sharedPrefsService.setRefreshToken(
                          newRefreshToken,
                        );
                      }
                      AppLogger.info('Token refreshed successfully via API');
                    } else {
                      throw Exception('Token not found in refresh response');
                    }
                  } else {
                    throw Exception(
                      'Refresh API returned ${response.statusCode}',
                    );
                  }
                }
              }

              // Update token in request for retry
              final finalToken = _sharedPrefsService.getAuthToken();
              if (finalToken != null && finalToken.isNotEmpty) {
                requestOptions.headers['Authorization'] = 'Bearer $finalToken';
              }

              // Retry the original request
              try {
                final response = await _dio.fetch(requestOptions);
                handler.resolve(response);

                // Process pending requests
                await _processPendingRequests();
              } catch (e) {
                // If retry fails, pass the new error
                final dioError = e is DioException
                    ? e
                    : DioException(requestOptions: requestOptions, error: e);
                handler.reject(dioError);
                await _processPendingRequests();
              }
            } catch (e) {
              // IMPORTANT: do NOT force-logout here. A confirmed-invalid/expired
              // refresh token is already handled above (lines ~115-123) — that's
              // the only case where the server has actually told us the session
              // is dead. Everything that lands in THIS catch is either "there was
              // no refresh token to try" (true for every child session — child
              // JWTs never expire by design, so this path being reached at all
              // means the 401 came from something else, e.g. a token read race
              // in a background isolate) or a transient failure calling the
              // refresh endpoint itself (network timeout, connection error, a
              // 5xx). None of those mean the session is actually invalid, and
              // wiping child_id/parent_id for them was exactly what caused the
              // child app to silently bounce back to onboarding mid-use —
              // often from a headless background isolate with no visible
              // dialog at all. Just let this one request fail; the session is
              // preserved for the next attempt.
              AppLogger.error(
                'Token refresh failed (non-fatal, session preserved): $e',
              );
              handler.next(error);
              await _rejectPendingRequests(error);
            } finally {
              _isRefreshing = false;
            }
          } else {
            handler.next(error);
          }
        },
      ),
    );

    // Logging Interceptor — debug builds only (avoids token leaks in logcat)
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          requestHeader: true,
          responseHeader: false,
          error: true,
        ),
      );
    }
  }

  // Process pending requests after token refresh
  Future<void> _processPendingRequests() async {
    final pending = List<_PendingRequest>.from(_pendingRequests);
    _pendingRequests.clear();

    final newToken = _sharedPrefsService.getAuthToken();

    for (final pendingRequest in pending) {
      try {
        // Update token in request
        if (newToken != null && newToken.isNotEmpty) {
          pendingRequest.requestOptions.headers['Authorization'] =
              'Bearer $newToken';
        }

        // Retry the request
        final response = await _dio.fetch(pendingRequest.requestOptions);
        pendingRequest.handler.resolve(response);
      } catch (e) {
        final dioError = e is DioException
            ? e
            : DioException(
                requestOptions: pendingRequest.requestOptions,
                error: e,
              );
        pendingRequest.handler.reject(dioError);
      }
    }
  }

  // Reject all pending requests when token refresh fails
  Future<void> _rejectPendingRequests(DioException error) async {
    final pending = List<_PendingRequest>.from(_pendingRequests);
    _pendingRequests.clear();

    for (final pendingRequest in pending) {
      // Create a new error with the pending request's options
      final dioError = DioException(
        requestOptions: pendingRequest.requestOptions,
        response: error.response,
        type: error.type,
        error: error.error,
      );
      pendingRequest.handler.reject(dioError);
    }
  }

  // Check connectivity before making request
  void _checkConnectivity() {
    if (_connectivityBloc == null) return;
    final state = _connectivityBloc.state;
    if (state is ConnectivityOffline) {
      throw Exception('Internet not available. Please check your connection.');
    }
  }

  // GET Request
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    _checkConnectivity();
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // POST Request
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    _checkConnectivity();
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // PUT Request
  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    _checkConnectivity();
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // PATCH Request
  Future<Response> patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    _checkConnectivity();
    try {
      final response = await _dio.patch(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // DELETE Request
  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    _checkConnectivity();
    try {
      final response = await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // Extract error message from response data safely
  String _extractErrorMessage(dynamic data) {
    if (data == null) {
      return 'Server error occurred';
    }

    // If data is a String, return it directly
    if (data is String) {
      return data.isNotEmpty ? data : 'Server error occurred';
    }

    // If data is a Map, try to extract message
    if (data is Map) {
      // Try 'message' key first
      if (data.containsKey('message') && data['message'] != null) {
        final message = data['message'];
        if (message is String && message.isNotEmpty) {
          return message;
        }
      }

      // Try 'error' key as fallback
      if (data.containsKey('error') && data['error'] != null) {
        final error = data['error'];
        if (error is String && error.isNotEmpty) {
          return error;
        }
        // If error is a Map, try to get message from it
        if (error is Map && error.containsKey('message')) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) {
            return message;
          }
        }
      }

      // Try 'detail' key as another fallback
      if (data.containsKey('detail') && data['detail'] != null) {
        final detail = data['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
      }
    }

    return 'Server error occurred';
  }

  // Error Handler
  Exception _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return Exception(
          'Request timeout. Please check your internet connection.',
        );

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final message = _extractErrorMessage(error.response?.data);
        final body = error.response?.data;
        final errorCode = body is Map ? body['error_code']?.toString() : null;
        final errorData = body is Map && body['data'] is Map
            ? Map<String, dynamic>.from(body['data'] as Map)
            : null;
        // Same text as the plain Exception it replaces; additionally carries the
        // status / error_code so callers can tell a retryable failure from a
        // permanent refusal.
        ApiException api(String text) => ApiException(
          text,
          statusCode: statusCode,
          errorCode: errorCode,
          data: errorData,
        );

        switch (statusCode) {
          case 400:
            AppLogger.error('Bad request:', message, StackTrace.current);
            return api(
              message.isNotEmpty
                  ? message
                  : 'Bad request: Please check your request',
            );
          case 401:
            AppLogger.error('Unauthorized:', message, StackTrace.current);
            return api('Unauthorized: Please login again to continue');
          case 403:
            AppLogger.error('Access denied:', message, StackTrace.current);
            return api(
              'Access denied: You are not authorized to access this resource',
            );
          case 404:
            AppLogger.error('Not found:', message, StackTrace.current);
            // Prefer the server's own reason when it gave one ("This app is
            // not locked by your parent"); the generic line hid it.
            return api(
              message.isNotEmpty
                  ? message
                  : 'Not found: The requested resource was not found',
            );
          case 500:
            AppLogger.error(
              'Internal server error:',
              message,
              StackTrace.current,
            );
            return api('Internal server error: Please try again later');
          default:
            AppLogger.error('Server error:', message, StackTrace.current);
            return api('Server error: Please try again later');
        }

      case DioExceptionType.cancel:
        AppLogger.error(
          'Request cancelled:',
          error.message,
          StackTrace.current,
        );
        return Exception('Request was cancelled');

      case DioExceptionType.connectionError:
        AppLogger.error('Connection error:', error.message, StackTrace.current);
        return Exception(
          'Connection error. Please check your internet connection.',
        );

      case DioExceptionType.badCertificate:
        AppLogger.error(
          'Certificate error:',
          error.message,
          StackTrace.current,
        );
        return Exception('Certificate error. Please try again.');

      case DioExceptionType.unknown:
        AppLogger.error('Unknown error:', error.message, StackTrace.current);
        return Exception('An unknown error occurred. Please try again.');
    }
  }

  // Get Dio instance for custom requests
  Dio get dio => _dio;
}
