// lib/core/utils/contact_utils.dart
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone dialler with the given number.
/// Returns false if the number is empty or the dialler couldn't be opened.
Future<bool> callNumber(String phone) async {
  final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleaned.isEmpty) return false;
  final uri = Uri(scheme: 'tel', path: cleaned);
  return launchUrl(uri);
}

/// Opens WhatsApp chat with the given number.
/// Normalizes 10-digit Indian numbers by prepending 91.
Future<bool> whatsappNumber(String phone, {String? message}) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return false;
  final normalized = digits.length == 10 ? '91$digits' : digits;
  final suffix =
      message != null ? '?text=${Uri.encodeComponent(message)}' : '';
  final uri = Uri.parse('https://wa.me/$normalized$suffix');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}