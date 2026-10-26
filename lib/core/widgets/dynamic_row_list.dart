import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

class FieldSpec {
  final String key;
  final String label;
  final String hint;
  final bool required;
  const FieldSpec({
    required this.key,
    required this.label,
    required this.hint,
    this.required = false,
  });
}

class DynamicRowList extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final List<FieldSpec> fields;
  final String addLabel;
  final Color accent;

  const DynamicRowList({
    super.key,
    required this.items,
    required this.onChanged,
    required this.fields,
    this.addLabel = 'Add Row',
    this.accent = AppColors.primary,
  });

  @override
  State<DynamicRowList> createState() => _DynamicRowListState();
}

class _DynamicRowListState extends State<DynamicRowList> {
  final Map<int, Map<String, TextEditingController>> _controllers = {};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant DynamicRowList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    for (var i = 0; i < widget.items.length; i++) {
      _controllers.putIfAbsent(i, () {
        final row = widget.items[i];
        return {
          for (final f in widget.fields)
            f.key: TextEditingController(
                text: (row[f.key] ?? '').toString()),
        };
      });
    }
    _controllers.removeWhere((k, _) => k >= widget.items.length);
  }

  @override
  void dispose() {
    for (final row in _controllers.values) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() {
    widget.onChanged([...widget.items, {}]);
  }

  void _removeRow(int index) {
    final updated = [...widget.items]..removeAt(index);
    _controllers.remove(index);
    widget.onChanged(updated);
  }

  void _updateRow(int index, String key, String value) {
    final updated = [...widget.items];
    while (updated.length <= index) {
      updated.add({});
    }
    updated[index] = {...updated[index], key: value};
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(widget.items.length, (i) {
          final ctrls = _controllers[i] ?? {};
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Entry ${i + 1}',
                        style: AppTextStyles.caption
                            .copyWith(color: widget.accent)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.error, size: 18),
                      onPressed: () => _removeRow(i),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...widget.fields.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: ctrls[f.key],
                        onChanged: (v) => _updateRow(i, f.key, v),
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: f.hint,
                          labelText: f.label,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    )),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: _addRow,
          icon: Icon(Icons.add_rounded, color: widget.accent, size: 18),
          label:
              Text(widget.addLabel, style: TextStyle(color: widget.accent)),
        ),
      ],
    );
  }
}