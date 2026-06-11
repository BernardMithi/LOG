import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/articles/widgets/article_body_view.dart';
import 'package:lift/features/articles/widgets/article_embed_view.dart';
import 'package:lift/features/articles/widgets/article_image_view.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lift/shared/models/article.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/widgets/lift_dialogs.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/lift_menu_sheet.dart';
import 'package:lift/shared/widgets/surfaces.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fs.XTypeGroup _kImportTextTypeGroup = fs.XTypeGroup(
  label: 'Text documents',
  extensions: <String>['txt', 'md'],
);

enum _EditorSurfaceTab { write, preview }

class _ArticleTemplatePreset {
  const _ArticleTemplatePreset({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.content,
    this.suggestedTitle,
    this.suggestedSummary,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String content;
  final String? suggestedTitle;
  final String? suggestedSummary;
}

const List<_ArticleTemplatePreset> _kArticleTemplatePresets = [
  _ArticleTemplatePreset(
    title: 'Technique guide',
    subtitle: 'Break down movement setup, execution, and common mistakes.',
    icon: Icons.fitness_center_rounded,
    accent: kAccentColor,
    suggestedTitle: 'How to improve your lift',
    suggestedSummary:
        'Teach members how to perform a movement safely and well.',
    content:
        '# What this covers\n\nAdd a short opener explaining what members will learn and why it matters.\n\n## Setup\n\n- Who this movement is for\n- Equipment needed\n- Safety notes\n\n## Step-by-step\n\n1. Starting position\n2. Main action\n3. Finish and reset\n\n## Common mistakes\n\n- Mistake one\n- Mistake two\n\n## Coaching cues\n\n> Add 2 or 3 short cues members can remember quickly.\n\n## Takeaway\n\nClose with the main point members should keep in mind.',
  ),
  _ArticleTemplatePreset(
    title: 'Recovery explainer',
    subtitle: 'Turn a coaching note into a structured recovery article.',
    icon: Icons.self_improvement_rounded,
    accent: Color(0xFF0A7A6B),
    suggestedTitle: 'How to recover better between sessions',
    suggestedSummary: 'Help members understand recovery habits and timing.',
    content:
        '# Why recovery matters\n\nExplain the problem this article solves.\n\n## Signs to watch\n\n- Soreness pattern\n- Fatigue pattern\n- Performance drop\n\n## What to do today\n\n1. Immediate action\n2. Recovery habit\n3. When to train again\n\n## When to scale back\n\n> Add a simple rule members can apply without overthinking it.\n\n## Final note\n\nEnd with the one habit that gives the biggest return.',
  ),
  _ArticleTemplatePreset(
    title: 'Workout plan',
    subtitle: 'Outline a full session with intent, structure, and finish.',
    icon: Icons.route_rounded,
    accent: Color(0xFF7A2E8A),
    suggestedTitle: 'Build a balanced workout plan',
    suggestedSummary: 'Explain the goal of the session and how to progress it.',
    content:
        '# Session goal\n\nState what the workout is meant to improve.\n\n## Warm-up\n\n- Movement prep\n- Ramp-up sets\n\n## Main work\n\n1. Primary exercise\n2. Secondary exercise\n3. Accessory block\n\n## Rest and pacing\n\nAdd guidance on rest periods and how hard each block should feel.\n\n## Progression\n\n- How to increase load\n- When to repeat the session\n\n## Wrap-up\n\nTell members what success looks like for this session.',
  ),
  _ArticleTemplatePreset(
    title: 'Machine guide',
    subtitle: 'Write a concise machine walkthrough for gym members.',
    icon: Icons.precision_manufacturing_rounded,
    accent: Color(0xFF2563EB),
    suggestedTitle: 'How to use this machine',
    suggestedSummary:
        'Show members how to set up the machine and avoid common errors.',
    content:
        '# Purpose\n\nExplain what the machine trains and who should use it.\n\n## Setup\n\n- Seat or pad adjustment\n- Grip or foot position\n- Starting weight\n\n## How to use it\n\n1. Get into position\n2. Move through the full rep\n3. Return under control\n\n## Avoid these mistakes\n\n- Rushing the movement\n- Using too much load\n\n## Best pairings\n\nSuggest when this machine fits into a workout.',
  ),
];

class ArticleEditorScreen extends StatefulWidget {
  const ArticleEditorScreen({
    super.key,
    this.initialArticle,
    required this.machineSuggestions,
  });

  final Article? initialArticle;
  final List<String> machineSuggestions;

  bool get isEditing => initialArticle != null;

  @override
  State<ArticleEditorScreen> createState() => _ArticleEditorScreenState();
}

class _ArticleEditorScreenState extends State<ArticleEditorScreen> {
  static const String _editorDraftStoragePrefix =
      'lift_article_editor_draft_v1';
  late final TextEditingController _titleController;
  late final TextEditingController _summaryController;
  late final TextEditingController _contentController;
  late final TextEditingController _imageController;
  late final TextEditingController _tagsController;
  late final TextEditingController _musclesController;
  late final TextEditingController _categoriesController;
  late final TextEditingController _machinesController;
  final FocusNode _contentFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  late ArticleStatus _status;
  _EditorSurfaceTab _editorTab = _EditorSurfaceTab.write;
  Timer? _autosaveDebounce;

  @override
  void initState() {
    super.initState();
    final article = widget.initialArticle;
    _titleController = TextEditingController(text: article?.title ?? '');
    _summaryController = TextEditingController(text: article?.summary ?? '');
    _contentController = TextEditingController(text: article?.content ?? '');
    _imageController = TextEditingController(text: article?.imageUrl ?? '');
    _tagsController = TextEditingController(text: _join(article?.tags));
    _musclesController = TextEditingController(
      text: _join(article?.muscleGroups),
    );
    _categoriesController = TextEditingController(
      text: _join(article?.categories),
    );
    _machinesController = TextEditingController(
      text: _join(article?.machineIds),
    );
    _status = article?.status ?? ArticleStatus.draft;

    _titleController.addListener(_handleEditorChange);
    _summaryController.addListener(_handleEditorChange);
    _contentController.addListener(_handleEditorChange);
    _imageController.addListener(_handleEditorChange);
    _tagsController.addListener(_handleEditorChange);
    _musclesController.addListener(_handleEditorChange);
    _categoriesController.addListener(_handleEditorChange);
    _machinesController.addListener(_handleEditorChange);
    _restoreDraft();
  }

  String _join(List<String>? items) => items == null ? '' : items.join(', ');

  void _handleEditorChange() {
    if (!mounted) return;
    _scheduleDraftSave();
    setState(() {});
  }

  String get _draftStorageKey {
    final articleId = widget.initialArticle?.id ?? 'new';
    return '$_editorDraftStoragePrefix:$articleId';
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftStorageKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final draft = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final draftSavedAt = DateTime.tryParse(
        (draft['savedAt'] as String?) ?? '',
      );
      final articleUpdatedAt = widget.initialArticle?.updatedAt;
      if (draftSavedAt != null &&
          articleUpdatedAt != null &&
          !draftSavedAt.isAfter(articleUpdatedAt)) {
        return;
      }

      void restoreText(TextEditingController controller, String key) {
        final value = draft[key];
        if (value is String) controller.text = value;
      }

      restoreText(_titleController, 'title');
      restoreText(_summaryController, 'summary');
      restoreText(_contentController, 'content');
      restoreText(_imageController, 'imageUrl');
      restoreText(_tagsController, 'tags');
      restoreText(_musclesController, 'muscles');
      restoreText(_categoriesController, 'categories');
      restoreText(_machinesController, 'machines');

      final statusRaw = draft['status'];
      if (statusRaw is String && statusRaw.trim().isNotEmpty) {
        _status = ArticleStatusX.fromWire(statusRaw);
      }
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      // Ignore malformed local draft data.
    }
  }

  void _scheduleDraftSave() {
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 280), _persistDraft);
  }

  Future<void> _persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, String>{
        'title': _titleController.text,
        'summary': _summaryController.text,
        'content': _contentController.text,
        'imageUrl': _imageController.text,
        'tags': _tagsController.text,
        'muscles': _musclesController.text,
        'categories': _categoriesController.text,
        'machines': _machinesController.text,
        'status': _status.wireValue,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_draftStorageKey, jsonEncode(payload));
    } catch (_) {
      // Non-fatal draft persistence failure.
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftStorageKey);
    } catch (_) {
      // Non-fatal draft cleanup failure.
    }
  }

  List<String> _parseCsv(String raw) {
    return raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  int _countWords(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return 0;
    return RegExp(r'\S+').allMatches(normalized).length;
  }

  int get _wordCount => _countWords(_contentController.text);

  int get _characterCount => _contentController.text.trim().length;

  int get _estimatedReadMinutes {
    if (_wordCount == 0) return 0;
    return math.max(1, (_wordCount / 180).ceil());
  }

  bool get _canSave {
    return _titleController.text.trim().isNotEmpty &&
        _summaryController.text.trim().isNotEmpty &&
        _contentController.text.trim().isNotEmpty;
  }

  String get _editorTitle => 'Article studio';

  void _submit() {
    final title = _titleController.text.trim();
    final summary = _summaryController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || summary.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Title, summary, and content are required.'),
        ),
      );
      return;
    }
    _autosaveDebounce?.cancel();
    unawaited(_clearDraft());
    Navigator.of(context).pop(
      ArticleInput(
        title: title,
        summary: summary,
        content: content,
        imageUrl: _imageController.text.trim(),
        tags: _parseCsv(_tagsController.text),
        machineIds: _parseCsv(_machinesController.text),
        muscleGroups: _parseCsv(_musclesController.text),
        categories: _parseCsv(_categoriesController.text),
        status: _status,
      ),
    );
  }

  String _normalizeImportedText(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\t', ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _plainTextLine(String raw) {
    return raw
        .trim()
        .replaceFirst(RegExp(r'^(#+\s*|>\s*|-\s+|\d+\.\s+)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _applyImportedText(String raw, {required String sourceLabel}) {
    final normalized = _normalizeImportedText(raw);
    if (normalized.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No usable text found to import.')),
      );
      return;
    }

    final blocks = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: true);

    String? inferredTitle;
    String? inferredSummary;

    if (_titleController.text.trim().isEmpty && blocks.isNotEmpty) {
      final candidate = _plainTextLine(blocks.first);
      if (candidate.isNotEmpty && candidate.length <= 90) {
        inferredTitle = candidate;
        blocks.removeAt(0);
      }
    }

    if (_summaryController.text.trim().isEmpty && blocks.isNotEmpty) {
      final candidate =
          blocks.first
              .replaceAll('\n', ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
      if (candidate.isNotEmpty) {
        inferredSummary =
            candidate.length > 180
                ? '${candidate.substring(0, 177).trimRight()}...'
                : candidate;
        blocks.removeAt(0);
      }
    }

    final importedBody = blocks.isEmpty ? normalized : blocks.join('\n\n');
    final currentContent = _contentController.text.trim();
    final nextContent =
        currentContent.isEmpty
            ? importedBody
            : '$currentContent\n\n$importedBody';

    setState(() {
      if (inferredTitle != null) {
        _titleController.text = inferredTitle;
      }
      if (inferredSummary != null) {
        _summaryController.text = inferredSummary;
      }
      _contentController.text = nextContent;
      _contentController.selection = TextSelection.collapsed(
        offset: _contentController.text.length,
      );
      _editorTab = _EditorSurfaceTab.write;
    });

    _contentFocusNode.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Imported ${_countWords(importedBody)} words from $sourceLabel.',
        ),
      ),
    );
  }

  Future<void> _importFromClipboard() async {
    Navigator.of(context).pop();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text ?? '';
    if (!mounted) return;
    _applyImportedText(raw, sourceLabel: 'clipboard');
  }

  Future<void> _importFromDocument() async {
    Navigator.of(context).pop();
    final file = await fs.openFile(
      acceptedTypeGroups: <fs.XTypeGroup>[_kImportTextTypeGroup],
    );
    if (file == null || !mounted) return;
    try {
      final raw = await file.readAsString();
      if (!mounted) return;
      _applyImportedText(raw, sourceLabel: file.name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to read that file. Import .txt or .md documents.',
          ),
        ),
      );
    }
  }

  Future<void> _showImportSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          bottom: false,
          child: LiftMenuSheet(
            title: 'Import content',
            subtitle: 'Bring text in from your clipboard or a text document.',
            children: [
              LiftMenuActionTile(
                icon: const Icon(Icons.content_paste_rounded),
                title: 'Paste from clipboard',
                subtitle: 'Import copied text into the editor',
                onTap: _importFromClipboard,
              ),
              const SizedBox(height: 8),
              LiftMenuActionTile(
                icon: const Icon(Icons.upload_file_rounded),
                title: 'Import text document',
                subtitle: 'Reads .txt and .md files into the article body',
                onTap: _importFromDocument,
              ),
            ],
          ),
        );
      },
    );
  }

  void _insertPreset(_ArticleTemplatePreset preset) {
    Navigator.of(context).pop();
    final existing = _contentController.text.trim();
    final nextContent =
        existing.isEmpty ? preset.content : '$existing\n\n${preset.content}';

    setState(() {
      if (_titleController.text.trim().isEmpty &&
          preset.suggestedTitle != null) {
        _titleController.text = preset.suggestedTitle!;
      }
      if (_summaryController.text.trim().isEmpty &&
          preset.suggestedSummary != null) {
        _summaryController.text = preset.suggestedSummary!;
      }
      _contentController.text = nextContent;
      _contentController.selection = TextSelection.collapsed(
        offset: _contentController.text.length,
      );
      _editorTab = _EditorSurfaceTab.write;
    });

    _contentFocusNode.requestFocus();
  }

  Future<void> _showStructureSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          bottom: false,
          child: LiftMenuSheet(
            title: 'Insert structure',
            subtitle:
                'Start from a reusable article outline instead of a blank page.',
            children: [
              for (var i = 0; i < _kArticleTemplatePresets.length; i++) ...[
                LiftMenuActionTile(
                  icon: Icon(_kArticleTemplatePresets[i].icon),
                  title: _kArticleTemplatePresets[i].title,
                  subtitle: _kArticleTemplatePresets[i].subtitle,
                  accent: _kArticleTemplatePresets[i].accent,
                  onTap: () => _insertPreset(_kArticleTemplatePresets[i]),
                ),
                if (i < _kArticleTemplatePresets.length - 1)
                  const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }

  void _replaceContentSelection(String replacement) {
    final value = _contentController.value;
    final selection =
        value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final nextText = value.text.replaceRange(start, end, replacement);
    final nextOffset = start + replacement.length;
    _contentController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    _contentFocusNode.requestFocus();
  }

  void _wrapSelection(
    String prefix,
    String suffix, {
    required String placeholder,
  }) {
    final value = _contentController.value;
    final selection =
        value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final selected = value.text.substring(start, end);
    final inner = selected.isEmpty ? placeholder : selected;
    _replaceContentSelection('$prefix$inner$suffix');
  }

  void _insertBlock(String block) {
    final value = _contentController.value;
    final selection =
        value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final before = value.text.substring(0, start);
    final after = value.text.substring(end);

    final leading =
        before.isEmpty
            ? ''
            : before.endsWith('\n\n')
            ? ''
            : before.endsWith('\n')
            ? '\n'
            : '\n\n';
    final trailing =
        after.isEmpty
            ? ''
            : after.startsWith('\n\n')
            ? ''
            : after.startsWith('\n')
            ? '\n'
            : '\n\n';

    _replaceContentSelection('$leading$block$trailing');
  }

  void _insertEmbed(String rawUrl) {
    final embed = ArticleEmbedData.tryParse(rawUrl);
    if (embed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Paste a valid YouTube link or Instagram post / reel URL.',
          ),
        ),
      );
      return;
    }

    _insertBlock('!embed ${embed.sourceUrl}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${embed.label} added to the article.')),
    );
  }

  String? _normalizeImageReference(String raw) {
    return normalizeArticleImageReference(raw);
  }

  String _sanitizeImageStem(String rawName) {
    final dotIndex = rawName.lastIndexOf('.');
    final baseName = dotIndex <= 0 ? rawName : rawName.substring(0, dotIndex);
    final sanitized = baseName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? 'article_image' : sanitized;
  }

  String _safeImageExtension(String rawName) {
    final dotIndex = rawName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == rawName.length - 1) {
      return '.jpg';
    }
    final extension = rawName.substring(dotIndex).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)) {
      return '.jpg';
    }
    return extension;
  }

  Future<String?> _copyPickedImageToArticleStorage(XFile pickedFile) async {
    final sourceFile = File(pickedFile.path);
    if (!await sourceFile.exists()) return null;

    final appDir = await getApplicationSupportDirectory();
    final imageDir = Directory('${appDir.path}/article_images');
    await imageDir.create(recursive: true);

    final extension = _safeImageExtension(pickedFile.name);
    final stem = _sanitizeImageStem(pickedFile.name);
    final targetPath =
        '${imageDir.path}/${DateTime.now().microsecondsSinceEpoch}_$stem$extension';

    await sourceFile.copy(targetPath);
    return targetPath;
  }

  Future<String?> _pickImageFromPhone() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 92,
      );
      if (pickedFile == null) return null;
      final storedPath = await _copyPickedImageToArticleStorage(pickedFile);
      if (storedPath == null) {
        throw StateError('Unable to store image');
      }
      return storedPath;
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open your photo library. Check photo access and try again.',
          ),
        ),
      );
      return null;
    }
  }

  void _insertImageReference(String raw) {
    final imageRef = _normalizeImageReference(raw);
    if (imageRef == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid image URL or choose an image from your phone.',
          ),
        ),
      );
      return;
    }
    _insertBlock('!image $imageRef');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Image added to the article body.')),
    );
  }

  Future<void> _pickHeaderImageFromPhone() async {
    final imageRef = await _pickImageFromPhone();
    if (!mounted || imageRef == null) return;
    _imageController.text = imageRef;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Header image selected from your phone.')),
    );
  }

  Future<void> _showImageSheet() async {
    final controller = TextEditingController();
    var errorText = '';

    Future<void> pasteFromClipboard(StateSetter setSheetState) async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final pasted = data?.text?.trim() ?? '';
      if (pasted.isEmpty) return;
      setSheetState(() {
        controller.text = pasted;
        errorText = '';
      });
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void submit() {
              final raw = controller.text.trim();
              if (_normalizeImageReference(raw) == null) {
                setSheetState(() {
                  errorText = 'Use a full image URL or choose from your phone.';
                });
                return;
              }
              Navigator.of(sheetContext).pop();
              _insertImageReference(raw);
            }

            Future<void> chooseFromPhone() async {
              Navigator.of(sheetContext).pop();
              final imageRef = await _pickImageFromPhone();
              if (!mounted || imageRef == null) return;
              _insertImageReference(imageRef);
            }

            return SafeArea(
              top: false,
              bottom: false,
              child: LiftMenuSheet(
                title: 'Insert image',
                subtitle:
                    'Paste a direct image link or choose a photo from your phone. '
                    'It appears full-width in the article and preview.',
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: _inputDecoration(
                      hint: 'https://example.com/photo.jpg',
                    ).copyWith(errorText: errorText.isEmpty ? null : errorText),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _EmbedExampleChip(label: 'Hero image'),
                      _EmbedExampleChip(label: 'Diagram'),
                      _EmbedExampleChip(label: 'Exercise photo'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: chooseFromPhone,
                      icon: const MynauiIcon(
                        MynauiGlyphs.galleryMinimalistic,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text('Choose from phone'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pasteFromClipboard(setSheetState),
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 18,
                          ),
                          label: const Text('Paste'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: submit,
                          icon: const MynauiIcon(
                            MynauiGlyphs.galleryMinimalistic,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text('Use link'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEmbedSheet() async {
    final controller = TextEditingController();
    var errorText = '';

    Future<void> pasteFromClipboard(StateSetter setSheetState) async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final pasted = data?.text?.trim() ?? '';
      if (pasted.isEmpty) return;
      setSheetState(() {
        controller.text = pasted;
        errorText = '';
      });
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void submit() {
              final raw = controller.text.trim();
              final embed = ArticleEmbedData.tryParse(raw);
              if (embed == null) {
                setSheetState(() {
                  errorText =
                      'Use a YouTube link or an Instagram post / reel URL.';
                });
                return;
              }
              Navigator.of(sheetContext).pop();
              _insertEmbed(embed.sourceUrl);
            }

            return SafeArea(
              top: false,
              bottom: false,
              child: LiftMenuSheet(
                title: 'Embed content',
                subtitle:
                    'Paste a YouTube video or Instagram post / reel link.',
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: _inputDecoration(
                      hint:
                          'https://youtube.com/... or https://instagram.com/...',
                    ).copyWith(errorText: errorText.isEmpty ? null : errorText),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _EmbedExampleChip(label: 'YouTube video'),
                      _EmbedExampleChip(label: 'Instagram post'),
                      _EmbedExampleChip(label: 'Instagram reel'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pasteFromClipboard(setSheetState),
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 18,
                          ),
                          label: const Text('Paste'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: submit,
                          icon: const Icon(Icons.add_link_rounded, size: 18),
                          label: const Text('Insert embed'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _fillSummaryFromIntro() {
    final normalized = _normalizeImportedText(_contentController.text);
    if (normalized.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Write some content before generating a summary.'),
        ),
      );
      return;
    }

    final firstBlock =
        normalized
            .split(RegExp(r'\n\s*\n'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .first;
    final cleaned =
        firstBlock
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceFirst(RegExp(r'^#+\s*'), '')
            .trim();

    if (cleaned.isEmpty) return;

    setState(() {
      _summaryController.text =
          cleaned.length > 180
              ? '${cleaned.substring(0, 177).trimRight()}...'
              : cleaned;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Summary filled from the opening section.')),
    );
  }

  Future<void> _clearContent() async {
    if (_contentController.text.trim().isEmpty) return;
    final confirmed = await showLiftConfirmDialog(
      context: context,
      title: 'Clear article body?',
      message: 'This removes the current content from the editor.',
      confirmLabel: 'Clear',
      confirmColor: Colors.red.shade600,
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _contentController.clear();
      _editorTab = _EditorSurfaceTab.write;
    });
  }

  void _appendCsvValue(TextEditingController controller, String value) {
    final items = _parseCsv(controller.text);
    if (items.contains(value)) return;
    items.add(value);
    items.sort();
    setState(() => controller.text = items.join(', '));
  }

  @override
  void dispose() {
    _autosaveDebounce?.cancel();
    unawaited(_persistDraft());
    _titleController.removeListener(_handleEditorChange);
    _summaryController.removeListener(_handleEditorChange);
    _contentController.removeListener(_handleEditorChange);
    _imageController.removeListener(_handleEditorChange);
    _tagsController.removeListener(_handleEditorChange);
    _musclesController.removeListener(_handleEditorChange);
    _categoriesController.removeListener(_handleEditorChange);
    _machinesController.removeListener(_handleEditorChange);
    _titleController.dispose();
    _summaryController.dispose();
    _contentController.dispose();
    _imageController.dispose();
    _tagsController.dispose();
    _musclesController.dispose();
    _categoriesController.dispose();
    _machinesController.dispose();
    _contentFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kIosCornerRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        borderSide: const BorderSide(color: kAccentColor, width: 1.4),
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    required String hint,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            style: const TextStyle(fontSize: 14, height: 1.35),
            decoration: _inputDecoration(hint: hint),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicsSection() {
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Basics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            'Set the title and summary first so the article has a clear hook.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _labeledField(
            label: 'Title',
            controller: _titleController,
            hint: 'What should members learn here?',
          ),
          _labeledField(
            label: 'Summary',
            controller: _summaryController,
            hint: 'A short preview that sells the article in one or two lines.',
            minLines: 2,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildContentToolbar() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _EditorToolChip(
          iconBuilder:
              (accent) => Icon(Icons.import_export_rounded, color: accent),
          label: 'Import',
          onTap: _showImportSheet,
        ),
        _EditorToolChip(
          iconBuilder:
              (accent) => Icon(Icons.view_quilt_rounded, color: accent),
          label: 'Template',
          onTap: _showStructureSheet,
        ),
        _EditorToolChip(
          iconBuilder:
              (accent) => Icon(Icons.short_text_rounded, color: accent),
          label: 'Use intro for summary',
          onTap: _fillSummaryFromIntro,
        ),
        _EditorToolChip(
          iconBuilder: (accent) => Icon(Icons.title_rounded, color: accent),
          label: 'H1',
          onTap: () => _insertBlock('# Heading'),
        ),
        _EditorToolChip(
          iconBuilder: (accent) => Icon(Icons.subtitles_rounded, color: accent),
          label: 'H2',
          onTap: () => _insertBlock('## Section title'),
        ),
        _EditorToolChip(
          iconBuilder:
              (accent) =>
                  Icon(Icons.format_list_bulleted_rounded, color: accent),
          label: 'Bullets',
          onTap: () => _insertBlock('- Point one\n- Point two\n- Point three'),
        ),
        _EditorToolChip(
          iconBuilder:
              (accent) =>
                  Icon(Icons.format_list_numbered_rounded, color: accent),
          label: 'Steps',
          onTap:
              () =>
                  _insertBlock('1. First step\n2. Second step\n3. Third step'),
        ),
        _EditorToolChip(
          iconBuilder:
              (accent) => Icon(Icons.format_quote_rounded, color: accent),
          label: 'Quote',
          onTap: () => _insertBlock('> Add a key takeaway or coach note here.'),
        ),
        _EditorToolChip(
          iconBuilder:
              (accent) => Icon(Icons.ondemand_video_rounded, color: accent),
          label: 'Embed',
          onTap: _showEmbedSheet,
        ),
        _EditorToolChip(
          iconBuilder:
              (accent) => MynauiIcon(
                MynauiGlyphs.galleryMinimalistic,
                size: 15,
                color: accent,
              ),
          label: 'Image',
          onTap: _showImageSheet,
        ),
        _EditorToolChip(
          iconBuilder: (accent) => Icon(Icons.link_rounded, color: accent),
          label: 'Link',
          onTap:
              () => _wrapSelection(
                '[',
                '](https://example.com)',
                placeholder: 'link text',
              ),
        ),
        _EditorToolChip(
          iconBuilder:
              (accent) => Icon(Icons.horizontal_rule_rounded, color: accent),
          label: 'Divider',
          onTap: () => _insertBlock('---'),
        ),
        _EditorToolChip(
          iconBuilder:
              (accent) =>
                  MynauiIcon(MynauiGlyphs.closeCircle, size: 15, color: accent),
          label: 'Clear body',
          destructive: true,
          onTap: _clearContent,
        ),
      ],
    );
  }

  Widget _buildContentEditor() {
    final previewTitle =
        _titleController.text.trim().isEmpty
            ? 'Article title preview'
            : _titleController.text.trim();
    final previewSummary =
        _summaryController.text.trim().isEmpty
            ? 'Your summary will appear here once you add one.'
            : _summaryController.text.trim();

    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Writing surface',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              SegmentedButton<_EditorSurfaceTab>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: _EditorSurfaceTab.write,
                    icon: Icon(Icons.edit_note_rounded, size: 16),
                    label: Text('Write'),
                  ),
                  ButtonSegment(
                    value: _EditorSurfaceTab.preview,
                    icon: Icon(Icons.visibility_outlined, size: 16),
                    label: Text('Preview'),
                  ),
                ],
                selected: {_editorTab},
                onSelectionChanged: (next) {
                  if (next.isEmpty) return;
                  setState(() => _editorTab = next.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Use headings, lists, quotes, dividers, embeds, and images to structure the article. Preview uses the same renderer as the reader.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _EditorStatChip(label: 'Words', value: _wordCount.toString()),
              _EditorStatChip(
                label: 'Characters',
                value: _characterCount.toString(),
              ),
              _EditorStatChip(
                label: 'Read time',
                value:
                    _estimatedReadMinutes == 0
                        ? '0 min'
                        : '$_estimatedReadMinutes min',
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildContentToolbar(),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: LiftMotion.fast,
            switchInCurve: LiftMotion.enterCurve,
            switchOutCurve: LiftMotion.exitCurve,
            transitionBuilder: (child, animation) {
              return LiftTransitions.buildFadeUpTransition(
                animation: animation,
                child: child,
                beginOffset: const Offset(0, 0.012),
                beginScale: 0.998,
                fadeStart: 0.0,
              );
            },
            child:
                _editorTab == _EditorSurfaceTab.write
                    ? TextField(
                      key: const ValueKey('write'),
                      controller: _contentController,
                      focusNode: _contentFocusNode,
                      minLines: 12,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                      decoration: _inputDecoration(
                        hint:
                            'Start with the member problem, then break the answer into clear sections.',
                      ).copyWith(contentPadding: const EdgeInsets.all(12)),
                    )
                    : Container(
                      key: const ValueKey('preview'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(kIosCornerRadius),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            previewTitle,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            previewSummary,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Divider(
                            color: Theme.of(context).dividerTheme.color,
                            height: 1,
                          ),
                          const SizedBox(height: 10),
                          ArticleBodyView(content: _contentController.text),
                        ],
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataSection() {
    final suggestedMachines = widget.machineSuggestions
        .take(8)
        .toList(growable: false);
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Metadata',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            'Add supporting data so the article is easier to find and relate to machines or muscle groups.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _labeledField(
            label: 'Header image',
            controller: _imageController,
            hint: 'Paste a URL or choose from your phone',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _pickHeaderImageFromPhone,
              icon: const MynauiIcon(
                MynauiGlyphs.galleryMinimalistic,
                size: 18,
                color: Color(0xFF374151),
              ),
              label: const Text('Choose header image from phone'),
            ),
          ),
          const SizedBox(height: 10),
          _labeledField(
            label: 'Tags',
            controller: _tagsController,
            hint: 'form, back, machine',
          ),
          _labeledField(
            label: 'Muscle groups',
            controller: _musclesController,
            hint: 'Back, Biceps',
          ),
          _labeledField(
            label: 'Categories',
            controller: _categoriesController,
            hint: 'Technique, Recovery, Workout plan',
          ),
          _labeledField(
            label: 'Machine IDs',
            controller: _machinesController,
            hint: widget.machineSuggestions.join(', '),
          ),
          if (suggestedMachines.isNotEmpty) ...[
            Text(
              'Quick add machine IDs',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  suggestedMachines
                      .map(
                        (machineId) => ActionChip(
                          label: Text(machineId.toUpperCase()),
                          onPressed:
                              () => _appendCsvValue(
                                _machinesController,
                                machineId,
                              ),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            'Status',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          SegmentedButton<ArticleStatus>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? Colors.white
                    : kAccentColor;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? kAccentColor
                    : Colors.white;
              }),
              side: WidgetStatePropertyAll(
                BorderSide(color: Colors.grey.shade300),
              ),
            ),
            segments: const [
              ButtonSegment(value: ArticleStatus.draft, label: Text('Draft')),
              ButtonSegment(
                value: ArticleStatus.published,
                label: Text('Published'),
              ),
              ButtonSegment(
                value: ArticleStatus.archived,
                label: Text('Archived'),
              ),
            ],
            selected: {_status},
            onSelectionChanged: (next) {
              if (next.isEmpty) return;
              setState(() => _status = next.first);
              _scheduleDraftSave();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    const islandTop = 16.0;
    final listTopPadding =
        topInset + islandTop + kLiftIslandHeaderHeight + kIslandHeaderGap;
    final mediaBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: liftCanvasColor(context),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _editorScrollController,
              primary: false,
              padding: EdgeInsets.fromLTRB(
                kPagePadding,
                listTopPadding,
                kPagePadding,
                mediaBottom + 24,
              ),
              child: Column(
                children: [
                  _buildBasicsSection(),
                  const SizedBox(height: 8),
                  _buildContentEditor(),
                  const SizedBox(height: 8),
                  _buildMetadataSection(),
                ],
              ),
            ),
          ),
          Positioned(
            top: topInset + islandTop,
            left: kPagePadding,
            right: kPagePadding,
            child: LiftIslandHeader(
              scrollController: _editorScrollController,
              title: _editorTitle,
              leading: LiftIslandHeaderAction(
                onTap: () => Navigator.of(context).pop(),
                child: const MynauiIcon(
                  MynauiGlyphs.altArrowLeft,
                  color: kLiftIslandOnFrosted,
                  size: 22,
                ),
              ),
              trailing: LiftIslandHeaderAction(
                onTap: _canSave ? _submit : null,
                child: Opacity(
                  opacity: _canSave ? 1.0 : 0.35,
                  child: const MynauiIcon(
                    MynauiGlyphs.checkCircle,
                    color: kLiftIslandOnFrosted,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorStatChip extends StatelessWidget {
  const _EditorStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF111827),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorToolChip extends StatelessWidget {
  const _EditorToolChip({
    required this.iconBuilder,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final Widget Function(Color accent) iconBuilder;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final accent = destructive ? Colors.red.shade500 : kAccentColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(kIosCornerRadius),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 15,
                height: 15,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: iconBuilder(accent),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmbedExampleChip extends StatelessWidget {
  const _EmbedExampleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(kIosControlRadius),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFF4B5563),
        ),
      ),
    );
  }
}
