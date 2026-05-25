# Permission Service — Clean Architecture Implementation

## Domain Layer

```dart
// lib/core/permissions/permission_failure.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'permission_failure.freezed.dart';

@freezed
class PermissionFailure with _$PermissionFailure {
  const factory PermissionFailure.denied({required String permission}) = PermissionDenied;
  const factory PermissionFailure.permanentlyDenied({required String permission}) = PermissionPermanentlyDenied;
  const factory PermissionFailure.restricted({required String permission}) = PermissionRestricted;
  const factory PermissionFailure.unknown({required String message}) = PermissionUnknown;
}

// lib/core/permissions/permission_service.dart
import 'package:fpdart/fpdart.dart';
import 'package:permission_handler/permission_handler.dart';

abstract interface class PermissionService {
  /// Check current status without requesting.
  Future<PermissionStatus> check(Permission permission);

  /// Request a single permission. Returns Right(true) if granted.
  Future<Either<PermissionFailure, bool>> request(Permission permission);

  /// Request multiple permissions at once.
  Future<Map<Permission, PermissionStatus>> requestMultiple(
    List<Permission> permissions,
  );

  /// Whether the rationale dialog should be shown before requesting.
  Future<bool> shouldShowRationale(Permission permission);

  /// Open the app's system settings page.
  Future<bool> openSettings();
}
```

## Data Layer — PermissionService Implementation

```dart
// lib/core/permissions/permission_service_impl.dart
import 'package:injectable/injectable.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fpdart/fpdart.dart';

@LazySingleton(as: PermissionService)
class PermissionServiceImpl implements PermissionService {

  @override
  Future<PermissionStatus> check(Permission permission) =>
      permission.status;

  @override
  Future<Either<PermissionFailure, bool>> request(
    Permission permission,
  ) async {
    try {
      final current = await permission.status;

      // Already granted — no need to request
      if (current.isGranted) return const Right(true);

      // Limited (iOS photos) — partial access, treat as granted
      if (current.isLimited) return const Right(true);

      // Permanently denied — cannot request, must go to settings
      if (current.isPermanentlyDenied) {
        return Left(PermissionFailure.permanentlyDenied(
          permission: permission.toString(),
        ));
      }

      // Restricted (iOS parental controls) — cannot request
      if (current.isRestricted) {
        return Left(PermissionFailure.restricted(
          permission: permission.toString(),
        ));
      }

      // Request the permission
      final result = await permission.request();

      if (result.isGranted || result.isLimited) return const Right(true);

      if (result.isPermanentlyDenied) {
        return Left(PermissionFailure.permanentlyDenied(
          permission: permission.toString(),
        ));
      }

      return Left(PermissionFailure.denied(
        permission: permission.toString(),
      ));
    } catch (e) {
      return Left(PermissionFailure.unknown(message: '$e'));
    }
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestMultiple(
    List<Permission> permissions,
  ) =>
      permissions.request();

  @override
  Future<bool> shouldShowRationale(Permission permission) =>
      permission.shouldShowRequestRationale;

  @override
  Future<bool> openSettings() => openAppSettings();
}
```

## Use Cases

```dart
// lib/core/permissions/usecases/request_permission_usecase.dart
import 'package:injectable/injectable.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class RequestPermissionUseCase {
  final PermissionService _service;
  RequestPermissionUseCase(this._service);

  Future<Either<PermissionFailure, bool>> call(Permission permission) =>
      _service.request(permission);
}

// lib/core/permissions/usecases/check_permission_usecase.dart
@injectable
class CheckPermissionUseCase {
  final PermissionService _service;
  CheckPermissionUseCase(this._service);

  Future<PermissionStatus> call(Permission permission) =>
      _service.check(permission);
}
```

## BLoC Integration

