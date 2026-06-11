import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/app/app_bootstrap.dart';
import 'package:lift/features/profile/edit_profile_page.dart';
import 'package:lift/features/profile/profile_history_metrics.dart';
import 'package:lift/features/profile/profile_mock_data.dart';
import 'package:lift/features/profile/profile_models.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/models/workout_history_entry.dart';
import 'package:lift/shared/widgets/lift_action_button.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/lift_pressable.dart';
import 'package:lift/shared/widgets/scroll_linked_top_blur_scrim.dart';

const Color _kProfileCanvas = Color(0xFFF7F7F8);
const Color _kProfileAccent = kAccentColor;
const Color _kProfileAccentSoft = Color(0xFFF1F3F5);
const Color _kProfileTextStrong = kAccentColor;
const Color _kProfileTextMuted = kAccentMid;
const Color _kProfileBorder = Color(0xFFE5E8EC);

enum _ProfileTab { workouts, progress, activity }

enum _ProgressChartView { volume, strength, balance }

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.data,
    this.isOwnProfile = true,
    this.showBack = true,
    this.workoutHistory,
    this.onBack,
    this.onEditProfile,
    this.onShareProfile,
    this.onSettingsTap,
    this.onToggleFollow,
    this.onMessageTap,
    this.onViewGym,
  });

  final ProfileViewData? data;
  final bool isOwnProfile;
  final bool showBack;
  final List<WorkoutHistoryEntry>? workoutHistory;
  final VoidCallback? onBack;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;
  final ValueChanged<ProfileViewData>? onSettingsTap;
  final VoidCallback? onToggleFollow;
  final VoidCallback? onMessageTap;
  final VoidCallback? onViewGym;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ScrollController _scrollController = ScrollController();
  late ProfileViewData _data;
  late bool _isFollowing;
  _ProfileTab _selectedTab = _ProfileTab.workouts;
  int _historyHydrationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _resolveData();
    _hydrateRecentWorkouts();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.isOwnProfile != widget.isOwnProfile ||
        oldWidget.workoutHistory != widget.workoutHistory) {
      _resolveData();
      _hydrateRecentWorkouts();
    }
  }

  void _resolveData() {
    _historyHydrationGeneration += 1;
    _data =
        widget.data ??
        (widget.isOwnProfile
            ? ProfileMockData.ownProfile()
            : ProfileMockData.viewedProfile());
    if (widget.isOwnProfile) {
      _data =
          widget.workoutHistory != null
              ? _dataWithHistory(widget.workoutHistory!)
              : _dataWithHistory(const <WorkoutHistoryEntry>[]);
    }
    _isFollowing = _data.isFollowing;
  }

  Future<void> _hydrateRecentWorkouts() async {
    if (!widget.isOwnProfile || widget.workoutHistory != null) return;
    final generation = ++_historyHydrationGeneration;
    final storedHistory = await loadStoredWorkoutHistory();
    if (!mounted || generation != _historyHydrationGeneration) return;
    setState(() {
      _data = _dataWithHistory(storedHistory);
    });
  }

  ProfileViewData _dataWithHistory(List<WorkoutHistoryEntry> history) {
    final metrics = deriveProfileHistoryMetrics(history);
    return _data.copyWith(
      user: _data.user.copyWith(stats: metrics.stats),
      trainingScore: metrics.trainingScore,
      recentWorkouts: _buildRecentWorkoutSummaries(history),
      analytics: metrics.analytics,
      activity: metrics.activity,
      highlights: metrics.highlights,
    );
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _toggleFollow() {
    if (widget.onToggleFollow != null) {
      widget.onToggleFollow!();
      return;
    }
    setState(() => _isFollowing = !_isFollowing);
  }

  void _handleEditProfileTap() {
    if (widget.onEditProfile != null) {
      widget.onEditProfile!();
      return;
    }
    _openEditProfile();
  }

  Future<void> _openEditProfile() async {
    final updated = await pushEditProfilePage(context, initialData: _data);
    if (!mounted || updated == null) return;
    setState(() => _data = updated);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final tokens = ProfilePageTokens.forPlatform(platform);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const islandTop = 16.0;
    final listTopPadding =
        topInset + islandTop + kLiftIslandHeaderHeight + kIslandHeaderGap;
    final topBlurBandHeight = listTopPadding + 88.0;

    return Scaffold(
      backgroundColor: liftCanvasColor(context, light: _kProfileCanvas),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  kPagePadding,
                  listTopPadding,
                  kPagePadding,
                  bottomInset + 24,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ProfileHeader(
                            profile: _data.user,
                            isOwnProfile: widget.isOwnProfile,
                            isFollowing: _isFollowing,
                            accentColor: _kProfileAccent,
                            tokens: tokens,
                            onEditProfile: _handleEditProfileTap,
                            onShareProfile: widget.onShareProfile ?? () {},
                            onSettingsTap:
                                widget.onSettingsTap != null
                                    ? () => widget.onSettingsTap!(_data)
                                    : null,
                            onToggleFollow: _toggleFollow,
                            onMessageTap: widget.onMessageTap ?? () {},
                          ),
                          SizedBox(height: tokens.sectionGap),
                          PerformanceCard(
                            score: _data.trainingScore,
                            tokens: tokens,
                            accentColor: _kProfileAccent,
                          ),
                          SizedBox(height: tokens.sectionGap),
                          _ProfileSegmentedControl<_ProfileTab>(
                            options: const <_SegmentOption<_ProfileTab>>[
                              _SegmentOption(
                                value: _ProfileTab.workouts,
                                label: 'Workouts',
                              ),
                              _SegmentOption(
                                value: _ProfileTab.progress,
                                label: 'Progress',
                              ),
                              _SegmentOption(
                                value: _ProfileTab.activity,
                                label: 'Activity',
                              ),
                            ],
                            selectedValue: _selectedTab,
                            onChanged:
                                (value) => setState(() => _selectedTab = value),
                          ),
                          SizedBox(height: tokens.sectionGap),
                          AnimatedSwitcher(
                            duration: LiftMotion.standard,
                            switchInCurve: LiftMotion.enterCurve,
                            switchOutCurve: LiftMotion.exitCurve,
                            child: KeyedSubtree(
                              key: ValueKey<_ProfileTab>(_selectedTab),
                              child: _buildSelectedTab(tokens),
                            ),
                          ),
                          if (_data.user.mode == ProfileMode.gym &&
                              _data.gym != null) ...[
                            SizedBox(height: tokens.sectionGap),
                            _GymContextCard(
                              gym: _data.gym!,
                              tokens: tokens,
                              onViewGym: widget.onViewGym ?? () {},
                            ),
                          ],
                          SizedBox(height: tokens.sectionGap),
                          _HighlightsCard(
                            highlights: _data.highlights,
                            tokens: tokens,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topBlurBandHeight,
              child: IgnorePointer(
                child: ScrollLinkedTopBlurScrim(
                  scrollController: _scrollController,
                  scrollRampDistance: 120,
                  maxBlurSigma: 16,
                  topTint: _kProfileCanvas,
                  maxTintOpacity: 0.28,
                ),
              ),
            ),
            Positioned(
              top: topInset + islandTop,
              left: kPagePadding,
              right: kPagePadding,
              child: LiftIslandHeader(
                scrollController: _scrollController,
                title: 'Profile',
                leading:
                    widget.showBack
                        ? LiftIslandHeaderAction(
                          onTap: _handleBack,
                          child: MynauiIcon(
                            MynauiGlyphs.altArrowLeft,
                            color: kLiftIslandOnFrosted,
                            size: tokens.isApple ? 20 : 22,
                          ),
                        )
                        : null,
                trailing: LiftIslandHeaderAction(
                  onTap: widget.onShareProfile ?? () {},
                  child: const MynauiIcon(
                    MynauiGlyphs.squareShareLine,
                    color: kLiftIslandOnFrosted,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTab(ProfilePageTokens tokens) {
    switch (_selectedTab) {
      case _ProfileTab.workouts:
        return WorkoutList(workouts: _data.recentWorkouts, tokens: tokens);
      case _ProfileTab.progress:
        return ChartSection(analytics: _data.analytics, tokens: tokens);
      case _ProfileTab.activity:
        return ActivityList(activity: _data.activity, tokens: tokens);
    }
  }
}

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.isOwnProfile,
    required this.isFollowing,
    required this.accentColor,
    required this.tokens,
    required this.onEditProfile,
    required this.onShareProfile,
    required this.onToggleFollow,
    required this.onMessageTap,
    this.onSettingsTap,
  });

  final UserProfile profile;
  final bool isOwnProfile;
  final bool isFollowing;
  final Color accentColor;
  final ProfilePageTokens tokens;
  final VoidCallback onEditProfile;
  final VoidCallback onShareProfile;
  final VoidCallback? onSettingsTap;
  final VoidCallback onToggleFollow;
  final VoidCallback onMessageTap;

  @override
  Widget build(BuildContext context) {
    final stats = profile.stats;

    return _ProfileCard(
      tokens: tokens,
      padding: EdgeInsets.all(tokens.heroPadding),
      accented: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarView(
                name: profile.name,
                avatarUrl: profile.avatarUrl,
                size: tokens.isApple ? 84 : 80,
              ),
              SizedBox(width: tokens.itemGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: TextStyle(
                        fontSize: tokens.isApple ? 28 : 26,
                        fontWeight: FontWeight.w700,
                        color: _kProfileTextStrong,
                        height: 1.04,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profile.username,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kProfileTextMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetaChip(
                          label:
                              profile.mode == ProfileMode.gym
                                  ? 'Member at ${profile.gymName ?? 'Gym'}'
                                  : 'Independent',
                          accent: true,
                        ),
                        _MetaChip(label: profile.plan),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((profile.headline ?? '').trim().isNotEmpty) ...[
            SizedBox(height: tokens.itemGap),
            Text(
              profile.headline!,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: _kProfileTextMuted.withValues(alpha: 0.96),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          SizedBox(height: tokens.sectionGap),
          Row(
            children: [
              Expanded(
                child: _ProfileStatTile(
                  label: 'Workouts',
                  value: '${stats.workouts}',
                  highlighted: false,
                ),
              ),
              SizedBox(width: tokens.compactGap),
              Expanded(
                child: _ProfileStatTile(
                  label: 'Streak',
                  value: '${stats.streak}d',
                  highlighted: false,
                ),
              ),
              SizedBox(width: tokens.compactGap),
              Expanded(
                child: _ProfileStatTile(
                  label: 'Training Score',
                  value: '${stats.score}',
                  highlighted: true,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.sectionGap),
          isOwnProfile
              ? _OwnProfileActions(
                accentColor: accentColor,
                showSettings: onSettingsTap != null,
                onEditProfile: onEditProfile,
                onShareProfile: onShareProfile,
                onSettingsTap: onSettingsTap,
              )
              : _ViewedProfileActions(
                accentColor: accentColor,
                isFollowing: isFollowing,
                onToggleFollow: onToggleFollow,
                onMessageTap: onMessageTap,
              ),
        ],
      ),
    );
  }
}

class PerformanceCard extends StatelessWidget {
  const PerformanceCard({
    super.key,
    required this.score,
    required this.tokens,
    required this.accentColor,
  });

  final TrainingScore score;
  final ProfilePageTokens tokens;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardHeader(
          title: 'Performance',
          subtitle:
              'Current training score, quality signals, and this week’s coaching insight.',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _LabelPill(label: score.label),
            const SizedBox(width: 8),
            Text(
              'Current Training Score',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _kProfileTextMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricPill(title: 'Consistency', value: '${score.consistency}%'),
            _MetricPill(title: 'Balance', value: score.balance),
            _MetricPill(title: 'Recovery', value: score.recovery),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kProfileAccentSoft.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kProfileAccent.withValues(alpha: 0.12)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _kProfileAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: _kProfileAccent,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  score.insight,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.42,
                    color: _kProfileTextStrong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return _ProfileCard(
      tokens: tokens,
      accented: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 560;
          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: _TrainingScoreGauge(value: score.value),
                  ),
                ),
                details,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 20, top: 2),
                child: _TrainingScoreGauge(value: score.value),
              ),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class WorkoutList extends StatelessWidget {
  const WorkoutList({super.key, required this.workouts, required this.tokens});

  final List<WorkoutSummary> workouts;
  final ProfilePageTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (workouts.isEmpty) {
      return _ProfileCard(
        tokens: tokens,
        child: const _SectionEmptyState(
          title: 'No workouts yet',
          message: 'Recent sessions will appear here once workouts are logged.',
        ),
      );
    }

    return _ProfileCard(
      tokens: tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            title: 'Recent Workouts',
            subtitle:
                'Latest sessions with duration, volume, and muscle emphasis.',
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < workouts.length; index += 1) ...[
            _WorkoutRow(workout: workouts[index]),
            if (index < workouts.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Divider(
                  height: 1,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class ChartSection extends StatefulWidget {
  const ChartSection({
    super.key,
    required this.analytics,
    required this.tokens,
  });

  final ProfileAnalytics analytics;
  final ProfilePageTokens tokens;

  @override
  State<ChartSection> createState() => _ChartSectionState();
}

class _ChartSectionState extends State<ChartSection> {
  _ProgressChartView _selectedView = _ProgressChartView.volume;

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      tokens: widget.tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            title: 'Progress',
            subtitle: _chartSubtitle(_selectedView),
          ),
          const SizedBox(height: 16),
          _ProfileSegmentedControl<_ProgressChartView>(
            options: const <_SegmentOption<_ProgressChartView>>[
              _SegmentOption(value: _ProgressChartView.volume, label: 'Volume'),
              _SegmentOption(
                value: _ProgressChartView.strength,
                label: 'Strength',
              ),
              _SegmentOption(
                value: _ProgressChartView.balance,
                label: 'Balance',
              ),
            ],
            selectedValue: _selectedView,
            onChanged: (value) => setState(() => _selectedView = value),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: LiftMotion.standard,
            switchInCurve: LiftMotion.enterCurve,
            switchOutCurve: LiftMotion.exitCurve,
            child: SizedBox(
              key: ValueKey<_ProgressChartView>(_selectedView),
              child: _buildChartContent(),
            ),
          ),
        ],
      ),
    );
  }

  String _chartSubtitle(_ProgressChartView view) {
    switch (view) {
      case _ProgressChartView.volume:
        return 'Volume trend across the current block.';
      case _ProgressChartView.strength:
        return 'Key lift progression from the last block.';
      case _ProgressChartView.balance:
        return 'Current workload balance across major patterns.';
    }
  }

  Widget _buildChartContent() {
    switch (_selectedView) {
      case _ProgressChartView.volume:
        if (widget.analytics.volumeTrend.isEmpty) {
          return const _SectionEmptyState(
            title: 'No volume trend yet',
            message: 'Log more sessions to populate the volume chart.',
          );
        }
        final values = widget.analytics.volumeTrend
            .map((point) => point.value)
            .toList(growable: false);
        final peak = values.reduce(math.max);
        final average =
            values.fold<double>(0, (sum, value) => sum + value) / values.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 220,
              child: _VolumeTrendChart(points: widget.analytics.volumeTrend),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MiniMetricTile(
                    label: 'Block average',
                    value: '${average.toStringAsFixed(1)}k kg',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniMetricTile(
                    label: 'Peak week',
                    value: '${peak.toStringAsFixed(0)}k kg',
                  ),
                ),
              ],
            ),
          ],
        );
      case _ProgressChartView.strength:
        if (widget.analytics.strengthProgression.isEmpty) {
          return const _SectionEmptyState(
            title: 'No strength progression yet',
            message: 'Key lifts will populate once progress snapshots exist.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 240,
              child: _StrengthProgressChart(
                lifts: widget.analytics.strengthProgression,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.analytics.strengthProgression
                  .map((lift) {
                    final delta = lift.current - lift.previous;
                    return _LabelPill(
                      label:
                          '${lift.lift} +${delta.toStringAsFixed(delta % 1 == 0 ? 0 : 1)}kg',
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        );
      case _ProgressChartView.balance:
        if (widget.analytics.muscleBalance.isEmpty) {
          return const _SectionEmptyState(
            title: 'No balance data yet',
            message:
                'Muscle balance appears after enough workout history is available.',
          );
        }
        return Column(
          children: widget.analytics.muscleBalance
              .map(
                (datum) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _BalanceMeter(datum: datum),
                ),
              )
              .toList(growable: false),
        );
    }
  }
}

class ActivityList extends StatelessWidget {
  const ActivityList({super.key, required this.activity, required this.tokens});

  final List<ActivityEntry> activity;
  final ProfilePageTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (activity.isEmpty) {
      return _ProfileCard(
        tokens: tokens,
        child: const _SectionEmptyState(
          title: 'No activity yet',
          message: 'Completed workouts, PRs, and milestones will appear here.',
        ),
      );
    }

    return _ProfileCard(
      tokens: tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            title: 'Activity',
            subtitle: 'Completed workouts, PRs, and milestones only.',
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < activity.length; index += 1) ...[
            _ActivityRow(entry: activity[index]),
            if (index < activity.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Divider(
                  height: 1,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _GymContextCard extends StatelessWidget {
  const _GymContextCard({
    required this.gym,
    required this.tokens,
    required this.onViewGym,
  });

  final GymSummary gym;
  final ProfilePageTokens tokens;
  final VoidCallback onViewGym;

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      tokens: tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            title: 'Gym',
            subtitle: 'Home gym context and membership-linked access.',
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GymLogoBadge(name: gym.name),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gym.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _kProfileTextStrong,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      gym.description,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: _kProfileTextMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 140,
            child: LiftActionButton(
              label: gym.ctaLabel,
              color: _kProfileAccent,
              onTap: onViewGym,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard({required this.highlights, required this.tokens});

  final List<HighlightSummary> highlights;
  final ProfilePageTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (highlights.isEmpty) {
      return _ProfileCard(
        tokens: tokens,
        child: const _SectionEmptyState(
          title: 'No highlights yet',
          message:
              'Long-term milestones will show up as training history builds.',
        ),
      );
    }

    return _ProfileCard(
      tokens: tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            title: 'Highlights',
            subtitle: 'Long-term markers that define this training identity.',
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 620;
              final tileWidth =
                  isWide
                      ? (constraints.maxWidth - 24) / 3
                      : (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: highlights
                    .map(
                      (highlight) => SizedBox(
                        width: tileWidth,
                        child: _HighlightTile(highlight: highlight),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OwnProfileActions extends StatelessWidget {
  const _OwnProfileActions({
    required this.accentColor,
    required this.showSettings,
    required this.onEditProfile,
    required this.onShareProfile,
    this.onSettingsTap,
  });

  final Color accentColor;
  final bool showSettings;
  final VoidCallback onEditProfile;
  final VoidCallback onShareProfile;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: LiftActionButton(
            label: 'Edit Profile',
            color: accentColor,
            solid: true,
            onTap: onEditProfile,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: LiftActionButton(
            label: 'Share',
            color: accentColor,
            onTap: onShareProfile,
          ),
        ),
        if (showSettings) ...[
          const SizedBox(width: 10),
          LiftActionIconButton(
            assetPath: MynauiGlyphs.settings,
            color: accentColor,
            size: 44,
            iconSize: 22,
            onTap: onSettingsTap ?? () {},
          ),
        ],
      ],
    );
  }
}

class _ViewedProfileActions extends StatelessWidget {
  const _ViewedProfileActions({
    required this.accentColor,
    required this.isFollowing,
    required this.onToggleFollow,
    required this.onMessageTap,
  });

  final Color accentColor;
  final bool isFollowing;
  final VoidCallback onToggleFollow;
  final VoidCallback onMessageTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LiftActionButton(
            label: isFollowing ? 'Following' : 'Follow',
            color: accentColor,
            solid: !isFollowing,
            onTap: onToggleFollow,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LiftActionButton(
            label: 'Message',
            color: accentColor,
            onTap: onMessageTap,
          ),
        ),
      ],
    );
  }
}

class _ProfileStatTile extends StatelessWidget {
  const _ProfileStatTile({
    required this.label,
    required this.value,
    required this.highlighted,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color:
            highlighted
                ? _kProfileAccent.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              highlighted
                  ? _kProfileAccent.withValues(alpha: 0.14)
                  : _kProfileBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: _kProfileTextMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: highlighted ? 28 : 24,
              fontWeight: FontWeight.w700,
              color: _kProfileTextStrong,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSegmentedControl<T> extends StatelessWidget {
  const _ProfileSegmentedControl({
    required this.options,
    required this.selectedValue,
    required this.onChanged,
  });

  final List<_SegmentOption<T>> options;
  final T selectedValue;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kProfileBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: options
            .map(
              (option) => Expanded(
                child: LiftPressable(
                  onTap: () => onChanged(option.value),
                  borderRadius: 14,
                  pressedScale: LiftMotion.gentlePressScale,
                  child: AnimatedContainer(
                    duration: LiftMotion.standard,
                    curve: LiftMotion.enterCurve,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color:
                          option.value == selectedValue
                              ? _kProfileAccent.withValues(alpha: 0.10)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              option.value == selectedValue
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                          color:
                              option.value == selectedValue
                                  ? _kProfileAccent
                                  : _kProfileTextMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _SegmentOption<T> {
  const _SegmentOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.child,
    required this.tokens,
    this.padding = const EdgeInsets.all(18),
    this.accented = false,
  });

  final Widget child;
  final ProfilePageTokens tokens;
  final EdgeInsetsGeometry padding;
  final bool accented;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(tokens.cardRadius);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: tokens.isApple ? 0.04 : 0.055,
            ),
            blurRadius: tokens.isApple ? 28 : 18,
            offset: Offset(0, tokens.isApple ? 10 : 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: radius,
            border: Border.all(color: _kProfileBorder),
          ),
          child: Stack(
            children: [
              if (accented) ...[
                Positioned(
                  top: -48,
                  right: -24,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _kProfileAccent.withValues(alpha: 0.12),
                          _kProfileAccent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: -32,
                  bottom: -48,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _kProfileAccent.withValues(alpha: 0.07),
                          _kProfileAccent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionEmptyState extends StatelessWidget {
  const _SectionEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _kProfileTextStrong,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.42,
            color: _kProfileTextMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AvatarView extends StatelessWidget {
  const _AvatarView({
    required this.name,
    required this.avatarUrl,
    required this.size,
  });

  final String name;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.34);
    final initials = _initialsFor(name);

    if ((avatarUrl ?? '').trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder:
              (context, error, stackTrace) =>
                  _AvatarFallback(initials: initials, size: size),
        ),
      );
    }

    return _AvatarFallback(initials: initials, size: size);
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initials, required this.size});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F9FA), Color(0xFFE3EAEE)],
        ),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.28,
          fontWeight: FontWeight.w700,
          color: _kProfileTextStrong,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:
            accent
                ? _kProfileAccentSoft.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              accent
                  ? _kProfileAccent.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: accent ? _kProfileAccent : _kProfileTextStrong,
        ),
      ),
    );
  }
}

class _LabelPill extends StatelessWidget {
  const _LabelPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: _kProfileAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _kProfileAccent,
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kProfileBorder),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$title  ',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kProfileTextMuted,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _kProfileTextStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: _kProfileTextStrong,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.42,
            color: _kProfileTextMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TrainingScoreGauge extends StatelessWidget {
  const _TrainingScoreGauge({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final progress = (value / 100).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        return SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: CircularProgressIndicator(
                  value: animatedValue,
                  strokeWidth: 11,
                  backgroundColor: _kProfileAccent.withValues(alpha: 0.10),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    _kProfileAccent,
                  ),
                ),
              ),
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$value',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: _kProfileTextStrong,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'score',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kProfileTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({required this.workout});

  final WorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: _kProfileAccent.withValues(alpha: 0.10),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.fitness_center_rounded,
              size: 20,
              color: _kProfileAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        workout.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _kProfileTextStrong,
                        ),
                      ),
                    ),
                    if ((workout.personalRecord ?? '').isNotEmpty)
                      const _LabelPill(label: 'PR'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatDate(workout.date)}  •  ${_formatDuration(workout.duration)}  •  ${_formatVolume(workout.volume)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kProfileTextMuted,
                  ),
                ),
                if ((workout.personalRecord ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    workout.personalRecord!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kProfileAccent,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: workout.muscles
                      .map((muscle) => _MuscleChip(label: muscle))
                      .toList(growable: false),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.black.withValues(alpha: 0.28),
          ),
        ],
      ),
    );
  }
}

class _MuscleChip extends StatelessWidget {
  const _MuscleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kProfileAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconForMuscle(label), size: 13, color: _kProfileAccent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kProfileAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetricTile extends StatelessWidget {
  const _MiniMetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kProfileTextMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _kProfileTextStrong,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceMeter extends StatelessWidget {
  const _BalanceMeter({required this.datum});

  final MuscleBalanceDatum datum;

  @override
  Widget build(BuildContext context) {
    final sharePercent = (datum.share * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  datum.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kProfileTextStrong,
                  ),
                ),
              ),
              Text(
                '$sharePercent%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _kProfileAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: datum.share.clamp(0.0, 1.0),
              backgroundColor: _kProfileAccent.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(_kProfileAccent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            datum.status,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _kProfileTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _kProfileAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              _iconForActivity(entry.kind),
              size: 19,
              color: _kProfileAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: _kProfileTextStrong,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.detail,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _kProfileTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _relativeLabel(entry.date),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _kProfileTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({required this.highlight});

  final HighlightSummary highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: _kProfileAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kProfileAccent.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            highlight.title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kProfileTextMuted,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            highlight.value,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: _kProfileTextStrong,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            highlight.detail,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: _kProfileTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _GymLogoBadge extends StatelessWidget {
  const _GymLogoBadge({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5F7F9), Color(0xFFE2E9EE)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kProfileBorder),
      ),
      alignment: Alignment.center,
      child: Text(
        _initialsFor(name),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _kProfileTextStrong,
        ),
      ),
    );
  }
}

class _VolumeTrendChart extends StatelessWidget {
  const _VolumeTrendChart({required this.points});

  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    final spots = <FlSpot>[
      for (var index = 0; index < points.length; index += 1)
        FlSpot(index.toDouble(), points[index].value),
    ];
    final values = points.map((point) => point.value).toList(growable: false);
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final padding = math.max(2.5, (maxValue - minValue) * 0.2).toDouble();
    final minY = math.max(0.0, minValue - padding).toDouble();
    final maxY = (maxValue + padding).toDouble();
    final interval = _niceInterval((maxY - minY) / 4);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine:
              (_) => FlLine(
                color: Colors.black.withValues(alpha: 0.06),
                strokeWidth: 1,
              ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: interval,
              getTitlesWidget:
                  (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      '${value.toStringAsFixed(0)}k',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kProfileTextMuted,
                      ),
                    ),
                  ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    points[index].label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _kProfileTextMuted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            tooltipBorderRadius: BorderRadius.circular(14),
            getTooltipColor:
                (touchedSpot) => Colors.white.withValues(alpha: 0.96),
            getTooltipItems:
                (touchedSpots) => touchedSpots
                    .map(
                      (spot) => LineTooltipItem(
                        '${points[spot.x.toInt()].label}\n${spot.y.toStringAsFixed(1)}k kg',
                        const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _kProfileTextStrong,
                          height: 1.35,
                        ),
                      ),
                    )
                    .toList(growable: false),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.22,
            barWidth: 3.2,
            color: _kProfileAccent,
            isStrokeCapRound: true,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _kProfileAccent.withValues(alpha: 0.18),
                  _kProfileAccent.withValues(alpha: 0.02),
                ],
              ),
            ),
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, _) => spot.x == spots.last.x,
              getDotPainter:
                  (_, __, ___, ____) => FlDotCirclePainter(
                    radius: 4.5,
                    color: _kProfileAccent,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrengthProgressChart extends StatelessWidget {
  const _StrengthProgressChart({required this.lifts});

  final List<StrengthLiftSnapshot> lifts;

  @override
  Widget build(BuildContext context) {
    final maxValue = lifts
        .map((lift) => math.max(lift.current, lift.previous))
        .reduce(math.max);
    final maxY = (maxValue * 1.18).ceilToDouble();
    final interval = _niceInterval(maxY / 4);

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine:
              (_) => FlLine(
                color: Colors.black.withValues(alpha: 0.06),
                strokeWidth: 1,
              ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: interval,
              getTitlesWidget:
                  (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      value == 0 ? '0' : '${value.toInt()}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kProfileTextMuted,
                      ),
                    ),
                  ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= lifts.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: SizedBox(
                    width: 62,
                    child: Text(
                      lifts[index].lift,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kProfileTextMuted,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            tooltipBorderRadius: BorderRadius.circular(14),
            getTooltipColor: (group) => Colors.white.withValues(alpha: 0.96),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final lift = lifts[group.x.toInt()];
              final delta = lift.current - lift.previous;
              return BarTooltipItem(
                '${lift.lift}\n${lift.current.toStringAsFixed(lift.current % 1 == 0 ? 0 : 1)}kg  •  +${delta.toStringAsFixed(delta % 1 == 0 ? 0 : 1)}kg',
                const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _kProfileTextStrong,
                  height: 1.35,
                ),
              );
            },
          ),
        ),
        barGroups: [
          for (var index = 0; index < lifts.length; index += 1)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: lifts[index].current,
                  width: 22,
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      _kProfileAccent,
                      _kProfileAccent.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class ProfilePageTokens {
  const ProfilePageTokens({
    required this.isApple,
    required this.sectionGap,
    required this.itemGap,
    required this.compactGap,
    required this.cardRadius,
    required this.heroPadding,
  });

  final bool isApple;
  final double sectionGap;
  final double itemGap;
  final double compactGap;
  final double cardRadius;
  final double heroPadding;

  factory ProfilePageTokens.forPlatform(TargetPlatform platform) {
    final isApple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    return ProfilePageTokens(
      isApple: isApple,
      sectionGap: isApple ? 16 : 14,
      itemGap: isApple ? 14 : 12,
      compactGap: isApple ? 10 : 8,
      cardRadius: isApple ? 24 : 22,
      heroPadding: isApple ? 20 : 18,
    );
  }
}

String _formatDate(DateTime date) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours <= 0) return '${duration.inMinutes} min';
  return '${hours}h ${minutes}m';
}

