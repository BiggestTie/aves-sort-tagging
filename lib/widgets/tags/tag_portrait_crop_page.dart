import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/images.dart';
import 'package:aves/model/tags/tag_path.dart';
import 'package:aves/model/tags/tag_portraits.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:material_ui/material_ui.dart';

// Lets the user move and zoom an image inside a square frame,
// and saves the framed part as the portrait of a tag.
// Pops with true when a portrait was saved.
class TagPortraitCropPage extends StatefulWidget {
  static const routeName = '/tags/portrait/crop';

  // size of the saved portrait, in pixels
  static const portraitSize = 512;

  final AvesEntry entry;
  final String tag;

  const new({
    super.key,
    required this.entry,
    required this.tag,
  });

  @override
  State<TagPortraitCropPage> createState() => _TagPortraitCropPageState();
}

class _TagPortraitCropPageState extends State<TagPortraitCropPage> {
  final TransformationController _transformationController = TransformationController();
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  ui.Image? _image;
  Object? _error;
  bool _saving = false;

  // size of the square frame, and scale from image pixels to frame pixels at zoom 1
  double _frameSize = 0;
  double _baseScale = 1;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    final listener = _imageListener;
    if (listener != null) {
      _imageStream?.removeListener(listener);
    }
    _transformationController.dispose();
    super.dispose();
  }

  void _loadImage() {
    final stream = widget.entry.getFullImage().resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, synchronousCall) {
        if (!mounted) return;
        setState(() => _image = info.image);
      },
      onError: (error, stackTrace) {
        if (!mounted) return;
        setState(() => _error = error);
      },
    );
    stream.addListener(listener);
    _imageStream = stream;
    _imageListener = listener;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = _image;
    return AvesScaffold(
      appBar: AppBar(
        title: Text(TagPath.leaf(widget.tag)),
        actions: [
          IconButton(
            icon: const Icon(AIcons.apply),
            onPressed: image == null || _saving ? null : _save,
            tooltip: 'Save portrait',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Move and zoom so the face fills the square.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: Center(
                child: _error != null
                    ? Text('Could not load this image.\n$_error', textAlign: .center)
                    : image == null
                    ? const CircularProgressIndicator()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          _setupFrame(image, min(constraints.maxWidth, constraints.maxHeight) - 32);
                          return Container(
                            width: _frameSize,
                            height: _frameSize,
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.colorScheme.primary, width: 2),
                            ),
                            child: ClipRect(
                              child: InteractiveViewer(
                                transformationController: _transformationController,
                                constrained: false,
                                minScale: 1,
                                maxScale: 10,
                                child: SizedBox(
                                  width: image.width * _baseScale,
                                  height: image.height * _baseScale,
                                  child: RawImage(image: image, fit: .fill),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            if (_saving) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  // at zoom 1, the image covers the frame, centered
  // (set up once, before the viewer listens to the transformation)
  void _setupFrame(ui.Image image, double frameSize) {
    if (_frameSize > 0) return;
    _frameSize = frameSize;
    _baseScale = frameSize / min(image.width, image.height);
    final dx = (image.width * _baseScale - frameSize) / 2;
    final dy = (image.height * _baseScale - frameSize) / 2;
    _transformationController.value = Matrix4.translationValues(-dx, -dy, 0);
  }

  Future<void> _save() async {
    final image = _image;
    if (image == null || _frameSize <= 0) return;
    setState(() => _saving = true);
    try {
      // frame corners, in image pixels
      final topLeft = _transformationController.toScene(Offset.zero) / _baseScale;
      final bottomRight = _transformationController.toScene(Offset(_frameSize, _frameSize)) / _baseScale;
      final source = Rect.fromPoints(topLeft, bottomRight).intersect(Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));
      if (source.isEmpty) return;

      const size = TagPortraitCropPage.portraitSize;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        source,
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        Paint()..filterQuality = .high,
      );
      final portrait = await recorder.endRecording().toImage(size, size);
      final bytes = await portrait.toByteData(format: ui.ImageByteFormat.png);
      portrait.dispose();
      if (bytes == null) return;

      await TagPortraits.instance.save(widget.tag, bytes.buffer.asUint8List());
      if (mounted) Navigator.maybeOf(context)?.pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
