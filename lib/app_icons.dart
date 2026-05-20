import 'package:flutter/material.dart';

/// Iconografía unificada (Material Icons) para MatchGol Stats.
abstract final class AppIcons {
  static const Color accent = Color(0xFF00E650);
  static const Color accentAlt = Color(0xFF00C853);

  static Widget icon(
    IconData icon, {
    double size = 24,
    Color? color,
  }) =>
      Icon(icon, size: size, color: color ?? accent);

  /// Ícono de cada sección del hub Liga (`_selectedIndex`).
  static IconData ligaSection(int index) {
    switch (index) {
      case 0:
        return Icons.sports_soccer;
      case 1:
        return Icons.leaderboard;
      case 2:
        return Icons.sports;
      case 3:
        return Icons.sports_handball;
      case 4:
        return Icons.calendar_today;
      case 5:
        return Icons.live_tv;
      case 6:
        return Icons.show_chart;
      case 7:
        return Icons.public;
      case 8:
        return Icons.newspaper;
      case 9:
        return Icons.emoji_events;
      case 10:
        return Icons.military_tech;
      case 11:
        return Icons.warning_amber;
      case 12:
        return Icons.block;
      case 13:
        return Icons.pie_chart;
      case 14:
        return Icons.trending_down;
      case 15:
        return Icons.emoji_events;
      case 16:
        return Icons.trending_up;
      case 17:
        return Icons.healing;
      case 18:
        return Icons.groups;
      case 19:
        return Icons.gavel;
      default:
        return Icons.circle_outlined;
    }
  }

  // Dashboard principal
  static const IconData torneos = Icons.emoji_events;
  static const IconData mundial = Icons.public;
  static const IconData noticias = Icons.newspaper;
  static const IconData tablaHinchas = Icons.groups;

  // Pantalla Torneos
  static const IconData ligaArgentina = Icons.flag;
  static const IconData copaArgentina = Icons.emoji_events;
  static const IconData libertadores = Icons.workspace_premium;
  static const IconData sudamericana = Icons.military_tech;
  static const IconData ligaInternacional = Icons.language;

  // Navegación / UI
  static const IconData home = Icons.home;
  static const IconData back = Icons.arrow_back;
  static const IconData cuenta = Icons.account_circle;
  static const IconData chevron = Icons.chevron_right;
  static const IconData enVivo = Icons.sensors;
  static const IconData tablaMoral = Icons.psychology;
}
