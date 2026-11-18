import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/unit.dart';
import 'group_repository.dart';

/// Persists the units and unit conversions of the current group in Firestore
/// (`units` and `unit_conversions` collections) and keeps [UnitRegistry] in sync.
class FirebaseUnitRepository {
  final CollectionReference _units =
      FirebaseFirestore.instance.collection('units');
  final CollectionReference _conversions =
      FirebaseFirestore.instance.collection('unit_conversions');

  Future<String?> _getGroupId() => GroupRepository.instance.getCurrentGroupId();

  /// Loads the group's units/conversions into [UnitRegistry].
  /// If the group has no unit yet, the common units and conversions are created first.
  Future<void> load() async {
    final groupId = await _getGroupId();
    if (groupId == null) return;

    var unitSnap = await _units.where('groupId', isEqualTo: groupId).get();
    if (unitSnap.docs.isEmpty) {
      await _seedDefaults(groupId);
      unitSnap = await _units.where('groupId', isEqualTo: groupId).get();
    }
    final conversionSnap =
        await _conversions.where('groupId', isEqualTo: groupId).get();

    final units = unitSnap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final code = data['code'] as String? ?? '';
      return Unit(code, data['label'] as String? ?? code);
    }).where((u) => u.name.isNotEmpty).toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    final conversions = conversionSnap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return UnitConversion(
        id: doc.id,
        fromCode: data['fromCode'] as String? ?? '',
        toCode: data['toCode'] as String? ?? '',
        factor: (data['factor'] as num?)?.toDouble() ?? 0,
        autoConvert: data['autoConvert'] as bool? ?? false,
      );
    }).toList();

    UnitRegistry.configure(units: units, conversions: conversions);
  }

  Future<void> _seedDefaults(String groupId) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final u in Unit.defaults) {
      batch.set(_units.doc('${groupId}_${u.name}'), {
        'groupId': groupId,
        'code': u.name,
        'label': u.label,
      });
    }
    for (final c in UnitConversion.defaults) {
      batch.set(_conversions.doc(_conversionId(groupId, c.fromCode, c.toCode)), {
        'groupId': groupId,
        'fromCode': c.fromCode,
        'toCode': c.toCode,
        'factor': c.factor,
        'autoConvert': c.autoConvert,
      });
    }
    await batch.commit();
  }

  String _conversionId(String groupId, String from, String to) =>
      '${groupId}_${from}_$to';

  static String _slug(String label) {
    const accents = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'î': 'i', 'ï': 'i', 'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'œ': 'oe',
    };
    final buffer = StringBuffer();
    for (final ch in label.toLowerCase().trim().split('')) {
      buffer.write(accents[ch] ?? ch);
    }
    final slug = buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return slug.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Creates a unit with the given display [label]. Returns false if a unit
  /// with the same label already exists.
  Future<bool> addUnit(String label) async {
    final groupId = await _getGroupId();
    if (groupId == null) return false;
    final trimmed = label.trim();
    if (trimmed.isEmpty) return false;
    if (Unit.values.any((u) => u.label.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }

    final base = _slug(trimmed).isEmpty ? 'unit' : _slug(trimmed);
    var code = base;
    var i = 2;
    while (Unit.byName(code) != null) {
      code = '${base}_$i';
      i++;
    }
    await _units.doc('${groupId}_$code').set({
      'groupId': groupId,
      'code': code,
      'label': trimmed,
    });
    await load();
    return true;
  }

  /// Renames a unit (its code, used by existing data, never changes).
  /// Returns false if another unit already uses this label.
  Future<bool> updateUnit(String code, String label) async {
    final groupId = await _getGroupId();
    if (groupId == null) return false;
    final trimmed = label.trim();
    if (trimmed.isEmpty) return false;
    if (Unit.values.any((u) =>
        u.name != code && u.label.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }
    await _units.doc('${groupId}_$code').update({'label': trimmed});
    await load();
    return true;
  }

  /// Deletes a unit and every conversion that references it.
  Future<void> deleteUnit(String code) async {
    final groupId = await _getGroupId();
    if (groupId == null) return;
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_units.doc('${groupId}_$code'));
    for (final c in UnitRegistry.conversions) {
      if (c.fromCode == code || c.toCode == code) {
        batch.delete(_conversions.doc(c.id));
      }
    }
    await batch.commit();
    await load();
  }

  /// Creates or updates the conversion "1 [fromCode] = [factor] [toCode]".
  /// The conversion is stored with the larger unit as `from` (factor ≥ 1).
  /// [replaceId] is the id of the conversion being edited, if any.
  /// Returns false when the conversion is invalid or would duplicate another.
  Future<bool> saveConversion({
    String? replaceId,
    required String fromCode,
    required String toCode,
    required double factor,
    required bool autoConvert,
  }) async {
    final groupId = await _getGroupId();
    if (groupId == null) return false;
    if (fromCode == toCode || factor <= 0 || factor.isNaN || factor.isInfinite) {
      return false;
    }
    if (factor < 1) {
      final tmp = fromCode;
      fromCode = toCode;
      toCode = tmp;
      factor = 1 / factor;
    }
    final id = _conversionId(groupId, fromCode, toCode);
    final reverseId = _conversionId(groupId, toCode, fromCode);
    final duplicate = UnitRegistry.conversions.any(
        (c) => (c.id == id || c.id == reverseId) && c.id != replaceId);
    if (duplicate) return false;

    final batch = FirebaseFirestore.instance.batch();
    if (replaceId != null && replaceId != id) {
      batch.delete(_conversions.doc(replaceId));
    }
    batch.set(_conversions.doc(id), {
      'groupId': groupId,
      'fromCode': fromCode,
      'toCode': toCode,
      'factor': factor,
      'autoConvert': autoConvert,
    });
    await batch.commit();
    await load();
    return true;
  }

  Future<void> deleteConversion(String id) async {
    await _conversions.doc(id).delete();
    await load();
  }
}
