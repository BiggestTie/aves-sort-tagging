import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/images.dart';
import 'package:aves/model/tags/comics.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/comics/comic_page.dart';
import 'package:material_ui/material_ui.dart';

// Full screen reader for a comic: swipe left to right, right to left (manga),
// or scroll vertically (webtoon), with pinch to zoom. Tap to show or hide controls.
class ComicReaderPage extends StatefulWidget {
  static const routeName = '/comics/reader';

  final String comicTag;
  final List<AvesEntry> pages;
  final int initialPage;

  const new({
    super.key,
    required this.comicTag,
    required this.pages,
    this.initialPage = 0,
  });

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage> {
  late ComicReadingMode _mode;
  late PageController _pageController;
  late List<AvesEntry> _pages;
  int _page = 0;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _mode = Comics.readingMode(widget.comicTag);
    _pages = widget.pages;
    _page = widget.initialPage.clamp(0, _pages.isEmpty ? 0 : _pages.length - 1);
    _pageController = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              title: Text(Comics.title(widget.comicTag)),
              actions: [
                PopupMenuButton<ComicReadingMode>(
                  icon: const Icon(AIcons.read),
                  tooltip: 'Reading direction',
                  initialValue: _mode,
                  onSelected: _setMode,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: .leftToRight, child: Text('Left to right')),
                    PopupMenuItem(value: .rightToLeft, child: Text('Right to left (manga)')),
                    PopupMenuItem(value: .vertical, child: Text('Vertical scroll')),
                  ],
                ),
                IconButton(
                  icon: const Icon(AIcons.comic),
                  onPressed: _openPages,
                  tooltip: 'Pages, order and tags',
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            Positioned.fill(child: _mode == .vertical ? _buildVertical() : _buildPaged()),
            if (_showControls && _pages.isNotEmpty && _mode != .vertical)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text('${_page + 1} / ${_pages.length}', style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaged() {
    return PageView.builder(
      controller: _pageController,
      reverse: _mode == .rightToLeft,
      itemCount: _pages.length,
      onPageChanged: (page) => setState(() => _page = page),
      itemBuilder: (context, index) => _ZoomablePage(entry: _pages[index]),
    );
  }

  Widget _buildVertical() {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: ListView.builder(
        itemCount: _pages.length,
        itemBuilder: (context, index) => Image(
          image: _pages[index].getFullImage(),
          fit: .fitWidth,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) => progress == null ? child : const SizedBox(height: 400, child: Center(child: CircularProgressIndicator())),
        ),
      ),
    );
  }

  void _setMode(ComicReadingMode mode) {
    Comics.setReadingMode(widget.comicTag, mode);
    setState(() {
      _mode = mode;
      _pageController.dispose();
      _pageController = PageController(initialPage: _page);
    });
  }

  Future<void> _openPages() async {
    await Navigator.maybeOf(context)?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: ComicPage.routeName),
        builder: (context) => ComicPage(comicTag: widget.comicTag),
      ),
    );
  }
}

// a page that can be zoomed, letting the reader swipe to other pages when not zoomed
class _ZoomablePage extends StatefulWidget {
  final AvesEntry entry;

  const new({required this.entry});

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      minScale: 1,
      maxScale: 5,
      panEnabled: _zoomed,
      child: Center(
        child: Image(
          image: widget.entry.getFullImage(),
          fit: .contain,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
