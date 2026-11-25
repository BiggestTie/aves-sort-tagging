import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/images.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/tags/online/online_tag_search.dart';
import 'package:aves/model/tags/online/online_tag_suggester.dart';
import 'package:aves/model/tags/tag_catalog.dart';
import 'package:aves/model/tags/tag_path.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/aves_app.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/tags/tag_tree_list.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// Finds the image online (SauceNAO, then Danbooru for tags) and lets the user
// review suggested tags, matched to their own tags. Nothing is added without confirmation.
// Pops with the tags to add.
class OnlineTagSearchPage extends StatefulWidget {
  static const routeName = '/tags/online_search';

  // longest side of the image sent for the search
  static const maxUploadSize = 1200;

  final AvesEntry entry;

  // tags already on the item
  final Set<String> currentTags;

  const new({
    super.key,
    required this.entry,
    required this.currentTags,
  });

  @override
  State<OnlineTagSearchPage> createState() => _OnlineTagSearchPageState();
}

class _OnlineTagSearchPageState extends State<OnlineTagSearchPage> {
  bool _loading = true;
  String? _status;
  String? _error;
  OnlineTagSearchResult? _result;
  bool _noMatch = false;
  List<TagSuggestion> _suggestions = [];
  final Set<int> _checked = {};
  bool _retryingDanbooru = false;
  bool _askedForKey = false;

