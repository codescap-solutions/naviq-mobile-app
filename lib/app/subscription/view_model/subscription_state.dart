import 'package:equatable/equatable.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

abstract class SubscriptionState extends Equatable {
  const SubscriptionState();

  @override
  List<Object?> get props => [];
}

class SubscriptionInitial extends SubscriptionState {
  const SubscriptionInitial();
}

class SubscriptionLoading extends SubscriptionState {
  const SubscriptionLoading();
}

/// Offerings are loaded. [selectedIndex] 0 = monthly, 1 = yearly.
class SubscriptionLoaded extends SubscriptionState {
  final Package? monthlyPackage;
  final Package? yearlyPackage;
  final int selectedIndex; // 0 = monthly, 1 = yearly

  const SubscriptionLoaded({
    required this.monthlyPackage,
    required this.yearlyPackage,
    required this.selectedIndex,
  });

  Package? get selectedPackage =>
      selectedIndex == 0 ? monthlyPackage : yearlyPackage;

  SubscriptionLoaded copyWith({int? selectedIndex}) {
    return SubscriptionLoaded(
      monthlyPackage: monthlyPackage,
      yearlyPackage: yearlyPackage,
      selectedIndex: selectedIndex ?? this.selectedIndex,
    );
  }

  @override
  List<Object?> get props => [monthlyPackage, yearlyPackage, selectedIndex];
}

/// Native payment sheet is open — lock all buttons, show spinner on CTA.
class SubscriptionPurchasing extends SubscriptionState {
  final Package purchasingPackage;
  const SubscriptionPurchasing(this.purchasingPackage);

  @override
  List<Object?> get props => [purchasingPackage];
}

class SubscriptionSuccess extends SubscriptionState {
  final CustomerInfo customerInfo;
  const SubscriptionSuccess(this.customerInfo);

  @override
  List<Object?> get props => [customerInfo];
}

class SubscriptionRestoring extends SubscriptionState {
  const SubscriptionRestoring();
}

class SubscriptionError extends SubscriptionState {
  final String message;
  final bool isCancelled; // true when user dismissed the payment sheet
  final bool
  isLoadError; // true when offerings failed to load (vs purchase error)

  const SubscriptionError(
    this.message, {
    this.isCancelled = false,
    this.isLoadError = false,
  });

  @override
  List<Object?> get props => [message, isCancelled, isLoadError];
}
