import 'package:flutter/material.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/progress/leg_day_trends/leg_day_trends_mock_data.dart';
import 'package:lift/features/progress/leg_day_trends/leg_day_trends_models.dart';
import 'package:lift/features/progress/leg_day_trends/widgets/leg_day_trends_sections.dart';
import 'package:lift/shared/models/workout_template.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/widgets/lift_floating_island.dart';
import 'package:lift/shared/widgets/lower_body_mannequin_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _kLegDayTrendsAccent = Color(0xFF171717);
const String _kUserGenderStorageKey = 'lift_user_gender';

class LegDayTrendsPage extends StatefulWidget {
  const LegDayTrendsPage({super.key, this.data, this.template});

  final LegDayTrendsData? data;
  final WorkoutTemplate? template;

  @override
  State<LegDayTrendsPage> createState() => _LegDayTrendsPageState();
}

class _LegDayTrendsPageState extends State<LegDayTrendsPage> {
  final ScrollController _scrollController = ScrollController();
  LegDayTrendRange _selectedRange = LegDayTrendRange.thirtyDays;
  LegDayTrendMetric _selectedMetric = LegDayTrendMetric.volume;
  LowerBodyMannequinBodyType _bodyType = LowerBodyMannequinBodyType.male;

  @override
  void initState() {
    super.initState();
    _loadBodyType();
  }

  Future<void> _loadBodyType() async {
    final prefs = await SharedPreferences.getInstance();
    final rawValue = prefs.getString(_kUserGenderStorageKey) ?? '';
    final normalized = rawValue.trim().toLowerCase();
    final nextType =
        normalized == 'female' ||
                normalized == 'f' ||
                normalized == 'woman' ||
                normalized == 'girl'
            ? LowerBodyMannequinBodyType.female
            : LowerBodyMannequinBodyType.male;
    if (!mounted) return;
    setState(() => _bodyType = nextType);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data =
        widget.data ??
        (widget.template != null
            ? LegDayTrendsMockData.forTemplate(widget.template!)
            : LegDayTrendsMockData.sample);
    final snapshot = data.snapshotFor(_selectedRange);
    final targetMuscles = data.muscleBalance.distribution
        .map((entry) => entry.label)
        .toList(growable: false);
    final lowerBodyRegions = lowerBodyRegionsForLabels(targetMuscles);
    final showsLowerBodyMap =
        targetMuscles.isNotEmpty &&
        lowerBodyRegions.length == targetMuscles.length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topInset = MediaQuery.paddingOf(context).top;
    const islandTop = 16.0;
    const headerLeadingInset = 62.0;
    final listTopPadding = topInset + islandTop;

    return Scaffold(
      backgroundColor: liftCanvasColor(context),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  kPagePadding,
                  listTopPadding,
                  kPagePadding,
                  12 + bottomInset,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final twoColumn = constraints.maxWidth >= 720;
                        final sectionWidth =
                            twoColumn
                                ? (constraints.maxWidth - 12) / 2
                                : constraints.maxWidth;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 48,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const SizedBox(width: headerLeadingInset),
                                  Expanded(
                                    child: Text(
                                      data.title,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                        height: 1.02,
                                        color: Color(0xFF171717),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              data.subtitle,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (showsLowerBodyMap)
                              TargetMusclesCard(
                                targetMuscles: targetMuscles,
                                muscleStatuses: data.recovery.muscleStatuses,
                                bodyType: _bodyType,
                                accentColor: _kLegDayTrendsAccent,
                              )
                            else
                              WorkoutFocusCard(
                                targetMuscles: targetMuscles,
                                muscleStatuses: data.recovery.muscleStatuses,
                                bodyType: _bodyType,
                                accentColor: _kLegDayTrendsAccent,
                              ),
                            const SizedBox(height: 12),
                            LegDayRangeSelector(
                              selectedRange: _selectedRange,
                              onChanged:
                                  (range) =>
                                      setState(() => _selectedRange = range),
                              accentColor: _kLegDayTrendsAccent,
                            ),
                            const SizedBox(height: 16),
                            PrimaryTrendCard(
                              snapshot: snapshot,
                              selectedMetric: _selectedMetric,
                              onMetricChanged:
                                  (metric) =>
                                      setState(() => _selectedMetric = metric),
                              accentColor: _kLegDayTrendsAccent,
                            ),
                            const SizedBox(height: 12),
                            KeyLiftsCard(keyLifts: data.keyLifts),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: sectionWidth,
                                  child: MuscleBalanceCard(
                                    summary: data.muscleBalance,
                                    accentColor: _kLegDayTrendsAccent,
                                  ),
                                ),
                                SizedBox(
                                  width: sectionWidth,
                                  child: RecoveryTrendsCard(
                                    summary: data.recovery,
                                  ),
                                ),
                                SizedBox(
                                  width: sectionWidth,
                                  child: ConsistencyCard(
                                    summary: data.consistency,
                                  ),
                                ),
                                SizedBox(
                                  width: sectionWidth,
                                  child: SmartInsightsCard(
                                    summary: data.smartInsight,
                                    accentColor: _kLegDayTrendsAccent,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: topInset + islandTop,
              left: kPagePadding,
              child: _BackOrbButton(onTap: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackOrbButton extends StatelessWidget {
  const _BackOrbButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LiftFloatingIslandSurface(
      borderRadius: 24,
      boxShadow: LiftFloatingIslandTokens.chipShadows,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: MynauiIcon(
                MynauiGlyphs.altArrowLeft,
                color: kLiftIslandOnFrosted,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