  @override
  void initState() {
    super.initState();
    // after the first frame, as it may show a dialog
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
      _noMatch = false;
      _result = null;
    });

    // without a SauceNAO key, the other search engines are still tried
    var apiKey = settings.sauceNaoApiKey;
    if (apiKey == null && !_askedForKey) {
      _askedForKey = true;
      apiKey = await showSauceNaoKeyDialog(context);
      if (!mounted) return;
    }

    try {
      setState(() => _status = 'Preparing image…');
      final bytes = await _encodeImage();
      if (!mounted) return;
      setState(() => _status = 'Searching online…');
      final result = await OnlineTagSearch.search(
        bytes,
        sauceNaoApiKey: apiKey,
        danbooruLogin: settings.danbooruLogin,
        danbooruApiKey: settings.danbooruApiKey,
      );
      if (!mounted) return;
      await TagCatalog.instance.ensureLoaded();
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _noMatch = true;
          _loading = false;
        });
        return;
      }
      _setResult(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  void _setResult(OnlineTagSearchResult result) {
    final source = context.read<CollectionSource>();
    final suggester = OnlineTagSuggester(
      knownTags: {...source.sortedTags, ...TagCatalog.instance.tags},
      catalogLookup: TagCatalog.instance.find,
      rememberedMappings: settings.onlineTagMappings,
    );
    final currentTags = TagPath.expand(widget.currentTags);
    // tags already on the item are not suggested again
    final suggestions = suggester.suggest(result.tags).whereNot((v) => currentTags.contains(v.target)).toList();
    setState(() {
      _result = result;
      _suggestions = suggestions;
      _checked
        ..clear()
        ..addAll(suggestions.indexed.where((kv) => kv.$2.recommended).map((kv) => kv.$1));
      _loading = false;
    });
  }

  // the image, scaled down, as PNG
  Future<Uint8List> _encodeImage() async {
    final stream = widget.entry.getFullImage().resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image>();
    final listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image.clone());
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    final image = await completer.future;
    stream.removeListener(listener);

    final scale = min(1.0, OnlineTagSearchPage.maxUploadSize / max(image.width, image.height));
    final width = max(1, (image.width * scale).round());
    final height = max(1, (image.height * scale).round());
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = .medium,
    );
    image.dispose();
    final scaled = await recorder.endRecording().toImage(width, height);
    final bytes = await scaled.toByteData(format: ui.ImageByteFormat.png);
    scaled.dispose();
    if (bytes == null) throw const OnlineTagSearchException('Could not prepare the image.');
    return bytes.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return AvesScaffold(
      appBar: AppBar(
        title: const Text('Find tags online'),
        actions: [
          IconButton(
            icon: const Icon(AIcons.settings),
            onPressed: () => showSauceNaoKeyDialog(context),
            tooltip: 'SauceNAO API key',
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
      floatingActionButton: _result != null && _checked.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _apply,
              icon: const Icon(AIcons.apply),
              label: Text('Add ${_checked.length} tags'),
            )
          : null,
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status ?? ''),
          ],
        ),
      );
    }
    final error = _error;
    if (error != null || _noMatch) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: .min,
            children: [
              Text(
                error ?? 'No confident match found online (SauceNAO, Danbooru, IQDB).\nThe image may be too new, edited, or cropped.',
                textAlign: .center,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _search,
                icon: const Icon(AIcons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final result = _result!;
    final match = result.match;
    final main = _suggestions.indexed.where((kv) => kv.$2.recommended).toList();
    final other = _suggestions.indexed.whereNot((kv) => kv.$2.recommended).toList();
    final link = match.urls.firstOrNull;
    final tagError = result.tagError;

    // other tags in collapsed groups, to look through without being overwhelmed
    final otherGroups = <(String, List<(int, TagSuggestion)>)>[
      ('Characters & series', other.where((kv) => kv.$2.category == .character || kv.$2.category == .franchise).toList()),
      ('Artists', other.where((kv) => kv.$2.category == .artist).toList()),
      ('Other tags', other.where((kv) => kv.$2.category == .general).toList()),
    ].where((v) => v.$2.isNotEmpty).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        // the item and the match side by side, scrolling away with the list
        _buildComparison(context, result),
        ListTile(
          title: Text('${match.similarity.toStringAsFixed(1)}% match on ${match.sourceName}'),
          subtitle: Text(
            [
              'Found by ${result.engine}',
              'Tags from ${result.tagSource}',
              if (result.longRemaining != null) '${result.longRemaining} SauceNAO searches left today',
            ].join(' · '),
          ),
          trailing: link != null
              ? IconButton(
                  icon: const Icon(AIcons.openOutside),
                  onPressed: () => AvesApp.launchUrl(link),
                  tooltip: 'Open source',
                )
              : null,
        ),
        if (_suggestions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('The match has no new tags for this item.'),
          ),
        if (main.isNotEmpty) ...[
          _header(context, 'Suggested'),
          ...main.map((kv) => _buildSuggestion(context, kv.$1, kv.$2)),
        ],
        if (tagError != null)
          ListTile(
            leading: const Icon(AIcons.error),
            title: const Text('Could not get the full tag list from Danbooru'),
            subtitle: Text('Only the short summary from SauceNAO is shown.\n$tagError\nAdding your Danbooru login in ⚙ may help.'),
            isThreeLine: true,
            trailing: result.danbooruId != null
                ? (_retryingDanbooru
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(AIcons.refresh),
                          onPressed: () => _retryDanbooru(result),
                          tooltip: 'Try Danbooru again',
                        ))
                : null,
          ),
        if (otherGroups.isNotEmpty) ...[
          _header(context, 'Not in your tags'),
          ...otherGroups.map(
            (group) => ExpansionTile(
              title: Text('${group.$1} (${group.$2.length})'),
              subtitle: Text('${group.$2.where((kv) => _checked.contains(kv.$1)).length} ticked'),
              children: group.$2.map((kv) => _buildSuggestion(context, kv.$1, kv.$2)).toList(),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Tick any tag to add it. Tap the pencil to use one of your tags instead: your choice is remembered for next time.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  // fetches the full Danbooru tags again, without a new SauceNAO search
  Future<void> _retryDanbooru(OnlineTagSearchResult result) async {
    final id = result.danbooruId;
    if (id == null) return;
    setState(() => _retryingDanbooru = true);
    try {
      final tags = await OnlineTagSearch.fetchDanbooruTags(id, login: settings.danbooruLogin, apiKey: settings.danbooruApiKey);
      if (!mounted) return;
      _setResult(
        OnlineTagSearchResult(
          match: result.match,
          tagSource: 'Danbooru',
          tags: tags,
          shortRemaining: result.shortRemaining,
          longRemaining: result.longRemaining,
          danbooruId: id,
          engine: result.engine,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _setResult(
        OnlineTagSearchResult(
          match: result.match,
          tagSource: result.tagSource,
          tags: result.tags,
          shortRemaining: result.shortRemaining,
          longRemaining: result.longRemaining,
          tagError: '$error',
          danbooruId: id,
          engine: result.engine,
        ),
      );
    } finally {
      if (mounted) setState(() => _retryingDanbooru = false);
    }
  }

  Widget _buildComparison(BuildContext context, OnlineTagSearchResult result) {
    final theme = Theme.of(context);
    final imageUrl = result.imageUrl;
    final link = result.match.urls.firstOrNull;

    Widget frame(Widget child, String caption, {VoidCallback? onTap}) => Expanded(
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: .antiAlias,
              child: InkWell(onTap: onTap, child: child),
            ),
          ),
          const SizedBox(height: 6),
          Text(caption, style: theme.textTheme.labelMedium),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          frame(
            Image(image: widget.entry.getThumbnail(extent: 512), fit: .contain),
            'Your image',
          ),
          const SizedBox(width: 12),
          frame(
            imageUrl != null
                ? Image.network(
                    imageUrl,
                    headers: const {'User-Agent': OnlineTagSearch.userAgent},
                    fit: .contain,
                    loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (context, error, stackTrace) => const Center(child: Icon(AIcons.error)),
                  )
                : const Center(child: Icon(AIcons.image)),
            'Match (${result.match.similarity.toStringAsFixed(0)}%)',
            onTap: link != null ? () => AvesApp.launchUrl(link) : null,
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _buildSuggestion(BuildContext context, int index, TagSuggestion suggestion) {
    final theme = Theme.of(context);
    final segments = TagPath.segments(suggestion.target);
    return CheckboxListTile(
      value: _checked.contains(index),
      onChanged: (value) => setState(() {
        if (value ?? false) {
          _checked.add(index);
        } else {
          _checked.remove(index);
        }
      }),
      title: Text(segments.last),
      subtitle: Text(
        [
          if (segments.length > 1) segments.sublist(0, segments.length - 1).join(' › '),
          '${suggestion.isKnown ? '' : 'new tag · '}from ${suggestion.source}',
        ].join('\n'),
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      isThreeLine: segments.length > 1,
      secondary: IconButton(
        icon: const Icon(AIcons.edit),
        onPressed: () => _changeTarget(index, suggestion),
        tooltip: 'Use another tag',
      ),
    );
  }

  Future<void> _changeTarget(int index, TagSuggestion suggestion) async {
    final source = context.read<CollectionSource>();
    final tag = await showAvesDialog<String>(
      context: context,
      builder: (context) => _PickTagDialog(source: source, initialQuery: TagPath.leaf(suggestion.target)),
    );
    if (tag == null || !mounted) return;

    // remember the choice for this tag found online
    settings.onlineTagMappings = {...settings.onlineTagMappings, suggestion.source: tag};
    setState(() {
      _suggestions[index] = suggestion.copyWith(target: tag);
      _checked.add(index);
    });
  }

  void _apply() {
    final tags = _checked.map((i) => _suggestions[i].target).toSet();
    Navigator.maybeOf(context)?.pop<Set<String>>(tags);
  }
}

// Asks for the SauceNAO API key (and optional Danbooru login), and stores them.
// Returns the SauceNAO key, or null when cancelled.
Future<String?> showSauceNaoKeyDialog(BuildContext context) async {
  final controller = TextEditingController(text: settings.sauceNaoApiKey ?? '');
  final danbooruLoginController = TextEditingController(text: settings.danbooruLogin ?? '');
  final danbooruKeyController = TextEditingController(text: settings.danbooruApiKey ?? '');
  final key = await showAvesDialog<String>(
    context: context,
    builder: (context) => AvesDialog(
      title: 'Online search keys',
      scrollableContent: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Searching images online uses SauceNAO, which needs a free account:\n'
            '1. Register at saucenao.com\n'
            '2. Open your account page, “api” section\n'
            '3. Copy the API key and paste it here',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => AvesApp.launchUrl('https://saucenao.com/user.php?page=search-api'),
              child: const Text('Open saucenao.com'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'API key'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Text(
            'Optional: your Danbooru login, used to get full tag lists when Danbooru blocks anonymous apps. '
            'Make an API key on danbooru.donmai.us in My Account › API Key.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: danbooruLoginController,
            decoration: const InputDecoration(labelText: 'Danbooru username'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: danbooruKeyController,
            decoration: const InputDecoration(labelText: 'Danbooru API key'),
          ),
        ),
      ],
      actions: [
        const CancelButton(),
        TextButton(
          onPressed: () => Navigator.maybeOf(context)?.pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  final danbooruLogin = danbooruLoginController.text;
  final danbooruKey = danbooruKeyController.text;
  controller.dispose();
  danbooruLoginController.dispose();
  danbooruKeyController.dispose();
  if (key == null || key.isEmpty) return null;
  settings.sauceNaoApiKey = key;
  settings.danbooruLogin = danbooruLogin;
  settings.danbooruApiKey = danbooruKey;
  return key;
}

// Lets the user pick one of their tags (or catalog tags), or type a new one.
class _PickTagDialog extends StatefulWidget {
  final CollectionSource source;
  final String initialQuery;

  const new({
    required this.source,
    required this.initialQuery,
  });

  @override
  State<_PickTagDialog> createState() => _PickTagDialogState();
}

class _PickTagDialogState extends State<_PickTagDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AvesDialog(
      title: 'Use another tag',
      scrollableContent: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search your tags',
              helperText: 'Or type a new tag, with | for nested tags',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        TagTreeList(
          source: widget.source,
          upQuery: _controller.text.trim().toUpperCase(),
          extraTags: TagCatalog.instance.tags,
          onTap: (tag) => Navigator.maybeOf(context)?.pop(tag),
        ),
      ],
      actions: [
        const CancelButton(),
        TextButton(
          onPressed: () {
            final tag = TagPath.normalize(_controller.text);
            if (tag.isNotEmpty) Navigator.maybeOf(context)?.pop(tag);
          },
          child: const Text('Use typed tag'),
        ),
      ],
    );
  }
}
