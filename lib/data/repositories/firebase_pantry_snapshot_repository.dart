import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/unit.dart';
import '../../domain/entities/pantry_item.dart';
import 'group_repository.dart';

/// Représente un item figé dans le snapshot frigo/placard du plan.
class PantrySnapshotItem {
  final String name;
  final double quantity;
  final Unit unit;
  final bool isUrgent;
  final String typeName;

  const PantrySnapshotItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.isUrgent,
    required this.typeName,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'quantity': quantity,
        'unit': unit.name,
        'isUrgent': isUrgent,
        'typeName': typeName,
      };

  factory PantrySnapshotItem.fromMap(Map<String, dynamic> map) {
    return PantrySnapshotItem(
      name: map['name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: Unit.values.firstWhere(
        (u) => u.name == (map['unit'] as String?),
        orElse: () => Unit.piece,
      ),
      isUrgent: map['isUrgent'] as bool? ?? false,
      typeName: map['typeName'] as String? ?? '',
    );
  }

  factory PantrySnapshotItem.fromPantryItem(PantryItem item) {
    return PantrySnapshotItem(
      name: item.name,
      quantity: item.quantity,
      unit: item.unit,
      isUrgent: item.isUrgent,
      typeName: item.typeName,
    );
  }
}

/// Gère la collection `pantry_snapshots` — un seul document par groupe,
/// figé au moment de la génération du plan.
class FirebasePantrySnapshotRepository {
  FirebasePantrySnapshotRepository._();
  static final instance = FirebasePantrySnapshotRepository._();

  final CollectionReference _col =
      FirebaseFirestore.instance.collection('pantry_snapshots');

  Future<String> _groupId() async {
    final id = await GroupRepository.instance.getCurrentGroupId();
    if (id == null) throw Exception('Aucun groupe trouvé.');
    return id;
  }

  /// Remplace l'éventuel snapshot existant par un nouveau basé sur [items].
  /// Appelé juste après la génération d'un plan.
  Future<void> save(List<PantryItem> items) async {
    final gid = await _groupId();
    await _col.doc(gid).set({
      'groupId': gid,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'items': items.map((i) => PantrySnapshotItem.fromPantryItem(i).toMap()).toList(),
    });
  }

  /// Retourne les items du snapshot courant, ou une liste vide si inexistant.
  Future<List<PantrySnapshotItem>> get() async {
    final gid = await _groupId();
    final doc = await _col.doc(gid).get();
    if (!doc.exists) return [];
    final data = doc.data() as Map<String, dynamic>;
    final rawItems = data['items'] as List<dynamic>? ?? [];
    return rawItems
        .map((e) => PantrySnapshotItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Supprime le snapshot (ex : lors de la suppression d'un plan).
  Future<void> delete() async {
    final gid = await _groupId();
    await _col.doc(gid).delete();
  }
}
