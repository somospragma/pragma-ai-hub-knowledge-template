# Lint Self-Review Checklist

Before delivering code, verify:

- [ ] **DS-001**: ZERO numeric values for colors/spacing/radius?
- [ ] **DS-002**: ZERO `Colors.*` anywhere?
- [ ] **DS-003**: ZERO `TextStyle(fontSize: ...)` manual?
- [ ] **DS-004**: No inline/block/doc comments unless fundamental and justified?
- [ ] **DS-005**: Only 1 public widget in the file?
- [ ] **DS-006**: Constructor is `const`?
- [ ] **DS-007**: Only authorized imports (Flutter + DS package)?
- [ ] **DS-008**: All parameters are named?
- [ ] **DS-009**: Package imports (no `../`)?
- [ ] **DS-010**: No commented or dead code?
- [ ] **DS-014**: No `!` except where strictly necessary?
- [ ] **DS-015**: Optional callbacks are nullable?
