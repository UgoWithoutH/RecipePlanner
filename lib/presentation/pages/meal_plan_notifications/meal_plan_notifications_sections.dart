// ignore_for_file: invalid_use_of_protected_member
part of 'meal_plan_notifications_page.dart';

extension _MealPlanNotificationsSections on _MealPlanNotificationsPageState {
  Widget _buildHeader(bool hasPlan) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _purpleLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _purple.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notifications_active_outlined,
              color: _purple, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rappels du plan de repas',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: _purple,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasPlan
                      ? 'Configurez l\'heure et le moment de réception, puis activez les jours souhaités.'
                      : 'Configurez vos préférences. Elles seront appliquées lors de votre prochain plan.',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker() {
    final timeStr =
        '${_notificationTime.hour.toString().padLeft(2, '0')}:${_notificationTime.minute.toString().padLeft(2, '0')}';

    return _card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: _iconBox(Icons.access_time_rounded),
        title: Text(
          'Heure de notification',
          style:
              GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          'Heure à laquelle vous recevrez la notification',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
        ),
        trailing: GestureDetector(
          onTap: _pickTime,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _purple,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              timeStr,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOffsetSelector() {
    return _card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconBox(Icons.schedule_rounded),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quand recevoir la notification ?',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        'Par rapport au jour du repas',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.black45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _offsetOptions.map((opt) {
                final selected = _offsetDays == opt.value;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _offsetDays = opt.value;
                      if (widget.mealPlan != null) {
                        _activeDays = _activeDays
                            .where(_isNotificationInFuture)
                            .toSet();
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? _purple : _purpleLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? _purple : _purple.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      opt.label,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : _purple,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _purpleSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _purple.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 15, color: _purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Exemple : pour le repas du mardi, notification '
                      '$_offsetLabel à '
                      '${_notificationTime.hour.toString().padLeft(2, '0')}:'
                      '${_notificationTime.minute.toString().padLeft(2, '0')}.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultToggle() {
    return _card(
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        secondary: _iconBox(Icons.notifications_outlined),
        title: Text(
          'Activer par défaut',
          style:
              GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          'Lorsqu\'un nouveau plan s\'ouvre, toutes les notifications sont '
          '${_defaultEnabled ? 'activées' : 'désactivées'} par défaut.',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
        ),
        value: _defaultEnabled,
        activeColor: _purple,
        onChanged: (value) => setState(() => _defaultEnabled = value),
      ),
    );
  }

  Widget _buildSelectAllRow() {
    final allFutureDays =
        List.generate(widget.mealPlan!.durationDays, (i) => i)
            .where(_isNotificationInFuture)
            .toSet();
    final allSelected = allFutureDays.isNotEmpty &&
        allFutureDays.every(_activeDays.contains);

    return Row(
      children: [
        Text(
          '$_futureActiveDaysCount rappel(s) sélectionné(s)',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () {
            setState(() {
              if (allSelected) {
                _activeDays.clear();
              } else {
                _activeDays = Set.from(allFutureDays);
              }
            });
          },
          style: TextButton.styleFrom(
            foregroundColor: _purple,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
          child: Text(
            allSelected ? 'Tout désactiver' : 'Tout activer',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildDayCard(int dayIndex) {
    final planDay = _planDay(dayIndex);
    final meals = _mealsForDay(dayIndex);
    final lunch = meals.where((m) => m.type == MealType.lunch).firstOrNull;
    final dinner = meals.where((m) => m.type == MealType.dinner).firstOrNull;
    final isPast = !_isNotificationInFuture(dayIndex);
    final isActive = _activeDays.contains(dayIndex);
    final notifyDate = _formatNotifyDate(dayIndex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isPast ? 0.45 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isActive && !isPast
                ? Border.all(color: _purple.withOpacity(0.5), width: 1.5)
                : Border.all(color: Colors.transparent),
            boxShadow: [
              BoxShadow(
                color: _purple.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isActive && !isPast ? _purple : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'J${dayIndex + 1}',
                        style: GoogleFonts.poppins(
                          color: isActive && !isPast
                              ? Colors.white
                              : Colors.black45,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(planDay),
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          if (!isPast)
                            Text(
                              '🔔 Notif. le $notifyDate à '
                              '${_notificationTime.hour.toString().padLeft(2, '0')}:'
                              '${_notificationTime.minute.toString().padLeft(2, '0')} '
                              '($_offsetLabel)',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: Colors.black45),
                            )
                          else
                            Text(
                              '⏩ Date passée – notification ignorée',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: Colors.orange[700]),
                            ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isActive && !isPast,
                      onChanged: isPast
                          ? null
                          : (val) {
                              setState(() {
                                if (val) {
                                  _activeDays.add(dayIndex);
                                } else {
                                  _activeDays.remove(dayIndex);
                                }
                              });
                            },
                      activeColor: _purple,
                    ),
                  ],
                ),
              ),
              if (meals.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 16),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (lunch != null)
                        _mealRow('🥗', 'Déjeuner', lunch.recipe.title,
                            lunch.isLeftoverMeal),
                      if (dinner != null)
                        _mealRow('🍲', 'Dîner', dinner.recipe.title,
                            dinner.isLeftoverMeal),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const Text('❄️',
                                style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Rappel : pensez à décongeler si nécessaire',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Text(
                    'Aucun repas planifié pour ce jour.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.black38),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mealRow(
      String emoji, String label, String title, bool isLeftover) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            '$label : ',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLeftover)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Text(
                      'Restes',
                      style: GoogleFonts.poppins(
                          fontSize: 10, color: Colors.orange[700]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool hasPlan) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _purple,
                  side: const BorderSide(color: _purple),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Annuler',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : (hasPlan ? _scheduleNotifications : _saveSettings),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Sauvegarder',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _purple.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _iconBox(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _purpleLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: _purple, size: 22),
    );
  }
}
