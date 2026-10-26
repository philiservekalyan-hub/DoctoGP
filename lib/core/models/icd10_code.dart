// lib/core/models/icd10_code.dart

/// A single ICD-10 code with its human-readable description.
///
/// Phase 2+ may add a service layer that populates a full ~14,000
/// code list from Firebase Storage; the widget that consumes this
/// model is unchanged when that happens.
class Icd10Code {
  final String code;
  final String description;

  const Icd10Code({required this.code, required this.description});

  factory Icd10Code.fromJson(Map<String, dynamic> json) => Icd10Code(
        code: (json['code'] ?? '').toString(),
        description:
            (json['desc'] ?? json['description'] ?? '').toString(),
      );

  /// Lowercased variants — computed on demand. Bundled set is tiny
  /// (~120 codes), so recomputing per search call is instant.
  String get codeLower => code.toLowerCase();
  String get descriptionLower => description.toLowerCase();
}