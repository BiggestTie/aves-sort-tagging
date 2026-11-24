import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/tags/tag_backup.dart';
import 'package:aves/model/tags/tag_catalog.dart';
import 'package:aves/model/tags/tag_conversion.dart';
import 'package:aves/model/tags/tag_path.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/entry_set_action_delegate.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/dialogs/aves_confirmation_dialog.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// Bulk conversion of flat tags like `Asuna - Blue Archive` into nested tags
// like `Blue Archive|Asuna`, with a preview, a backup and a way to undo.
class TagConversionPage extends StatefulWidget {
  static const routeName = '/tags/convert';

  const new({super.key});

  @override
  State<TagConversionPage> createState() => _TagConversionPageState();
}

class _TagConversionPageState extends State<TagConversionPage> {
  late Map<String, int> _tagCounts;
  final Set<String> _excludedFranchises = {};

  // tags the user chose not to convert
  final Set<String> _skipped = {};

  // targets set by hand, overriding the suggestions
  final Map<String, String> _overrides = {};

  late TagConversionPlan _plan;
  bool _busy = false;

  CollectionSource get _source => context.read<CollectionSource>();

  @override
  void initState() {
    super.initState();
    _countTags();
    _updatePlan();
    // known characters give fuller paths, once loaded
    TagCatalog.instance.ensureLoaded().then((_) {
      if (!mounted) return;
      _updatePlan();
      setState(() {});
    });
  }

  void _countTags() {
    final counts = <String, int>{};
    _source.visibleEntries.forEach((entry) {
      entry.tags.forEach((tag) => counts[tag] = (counts[tag] ?? 0) + 1);
    });
    _tagCounts = counts;
  }

  void _updatePlan() {
    _plan = TagConversionPlanner.plan(
      _tagCounts,
      excludedFranchises: _excludedFranchises,
      catalogLookup: TagCatalog.instance.find,
    );
  }

  // final mapping: suggestions, minus skipped tags, plus manual targets
  Map<String, String> get _mapping {
    final mapping = Map.of(_plan.mapping)..removeWhere((from, _) => _skipped.contains(from));
    _overrides.forEach((from, to) {
      if (!_skipped.contains(from) && to != from) {
        mapping[from] = to;
      }
    });
    return mapping;
  }

