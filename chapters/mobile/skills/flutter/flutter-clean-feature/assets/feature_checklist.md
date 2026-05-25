# Feature Implementation Checklist
# Copy into the PR description

## Feature: [Feature Name]

### Domain Layer
- [ ] DomainModel defined with `@freezed abstract class` (no `fromJson`) in `domain_models/`
- [ ] Repository interface (`abstract interface class`) in `repositories/`
- [ ] UseCase(s) implement `UseCase<T, Params>` from core in `usecases/`
- [ ] Failure types covered in `core/error/failure.dart`

### Data Layer
- [ ] DataModel defined with `@freezed abstract class` + `fromJson` in `data_models/`
- [ ] Mapper (domain model ↔ data model) with edge cases handled
- [ ] RemoteDataSource interface + impl in `data_sources/remote/`
- [ ] LocalDataSource interface + impl in `data_sources/local/` (if applicable)
- [ ] RepositoryImpl catches `DioException` + generic exceptions → `Failure`
- [ ] Cache logic: check local → fetch remote → cache result

### Presentation Layer
- [ ] BLoC Event + State with `@freezed sealed class` in `bloc/`
- [ ] BLoC uses `@injectable`, only injects UseCases
- [ ] UIModel in `ui_models/` converts DomainModel → view-ready data
- [ ] Page in `pages/` uses `BlocProvider` with `getIt<Bloc>()`
- [ ] Organisms in `organism/` (composed widgets for the feature)
- [ ] Templates in `templates/` (mobile/web layouts if applicable)
- [ ] All states covered: initial, loading, success, error
- [ ] Side effects (navigation, snackbars) in `BlocListener`

### DI and Routes
- [ ] `dart run build_runner build` — zero errors
- [ ] Route added in GoRouter
- [ ] Auth redirect applied if the route requires authentication

### Monorepo (if applicable)
- [ ] `melos bootstrap` run after creating a new package
- [ ] Barrel export (`lib/{package}.dart`) updated with new public API
- [ ] App's `pubspec.yaml` declares the package as a path dependency
- [ ] App's `injection_container.dart` declares `ExternalModule` for the new package
- [ ] `melos exec --scope={package}` used for package-scoped commands

### Tests
- [ ] UseCase test: happy path + all failures
- [ ] Mapper test: all fields, nulls, edge cases
- [ ] RepositoryImpl test: cache hit, cache miss, failure
- [ ] BLoC test: all events → expected state sequences
- [ ] Coverage: `flutter test --coverage` ≥ 80%

### Quality
- [ ] `flutter analyze` — zero warnings
- [ ] `dart format` applied
- [ ] No `print()` without `kDebugMode` guard
- [ ] No domain model importing `package:flutter`
- [ ] No DataModel used in the Presentation layer
- [ ] `fpdart` used — no `dartz` imports
