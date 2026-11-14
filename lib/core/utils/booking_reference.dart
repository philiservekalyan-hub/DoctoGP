// lib/core/utils/booking_reference.dart

/// Convert a Firestore doc ID into a short, human-readable booking
/// reference. Deterministic — same input always → same output.
///
/// "kL3mNpQrStUvWxYz12Ab" → "STAT-KL3M-12AB"
String bookingRefFromDocId(String docId) {
  if (docId.isEmpty) return 'STAT-0000-0000';
  final cleaned =
      docId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  if (cleaned.length < 8) {
    return 'STAT-${cleaned.padRight(8, '0')}';
  }
  final a = cleaned.substring(0, 4);
  final b = cleaned.substring(cleaned.length - 4);
  return 'STAT-$a-$b';
}