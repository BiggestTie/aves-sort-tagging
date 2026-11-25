import 'dart:async';
import 'dart:math';

import 'package:aves/model/tags/tag_path.dart';
import 'package:aves/model/tags/tag_portraits.dart';
import 'package:aves/theme/icons.dart';
import 'package:material_ui/material_ui.dart';

class TagPopupAction {
  final String label;
  final IconData icon;
  final FutureOr<void> Function() onTap;

  const new({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

// Shows a tag's portrait large, with its full path and some actions,
// when long pressing a tag. Tap outside to close.
Future<void> showTagPortraitPopup(
  BuildContext context, {
  required String tag,
  List<TagPopupAction> actions = const [],
}) async {
  // remove focus, if any, to prevent the keyboard from showing up afterwards
  FocusManager.instance.primaryFocus?.unfocus();

  final selected = await showGeneralDialog<TagPopupAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, animation, secondaryAnimation) => _TagPortraitPopup(tag: tag, actions: actions),
    transitionBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: .9, end: 1).animate(animation),
        child: child,
      ),
    ),
  );
  if (selected != null) {
    await selected.onTap();
  }
}

class _TagPortraitPopup extends StatelessWidget {
  final String tag;
  final List<TagPopupAction> actions;

  const new({
    required this.tag,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.sizeOf(context);
    final size = min(min(mq.width - 48, mq.height * .55), 400.0);
    final file = TagPortraits.instance.fileFor(tag);

    return SafeArea(
      child: Center(
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: .antiAlias,
          child: SizedBox(
            width: size,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                SizedBox(
                  width: size,
                  height: size,
                  child: file != null
                      ? Image.file(file, fit: .cover)
                      : ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Column(
                            mainAxisAlignment: .center,
                            children: [
                              Icon(AIcons.portrait, size: size / 4, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(height: 8),
                              Text('No portrait yet', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    TagPath.leaf(tag),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (TagPath.isNested(tag))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      TagPath.segments(tag).join(' › '),
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                if (actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 4,
                      children: actions
                          .map(
                            (action) => TextButton.icon(
                              onPressed: () => Navigator.maybeOf(context)?.pop(action),
                              icon: Icon(action.icon),
                              label: Text(action.label),
                            ),
                          )
                          .toList(),
                    ),
                  )
                else
                  const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
