import 'live_fixture_bundle.dart';

/// Partido y bundle ficticios para vista previa cuando no hay `live` en la API.
class LiveSectionMock {
  LiveSectionMock._();

  static const int _fixtureIdPreview = -90001;

  static Map<String, dynamic> partidoEjemplo() {
    return {
      'fixture': {
        'id': _fixtureIdPreview,
        'referee': 'Darío Herrera, Argentina',
        'timezone': 'America/Argentina/Buenos_Aires',
        'date': DateTime.now().toUtc().toIso8601String(),
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'venue': {'id': 1, 'name': 'Monumental', 'city': 'Buenos Aires'},
        'status': {'long': 'Second Half', 'short': '2H', 'elapsed': 67, 'extra': null},
      },
      'league': {'id': 128, 'name': 'Liga Profesional Argentina', 'season': 2026},
      'teams': {
        'home': {
          'id': 435,
          'name': 'River Plate',
          'logo': 'https://media.api-sports.io/football/teams/435.png',
          'colors': {
            'player': {'primary': 'ffffff', 'number': 'd0202f', 'border': 'd0202f'},
            'goalkeeper': {'primary': '000000', 'number': 'ffffff', 'border': 'ffffff'},
          },
        },
        'away': {
          'id': 451,
          'name': 'Racing Club',
          'logo': 'https://media.api-sports.io/football/teams/451.png',
          'colors': {
            'player': {'primary': '00a8d4', 'number': 'ffffff', 'border': 'ffffff'},
            'goalkeeper': {'primary': 'ffff00', 'number': '000000', 'border': '000000'},
          },
        },
      },
      'goals': {'home': 2, 'away': 1},
      'score': {
        'halftime': {'home': 1, 'away': 0},
        'fulltime': {'home': null, 'away': null},
        'extratime': {'home': null, 'away': null},
        'penalty': {'home': null, 'away': null},
      },
    };
  }

