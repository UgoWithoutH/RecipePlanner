import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../domain/entities/meal_plan.dart';

/// Service singleton gérant la planification des notifications locales
/// pour les rappels du plan de repas.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'meal_plan_reminders';
  static const String _channelName = 'Rappels du plan de repas';
  static const String _channelDescription =
      'Notifications de rappel pour préparer les repas à venir';
  static const int _notificationBaseId = 1000;

  // ─────────────────────────────────────────────────────────────────────────
  // Initialisation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;

    // Fuseau horaire local
    tz_data.initializeTimeZones();
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (_) {
      // Fallback : UTC si la résolution échoue
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Crée le canal Android (API 26+)
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );

    _initialized = true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Permissions
  // ─────────────────────────────────────────────────────────────────────────

  /// Demande la permission de notification (POST_NOTIFICATIONS sur Android 13+).
  /// Ne demande PAS la permission d'alarme exacte pour ne pas ouvrir
  /// les paramètres système silencieusement lors de l'auto-planification.
  /// Retourne `true` si les permissions sont accordées.
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true;
  }

  /// Demande la permission d'alarme exacte (Android 12+).
  /// À appeler uniquement depuis un flux initialisé par l'utilisateur
  /// (ex : bouton "Sauvegarder" de la page notifications), car cela
  /// peut ouvrir l'écran "Alarmes & rappels" des paramètres système.
  /// En cas de refus, scheduleMealPlanNotifications() retombe sur le mode
  /// inexact automatiquement — aucun crash.
  Future<void> requestExactAlarmPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Planification
  // ─────────────────────────────────────────────────────────────────────────

  /// Planifie une notification la veille au soir pour chaque jour sélectionné.
  ///
  /// [activeDays] : indices des jours du plan (0 = premier jour) à notifier.
  /// La notification se déclenche à [notificationTime] le jour J-1 et annonce
  /// les repas du jour J (déjeuner + dîner) ainsi que les ingrédients à
  /// décongeler si nécessaire.
  Future<void> scheduleMealPlanNotifications({
    required MealPlan plan,
    required TimeOfDay notificationTime,
    required Set<int> activeDays,
    int offsetDays = -1,
  }) async {
    await cancelAllMealPlanNotifications();

    // Android 12+ : utilise exactAllowWhileIdle si la permission est accordée,
    // sinon tombe sur inexactAllowWhileIdle pour éviter la PlatformException.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canExact = android != null
        ? (await android.canScheduleExactNotifications() ?? false)
        : true;
    final scheduleMode = canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final now = DateTime.now();

    for (final dayIndex in activeDays) {
      final planDay = plan.startDate.add(Duration(days: dayIndex));
      final notifyDay = planDay.add(Duration(days: offsetDays));

      final notifyDateTime = DateTime(
        notifyDay.year,
        notifyDay.month,
        notifyDay.day,
        notificationTime.hour,
        notificationTime.minute,
      );

      // Ignore les notifications déjà passées
      if (notifyDateTime.isBefore(now)) continue;

      final mealsForDay = _mealsForDate(plan, planDay);
      if (mealsForDay.isEmpty) continue;

      final title = _buildTitle(planDay, offsetDays);
      final body = _buildBody(mealsForDay);

      final tzDateTime = tz.TZDateTime.from(notifyDateTime, tz.local);

      await _plugin.zonedSchedule(
        _notificationBaseId + dayIndex,
        title,
        body,
        tzDateTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Annule toutes les notifications du plan de repas.
  Future<void> cancelAllMealPlanNotifications() async {
    for (int i = 0; i < 60; i++) {
      await _plugin.cancel(_notificationBaseId + i);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  List<Meal> _mealsForDate(MealPlan plan, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return plan.meals.where((m) {
      final md = DateTime(m.date.year, m.date.month, m.date.day);
      return md == d;
    }).toList();
  }

  String _buildTitle(DateTime planDay, int offsetDays) {
    final dayName = _frenchWeekday(planDay.weekday);
    final formatted =
        '${planDay.day.toString().padLeft(2, '0')}/${planDay.month.toString().padLeft(2, '0')}';
    final String when;
    if (offsetDays == 0) {
      when = "Repas d'aujourd'hui";
    } else if (offsetDays == -1) {
      when = 'Repas de demain';
    } else if (offsetDays < -1) {
      when = 'Repas dans ${-offsetDays} jours';
    } else {
      when = 'Repas d\'hier';
    }
    return '🍽️ $when – $dayName $formatted';
  }

  String _buildBody(List<Meal> meals) {
    final lunch =
        meals.where((m) => m.type == MealType.lunch).firstOrNull;
    final dinner =
        meals.where((m) => m.type == MealType.dinner).firstOrNull;

    final lines = <String>[];
    if (lunch != null) lines.add('🥗 Déjeuner : ${lunch.recipe.title}');
    if (dinner != null) lines.add('🍲 Dîner : ${dinner.recipe.title}');
    lines.add('❄️ Pensez à décongeler les aliments si nécessaire.');

    return lines.join('\n');
  }

  String _frenchWeekday(int weekday) {
    const days = [
      '',
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche',
    ];
    return days[weekday];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Aperçu (pour l'interface)
  // ─────────────────────────────────────────────────────────────────────────

  /// Retourne le contenu prévisualisé d'une notification pour un jour donné.
  /// Utile pour afficher un aperçu dans la page de configuration.
  ({String title, String body}) previewForDay(
    MealPlan plan,
    int dayIndex, {
    int offsetDays = -1,
  }) {
    final planDay = plan.startDate.add(Duration(days: dayIndex));
    final meals = _mealsForDate(plan, planDay);
    return (
      title: _buildTitle(planDay, offsetDays),
      body: _buildBody(meals),
    );
  }
}
