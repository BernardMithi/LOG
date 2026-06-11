import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/articles/article_editor_screen.dart';
import 'package:lift/features/articles/articles_repository.dart';
import 'package:lift/features/articles/widgets/article_body_view.dart';
import 'package:lift/features/articles/widgets/article_image_view.dart';
import 'package:lift/shared/models/article.dart';
import 'package:lift/shared/widgets/lift_dialogs.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/lift_menu_sheet.dart';
import 'package:lift/shared/widgets/scroll_linked_top_blur_scrim.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/widgets/surfaces.dart';

const String _kArticlePlaceholderImage =
    'https://blocks.astratic.com/img/general-img-landscape.png';

enum _ArticleHeaderMenuAction { edit, archive }

class ArticleDetailScreen extends StatefulWidget {
  const ArticleDetailScreen({
    super.key,
    required this.articleId,
    required this.repository,
    required this.machineSuggestions,
    this.initialArticle,
    this.initialAuthors = const <String, ArticleAuthor>{},
  });

  final String articleId;
  final ArticlesRepository repository;
  final List<String> machineSuggestions;
  final Article? initialArticle;
  final Map<String, ArticleAuthor> initialAuthors;

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  Article? _article;
  Map<String, ArticleAuthor> _authors = const {};
  bool _isLoading = true;
  bool _bookmarked = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _bookmarked = widget.repository.isArticleSavedSync(widget.articleId);
    _article =
        widget.initialArticle ??
        widget.repository.peekArticleById(widget.articleId);
    _authors =
        widget.initialAuthors.isNotEmpty
            ? widget.initialAuthors
            : {
              for (final author
                  in widget.repository.peekAuthors() ?? const <ArticleAuthor>[])
                author.id: author,
            };
    _isLoading = _article == null;
    _loadBookmarkState();
    _load(showLoader: _article == null);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) {
      setState(() => _isLoading = true);
    }
    final article = await widget.repository.getArticleById(widget.articleId);
    final authors = await widget.repository.getAuthors();
    if (!mounted) return;
    setState(() {
      _article = article;
      _authors = {for (final author in authors) author.id: author};
      _isLoading = false;
    });
  }

  Future<void> _loadBookmarkState() async {
    final bookmarked = await widget.repository.isArticleSaved(widget.articleId);
    if (!mounted) return;
    setState(() => _bookmarked = bookmarked);
  }

  Future<void> _toggleBookmark() async {
    final bookmarked = await widget.repository.toggleArticleSaved(
      widget.articleId,
    );
    if (!mounted) return;
    setState(() => _bookmarked = bookmarked);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bookmarked ? 'Saved to bookmarks' : 'Removed from bookmarks',
        ),
        duration: kLiftSnackBarDuration,
      ),
    );
  }

  Future<void> _edit() async {
    final article = _article;
    if (article == null) return;
    final input = await Navigator.of(context).push<ArticleInput>(
      MaterialPageRoute(
        builder:
            (_) => ArticleEditorScreen(
              initialArticle: article,
              machineSuggestions: widget.machineSuggestions,
            ),
      ),
    );
    if (input == null) return;
    await widget.repository.updateArticle(existing: article, input: input);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Article updated')));
  }

  Future<void> _archive() async {
    final article = _article;
    if (article == null) return;
    final confirmed = await showLiftConfirmDialog(
      context: context,
      title: 'Archive article?',
      message: 'This will hide the article from member views.',
      confirmLabel: 'Archive',
      confirmColor: Colors.red.shade600,
    );
    if (confirmed != true) return;
    await widget.repository.archiveArticle(article);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _showHeaderActions() async {
    final article = _article;
    if (article == null) return;
    final canEdit = widget.repository.canEdit(article);
    final canArchive = widget.repository.canArchive(article);
    final action = await showModalBottomSheet<_ArticleHeaderMenuAction>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) {
        final tiles = <Widget>[];
        if (canEdit) {
          tiles.add(
            LiftMenuActionTile(
              icon: MynauiIcon(
                MynauiGlyphs.editOne,
                size: 22,
                color: kAccentColor,
              ),
              title: 'Edit article',
              onTap:
                  () => Navigator.of(
                    sheetContext,
                  ).pop(_ArticleHeaderMenuAction.edit),
            ),
          );
          if (canArchive) tiles.add(const SizedBox(height: 8));
        }
        if (canArchive) {
          tiles.add(
            LiftMenuActionTile(
              icon: MynauiIcon(
                MynauiGlyphs.trashBin,
                size: 22,
                color: Colors.red.shade600,
              ),
              title: 'Archive article',
              accent: Colors.red.shade600,
              onTap:
                  () => Navigator.of(
                    sheetContext,
                  ).pop(_ArticleHeaderMenuAction.archive),
            ),
          );
        }
        return SafeArea(
          top: false,
          bottom: false,
          child: LiftMenuSheet(
            title: 'Article options',
            subtitle: article.title,
            children: tiles,
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _ArticleHeaderMenuAction.edit:
        await _edit();
        break;
      case _ArticleHeaderMenuAction.archive:
        await _archive();
        break;
    }
  }

  Widget _chip(String value) {
    return FrostedControlSurface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      borderRadius: kIosChipRadius,
      backgroundColor: const Color(0xFFF1F3F5).withValues(alpha: 0.90),
      borderColor: Colors.black.withValues(alpha: 0.08),
      boxShadow: const [],
      child: Text(
        value.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade800,
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.42,
          height: 1.1,
        ),
      ),
    );
  }

  void _showShareToast() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Share coming soon')));
  }

  List<String> _heroLabelsFor(Article article) {
    final labels = <String>[];
    if (article.status == ArticleStatus.draft) {
      labels.add(article.status.label);
    }
    final primaryTopic =
        article.categories.isNotEmpty
            ? article.categories.first
            : article.tags.isNotEmpty
            ? article.tags.first
            : null;
    if (primaryTopic != null &&
        primaryTopic.trim().isNotEmpty &&
        !labels.contains(primaryTopic)) {
      labels.add(primaryTopic);
    }
    return labels.take(2).toList(growable: false);
  }

  List<String> _detailLabelsFor(Article article) {
    final labels = <String>[];
    void addLabel(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || labels.contains(trimmed)) return;
      labels.add(trimmed);
    }

    for (final tag in article.tags) {
      addLabel(tag);
    }
    for (final category in article.categories) {
      addLabel(category);
    }
    if (article.status == ArticleStatus.draft) {
      addLabel(article.status.label);
    }
    return labels;
  }

  List<String> _relatedLabelsFor(Article article) {
    final labels = <String>[];
    void addLabel(String prefix, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      labels.add('$prefix: $trimmed');
    }

    for (final machine in article.machineIds) {
      addLabel('Machine', machine);
    }
    for (final muscle in article.muscleGroups) {
      addLabel('Muscle', muscle);
    }
    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final article = _article;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: liftCanvasColor(context),
        body: const Center(
          child: CircularProgressIndicator(color: kAccentColor),
        ),
      );
    }
    if (article == null) {
      return Scaffold(
        backgroundColor: liftCanvasColor(context),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              16,
              kPagePadding,
              16,
            ),
            child: Column(
              children: [
                LiftIslandHeader(
                  center: const SizedBox.shrink(),
                  collapseOnScroll: false,
                  leading: LiftIslandHeaderAction(
                    onTap: () => Navigator.of(context).pop(),
                    child: const MynauiIcon(
                      MynauiGlyphs.altArrowLeft,
                      color: kLiftIslandOnFrosted,
                      size: 22,
                    ),
                  ),
                ),
                const Expanded(child: Center(child: Text('Article not found'))),
              ],
            ),
          ),
        ),
      );
    }
    final author = _authors[article.authorId];
    final canEdit = widget.repository.canEdit(article);
    final canArchive = widget.repository.canArchive(article);
    final publishedLabel = _dateLabel(article.publishedAt);
    final heroLabels = _heroLabelsFor(article);
    final detailLabels = _detailLabelsFor(article);
    final relatedLabels = _relatedLabelsFor(article);
    final topInset = MediaQuery.paddingOf(context).top;
    const islandTop = 16.0;
    final listTopPadding =
        topInset + islandTop + kLiftIslandHeaderHeight + kIslandHeaderGap;
    final topBlurBandHeight = listTopPadding + 88.0;

    return Scaffold(
      backgroundColor: liftCanvasColor(context),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const scrollBottomPadding = 28.0;
                  const heroToSheetGap = 34.0;
                  const heroAspectRatio = 0.94;
                  const sheetVerticalPadding = 38.0;

                  final contentWidth =
                      constraints.maxWidth - (kPagePadding * 2);
                  final heroHeight =
                      contentWidth > 0 ? contentWidth / heroAspectRatio : 0.0;
                  final sheetTargetHeight =
                      constraints.maxHeight -
                      listTopPadding -
                      scrollBottomPadding -
                      heroHeight -
                      heroToSheetGap;
                  final sheetContentMinHeight =
                      sheetTargetHeight > sheetVerticalPadding
                          ? sheetTargetHeight - sheetVerticalPadding
                          : 0.0;

                  return SingleChildScrollView(
                    controller: _scrollController,
                    primary: false,
                    padding: EdgeInsets.fromLTRB(
                      kPagePadding,
                      listTopPadding,
                      kPagePadding,
                      scrollBottomPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ArticleHeroBanner(
                          article: article,
                          labels: heroLabels,
                          bookmarked: _bookmarked,
                          onToggleBookmark: _toggleBookmark,
                          onShare: _showShareToast,
                        ),
                        const SizedBox(height: heroToSheetGap),
                        SectionBoundary(
                          borderRadius: kIosCornerRadius,
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: sheetContentMinHeight,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    FrostedControlSurface(
                                      padding: EdgeInsets.zero,
                                      borderRadius: 24,
                                      boxShadow: const [],
                                      backgroundColor: const Color(
                                        0xFFF1F3F5,
                                      ).withValues(alpha: 0.96),
                                      child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Center(
                                          child: Text(
                                            (author?.name ?? 'Lift')
                                                .substring(0, 1)
                                                .toUpperCase(),
                                            style: const TextStyle(
                                              color: kLiftIslandOnFrosted,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            author?.name ?? 'LIFT',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF171717),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${author?.roleLabel ?? 'Coach'} • $publishedLabel',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (article.summary.trim().isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  Text(
                                    article.summary,
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      height: 1.5,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                                if (detailLabels.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: detailLabels.map(_chip).toList(),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                ArticleBodyView(content: article.content),
                                if (relatedLabels.isNotEmpty) ...[
                                  const SizedBox(height: 22),
                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Theme.of(context).dividerTheme.color,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Related',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF171717),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: relatedLabels.map(_chip).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topBlurBandHeight,
              child: IgnorePointer(child: const _ArticleTopGradientBlurScrim()),
            ),
            Positioned(
              top: topInset + islandTop,
              left: kPagePadding,
              right: kPagePadding,
              child: LiftIslandHeader(
                center: const SizedBox.shrink(),
                scrollController: _scrollController,
                leading: LiftIslandHeaderAction(
                  onTap: () => Navigator.of(context).pop(),
                  child: const MynauiIcon(
                    MynauiGlyphs.altArrowLeft,
                    color: kLiftIslandOnFrosted,
                    size: 22,
                  ),
                ),
                trailing:
                    (canEdit || canArchive)
                        ? LiftIslandHeaderAction(
                          onTap: _showHeaderActions,
                          child: const MynauiIcon(
                            MynauiGlyphs.menuDotsCircle,
                            color: kLiftIslandOnFrosted,
                            size: 22,
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

  String _dateLabel(DateTime date) {
    final month =
        <String>[
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
        ][date.month - 1];
    return '${date.day} $month ${date.year}';
  }
}

class _ArticleTopGradientBlurScrim extends StatelessWidget {
  const _ArticleTopGradientBlurScrim();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: featherTopBlurMask,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: const ColoredBox(color: Color(0x00000000)),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.38),
                    Colors.white.withValues(alpha: 0.20),
                    Colors.white.withValues(alpha: 0.07),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.28, 0.58, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleHeroBanner extends StatelessWidget {
  const _ArticleHeroBanner({
    required this.article,
    required this.labels,
    required this.bookmarked,
    required this.onToggleBookmark,
    required this.onShare,
  });

  final Article article;
  final List<String> labels;
  final bool bookmarked;
  final VoidCallback onToggleBookmark;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    const heroRadius = 28.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(heroRadius),
          child: AspectRatio(
            aspectRatio: 0.94,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ArticleImageView(
                  imageRef: article.imageUrl,
                  placeholderUrl: _kArticlePlaceholderImage,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) => Container(
                        color: Colors.grey.shade300,
                        alignment: Alignment.center,
                        child: const MynauiIcon(
                          MynauiGlyphs.galleryMinimalistic,
                          size: 40,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.10),
                          Colors.black.withValues(alpha: 0.18),
                          Colors.black.withValues(alpha: 0.74),
                        ],
                        stops: const [0.0, 0.42, 1.0],
                      ),
                    ),
                  ),
                ),
                if (labels.isNotEmpty)
                  Positioned(
                    left: 18,
                    right: 18,
                    top: 20,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: labels
                          .map((label) => _HeroLabelPill(label: label))
                          .toList(growable: false),
                    ),
                  ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 22,
                  child: Text(
                    article.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.08,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 18,
          bottom: -26,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FloatingHeroActionButton(
                onTap: onToggleBookmark,
                active: bookmarked,
                child: MynauiIcon(
                  MynauiGlyphs.bookmark,
                  size: 25,
                  color: bookmarked ? Colors.white : const Color(0xFF111111),
                ),
              ),
              const SizedBox(width: 10),
              _FloatingHeroActionButton(
                onTap: onShare,
                child: MynauiIcon(
                  MynauiGlyphs.squareShareLine,
                  color: const Color(0xFF111111),
                  size: 25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroLabelPill extends StatelessWidget {
  const _HeroLabelPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return FrostedControlSurface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      borderRadius: kIosChipRadius,
      blur: 10,
      backgroundColor: Colors.white.withValues(alpha: 0.92),
      borderColor: Colors.white.withValues(alpha: 0.40),
      boxShadow: const [],
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF171717),
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.42,
          height: 1.1,
        ),
      ),
    );
  }
}

class _FloatingHeroActionButton extends StatelessWidget {
  const _FloatingHeroActionButton({
    required this.child,
    required this.onTap,
    this.active = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? const Color(0xFF171717) : Colors.white,
            border: Border.all(
              color:
                  active
                      ? Colors.black.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