```dart
// lib/core/permissions/presentation/bloc/permission_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fpdart/fpdart.dart';

part 'permission_bloc.freezed.dart';
part 'permission_event.dart';
part 'permission_state.dart';

@injectable
class PermissionBloc extends Bloc<PermissionEvent, PermissionState> {
  final PermissionService _service;

  PermissionBloc(this._service) : super(const PermissionState.initial()) {
    on<RequestPermissionEvent>(_onRequest, transformer: droppable());
    on<CheckPermissionEvent>(_onCheck);
    on<OpenSettingsEvent>(_onOpenSettings);
  }

  Future<void> _onRequest(
    RequestPermissionEvent event,
    Emitter<PermissionState> emit,
  ) async {
    emit(const PermissionState.requesting());

    // Show rationale on Android before the system dialog
    if (await _service.shouldShowRationale(event.permission)) {
      emit(PermissionState.rationaleRequired(
        permission: event.permission,
        rationale: event.rationale,
      ));
      return; // UI will show rationale dialog, then re-dispatch RequestPermissionEvent
    }

    final result = await _service.request(event.permission);

    result.fold(
      (failure) => failure.when(
        denied: (_) => emit(const PermissionState.denied()),
        permanentlyDenied: (_) => emit(const PermissionState.permanentlyDenied()),
        restricted: (_) => emit(const PermissionState.restricted()),
        unknown: (msg) => emit(PermissionState.error(msg)),
      ),
      (granted) => emit(granted
          ? const PermissionState.granted()
          : const PermissionState.denied()),
    );
  }

  Future<void> _onCheck(
    CheckPermissionEvent event,
    Emitter<PermissionState> emit,
  ) async {
    final status = await _service.check(event.permission);
    emit(PermissionState.fromStatus(status));
  }

  Future<void> _onOpenSettings(
    OpenSettingsEvent event,
    Emitter<PermissionState> emit,
  ) async {
    await _service.openSettings();
  }
}

// permission_event.dart
part of 'permission_bloc.dart';

@freezed
class PermissionEvent with _$PermissionEvent {
  const factory PermissionEvent.request({
    required Permission permission,
    String? rationale,
  }) = RequestPermissionEvent;
  const factory PermissionEvent.check(Permission permission) = CheckPermissionEvent;
  const factory PermissionEvent.openSettings() = OpenSettingsEvent;
}

// permission_state.dart
part of 'permission_bloc.dart';

@freezed
class PermissionState with _$PermissionState {
  const factory PermissionState.initial() = PermissionInitial;
  const factory PermissionState.requesting() = PermissionRequesting;
  const factory PermissionState.granted() = PermissionGranted;
  const factory PermissionState.denied() = PermissionDenied;
  const factory PermissionState.permanentlyDenied() = PermissionPermanentlyDenied;
  const factory PermissionState.restricted() = PermissionRestricted;
  const factory PermissionState.rationaleRequired({
    required Permission permission,
    String? rationale,
  }) = PermissionRationaleRequired;
  const factory PermissionState.error(String message) = PermissionError;

  factory PermissionState.fromStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return const PermissionState.granted();
    if (status.isPermanentlyDenied) return const PermissionState.permanentlyDenied();
    if (status.isRestricted) return const PermissionState.restricted();
    return const PermissionState.denied();
  }
}
```

## Widget — Request at Point of Use

```dart
// lib/features/camera/presentation/widgets/camera_button.dart
class CameraButton extends StatelessWidget {
  const CameraButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<PermissionBloc>()
        ..add(const PermissionEvent.check(Permission.camera)),
      child: BlocConsumer<PermissionBloc, PermissionState>(
        listener: (context, state) {
          if (state is PermissionGranted) {
            context.push('/camera');
          } else if (state is PermissionPermanentlyDenied) {
            _showPermanentlyDeniedDialog(context);
          } else if (state is PermissionRationaleRequired) {
            _showRationaleDialog(context, state);
          }
        },
        builder: (context, state) => ElevatedButton.icon(
          onPressed: state is PermissionRequesting
              ? null
              : () => context.read<PermissionBloc>().add(
                    const PermissionEvent.request(
                      permission: Permission.camera,
                      rationale: 'Camera access is needed to take product photos.',
                    ),
                  ),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Take Photo'),
        ),
      ),
    );
  }

  void _showPermanentlyDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
          'Camera access was denied. Please enable it in Settings to take photos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<PermissionBloc>().add(const PermissionEvent.openSettings());
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showRationaleDialog(BuildContext context, PermissionRationaleRequired state) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Camera Access'),
        content: Text(state.rationale ?? 'This feature requires camera access.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Re-request after showing rationale
              context.read<PermissionBloc>().add(
                PermissionEvent.request(permission: state.permission),
              );
            },
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }
}
```

## Testing

```dart
// test/core/permissions/permission_service_impl_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fpdart/fpdart.dart';

// Mock the permission_handler platform channel
class MockPermissionHandler extends Mock implements PermissionService {}

void main() {
  late MockPermissionHandler mockService;

  setUp(() => mockService = MockPermissionHandler());

  group('PermissionService', () {
    test('returns Right(true) when permission is already granted', () async {
      when(() => mockService.request(Permission.camera))
          .thenAnswer((_) async => const Right(true));

      final result = await mockService.request(Permission.camera);
      expect(result, const Right(true));
    });

    test('returns Left(permanentlyDenied) when permanently denied', () async {
      when(() => mockService.request(Permission.camera)).thenAnswer(
        (_) async => const Left(
          PermissionFailure.permanentlyDenied(permission: 'camera'),
        ),
      );

      final result = await mockService.request(Permission.camera);
      expect(result.isLeft(), true);
      result.fold(
        (f) => expect(f, isA<PermissionPermanentlyDenied>()),
        (_) => fail('Expected failure'),
      );
    });
  });
}
```
