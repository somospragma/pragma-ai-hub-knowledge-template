# Extended Figma Checklist

## 9. Component Anatomy
- [ ] Widget tree reflects Figma layer hierarchy
- [ ] `(INSTANCE)` layers use corresponding DS widget
- [ ] `(TEXT)` layers use typography token
- [ ] Child order matches (Column/Row order = Figma layer order)

## 10. Component States
- [ ] Each documented state exists in Flutter enum
- [ ] State description matches implemented behavior
- [ ] "Use when" documented in dartdoc or spec
- [ ] Discrepancies registered if any

## 11. Interaction
- [ ] Interactive elements have visual feedback (splash, highlight)
- [ ] Focus applies only to interactive elements
- [ ] No hover on non-interactive areas
- [ ] Tap/click invokes callback correctly

## 12. Modularity
- [ ] Optional elements are nullable or have toggle
- [ ] Visibility combinations render without error
- [ ] Golden tests cover main combinations
- [ ] `[NEW]-separate` sub-components have completed pipeline
- [ ] `[NEW]-inline` sub-components exist as private widgets

## 13. Assets
- [ ] Icons used exist in DS catalog
- [ ] Icon set import correct
- [ ] Icon sizes match Figma
- [ ] Sub-components imported via barrel file

## 14. Final Cross-Check
- [ ] All compared tokens match or discrepancies documented
- [ ] Every Figma property has Flutter parameter
- [ ] Light and Dark verified
- [ ] Measurements verified (padding, spacing, sizes, border radius)
- [ ] Typography verified
- [ ] Anatomy verified
- [ ] Interactions verified
- [ ] Golden tests cover all variants × main combinations
- [ ] 0 unjustified discrepancies