String _formatVolume(int volumeKg) {
  if (volumeKg >= 1000) {
    return '${(volumeKg / 1000).toStringAsFixed(1)}k kg';
  }
  return '$volumeKg kg';
}

String _relativeLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final delta = today.difference(target).inDays;
  if (delta <= 0) return 'Today';
  if (delta == 1) return 'Yesterday';
  if (delta < 7) return '${delta}d ago';
  return _formatDate(date);
}

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

IconData _iconForMuscle(String muscle) {
  final normalized = muscle.toLowerCase();
  if (normalized.contains('quad') ||
      normalized.contains('ham') ||
      normalized.contains('glute') ||
      normalized.contains('calf')) {
    return Icons.directions_run_rounded;
  }
  if (normalized.contains('lat') ||
      normalized.contains('back') ||
      normalized.contains('bicep')) {
    return Icons.south_rounded;
  }
  if (normalized.contains('chest') ||
      normalized.contains('shoulder') ||
      normalized.contains('tricep')) {
    return Icons.north_rounded;
  }
  if (normalized.contains('core')) return Icons.circle_outlined;
  return Icons.adjust_rounded;
}

IconData _iconForActivity(ActivityEntryKind kind) {
  switch (kind) {
    case ActivityEntryKind.workout:
      return Icons.check_circle_outline_rounded;
    case ActivityEntryKind.pr:
      return Icons.workspace_premium_outlined;
    case ActivityEntryKind.milestone:
      return Icons.flag_outlined;
  }
}

