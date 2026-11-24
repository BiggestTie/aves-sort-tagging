import 'package:aves/model/tags/tag_path.dart';
import 'package:aves/theme/themes.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:material_ui/material_ui.dart';

// Edits which tags are added automatically along with `tag`.
// Pops with the new set of implied tags, or null when cancelled.
class TagImplicationDialog extends StatefulWidget {
  static const routeName = '/dialog/tag_implication';

  final String tag;
  final Set<String> implied;

  const new({
    super.key,
    required this.tag,
    required this.implied,
  });

  @override
  State<TagImplicationDialog> createState() => _TagImplicationDialogState();
}

class _TagImplicationDialogState extends State<TagImplicationDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = (widget.implied.toList()..sort()).join('\n');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AvesDialog(
      title: 'Implied tags',
      scrollableContent: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Whenever you add '),
                TextSpan(
                  text: TagPath.label(widget.tag),
                  style: const TextStyle(fontWeight: .bold),
                ),
                const TextSpan(text: ', also add:'),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'Blue Archive|Groups|C&C',
            ),
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'One tag per line. Use | for nested tags. Leave empty to remove the rule.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
      actions: [
        const CancelButton(),
        TextButton(
          onPressed: _submit,
          child: Text(Themes.asButtonLabel('Save')),
        ),
      ],
    );
  }

  void _submit() {
    final implied = _controller.text.split('\n').map(TagPath.normalize).where((v) => v.isNotEmpty).toSet();
    Navigator.maybeOf(context)?.pop<Set<String>>(implied);
  }
}
