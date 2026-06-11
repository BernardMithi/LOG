import 'package:flutter/material.dart';
import 'package:lift/app/app_appearance.dart';
import 'package:lift/app/app_bootstrap.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/home/home_screen.dart';

/// Prevents overscroll into empty areas across the app.
class _ClampingScrollBehavior extends ScrollBehavior {
  const _ClampingScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

class LiftApp extends StatefulWidget {
  const LiftApp({super.key, required this.bootstrapData});

  final LiftAppBootstrapData bootstrapData;

  @override
  State<LiftApp> createState() => _LiftAppState();
}

class _LiftAppState extends State<LiftApp> {
  late final LiftAppearanceController _appearanceController;

  @override
  void initState() {
    super.initState();
    _appearanceController = LiftAppearanceController(
      widget.bootstrapData.themeMode,
    );
  }

  @override
  void dispose() {
    _appearanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiftAppearance(
      controller: _appearanceController,
      child: AnimatedBuilder(
        animation: _appearanceController,
        builder: (context, _) {
          return MaterialApp(
            title: 'LIFT',
            debugShowCheckedModeBanner: false,
            theme: buildLiftTheme(),
            darkTheme: buildLiftTheme(Brightness.dark),
            themeMode: _appearanceController.themeMode,
            builder:
                (context, child) => ScrollConfiguration(
                  behavior: const _ClampingScrollBehavior(),
                  child: child!,
                ),
            home: HomeScreen(
              initialWorkoutHistory: widget.bootstrapData.workoutHistory,
              signedInUserGender: widget.bootstrapData.userGenderRaw,
              preloadedFromBootstrap: true,
            ),
          );
        },
      ),
    );
  }
}
