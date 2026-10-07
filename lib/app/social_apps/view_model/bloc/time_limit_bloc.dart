import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/app/social_apps/view_model/time_limit_repository.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'time_limit_event.dart';
import 'time_limit_state.dart';

class TimeLimitBloc extends Bloc<TimeLimitEvent, TimeLimitState> {
  final TimeLimitRepository _repository;
  final SharedPrefsService _prefs;

  TimeLimitBloc({
    required TimeLimitRepository repository,
    required SharedPrefsService sharedPrefsService,
  }) : _repository = repository,
       _prefs = sharedPrefsService,
       super(TimeLimitInitial()) {
    on<FetchTimeLimits>(_onFetchTimeLimits);
    on<SetTimeLimit>(_onSetTimeLimit);
    on<RemoveTimeLimit>(_onRemoveTimeLimit);
  }

  String get _childId =>
      _prefs.getString('selected_child_id') ??
      _prefs.getString('child_id') ??
      '';

  Future<void> _onFetchTimeLimits(
    FetchTimeLimits event,
    Emitter<TimeLimitState> emit,
  ) async {
    emit(TimeLimitLoading());
    final childId = _childId;
    if (childId.isEmpty) {
      emit(const TimeLimitLoaded());
      return;
    }

    final response = await _repository.getTimeLimits(childId: childId);
    if (response.isSuccess && response.data != null) {
      final map = {for (final item in response.data!) item.packageName: item};
      emit(TimeLimitLoaded(limitsByPackage: map));
    } else {
      emit(TimeLimitError(response.message));
    }
  }

  Future<void> _onSetTimeLimit(
    SetTimeLimit event,
    Emitter<TimeLimitState> emit,
  ) async {
    final childId = _childId;
    if (childId.isEmpty) return;

    final response = await _repository.setTimeLimit(
      childId: childId,
      packageName: event.packageName,
      appName: event.appName,
      dailyLimitMinutes: event.dailyLimitMinutes,
    );

    if (response.isSuccess) {
      add(FetchTimeLimits());
    } else {
      AppLogger.error('Failed to set time limit: ${response.message}');
      emit(TimeLimitError(response.message));
    }
  }

  Future<void> _onRemoveTimeLimit(
    RemoveTimeLimit event,
    Emitter<TimeLimitState> emit,
  ) async {
    final childId = _childId;
    if (childId.isEmpty) return;

    final response = await _repository.removeTimeLimit(
      childId: childId,
      packageName: event.packageName,
    );

    if (response.isSuccess) {
      add(FetchTimeLimits());
    } else {
      AppLogger.error('Failed to remove time limit: ${response.message}');
      emit(TimeLimitError(response.message));
    }
  }
}
