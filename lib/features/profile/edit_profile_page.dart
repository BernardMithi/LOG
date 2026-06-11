import 'package:flutter/material.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/profile/profile_models.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/widgets/lift_action_button.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/lift_pressable.dart';
import 'package:lift/shared/widgets/scroll_linked_top_blur_scrim.dart';

const Color _kEditProfileCanvas = Color(0xFFF7F7F8);
const Color _kEditProfileAccent = kAccentColor;
const Color _kEditProfileAccentSoft = Color(0xFFF1F3F5);
const Color _kEditProfileTextStrong = kAccentColor;
const Color _kEditProfileTextMuted = kAccentMid;
const Color _kEditProfileBorder = Color(0xFFE5E8EC);

Future<ProfileViewData?> pushEditProfilePage(
  BuildContext context, {
  required ProfileViewData initialData,
}) {
  return Navigator.of(context).push<ProfileViewData>(
    MaterialPageRoute<ProfileViewData>(
      builder: (_) => EditProfilePage(initialData: initialData),
    ),
  );
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.initialData});

  final ProfileViewData initialData;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _headlineController;
  late final TextEditingController _gymNameController;
  late final TextEditingController _gymDescriptionController;

  late ProfileMode _mode;
  late String _plan;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialData.user;
    _nameController = TextEditingController(text: profile.name);
    _usernameController = TextEditingController(text: profile.username);
    _headlineController = TextEditingController(text: profile.headline ?? '');
    _gymNameController = TextEditingController(text: profile.gymName ?? '');
    _gymDescriptionController = TextEditingController(
      text: profile.gymDescription ?? widget.initialData.gym?.description ?? '',
    );
    _mode = profile.mode;
    _plan = profile.plan;
    _nameController.addListener(_handleDraftChanged);
    _usernameController.addListener(_handleDraftChanged);
    _headlineController.addListener(_handleDraftChanged);
    _gymNameController.addListener(_handleDraftChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    _usernameController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    _headlineController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    _gymNameController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    _gymDescriptionController.dispose();
    super.dispose();
  }

  void _handleDraftChanged() => setState(() {});

  String get _previewName {
    final name = _nameController.text.trim();
    return name.isEmpty ? 'Your Name' : name;
  }

  String get _previewUsername {
    final raw = _usernameController.text.trim();
    if (raw.isEmpty) return '@username';
    return raw.startsWith('@') ? raw : '@$raw';
  }

  void _save() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final name = _nameController.text.trim();
    final username = _normalizeUsername(_usernameController.text);
    final headline = _headlineController.text.trim();
    final gymName = _gymNameController.text.trim();
    final gymDescription = _gymDescriptionController.text.trim();

    final nextUser = widget.initialData.user.copyWith(
      name: name,
      username: username,
      mode: _mode,
      plan: _plan,
      headline: headline.isEmpty ? null : headline,
      clearHeadline: headline.isEmpty,
      gymName: _mode == ProfileMode.gym ? gymName : null,
      clearGymName: _mode != ProfileMode.gym,
      gymDescription:
          _mode == ProfileMode.gym
              ? (gymDescription.isEmpty ? null : gymDescription)
              : null,
      clearGymDescription: _mode != ProfileMode.gym || gymDescription.isEmpty,
    );

    GymSummary? nextGym;
    if (_mode == ProfileMode.gym) {
      final fallbackDescription =
          gymDescription.isEmpty
              ? 'Membership-linked gym profile for training, recovery, and access perks.'
              : gymDescription;
      nextGym =
          widget.initialData.gym?.copyWith(
            name: gymName,
            description: fallbackDescription,
          ) ??
          GymSummary(name: gymName, description: fallbackDescription);
    }

    Navigator.of(context).pop<ProfileViewData>(
      widget.initialData.copyWith(
        user: nextUser,
        gym: nextGym,
        clearGym: _mode != ProfileMode.gym,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final tokens = _EditProfileTokens.forPlatform(platform);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const islandTop = 16.0;
    final listTopPadding =
        topInset + islandTop + kLiftIslandHeaderHeight + kIslandHeaderGap;
    final topBlurBandHeight = listTopPadding + 88.0;

    return Scaffold(
      backgroundColor: liftCanvasColor(context, light: _kEditProfileCanvas),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    kPagePadding,
                    listTopPadding,
                    kPagePadding,
                    bottomInset + 28,
                  ),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _EditProfilePreviewCard(
                              name: _previewName,
                              username: _previewUsername,
                              plan: _plan,
                              mode: _mode,
                              gymName: _gymNameController.text.trim(),
                              headline: _headlineController.text.trim(),
                              tokens: tokens,
                            ),
                            SizedBox(height: tokens.sectionGap),
                            _EditCard(
                              tokens: tokens,
                              title: 'Identity',
                              subtitle:
                                  'Update the public identity that appears across your training profile.',
                              child: Column(
                                children: [
                                  _LabeledField(
                                    label: 'Full name',
                                    child: TextFormField(
                                      controller: _nameController,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      decoration: _fieldDecoration(
                                        hintText: 'Enter your name',
                                      ),
                                      validator: (value) {
                                        if ((value ?? '').trim().isEmpty) {
                                          return 'Full name is required.';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  SizedBox(height: tokens.itemGap),
                                  _LabeledField(
                                    label: 'Username',
                                    child: TextFormField(
                                      controller: _usernameController,
                                      autocorrect: false,
                                      decoration: _fieldDecoration(
                                        hintText: '@username',
                                      ),
                                      validator: (value) {
                                        final normalized = _normalizeUsername(
                                          value ?? '',
                                        );
                                        if (normalized == '@') {
                                          return 'Username is required.';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  SizedBox(height: tokens.itemGap),
                                  _LabeledField(
                                    label: 'Headline',
                                    child: TextFormField(
                                      controller: _headlineController,
                                      maxLines: 3,
                                      minLines: 3,
                                      decoration: _fieldDecoration(
                                        hintText:
                                            'Write a short line about your current training focus.',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: tokens.sectionGap),
                            _EditCard(
                              tokens: tokens,
                              title: 'Membership',
                              subtitle:
                                  'Set how your profile reflects gym affiliation and plan status.',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Training mode',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _kEditProfileTextStrong,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  _EditSegmentedControl<ProfileMode>(
                                    value: _mode,
                                    options:
                                        const <_EditSegmentOption<ProfileMode>>[
                                          _EditSegmentOption(
                                            value: ProfileMode.gym,
                                            label: 'Gym',
                                          ),
                                          _EditSegmentOption(
                                            value: ProfileMode.independent,
                                            label: 'Independent',
                                          ),
                                        ],
                                    onChanged: (value) {
                                      setState(() => _mode = value);
                                    },
                                  ),
                                  SizedBox(height: tokens.itemGap),
                                  const Text(
                                    'Plan status',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _kEditProfileTextStrong,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  _EditSegmentedControl<String>(
                                    value: _plan,
                                    options: const <_EditSegmentOption<String>>[
                                      _EditSegmentOption(
                                        value: 'Included in membership',
                                        label: 'Membership',
                                      ),
                                      _EditSegmentOption(
                                        value: 'Pro Plan',
                                        label: 'Pro Plan',
                                      ),
                                    ],
                                    onChanged: (value) {
                                      setState(() => _plan = value);
                                    },
                                  ),
                                  if (_mode == ProfileMode.gym) ...[
                                    SizedBox(height: tokens.itemGap),
                                    _LabeledField(
                                      label: 'Gym name',
                                      child: TextFormField(
                                        controller: _gymNameController,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        decoration: _fieldDecoration(
                                          hintText: 'Enter gym name',
                                        ),
                                        validator: (value) {
                                          if (_mode != ProfileMode.gym) {
                                            return null;
                                          }
                                          if ((value ?? '').trim().isEmpty) {
                                            return 'Gym name is required for gym mode.';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    SizedBox(height: tokens.itemGap),
                                    _LabeledField(
                                      label: 'Gym description',
                                      child: TextFormField(
                                        controller: _gymDescriptionController,
                                        maxLines: 3,
                                        minLines: 3,
                                        textCapitalization:
                                            TextCapitalization.sentences,
                                        decoration: _fieldDecoration(
                                          hintText:
                                              'Add a short line about the gym, equipment, or membership benefits.',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            SizedBox(height: tokens.sectionGap),
                            SizedBox(
                              height: 48,
                              child: LiftActionButton(
                                label: 'Save Changes',
                                color: _kEditProfileAccent,
                                solid: true,
                                onTap: _save,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
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
                  topTint: _kEditProfileCanvas,
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
                title: 'Edit Profile',
                leading: LiftIslandHeaderAction(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const MynauiIcon(
                    MynauiGlyphs.altArrowLeft,
                    color: kLiftIslandOnFrosted,
                    size: 22,
                  ),
                ),
                trailing: LiftIslandHeaderAction(
                  onTap: _save,
                  child: const MynauiIcon(
                    MynauiGlyphs.checkCircle,
                    color: kLiftIslandOnFrosted,
                    size: 28,
                    semanticLabel: 'Save',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfilePreviewCard extends StatelessWidget {
  const _EditProfilePreviewCard({
    required this.name,
    required this.username,
    required this.plan,
    required this.mode,
    required this.gymName,
    required this.headline,
    required this.tokens,
  });

  final String name;
  final String username;
  final String plan;
  final ProfileMode mode;
  final String gymName;
  final String headline;
  final _EditProfileTokens tokens;

  @override
  Widget build(BuildContext context) {
    final gymLabel =
        mode == ProfileMode.gym
            ? 'Member at ${gymName.isEmpty ? 'Gym' : gymName}'
            : 'Independent';
    return _EditCard(
      tokens: tokens,
      title: 'Preview',
      subtitle: 'This is how your identity card will read in the app.',
      accented: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EditAvatar(name: name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: _kEditProfileTextStrong,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  username,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kEditProfileTextMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PreviewChip(label: gymLabel, accent: true),
                    _PreviewChip(label: plan),
                  ],
                ),
                if (headline.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    headline,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.42,
                      fontWeight: FontWeight.w500,
                      color: _kEditProfileTextMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditCard extends StatelessWidget {
  const _EditCard({
    required this.tokens,
    required this.title,
    required this.subtitle,
    required this.child,
    this.accented = false,
  });

  final _EditProfileTokens tokens;
  final String title;
  final String subtitle;
  final Widget child;
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
            border: Border.all(color: _kEditProfileBorder),
          ),
          child: Stack(
            children: [
              if (accented)
                Positioned(
                  right: -24,
                  top: -38,
                  child: IgnorePointer(
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _kEditProfileAccent.withValues(alpha: 0.10),
                            _kEditProfileAccent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _kEditProfileTextStrong,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.42,
                        fontWeight: FontWeight.w500,
                        color: _kEditProfileTextMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    child,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _kEditProfileTextStrong,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _EditSegmentedControl<T> extends StatelessWidget {
  const _EditSegmentedControl({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<_EditSegmentOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kEditProfileBorder),
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
                          option.value == value
                              ? _kEditProfileAccent.withValues(alpha: 0.10)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              option.value == value
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                          color:
                              option.value == value
                                  ? _kEditProfileAccent
                                  : _kEditProfileTextMuted,
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

class _EditSegmentOption<T> {
  const _EditSegmentOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _EditAvatar extends StatelessWidget {
  const _EditAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F9FA), Color(0xFFE3EAEE)],
        ),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      alignment: Alignment.center,
      child: Text(
        _initialsFor(name),
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: _kEditProfileTextStrong,
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color:
            accent
                ? _kEditProfileAccentSoft.withValues(alpha: 0.92)
                : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              accent
                  ? _kEditProfileAccent.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: accent ? _kEditProfileAccent : _kEditProfileTextStrong,
        ),
      ),
    );
  }
}

class _EditProfileTokens {
  const _EditProfileTokens({
    required this.isApple,
    required this.sectionGap,
    required this.itemGap,
    required this.cardRadius,
  });

  final bool isApple;
  final double sectionGap;
  final double itemGap;
  final double cardRadius;

  factory _EditProfileTokens.forPlatform(TargetPlatform platform) {
    final isApple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    return _EditProfileTokens(
      isApple: isApple,
      sectionGap: isApple ? 16 : 14,
      itemGap: isApple ? 14 : 12,
      cardRadius: isApple ? 24 : 22,
    );
  }
}

InputDecoration _fieldDecoration({required String hintText}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(
      color: _kEditProfileTextMuted.withValues(alpha: 0.72),
      fontWeight: FontWeight.w500,
    ),
    filled: true,
    fillColor: _kEditProfileAccentSoft.withValues(alpha: 0.55),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: _kEditProfileAccent.withValues(alpha: 0.34),
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.red.shade400),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.red.shade500),
    ),
  );
}

String _normalizeUsername(String input) {
  final trimmed = input.trim().replaceAll(' ', '');
  if (trimmed.isEmpty) return '@';
  return trimmed.startsWith('@') ? trimmed : '@$trimmed';
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
