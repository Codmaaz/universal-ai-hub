# Universal AI Hub V4.2

## Stability
- Fixed malformed `AppDatabase.close()` code that prevented Flutter builds.
- Kept chat persistence architecture intact and made send failures more visible.

## Models
- Added a user-friendly **Update models** button directly inside the Model section.
- Model updates now use a newly typed API key or an existing securely stored key when editing a provider.
- Shows loading, empty/error, model count, and selectable model chips.

## UX
- Clearer model update wording and feedback.
- The model update action is no longer tied to navigation/back UI.
- More useful unexpected send error text.

## Next recommended validation
Run `flutter pub get`, `flutter analyze`, and `flutter build apk --release` in a Flutter environment before release.
