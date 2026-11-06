import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/notification_settings_repository.dart';
import '../../../data/services/notification_service.dart';
import '../../../domain/entities/meal_plan.dart';

part 'meal_plan_notifications_sections.dart';

/// Page de configuration des notifications du plan de repas.
///
/// Peut être ouverte avec ou sans plan :
/// - Sans plan : configure l'heure et le décalage, sauvegarde en Firestore.
/// - Avec plan : idem + liste des jours activables + bouton pour planifier.
class MealPlanNotificationsPage extends StatefulWidget {
  /// Plan de repas courant. Peut être null si aucun plan n'existe.
  final MealPlan? mealPlan;

  const MealPlanNotificationsPage({super.key, this.mealPlan});

  @override
  State<MealPlanNotificationsPage> createState() =>
      _MealPlanNotificationsPageState();
}

const _purple = Color(0xFF6A5AE0);
const _purpleLight = Color(0xFFEDE8FF);
const _purpleSurface = Color(0xFFF5F3FF);

const _offsetOptions = [
  (label: '3 jours avant', value: -3),
  (label: '2 jours avant', value: -2),
  (label: 'La veille', value: -1),
  (label: 'Le jour même', value: 0),
];

class _MealPlanNotificationsPageState
    extends State<MealPlanNotificationsPage> {
  final _repo = NotificationSettingsRepository();

  TimeOfDay _notificationTime = const TimeOfDay(hour: 21, minute: 0);

  /// Décalage en jours par rapport au jour du repas.
  /// -3, -2, -1 (veille, défaut), 0 (jour même).
  int _offsetDays = -1;

  /// Activer les notifications pour tous les jours par défaut sur un nouveau plan.
  bool _defaultEnabled = true;

  late Set<int> _activeDays;
  bool _isLoading = true;
  bool _isSaving = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _activeDays = {};
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _repo.load();
      if (!mounted) return;
      setState(() {
        _notificationTime = settings.time;
        _offsetDays = settings.offsetDays;
        _defaultEnabled = settings.defaultNotificationsEnabled;
        if (widget.mealPlan != null) {
          final days = settings.effectiveNotificationDaysForPlan(
            widget.mealPlan!.id,
            widget.mealPlan!.durationDays,
          );
          _activeDays = {
            for (int i = 0; i < days.length; i++)
              if (days[i]) i,
          };
        }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DateTime _planDay(int dayIndex) =>
      widget.mealPlan!.startDate.add(Duration(days: dayIndex));

  DateTime _notifyDateTime(int dayIndex) {
    final notifyDay = _planDay(dayIndex).add(Duration(days: _offsetDays));
    return DateTime(
      notifyDay.year,
      notifyDay.month,
      notifyDay.day,
      _notificationTime.hour,
      _notificationTime.minute,
    );
  }

  bool _isNotificationInFuture(int dayIndex) =>
      _notifyDateTime(dayIndex).isAfter(DateTime.now());

  List<Meal> _mealsForDay(int dayIndex) {
    final d = _planDay(dayIndex);
    final target = DateTime(d.year, d.month, d.day);
    return widget.mealPlan!.meals.where((m) {
      final md = DateTime(m.date.year, m.date.month, m.date.day);
      return md == target;
    }).toList();
  }

  String _formatDate(DateTime date) =>
      DateFormat('EEE d MMM', 'fr_FR').format(date);

  String _formatNotifyDate(int dayIndex) {
    final notifyDay = _planDay(dayIndex).add(Duration(days: _offsetDays));
    return DateFormat('EEE d MMM', 'fr_FR').format(notifyDay);
  }

  int get _futureActiveDaysCount =>
      _activeDays.where(_isNotificationInFuture).length;

  String get _offsetLabel =>
      _offsetOptions.firstWhere((o) => o.value == _offsetDays).label;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _notificationTime,
      helpText: 'Heure de notification',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _purple,
            onPrimary: Colors.white,
            onSurface: Colors.black87,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _notificationTime = picked;
        if (widget.mealPlan != null) {
          _activeDays = _activeDays.where(_isNotificationInFuture).toSet();
        }
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final planId = widget.mealPlan?.id ?? '';
      final days = widget.mealPlan != null
          ? List.generate(
              widget.mealPlan!.durationDays,
              (i) => _activeDays.contains(i),
            )
          : const <bool>[];
      await _repo.save(NotificationSettings(
        time: _notificationTime,
        offsetDays: _offsetDays,
        notificationPlanId: planId,
        notificationDays: days,
        defaultNotificationsEnabled: _defaultEnabled,
      ));
      if (mounted) _showSnack('✅ Préférences sauvegardées.');
    } catch (e) {
      if (mounted) _showSnack('Erreur : $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _scheduleNotifications() async {
    final futureDays = _activeDays.where(_isNotificationInFuture).toSet();

    setState(() => _isSaving = true);
    try {
      final notifService = NotificationService();

      // Sauvegarder les préférences et les jours activés dans Firestore
      final days = List.generate(
        widget.mealPlan!.durationDays,
        (i) => _activeDays.contains(i),
      );
      await _repo.save(NotificationSettings(
        time: _notificationTime,
        offsetDays: _offsetDays,
        notificationPlanId: widget.mealPlan!.id,
        notificationDays: days,
        defaultNotificationsEnabled: _defaultEnabled,
      ));

      if (futureDays.isEmpty) {
        // Aucun jour actif : annuler les notifs existantes et quitter
        await notifService.cancelAllMealPlanNotifications();
        if (mounted) {
          _showSnack('✅ Préférences sauvegardées. Aucune notification programmée.');
          Navigator.of(context).pop(false);
        }
        return;
      }

      final granted = await notifService.requestPermissions();
      if (!granted) {
        if (mounted) {
          _showSnack(
            'Permission refusée. Activez les notifications dans les réglages.',
            isError: true,
          );
        }
        return;
      }

      // Demande la permission d'alarme exacte (Android 12+).
      // Ouvre "Alarmes & rappels" dans les paramètres si nécessaire.
      // Si refusée, on retombe sur le mode inexact — pas de crash.
      await notifService.requestExactAlarmPermission();

      await notifService.scheduleMealPlanNotifications(
        plan: widget.mealPlan!,
        notificationTime: _notificationTime,
        activeDays: futureDays,
        offsetDays: _offsetDays,
      );

      if (mounted) {
        _showSnack('✅ ${futureDays.length} notification(s) programmée(s) !');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) _showSnack('Erreur : $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Persiste immédiatement les jours activés dans notificationSettings Firestore.
  Future<void> _persistNotificationDays() async {
    if (widget.mealPlan == null || widget.mealPlan!.id.isEmpty) return;
    await _repo.saveNotificationDays(
      widget.mealPlan!.id,
      List.generate(
        widget.mealPlan!.durationDays,
        (i) => _activeDays.contains(i),
      ),
    );
  }

  Future<void> _cancelAll() async {
    await NotificationService().cancelAllMealPlanNotifications();
    if (mounted) {
      _showSnack('Toutes les notifications du plan ont été annulées.');
      if (widget.mealPlan != null) Navigator.of(context).pop(false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(message, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: isError ? Colors.red[700] : _purple,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _purpleSurface,
        body: Center(child: CircularProgressIndicator(color: _purple)),
      );
    }

    final hasPlan = widget.mealPlan != null;

    return Scaffold(
      backgroundColor: _purpleSurface,
      appBar: AppBar(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Notifications du plan',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                _buildHeader(hasPlan),
                const SizedBox(height: 16),
                _buildDefaultToggle(),
                const SizedBox(height: 16),
                _buildTimePicker(),
                const SizedBox(height: 16),
                _buildOffsetSelector(),
                if (hasPlan) ...[
                  const SizedBox(height: 16),
                  _buildSelectAllRow(),
                  const SizedBox(height: 12),
                  ...List.generate(
                    widget.mealPlan!.durationDays,
                    (i) => _buildDayCard(i),
                  ),
                ],
              ],
            ),
          ),
          _buildBottomBar(hasPlan),
        ],
      ),
    );
  }


}