double _niceInterval(double raw) {
  if (raw <= 0) return 1;
  final exponent = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final fraction = raw / exponent;
  final niceFraction =
      fraction <= 1
          ? 1
          : fraction <= 2
          ? 2
          : fraction <= 5
          ? 5
          : 10;
  return niceFraction * exponent;
}

List<WorkoutSummary> _buildRecentWorkoutSummaries(
  List<WorkoutHistoryEntry> history,
) {
  if (history.isEmpty) return const <WorkoutSummary>[];
  final sorted = List<WorkoutHistoryEntry>.from(history)
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  return sorted
      .take(6)
      .map(_workoutSummaryFromHistoryEntry)
      .toList(growable: false);
}

WorkoutSummary _workoutSummaryFromHistoryEntry(WorkoutHistoryEntry entry) {
  final prs = entry.prsAchieved;
  return WorkoutSummary(
    id: entry.id,
    name: entry.workoutName,
    date: entry.completedAt,
    duration: entry.duration,
    volume: entry.totalVolumeKg.round(),
    muscles: _topMusclesForHistoryEntry(entry),
    personalRecord: prs > 0 ? '$prs ${prs == 1 ? 'PR' : 'PRs'}' : null,
  );
}

List<String> _topMusclesForHistoryEntry(WorkoutHistoryEntry entry) {
  if (entry.muscleGroupVolumeKg.isNotEmpty) {
    final sorted = entry.muscleGroupVolumeKg.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .map((muscle) => muscle.key.trim())
        .where((label) => label.isNotEmpty)
        .take(3)
        .toList(growable: false);
  }

  final ordered = <String>[];
  for (final exercise in entry.exerciseSummaries) {
    for (final muscle in exercise.muscleGroups) {
      final normalized = muscle.trim();
      if (normalized.isEmpty || ordered.contains(normalized)) continue;
      ordered.add(normalized);
      if (ordered.length == 3) {
        return List<String>.unmodifiable(ordered);
      }
    }
  }
  return List<String>.unmodifiable(ordered);
}
