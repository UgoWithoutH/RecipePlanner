/// Formate une quantité numérique pour l'affichage.
/// - Entiers : "1", "2", "500"
/// - Décimaux : "1.5", "0.25", "1.75" (max 2 décimales, zéros finaux supprimés)
String fmtQty(double qty) {
  if (qty == qty.truncateToDouble()) return qty.toInt().toString();
  final s = qty.toStringAsFixed(2);
  return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

/// Parse une saisie utilisateur en double en acceptant virgule et point.
/// Retourne [fallback] si la valeur ne peut pas être parsée.
double parseQty(String text, {double fallback = 0.0}) {
  return double.tryParse(text.trim().replaceAll(',', '.')) ?? fallback;
}
