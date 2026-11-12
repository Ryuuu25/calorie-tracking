# Bangladeshi Calorie Tracker

Folder layout:
- lib/main.dart
- pubspec.yaml
- assets/bd_foods.json
- .github/workflows/build-apk.yml  (builds the APK online for you)

Build online: upload this whole folder to a new GitHub repository, open the Actions tab,
run "Build APK", then download calorie-tracker-apk from the finished run.

Build on your computer: flutter create bd_calorie_tracker, replace lib/main.dart and pubspec.yaml,
add assets/bd_foods.json, then run flutter pub get and flutter build apk --release.
