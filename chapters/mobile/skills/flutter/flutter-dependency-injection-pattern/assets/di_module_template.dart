// TEMPLATE: lib/features/{feature}/data/di/{feature}_module.dart
// Reference for generating DI code per feature.
// Placeholders: {feature} (snake_case), {Feature} (PascalCase), {Entity} (PascalCase).

import 'package:injectable/injectable.dart';

// A @module is only needed when data sources have dependencies that Injectable
// cannot auto-detect (e.g., named String parameters).
// Most features do NOT need @module — @LazySingleton(as:) on the impl class
// is sufficient for auto-wiring.

// @module
// abstract class {Feature}Module {
//   @lazySingleton
//   {Feature}RemoteDataSource get remoteDataSource =>
//       {Feature}RemoteDataSourceImpl(getIt());
// }

// ─── Standard pattern (no @module needed) ────────────────────────────────
//
// 1. Annotate RemoteDataSourceImpl:
//    @LazySingleton(as: {Feature}RemoteDataSource)
//    class {Feature}RemoteDataSourceImpl implements {Feature}RemoteDataSource {
//      const {Feature}RemoteDataSourceImpl(this._apiClient);
//      final ApiClient _apiClient;
//    }
//
// 2. Annotate LocalDataSourceImpl (if applicable):
//    @LazySingleton(as: {Feature}LocalDataSource)
//    class {Feature}LocalDataSourceImpl implements {Feature}LocalDataSource {
//      const {Feature}LocalDataSourceImpl(this._cache);
//      final CacheStore _cache;
//    }
//
// 3. Annotate RepositoryImpl:
//    @LazySingleton(as: {Feature}Repository)
//    class {Feature}RepositoryImpl implements {Feature}Repository {
//      const {Feature}RepositoryImpl(this._remote, this._local);
//      final {Feature}RemoteDataSource _remote;
//      final {Feature}LocalDataSource _local;
//    }
//
// 4. Annotate UseCase:
//    @injectable
//    class Get{Entity}UseCase {
//      const Get{Entity}UseCase(this._repository);
//      final {Feature}Repository _repository;
//    }
//
// 5. Annotate BLoC:
//    @injectable
//    class {Feature}Bloc extends Bloc<{Feature}Event, {Feature}State> {
//      {Feature}Bloc(this._get{Entity}) : super(const {Feature}State.initial()) { ... }
//      final Get{Entity}UseCase _get{Entity};
//    }
//
// ─── @ignoreParam — manual parameter at call site (injectable 3.0.0+) ────
//
// Use when a parameter must be provided at resolution time, not by the container.
//
//    @injectable
//    class {Feature}Bloc extends Bloc<{Feature}Event, {Feature}State> {
//      {Feature}Bloc(
//        this._get{Entity},
//        @ignoreParam this.initialId, // ← not injected by GetIt
//      ) : super(const {Feature}State.initial());
//
//      final Get{Entity}UseCase _get{Entity};
//      final String? initialId;
//    }
//
//    // Resolve with the manual parameter:
//    BlocProvider(
//      create: (_) => getIt<{Feature}Bloc>(param1: widget.id),
//      child: const {Feature}View(),
//    )
//
// ─── Cached Factory pattern (flow-scoped state) ───────────────────────────
//
// Use when the instance must live during a flow (checkout, onboarding)
// and be released when it ends. Requires get_it 8.0+ / injectable 3.0.0+.
//
//    @Injectable(cache: true)
//    class {Feature}FlowController {
//      {Feature}FlowController(this._repository);
//      final {Feature}Repository _repository;
//    }
//
//    // Resolve (same instance throughout the flow):
//    final controller = getIt<{Feature}FlowController>();
//
//    // Release when the flow ends:
//    getIt.releaseInstance(controller);
//
// ─── Rebuild and verify ───────────────────────────────────────────────────
//
// 6. Rebuild (choose one):
//    dart run build_runner build --delete-conflicting-outputs
//    dart run lean_builder build   # faster alternative (experimental)
//
// 7. Verify in injection.config.dart:
//    grep "{Feature}Repository\|{Feature}Bloc" lib/core/di/injection.config.dart
