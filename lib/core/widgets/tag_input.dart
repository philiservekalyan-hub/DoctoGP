import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

class TagInput extends StatefulWidget {
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final String hint;
  final Color accent;

  const TagInput({
    super.key,
    required this.tags,
    required this.onChanged,
    this.hint = 'Type and press Enter',
    this.accent = AppColors.primary,
  });

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  final _controller = TextEditingController();

  void _add(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    if (widget.tags.contains(v)) return;
    widget.onChanged([...widget.tags, v]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: AppColors.textPrimary),
                  onSubmitted: _add,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _add(_controller.text),
                icon: Icon(Icons.add_circle, color: widget.accent),
              ),
            ],
          ),
        ),
        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tags
                .map((t) => Chip(
                      label: Text(t),
                      backgroundColor: widget.accent.withOpacity(0.15),
                      labelStyle:
                          TextStyle(color: widget.accent, fontSize: 12),
                      side: BorderSide(
                          color: widget.accent.withOpacity(0.4)),
                      deleteIconColor: widget.accent,
                      onDeleted: () => widget.onChanged(
                          widget.tags.where((x) => x != t).toList()),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}