  Set<AvesEntry> _affectedEntries(Map<String, String> mapping) {
    return _source.visibleEntries.where((entry) => entry.canEditTags && entry.tags.any(mapping.containsKey)).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mapping = _mapping;
    final affectedCount = _affectedEntries(mapping).length;

    // suggested conversions, then tags converted by hand
    final rows = <String>[
      ..._plan.conversions.map((v) => v.from),
      ..._overrides.keys.whereNot(_plan.mapping.containsKey),
    ];
    final unchanged = _plan.unchanged.whereNot(_overrides.containsKey).toList();

    return AvesScaffold(
      appBar: AppBar(
        title: const Text('Convert tags'),
        actions: [
          IconButton(
            icon: const Icon(AIcons.restore),
            onPressed: _busy ? null : _showBackups,
            tooltip: 'Undo a conversion',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Turns tags like “Asuna - Blue Archive” into nested tags like “Blue Archive|Asuna”. '
                'Nothing changes until you tap Apply, and your current tags are backed up first.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const _SectionTitle('Franchises'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Detected from your tags. Untick any that are not franchises (like an outfit name).',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _buildFranchiseChips(),
              ),
            ),
            _SectionTitle('Changes: ${rows.length - _skipped.where(rows.contains).length} tags on $affectedCount items'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Tap a change to edit where the tag goes, e.g. “Blue Archive|Groups|C&C”.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            ...rows.map((from) {
              final to = _overrides[from] ?? _plan.mapping[from] ?? from;
              final skipped = _skipped.contains(from);
              return CheckboxListTile(
                value: !skipped,
                onChanged: (value) => setState(() {
                  if (value ?? false) {
                    _skipped.remove(from);
                  } else {
                    _skipped.add(from);
                  }
                }),
                title: Text(from),
                subtitle: Text('→ $to · ${_tagCounts[from] ?? 0} items'),
                secondary: IconButton(
                  icon: const Icon(AIcons.edit),
                  onPressed: () => _editTarget(from, to),
                  tooltip: 'Edit',
                ),
              );
            }),
            if (unchanged.isNotEmpty)
              ExpansionTile(
                title: Text('Not converted (${unchanged.length})'),
                subtitle: const Text('Tags without a franchise. Tap one to convert it by hand.'),
                children: unchanged
                    .map(
                      (tag) => ListTile(
                        title: Text(tag),
                        subtitle: Text('${_tagCounts[tag] ?? 0} items'),
                        onTap: () => _editTarget(tag, tag),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy || mapping.isEmpty ? null : () => _apply(mapping),
        icon: const Icon(AIcons.apply),
        label: Text(_busy ? 'Working…' : 'Apply'),
      ),
    );
  }

  List<Widget> _buildFranchiseChips() {
    // franchises currently used, plus excluded ones so they can be ticked again
    final names = <String>[
      ..._plan.franchises.map((v) => v.name),
      ..._excludedFranchises.whereNot((v) => _plan.franchises.any((f) => f.name == v)),
    ];
    return names.map((name) {
      final franchise = _plan.franchises.firstWhereOrNull((v) => v.name == name);
      final excluded = _excludedFranchises.contains(name);
      return FilterChip(
        label: Text(franchise != null ? '$name (${franchise.tagCount})' : name),
        selected: !excluded,
        onSelected: (selected) => setState(() {
          if (selected) {
            _excludedFranchises.remove(name);
          } else {
            _excludedFranchises.add(name);
          }
          _updatePlan();
        }),
      );
    }).toList();
  }

  Future<void> _editTarget(String from, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showAvesDialog<String>(
      context: context,
      builder: (context) => AvesDialog(
        title: from,
        scrollableContent: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Convert to',
                helperText: 'Use | for nested tags',
              ),
              onSubmitted: (value) => Navigator.maybeOf(context)?.pop(value),
            ),
          ),
        ],
        actions: [
          const CancelButton(),
          TextButton(
            onPressed: () => Navigator.maybeOf(context)?.pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    final to = TagPath.normalize(result);
    setState(() {
      _skipped.remove(from);
      if (to.isEmpty || to == from) {
        _overrides.remove(from);
        if (!_plan.mapping.containsKey(from)) return;
        _skipped.add(from);
      } else {
        _overrides[from] = to;
      }
    });
  }

  Future<void> _apply(Map<String, String> mapping) async {
    final entries = _affectedEntries(mapping);
    if (entries.isEmpty) return;

    final confirmed = await showConfirmationDialog(
      context: context,
      message: 'Convert ${mapping.length} tags on ${entries.length} items? Your current tags are backed up first, and you can undo from the history button.',
      ok: 'Convert',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await TagBackup.save(entries, label: 'Convert tags');
      if (!mounted) return;
      final newTagsByEntry = Map.fromEntries(entries.map((entry) => MapEntry(entry, TagConversionPlanner.convertTags(entry.tags, mapping))));
      await EntrySetActionDelegate().doEditTags(context, newTagsByEntry);
    } finally {
      if (mounted) {
        _skipped.clear();
        _overrides.clear();
        _countTags();
        _updatePlan();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showBackups() async {
    final backups = await TagBackup.list();
    if (!mounted) return;
    final backup = await showAvesDialog<TagBackup>(
      context: context,
      builder: (context) => AvesDialog(
        title: 'Undo a conversion',
        scrollableContent: backups.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No backups yet.'),
                ),
              ]
            : backups
                  .map(
                    (v) => ListTile(
                      title: Text(_formatDate(v.created)),
                      subtitle: Text('${v.itemCount} items'),
                      onTap: () => Navigator.maybeOf(context)?.pop(v),
                    ),
                  )
                  .toList(),
        actions: const [CancelButton()],
      ),
    );
    if (backup == null || !mounted) return;

    final tagsByEntry = await backup.read(_source.visibleEntries.where((entry) => entry.canEditTags));
    if (!mounted) return;
    final confirmed = await showConfirmationDialog(
      context: context,
      message: 'Restore the tags of ${tagsByEntry.length} items to how they were on ${_formatDate(backup.created)}?',
      ok: 'Restore',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await EntrySetActionDelegate().doEditTags(context, tagsByEntry);
    } finally {
      if (mounted) {
        _countTags();
        _updatePlan();
        setState(() => _busy = false);
      }
    }
  }

  static String _formatDate(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const new(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
