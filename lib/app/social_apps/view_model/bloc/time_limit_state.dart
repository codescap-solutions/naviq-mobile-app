import 'package:equatable/equatable.dart';
import 'package:child_track/app/social_apps/model/time_limit_model.dart';

abstract class TimeLimitState extends Equatable {
  const TimeLimitState();

  @override
  List<Object> get props => [];
}

class TimeLimitInitial extends TimeLimitState {}

class TimeLimitLoading extends TimeLimitState {}

class TimeLimitLoaded extends TimeLimitState {
  /// Keyed by package_name for quick per-app lookup in the list UI.
  final Map<String, AppTimeLimitItem> limitsByPackage;

  const TimeLimitLoaded({this.limitsByPackage = const {}});

  TimeLimitLoaded copyWith({Map<String, AppTimeLimitItem>? limitsByPackage}) {
    return TimeLimitLoaded(
      limitsByPackage: limitsByPackage ?? this.limitsByPackage,
    );
  }

  @override
  List<Object> get props => [limitsByPackage];
}

class TimeLimitError extends TimeLimitState {
  final String message;

  const TimeLimitError(this.message);

  @override
  List<Object> get props => [message];
}
