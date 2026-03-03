import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Paramètres de notification persistés dans Firestore.
class NotificationSettings {
  /// Heure d'envoi de la notification.
  final TimeOfDay time;

  /// Décalage en jours par rapport au jour du repas.
  /// -1 = la veille (défaut), 0 = le jour même, -2 = 2 jours avant, etc.
  final int offsetDays;

  /// Identifiant du plan de repas auquel correspondent [notificationDays].
  /// Vide si aucun plan n'a encore été configuré.
  final String notificationPlanId;

  /// Liste par jour du plan : true = notification activée.
  /// Vide ou longueur différente de celle du plan → tout true par défaut.
  final List<bool> notificationDays;

  /// Comportement par défaut lors de l'ouverture d'un nouveau plan :
  /// true = toutes les notifications activées, false = toutes désactivées.
  final bool defaultNotificationsEnabled;

  const NotificationSettings({
    required this.time,
    this.offsetDays = -1,
    this.notificationPlanId = '',
    this.notificationDays = const [],
    this.defaultNotificationsEnabled = true,
  });

  /// Retourne la liste normalisée pour le plan [planId] de [durationDays] jours.
  /// Si le planId ne correspond pas ou si la longueur diffère, utilise [defaultNotificationsEnabled].
  List<bool> effectiveNotificationDaysForPlan(String planId, int durationDays) {
    if (notificationPlanId == planId &&
        notificationDays.length == durationDays) {
      return notificationDays;
    }
    return List.filled(durationDays, defaultNotificationsEnabled);
  }
}

/// Persiste les préférences de notification dans Firestore
/// sous `notificationSettings/{uid}`.
class NotificationSettingsRepository {
  static const _collection = 'notificationSettings';

  final FirebaseFirestore _db;

  NotificationSettingsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> save(NotificationSettings settings) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection(_collection).doc(uid).set({
      'hour': settings.time.hour,
      'minute': settings.time.minute,
      'offsetDays': settings.offsetDays,
      'notificationPlanId': settings.notificationPlanId,
      'notificationDays': settings.notificationDays,
      'defaultNotificationsEnabled': settings.defaultNotificationsEnabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Persiste uniquement les jours activés pour un plan donné.
  Future<void> saveNotificationDays(
      String planId, List<bool> days) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection(_collection).doc(uid).set({
      'notificationPlanId': planId,
      'notificationDays': days,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Écrit les valeurs par défaut dans Firestore si aucun document n'existe encore.
  /// Appelée à chaque ouverture de l'app — sans effet si les préférences existent déjà.
  Future<void> initializeDefaults() async {
    final uid = _uid;
    if (uid == null) return;
    final doc = await _db.collection(_collection).doc(uid).get();
    if (!doc.exists) {
      await _db.collection(_collection).doc(uid).set({
        'hour': 21,
        'minute': 0,
        'offsetDays': -1,
        'notificationPlanId': '',
        'notificationDays': <bool>[],
        'defaultNotificationsEnabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Retourne les paramètres sauvegardés, ou les valeurs par défaut.
  Future<NotificationSettings> load() async {
    final uid = _uid;
    if (uid != null) {
      final doc = await _db.collection(_collection).doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final hour = data['hour'] as int?;
        final minute = data['minute'] as int?;
        final offset = data['offsetDays'] as int? ?? -1;
        final planId = data['notificationPlanId'] as String? ?? '';
        final rawDays = data['notificationDays'] as List<dynamic>?;
        final days = rawDays?.map((e) => e as bool? ?? true).toList() ?? [];
        final defaultEnabled =
            data['defaultNotificationsEnabled'] as bool? ?? true;
        if (hour != null && minute != null) {
          return NotificationSettings(
            time: TimeOfDay(hour: hour, minute: minute),
            offsetDays: offset,
            notificationPlanId: planId,
            notificationDays: days,
            defaultNotificationsEnabled: defaultEnabled,
          );
        }
      }
    }
    return const NotificationSettings(
      time: TimeOfDay(hour: 21, minute: 0),
      offsetDays: -1,
    );
  }
}
