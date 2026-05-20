import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Iconografía unificada (Phosphor Icons) para MatchGol Stats.
abstract final class AppIcons {
  static const Color accent = Color(0xFF00E650);
  static const Color accentAlt = Color(0xFF00C853);

  static const _s = PhosphorIconsStyle.regular;
  static const _fill = PhosphorIconsStyle.fill;

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
        return PhosphorIcons.soccerBall(_s);
      case 1:
        return PhosphorIcons.table(_s);
      case 2:
        return PhosphorIcons.sneaker(_s);
      case 3:
        return PhosphorIcons.hand(_s);
      case 4:
        return PhosphorIcons.calendarDots(_s);
      case 5:
        return PhosphorIcons.broadcast(_s);
      case 6:
        return PhosphorIcons.chartLineUp(_s);
      case 7:
        return PhosphorIcons.globeHemisphereWest(_s);
      case 8:
        return PhosphorIcons.newspaper(_s);
      case 9:
        return PhosphorIcons.trophy(_fill);
      case 10:
        return PhosphorIcons.medal(_fill);
      case 11:
        return PhosphorIcons.warning(_s);
      case 12:
        return PhosphorIcons.prohibit(_s);
      case 13:
        return PhosphorIcons.chartPie(_s);
      case 14:
        return PhosphorIcons.trendDown(_s);
      case 15:
        return PhosphorIcons.trophy(_fill);
      case 16:
        return PhosphorIcons.trendUp(_s);
      case 17:
        return PhosphorIcons.bandaids(_s);
      case 18:
        return PhosphorIcons.usersThree(_s);
      case 19:
        return PhosphorIcons.gavel(_s);
      default:
        return PhosphorIcons.circle(_s);
    }
  }

  // Dashboard principal
  static PhosphorIconData get torneos => PhosphorIcons.trophy(_fill);
  static PhosphorIconData get mundial => PhosphorIcons.globeHemisphereWest(_fill);
  static PhosphorIconData get noticias => PhosphorIcons.newspaper(_s);
  static PhosphorIconData get tablaHinchas => PhosphorIcons.usersThree(_fill);

  // Pantalla Torneos
  static PhosphorIconData get ligaArgentina => PhosphorIcons.flag(_fill);
  static PhosphorIconData get copaArgentina => PhosphorIcons.trophy(_fill);
  static PhosphorIconData get libertadores => PhosphorIcons.crown(_fill);
  static PhosphorIconData get sudamericana => PhosphorIcons.medal(_fill);
  static PhosphorIconData get ligaInternacional => PhosphorIcons.globe(_s);

  // Navegación / UI
  static PhosphorIconData get home => PhosphorIcons.house(_s);
  static PhosphorIconData get back => PhosphorIcons.caretLeft(_s);
  static PhosphorIconData get cuenta => PhosphorIcons.userCircle(_s);
  static PhosphorIconData get chevron => PhosphorIcons.caretRight(_s);
  static PhosphorIconData get enVivo => PhosphorIcons.broadcast(_fill);
  static PhosphorIconData get tablaMoral => PhosphorIcons.brain(_s);
}
