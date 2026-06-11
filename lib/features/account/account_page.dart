import 'package:flutter/material.dart';
import 'package:lift/app/app_appearance.dart';
import 'package:lift/app/app_bootstrap.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/calendar/training_calendar_screen.dart';
import 'package:lift/features/profile/profile_models.dart' as profile_models;
import 'package:lift/features/progress/progress_screen.dart';
import 'package:lift/features/progress/workout_history_page.dart';
import 'package:lift/features/workout/workout_templates_flow.dart';
import 'package:lift/shared/models/workout_history_entry.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/scroll_linked_top_blur_scrim.dart';
import 'package:lift/shared/widgets/surfaces.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

const Color _kAccountCanvas = Color(0xFFF7F7F8);
const Color _kAccountAccent = Color(0xFF516579);
const Color _kAccountAccentSoft = Color(0xFFF1F5F8);
const Color _kAccountConnected = Color(0xFF4E7568);
const Color _kAccountConnectedSoft = Color(0xFFEAF3EE);
const Color _kAccountIndependentSoft = Color(0xFFF5F6F9);

Color _accountCanvas(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF090A0C)
      : _kAccountCanvas;
}

Color _accountTextStrong(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFF3F4F6)
      : const Color(0xFF171717);
}

Color _accountTextMuted(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFA9B1BA)
      : Colors.grey.shade600;
}

Color _accountSoftSurface(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF202329)
      : const Color(0xFFF7F8FA);
}

enum UserMode { gymConnected, independent }

enum IntegrationKind { health, wearable, nutrition }

enum AccountActionKind { gym, health, nutrition, score }

class UserProfile {
  const UserProfile({
    required this.fullName,
    required this.handle,
    required this.mode,
    required this.plan,
    required this.stats,
    required this.integrations,
    this.gym,
    this.profileNote,
  });

  final String fullName;
  final String handle;
  final UserMode mode;
  final GymSummary? gym;
  final PlanState plan;
  final List<AccountStat> stats;
  final List<IntegrationState> integrations;
  final String? profileNote;
}

class GymSummary {
  const GymSummary({
    required this.name,
    required this.code,
    required this.locationLabel,
    required this.benefitsLabel,
  });

  final String name;
  final String code;
  final String locationLabel;
  final String benefitsLabel;
}

class IntegrationState {
  const IntegrationState({
    required this.kind,
    required this.connected,
    required this.statusLabel,
    this.detailLabel,
  });

  final IntegrationKind kind;
  final bool connected;
  final String statusLabel;
  final String? detailLabel;
}

class PlanState {
  const PlanState({
    required this.label,
    required this.detailLabel,
    this.emphasized = false,
  });

  final String label;
  final String detailLabel;
  final bool emphasized;
}

class AccountStat {
  const AccountStat({required this.label, required this.value});

  final String label;
  final String value;
}

class ActionItem {
  const ActionItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.statusLabel,
    this.highlighted = false,
    this.connected = false,
  });

  final AccountActionKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final String statusLabel;
  final bool highlighted;
  final bool connected;
}

