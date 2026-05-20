import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Iconografía unificada (Phosphor Icons 2.0.0) para MatchGol Stats.
abstract final class AppIcons {
  static const Color accent = Color(0xFF00E650);
  static const Color accentAlt = Color(0xFF00C853);

  static final _s = PhosphorIcons.regular;
  static final _fill = PhosphorIcons.fill;

  static Widget phosphor(
    PhosphorIconData icon, {
    double size = 24,
    Color? color,
  }) =>
      PhosphorIcon(icon, size: size, color: color ?? accent);

  /// Ícono de cada sección del hub Liga (`_selectedIndex`).
  static PhosphorIconData ligaSection(int index) {
    switch (index) {
      case 0:
        return _s.soccerBall;
      case 1:
        return _s.table;
      case 2:
        return _s.sneaker;
      case 3:
        return _s.hand;
      case 4:
        return _s.calendar;
      case 5:
        return _s.broadcast;
      case 6:
        return _s.chartLineUp;
      case 7:
        return _s.globeHemisphereWest;
      case 8:
        return _s.newspaper;
      case 9:
        return _fill.trophy;
      case 10:
        return _fill.medal;
      case 11:
        return _s.warning;
      case 12:
        return _s.prohibit;
      case 13:
        return _s.chartPie;
      case 14:
        return _s.trendDown;
      case 15:
        return _fill.trophy;
      case 16:
        return _s.trendUp;
      case 17:
        return _s.bandaids;
      case 18:
        return _s.usersThree;
      case 19:
        return _s.gavel;
      default:
        return _s.circle;
    }
  }

  // Dashboard principal
  static PhosphorIconData get torneos => _fill.trophy;
  static PhosphorIconData get mundial => _fill.globeHemisphereWest;
  static PhosphorIconData get noticias => _s.newspaper;
  static PhosphorIconData get tablaHinchas => _fill.usersThree;

  // Pantalla Torneos
  static PhosphorIconData get ligaArgentina => _fill.flag;
  static PhosphorIconData get copaArgentina => _fill.trophy;
  static PhosphorIconData get libertadores => _fill.crown;
  static PhosphorIconData get sudamericana => _fill.medal;
  static PhosphorIconData get ligaInternacional => _s.globe;

  // Navegación / UI
  static PhosphorIconData get home => _s.house;
  static PhosphorIconData get back => _s.caretLeft;
  static PhosphorIconData get cuenta => _s.userCircle;
  static PhosphorIconData get chevron => _s.caretRight;
  static PhosphorIconData get enVivo => _fill.broadcast;
  static PhosphorIconData get tablaMoral => _s.brain;
}
