# M6 — Insecure Authorization

This category covers access control and authorization logic implemented incorrectly on the client side.

---

## Check M6-A: Authorization controls only in the UI

**ID:** `M6-A-CLIENT-SIDE-AUTHZ`
**Objective:** Detect authorization logic implemented only on the client without backend validation.
**Scope:** `lib/**.dart`

**Method:** Semantic search
**Insecure patterns:**

```dart
// PATTERN 1: Role check only in UI
Widget build(BuildContext context) {
  // ❌ Access control is only visual
  if (currentUser.role == 'admin') {
    return AdminPanel();
  }
  return UserDashboard();
}

// PATTERN 2: Hiding buttons by role (no backend validation)
Widget deleteButton() {
  // ❌ Hiding UI is not security
  if (isAdmin) {
    return ElevatedButton(
      onPressed: () => deleteUser(userId),  // API does not validate admin role
      child: const Text('Delete'),
    );
  }
  return const SizedBox.shrink();
}

// PATTERN 3: Sensitive endpoint without authorization header
Future<void> deleteUser(String userId) async {
  // ❌ No token in sensitive operation
  await http.delete(Uri.parse('https://api.example.com/users/$userId'));
}

// PATTERN 4: Permission decision based on local (manipulable) data
bool canDeletePost(Post post) {
  // ❌ Decision based on local state
  return post.authorId == currentUser.id || currentUser.isAdmin;
}
```

**Lexical search:**
```regex
if\s*\([^)]*\.(role|isAdmin|permission)\s*==
\.role\s*=\s*['\"]admin['\"](?!.*await.*api)
canDelete|canEdit|canView.*return.*currentUser
http\.(delete|put|patch).*(?!.*headers.*Authorization)
```

**Criteria:**
- ❌ **Fail:** Authorization decisions based only on client state
- ❌ **Fail:** Sensitive API calls without authorization token
- ⚠️ **Warning:** UI hides functionality but API does not validate permissions
- ✅ **Pass:** All operations validated by the backend

**Severity:** `HIGH`
**Automation:** 🟡 Medium (50%)

**Remediation:**

```dart
// ✅ SOLUTION 1: Authorization validated by backend
class SecureApiService {
  final TokenRepository _tokenRepository;

  SecureApiService(this._tokenRepository);

  // ✅ ALWAYS include token in sensitive operations
  Future<Either<Failure, void>> deleteUser(String userId) async {
    final token = await _tokenRepository.getValidAccessToken();
    if (token == null) return const Left(Failure.unauthorized());

    try {
      final response = await _dio.delete(
        '/users/$userId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) return const Right(null);
      if (response.statusCode == 403) {
        return const Left(Failure.forbidden(message: 'Not authorized to delete users'));
      }
      return Left(Failure.server(message: 'Unexpected error'));
    } on DioException catch (e) {
      return Left(Failure.network(message: e.message ?? 'Network error'));
    }
  }

  // ✅ Fetch permissions from backend
  Future<Either<Failure, UserPermissions>> getUserPermissions() async {
    final token = await _tokenRepository.getValidAccessToken();
    if (token == null) return const Left(Failure.unauthorized());

    final response = await _dio.get(
      '/user/permissions',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return Right(UserPermissions.fromJson(response.data as Map<String, dynamic>));
  }
}
```

```dart
// ✅ SOLUTION 2: UI reacts to backend permissions
class PermissionsBloc extends Bloc<PermissionsEvent, PermissionsState> {
  final SecureApiService _apiService;

  PermissionsBloc(this._apiService) : super(const PermissionsState.initial()) {
    on<PermissionsLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    PermissionsLoadRequested event,
    Emitter<PermissionsState> emit,
  ) async {
    emit(const PermissionsState.loading());
    final result = await _apiService.getUserPermissions();
    result.fold(
      (f) => emit(PermissionsState.error(f.message)),
      (p) => emit(PermissionsState.loaded(p)),
    );
  }
}

// ✅ UI uses permissions for UX, but backend always validates
class UserListPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PermissionsBloc, PermissionsState>(
      builder: (context, state) {
        return state.maybeMap(
          loaded: (s) => s.permissions.canDeleteUsers
              ? IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => context.read<UserBloc>()
                      .add(UserDeleteRequested(userId: userId)),
                )
              : const SizedBox.shrink(),
          orElse: () => const SizedBox.shrink(),
        );
      },
    );
  }
}
```

```dart
// ✅ SOLUTION 3: Permissions model from backend
class UserPermissions {
  final bool canDeleteUsers;
  final bool canEditUsers;
  final bool canViewReports;
  final bool canManageRoles;
  final List<String> allowedResources;

  const UserPermissions({
    required this.canDeleteUsers,
    required this.canEditUsers,
    required this.canViewReports,
    required this.canManageRoles,
    required this.allowedResources,
  });

  factory UserPermissions.fromJson(Map<String, dynamic> json) =>
      UserPermissions(
        canDeleteUsers: json['can_delete_users'] as bool? ?? false,
        canEditUsers: json['can_edit_users'] as bool? ?? false,
        canViewReports: json['can_view_reports'] as bool? ?? false,
        canManageRoles: json['can_manage_roles'] as bool? ?? false,
        allowedResources: List<String>.from(json['allowed_resources'] ?? []),
      );

  bool canAccessResource(String resourceId) =>
      allowedResources.contains(resourceId);
}
```

---

## Authorization Best Practices

### ✅ Do
1. **Always validate permissions on the backend**
2. Use JWT claims for permission scopes
3. Implement RBAC (Role-Based Access Control) on the backend
4. Reload permissions periodically from the backend
5. Handle 403 Forbidden responses correctly
6. Log unauthorized access attempts for auditing

### ❌ Do not
1. Never trust client-side-only checks
2. Do not hide UI without protecting the API
3. Do not store roles/permissions in SharedPreferences
4. Do not make security decisions based on local data
5. Do not modify permissions locally without backend validation

---

## M6 Summary

| Check | Severity | Automation | Fix Effort |
|---|---|---|---|
| M6-A | HIGH | 🟡 50% | High |

**Total checks:** 1 | **Critical:** 0 | **High:** 1 | **Medium:** 0 | **Low:** 0

**Last updated:** April 2026 | **Version:** 2.0
