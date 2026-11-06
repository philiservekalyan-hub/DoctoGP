// lib/core/services/lab_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/lab_order_model.dart';
import '../models/lab_test_model.dart';
import '../models/lab_customer_model.dart';
import 'lab_customer_service.dart';

class LabService {
  final _db = FirebaseFirestore.instance;
  final _labCustomerService = LabCustomerService();

  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('labOrders');

  CollectionReference<Map<String, dynamic>> get _clinics =>
      _db.collection('clinics');

  CollectionReference<Map<String, dynamic>> _testsFor(String labClinicId) =>
      _clinics.doc(labClinicId).collection('labTests');

  CollectionReference<Map<String, dynamic>> _packagesFor(
          String labClinicId) =>
      _clinics.doc(labClinicId).collection('labPackages');

  // =================================================================
  // LINK MANAGEMENT
  // =================================================================

  Future<void> linkClinicAndLab({
    required String clinicId,
    required String clinicName,
    required String labClinicId,
    required String labName,
  }) async {
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();
    final adminUid = FirebaseAuth.instance.currentUser?.uid;

    final base = <String, dynamic>{
      'clinicId': clinicId,
      'clinicName': clinicName,
      'labClinicId': labClinicId,
      'labName': labName,
      'linkedAt': now,
      'linkedByAdminUid': adminUid,
      'active': true,
    };

    batch.set(
      _clinics.doc(clinicId).collection('linkedLabs').doc(labClinicId),
      base,
    );
    batch.set(
      _clinics
          .doc(labClinicId)
          .collection('linkedClinics')
          .doc(clinicId),
      base,
    );

    await batch.commit();
  }

  Future<void> unlinkClinicAndLab({
    required String clinicId,
    required String labClinicId,
  }) async {
    final batch = _db.batch();
    batch.delete(
      _clinics.doc(clinicId).collection('linkedLabs').doc(labClinicId),
    );
    batch.delete(
      _clinics
          .doc(labClinicId)
          .collection('linkedClinics')
          .doc(clinicId),
    );
    await batch.commit();
  }

  Stream<List<Map<String, dynamic>>> watchLinkedLabs(String clinicId) {
    return _clinics
        .doc(clinicId)
        .collection('linkedLabs')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  Stream<List<Map<String, dynamic>>> watchLinkedClinics(
      String labClinicId) {
    return _clinics
        .doc(labClinicId)
        .collection('linkedClinics')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  Stream<List<Map<String, dynamic>>> watchEntitiesByType(String type) {
    return _clinics
        .where('type', isEqualTo: type)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList());
  }

  // =================================================================
  // CATALOG READS
  // =================================================================

  Stream<List<({String labClinicId, String labName, List<dynamic> tests})>>
      watchLinkedCatalogs(String referringClinicId) {
    return watchLinkedLabs(referringClinicId).asyncMap((linked) async {
      final out =
          <({String labClinicId, String labName, List<dynamic> tests})>[];
      for (final lab in linked) {
        final labClinicId = lab['labClinicId'] as String;
        final labName = (lab['labName'] ?? 'Lab').toString();
        final catSnap = await _clinics
            .doc(labClinicId)
            .collection('catalog')
            .doc('main')
            .get();
        final tests = catSnap.exists
            ? (catSnap.data()?['tests'] as List? ?? [])
            : <dynamic>[];
        out.add((labClinicId: labClinicId, labName: labName, tests: tests));
      }
      return out;
    });
  }

  Stream<List<LabTestModel>> watchLabTests({
    required String labClinicId,
    bool includeInactive = false,
  }) {
    Query<Map<String, dynamic>> q = _testsFor(labClinicId);
    if (!includeInactive) {
      q = q.where('active', isEqualTo: true);
    }
    return q.snapshots().asyncMap((s) async {
      final docs = s.docs;

      final testIds = <String>{
        for (final d in docs)
          if ((d.data()['isLocal'] != true) &&
              (d.data()['testId'] != null) &&
              d.data()['testId'].toString().isNotEmpty)
            d.data()['testId'].toString(),
      };

      final canonicalMap = <String, Map<String, dynamic>>{};
      final ids = testIds.toList();
      for (var i = 0; i < ids.length; i += 30) {
        final chunk = ids.sublist(
          i, (i + 30) > ids.length ? ids.length : i + 30,
        );
        final snap = await _db
            .collection('tests')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          canonicalMap[doc.id] = doc.data();
        }
      }

      final list = docs.map((d) {
        final raw = Map<String, dynamic>.from(d.data());
        final isLocal = raw['isLocal'] == true;
        final testId = raw['testId']?.toString();

        if (!isLocal && testId != null && canonicalMap.containsKey(testId)) {
          final c = canonicalMap[testId]!;
          raw['code'] = c['code'];
          raw['name'] = c['name'];
          raw['category'] = c['category'];
          raw['sampleType'] = c['sampleType'];
          raw['fastingRequired'] = c['fastingRequired'] == true;
        } else if (isLocal) {
          raw['code'] = raw['localCode'];
          raw['name'] = raw['localName'];
          raw['category'] = raw['localCategory'];
          raw['sampleType'] = raw['localSampleType'];
          raw['fastingRequired'] = raw['localFastingRequired'] == true;
        }
        return LabTestModel.fromMap(d.id, raw);
      }).toList()
        ..sort((a, b) {
          final byCat = a.category.compareTo(b.category);
          if (byCat != 0) return byCat;
          return a.code.compareTo(b.code);
        });

      return list;
    });
  }

