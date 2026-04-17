// lib/tabla_rachas_tab.dart
// Tabla de Rachas — sin ganar / sin perder — general, local, visitante
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'api_service.dart';
import 'racha_model.dart';

// ─── Constantes de liga (ajustar según leagueId/season activo) ───────────────

enum _ModoRacha { sinGanar, sinPerder }

enum _SortCol { equipo, general, local, visitante }

class TablaRachasTab extends StatefulWidget {
  const TablaRachasTab({super.key});

  @override
  State<TablaRachasTab> createState() => _TablaRachasTabState();
}

class _TablaRachasTabState extends State<TablaRachasTab> {
  

  List<RachaEquipo> _rachas = [];
  bool _loading = true;
  String? _error;

  _ModoRacha _modo = _ModoRacha.sinGanar;
  _SortCol _sortCol = _SortCol.general;
  bool _sortAsc = false; // desc por defecto (mayor racha arriba)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getRachasEquipos(
        forceRefresh: forceRefresh,
      );
      setState(() {
        _rachas = data;
        _loading = false;
      });
      _sortData();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Valor de la columna seleccionada según modo
  int _valor(RachaEquipo r) {
    if (_modo == _ModoRacha.sinGanar) {
      switch (_sortCol) {
        case _SortCol.general:
          return r.sinGanarGeneral;
        case _SortCol.local:
          return r.sinGanarLocal;
        case _SortCol.visitante:
          return r.sinGanarVisitante;
        case _SortCol.equipo:
          return 0;
      }
    } else {
      switch (_sortCol) {
        case _SortCol.general:
          return r.sinPerderGeneral;
        case _SortCol.local:
          return r.sinPerderLocal;
        case _SortCol.visitante:
          return r.sinPerderVisitante;
        case _SortCol.equipo:
          return 0;
      }
    }
  }

  void _sortData() {
    setState(() {
      if (_sortCol == _SortCol.equipo) {
        _rachas.sort((a, b) =>
            _sortAsc ? a.teamName.compareTo(b.teamName) : b.teamName.compareTo(a.teamName));
      } else {
        _rachas.sort((a, b) =>
            _sortAsc ? _valor(a).compareTo(_valor(b)) : _valor(b).compareTo(_valor(a)));
      }
    });
  }

  void _onSortTap(_SortCol col) {
    setState(() {
      if (_sortCol == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = col;
        _sortAsc = false;
      }
    });
    _sortData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToggle(),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error al cargar rachas', style: TextStyle(color: Colors.red[300])),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _load(forceRefresh: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(forceRefresh: true),
              child: _buildTable(),
            ),
          ),
      ],
    );
  }

  // ─── Toggle Sin Ganar / Sin Perder ─────────────────────────────────────────
  Widget _buildToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _toggleBtn('Sin Ganar', _ModoRacha.sinGanar, Colors.red[400]!),
          _toggleBtn('Sin Perder', _ModoRacha.sinPerder, Colors.green[400]!),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, _ModoRacha modo, Color activeColor) {
    final isActive = _modo == modo;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _modo = modo);
          _sortData();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? activeColor.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isActive
                ? Border.all(color: activeColor, width: 1.5)
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? activeColor : Colors.grey[500],
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Tabla principal ────────────────────────────────────────────────────────
  Widget _buildTable() {
    final accentColor =
        _modo == _ModoRacha.sinGanar ? Colors.red[400]! : Colors.green[400]!;

    return Column(
      children: [
        _buildHeader(accentColor),
        Expanded(
          child: ListView.builder(
            itemCount: _rachas.length,
            itemBuilder: (ctx, i) => _buildRow(_rachas[i], i, accentColor),
          ),
        ),
        _buildLeyenda(),
      ],
    );
  }

  // ─── Encabezado con columnas ordenables ────────────────────────────────────
  Widget _buildHeader(Color accentColor) {
    return Container(
      color: Colors.grey[850],
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          // Equipo
          Expanded(
            flex: 5,
            child: _headerCell('Equipo', _SortCol.equipo, accentColor),
          ),
          // General
          Expanded(
            flex: 2,
            child: _headerCell('Gral', _SortCol.general, accentColor),
          ),
          // Local
          Expanded(
            flex: 2,
            child: _headerCell('🏠', _SortCol.local, accentColor),
          ),
          // Visitante
          Expanded(
            flex: 2,
            child: _headerCell('✈️', _SortCol.visitante, accentColor),
          ),
          // Últimos 5
          const Expanded(
            flex: 5,
            child: Text(
              'Últ. 5',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String label, _SortCol col, Color accentColor) {
    final isActive = _sortCol == col;
    return GestureDetector(
      onTap: () => _onSortTap(col),
      child: Row(
        mainAxisAlignment: col == _SortCol.equipo
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isActive ? accentColor : Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 2),
            Icon(
              _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
              size: 10,
              color: accentColor,
            ),
          ]
        ],
      ),
    );
  }

  // ─── Fila de equipo ─────────────────────────────────────────────────────────
  Widget _buildRow(RachaEquipo r, int index, Color accentColor) {
    final sinGanar = _modo == _ModoRacha.sinGanar;
    final general = sinGanar ? r.sinGanarGeneral : r.sinPerderGeneral;
    final local = sinGanar ? r.sinGanarLocal : r.sinPerderLocal;
    final visitante = sinGanar ? r.sinGanarVisitante : r.sinPerderVisitante;

    return Container(
      decoration: BoxDecoration(
        color: index.isEven ? Colors.grey[900] : Colors.grey[850],
        border: Border(
          bottom: BorderSide(color: Colors.grey[800]!, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
      child: Row(
        children: [
          // Equipo (logo + nombre)
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Image.network(
                  r.teamLogo,
                  width: 22,
                  height: 22,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.sports_soccer, size: 22, color: Colors.grey),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _shortName(r.teamName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // General
          Expanded(
            flex: 2,
            child: _valorCell(general, sinGanar, isActive: _sortCol == _SortCol.general),
          ),
          // Local
          Expanded(
            flex: 2,
            child: _valorCell(local, sinGanar, isActive: _sortCol == _SortCol.local),
          ),
          // Visitante
          Expanded(
            flex: 2,
            child: _valorCell(visitante, sinGanar, isActive: _sortCol == _SortCol.visitante),
          ),
          // Últimos 5
          Expanded(
            flex: 5,
            child: _ultimos5Row(r.ultimos5),
          ),
        ],
      ),
    );
  }

  // ─── Celda de valor con color semáforo ─────────────────────────────────────
  Widget _valorCell(int valor, bool sinGanar, {bool isActive = false}) {
    Color color;
    if (sinGanar) {
      // Sin ganar: más alto = peor = más rojo
      if (valor == 0)
        color = Colors.green[400]!;
      else if (valor <= 2)
        color = Colors.white;
      else if (valor <= 4)
        color = Colors.orange[300]!;
      else
        color = Colors.red[400]!;
    } else {
      // Sin perder: más alto = mejor = más verde
      if (valor == 0)
        color = Colors.grey[500]!;
      else if (valor <= 3)
        color = Colors.white;
      else if (valor <= 6)
        color = Colors.lightGreen[300]!;
      else
        color = Colors.green[400]!;
    }

    return Container(
      alignment: Alignment.center,
      child: Text(
        '$valor',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  // ─── Últimos 5 resultados ───────────────────────────────────────────────────
  Widget _ultimos5Row(List<String> resultados) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        if (i >= resultados.length) {
          return _dot('·', Colors.grey[700]!);
        }
        final r = resultados[i];
        final color = r == 'W'
            ? Colors.green[400]!
            : r == 'L'
                ? Colors.red[400]!
                : Colors.grey[400]!;
        return _dot(r, color);
      }),
    );
  }

  Widget _dot(String letra, Color color) {
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.8),
      ),
      child: Center(
        child: Text(
          letra,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ─── Leyenda ────────────────────────────────────────────────────────────────
  Widget _buildLeyenda() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _leyendaItem('🏠 Local', Colors.grey[400]!),
          const SizedBox(width: 16),
          _leyendaItem('✈️ Visitante', Colors.grey[400]!),
          const SizedBox(width: 16),
          _leyendaItem('G Ganó', Colors.green[400]!),
          const SizedBox(width: 8),
          _leyendaItem('E Empató', Colors.grey[400]!),
          const SizedBox(width: 8),
          _leyendaItem('P Perdió', Colors.red[400]!),
        ],
      ),
    );
  }

  Widget _leyendaItem(String texto, Color color) {
    return Text(
      texto,
      style: TextStyle(color: color, fontSize: 9),
    );
  }

  // ─── Abreviatura de nombre de equipo ───────────────────────────────────────
  String _shortName(String name) {
    // Abreviaturas comunes de la LPF
    const abreviaturas = {
      'Estudiantes de La Plata': 'Estudiantes',
      'Newell\'s Old Boys': 'Newell\'s',
      'Atlético Tucumán': 'Atl. Tucumán',
      'Defensa y Justicia': 'Def. y Justicia',
      'San Lorenzo de Almagro': 'San Lorenzo',
      'Independiente Rivadavia': 'Ind. Rivadavia',
      'Argentinos Juniors': 'Arg. Juniors',
      'Deportivo Riestra': 'Riestra',
      'Talleres de Córdoba': 'Talleres',
    };
    return abreviaturas[name] ?? name;
  }
}
