import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kLiftThemeModeStorageKey = 'lift_theme_mode_v1';

ThemeMode liftThemeModeFromString(String? raw) {
  return switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' || _ => ThemeMode.system,
  };
}

String liftThemeModeToString(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}

String liftThemeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };
}

class LiftAppearanceController extends ChangeNotifier {
  LiftAppearanceController(this._themeMode);

  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kLiftThemeModeStorageKey,
      liftThemeModeToString(mode),
    );
  }
}

class LiftAppearance extends InheritedNotifier<LiftAppearanceController> {
  const LiftAppearance({
    super.key,
    required LiftAppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static LiftAppearanceController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LiftAppearance>();
    assert(scope != null, 'LiftAppearance was not found in the widget tree.');
    return scope!.notifier!;
  }
}