class SettingsRowModel {
  const SettingsRowModel({
    required this.title,
    this.icon,
    this.mynauiAssetPath,
    this.subtitle,
    this.value,
    this.enabled = true,
    this.highlighted = false,
  }) : assert(
         icon != null || mynauiAssetPath != null,
         'Provide icon or mynauiAssetPath',
       );

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// When set, shown instead of a [PhosphorIcon] for [icon].
  final String? mynauiAssetPath;
  final String? value;
  final bool enabled;
  final bool highlighted;
}

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    this.user,
    this.profileData,
    this.workoutHistory,
    this.onWorkoutHistoryChanged,
    this.showBack = false,
    this.showSettingsAction = true,
    this.extraBottomInset = kShellTabContentBottomInset,
    this.onBack,
    this.onSettingsTap,
    this.onCalendarTap,
  });

  final UserProfile? user;
  final profile_models.ProfileViewData? profileData;
  final List<WorkoutHistoryEntry>? workoutHistory;
  final ValueChanged<List<WorkoutHistoryEntry>>? onWorkoutHistoryChanged;
  final bool showBack;
  final bool showSettingsAction;
  final double extraBottomInset;
  final VoidCallback? onBack;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onCalendarTap;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final ScrollController _scrollController = ScrollController();
  List<WorkoutHistoryEntry> _trainingHistory = <WorkoutHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    _trainingHistory =
        widget.workoutHistory != null
            ? List<WorkoutHistoryEntry>.from(widget.workoutHistory!)
            : <WorkoutHistoryEntry>[];
    if (widget.workoutHistory == null) {
      _loadTrainingHistory();
    }
  }

  @override
  void didUpdateWidget(covariant AccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workoutHistory != widget.workoutHistory &&
        widget.workoutHistory != null) {
      _trainingHistory = List<WorkoutHistoryEntry>.from(widget.workoutHistory!);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTrainingHistory() async {
    final storedHistory = await loadStoredWorkoutHistory();
    if (!mounted) return;
    setState(() => _trainingHistory = storedHistory);
  }

  Future<void> _persistTrainingHistory() async {
    await saveStoredWorkoutHistory(_trainingHistory);
    widget.onWorkoutHistoryChanged?.call(
      List<WorkoutHistoryEntry>.from(_trainingHistory),
    );
  }

  Future<void> _handleWorkoutCompleted(WorkoutHistoryEntry entry) async {
    setState(() {
      _trainingHistory.removeWhere((value) => value.id == entry.id);
      _trainingHistory.add(entry);
      _trainingHistory.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    });
    await _persistTrainingHistory();
  }

  Future<void> _openWorkoutHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutHistoryPage(entries: _trainingHistory),
      ),
    );
  }

  Future<void> _openRecovery() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder:
            (_) => ProgressScreen(
              history: _trainingHistory,
              showBack: true,
              showProfileAction: false,
              headerTitle: 'Recovery & Muscles',
              recoveryFocusMode: true,
            ),
      ),
    );
  }

  Future<void> _openTemplates({WorkoutFlowCommand? command}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder:
            (_) => Scaffold(
              backgroundColor: _accountCanvas(context),
              body: WorkoutTemplatesFlow(
                showRootBack: true,
                onRootBack: () => Navigator.of(context).pop(),
                showRootProfileAction: false,
                popOnBackFromDetail: false,
                popOnBackFromList: true,
                startInList: command == null,
                externalCommand: command,
                onWorkoutCompleted: (entry) {
                  _handleWorkoutCompleted(entry);
                },
              ),
            ),
      ),
    );
  }

  Future<void> _openTrainingCalendar() async {
    final flow = await Navigator.of(context).push<WorkoutFlowFromCalendar?>(
      MaterialPageRoute<WorkoutFlowFromCalendar?>(
        builder:
            (_) => const TrainingCalendarScreen(
              showBack: true,
              showProfileAction: false,
            ),
      ),
    );
    if (!mounted || flow == null) return;
    await _openTemplates(
      command: WorkoutFlowCommand(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        target:
            flow.startLive
                ? WorkoutFlowRouteTarget.live
                : WorkoutFlowRouteTarget.editor,
        templateId: flow.templateId,
      ),
    );
  }

  Future<void> _openAppearanceSheet() async {
    final appearance = LiftAppearance.of(context);
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        const modes = <ThemeMode>[
          ThemeMode.system,
          ThemeMode.light,
          ThemeMode.dark,
        ];
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SectionBoundary(
              borderRadius: 28,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appearance',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: _accountTextStrong(sheetContext),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose how LIFT looks on this device.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _accountTextMuted(sheetContext),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final mode in modes)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(sheetContext, mode),
                        borderRadius: BorderRadius.circular(kIosControlRadius),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  liftThemeModeLabel(mode),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _accountTextStrong(sheetContext),
                                  ),
                                ),
                              ),
                              if (appearance.themeMode == mode)
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: _accountTextStrong(sheetContext),
                                  size: 22,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    await appearance.setThemeMode(selected);
  }

  @override
  Widget build(BuildContext context) {
    final appearance = LiftAppearance.of(context);
    final canvas = _accountCanvas(context);
    final platform = Theme.of(context).platform;
    final profile =
        widget.user ??
        (widget.profileData != null
            ? _accountUserFromProfileData(widget.profileData!, platform)
            : AccountMockData.sampleForPlatform(platform));
    final isApple = _isApplePlatform(platform);
    final topInset = MediaQuery.paddingOf(context).top;
    final mediaBottom = MediaQuery.paddingOf(context).bottom;
    final sectionGap = isApple ? 14.0 : 12.0;
    final listBottomPadding = mediaBottom + widget.extraBottomInset + 24;

    final actions = _buildSmartActions(profile, platform);
    final trainingRows = _buildTrainingRows();
    final gymRows = _buildGymRows(profile);
    final insightRows = _buildInsightRows(platform);
    final rewardsRows = _buildRewardsRows(profile);
    final accountRows = _buildAccountRows();
    final appearanceRow = SettingsRowModel(
      title: 'Appearance',
      subtitle: 'Use system theme or choose light or dark mode',
      icon: PhosphorIconsRegular.moon,
      value: liftThemeModeLabel(appearance.themeMode),
    );

    // Same “floating island” geometry as [HomeScreen]: header is overlaid so
    // the list scrolls under the frosted bar; top padding clears the badges.
    const islandTop = 16.0;
    final listTopPadding =
        topInset + islandTop + kLiftIslandHeaderHeight + kIslandHeaderGap;
    final topBlurBandHeight = listTopPadding + 88.0;

    return Scaffold(
      backgroundColor: canvas,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ListView(
                controller: _scrollController,
                primary: false,
                padding: EdgeInsets.fromLTRB(
                  kPagePadding,
                  listTopPadding,
                  kPagePadding,
                  listBottomPadding,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ProfileHeaderCard(
                            profile: profile,
                            platform: platform,
                          ),
                          SizedBox(height: sectionGap),
                          AccountGroupedCard(
                            title: 'Smart actions',
                            subtitle:
                                'Quick control over gym access, health sync, and score quality.',
                            child: _SmartActionsGrid(actions: actions),
                          ),
                          SizedBox(height: sectionGap),
                          AccountGroupedCard(
                            title: 'Training',
                            child: Column(
                              children: _buildTrainingRowList(
                                trainingRows,
                                widget.onCalendarTap,
                              ),
                            ),
                          ),
                          SizedBox(height: sectionGap),
                          AccountGroupedCard(
                            title: 'Gym & Equipment',
                            subtitle:
                                profile.mode == UserMode.gymConnected
                                    ? profile.gym?.name
                                    : 'Machine access and gym-linked tools',
                            child: Column(children: _buildRowList(gymRows)),
                          ),
                          SizedBox(height: sectionGap),
                          AccountGroupedCard(
                            title: 'Insights',
                            subtitle:
                                'Your personal intelligence layer for training and recovery.',
                            child: Column(children: _buildRowList(insightRows)),
                          ),
                          SizedBox(height: sectionGap),
                          AccountGroupedCard(
                            title: 'Connected Apps',
                            subtitle:
                                isApple
                                    ? 'Bring Apple ecosystem data into your score.'
                                    : 'Bring Health Connect and wearable data into your score.',
                            child: Column(
                              children: _buildIntegrationRows(
                                profile,
                                platform,
                              ),
                            ),
                          ),
                          SizedBox(height: sectionGap),
                          AccountGroupedCard(
                            title: 'Rewards & Plans',
                            subtitle:
                                profile.mode == UserMode.gymConnected
                                    ? 'Membership perks, benefits, and referrals.'
                                    : 'Manage upgrades, billing, and referral rewards.',
                            child: Column(children: _buildRowList(rewardsRows)),
                          ),
                          SizedBox(height: sectionGap),
                          AccountGroupedCard(
                            title: 'Appearance',
                            child: Column(
                              children: [
                                AccountSettingsRow(
                                  model: appearanceRow,
                                  showDivider: false,
                                  onTap: _openAppearanceSheet,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: sectionGap),
                          AccountGroupedCard(
                            title: 'Account Settings',
                            child: Column(children: _buildRowList(accountRows)),
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
                  topTint: canvas,
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
                title: 'Account',
                leading:
                    widget.showBack
                        ? LiftIslandHeaderAction(
                          onTap:
                              widget.onBack ??
                              () => Navigator.of(context).pop(),
                          child: const MynauiIcon(
                            MynauiGlyphs.altArrowLeft,
                            color: kLiftIslandOnFrosted,
                            size: 22,
                          ),
                        )
                        : null,
                trailing:
                    widget.showSettingsAction
                        ? LiftIslandHeaderAction(
                          onTap: widget.onSettingsTap ?? () {},
                          child: const MynauiIcon(
                            MynauiGlyphs.settings,
                            color: kLiftIslandOnFrosted,
                            size: 23,
                          ),
                        )
                        : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRowList(List<SettingsRowModel> rows) {
    return List<Widget>.generate(rows.length, (index) {
      return AccountSettingsRow(
        model: rows[index],
        showDivider: index < rows.length - 1,
        onTap: rows[index].enabled ? () {} : null,
      );
    });
  }

  List<Widget> _buildTrainingRowList(
    List<SettingsRowModel> rows,
    VoidCallback? onCalendarTap,
  ) {
    return List<Widget>.generate(rows.length, (index) {
      final row = rows[index];
      VoidCallback? onTap;
      if (row.enabled) {
        switch (row.title) {
          case 'Workouts':
            onTap = () {
              _openWorkoutHistory();
            };
            break;
          case 'Calendar':
            onTap =
                onCalendarTap ??
                () {
                  _openTrainingCalendar();
                };
            break;
          case 'Templates':
            onTap = () {
              _openTemplates();
            };
            break;
          case 'Recovery & Muscles':
            onTap = () {
              _openRecovery();
            };
            break;
          default:
            onTap = () {};
            break;
        }
      }
      return AccountSettingsRow(
        model: row,
        showDivider: index < rows.length - 1,
        onTap: onTap,
      );
    });
  }

  List<Widget> _buildIntegrationRows(
    UserProfile profile,
    TargetPlatform platform,
  ) {
    final integrations = _platformAwareIntegrations(profile, platform);
    return List<Widget>.generate(integrations.length, (index) {
      final state = integrations[index];
      return AccountSettingsRow(
        model: SettingsRowModel(
          title: _integrationTitle(state.kind, platform),
          subtitle: _integrationSubtitle(state.kind, platform),
          icon: _integrationIcon(state.kind),
        ),
        showDivider: index < integrations.length - 1,
        trailing: _ConnectionStateChip(state: state),
        onTap: () {},
      );
    });
  }
}

class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({
    super.key,
    required this.profile,
    required this.platform,
  });

  final UserProfile profile;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGymUser = profile.mode == UserMode.gymConnected;
    final gym = profile.gym;
    final note =
        profile.profileNote ??
        (isGymUser
            ? 'Manage ${gym?.name ?? 'your gym'} access, connected apps, and account preferences.'
            : 'Manage your account plan, connected apps, and training preferences.');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark ? const Color(0xFF17191D) : Colors.white,
            isDark
                ? const Color(0xFF20242A)
                : (isGymUser ? _kAccountAccentSoft : _kAccountIndependentSoft),
          ],
        ),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarBadge(name: profile.fullName),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: _accountTextStrong(context),
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.handle,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: _accountTextMuted(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoBadge(
                          label:
                              isGymUser
                                  ? 'Member at ${gym?.name ?? 'Your gym'}'
                                  : 'Independent',
                          emphasized: isGymUser,
                        ),
                        _InfoBadge(
                          label: profile.plan.label,
                          emphasized: profile.plan.emphasized,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            note.trim(),
            style: TextStyle(
              fontSize: platform == TargetPlatform.iOS ? 13.5 : 13,
              height: 1.4,
              color: _accountTextMuted(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class AccountGroupedCard extends StatelessWidget {
  const AccountGroupedCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _accountTextStrong(context),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13.5,
                color: _accountTextMuted(context),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class AccountSettingsRow extends StatelessWidget {
  const AccountSettingsRow({
    super.key,
    required this.model,
    this.onTap,
    this.trailing,
    this.showDivider = true,
  });

  final SettingsRowModel model;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final enabled = model.enabled;
    final foreground =
        enabled ? _accountTextStrong(context) : _accountTextMuted(context);
    final subtitleColor =
        enabled ? _accountTextMuted(context) : _accountTextMuted(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(kIosControlRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color:
                          model.highlighted
                              ? (isDark
                                  ? const Color(0xFF26303A)
                                  : _kAccountAccentSoft)
                              : _accountSoftSurface(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            model.highlighted
                                ? _kAccountAccent.withValues(alpha: 0.14)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.05)),
                      ),
                    ),
                    child: Center(
                      child:
                          model.mynauiAssetPath != null
                              ? MynauiIcon(
                                model.mynauiAssetPath!,
                                size: 20,
                                color:
                                    model.highlighted
                                        ? _kAccountAccent
                                        : foreground.withValues(alpha: 0.82),
                              )
                              : PhosphorIcon(
                                model.icon!,
                                size: 20,
                                color:
                                    model.highlighted
                                        ? _kAccountAccent
                                        : foreground.withValues(alpha: 0.82),
                              ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                        if (model.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            model.subtitle!,
                            style: TextStyle(
                              fontSize: 12.8,
                              height: 1.35,
                              color: subtitleColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    trailing!,
                    const SizedBox(width: 8),
                  ] else if (model.value != null) ...[
                    Text(
                      model.value!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color:
                            model.highlighted
                                ? _kAccountAccent
                                : _accountTextMuted(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _accountTextMuted(context).withValues(alpha: 0.72),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).dividerTheme.color,
          ),
      ],
    );
  }
}

class CompactStatItem extends StatelessWidget {
  const CompactStatItem({super.key, required this.stat});

  final AccountStat stat;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color:
            isDark
                ? const Color(0xFF202329).withValues(alpha: 0.82)
                : Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stat.value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _accountTextStrong(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _accountTextMuted(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartActionsGrid extends StatelessWidget {
  const _SmartActionsGrid({required this.actions});

  final List<ActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 10.0;
        final itemWidth =
            constraints.maxWidth >= 420
                ? (constraints.maxWidth - spacing) / 2
                : constraints.maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: actions
              .map(
                (action) => SizedBox(
                  width: itemWidth,
                  child: _ActionItemCard(action: action),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _ActionItemCard extends StatelessWidget {
  const _ActionItemCard({required this.action});

  final ActionItem action;

  @override
  Widget build(BuildContext context) {
    final connectedTone = action.connected;
    final highlighted = action.highlighted;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(kIosControlRadius),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:
                highlighted
                    ? (isDark ? const Color(0xFF26303A) : _kAccountAccentSoft)
                    : (isDark
                        ? const Color(0xFF202329).withValues(alpha: 0.82)
                        : Colors.white.withValues(alpha: 0.82)),
            borderRadius: BorderRadius.circular(kIosControlRadius),
            border: Border.all(
              color:
                  highlighted
                      ? _kAccountAccent.withValues(alpha: 0.14)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color:
                          connectedTone
                              ? (isDark
                                  ? const Color(0xFF1C342C)
                                  : _kAccountConnectedSoft)
                              : (isDark
                                  ? const Color(0xFF17191D)
                                  : Colors.white.withValues(alpha: 0.92)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            connectedTone
                                ? _kAccountConnected.withValues(alpha: 0.14)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.06)),
                      ),
                    ),
                    child: Center(
                      child: PhosphorIcon(
                        action.icon,
                        size: 18,
                        color:
                            connectedTone
                                ? _kAccountConnected
                                : highlighted
                                ? _kAccountAccent
                                : _accountTextStrong(context),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _ActionStatusPill(
                    label: action.statusLabel,
                    connected: connectedTone,
                    highlighted: highlighted,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                action.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _accountTextStrong(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                action.subtitle,
                style: TextStyle(
                  fontSize: 12.8,
                  height: 1.35,
                  color: _accountTextMuted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionStateChip extends StatelessWidget {
  const _ConnectionStateChip({required this.state});

  final IntegrationState state;

  @override
  Widget build(BuildContext context) {
    final connected = state.connected;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            connected
                ? (isDark ? const Color(0xFF1C342C) : _kAccountConnectedSoft)
                : _accountSoftSurface(context),
        borderRadius: BorderRadius.circular(kIosChipRadius),
        border: Border.all(
          color:
              connected
                  ? _kAccountConnected.withValues(alpha: 0.16)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      child: Text(
        state.statusLabel.toUpperCase(),
        style: TextStyle(
          fontSize: 11.8,
          fontWeight: FontWeight.w700,
          color: connected ? _kAccountConnected : _accountTextMuted(context),
        ),
      ),
    );
  }
}

class _ActionStatusPill extends StatelessWidget {
  const _ActionStatusPill({
    required this.label,
    required this.connected,
    required this.highlighted,
  });

  final String label;
  final bool connected;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color:
            connected
                ? (isDark ? const Color(0xFF1C342C) : _kAccountConnectedSoft)
                : highlighted
                ? (isDark ? const Color(0xFF26303A) : _kAccountAccentSoft)
                : _accountSoftSurface(context),
        borderRadius: BorderRadius.circular(kIosChipRadius),
        border: Border.all(
          color:
              connected
                  ? _kAccountConnected.withValues(alpha: 0.16)
                  : highlighted
                  ? _kAccountAccent.withValues(alpha: 0.12)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color:
              connected
                  ? _kAccountConnected
                  : highlighted
                  ? _kAccountAccent
                  : _accountTextMuted(context),
        ),
      ),
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = _initialsForName(name);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors:
              isDark
                  ? const [Color(0xFF262A31), Color(0xFF17191D)]
                  : const [Color(0xFFF7F8FA), Color(0xFFE4EAF0)],
        ),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: _accountTextStrong(context),
          ),
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.label, this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color:
            emphasized
                ? (isDark ? const Color(0xFF26303A) : _kAccountAccentSoft)
                : (isDark
                    ? const Color(0xFF202329).withValues(alpha: 0.82)
                    : Colors.white.withValues(alpha: 0.82)),
        borderRadius: BorderRadius.circular(kIosChipRadius),
        border: Border.all(
          color:
              emphasized
                  ? _kAccountAccent.withValues(alpha: 0.12)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: emphasized ? _kAccountAccent : _accountTextMuted(context),
        ),
      ),
    );
  }
}

class AccountMockData {
  static const UserProfile gymConnectedIosUser = UserProfile(
    fullName: 'Amara Stone',
    handle: '@amarastone',
    mode: UserMode.gymConnected,
    gym: GymSummary(
      name: 'Atlas Athletic Club',
      code: 'ATLAS-4281',
      locationLabel: 'City floor • machine zone synced',
      benefitsLabel: 'Priority machine access and coach-led programming',
    ),
    plan: PlanState(
      label: 'Included in membership',
      detailLabel: 'Premium tools unlocked through Atlas Athletic Club',
      emphasized: true,
    ),
    stats: [
      AccountStat(label: 'Workouts', value: '184'),
      AccountStat(label: 'Streak', value: '21d'),
      AccountStat(label: 'Training Score', value: '89'),
    ],
    integrations: [
      IntegrationState(
        kind: IntegrationKind.health,
        connected: true,
        statusLabel: 'Connected',
        detailLabel: 'Synced this morning',
      ),
      IntegrationState(
        kind: IntegrationKind.wearable,
        connected: true,
        statusLabel: 'Connected',
        detailLabel: 'Daily recovery data active',
      ),
      IntegrationState(
        kind: IntegrationKind.nutrition,
        connected: false,
        statusLabel: 'Not connected',
        detailLabel: 'Add fuelling context',
      ),
    ],
    profileNote:
        'Atlas membership covers advanced machine guidance, recovery scoring, and coach-facing insights.',
  );

  static const UserProfile independentAndroidUser = UserProfile(
    fullName: 'Mason Reed',
    handle: '@masonlifts',
    mode: UserMode.independent,
    plan: PlanState(
      label: 'Free Plan',
      detailLabel:
          'Upgrade for advanced trends, score depth, and machine intelligence',
    ),
    stats: [
      AccountStat(label: 'Workouts', value: '46'),
      AccountStat(label: 'Streak', value: '6d'),
      AccountStat(label: 'Training Score', value: '71'),
    ],
    integrations: [
      IntegrationState(
        kind: IntegrationKind.health,
        connected: false,
        statusLabel: 'Not connected',
        detailLabel: 'Connect daily health signals',
      ),
      IntegrationState(
        kind: IntegrationKind.wearable,
        connected: false,
        statusLabel: 'Not connected',
        detailLabel: 'Bring wearable context into recovery',
      ),
      IntegrationState(
        kind: IntegrationKind.nutrition,
        connected: true,
        statusLabel: 'Connected',
        detailLabel: 'Meals and habits synced',
      ),
    ],
    profileNote:
        'You are training independently right now. Join a gym or upgrade to unlock machine-linked guidance and deeper score accuracy.',
  );

  static UserProfile sampleForPlatform(TargetPlatform platform) {
    return _isApplePlatform(platform)
        ? gymConnectedIosUser
        : independentAndroidUser;
  }
}

bool _isApplePlatform(TargetPlatform platform) {
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

UserProfile _accountUserFromProfileData(
  profile_models.ProfileViewData data,
  TargetPlatform platform,
) {
  final user = data.user;
  final isGymUser = user.mode == profile_models.ProfileMode.gym;
  final gymName = user.gymName ?? data.gym?.name ?? 'Your gym';
  final gymDescription =
      user.gymDescription ??
      data.gym?.description ??
      'Connected gym access and machine-linked tools.';
  final sample = AccountMockData.sampleForPlatform(platform);
  final score = data.trainingScore.value;
  return UserProfile(
    fullName: user.name,
    handle: user.username,
    mode: isGymUser ? UserMode.gymConnected : UserMode.independent,
    gym:
        isGymUser
            ? GymSummary(
              name: gymName,
              code: 'Member access',
              locationLabel: gymDescription,
              benefitsLabel:
                  _isMembershipPlan(user.plan)
                      ? 'Membership benefits active'
                      : 'Gym-linked features available',
            )
            : null,
    plan: PlanState(
      label: user.plan,
      detailLabel:
          _isMembershipPlan(user.plan)
              ? 'Premium tools are currently unlocked through your membership.'
              : 'Manage your plan status and unlock deeper training intelligence.',
      emphasized: _isPremiumPlan(user.plan),
    ),
    stats: <AccountStat>[
      AccountStat(label: 'Workouts', value: '${user.stats.workouts}'),
      AccountStat(label: 'Streak', value: '${user.stats.streak}d'),
      AccountStat(label: 'Training Score', value: '$score'),
    ],
    integrations: sample.integrations,
    profileNote:
        isGymUser
            ? 'Manage $gymName access, connected apps, and account preferences.'
            : 'Manage your account plan, connected apps, and training preferences.',
  );
}

bool _isMembershipPlan(String planLabel) {
  return planLabel.toLowerCase().contains('membership');
}

bool _isPremiumPlan(String planLabel) {
  final normalized = planLabel.toLowerCase();
  return normalized.contains('membership') || normalized.contains('pro');
}

String _initialsForName(String name) {
  final parts = name
      .split(' ')
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'L';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

String _healthPlatformLabel(TargetPlatform platform) {
  return _isApplePlatform(platform) ? 'Apple Health' : 'Health Connect';
}

String _wearablePlatformLabel(TargetPlatform platform) {
  return _isApplePlatform(platform) ? 'Apple Watch' : 'Wear OS';
}

String _integrationTitle(IntegrationKind kind, TargetPlatform platform) {
  switch (kind) {
    case IntegrationKind.health:
      return _healthPlatformLabel(platform);
    case IntegrationKind.wearable:
      return _wearablePlatformLabel(platform);
    case IntegrationKind.nutrition:
      return 'Nutrition App';
  }
}

String _integrationSubtitle(IntegrationKind kind, TargetPlatform platform) {
  switch (kind) {
    case IntegrationKind.health:
      return _isApplePlatform(platform)
          ? 'Improve score accuracy with workouts, sleep, and recovery.'
          : 'Improve score accuracy with sessions, sleep, and recovery via Health Connect.';
    case IntegrationKind.wearable:
      return _isApplePlatform(platform)
          ? 'Add heart rate, rings, and readiness context.'
          : 'Bring wearable recovery context into your score.';
    case IntegrationKind.nutrition:
      return 'Add fuelling context to recovery and performance.';
  }
}

IconData _integrationIcon(IntegrationKind kind) {
  switch (kind) {
    case IntegrationKind.health:
      return PhosphorIconsRegular.heartbeat;
    case IntegrationKind.wearable:
      return PhosphorIconsRegular.watch;
    case IntegrationKind.nutrition:
      return PhosphorIconsRegular.appleLogo;
  }
}

List<IntegrationState> _platformAwareIntegrations(
  UserProfile profile,
  TargetPlatform platform,
) {
  final health =
      profile.integrations
          .where((state) => state.kind == IntegrationKind.health)
          .first;
  final wearable =
      profile.integrations
          .where((state) => state.kind == IntegrationKind.wearable)
          .first;
  final nutrition =
      profile.integrations
          .where((state) => state.kind == IntegrationKind.nutrition)
          .first;

  return [health, wearable, nutrition];
}

List<ActionItem> _buildSmartActions(
  UserProfile profile,
  TargetPlatform platform,
) {
  final health = _platformAwareIntegrations(profile, platform)[0];
  final nutrition = _platformAwareIntegrations(profile, platform)[2];
  final isGymUser = profile.mode == UserMode.gymConnected;

  return [
    ActionItem(
      kind: AccountActionKind.gym,
      title: isGymUser ? 'My gym' : 'Join a gym',
      subtitle:
          isGymUser
              ? '${profile.gym?.name ?? 'Gym'} access, benefits, and machine floor tools'
              : 'Unlock member-only machine flows, gym code access, and facility perks',
      icon:
          isGymUser
              ? PhosphorIconsRegular.buildings
              : PhosphorIconsRegular.handshake,
      statusLabel: isGymUser ? 'Member' : 'Open',
      highlighted: !isGymUser,
    ),
    ActionItem(
      kind: AccountActionKind.health,
      title:
          health.connected
              ? _healthPlatformLabel(platform)
              : 'Connect ${_healthPlatformLabel(platform)}',
      subtitle:
          health.connected
              ? 'Daily recovery inputs are already improving your score'
              : 'Bring movement, sleep, and recovery data into your score',
      icon: _integrationIcon(IntegrationKind.health),
      statusLabel: health.statusLabel,
      connected: health.connected,
    ),
    ActionItem(
      kind: AccountActionKind.nutrition,
      title:
          nutrition.connected ? 'Nutrition synced' : 'Connect nutrition data',
      subtitle:
          nutrition.connected
              ? 'Meals and fuelling context are feeding recovery guidance'
              : 'Add fuelling context to recovery and performance insights',
      icon: _integrationIcon(IntegrationKind.nutrition),
      statusLabel: nutrition.statusLabel,
      connected: nutrition.connected,
    ),
    const ActionItem(
      kind: AccountActionKind.score,
      title: 'Improve Training Score',
      subtitle:
          'Tighten your data sources, consistency, and recovery inputs to sharpen coaching',
      icon: PhosphorIconsRegular.sparkle,
      statusLabel: 'Coach',
      highlighted: true,
    ),
  ];
}

List<SettingsRowModel> _buildTrainingRows() {
  return const [
    SettingsRowModel(
      title: 'Workouts',
      subtitle: 'Review sessions, logs, and personal bests',
      mynauiAssetPath: MynauiGlyphs.weightlifting,
    ),
    SettingsRowModel(
      title: 'Calendar',
      subtitle: 'Structure your training week and upcoming sessions',
      mynauiAssetPath: MynauiGlyphs.calendarMark,
    ),
    SettingsRowModel(
      title: 'Templates',
      subtitle: 'Manage split templates and reusable plans',
      icon: PhosphorIconsRegular.files,
    ),
    SettingsRowModel(
      title: 'Custom Exercises',
      subtitle: 'Create gym-floor movements that match your setup',
      mynauiAssetPath: MynauiGlyphs.editOne,
    ),
    SettingsRowModel(
      title: 'Recovery & Muscles',
      subtitle: 'Readiness, muscle balance, and fatigue tracking',
      icon: PhosphorIconsRegular.waveform,
    ),
  ];
}

List<SettingsRowModel> _buildGymRows(UserProfile profile) {
  if (profile.mode == UserMode.gymConnected) {
    return [
      SettingsRowModel(
        title: 'My Gym',
        subtitle: profile.gym?.name ?? 'Connected gym',
        icon: PhosphorIconsRegular.buildings,
        value: 'Open',
        highlighted: true,
      ),
      const SettingsRowModel(
        title: 'Machines',
        subtitle: 'Browse your gym’s machine catalogue and setup guidance',
        icon: PhosphorIconsRegular.cpu,
      ),
      const SettingsRowModel(
        title: 'Scan Machine',
        subtitle: 'Open machine setup instantly from the gym floor',
        icon: PhosphorIconsRegular.scan,
      ),
      SettingsRowModel(
        title: 'Gym Code',
        subtitle: 'Use your member access code when needed',
        icon: PhosphorIconsRegular.identificationCard,
        value: profile.gym?.code,
      ),
    ];
  }

  return const [
    SettingsRowModel(
      title: 'Join a Gym',
      subtitle: 'Connect to a partner gym for access and machine-linked tools',
      icon: PhosphorIconsRegular.handshake,
      highlighted: true,
    ),
    SettingsRowModel(
      title: 'Machines',
      subtitle: 'Browse the generic machine catalogue',
      icon: PhosphorIconsRegular.cpu,
    ),
    SettingsRowModel(
      title: 'Scan Machine',
      subtitle: 'Preview machine setup and movement guidance',
      icon: PhosphorIconsRegular.scan,
    ),
  ];
}

List<SettingsRowModel> _buildInsightRows(TargetPlatform platform) {
  return [
    const SettingsRowModel(
      title: 'Training Score',
      subtitle: 'Understand how your score is built and what moves it',
      icon: PhosphorIconsRegular.chartPieSlice,
    ),
    SettingsRowModel(
      title: 'Performance Trends',
      subtitle: 'Volume, strength, consistency, and machine output',
      mynauiAssetPath: MynauiGlyphs.courseUp,
    ),
    const SettingsRowModel(
      title: 'Recovery Insights',
      subtitle: 'Spot overload, readiness drops, and muscle fatigue',
      icon: PhosphorIconsRegular.waveform,
    ),
    SettingsRowModel(
      title: 'Data Sources',
      subtitle:
          'See how ${_healthPlatformLabel(platform)} and gym data feed your intelligence layer',
      icon: PhosphorIconsRegular.database,
    ),
  ];
}

List<SettingsRowModel> _buildRewardsRows(UserProfile profile) {
  if (profile.mode == UserMode.gymConnected) {
    return [
      const SettingsRowModel(
        title: 'Included in Membership',
        subtitle: 'Your plan already includes premium coaching tools',
        icon: PhosphorIconsRegular.sealCheck,
        highlighted: true,
      ),
      SettingsRowModel(
        title: 'Gym Benefits',
        subtitle: profile.gym?.benefitsLabel ?? 'Membership benefits and perks',
        icon: PhosphorIconsRegular.gift,
      ),
      const SettingsRowModel(
        title: 'Rewards & Referrals',
        subtitle: 'Earn perks, guest passes, and branded rewards',
        icon: PhosphorIconsRegular.confetti,
      ),
    ];
  }

  return [
    const SettingsRowModel(
      title: 'Upgrade to Pro',
      subtitle:
          'Unlock deeper trends, better score accuracy, and premium tools',
      icon: PhosphorIconsRegular.arrowCircleUpRight,
      highlighted: true,
    ),
    SettingsRowModel(
      title: 'Billing',
      subtitle:
          profile.plan.label == 'Free Plan'
              ? 'No active subscription'
              : 'Manage billing and plan renewal',
      icon: PhosphorIconsRegular.creditCard,
    ),
    const SettingsRowModel(
      title: 'Rewards & Referrals',
      subtitle: 'Earn rewards when training partners join the app',
      icon: PhosphorIconsRegular.confetti,
    ),
  ];
}

List<SettingsRowModel> _buildAccountRows() {
  return const [
    SettingsRowModel(
      title: 'Fitness Profile',
      subtitle: 'Goals, body metrics, and training level',
      icon: PhosphorIconsRegular.userFocus,
    ),
    SettingsRowModel(
      title: 'Notifications',
      subtitle: 'Session reminders, gym updates, and referral alerts',
      icon: PhosphorIconsRegular.bell,
    ),
    SettingsRowModel(
      title: 'Privacy',
      subtitle: 'Manage visibility, data sharing, and permissions',
      icon: PhosphorIconsRegular.lockKey,
    ),
    SettingsRowModel(
      title: 'Manage Account',
      subtitle: 'Email, password, export, and account controls',
      mynauiAssetPath: MynauiGlyphs.filter,
    ),
  ];
}
