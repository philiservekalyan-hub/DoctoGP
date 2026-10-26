// lib/core/models/disposition.dart

/// Clinical disposition — what happens to the patient at the end
/// of the consultation. Stored as a short string on the consultation
/// document; serialized via `.name` and parsed back via `fromString`.
enum Disposition {
  followUp,      // scheduled/asked to return
  discharged,    // finished — no further visit planned
  referred,      // referred to specialist or higher centre
  admitted,      // admitted to hospital
  noFollowUp,    // patient declined / not reachable
}

extension DispositionX on Disposition {
  String get label {
    switch (this) {
      case Disposition.followUp:
        return 'Follow-up';
      case Disposition.discharged:
        return 'Discharged';
      case Disposition.referred:
        return 'Referred';
      case Disposition.admitted:
        return 'Admitted';
      case Disposition.noFollowUp:
        return 'No follow-up';
    }
  }

  String get description {
    switch (this) {
      case Disposition.followUp:
        return 'Patient asked to return';
      case Disposition.discharged:
        return 'Consultation closed, no further visit planned';
      case Disposition.referred:
        return 'Referred to a specialist or higher centre';
      case Disposition.admitted:
        return 'Admitted for inpatient care';
      case Disposition.noFollowUp:
        return 'Patient declined follow-up or is unreachable';
    }
  }
}

Disposition? dispositionFromString(String? s) {
  if (s == null) return null;
  for (final d in Disposition.values) {
    if (d.name == s) return d;
  }
  return null;
}