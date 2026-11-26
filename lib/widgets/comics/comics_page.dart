import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/images.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/tags/comics.dart';
import 'package:aves/model/tags/tag_path.dart';
import 'package:aves/widgets/comics/comic_page.dart';
import 'package:aves/widgets/comics/comic_reader_page.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// All comics, with their cover and number of pages.
class ComicsPage extends StatefulWidget {
  static const routeName = '/comics';

  const new({super.key});

  @override
  State<ComicsPage> createState() => _ComicsPageState();
}

class _ComicsPageState extends State<ComicsPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = context.read<CollectionSource>();
    final comics = Comics.collect(source).entries.sortedByCompare((kv) => kv.key, TagPath.compare);

    return AvesScaffold(
      appBar: AppBar(
        title: const Text('Comics'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => setState(() {
              if (value == 'stack') Comics.stackInGallery = !Comics.stackInGallery;
            }),
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'stack',
                checked: Comics.stackInGallery,
                child: const Text('One tile per comic in the gallery'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: comics.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No comics yet.\nSelect the pages in the gallery, open Edit tags, and tap the book button to make a comic.',
                    textAlign: .center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            : ListView(
                children: comics.map((kv) {
                  final comicTag = kv.key;
                  final pages = kv.value;
                  return ListTile(
                    leading: SizedBox(
                      width: 56,
                      height: 72,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image(image: pages.first.getThumbnail(extent: 160), fit: .cover),
                      ),
                    ),
                    title: Text(Comics.title(comicTag)),
                    subtitle: Text('${pages.length} pages'),
                    onTap: () => _open(context, comicTag, pages),
                    onLongPress: () => _openPages(context, comicTag),
                  );
                }).toList(),
              ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String comicTag, List<AvesEntry> pages) async {
    await Navigator.maybeOf(context)?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: ComicReaderPage.routeName),
        builder: (context) => ComicReaderPage(comicTag: comicTag, pages: List.of(pages)),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openPages(BuildContext context, String comicTag) async {
    await Navigator.maybeOf(context)?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: ComicPage.routeName),
        builder: (context) => ComicPage(comicTag: comicTag),
      ),
    );
    if (mounted) setState(() {});
  }
}