  // =================================================================
  // LEGACY FREE-FORM TEST CRUD
  // =================================================================

  Future<String> createLabTest({
    required String labClinicId,
    required String code,
    required String name,
    required String category,
    required String sampleType,
    bool fastingRequired = false,
    int? turnaroundHours,
    String? deptId,
  }) async {
    final idx = LabTestModel.buildSearchIndex(
      code: code,
      name: name,
      category: category,
      sampleType: sampleType,
    );

    final ref = _testsFor(labClinicId).doc();
    await ref.set({
      'labClinicId': labClinicId,
      'code': code.trim(),
      'name': name.trim(),
      'category': category.trim(),
      'sampleType': sampleType.trim(),
      'fastingRequired': fastingRequired,
      'turnaroundHours': turnaroundHours,
      'deptId': deptId,
      'active': true,
      'searchKey': idx.key,
      'searchTokens': idx.tokens,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _rebuildDenormalizedCatalog(labClinicId);
    return ref.id;
  }

  Future<void> updateLabTest({
    required String labClinicId,
    required String testDocId,
    required String code,
    required String name,
    required String category,
    required String sampleType,
    required bool fastingRequired,
    int? turnaroundHours,
    String? deptId,
    required bool active,
  }) async {
    final idx = LabTestModel.buildSearchIndex(
      code: code,
      name: name,
      category: category,
      sampleType: sampleType,
    );

    await _testsFor(labClinicId).doc(testDocId).update({
      'code': code.trim(),
      'name': name.trim(),
      'category': category.trim(),
      'sampleType': sampleType.trim(),
      'fastingRequired': fastingRequired,
      'turnaroundHours': turnaroundHours,
      'deptId': deptId,
      'active': active,
      'searchKey': idx.key,
      'searchTokens': idx.tokens,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Future<void> deactivateLabTest({
    required String labClinicId,
    required String testDocId,
  }) async {
    await _testsFor(labClinicId).doc(testDocId).update({
      'active': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _rebuildDenormalizedCatalog(labClinicId);
  }

  // =================================================================
  // CANONICAL OFFERINGS, LOCAL TESTS, PACKAGES
  // =================================================================

  Future<void> addOfferings({
    required String labClinicId,
    required List<String> testIds,
  }) async {
    if (testIds.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;

    final unique = <String>{};
    for (final id in testIds) {
      if (id.isNotEmpty) unique.add(id);
    }
    if (unique.isEmpty) return;

    final existing = await _testsFor(labClinicId).get();
    final existingCanonical = <String>{
      for (final d in existing.docs)
        if (d.data()['isLocal'] != true)
          (d.data()['testId'] ?? '').toString(),
    }..remove('');

    final toAdd = unique.difference(existingCanonical).toList();
    if (toAdd.isEmpty) return;

    final canonicalMap = <String, Map<String, dynamic>>{};
    for (var i = 0; i < toAdd.length; i += 30) {
      final chunk = toAdd.sublist(
        i, (i + 30) > toAdd.length ? toAdd.length : i + 30,
      );
      final snap = await _db
          .collection('tests')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        canonicalMap[doc.id] = doc.data();
      }
    }

    final batch = _db.batch();
    var added = 0;
    for (final testId in toAdd) {
      if (!canonicalMap.containsKey(testId)) continue;

      final docRef = _testsFor(labClinicId).doc(testId);
      batch.set(docRef, {
        'testId': testId,
        'isLocal': false,
        'mrp': null,
        'offerPrice': null,
        'turnaroundHours': null,
        'deptId': null,
        'displayName': null,
        'notes': null,
        'active': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': user?.uid,
        'createdByEmail': user?.email,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': user?.uid,
      });
      added++;
    }

    if (added == 0) return;

    await batch.commit();
    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Future<Set<String>> whichTestIdsAlreadyExist({
    required String labClinicId,
    required List<String> testIds,
  }) async {
    if (testIds.isEmpty) return const {};
    final snap = await _testsFor(labClinicId).get();
    final existing = <String>{
      for (final d in snap.docs)
        if (d.data()['isLocal'] != true)
          (d.data()['testId'] ?? '').toString(),
    }..remove('');
    return testIds.where(existing.contains).toSet();
  }

  Future<void> createLocalTest({
    required String labClinicId,
    required String code,
    required String name,
    required String category,
    required String sampleType,
    bool fastingRequired = false,
    int? turnaroundHours,
    required double mrp,
    double? offerPrice,
    String? notes,
  }) async {
    final effectiveOffer = offerPrice ?? mrp;
    if (effectiveOffer > mrp) {
      throw ArgumentError('Offer price cannot exceed MRP.');
    }

    final upperCode = code.trim().toUpperCase();
    if (upperCode.isEmpty) {
      throw ArgumentError('Local test code is required.');
    }

    final existing = await _testsFor(labClinicId).get();
    final canonicalTestIds = <String>[];
    for (final d in existing.docs) {
      final m = d.data();
      if (m['isLocal'] == true) {
        final existingCode =
            (m['localCode'] ?? '').toString().toUpperCase();
        if (existingCode == upperCode) {
          throw StateError(
            'A local test with code "$upperCode" already exists in your catalogue.',
          );
        }
      } else {
        final testId = (m['testId'] ?? '').toString();
        if (testId.isNotEmpty) canonicalTestIds.add(testId);
      }
    }

    for (var i = 0; i < canonicalTestIds.length; i += 30) {
      final chunk = canonicalTestIds.sublist(
        i,
        (i + 30) > canonicalTestIds.length
            ? canonicalTestIds.length
            : i + 30,
      );
      final snap = await _db
          .collection('tests')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final cCode =
            (doc.data()['code'] ?? '').toString().toUpperCase();
        if (cCode == upperCode) {
          throw StateError(
            'A test with code "$upperCode" already exists in your catalogue '
            '(from the master dictionary).',
          );
        }
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    final docRef = _testsFor(labClinicId).doc();
    await docRef.set({
      'testId': null,
      'isLocal': true,
      'localCode': upperCode,
      'localName': name.trim(),
      'localCategory': category,
      'localSampleType': sampleType,
      'localFastingRequired': fastingRequired,
      'mrp': mrp,
      'offerPrice': effectiveOffer,
      'turnaroundHours': turnaroundHours,
      'deptId': null,
      'displayName': null,
      'notes': notes,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': user?.uid,
      'createdByEmail': user?.email,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': user?.uid,
    });
    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Future<void> updateOffering({
    required String labClinicId,
    required String offeringId,
    required double mrp,
    double? offerPrice,
    int? turnaroundHours,
    bool? active,
    String? notes,
  }) async {
    final effectiveOffer = offerPrice ?? mrp;
    if (effectiveOffer > mrp) {
      throw ArgumentError('Offer price cannot exceed MRP.');
    }
    final user = FirebaseAuth.instance.currentUser;
    final data = <String, dynamic>{
      'mrp': mrp,
      'offerPrice': effectiveOffer,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': user?.uid,
    };
    if (turnaroundHours != null) {
      data['turnaroundHours'] = turnaroundHours;
    }
    if (active != null) data['active'] = active;
    if (notes != null) data['notes'] = notes;
    await _testsFor(labClinicId).doc(offeringId).update(data);
    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Future<void> setOfferingActive({
    required String labClinicId,
    required String offeringId,
    required bool active,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    await _testsFor(labClinicId).doc(offeringId).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': user?.uid,
    });
    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Future<void> removeOffering({
    required String labClinicId,
    required String offeringId,
  }) async {
    await _testsFor(labClinicId).doc(offeringId).delete();
    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Future<void> createPackage({
    required String labClinicId,
    required String name,
    String? description,
    required List<String> offeringIds,
    int? turnaroundHours,
    String? notes,
  }) async {
    if (offeringIds.isEmpty) {
      throw ArgumentError('Package must contain at least one test.');
    }
    final user = FirebaseAuth.instance.currentUser;
    final docRef = _packagesFor(labClinicId).doc();
    await docRef.set({
      'name': name.trim(),
      'description': description?.trim(),
      'includedTestOfferingIds': offeringIds,
      'includedTestSummary': '',
      'computedMrp': null,
      'computedOfferPrice': null,
      'computedDiscount': null,
      'computedDiscountPercent': null,
      'turnaroundHours': turnaroundHours,
      'notes': notes,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': user?.uid,
      'createdByEmail': user?.email,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': user?.uid,
    });
    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Future<void> updatePackage({
    required String labClinicId,
    required String packageId,
    required String name,
    String? description,
    required List<String> offeringIds,
    int? turnaroundHours,
    bool? active,
    String? notes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final data = <String, dynamic>{
      'name': name.trim(),
      'description': description?.trim(),
      'includedTestOfferingIds': offeringIds,
      'turnaroundHours': turnaroundHours,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': user?.uid,
    };
    if (active != null) data['active'] = active;
    await _packagesFor(labClinicId).doc(packageId).update(data);
    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Future<void> deletePackage({
    required String labClinicId,
    required String packageId,
  }) async {
    await _packagesFor(labClinicId).doc(packageId).delete();
    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Stream<List<Map<String, dynamic>>> watchPackages(String labClinicId) {
    return _packagesFor(labClinicId)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => <String, dynamic>{'packageId': d.id, ...d.data()})
            .toList());
  }

  // =================================================================
  // DENORMALIZED CATALOG REBUILD
  // =================================================================

  Future<void> _rebuildDenormalizedCatalog(String labClinicId) async {
    final offeringsSnap =
        await _testsFor(labClinicId).where('active', isEqualTo: true).get();
    final packagesSnap = await _packagesFor(labClinicId)
        .where('active', isEqualTo: true)
        .get();

    final testIds = <String>{
      for (final d in offeringsSnap.docs)
        if ((d.data()['testId'] ?? '').toString().isNotEmpty)
          d.data()['testId'].toString(),
    };
    final canonicalMap = <String, Map<String, dynamic>>{};
    final testIdList = testIds.toList();
    for (var i = 0; i < testIdList.length; i += 30) {
      final chunk = testIdList.sublist(
        i,
        (i + 30) > testIdList.length ? testIdList.length : i + 30,
      );
      final snap = await _db
          .collection('tests')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        canonicalMap[doc.id] = doc.data();
      }
    }

    final merged = <Map<String, dynamic>>[];
    final offeringById = <String, Map<String, dynamic>>{};

    for (final offering in offeringsSnap.docs) {
      final o = offering.data();
      final isLocal = o['isLocal'] == true;
      final testId = (o['testId'] ?? '').toString();

      Map<String, dynamic>? entry;

      if (isLocal) {
        entry = {
          'offeringId': offering.id,
          'testId': null,
          'isLocal': true,
          'isPackage': false,
          'code': (o['localCode'] ?? '').toString(),
          'name': (o['localName'] ?? '').toString(),
          'category': (o['localCategory'] ?? 'other').toString(),
          'sampleType': (o['localSampleType'] ?? 'other').toString(),
          'fastingRequired': o['localFastingRequired'] == true,
          'loincCode': null,
          'mrp': (o['mrp'] as num?)?.toDouble(),
          'offerPrice': (o['offerPrice'] as num?)?.toDouble(),
          'turnaroundHours': o['turnaroundHours'],
          'deptId': o['deptId'],
          'labClinicId': labClinicId,
          'active': o['active'] != false,
          'notes': o['notes'],
        };
      } else if (testId.isNotEmpty) {
        final c = canonicalMap[testId];
        if (c == null) continue;
        if (c['active'] != true) continue;

        final displayOverride = (o['displayName'] as String?)?.trim();
        final effectiveName =
            (displayOverride != null && displayOverride.isNotEmpty)
                ? displayOverride
                : (c['name'] ?? '').toString();

        entry = {
          'offeringId': offering.id,
          'testId': testId,
          'isLocal': false,
          'isPackage': false,
          'code': (c['code'] ?? '').toString(),
          'name': effectiveName,
          'category': (c['category'] ?? 'other').toString(),
          'sampleType': (c['sampleType'] ?? 'other').toString(),
          'fastingRequired': c['fastingRequired'] == true,
          'loincCode': c['loincCode'],
          'mrp': (o['mrp'] as num?)?.toDouble(),
          'offerPrice': (o['offerPrice'] as num?)?.toDouble(),
          'turnaroundHours': o['turnaroundHours'],
          'deptId': o['deptId'],
          'labClinicId': labClinicId,
          'active': o['active'] != false,
          'notes': o['notes'],
        };
      }

      if (entry != null) {
        final mrp = entry['mrp'] as double?;
        final offer = entry['offerPrice'] as double?;
        if (mrp != null && offer != null && mrp > 0) {
          entry['discount'] = (mrp - offer).clamp(0, mrp);
          entry['discountPercent'] =
              ((mrp - offer) / mrp * 100).round();
        } else {
          entry['discount'] = 0.0;
          entry['discountPercent'] = 0;
        }
        merged.add(entry);
        offeringById[offering.id] = entry;
      }
    }

    final packageEntries = <Map<String, dynamic>>[];
    for (final pkg in packagesSnap.docs) {
      final p = pkg.data();
      final includedIds =
          (p['includedTestOfferingIds'] as List?)?.cast<String>() ??
              const <String>[];
      final includedTests = <Map<String, dynamic>>[];
      for (final id in includedIds) {
        final entry = offeringById[id];
        if (entry != null) includedTests.add(entry);
      }
      if (includedTests.isEmpty) continue;

      double sumMrp = 0;
      double sumOffer = 0;
      var allHavePrice = true;
      for (final t in includedTests) {
        final mrp = t['mrp'] as double?;
        final offer = t['offerPrice'] as double?;
        if (mrp == null || offer == null) {
          allHavePrice = false;
          break;
        }
        sumMrp += mrp;
        sumOffer += offer;
      }

      final computedMrp = allHavePrice ? sumMrp : null;
      final computedOffer = allHavePrice ? sumOffer : null;
      final computedDiscount = (computedMrp != null &&
              computedOffer != null &&
              computedMrp > 0)
          ? (computedMrp - computedOffer).clamp(0, computedMrp)
          : 0.0;
      final computedDiscountPercent = (computedMrp != null &&
              computedOffer != null &&
              computedMrp > 0)
          ? ((computedMrp - computedOffer) / computedMrp * 100).round()
          : 0;

      final summary = includedTests
          .map((t) {
            final code = (t['code'] ?? '').toString();
            final name = (t['name'] ?? '').toString();
            return code.isNotEmpty ? code : name;
          })
          .where((s) => s.isNotEmpty)
          .join(', ');

      final patch = <String, dynamic>{};
      if (p['includedTestSummary'] != summary) {
        patch['includedTestSummary'] = summary;
      }
      if (p['computedMrp'] != computedMrp) {
        patch['computedMrp'] = computedMrp;
      }
      if (p['computedOfferPrice'] != computedOffer) {
        patch['computedOfferPrice'] = computedOffer;
      }
      if (p['computedDiscount'] != computedDiscount) {
        patch['computedDiscount'] = computedDiscount;
      }
      if (p['computedDiscountPercent'] != computedDiscountPercent) {
        patch['computedDiscountPercent'] = computedDiscountPercent;
      }
      if (patch.isNotEmpty) {
        await _packagesFor(labClinicId).doc(pkg.id).update(patch);
      }

      packageEntries.add({
        'packageId': pkg.id,
        'isPackage': true,
        'isLocal': false,
        'code': 'PKG',
        'name': (p['name'] ?? '').toString(),
        'description': (p['description'] ?? '').toString(),
        'category': 'package',
        'sampleType': 'multiple',
        'fastingRequired': false,
        'mrp': computedMrp,
        'offerPrice': computedOffer,
        'discount': computedDiscount,
        'discountPercent': computedDiscountPercent,
        'turnaroundHours': p['turnaroundHours'],
        'labClinicId': labClinicId,
        'includedTests': includedTests,
        'includedTestSummary': summary,
        'active': p['active'] != false,
      });
    }

    merged.sort((a, b) {
      final catA = (a['category'] ?? '').toString();
      final catB = (b['category'] ?? '').toString();
      final byCat = catA.compareTo(catB);
      if (byCat != 0) return byCat;
      return (a['code'] ?? '')
          .toString()
          .compareTo((b['code'] ?? '').toString());
    });

    final combined = <Map<String, dynamic>>[
      ...packageEntries,
      ...merged,
    ];

    await _clinics
        .doc(labClinicId)
        .collection('catalog')
        .doc('main')
        .set({
      'tests': combined,
      'count': combined.length,
      'testCount': merged.length,
      'packageCount': packageEntries.length,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // =================================================================
  // LAB ORDERS
  // =================================================================

  Future<double?> _resolvePricing({
    required String labClinicId,
    required List<LabTestItem> tests,
  }) async {
    if (tests.isEmpty) return 0;

    final snap = await _clinics
        .doc(labClinicId)
        .collection('catalog')
        .doc('main')
        .get();
    final raw = (snap.data()?['tests'] as List?) ?? const [];

    final byCode = <String, double>{};
    final byName = <String, double>{};
    for (final e in raw) {
      if (e is! Map) continue;
      final price = (e['offerPrice'] as num?)?.toDouble() ??
          (e['mrp'] as num?)?.toDouble();
      if (price == null || price <= 0) continue;
      final code = (e['code'] ?? '').toString().trim().toLowerCase();
      final name = (e['name'] ?? '').toString().trim().toLowerCase();
      if (code.isNotEmpty) byCode[code] = price;
      if (name.isNotEmpty) byName[name] = price;
    }

    var total = 0.0;
    for (final t in tests) {
      final c = (t.code ?? '').trim().toLowerCase();
      final n = t.name.trim().toLowerCase();
      final p = byCode[c] ?? byName[n];
      if (p == null) return null;
      total += p;
    }
    return total;
  }

  /// Builds sample groups from the order's tests, grouping by sample type
  /// using the lab's catalog. Assigns one sampleId per tube.
  /// Idempotent: if the order already has sampleGroups, returns them.
  Future<List<SampleGroup>> assignSampleIds({
    required String orderId,
    required String labClinicId,
  }) async {
    final orderRef = _orders.doc(orderId);
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw StateError('Lab order $orderId not found.');
    }
    final data = orderSnap.data() ?? {};

    final existingRaw = (data['sampleGroups'] as List?) ?? const [];
    if (existingRaw.isNotEmpty) {
      return existingRaw
          .map((e) =>
              SampleGroup.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    final catSnap = await _clinics
        .doc(labClinicId)
        .collection('catalog')
        .doc('main')
        .get();
    final catTests = ((catSnap.data()?['tests'] as List?) ?? const []);
    final sampleTypeByCode = <String, String>{};
    final sampleTypeByName = <String, String>{};
    for (final e in catTests) {
      if (e is! Map) continue;
      final code = (e['code'] ?? '').toString().toLowerCase().trim();
      final name = (e['name'] ?? '').toString().toLowerCase().trim();
      final st = (e['sampleType'] ?? 'other').toString().toLowerCase();
      if (code.isNotEmpty) sampleTypeByCode[code] = st;
      if (name.isNotEmpty) sampleTypeByName[name] = st;
    }

    final rawTests = (data['tests'] as List?) ?? const [];
    final byType = <String, List<String>>{};
    for (final t in rawTests) {
      final code = (t is Map ? t['code'] : null)?.toString();
      final name = (t is Map ? t['name'] : t).toString();
      final lookupCode = (code ?? '').toLowerCase().trim();
      final lookupName = name.toLowerCase().trim();
      final st = sampleTypeByCode[lookupCode] ??
          sampleTypeByName[lookupName] ??
          'other';
      byType.putIfAbsent(st, () => []).add(code ?? name);
    }

    final year = DateTime.now().year;
    final counterRef =
        _db.collection('counters').doc('sample_${year}_$labClinicId');

    final totalTubes = byType.length; // 1 tube per type by default
    if (totalTubes == 0) return const [];

    final startingNumbers =
        await _db.runTransaction<List<int>>((tx) async {
      final snap = await tx.get(counterRef);
      final current = (snap.data()?['count'] as num?)?.toInt() ?? 0;
      final next = current + totalTubes;
      tx.set(
        counterRef,
        {'count': next, 'year': year, 'labClinicId': labClinicId},
        SetOptions(merge: true),
      );
      return List.generate(totalTubes, (i) => current + 1 + i);
    });

    final suffixByType = <String, String>{
      'blood': 'B',
      'serum': 'B',
      'plasma': 'B',
      'urine': 'U',
      'stool': 'S',
      'sputum': 'P',
      'swab': 'W',
      'csf': 'C',
      'tissue': 'T',
      'other': 'X',
    };

    var idIndex = 0;
    final groups = <SampleGroup>[];
    for (final entry in byType.entries) {
      final st = entry.key;
      final testList = entry.value;
      final suffix = suffixByType[st] ?? 'X';
      final baseNum = startingNumbers[idIndex++];
      final baseStr = baseNum.toString().padLeft(4, '0');
      final sampleId = 'S-$year-$baseStr-$suffix';

      groups.add(SampleGroup(
        sampleType: st,
        barcodeSuffix: suffix,
        testCodes: testList,
        tubeCount: 1,
        sampleIds: [sampleId],
        printedAt: const [],
      ));
    }

    await orderRef.update({
      'sampleGroups': groups.map((g) => g.toMap()).toList(),
      'sampleGroupsAssignedAt': FieldValue.serverTimestamp(),
      'sampleGroupsAssignedByUid':
          FirebaseAuth.instance.currentUser?.uid,
    });
    return groups;
  }

  Future<String> createOrder({
    String? referringClinicId,
    required String labClinicId,
    required String labName,
    required String patientDocId,
    required String patientId,
    required String patientName,
    String? patientPhone,
    String? patientEmail,
    String? patientGender,
    DateTime? patientDob,
    String? patientBloodGroup,
    String? doctorDocId,
    String? doctorName,
    required List<LabTestItem> tests,
    String? instructions,
    String? referralNotes,
    String? appointmentId,
    String? deptId,
    double? billableAmount,
    double? catalogAmount,
    double? extraDiscount,
    String? referringClinicName,
    String? referringClinicPatientDocId,
    LabCustomerModel? existingCustomer,
  }) async {
    final ref = _orders.doc();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final hasReferral =
        referringClinicId != null && referringClinicId!.isNotEmpty;
    final hasDoctor = doctorDocId != null && doctorDocId!.isNotEmpty;
    final String referralType;
    final String customerSource;
    if (hasReferral && hasDoctor) {
      referralType = 'doctor_referral';
      customerSource = 'clinic_linked';
    } else if (hasReferral) {
      referralType = 'clinic_walkin';
      customerSource = 'clinic_linked';
    } else {
      referralType = 'direct_walkin';
      customerSource = 'direct';
    }

    String? customerDocId = existingCustomer?.docId;
    if (customerDocId == null && hasReferral) {
      final srcPatientDocId =
          referringClinicPatientDocId ?? patientDocId;
      customerDocId = LabCustomerModel.deterministicId(
        sourceClinicId: referringClinicId!,
        sourcePatientDocId: srcPatientDocId,
      );
      await _labCustomerService.upsertClinicLinked(
        labClinicId: labClinicId,
        sourceClinicId: referringClinicId,
        sourceClinicName: referringClinicName ?? '',
        sourcePatientDocId: srcPatientDocId,
        sourcePatientId: patientId,
        fullName: patientName,
        phone: patientPhone ?? '',
        gender: patientGender ?? 'male',
        email: patientEmail,
        dob: patientDob,
        bloodGroup: patientBloodGroup,
      );
    }

    final isWalkIn = !hasReferral && !hasDoctor;
    final double? resolvedAmount = isWalkIn
        ? ((billableAmount != null && billableAmount > 0)
            ? billableAmount
            : await _resolvePricing(labClinicId: labClinicId, tests: tests))
        : await _resolvePricing(labClinicId: labClinicId, tests: tests);

    await ref.set({
      'referringClinicId': referringClinicId,
      'labClinicId': labClinicId,
      'labName': labName,
      'deptId': deptId,
      'patientDocId': patientDocId,
      'patientId': patientId,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'doctorDocId': doctorDocId,
      'doctorName': doctorName,
      'appointmentId': appointmentId,
      'tests': tests.map((t) => t.toMap()).toList(),
      'instructions': instructions,
      'referralNotes': referralNotes,
      'status': 'ordered',
      'orderedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': uid,
      'billableAmount': resolvedAmount,
      'catalogAmount': catalogAmount,
      'extraDiscount': extraDiscount ?? 0,
      'paymentStatus': LabPaymentStatus.unpaid.name,
      'released': false,
      'labCustomerDocId': customerDocId,
      'customerSource': customerSource,
      'referralType': referralType,
    });

    if (customerDocId != null) {
      try {
        await _labCustomerService.recordOrderPlaced(customerDocId);
      } catch (_) {}
    }

    return ref.id;
  }

  Stream<List<LabOrderModel>> watchDoctorOrders({
    required String doctorDocId,
  }) {
    return _orders
        .where('doctorDocId', isEqualTo: doctorDocId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => LabOrderModel.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<LabOrderModel>> watchPatientOrders(String patientDocId) {
    return _orders
        .where('patientDocId', isEqualTo: patientDocId)
        .orderBy('orderedAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => LabOrderModel.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<List<LabOrderModel>> watchLabOrders({
    required String labClinicId,
    String? deptId,
    List<LabOrderStatus>? statuses,
  }) {
    Query<Map<String, dynamic>> q =
        _orders.where('labClinicId', isEqualTo: labClinicId);

    if (deptId != null && deptId.isNotEmpty) {
      q = q.where('deptId', isEqualTo: deptId);
    }

    if (statuses != null && statuses.isNotEmpty) {
      if (statuses.length == 1) {
        q = q.where('status', isEqualTo: statuses.first.name);
      } else {
        q = q.where('status',
            whereIn: statuses.map((s) => s.name).toList());
      }
    }

    return q.orderBy('orderedAt', descending: true).snapshots().map(
        (s) => s.docs
            .map((d) => LabOrderModel.fromMap(d.id, d.data()))
            .toList());
  }

  Future<void> updateStatus(String orderId, LabOrderStatus status) async {
    if (status == LabOrderStatus.ready) {
      throw StateError(
        'Use attachReport() to mark ready — a report must be uploaded first.',
      );
    }
    if (status == LabOrderStatus.delivered) {
      final snap = await _orders.doc(orderId).get();
      final released = snap.data()?['released'] == true;
      if (!released) {
        throw StateError(
          'Cannot mark delivered: report has not been released yet.',
        );
      }
    }
    final data = <String, dynamic>{
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
    };
    switch (status) {
      case LabOrderStatus.accepted:
        data['acceptedAt'] = FieldValue.serverTimestamp();
        break;
      case LabOrderStatus.sampleCollected:
        data['sampleCollectedAt'] = FieldValue.serverTimestamp();
        final snap = await _orders.doc(orderId).get();
        final existingGroups =
            (snap.data()?['sampleGroups'] as List?) ?? const [];
        if (existingGroups.isEmpty) {
          final labClinicId =
              (snap.data()?['labClinicId'] ?? '').toString();
          if (labClinicId.isNotEmpty) {
            try {
              final groups = await assignSampleIds(
                orderId: orderId,
                labClinicId: labClinicId,
              );
              data['sampleGroups'] =
                  groups.map((g) => g.toMap()).toList();
            } catch (_) {}
          }
        }
        break;
      case LabOrderStatus.processing:
        data['processingStartedAt'] = FieldValue.serverTimestamp();
        break;
      case LabOrderStatus.ready:
        data['reportReadyAt'] = FieldValue.serverTimestamp();
        break;
      case LabOrderStatus.delivered:
        data['deliveredAt'] = FieldValue.serverTimestamp();
        break;
      default:
        break;
    }
    await _orders.doc(orderId).update(data);
  }

  Future<void> forwardToTechnician({
    required String orderId,
    required String forwardedByUid,
    String? technicianUid,
  }) async {
    await _orders.doc(orderId).update({
      'status': LabOrderStatus.accepted.name,
      'acceptedAt': FieldValue.serverTimestamp(),
      'forwardedAt': FieldValue.serverTimestamp(),
      'forwardedByUid': forwardedByUid,
      if (technicianUid != null) 'assignedTechnicianUid': technicianUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': forwardedByUid,
    });
  }

  Future<void> cancelOrder(
    String orderId, {
    String? reason,
    String byRole = 'doctor',
  }) async {
    await _orders.doc(orderId).update({
      'status': LabOrderStatus.cancelled.name,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledByRole': byRole,
      'cancelReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  Future<void> markNoShow(String orderId, {String? reason}) async {
    await _orders.doc(orderId).update({
      'status': LabOrderStatus.noShow.name,
      'noShowAt': FieldValue.serverTimestamp(),
      'noShowReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  Future<void> attachReport({
    required String orderId,
    required String reportUrl,
    required String reportStoragePath,
    required String reportFileName,
  }) async {
    await _orders.doc(orderId).update({
      'reportUrl': reportUrl,
      'reportStoragePath': reportStoragePath,
      'reportFileName': reportFileName,
      'reportUploadedAt': FieldValue.serverTimestamp(),
      'reportUploadedByUid': FirebaseAuth.instance.currentUser?.uid,
      'status': 'ready',
      'reportReadyAt': FieldValue.serverTimestamp(),
      'released': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  Future<void> releaseReport({
    required String orderId,
    required String releasedByUid,
  }) async {
    final ref = _orders.doc(orderId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('Lab order $orderId not found.');
    }
    final m = snap.data() ?? {};
    final status = (m['status'] ?? '').toString();
    final reportUrl = (m['reportUrl'] ?? '').toString();
    final paymentStatus = (m['paymentStatus'] ?? 'unpaid').toString();
    final amount = (m['billableAmount'] as num?)?.toDouble() ?? 0;
    final alreadyReleased = m['released'] == true;

    if (alreadyReleased) return;
    if (status != 'ready') {
      throw StateError(
          'Cannot release: order is in status "$status", not "ready".');
    }
    if (reportUrl.isEmpty) {
      throw StateError('Cannot release: no report uploaded yet.');
    }
    if (amount <= 0) {
      throw StateError(
          'Cannot release: billable amount not set. Set the fee first.');
    }
    if (paymentStatus == 'unpaid') {
      throw StateError(
          'Cannot release: payment not settled. Mark paid or waived first.');
    }

    await ref.update({
      'released': true,
      'releasedAt': FieldValue.serverTimestamp(),
      'releasedByUid': releasedByUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': releasedByUid,
    });
  }

  Future<void> setBillableAmount({
    required String orderId,
    required double amount,
    required String setByUid,
  }) async {
    if (amount < 0) throw ArgumentError('Amount cannot be negative');
    await _orders.doc(orderId).update({
      'billableAmount': amount,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': setByUid,
    });
  }

  Future<void> markLabFeesPaid({
    required String orderId,
    required String collectedByUid,
  }) async {
    await _orders.doc(orderId).update({
      'paymentStatus': LabPaymentStatus.paid.name,
      'feesPaidAt': FieldValue.serverTimestamp(),
      'feesCollectedByUid': collectedByUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': collectedByUid,
    });
  }

  Future<void> waiveLabFees({
    required String orderId,
    required String collectedByUid,
  }) async {
    await _orders.doc(orderId).update({
      'paymentStatus': LabPaymentStatus.waived.name,
      'feesPaidAt': FieldValue.serverTimestamp(),
      'feesCollectedByUid': collectedByUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': collectedByUid,
    });
  }
}