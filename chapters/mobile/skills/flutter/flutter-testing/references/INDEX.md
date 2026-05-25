# Flutter Testing — Reference Index

Specialized documents for the `flutter-testing` skill.

## References

| File | When to use |
|---|---|
| [unit-testing.md](unit-testing.md) | Writing UseCases, Repos, DataSources, Mapper, BLoC tests |
| [widget-testing.md](widget-testing.md) | Testing UI rendering, state transitions, interactions |
| [integration-testing.md](integration-testing.md) | End-to-end user flows with `IntegrationTestWidgetsFlutterBinding` |
| [golden-testing.md](golden-testing.md) | Visual regression tests for complex custom widgets |
| [mutation-testing.md](mutation-testing.md) | Validating test effectiveness with boundary analysis |
| [mocking.md](mocking.md) | Advanced mocktail patterns: streams, void, captors, fakes |
| [native-plugins-testing.md](native-plugins-testing.md) | MethodChannel / EventChannel isolation and mocking |

## Recommended Reading Order

1. `unit-testing.md` — start here for domain and data layer contracts
2. `widget-testing.md` — UI behavior and BLoC state rendering
3. `mocking.md` — when dependencies get complex
4. `integration-testing.md` — critical user flows
5. `golden-testing.md` — visual regression for design system components
6. `native-plugins-testing.md` — when the feature uses device hardware or platform APIs
7. `mutation-testing.md` — quality audit on existing test suites
