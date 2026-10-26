// lib/core/models/lab_test_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════════════
// ENUMS — shared between canonical tests and lab offerings
// ═══════════════════════════════════════════════════════════════════

enum LabTestCategory {
  haematology,
  biochemistry,
  clinicalPathology,
  serology,
  immunology,
  microbiology,
  endocrinology,
  tumourMarkers,
  cytology,
  histopathology,
  molecular,
  other,
}

extension LabTestCategoryX on LabTestCategory {
  String get label {
    switch (this) {
      case LabTestCategory.haematology:
        return 'Haematology';
      case LabTestCategory.biochemistry:
        return 'Biochemistry';
      case LabTestCategory.clinicalPathology:
        return 'Clinical Pathology';
      case LabTestCategory.serology:
        return 'Serology';
      case LabTestCategory.immunology:
        return 'Immunology';
      case LabTestCategory.microbiology:
        return 'Microbiology';
      case LabTestCategory.endocrinology:
        return 'Endocrinology';
      case LabTestCategory.tumourMarkers:
        return 'Tumour Markers';
      case LabTestCategory.cytology:
        return 'Cytology';
      case LabTestCategory.histopathology:
        return 'Histopathology';
      case LabTestCategory.molecular:
        return 'Molecular';
      case LabTestCategory.other:
        return 'Other';
    }
  }
}

LabTestCategory parseLabTestCategory(String? s) {
  if (s == null) return LabTestCategory.other;
  for (final c in LabTestCategory.values) {
    if (c.name == s) return c;
  }
  return LabTestCategory.other;
}

enum LabSampleType {
  blood,
  serum,
  plasma,
  urine,
  stool,
  sputum,
  swab,
  csf,
  tissue,
  other,
}

extension LabSampleTypeX on LabSampleType {
  String get label {
    switch (this) {
      case LabSampleType.blood:
        return 'Blood';
      case LabSampleType.serum:
        return 'Serum';
      case LabSampleType.plasma:
        return 'Plasma';
      case LabSampleType.urine:
        return 'Urine';
      case LabSampleType.stool:
        return 'Stool';
      case LabSampleType.sputum:
        return 'Sputum';
      case LabSampleType.swab:
        return 'Swab';
      case LabSampleType.csf:
        return 'CSF';
      case LabSampleType.tissue:
        return 'Tissue';
      case LabSampleType.other:
        return 'Other';
    }
  }
}

LabSampleType parseLabSampleType(String? s) {
  if (s == null) return LabSampleType.other;
  for (final t in LabSampleType.values) {
    if (t.name == s) return t;
  }
  return LabSampleType.other;
}

// ═══════════════════════════════════════════════════════════════════
// CANONICAL TEST MODEL — the master dictionary (/tests/)
// ═══════════════════════════════════════════════════════════════════

/// Canonical test — the master entry in /tests/, curated by the
/// platform admin. Labs inherit clinical fields from here and cannot
/// override code, name, category, sampleType, or fastingRequired.
class CanonicalTestModel {
  final String testId;

  // Identity
  final String code;
  final String name;

  // Clinical classification
  final LabTestCategory category;
  final LabSampleType sampleType;
  final bool fastingRequired;

  // Descriptive
  final String? description;
  final String? turnaroundHint;

  // Phase 2 placeholder
  final String? loincCode;

  // Lifecycle
  final bool active;

  // Audit
  final String? createdByUid;
  final String? createdByEmail;
  final DateTime? createdAt;
  final String? updatedByUid;
  final DateTime? updatedAt;

  CanonicalTestModel({
    required this.testId,
    required this.code,
    required this.name,
    required this.category,
    required this.sampleType,
    this.fastingRequired = false,
    this.description,
    this.turnaroundHint,
    this.loincCode,
    this.active = true,
    this.createdByUid,
    this.createdByEmail,
    this.createdAt,
    this.updatedByUid,
    this.updatedAt,
  });

  String get codeLower => code.toLowerCase();
  String get nameLower => name.toLowerCase();

  Map<String, dynamic> toMap() => {
        'code': code,
        'name': name,
        'codeLower': codeLower,
        'nameLower': nameLower,
        'category': category.name,
        'sampleType': sampleType.name,
        'fastingRequired': fastingRequired,
        'description': description,
        'turnaroundHint': turnaroundHint,
        'loincCode': loincCode,
        'active': active,
        'createdByUid': createdByUid,
        'createdByEmail': createdByEmail,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'updatedByUid': updatedByUid,
        'updatedAt': updatedByUid != null
            ? FieldValue.serverTimestamp()
            : null,
      };

  factory CanonicalTestModel.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return CanonicalTestModel(
      testId: d.id,
      code: (m['code'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      category: parseLabTestCategory(m['category']?.toString()),
      sampleType: parseLabSampleType(m['sampleType']?.toString()),
      fastingRequired: m['fastingRequired'] == true,
      description: m['description']?.toString(),
      turnaroundHint: m['turnaroundHint']?.toString(),
      loincCode: m['loincCode']?.toString(),
      active: m['active'] != false,
      createdByUid: m['createdByUid']?.toString(),
      createdByEmail: m['createdByEmail']?.toString(),
      createdAt: ts(m['createdAt']),
      updatedByUid: m['updatedByUid']?.toString(),
      updatedAt: ts(m['updatedAt']),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// LAB TEST MODEL — the lab's own catalogue entry
// (still used by lab_service, lab_test_catalog_screen, and the
// walk-in picker until the lab-offering refactor lands)
// ═══════════════════════════════════════════════════════════════════

class LabTestModel {
  final String id;
  final String labClinicId;
  final String code;
  final String name;
  final String category;
  final String sampleType;
  final bool fastingRequired;
  final int? turnaroundHours;
  final String? deptId;
  final bool active;
  final String searchKey;
  final List<dynamic> searchTokens;

  LabTestModel({
    required this.id,
    required this.labClinicId,
    required this.code,
    required this.name,
    required this.category,
    required this.sampleType,
    this.fastingRequired = false,
    this.turnaroundHours,
    this.deptId,
    this.active = true,
    this.searchKey = '',
    this.searchTokens = const [],
  });

String get docId => id;
String get display => code.isEmpty ? name : '$code — $name';

  factory LabTestModel.fromMap(String id, Map<String, dynamic> m) {
    return LabTestModel(
      id: id,
      labClinicId: (m['labClinicId'] ?? '').toString(),
      code: (m['code'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      category: (m['category'] ?? 'Other').toString(),
      sampleType: (m['sampleType'] ?? 'Blood').toString(),
      fastingRequired: m['fastingRequired'] == true,
      turnaroundHours: (m['turnaroundHours'] as num?)?.toInt(),
      deptId: m['deptId']?.toString(),
      active: m['active'] != false,
      searchKey: (m['searchKey'] ?? '').toString(),
      searchTokens: (m['searchTokens'] as List?) ?? const [],
    );
  }

  /// Builds a normalized search index for a test. Used at creation
  /// time to denormalize searchable strings onto the doc.
  static ({String key, List<String> tokens}) buildSearchIndex({
    required String code,
    required String name,
    required String category,
    required String sampleType,
  }) {
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final key = '${norm(code)}__${norm(name)}';
    final tokens = <String>{
      ...norm(code).split(' '),
      ...norm(name).split(' '),
      ...norm(category).split(' '),
      ...norm(sampleType).split(' '),
    }.where((t) => t.isNotEmpty).toList();
    return (key: key, tokens: tokens);
  }
}