import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/images.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/tags/comics.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/entry_set_action_delegate.dart';
import 'package:aves/widgets/comics/comic_reader_page.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/dialogs/aves_confirmation_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

// Pages of a comic: drag to reorder, read from any page,
// and edit the tags of all pages at once.
class ComicPage extends StatefulWidget {
  static const routeName = '/comics/comic';

  final String comicTag;

  const new({
    super.key,
    required this.comicTag,
  });

  @override
  State<ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends State<ComicPage> {
  List<AvesEntry> _pages = [];

  CollectionSource get _source => context.read<CollectionSource>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _pages = Comics.pagesOf(_source, widget.comicTag);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AvesScaffold(
      appBar: AppBar(
        title: Text(Comics.title(widget.comicTag)),
        actions: [
          IconButton(
            icon: const Icon(AIcons.tag),
            onPressed: _pages.isEmpty ? null : _editTags,
            tooltip: 'Edit tags of all pages',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'sort':
                  _sortByFileName();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'sort', child: Text('Sort pages by file name')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _pages.isEmpty
            ? const Center(child: Text('This comic has no pages.'))
            : ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                header: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Hold and drag a page to move it. Tap a page to start reading from it.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                itemCount: _pages.length,
                onReorderItem: _onReorder,
                itemBuilder: (context, index) {
                  final entry = _pages[index];
                  return ListTile(
                    key: ValueKey(entry.id),
                    leading: SizedBox.square(
                      dimension: 56,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image(image: entry.getThumbnail(extent: 128), fit: .cover),
                      ),
                    ),
                    title: Text('Page ${index + 1}'),
                    subtitle: Text(p.basename(entry.path ?? entry.uri), maxLines: 1, overflow: .ellipsis),
                    trailing: IconButton(
                      icon: const Icon(AIcons.clear),
                      onPressed: () => _removePage(entry),
                      tooltip: 'Remove from comic',
                    ),
                    onTap: () => _read(index),
                  );
                },
              ),
      ),
      floatingActionButton: _pages.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _read(0),
              icon: const Icon(AIcons.read),
              label: const Text('Read'),
            ),
    );
  }

  // `newIndex` is already adjusted for the removed page
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final page = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, page);
    });
    Comics.saveOrder(widget.comicTag, _pages);
  }

  void _sortByFileName() {
    setState(() => _pages.sort(Comics.compareByFileName));
    Comics.saveOrder(widget.comicTag, _pages);
  }

  Future<void> _read(int index) async {
    await Navigator.maybeOf(context)?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: ComicReaderPage.routeName),
        builder: (context) => ComicReaderPage(comicTag: widget.comicTag, pages: List.of(_pages), initialPage: index),
      ),
    );
    if (mounted) setState(_load);
  }

  // the tags of the comic are those of all its pages
  Future<void> _editTags() async {
    final delegate = EntrySetActionDelegate();
    final newTagsByEntry = await delegate.selectTags(context, _pages.toSet());
    if (newTagsByEntry == null || !mounted) return;
    await delegate.doEditTags(context, newTagsByEntry);
    if (mounted) setState(_load);
  }

  Future<void> _removePage(AvesEntry entry) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      message: 'Remove this page from the comic? The image is kept, only its comic tag is removed.',
      ok: 'Remove',
    );
    if (!confirmed || !mounted) return;
    final tags = entry.tags.where((v) => v != widget.comicTag).toSet();
    await EntrySetActionDelegate().doEditTags(context, {entry: tags});
    if (mounted) setState(_load);
  }
}