  static LiveFixtureBundle bundleEjemplo() {
    final stats = {
      'response': [
        {
          'team': {'id': 435, 'name': 'River Plate', 'logo': ''},
          'statistics': [
            {'type': 'Ball Possession', 'value': '58%'},
            {'type': 'Shots on Goal', 'value': 6},
            {'type': 'Shots off Goal', 'value': 4},
            {'type': 'Total Shots', 'value': 10},
            {'type': 'Blocked Shots', 'value': 2},
            {'type': 'Corner Kicks', 'value': 5},
            {'type': 'Fouls', 'value': 11},
            {'type': 'Offsides', 'value': 2},
            {'type': 'Yellow Cards', 'value': 2},
            {'type': 'Red Cards', 'value': 0},
            {'type': 'Total passes', 'value': 412},
            {'type': 'Passes %', 'value': '84%'},
            {'type': 'Goalkeeper Saves', 'value': 2},
          ],
        },
        {
          'team': {'id': 451, 'name': 'Racing Club', 'logo': ''},
          'statistics': [
            {'type': 'Ball Possession', 'value': '42%'},
            {'type': 'Shots on Goal', 'value': 3},
            {'type': 'Shots off Goal', 'value': 3},
            {'type': 'Total Shots', 'value': 6},
            {'type': 'Blocked Shots', 'value': 1},
            {'type': 'Corner Kicks', 'value': 2},
            {'type': 'Fouls', 'value': 14},
            {'type': 'Offsides', 'value': 1},
            {'type': 'Yellow Cards', 'value': 3},
            {'type': 'Red Cards', 'value': 0},
            {'type': 'Total passes', 'value': 301},
            {'type': 'Passes %', 'value': '78%'},
            {'type': 'Goalkeeper Saves', 'value': 4},
          ],
        },
      ],
    };

    final events = <Map<String, dynamic>>[
      {
        'time': {'elapsed': 12, 'extra': null},
        'team': {'id': 435, 'name': 'River Plate'},
        'player': {'id': 101, 'name': 'Miguel Borja'},
        'assist': {'id': 102, 'name': 'Manuel Lanzini'},
        'type': 'Goal',
        'detail': 'Normal Goal',
      },
      {
        'time': {'elapsed': 34, 'extra': null},
        'team': {'id': 451, 'name': 'Racing Club'},
        'player': {'id': 201, 'name': 'Adrián Martínez'},
        'assist': {'id': 202, 'name': 'Roger Martínez'},
        'type': 'Goal',
        'detail': 'Normal Goal',
      },
      {
        'time': {'elapsed': 41, 'extra': null},
        'team': {'id': 451, 'name': 'Racing Club'},
        'player': {'id': 203, 'name': 'Aníbal Moreno'},
        'assist': {'id': 0, 'name': ''},
        'type': 'Card',
        'detail': 'Yellow Card',
      },
      {
        'time': {'elapsed': 52, 'extra': null},
        'team': {'id': 435, 'name': 'River Plate'},
        'player': {'id': 103, 'name': 'Franco Armani'},
        'assist': {'id': 0, 'name': ''},
        'type': 'Card',
        'detail': 'Yellow Card',
      },
      {
        'time': {'elapsed': 61, 'extra': null},
        'team': {'id': 435, 'name': 'River Plate'},
        'player': {'id': 104, 'name': 'Ignacio Fernández'},
        'assist': {'id': 105, 'name': 'Pablo Solari'},
        'type': 'Goal',
        'detail': 'Normal Goal',
      },
      {
        'time': {'elapsed': 64, 'extra': null},
        'team': {'id': 435, 'name': 'River Plate'},
        'player': {'id': 106, 'name': 'Rodrigo Aliendro'},
        'assist': {'id': 107, 'name': 'Giuliano Galoppo'},
        'type': 'subst',
        'detail': 'Substitution 1',
      },
    ];

    Map<String, dynamic> xiPlayer(int id, String name, int number, String pos, String grid) => {
          'player': {
            'id': id,
            'name': name,
            'number': number,
            'pos': pos,
            'grid': grid,
            'photo': '',
            'nationality': 'Argentina',
          },
        };

    final lineHome = {
      'team': {'id': 435, 'name': 'River Plate', 'logo': 'https://media.api-sports.io/football/teams/435.png'},
      'formation': '4-3-3',
      'coach': {'id': 1, 'name': 'Martín Demichelis', 'photo': ''},
      'startXI': [
        xiPlayer(103, 'Franco Armani', 1, 'G', '1:1'),
        xiPlayer(108, 'Andrés Herrera', 16, 'D', '2:4'),
        xiPlayer(109, 'Leandro González Pirez', 14, 'D', '2:3'),
        xiPlayer(110, 'Paulo Díaz', 17, 'D', '2:2'),
        xiPlayer(111, 'Milton Casco', 20, 'D', '2:1'),
        xiPlayer(106, 'Rodrigo Aliendro', 24, 'M', '3:3'),
        xiPlayer(112, 'Enzo Pérez', 8, 'M', '3:2'),
        xiPlayer(113, 'Ignacio Fernández', 26, 'M', '3:1'),
        xiPlayer(114, 'Pablo Solari', 36, 'F', '4:3'),
        xiPlayer(101, 'Miguel Borja', 9, 'F', '4:2'),
        xiPlayer(115, 'Facundo Colidio', 11, 'F', '4:1'),
      ],
      'substitutes': [
        xiPlayer(107, 'Giuliano Galoppo', 23, 'M', '0:0'),
        xiPlayer(116, 'Matías Suárez', 7, 'D', '0:0'),
      ],
    };

    final lineAway = {
      'team': {'id': 451, 'name': 'Racing Club', 'logo': 'https://media.api-sports.io/football/teams/451.png'},
      'formation': '4-4-2',
      'coach': {'id': 2, 'name': 'Gustavo Costas', 'photo': ''},
      'startXI': [
        xiPlayer(301, 'Gabriel Arias', 21, 'G', '1:1'),
        xiPlayer(302, 'Facundo Mura', 13, 'D', '2:4'),
        xiPlayer(303, 'Leonardo Sigali', 2, 'D', '2:3'),
        xiPlayer(304, 'Nazareno Colombo', 40, 'D', '2:2'),
        xiPlayer(305, 'Gabriel Rojas', 3, 'D', '2:1'),
        xiPlayer(306, 'Aníbal Moreno', 5, 'M', '3:4'),
        xiPlayer(307, 'Juan Nardoni', 16, 'M', '3:3'),
        xiPlayer(308, 'Agustín Ojeda', 11, 'M', '3:2'),
        xiPlayer(309, 'Roger Martínez', 10, 'M', '3:1'),
        xiPlayer(201, 'Adrián Martínez', 18, 'F', '4:2'),
        xiPlayer(310, 'Maximiliano Salas', 9, 'F', '4:1'),
      ],
      'substitutes': [
        xiPlayer(311, 'Matías Rojas', 7, 'M', '0:0'),
      ],
    };

    final players = <Map<String, dynamic>>[
      {'id': 101, 'nombre': 'Miguel Borja', 'equipo': 'River Plate', 'equipoId': 435, 'tieneRating': true, 'rating': 7.8, 'minutos': 67},
      {'id': 104, 'nombre': 'Ignacio Fernández', 'equipo': 'River Plate', 'equipoId': 435, 'tieneRating': true, 'rating': 7.4, 'minutos': 67},
      {'id': 103, 'nombre': 'Franco Armani', 'equipo': 'River Plate', 'equipoId': 435, 'tieneRating': true, 'rating': 6.9, 'minutos': 67},
      {'id': 201, 'nombre': 'Adrián Martínez', 'equipo': 'Racing Club', 'equipoId': 451, 'tieneRating': true, 'rating': 7.1, 'minutos': 67},
      {'id': 203, 'nombre': 'Aníbal Moreno', 'equipo': 'Racing Club', 'equipoId': 451, 'tieneRating': true, 'rating': 6.6, 'minutos': 58},
    ];

    final detalle = Map<String, dynamic>.from(partidoEjemplo());

    return LiveFixtureBundle(
      statisticsRaw: stats,
      events: events,
      lineups: [lineHome, lineAway],
      players: players,
      detalle: detalle,
      fetchedAt: DateTime.now(),
    );
  }
}
