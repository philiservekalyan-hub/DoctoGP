// lib/core/services/pill_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pill_models.dart';
import 'notification_service.dart';

final pillServiceProvider = Provider<PillService>((ref) {
  return PillService(ref.watch(notificationServiceProvider));
});

class PillService {
  PillService(this._notifier);
  final NotificationService _notifier;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<String> createSchedule({
    required String patientDocId,
    required String patientAuthUid,
    String? clinicId,
    required String medicationName,
    required String dose,
    required List<String> times,
    required DateTime startDate,
    DateTime? endDate,
    int graceMinutes = 30,
    String? prescribedBy,
    String? notes,
  }) async {
    final scheduleRef = _db.collection('pillSchedules').doc();

    final schedule = PillSchedule(
      scheduleId: scheduleRef.id,
      patientDocId: patientDocId,
      patientAuthUid: patientAuthUid,
      clinicId: clinicId,
      medicationName: medicationName,
      dose: dose,
      times: times,
      startDate: startDate,
      endDate: endDate,
      graceMinutes: graceMinutes,
      prescribedBy: prescribedBy,
      notes: notes,
    );

    await scheduleRef.set({
      ...schedule.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _generateDoses(
      scheduleId: scheduleRef.id,
      schedule: schedule,
      fromDate: startDate,
      days: 7,
    );

    return scheduleRef.id;
  }

  Future<void> updateSchedule(
    PillSchedule schedule, {
    required List<String> times,
    required int graceMinutes,
    DateTime? endDate,
    bool? active,
    String? notes,
  }) async {
    await _db.collection('pillSchedules').doc(schedule.scheduleId).update({
      'times': times,
      'graceMinutes': graceMinutes,
      'endDate': endDate == null ? null : Timestamp.fromDate(endDate),
      'active': active ?? schedule.active,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final futurePending = await _db
        .collection('pillDoses')
        .where('scheduleId', isEqualTo: schedule.scheduleId)
        .where('status', isEqualTo: 'pending')
        .where('scheduledAt', isGreaterThan: Timestamp.now())
        .get();
    if (futurePending.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final d in futurePending.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();

      for (final d in futurePending.docs) {
        await _notifier.cancelDoseReminder(d.id);
      }
    }

    await _generateDoses(
      scheduleId: schedule.scheduleId,
      schedule: schedule,
      fromDate: DateTime.now(),
      days: 7,
    );
  }

  Future<void> deactivateSchedule(String scheduleId) async {
    await _db.collection('pillSchedules').doc(scheduleId).update({
      'active': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final futurePending = await _db
        .collection('pillDoses')
        .where('scheduleId', isEqualTo: scheduleId)
        .where('status', isEqualTo: 'pending')
        .where('scheduledAt', isGreaterThan: Timestamp.now())
        .get();
    for (final d in futurePending.docs) {
      await _notifier.cancelDoseReminder(d.id);
    }
  }

  Future<void> markTaken(String doseId, {String? note}) async {
    await _db.collection('pillDoses').doc(doseId).update({
      'status': PillDoseStatus.taken.wire,
      'confirmedBy': 'patient',
      'confirmedAt': FieldValue.serverTimestamp(),
      if (note != null && note.trim().isNotEmpty) 'notes': note.trim(),
    });
    await _notifier.cancelDoseReminder(doseId);
  }

  Future<void> markSkipped(String doseId, {String? note}) async {
    await _db.collection('pillDoses').doc(doseId).update({
      'status': PillDoseStatus.skipped.wire,
      'confirmedBy': 'patient',
      'confirmedAt': FieldValue.serverTimestamp(),
      if (note != null && note.trim().isNotEmpty) 'notes': note.trim(),
    });
    await _notifier.cancelDoseReminder(doseId);
  }

  Future<void> _generateDoses({
    required String scheduleId,
    required PillSchedule schedule,
    required DateTime fromDate,
    required int days,
  }) async {
    final now = DateTime.now();
    final batch = _db.batch();
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final pendingNotifications = <({String doseId, DateTime at})>[];

    for (var d = 0; d < days; d++) {
      final day = start.add(Duration(days: d));
      if (schedule.endDate != null && day.isAfter(schedule.endDate!)) break;

      for (final t in schedule.times) {
        final parts = t.split(':');
        if (parts.length != 2) continue;
        final hh = int.tryParse(parts[0]);
        final mm = int.tryParse(parts[1]);
        if (hh == null || mm == null) continue;

        final scheduledAt = DateTime(day.year, day.month, day.day, hh, mm);
        if (scheduledAt.isBefore(now)) continue;

        final graceUntil =
            scheduledAt.add(Duration(minutes: schedule.graceMinutes));
        final doseRef = _db.collection('pillDoses').doc();

        batch.set(doseRef, {
          'scheduleId': scheduleId,
          'patientDocId': schedule.patientDocId,
          'patientAuthUid': schedule.patientAuthUid,
          'scheduledAt': Timestamp.fromDate(scheduledAt),
          'graceUntil': Timestamp.fromDate(graceUntil),
          'status': PillDoseStatus.pending.wire,
          'confirmedBy': null,
          'confirmedAt': null,
          'deviceEventId': null,
          'escalation': null,
          'notes': null,
          'medicationName': schedule.medicationName,
          'dose': schedule.dose,
          'createdAt': FieldValue.serverTimestamp(),
        });

        pendingNotifications.add((doseId: doseRef.id, at: scheduledAt));
      }
    }

    await batch.commit();

    for (final n in pendingNotifications) {
      try {
        await _notifier.scheduleDoseReminder(
          doseId: n.doseId,
          medicationName: schedule.medicationName,
          scheduledAt: n.at,
        );
      } catch (e) {
        debugPrint(
          '[PILL] failed to schedule notification for ${n.doseId}: $e',
        );
      }
    }
  }
}