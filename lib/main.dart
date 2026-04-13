import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const HDFStatsApp());
}

class HDFStatsApp extends StatelessWidget {
  const HDFStatsApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HDF STATS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0D1B2A),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF00C853)),
      ),
      home: const OnboardingCheck(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  int _fechaActual = -1;
  int? _equipoFavoritoId;
  String? _equipoFavoritoNombre;
  Future<Map<String, List<Map<String, dynamic>>>>? _futureTablaMoral;
  String _torneoActual = 'APERTURA';
  List<Map<String, dynamic>> _partidosEnVivo = [];
  Timer? _timerEnVivo;
  bool _hayEnVivo = false;

  @override
  void initState() {
    super.initState();
    ApiService.clearCache(); // Reset cache en cada inicio de sesion
    if (!kIsWeb) _inicializarFCM();
    _actualizarEnVivo();
    _timerEnVivo = Timer.periodic(const Duration(seconds: 60), (_) => _actualizarEnVivo());
    _cargarFavorito();
  }

  Future<Map<String, List<Map<String, dynamic>>>> _getTablaMoralCached() {
    _futureTablaMoral ??= ApiService.getTablaMoral();
    return _futureTablaMoral!;
  }

  Future<void> _cargarFavorito() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('equipo_favorito_id');
    final nombre = prefs.getString('equipo_favorito_nombre');
    if (id != null && id != -1 && mounted) {
      setState(() { _equipoFavoritoId = id; _equipoFavoritoNombre = nombre; });
    }
  }


  Future<void> _inicializarFCM() async {
    if (kIsWeb) return;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true, provisional: false);
    if (settings.authorizationStatus != AuthorizationStatus.authorized) return;
    final localNotif = FlutterLocalNotificationsPlugin();
    const channelId = 'hdf_partidos';
    const channelName = 'Partidos HDF Stats';
    await localNotif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(channelId, channelName,
            description: 'Alertas pre-partido, goles en vivo y analisis post-partido',
            importance: Importance.high));
    await localNotif.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (d) => _manejarTapNotificacion(d.payload));
    final token = await messaging.getToken();
    debugPrint('FCM Token: $token');
    if (token != null) {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('user_uid');
      if (uid != null) {
        await FirebaseFirestore.instance.collection('fcm_tokens').doc(uid)
            .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
    }
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final notif = message.notification;
      if (notif != null && message.notification?.android != null) {
        await localNotif.show(notif.hashCode, notif.title, notif.body,
            const NotificationDetails(android: AndroidNotificationDetails(channelId, channelName,
                importance: Importance.high, priority: Priority.high, icon: '@mipmap/ic_launcher')),
            payload: message.data['fixtureId']);
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _manejarTapNotificacion(m.data['fixtureId']));
    final initial = await messaging.getInitialMessage();
    if (initial != null) _manejarTapNotificacion(initial.data['fixtureId']);
  }

  void _manejarTapNotificacion(String? fixtureId) {
    if (fixtureId == null || !mounted) return;
    setState(() => _selectedIndex = 0);
  }

  // ── PERFIL DE CLUB ────────────────────────────────────────────────────────
  static const Map<int, Map<String, dynamic>> _clubInfo = {
    451: {'presidente': 'Juan Roman Riquelme', 'estadio': 'Estadio Alberto J. Armando (La Bombonera)', 'capacidad': '54.000', 'fundacion': '1905', 'socios': '70.000', 'titulosLocales': ['Liga 2022','Liga 2020','Clausura 2015','Clausura 2011','Clausura 2008','Clausura 2006','Clausura 2005','Clausura 2003'], 'titulosInternacionales': ['Copa Libertadores 2007','Copa Libertadores 2003','Copa Libertadores 2001','Copa Libertadores 2000','Copa Libertadores 1978','Copa Libertadores 1977'], 'ultimoTituloLocal': 'Liga Profesional 2022', 'ultimoTituloInternacional': 'Copa Libertadores 2007', 'dt': 'Fernando Gago'},
    450: {'presidente': 'Juan Sebastian Veron', 'estadio': 'Estadio Jorge Luis Hirschi', 'capacidad': '30.518', 'fundacion': '1905', 'socios': '40.000', 'titulosLocales': ['Liga 2023','Apertura 2010','Clausura 2010','Clausura 2006','Clausura 1983'], 'titulosInternacionales': ['Copa Libertadores 2009'], 'ultimoTituloLocal': 'Liga Profesional 2023', 'ultimoTituloInternacional': 'Copa Libertadores 2009', 'dt': 'Eduardo Dominguez'},
    438: {'presidente': 'Fabian Gardinetti', 'estadio': 'Estadio Jose Amalfitani', 'capacidad': '49.540', 'fundacion': '1910', 'socios': '38.000', 'titulosLocales': ['Clausura 2012','Clausura 2011','Apertura 2009','Clausura 2005','Apertura 2004'], 'titulosInternacionales': ['Copa Sudamericana 2023'], 'ultimoTituloLocal': 'Clausura 2012', 'ultimoTituloInternacional': 'Copa Sudamericana 2023', 'dt': 'Gustavo Quinteros'},
    441: {'presidente': 'Luis Spahn', 'estadio': 'Estadio 15 de Abril', 'capacidad': '23.054', 'fundacion': '1907', 'socios': '22.000', 'titulosLocales': [], 'titulosInternacionales': [], 'ultimoTituloLocal': '-', 'ultimoTituloInternacional': '-', 'dt': 'Gustavo Munua'},
    442: {'presidente': 'Hugo Moyano', 'estadio': 'Estadio Norberto Tomaghello', 'capacidad': '14.000', 'fundacion': '1935', 'socios': '12.000', 'titulosLocales': ['Copa Argentina 2023'], 'titulosInternacionales': ['Copa Sudamericana 2018'], 'ultimoTituloLocal': 'Copa Argentina 2023', 'ultimoTituloInternacional': 'Copa Sudamericana 2018', 'dt': 'Julio Vaccari'},
    446: {'presidente': 'Nicolas Russo', 'estadio': 'Estadio Ciudad de Lanus (La Fortaleza)', 'capacidad': '47.028', 'fundacion': '1915', 'socios': '30.000', 'titulosLocales': ['Clausura 2007','Clausura 2013'], 'titulosInternacionales': ['Copa Sudamericana 2013'], 'ultimoTituloLocal': 'Clausura 2013', 'ultimoTituloInternacional': 'Copa Sudamericana 2013', 'dt': 'Ricardo Zielinski'},
    453: {'presidente': 'Hugo Moyano', 'estadio': 'Estadio Libertadores de America', 'capacidad': '52.697', 'fundacion': '1905', 'socios': '55.000', 'titulosLocales': ['Apertura 2010','Clausura 2010','Apertura 2002','Clausura 1999','Clausura 1994'], 'titulosInternacionales': ['Copa Libertadores 1984','Copa Libertadores 1975','Copa Libertadores 1974','Copa Libertadores 1965','Copa Sudamericana 2010'], 'ultimoTituloLocal': 'Apertura 2010', 'ultimoTituloInternacional': 'Copa Sudamericana 2010', 'dt': 'Diego Dabove'},
    456: {'presidente': 'Andres Fassi', 'estadio': 'Estadio Mario Alberto Kempes', 'capacidad': '57.000', 'fundacion': '1913', 'socios': '42.000', 'titulosLocales': ['Copa de la Liga 2022'], 'titulosInternacionales': [], 'ultimoTituloLocal': 'Copa de la Liga 2022', 'ultimoTituloInternacional': '-', 'dt': 'Alexander Medina'},
    460: {'presidente': 'Marcelo Moretti', 'estadio': 'Estadio Pedro Bidegain (El Nuevo Gasometro)', 'capacidad': '48.916', 'fundacion': '1908', 'socios': '45.000', 'titulosLocales': ['Apertura 2007','Clausura 2007','Clausura 2004','Clausura 2001','Apertura 1995'], 'titulosInternacionales': ['Copa Libertadores 1986','Copa Interamericana 1969'], 'ultimoTituloLocal': 'Clausura 2007', 'ultimoTituloInternacional': 'Copa Libertadores 1986', 'dt': 'Miguel Angel Russo'},
    478: {'presidente': 'Pablo Zuluaga', 'estadio': 'Estadio Juan Domingo Peron', 'capacidad': '30.000', 'fundacion': '1918', 'socios': '15.000', 'titulosLocales': [], 'titulosInternacionales': [], 'ultimoTituloLocal': '-', 'ultimoTituloInternacional': '-', 'dt': 'Diego Dabove'},
    1064: {'presidente': 'Pablo Vidal', 'estadio': 'Estadio Ciudad de Vicente Lopez', 'capacidad': '13.300', 'fundacion': '1905', 'socios': '18.000', 'titulosLocales': [], 'titulosInternacionales': [], 'ultimoTituloLocal': '-', 'ultimoTituloInternacional': '-', 'dt': 'Martin Palermo'},
    1066: {'presidente': 'Gabriel Pellegrino', 'estadio': 'Estadio Juan Carmelo Zerillo', 'capacidad': '31.500', 'fundacion': '1887', 'socios': '25.000', 'titulosLocales': ['Nacional 1929'], 'titulosInternacionales': [], 'ultimoTituloLocal': 'Nacional 1929', 'ultimoTituloInternacional': '-', 'dt': 'Nestor Gorosito'},
    1065: {'presidente': 'Fernando Quiroga', 'estadio': 'Estadio Madre de Ciudades', 'capacidad': '30.000', 'fundacion': '1971', 'socios': '10.000', 'titulosLocales': [], 'titulosInternacionales': [], 'ultimoTituloLocal': '-', 'ultimoTituloInternacional': '-', 'dt': 'Omar De Felippe'},
    457: {'presidente': 'Sebastian Peratta', 'estadio': 'Estadio Marcelo Bielsa', 'capacidad': '42.000', 'fundacion': '1903', 'socios': '35.000', 'titulosLocales': ['Apertura 2004','Clausura 2004','Clausura 1998','Clausura 1992','Nacional 1988'], 'titulosInternacionales': [], 'ultimoTituloLocal': 'Clausura 2004', 'ultimoTituloInternacional': '-', 'dt': 'Mariano Soso'},
    476: {'presidente': 'Sergio Palazzo', 'estadio': 'Estadio Ramon Tarruela', 'capacidad': '16.000', 'fundacion': '1906', 'socios': '8.000', 'titulosLocales': [], 'titulosInternacionales': [], 'ultimoTituloLocal': '-', 'ultimoTituloInternacional': '-', 'dt': 'Marcelo Franchini'},
    435: {'presidente': 'Maximiliano Abad', 'estadio': 'Estadio Monumental Antonio Vespucio Liberti', 'capacidad': '84.567', 'fundacion': '1901', 'socios': '120.000', 'titulosLocales': ['Liga 2023','Liga 2021','Liga 2019','Liga 2018','Clausura 2014','Clausura 2012','Apertura 2009'], 'titulosInternacionales': ['Copa Libertadores 2018','Copa Libertadores 2015','Copa Libertadores 1996','Copa Libertadores 1986'], 'ultimoTituloLocal': 'Liga Profesional 2023', 'ultimoTituloInternacional': 'Copa Libertadores 2018', 'dt': 'Marcelo Gallardo'},
    458: {'presidente': 'Cristian Malaspina', 'estadio': 'Estadio Diego Armando Maradona', 'capacidad': '26.000', 'fundacion': '1904', 'socios': '18.000', 'titulosLocales': ['Clausura 2010'], 'titulosInternacionales': ['Copa Sudamericana 2014'], 'ultimoTituloLocal': 'Clausura 2010', 'ultimoTituloInternacional': 'Copa Sudamericana 2014', 'dt': 'Leandro Stillitano'},
    440: {'presidente': 'Gustavo Menendez', 'estadio': 'Estadio Gigante de Alberdi', 'capacidad': '30.000', 'fundacion': '1905', 'socios': '28.000', 'titulosLocales': ['Nacional 1979','Nacional 1980'], 'titulosInternacionales': [], 'ultimoTituloLocal': 'Nacional 1980', 'ultimoTituloInternacional': '-', 'dt': 'Diego Dabove'},
    437: {'presidente': 'Gonzalo Belloso', 'estadio': 'Estadio Gigante de Arroyito', 'capacidad': '42.000', 'fundacion': '1889', 'socios': '50.000', 'titulosLocales': ['Apertura 2012','Clausura 2008','Apertura 2006','Clausura 1997','Apertura 1995'], 'titulosInternacionales': ['Copa Libertadores 2000'], 'ultimoTituloLocal': 'Apertura 2012', 'ultimoTituloInternacional': 'Copa Libertadores 2000', 'dt': 'Facundo Sava'},
    445: {'presidente': 'Alejandro Nadur', 'estadio': 'Estadio Tomas Adolfo Duco (El Palacio)', 'capacidad': '48.314', 'fundacion': '1908', 'socios': '28.000', 'titulosLocales': ['Clausura 2009','Clausura 2000','Apertura 1991'], 'titulosInternacionales': [], 'ultimoTituloLocal': 'Clausura 2009', 'ultimoTituloInternacional': '-', 'dt': 'Frank Dario Kudelka'},
    2432: {'presidente': 'Rodolfo De Paoli', 'estadio': 'Estadio Claudio Cueto', 'capacidad': '7.000', 'fundacion': '1904', 'socios': '5.000', 'titulosLocales': [], 'titulosInternacionales': [], 'ultimoTituloLocal': '-', 'ultimoTituloInternacional': '-', 'dt': 'Rodolfo De Paoli'},
    452: {'presidente': 'Nestor Ortega', 'estadio': 'Estadio Jose Dellagiovanna', 'capacidad': '27.000', 'fundacion': '1902', 'socios': '20.000', 'titulosLocales': ['Clausura 2012'], 'titulosInternacionales': [], 'ultimoTituloLocal': 'Clausura 2012', 'ultimoTituloInternacional': '-', 'dt': 'Gustavo Alvarez'},
    436: {'presidente': 'Victor Blanco', 'estadio': 'Estadio Presidente Peron (El Cilindro)', 'capacidad': '51.389', 'fundacion': '1903', 'socios': '55.000', 'titulosLocales': ['Liga 2024','Apertura 2014','Clausura 2010','Apertura 2010'], 'titulosInternacionales': ['Copa Sudamericana 2018','Intercontinental 1967'], 'ultimoTituloLocal': 'Liga Profesional 2024', 'ultimoTituloInternacional': 'Copa Sudamericana 2018', 'dt': 'Gustavo Costas'},
    474: {'presidente': 'Ariel Cozzoni', 'estadio': 'Estadio Eva Peron', 'capacidad': '20.000', 'fundacion': '1911', 'socios': '12.000', 'titulosLocales': [], 'titulosInternacionales': [], 'ultimoTituloLocal': '-', 'ultimoTituloInternacional': '-', 'dt': 'Arnaldo Llinas'},
    434: {'presidente': 'Gabriel Pellegrino', 'estadio': 'Estadio Juan Carmelo Zerillo', 'capacidad': '31.500', 'fundacion': '1887', 'socios': '25.000', 'titulosLocales': ['Nacional 1929'], 'titulosInternacionales': [], 'ultimoTituloLocal': 'Nacional 1929', 'ultimoTituloInternacional': '-', 'dt': 'Nestor Gorosito'},
    449: {'presidente': 'Ramon Jerez', 'estadio': 'Estadio Florencio Sola', 'capacidad': '34.000', 'fundacion': '1896', 'socios': '20.000', 'titulosLocales': ['Clausura 2009'], 'titulosInternacionales': [], 'ultimoTituloLocal': 'Clausura 2009', 'ultimoTituloInternacional': '-', 'dt': 'Julio Cesar Falcioni'},
    455: {'presidente': 'Osvaldo Beligoy', 'estadio': 'Estadio Monumental Jose Fierro', 'capacidad': '23.000', 'fundacion': '1902', 'socios': '22.000', 'titulosLocales': ['Nacional 2015','Copa Argentina 2015'], 'titulosInternacionales': [], 'ultimoTituloLocal': 'Nacional 2015', 'ultimoTituloInternacional': '-', 'dt': 'Carlos Tevez'},
    473: {'presidente': 'Adrian Uriarte', 'estadio': 'Estadio Ciudad de Rivadavia', 'capacidad': '18.000', 'fundacion': '1932', 'socios': '8.000', 'titulosLocales': [], 'titulosInternacionales': [], 'ultimoTituloLocal': '-', 'ultimoTituloInternacional': '-', 'dt': 'Diego Pozo'},
    463: {'presidente': 'Rodolfo Caro', 'estadio': 'Estadio El Gigante del Sur', 'capacidad': '24.000', 'fundacion': '1908', 'socios': '15.000', 'titulosLocales': [], 'titulosInternacionales': [], 'ultimoTituloLocal': '-', 'ultimoTituloInternacional': '-', 'dt': 'Gaston Coyette'},
    2424: {'presidente': 'Marcelo Sanchez', 'estadio': 'Estadio Ciudad de Rio Cuarto', 'capacidad': '18.000', 'fundacion': '1915', 'socios': '10.000', 'titulosLocales': [], 'titulosInternacionales': [], 'ultimoTituloLocal': '-', 'ultimoTituloInternacional': '-', 'dt': 'Rodrigo Lugones'},
  };

  void _mostrarPerfilClub(BuildContext context, int teamId, String nombre, String? logo) {
    final info = _clubInfo[teamId];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1B2A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4, expand: false,
        builder: (_, sc) => DefaultTabController(
          length: 3,
          child: Column(children: [
            Container(margin: const EdgeInsets.only(top: 10, bottom: 6), width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                if (logo != null) Image.network(logo, width: 48, height: 48,
                    errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.white38, size: 48)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  if (info != null) Text('Fundado en ${info["fundacion"]}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ])),
              ]),
            ),
            const TabBar(
              indicatorColor: Color(0xFFFFD700),
              labelColor: Color(0xFFFFD700),
              unselectedLabelColor: Colors.white54,
              tabs: [Tab(text: 'INFO'), Tab(text: 'TITULOS'), Tab(text: 'PLANTEL')],
            ),
            Expanded(
              child: info == null
                ? const Center(child: Text('Datos proximos', style: TextStyle(color: Colors.white54)))
                : TabBarView(children: [
                    ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
                      _clubInfoRow('Estadio', info['estadio'] as String),
                      _clubInfoRow('Capacidad', '${info["capacidad"]} espectadores'),
                      _clubInfoRow('Presidente', info['presidente'] as String),
                      _clubInfoRow('Director Tecnico', info['dt'] as String),
                      _clubInfoRow('Fundacion', info['fundacion'] as String),
                      _clubInfoRow('Socios', '~${info["socios"]}'),
                    ]),
                    ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
                      const Text('LOCALES', style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 6),
                      ...(info['titulosLocales'] as List).map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('🏆 $t', style: const TextStyle(color: Colors.white, fontSize: 13)))),
                      const SizedBox(height: 12),
                      const Text('INTERNACIONALES', style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 6),
                      ...((info['titulosInternacionales'] as List).isEmpty
                        ? [const Text('Sin titulos internacionales', style: TextStyle(color: Colors.white54, fontSize: 13))]
                        : (info['titulosInternacionales'] as List).map((t) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('🌎 $t', style: const TextStyle(color: Colors.white, fontSize: 13))))),
                      const SizedBox(height: 12),
                      _clubInfoRow('Ultimo local', info['ultimoTituloLocal'] as String),
                      _clubInfoRow('Ultimo internacional', info['ultimoTituloInternacional'] as String),
                    ]),
                    const Center(child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Plantel disponible proximamente', style: TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
                    )),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _clubInfoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
    ]),
  );

  Widget _logoConTap(String? logo, double size, int? teamId, String nombre) {
    final img = logo != null
        ? Image.network(logo, width: size, height: size,
            errorBuilder: (_, __, ___) => Icon(Icons.shield, color: Colors.white38, size: size))
        : Icon(Icons.shield, color: Colors.white38, size: size);
    if (teamId == null) return img;
    return GestureDetector(onTap: () => _mostrarPerfilClub(context, teamId, nombre, logo), child: img);
  }
  // ── FIN PERFIL DE CLUB ────────────────────────────────────────────────────

  @override
  void dispose() {
    _timerEnVivo?.cancel();
    super.dispose();
  }

  Future<void> _actualizarEnVivo() async {
    final partidos = await ApiService.getPartidosEnVivo();
    if (mounted) {
      setState(() {
        _partidosEnVivo = partidos;
        _hayEnVivo = partidos.isNotEmpty;
      });
    }
  }

  final List<Map<String, dynamic>> _sections = [
    {'icon': Icons.sports_soccer, 'label': 'Resultados'},
    {'icon': Icons.table_chart, 'label': 'Tablas'},
    {'icon': Icons.sports_soccer, 'label': 'Goleadores'},
    {'icon': Icons.sports_handball, 'label': 'Arqueros'},
    {'icon': Icons.calendar_month, 'label': 'Fixture'},
    {'icon': Icons.live_tv, 'label': 'En Vivo'},
    {'icon': Icons.auto_graph, 'label': 'Predicción'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        title: Row(children: const [
          Text('HDF', style: TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: 2)),
          Text(' STATS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: 2)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.notifications_outlined, color: Color(0xFF00C853)), onPressed: () {}),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.person_outline, color: Colors.white70),
              onPressed: () => _mostrarPanelCodigo(ctx),
            ),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B2A3B),
          boxShadow: [BoxShadow(color: const Color(0xFF00C853).withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF1B2A3B),
          selectedItemColor: const Color(0xFF00C853),
          unselectedItemColor: Colors.white38,
          currentIndex: _selectedIndex,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          onTap: (index) => setState(() => _selectedIndex = index),
          items: _sections.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            if (i == 5 && _hayEnVivo) {
              return BottomNavigationBarItem(
                icon: Stack(children: [
                  Icon(s['icon']),
                  Positioned(top: 0, right: 0, child: Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF00C853), shape: BoxShape.circle),
                  )),
                ]),
                label: s['label'],
              );
            }
            return BottomNavigationBarItem(icon: Icon(s['icon']), label: s['label']);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0: return _buildResultados();
      case 1: return _buildTablas();
      case 2: return _buildEquipos();
      case 3: return _buildArqueros();
      case 4: return _buildFixture();
      case 5: return _buildEnVivo();
      case 6: return _buildPredicciones();
      default: return _buildResultados();
    }
  }

  void _mostrarPanelCodigo(BuildContext context) {
    final controller = TextEditingController();
    String? mensaje;
    bool cargando = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          backgroundColor: const Color(0xFF1B2A3B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 400,
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('👤', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                const Text('MI CUENTA', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
              ]),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              const Text('CÓDIGO DE CORTESÍA', style: TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              const Text('Ingresá tu código para acceder a HDF Stats Premium gratis.', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    decoration: InputDecoration(
                      hintText: 'Ej: SORTEO-ABRIL',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: const Color(0xFF0D1B2A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00C853))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                cargando
                  ? const CircularProgressIndicator(color: Color(0xFF00C853))
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C853),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        final codigo = controller.text.trim().toUpperCase();
                        if (codigo.isEmpty) return;
                        setModalState(() => cargando = true);
                        try {
                          // Fix: buscar por Document ID evita indice Firestore
                          final docRef = await FirebaseFirestore.instance
                            .collection('codigos_cortesia')
                            .doc(codigo)
                            .get();
                          if (!docRef.exists) {
                            setModalState(() { mensaje = '❌ Código inválido o inactivo.'; cargando = false; });
                            return;
                          }
                          final data = docRef.data()!;
                          if (data['activo'] != true) {
                            setModalState(() { mensaje = '❌ Código inválido o inactivo.'; cargando = false; });
                            return;
                          }
                          final usosActuales = (data['usos_actuales'] as num?)?.toInt() ?? 0;
                          final usosMaximos = (data['usos_maximos'] as num?)?.toInt() ?? 0;
                          if (usosActuales >= usosMaximos) {
                            setModalState(() { mensaje = '❌ Código agotado.'; cargando = false; });
                            return;
                          }
                          await FirebaseFirestore.instance.collection('codigos_cortesia').doc(codigo).update({
                            'usos_actuales': FieldValue.increment(1),
                          });
                          final meses = (data['meses_gratis'] as num?)?.toInt() ?? 1;
                          setModalState(() { mensaje = '✅ ¡Código válido! Tenés $meses mes${meses > 1 ? "es" : ""} gratis de HDF Stats Premium.'; cargando = false; });
                        } catch (e) {
                          setModalState(() { mensaje = '❌ Error al validar el código. Intentá de nuevo.'; cargando = false; });
                        }
                      },
                      child: const Text('APLICAR', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
              ]),
              if (mensaje != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: mensaje!.startsWith('✅') ? const Color(0xFF00C853).withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: mensaje!.startsWith('✅') ? const Color(0xFF00C853).withValues(alpha: 0.4) : Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(mensaje!, style: TextStyle(color: mensaje!.startsWith('✅') ? const Color(0xFF00C853) : Colors.red, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              const Text('HINCHAS HDF STATS', style: TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              SizedBox(
                height: 280,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('hinchas').orderBy('votos', descending: true).limit(10).snapshots(),
                  builder: (context, hSnap) {
                    if (hSnap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
                    final hdocs = hSnap.data?.docs ?? [];
                    if (hdocs.isEmpty) return const Center(child: Text('Sin datos aun', style: TextStyle(color: Colors.white38, fontSize: 12)));
                    final htotal = hdocs.fold<int>(0, (s, d) => s + (((d.data() as Map<String, dynamic>)['votos'] as num?)?.toInt() ?? 0));
                    return ListView.builder(
                      itemCount: hdocs.length,
                      itemBuilder: (ctx, hi) {
                        final hdata = hdocs[hi].data() as Map<String, dynamic>;
                        final hnombre = hdata['nombre'] as String? ?? '';
                        final hescudo = hdata['escudo'] as String? ?? '';
                        final hvotos = (hdata['votos'] as num?)?.toInt() ?? 0;
                        final hpct = htotal > 0 ? hvotos / htotal : 0.0;
                        final hesMio = _equipoFavoritoId?.toString() == hdocs[hi].id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            SizedBox(width: 20, child: Text('${hi+1}', style: TextStyle(color: hi==0?const Color(0xFFFFD700):hi==1?const Color(0xFFC0C0C0):hi==2?const Color(0xFFCD7F32):Colors.white38, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                            const SizedBox(width: 6),
                            if (hescudo.isNotEmpty) Image.network(hescudo, width: 22, height: 22, errorBuilder: (_, __, ___) => const SizedBox(width: 22)) else const SizedBox(width: 22),
                            const SizedBox(width: 8),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(hnombre, style: TextStyle(color: hesMio ? const Color(0xFF00C853) : Colors.white70, fontSize: 12, fontWeight: hesMio ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis)),
                                Text('$hvotos', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                if (hesMio) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.favorite, color: Color(0xFF00C853), size: 11)),
                              ]),
                              const SizedBox(height: 3),
                              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: hpct, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(hi==0?const Color(0xFFFFD700):hesMio?const Color(0xFF00C853):const Color(0xFF1565C0)), minHeight: 4)),
                            ])),
                          ]),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ]),
            ), // SingleChildScrollView
          ),
        ),
      ),
    );
  }

  Widget _buildResultados() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getPartidosHoy(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No hay partidos hoy', style: TextStyle(color: Colors.white54)));
        }
        final ligaPartidos = snapshot.data!;

        Widget buildCard(Map<String, dynamic> partido) {
          final teams = partido['teams'];
          final goals = partido['goals'];
          final fixture = partido['fixture'];
          final status = fixture['status']['short'];
          final local = teams['home']['name'] as String;
          final visitante = teams['away']['name'] as String;
          final homeId = teams['home']['id'] as int?;
          final awayId = teams['away']['id'] as int?;
          final golesLocal = goals['home']?.toString() ?? '-';
          final golesVisitante = goals['away']?.toString() ?? '-';
          final fixtureId = fixture['id'] as int?;
          String statusDisplay;
          bool jugado = false;
          if (status == 'FT' || status == 'AET' || status == 'PEN') {
            statusDisplay = 'FT'; jugado = true;
          } else if (status == '1H' || status == '2H' || status == 'ET') {
            statusDisplay = "${fixture['status']['elapsed']}'";
          } else if (status == 'NS') {
            final date = DateTime.parse(fixture['date'].toString()).toLocal();
            statusDisplay = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
          } else {
            statusDisplay = status;
          }
          final esFavorito = _equipoFavoritoId != null && _equipoFavoritoId != -1 &&
              (homeId == _equipoFavoritoId || awayId == _equipoFavoritoId);
          return _matchCard(local, visitante, golesLocal, golesVisitante, statusDisplay, jugado, fixtureId, esFavorito: esFavorito);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('HOY - LIGA PROFESIONAL'),
            const SizedBox(height: 12),
            ...ligaPartidos.map(buildCard),
          ],
        );
      },
    );
  }

  Widget _matchCard(String home, String away, String hScore, String aScore, String status, bool jugado, int? fixtureId, {bool esFavorito = false}) {
    final bool isLive = status.contains("'");
    final bool isFinished = status == 'FT';
    return GestureDetector(
      onTap: () => _mostrarDetalle(context, home, away, '$hScore - $aScore', jugado || isFinished, fixtureId: fixtureId, isLive: isLive, minuto: status),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2A3B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: esFavorito ? const Color(0xFFFFD700).withValues(alpha: 0.8) : isLive ? const Color(0xFF00C853).withValues(alpha: 0.5) : Colors.transparent,
            width: esFavorito ? 2.0 : 1.0,
          ),
        ),
        child: Row(children: [
          Expanded(child: Text(home, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(8)),
            child: Text('$hScore - $aScore', style: TextStyle(color: isLive ? const Color(0xFF00C853) : Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(away, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isLive ? const Color(0xFF00C853).withValues(alpha: 0.2) : isFinished ? Colors.white12 : const Color(0xFF1565C0).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(status, style: TextStyle(color: isLive ? const Color(0xFF00C853) : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  Widget _buildTablas() {
    return DefaultTabController(
      length: 9,
      child: Column(children: [
        Container(
          color: const Color(0xFF1B2A3B),
          child: TabBar(
            isScrollable: true,
            indicatorColor: const Color(0xFF00C853),
            labelColor: const Color(0xFF00C853),
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
            tabs: const [
              Tab(text: 'POSICIONES'),
              Tab(text: 'LOCAL'),
              Tab(text: 'VISITANTE'),
              Tab(text: 'ULTIMOS 5'),
              Tab(text: '1ER TIEMPO'),
              Tab(text: '2DO TIEMPO'),
              Tab(text: 'ÁRBITROS'),
              Tab(text: 'MORAL ✨'),
              Tab(text: 'CRUCES 🏆'),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _tabPosiciones(),
          _tabRendimiento('home'),
          _tabRendimiento('away'),
          _tabUltimos5(),
          _tabTiempo('first'),
          _tabTiempo('second'),
          _tabArbitros(),
          _buildTablaMoral(),
          _buildCruces(),
        ])),
      ]),
    );
  }

  Widget _tabPosiciones() {
    // Construir mapa de equipos jugando en vivo con su marcador
    final Map<int, String> enVivoMap = {};
    for (var p in _partidosEnVivo) {
      final hId = p['teams']['home']['id'] as int;
      final aId = p['teams']['away']['id'] as int;
      final gH = p['goals']['home']?.toString() ?? '0';
      final gA = p['goals']['away']?.toString() ?? '0';
      final min = p['fixture']['status']['elapsed']?.toString() ?? '';
      enVivoMap[hId] = '$gH-$gA $min\' ';
      enVivoMap[aId] = '$gH-$gA $min\' ';
    }
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: ApiService.getTablas(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No hay datos', style: TextStyle(color: Colors.white54)));
        final zonas = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...zonas.entries.where((z) => z.key == 'Zona A' || z.key == 'Zona B').map((zona) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(zona.key.toUpperCase()),
                const SizedBox(height: 8),
                _tablaHeader(),
                ...zona.value.map((equipo) {
                  final team = equipo['team'];
                  final stats = equipo['all'];
                  final teamId = team['id'] as int;
                  final vivo = enVivoMap[teamId];
                  final nombre = vivo != null ? '${team['name']} ($vivo)' : team['name'];
                  return _tablaRow(equipo['rank'].toString(), nombre, stats['played'].toString(), stats['win'].toString(), stats['draw'].toString(), stats['lose'].toString(), equipo['points'].toString(), enVivo: vivo != null, logo: team['logo'] as String?, teamId: team['id'] as int?);
                }),
                const SizedBox(height: 16),
              ],
            )),
          ],
        );
      },
    );
  }

  Widget _tabDTs() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getTablaDTs(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Color(0xFF00C853)),
            SizedBox(height: 12),
            Text('Cargando DTs...', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        );
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(
          child: Text('Sin datos de DTs', style: TextStyle(color: Colors.white54)),
        );
        final dts = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('TABLA DE DTs — APERTURA 2026'),
            const SizedBox(height: 12),
            ...dts.asMap().entries.map((e) => _dtCard(e.key + 1, e.value)),
          ],
        );
      },
    );
  }

  Widget _dtCard(int pos, Map<String, dynamic> dt) {
    final nombre = dt['nombre'] as String;
    final foto = dt['foto'] as String?;
    final equipo = dt['equipo'] as String;
    final partidos = dt['partidos'] as int;
    final victorias = dt['victorias'] as int;
    final empates = dt['empates'] as int;
    final derrotas = dt['derrotas'] as int;
    final puntos = dt['puntos'] as int;
    final pct = (dt['pctPuntos'] as double).toStringAsFixed(1);
    final rachaActual = dt['rachaActual'] as String;
    final ultimos5 = (dt['ultimos5'] as List).cast<String>();
    final edad = dt['edad'] as int? ?? 0;
    final nacionalidad = dt['nacionalidad'] as String? ?? '';
    final aniosExp = dt['aniosExp'] as int? ?? 0;
    final clubAnterior = dt['clubAnterior'] as String? ?? '';

    Color rachaColor = Colors.white54;
    if (rachaActual.endsWith('W')) rachaColor = const Color(0xFF00C853);
    else if (rachaActual.endsWith('L')) rachaColor = const Color(0xFFFF5252);
    else if (rachaActual.endsWith('D')) rachaColor = Colors.amber;

    Color resultColor(String r) {
      if (r == 'W') return const Color(0xFF00C853);
      if (r == 'L') return const Color(0xFFFF5252);
      return Colors.amber;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SizedBox(width: 24, child: Text('$pos', style: const TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
            const SizedBox(width: 8),
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0D1B2A),
                border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.4), width: 2),
                image: foto != null ? DecorationImage(image: NetworkImage(foto), fit: BoxFit.cover) : null,
              ),
              child: foto == null ? const Icon(Icons.person, color: Color(0xFF00C853), size: 26) : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
              Text(equipo, style: const TextStyle(color: Color(0xFF00C853), fontSize: 11)),
              if (edad > 0 || nacionalidad.isNotEmpty)
                Text(
                  [if (edad > 0) '$edad años', if (nacionalidad.isNotEmpty) nacionalidad].join(' · '),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              if (aniosExp > 0)
                Text('$aniosExp años de carrera', style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$pct%', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 18)),
              Text('$puntos pts · $partidos PJ', style: const TextStyle(color: Colors.white54, fontSize: 10)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: rachaColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: rachaColor.withValues(alpha: 0.4))),
                child: Text(rachaActual, style: TextStyle(color: rachaColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ]),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFF0D1B2A).withValues(alpha: 0.5), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))),
          child: Column(children: [
            Row(children: [
              _statChip('G', victorias.toString(), const Color(0xFF00C853)),
              const SizedBox(width: 6),
              _statChip('E', empates.toString(), Colors.amber),
              const SizedBox(width: 6),
              _statChip('P', derrotas.toString(), const Color(0xFFFF5252)),
              const SizedBox(width: 10),
              Row(children: ultimos5.map((r) => Container(
                width: 20, height: 20,
                margin: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(color: resultColor(r).withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: resultColor(r), width: 1.5)),
                child: Center(child: Text(r, style: TextStyle(color: resultColor(r), fontSize: 9, fontWeight: FontWeight.bold))),
              )).toList()),
            ]),
            if (clubAnterior.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.history, color: Colors.white24, size: 12),
                const SizedBox(width: 4),
                Text('Anterior: $clubAnterior', style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _tabArbitros() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getTablaArbitros(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Color(0xFF00C853)),
            SizedBox(height: 12),
            Text('Cargando árbitros...', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        );
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(
          child: Text('Sin datos de árbitros', style: TextStyle(color: Colors.white54)),
        );
        final arbitros = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('TABLA DE ÁRBITROS — APERTURA 2026'),
            const SizedBox(height: 12),
            ...arbitros.map((a) => _arbitroCard(a)),
          ],
        );
      },
    );
  }

  Widget _arbitroCard(Map<String, dynamic> a) {
    final nombre = a['nombre'] as String;
    final foto = a['foto'] as String?;
    final partidos = a['partidos'] as int;
    final vLocal = a['victoriasLocal'] as int;
    final vVisit = a['victoriasVisitante'] as int;
    final empates = a['empates'] as int;
    final amarillas = a['amarillasTotal'] as int;
    final amarillasLocal = a['amarillasLocal'] as int;
    final amarillasVisit = a['amarillasVisitante'] as int;
    final rojas = a['rojasTotal'] as int;
    final penales = a['penalesTotal'] as int;
    final penalesLocal = a['penalesLocal'] as int;
    final penalesVisit = a['penalesVisitante'] as int;
    final promAm = (a['promAmarillas'] as double).toStringAsFixed(1);
    final favorece = a['favorece'] as String;
    final beneficiado = a['equipoBeneficiado'] as String? ?? '-';
    final perjudicado = a['equipoPerjudicado'] as String? ?? '-';
    final varTotal = a['varTotal'] as int? ?? 0;
    final varGolesAnuladosLocal = a['varGolesAnuladosLocal'] as int? ?? 0;
    final varGolesAnuladosVisit = a['varGolesAnuladosVisitante'] as int? ?? 0;
    final varPenalesConf = a['varPenalesConfirmados'] as int? ?? 0;
    final varPenalesAnul = a['varPenalesAnulados'] as int? ?? 0;
    final varIndice = (a['varIndice'] as double? ?? 0.0).toStringAsFixed(2);
    final golesCorner = a['golesCorner'] as int? ?? 0;

    final totalResultados = vLocal + vVisit + empates;
    final pLocal = totalResultados > 0 ? vLocal / totalResultados : 0.0;
    final pEmpate = totalResultados > 0 ? empates / totalResultados : 0.0;
    final pVisit = totalResultados > 0 ? vVisit / totalResultados : 0.0;

    final totalAm = amarillasLocal + amarillasVisit;
    final pAmLocal = totalAm > 0 ? amarillasLocal / totalAm : 0.5;
    final pAmVisit = totalAm > 0 ? amarillasVisit / totalAm : 0.5;

    final totalPen = penalesLocal + penalesVisit;
    final pPenLocal = totalPen > 0 ? penalesLocal / totalPen : 0.5;

    final favColor = favorece == 'Local'
        ? const Color(0xFF00C853)
        : favorece == 'Visitante'
            ? const Color(0xFF2196F3)
            : Colors.white54;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0D1B2A),
                border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.6), width: 2),
                image: foto != null ? DecorationImage(image: NetworkImage(foto), fit: BoxFit.cover) : null,
              ),
              child: foto == null ? const Icon(Icons.sports, color: Color(0xFF00C853), size: 28) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text('$partidos partidos dirigidos', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 4),
              // Mini stats row
              Row(children: [
                _miniStatBadge('$amarillas', 'âš¡', Colors.amber),
                const SizedBox(width: 4),
                _miniStatBadge('$rojas', '🟥', Colors.red),
                const SizedBox(width: 4),
                _miniStatBadge('$penales', 'âš½', Colors.white70),
                if (golesCorner > 0) ...[
                  const SizedBox(width: 4),
                  _miniStatBadge('$golesCorner', '📐', const Color(0xFFFFD700)),
                ],
              ]),
            ])),
            // Favorece badge grande
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: favColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: favColor.withValues(alpha: 0.5)),
              ),
              child: Column(children: [
                Text('FAVORECE', style: TextStyle(color: favColor.withValues(alpha: 0.7), fontSize: 8, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(favorece, style: TextStyle(color: favColor, fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),
        ),

        // Cuerpo con gráficos
        Container(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(children: [

            // GRAFICO: Resultados Local / Empate / Visitante
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('RESULTADOS', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // Barra segmentada
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 20,
                    child: Row(children: [
                      if (pLocal > 0) Expanded(flex: (pLocal * 100).round(), child: Container(
                        color: const Color(0xFF00C853),
                        alignment: Alignment.center,
                        child: pLocal > 0.12 ? Text('$vLocal', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)) : const SizedBox(),
                      )),
                      if (pEmpate > 0) Expanded(flex: (pEmpate * 100).round(), child: Container(
                        color: Colors.white24,
                        alignment: Alignment.center,
                        child: pEmpate > 0.12 ? Text('$empates', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)) : const SizedBox(),
                      )),
                      if (pVisit > 0) Expanded(flex: (pVisit * 100).round(), child: Container(
                        color: const Color(0xFF2196F3),
                        alignment: Alignment.center,
                        child: pVisit > 0.12 ? Text('$vVisit', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)) : const SizedBox(),
                      )),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  _leyenda('🟢 Local', '${(pLocal*100).round()}%', const Color(0xFF00C853)),
                  _leyenda('⬜ Empate', '${(pEmpate*100).round()}%', Colors.white54),
                  _leyenda('🔵 Visit.', '${(pVisit*100).round()}%', const Color(0xFF2196F3)),
                ]),
              ]),
            ),
            const SizedBox(height: 8),

            // GRAFICOS: Amarillas y Penales en fila
            Row(children: [
              // Amarillas
              Expanded(child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('âš¡', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    const Text('AMARILLAS', style: TextStyle(color: Colors.white38, fontSize: 8, letterSpacing: 1)),
                    const Spacer(),
                    Text('$promAm/p', style: const TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 14,
                      child: Row(children: [
                        Expanded(flex: (pAmLocal * 100).round().clamp(1, 99), child: Container(
                          color: const Color(0xFF00C853).withValues(alpha: 0.7),
                          alignment: Alignment.center,
                          child: Text('$amarillasLocal', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        )),
                        Expanded(flex: (pAmVisit * 100).round().clamp(1, 99), child: Container(
                          color: Colors.amber.withValues(alpha: 0.7),
                          alignment: Alignment.center,
                          child: Text('$amarillasVisit', style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                        )),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('L: $amarillasLocal', style: const TextStyle(color: Color(0xFF00C853), fontSize: 9)),
                    Text('V: $amarillasVisit', style: const TextStyle(color: Colors.amber, fontSize: 9)),
                  ]),
                ]),
              )),
              const SizedBox(width: 8),
              // Penales
              Expanded(child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Text('âš½', style: TextStyle(fontSize: 11)),
                    SizedBox(width: 4),
                    Text('PENALES', style: TextStyle(color: Colors.white38, fontSize: 8, letterSpacing: 1)),
                  ]),
                  const SizedBox(height: 6),
                  if (totalPen > 0) ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 14,
                      child: Row(children: [
                        Expanded(flex: (pPenLocal * 100).round().clamp(1, 99), child: Container(
                          color: const Color(0xFF00C853).withValues(alpha: 0.7),
                          alignment: Alignment.center,
                          child: Text('$penalesLocal', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        )),
                        Expanded(flex: ((1-pPenLocal) * 100).round().clamp(1, 99), child: Container(
                          color: const Color(0xFF2196F3).withValues(alpha: 0.7),
                          alignment: Alignment.center,
                          child: Text('$penalesVisit', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        )),
                      ]),
                    ),
                  ) else Container(
                    height: 14,
                    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(3)),
                    alignment: Alignment.center,
                    child: const Text('Sin penales', style: TextStyle(color: Colors.white38, fontSize: 8)),
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('L: $penalesLocal', style: const TextStyle(color: Color(0xFF00C853), fontSize: 9)),
                    Text('V: $penalesVisit', style: const TextStyle(color: Color(0xFF2196F3), fontSize: 9)),
                  ]),
                ]),
              )),
            ]),
            const SizedBox(height: 8),

            // Beneficiado / Perjudicado
            Row(children: [
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('+ BENEFICIADO', style: TextStyle(color: Color(0xFF00C853), fontSize: 8, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(beneficiado, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ]),
              )),
              const SizedBox(width: 8),
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('- PERJUDICADO', style: TextStyle(color: Colors.red, fontSize: 8, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(perjudicado, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ]),
              )),
            ]),

            // VAR si existe
            if (varTotal > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.25)),
                ),
                child: Column(children: [
                  Row(children: [
                    const Text('📺', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    const Text('VAR', style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    const Spacer(),
                    Text('$varTotal intervenciones · $varIndice/p', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 10)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _varChip('â›" Goles anul.', '${varGolesAnuladosLocal + varGolesAnuladosVisit}', 'L:$varGolesAnuladosLocal V:$varGolesAnuladosVisit'),
                    const SizedBox(width: 6),
                    _varChip('✅ Pen. conf.', '$varPenalesConf', ''),
                    const SizedBox(width: 6),
                    _varChip('❌ Pen. anul.', '$varPenalesAnul', ''),
                  ]),
                ]),
              ),
            ],

            // Goles de corner si hay
            if (golesCorner > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Text('📐', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Goles de córner (olímpico)', style: TextStyle(color: Colors.white70, fontSize: 11))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFFFD700).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                    child: Text('$golesCorner', style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _miniStatBadge(String valor, String emoji, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 9)),
        const SizedBox(width: 2),
        Text(valor, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _leyenda(String label, String valor, Color color) {
    return Expanded(child: Row(children: [
      Text(label, style: TextStyle(color: color, fontSize: 9)),
      const SizedBox(width: 3),
      Text(valor, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    ]));
  }
  Widget _varChip(String label, String valor, String sub) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Text(valor, style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8), textAlign: TextAlign.center),
        if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: Colors.white24, fontSize: 8)),
      ]),
    ));
  }

  Widget _statChip(String label, String valor, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Column(children: [
        Text(valor, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
      ]),
    ));
  }

  Widget _tabRendimiento(String tipo) {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: ApiService.getTablas(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No hay datos', style: TextStyle(color: Colors.white54)));
        final zonas = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...zonas.entries.where((z) => z.key == 'Zona A' || z.key == 'Zona B').map((zona) {
              final equipos = List<Map<String, dynamic>>.from(zona.value);
              equipos.sort((a, b) {
                final sa = a[tipo] as Map<String, dynamic>? ?? {};
                final sb = b[tipo] as Map<String, dynamic>? ?? {};
                final pa = ((sa['win'] as num? ?? 0) * 3) + (sa['draw'] as num? ?? 0);
                final pb = ((sb['win'] as num? ?? 0) * 3) + (sb['draw'] as num? ?? 0);
                return pb.compareTo(pa);
              });
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('${zona.key.toUpperCase()} - ${tipo == 'home' ? 'LOCAL' : 'VISITANTE'}'),
                  const SizedBox(height: 8),
                  _tablaHeader(),
                  ...equipos.asMap().entries.map((entry) {
                    final i = entry.key + 1;
                    final eq = entry.value;
                    final s = eq[tipo] as Map<String, dynamic>? ?? {};
                    final pj = (s['played'] as num? ?? 0).toString();
                    final g = (s['win'] as num? ?? 0).toString();
                    final e = (s['draw'] as num? ?? 0).toString();
                    final p = (s['lose'] as num? ?? 0).toString();
                    final pts = (((s['win'] as num? ?? 0) * 3) + (s['draw'] as num? ?? 0)).toString();
                    return _tablaRow(i.toString(), eq['team']['name'], pj, g, e, p, pts, logo: eq['team']['logo'] as String?, teamId: eq['team']['id'] as int?);
                  }),
                  const SizedBox(height: 16),
                ],
              );
            }),
          ],
        );
      },
    );
  }
Widget _tabTiempo(String tipo) {
  return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
    future: ApiService.getTablasTiempos(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting)
        return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
      if (!snapshot.hasData || snapshot.data!.isEmpty)
        return const Center(child: Text('No hay datos', style: TextStyle(color: Colors.white54)));
      final pts = tipo == 'first' ? 'pts1' : 'pts2';
      final pj  = tipo == 'first' ? 'pj1'  : 'pj2';
      final g   = tipo == 'first' ? 'g1'   : 'g2';
      final e   = tipo == 'first' ? 'e1'   : 'e2';
      final p   = tipo == 'first' ? 'p1'   : 'p2';
      final titulo = tipo == 'first' ? '1ER TIEMPO' : '2DO TIEMPO';
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...snapshot.data!.entries.where((z) => z.key == 'Zona A' || z.key == 'Zona B').map((zona) {
            final equipos = List<Map<String, dynamic>>.from(zona.value);
            equipos.sort((a, b) => (b[pts] as int).compareTo(a[pts] as int));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('${zona.key.toUpperCase()} - $titulo'),
                const SizedBox(height: 8),
                _tablaHeader(),
                ...equipos.asMap().entries.map((entry) {
                  final i = entry.key + 1;
                  final eq = entry.value;
                  return _tablaRow(
                    i.toString(),
                    eq['nombre'] as String,
                    eq[pj].toString(),
                    eq[g].toString(),
                    eq[e].toString(),
                    eq[p].toString(),
                    eq[pts].toString(),
                    logo: eq['logo'] as String?,
                    teamId: eq['id'] as int?,
                  );
                }),
                const SizedBox(height: 16),
              ],
            );
          }),
        ],
      );
    },
  );
}
  Widget _tabUltimos5() {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: ApiService.getTablas(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No hay datos', style: TextStyle(color: Colors.white54)));
        final zonas = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...zonas.entries.where((z) => z.key == 'Zona A' || z.key == 'Zona B').map((zona) {
              final equipos = List<Map<String, dynamic>>.from(zona.value);
              final tabla = equipos.map((eq) {
                final forma = eq['form'] as String? ?? '';
                final ultimos = forma.split('').reversed.take(5).toList();
                int pts = 0;
                for (var r in ultimos) {
                  if (r == 'W') pts += 3;
                  else if (r == 'D') pts += 1;
                }
                return {'nombre': eq['team']['name'], 'logo': eq['team']['logo'], 'pts': pts, 'forma': ultimos.reversed.toList()};
              }).toList();
              tabla.sort((a, b) => (b['pts'] as int).compareTo(a['pts'] as int));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('${zona.key.toUpperCase()} - ULTIMOS 5'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFF1565C0).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                    child: const Row(children: [
                      SizedBox(width: 24, child: Text('#', style: TextStyle(color: Colors.white54, fontSize: 12))),
                      Expanded(child: Text('EQUIPO', style: TextStyle(color: Colors.white54, fontSize: 12))),
                      SizedBox(width: 90, child: Text('FORMA', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
                      SizedBox(width: 32, child: Text('PTS', style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    ]),
                  ),
                  ...tabla.asMap().entries.map((entry) {
                    final i = entry.key + 1;
                    final eq = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        SizedBox(width: 24, child: Text(i.toString(), style: const TextStyle(color: Colors.white54, fontSize: 13))),
                        if (eq['logo'] != null) ...[
                          const SizedBox(width: 4),
                          Image.network(eq['logo'] as String, width: 20, height: 20, errorBuilder: (_, __, ___) => const SizedBox(width: 20)),
                          const SizedBox(width: 6),
                        ] else const SizedBox(width: 8),
                        Expanded(child: Text(eq['nombre'] as String, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
                        SizedBox(width: 90, child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: (eq['forma'] as List<String>).map((r) {
                            final c = r == 'W' ? Colors.green : r == 'D' ? Colors.orange : Colors.red;
                            final t = r == 'W' ? 'G' : r == 'D' ? 'E' : 'P';
                            return Container(
                              width: 16, height: 16,
                              margin: const EdgeInsets.only(left: 2),
                              decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3), border: Border.all(color: c, width: 1)),
                              child: Center(child: Text(t, style: TextStyle(color: c, fontSize: 8, fontWeight: FontWeight.bold))),
                            );
                          }).toList(),
                        )),
                        SizedBox(width: 32, child: Text(eq['pts'].toString(), style: const TextStyle(color: Color(0xFF00C853), fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                      ]),
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              );
            }),
          ],
        );
      },
    );
  }

  Widget _tablaHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF1565C0).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
      child: const Row(children: [
        SizedBox(width: 24, child: Text('#', style: TextStyle(color: Colors.white54, fontSize: 12))),
        Expanded(child: Text('EQUIPO', style: TextStyle(color: Colors.white54, fontSize: 12))),
        SizedBox(width: 28, child: Text('PJ', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
        SizedBox(width: 28, child: Text('G', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
        SizedBox(width: 28, child: Text('E', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
        SizedBox(width: 28, child: Text('P', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
        SizedBox(width: 32, child: Text('PTS', style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
      ]),
    );
  }

  Widget _tablaRow(String pos, String equipo, String pj, String g, String e, String p, String pts, {bool enVivo = false, String? logo, int? teamId}) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: enVivo ? const Color(0xFF00C853).withValues(alpha: 0.08) : const Color(0xFF1B2A3B),
        borderRadius: BorderRadius.circular(8),
        border: enVivo ? Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.4)) : null,
      ),
      child: Row(children: [
        SizedBox(width: 24, child: Text(pos, style: const TextStyle(color: Colors.white54, fontSize: 13))),
        if (logo != null) ...[
          const SizedBox(width: 4),
          _logoConTap(logo, 20, teamId, equipo),
          const SizedBox(width: 6),
        ] else
          const SizedBox(width: 8),
        Expanded(child: Text(equipo, style: TextStyle(color: enVivo ? const Color(0xFF00C853) : Colors.white, fontSize: enVivo ? 12 : 13, fontWeight: FontWeight.w500))),
        SizedBox(width: 28, child: Text(pj, style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center)),
        SizedBox(width: 28, child: Text(g, style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center)),
        SizedBox(width: 28, child: Text(e, style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center)),
        SizedBox(width: 28, child: Text(p, style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center)),
        SizedBox(width: 32, child: Text(pts, style: const TextStyle(color: Color(0xFF00C853), fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
      ]),
    );
  }

  Widget _buildEquipos() {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Container(
          color: const Color(0xFF1B2A3B),
          child: const TabBar(
            indicatorColor: Color(0xFF00C853),
            labelColor: Color(0xFF00C853),
            unselectedLabelColor: Colors.white38,
            labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
            tabs: [
              Tab(text: 'GOLEADORES'),
              Tab(text: 'ASISTENCIAS'),
              Tab(text: 'EFICACIA'),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _tabGoleadores(),
          _tabAsistencias(),
          _tabEficacia(),
        ])),
      ]),
    );
  }

  Widget _tabGoleadores() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getGoleadores(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No hay datos', style: TextStyle(color: Colors.white54)));
        final goleadores = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('GOLEADORES - LIGA PROFESIONAL'),
            const SizedBox(height: 12),
            ...goleadores.asMap().entries.map((entry) {
              final i = entry.key;
              final g = entry.value;
              final player = g['player'];
              final stats = g['statistics'][0];
              return _goleadorCard((i + 1).toString(), player['name'], stats['team']['name'], stats['goals']['total'].toString(), null, null, player['photo'] as String?);
            }),
          ],
        );
      },
    );
  }

  Widget _tabAsistencias() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getAsistencias(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No hay datos', style: TextStyle(color: Colors.white54)));
        final asistentes = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('ASISTENCIAS - LIGA PROFESIONAL'),
            const SizedBox(height: 12),
            ...asistentes.asMap().entries.map((entry) {
              final i = entry.key;
              final g = entry.value;
              final player = g['player'];
              final stats = g['statistics'][0];
              final asistencias = stats['goals']['assists'] ?? 0;
              return _goleadorCard((i + 1).toString(), player['name'], stats['team']['name'], asistencias.toString(), null, null, player['photo'] as String?);
            }),
          ],
        );
      },
    );
  }

  Widget _tabEficacia() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getEficaciaGoleadores(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No hay datos', style: TextStyle(color: Colors.white54)));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Builder(builder: (ctx) {
              final ref = snapshot.data!.isNotEmpty ? snapshot.data!.first : <String,dynamic>{};
              final min = ref['minimoRef'] ?? 0;
              final max = ref['maxRef'] ?? 0;
              return _sectionTitle('EFICACIA — MIN $min PARTIDOS DE $max');
            }),
            const SizedBox(height: 12),
            ...snapshot.data!.asMap().entries.map((entry) {
              final i = entry.key;
              final g = entry.value;
              final ratio = (g['ratio'] as double).toStringAsFixed(2);
              final sub = '${g["goles"]} goles en ${g["partidos"]} partidos';
              return _goleadorCard((i + 1).toString(), g['nombre'], g['equipo'], ratio, sub, 'c/', g['foto'] as String?);
            }),
          ],
        );
      },
    );
  }

  Widget _goleadorCard(String pos, String nombre, String equipo, String valor, String? sub, String? prefijo, String? foto) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        SizedBox(width: 28, child: Text(pos, style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        const SizedBox(width: 10),
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0D1B2A),
            image: foto != null ? DecorationImage(image: NetworkImage(foto), fit: BoxFit.cover) : null,
          ),
          child: foto == null ? const Icon(Icons.person, color: Colors.white38, size: 20) : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          Text(equipo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (sub != null) Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFF00C853).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.4))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (prefijo != null) Text(prefijo, style: const TextStyle(color: Colors.white54, fontSize: 9)),
            Text(valor, style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildArqueros() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getArqueros(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No hay datos', style: TextStyle(color: Colors.white54)));
        final todos = snapshot.data!;

        // Tab 1: ordenado por menor promedio goles concedidos/partido
        final porPromedio = List<Map<String, dynamic>>.from(todos);
        porPromedio.sort((a, b) {
          final sA = a['statistics'][0]; final sB = b['statistics'][0];
          final pA = (sA['games']?['appearences'] as int? ?? 1).toDouble();
          final pB = (sB['games']?['appearences'] as int? ?? 1).toDouble();
          final cA = (sA['goals']?['conceded'] as int? ?? 999).toDouble();
          final cB = (sB['goals']?['conceded'] as int? ?? 999).toDouble();
          return (cA / pA).compareTo(cB / pB);
        });

        // Tab 2: ordenado por más vallas invictas
        final porVallas = List<Map<String, dynamic>>.from(todos);
        porVallas.sort((a, b) {
          final iA = a['statistics'][0]['games']?['lineups'] as int? ?? 0;
          final iB = b['statistics'][0]['games']?['lineups'] as int? ?? 0;
          final cA = a['statistics'][0]['goals']?['conceded'] as int? ?? 0;
          final cB = b['statistics'][0]['goals']?['conceded'] as int? ?? 0;
          // vallas invictas = partidos como titular - partidos donde recibió al menos 1 gol
          final vallasA = (iA - cA).clamp(0, iA);
          final vallasB = (iB - cB).clamp(0, iB);
          // ordenar de mayor a menor vallas invictas
          if (vallasB != vallasA) return vallasB.compareTo(vallasA);
          // desempate: más partidos jugados
          return iB.compareTo(iA);
        });

        // Tab 3: ordenado por más minutos sin goles (minutos/goles concedidos)
        final porMinutos = List<Map<String, dynamic>>.from(todos);
        porMinutos.sort((a, b) {
          final mA = a['minutosSinGol'] as int? ?? 0;
          final mB = b['minutosSinGol'] as int? ?? 0;
          return mB.compareTo(mA);
        });

        return DefaultTabController(
          length: 3,
          child: Column(children: [
            Container(
              color: const Color(0xFF0D1B2A),
              child: const TabBar(
                labelColor: Color(0xFF00C853),
                unselectedLabelColor: Colors.white38,
                indicatorColor: Color(0xFF00C853),
                labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                tabs: [
                  Tab(text: 'PROMEDIO'),
                  Tab(text: 'VALLAS INVICTAS'),
                  Tab(text: 'MIN/GOL'),
                ],
              ),
            ),
            Expanded(child: TabBarView(children: [
              // Tab 1: Promedio goles concedidos
              ListView(padding: const EdgeInsets.all(16), children: [
                _sectionTitle('MENOS GOLES CONCEDIDOS/PARTIDO'),
                const SizedBox(height: 12),
                ...porPromedio.asMap().entries.map((e) {
                  final a = e.value;
                  final stats = a['statistics'][0];
                  final player = a['player'];
                  final concedidos = stats['goals']?['conceded'] as int? ?? 0;
                  final partidos = stats['games']?['appearences'] as int? ?? 1;
                  final promedio = partidos > 0 ? (concedidos / partidos).toStringAsFixed(2) : '0.00';
                  return _arqueroCard((e.key + 1).toString(), player['name'], stats['team']['name'],
                    concedidos.toString(), '$promedio/pj', partidos.toString(), player['photo'] as String?, Colors.redAccent);
                }),
              ]),
              // Tab 2: Vallas invictas
              ListView(padding: const EdgeInsets.all(16), children: [
                _sectionTitle('VALLAS INVICTAS'),
                const SizedBox(height: 12),
                ...porVallas.asMap().entries.map((e) {
                  final a = e.value;
                  final stats = a['statistics'][0];
                  final player = a['player'];
                  final titulares = stats['games']?['lineups'] as int? ?? 0;
                  final concedidos = stats['goals']?['conceded'] as int? ?? 0;
                  final vallas = (titulares - concedidos).clamp(0, titulares);
                  final saves = stats['goals']?['saves'] as int? ?? 0;
                  return _arqueroCard((e.key + 1).toString(), player['name'], stats['team']['name'],
                    vallas.toString(), '$saves atajadas', titulares.toString(), player['photo'] as String?, const Color(0xFF00C853));
                }),
              ]),
              // Tab 3: Minutos sin goles
              ListView(padding: const EdgeInsets.all(16), children: [
                _sectionTitle('MINUTOS SIN RECIBIR GOL'),
                const SizedBox(height: 12),
                ...porMinutos.asMap().entries.map((e) {
                  final a = e.value;
                  final stats = a['statistics'][0];
                  final player = a['player'];
                  final minSinGol = a['minutosSinGol'] as int? ?? 0;
                  final minutos = stats['games']?['minutes'] as int? ?? 0;
                  return _arqueroCard((e.key + 1).toString(), player['name'], stats['team']['name'],
                    '${minSinGol}m', '$minutos min totales', '', player['photo'] as String?, Colors.amber);
                }),
              ]),
            ])),
          ]),
        );
      },
    );
  }

  Widget _arqueroCard(String pos, String nombre, String equipo, String valor, String sub, String partidos, String? foto, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        SizedBox(width: 28, child: Text(pos, style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        const SizedBox(width: 10),
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0D1B2A),
            image: foto != null ? DecorationImage(image: NetworkImage(foto), fit: BoxFit.cover) : null,
          ),
          child: foto == null ? const Icon(Icons.sports, color: Colors.white38, size: 20) : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          Text(equipo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(sub, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
          child: Text(valor, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ]),
    );
  }

  Widget _buildFixture() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getFixture(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No hay fixture', style: TextStyle(color: Colors.white54)));
        final todos = snapshot.data!;
        final todosOrdenados = List<Map<String, dynamic>>.from(todos);
        todosOrdenados.sort((a, b) => (a['fixture']['id'] as int).compareTo(b['fixture']['id'] as int));
        final mitad = todosOrdenados.length ~/ 2;
        final apertura = todosOrdenados.take(mitad).toList();
        final clausura = todosOrdenados.skip(mitad).toList();
        final filtrados = _torneoActual == 'APERTURA' ? apertura : clausura;
        Map<int, List<Map<String, dynamic>>> porFecha = {};
        for (var p in filtrados) {
          final st = p['fixture']['status']['short'];
          if (st == 'PST' || st == 'CANC' || st == 'TBD') continue;
          final round = p['league']['round'] as String;
          final num = int.tryParse(round.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          porFecha.putIfAbsent(num, () => []).add(p);
        }
        final fechas = porFecha.keys.toList()..sort();
        if (_fechaActual == -1) {
          _fechaActual = 0;
          for (int i = 0; i < fechas.length; i++) {
            final ps = porFecha[fechas[i]]!;
            if (ps.any((p) { final s = p['fixture']['status']['short']; return s == 'FT' || s == 'AET' || s == 'PEN' || s == 'AWD' || s == 'WO'; })) _fechaActual = i;
          }
        }
        final numFecha = fechas[_fechaActual];
        final partidos = porFecha[numFecha]!;
        final hayJugados = partidos.any((p) { final s = p['fixture']['status']['short']; return s == 'FT' || s == 'AET' || s == 'PEN' || s == 'AWD' || s == 'WO'; });
        return Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF0D1B2A),
            child: Row(children: ['APERTURA', 'CLAUSURA'].map((t) => Expanded(child: GestureDetector(
              onTap: () => setState(() { _torneoActual = t; _fechaActual = -1; }),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: _torneoActual == t ? const Color(0xFF00C853) : const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(8)),
                child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: _torneoActual == t ? Colors.black : Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ))).toList()),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1B2A3B),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFF00C853), size: 28), onPressed: _fechaActual > 0 ? () => setState(() => _fechaActual--) : null),
              Column(children: [
                Text('FECHA $numFecha', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2)),
                Text(hayJugados ? 'JUGADA' : 'PROXIMA', style: TextStyle(color: hayJugados ? Colors.white38 : const Color(0xFF00C853), fontSize: 11, letterSpacing: 1)),
              ]),
              IconButton(icon: const Icon(Icons.chevron_right, color: Color(0xFF00C853), size: 28), onPressed: _fechaActual < fechas.length - 1 ? () => setState(() => _fechaActual++) : null),
            ]),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.all(16),
            children: partidos.map((p) {
              final local = p['teams']['home']['name'];
              final visitante = p['teams']['away']['name'];
              final golesL = p['goals']['home']?.toString() ?? '-';
              final golesV = p['goals']['away']?.toString() ?? '-';
              final fecha = DateTime.parse(p['fixture']['date']).toLocal();
              final fixtureId = p['fixture']['id'] as int?;
          final homeId = p['teams']['home']['id'] as int?;
          final awayId = p['teams']['away']['id'] as int?;
              final statusShort = p['fixture']['status']['short'];
              final esJugado = statusShort == 'FT' || statusShort == 'AET' || statusShort == 'PEN' || statusShort == 'AWD' || statusShort == 'WO';
              final hora = esJugado ? '$golesL - $golesV' : '${fecha.day}/${fecha.month} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
              return GestureDetector(
                onTap: () => _mostrarDetalle(context, local, visitante, '$golesL - $golesV', esJugado, fixtureId: fixtureId, homeId: homeId, awayId: awayId),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12), border: Border.all(color: esJugado ? Colors.transparent : const Color(0xFF00C853).withValues(alpha: 0.2))),
                  child: Row(children: [
                    Expanded(child: Text(local, style: TextStyle(color: esJugado ? Colors.white54 : Colors.white, fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(8)),
                      child: Text(hora, style: TextStyle(color: esJugado ? Colors.white70 : const Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(visitante, style: TextStyle(color: esJugado ? Colors.white54 : Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
                ),
              );
            }).toList(),
          )),
        ]);
      },
    );
  }

  Widget _buildEnVivo() {
    if (_partidosEnVivo.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.live_tv, color: Colors.white24, size: 48),
        const SizedBox(height: 16),
        const Text('No hay partidos en vivo', style: TextStyle(color: Colors.white54, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Se actualizará automáticamente', style: TextStyle(color: Colors.white38, fontSize: 13)),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: _actualizarEnVivo,
          icon: const Icon(Icons.refresh, color: Color(0xFF00C853)),
          label: const Text('Actualizar', style: TextStyle(color: Color(0xFF00C853))),
        ),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _actualizarEnVivo,
      color: const Color(0xFF00C853),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _sectionTitle('EN VIVO — LIGA PROFESIONAL'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFF00C853).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF00C853), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                const Text('LIVE', style: TextStyle(color: Color(0xFF00C853), fontSize: 10, fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          ..._partidosEnVivo.map((partido) {
            final teams = partido['teams'];
            final goals = partido['goals'];
            final fixture = partido['fixture'];
            final status = fixture['status'];
            final local = teams['home']['name'] as String;
            final visitante = teams['away']['name'] as String;
            final golesL = goals['home']?.toString() ?? '0';
            final golesV = goals['away']?.toString() ?? '0';
            final minuto = status['elapsed']?.toString() ?? '';
            final eventos = (partido['events'] as List? ?? []).cast<Map<String, dynamic>>();
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1B2A3B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.4)),
              ),
              child: Column(children: [
                // Header con minuto
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C853).withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF00C853), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text("$minuto'", style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                ),
                // Marcador
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Expanded(child: Text(local, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.right)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(8)),
                      child: Text('$golesL - $golesV', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 22)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(visitante, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                  ]),
                ),
                // Últimos eventos
                if (eventos.isNotEmpty) ...[
                  const Divider(color: Colors.white12, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(children: eventos.reversed.take(3).map((e) {
                      final tipo = e['type'] as String? ?? '';
                      final min = e['time']?['elapsed']?.toString() ?? '';
                      final jugador = e['player']?['name'] as String? ?? '';
                      final equipo = e['team']?['name'] as String? ?? '';
                      String icono = tipo == 'Goal' ? '⚽' : tipo == 'Card' ? (e['detail'] == 'Yellow Card' ? '🟡' : '🔴') : '🔄';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Text(icono, style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 6),
                          Text("$min'", style: const TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(jugador, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                          Text(equipo, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ]),
                      );
                    }).toList()),
                  ),
                ],
              ]),
            );
          }),
        ],
      ),
    );
  }

  void _mostrarDetalle(BuildContext context, String local, String visitante, String resultado, bool jugado, {int? fixtureId, int? homeId, int? awayId, bool isLive = false, String minuto = ''}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B2A3B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
        builder: (context, scrollController) => FutureBuilder<List<dynamic>>(
          future: jugado && fixtureId != null
            ? Future.wait([ApiService.getEstadisticasPartido(fixtureId), ApiService.getEventosPartido(fixtureId), ApiService.getLineupsPartido(fixtureId), ApiService.getDetallePartido(fixtureId), ApiService.getPlayersPartido(fixtureId.toString())])
            : Future.wait([Future.value(null), Future.value(<dynamic>[]), Future.value(<dynamic>[]), Future.value(null), Future.value(<dynamic>[]), ApiService.getUltimos5(homeId ?? 0), ApiService.getUltimos5(awayId ?? 0)]),
          builder: (context, snap) {
            final stats = snap.data?[0] as Map<String, dynamic>?;
            final eventos = List<Map<String, dynamic>>.from(snap.data?[1] ?? []);
            final lineups = List<Map<String, dynamic>>.from(snap.data?[2] ?? []);
            final detalle = snap.data != null && snap.data!.length > 3 ? snap.data![3] as Map<String, dynamic>? : null;
            final rachaLocal = !jugado && snap.data != null && snap.data!.length > 5 ? List<Map<String, dynamic>>.from((snap.data![5] as List?) ?? []) : <Map<String, dynamic>>[];
            final rachaVisit = !jugado && snap.data != null && snap.data!.length > 6 ? List<Map<String, dynamic>>.from((snap.data![6] as List?) ?? []) : <Map<String, dynamic>>[];
            final arbitro = detalle?['fixture']?['referee'] ?? 'No disponible';
            final estadio = detalle?['fixture']?['venue']?['name'] ?? '';
            final ciudad = detalle?['fixture']?['venue']?['city'] ?? '';
            String moralLocal = '-', moralVisitante = '-', moralDesc = 'Calculando...';
            if (stats != null && stats['response'] != null && (stats['response'] as List).length >= 2) {
              final statLocal = List<Map<String, dynamic>>.from(stats['response'][0]['statistics'] ?? []);
              final statVisit = List<Map<String, dynamic>>.from(stats['response'][1]['statistics'] ?? []);
              double posLocal = 0, posVisit = 0;
              int tirosLocal = 0, tirosVisit = 0, cornersLocal = 0, cornersVisit = 0;
              for (var s in statLocal) {
                if (s['type'] == 'Ball Possession') posLocal = double.tryParse(s['value']?.toString().replaceAll('%', '') ?? '0') ?? 0;
                if (s['type'] == 'Shots on Goal') tirosLocal = int.tryParse(s['value']?.toString() ?? '0') ?? 0;
                if (s['type'] == 'Corner Kicks') cornersLocal = int.tryParse(s['value']?.toString() ?? '0') ?? 0;
              }
              for (var s in statVisit) {
                if (s['type'] == 'Ball Possession') posVisit = double.tryParse(s['value']?.toString().replaceAll('%', '') ?? '0') ?? 0;
                if (s['type'] == 'Shots on Goal') tirosVisit = int.tryParse(s['value']?.toString() ?? '0') ?? 0;
                if (s['type'] == 'Corner Kicks') cornersVisit = int.tryParse(s['value']?.toString() ?? '0') ?? 0;
              }
              final partes = resultado.split('-');
              final int glLocal = int.tryParse(partes.isNotEmpty ? partes[0].trim() : '0') ?? 0;
              final int glVisit = int.tryParse(partes.length > 1 ? partes[1].trim() : '0') ?? 0;
              int moralL = glLocal, moralV = glVisit;
              final double difPos = posLocal - posVisit;
              final int difTiros = tirosLocal - tirosVisit;
              final int difCorners = cornersLocal - cornersVisit;
              double dominio = 0;
              if (difPos.abs() > 25) dominio += difPos > 0 ? 1.5 : -1.5;
              else if (difPos.abs() > 15) dominio += difPos > 0 ? 1.0 : -1.0;
              if (difTiros.abs() >= 3) dominio += difTiros > 0 ? 1.0 : -1.0;
              else if (difTiros.abs() >= 1) dominio += difTiros > 0 ? 0.5 : -0.5;
              if (difCorners.abs() >= 5) dominio += difCorners > 0 ? 0.5 : -0.5;
              final int diferencia = (glLocal - glVisit).abs();
              final int ajuste = dominio.round().clamp(-1, 1);
              moralL += ajuste; moralV -= ajuste;
              if (moralL < 0) moralL = 0;
              if (moralV < 0) moralV = 0;
              if (diferencia == 1) {
                if (glLocal > glVisit && moralL < moralV) moralL = moralV;
                if (glVisit > glLocal && moralV < moralL) moralV = moralL;
              }
              if (glLocal == glVisit) {
                if (moralL > moralV + 1) moralL = moralV + 1;
                if (moralV > moralL + 1) moralV = moralL + 1;
              }
              moralLocal = moralL.toString();
              moralVisitante = moralV.toString();
              moralDesc = moralL > moralV ? '$local merecio ganar' : moralV > moralL ? '$visitante merecio ganar' : 'El resultado fue justo';
              // Guardar Resultado Moral en Firestore para Tabla Moral Acumulada
              if (jugado && fixtureId != null) {
                final homeTeamId = snap.data?[0]?['response']?[0]?['teams']?['home']?['id']?.toString() ?? '';
                final awayTeamId = snap.data?[0]?['response']?[0]?['teams']?['away']?['id']?.toString() ?? '';
                FirebaseFirestore.instance.collection('resultados_morales').doc(fixtureId.toString()).set({
                  'fixtureId': fixtureId,
                  'homeId': homeTeamId,
                  'awayId': awayTeamId,
                  'homeNombre': local,
                  'awayNombre': visitante,
                  'moralLocal': moralL,
                  'moralVisitante': moralV,
                  'ts': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              }
            }
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  Expanded(child: Text(local, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(10)),
                    child: Text(resultado, style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 24)),
                  ),
                  Expanded(child: Text(visitante, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)),
                ]),
                const SizedBox(height: 20),
                if (jugado && fixtureId != null) ...[
                  if (snap.connectionState == ConnectionState.waiting)
                    const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFF00C853))))
                  else if (stats != null) ...[
                    _detalleSeccion('INFO DEL PARTIDO'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Column(children: [
                        Row(children: [const Icon(Icons.sports, color: Color(0xFF00C853), size: 16), const SizedBox(width: 8), Text('Arbitro: $arbitro', style: const TextStyle(color: Colors.white70, fontSize: 13))]),
                        const SizedBox(height: 6),
                        Row(children: [const Icon(Icons.stadium, color: Color(0xFF00C853), size: 16), const SizedBox(width: 8), Text('$estadio${ciudad.isNotEmpty ? " - $ciudad" : ""}', style: const TextStyle(color: Colors.white70, fontSize: 13))]),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    _detalleSeccion('PODIO DEL PARTIDO'),
                    Builder(builder: (context) {
                      final jugadores = List<Map<String, dynamic>>.from(snap.data?[4] ?? []);
                      if (jugadores.isEmpty) return const SizedBox.shrink();
                      final top = jugadores.take(3).toList();
                      final orden = [
                        if (top.length > 1) top[1],
                        top[0],
                        if (top.length > 2) top[2],
                      ];
                      const medallas = ['🥈', '🥇', '🥉'];
                      const medallaColors = [Color(0xFFC0C0C0), Color(0xFFFFD700), Color(0xFFCD7F32)];
                      const alturas = [90.0, 120.0, 70.0];
                      const posLabels = ['2°', '1°', '3°'];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(orden.length, (vi) {
                            final j = orden[vi];
                            final rating = j['rating'] as double;
                            final foto = j['foto'] as String? ?? '';
                            final nombre = (j['nombre'] as String).split(' ').last;
                            final equipo = j['equipo'] as String;
                            final altura = alturas[vi];
                            final medallaColor = medallaColors[vi];
                            final posLabel = posLabels[vi];
                            final esPrimero = vi == 1;
                            return Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: medallaColor, width: esPrimero ? 3 : 2),
                                          boxShadow: [BoxShadow(color: medallaColor.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1)],
                                        ),
                                        child: CircleAvatar(
                                          radius: esPrimero ? 34 : 26,
                                          backgroundColor: const Color(0xFF1B2A3B),
                                          backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                                          child: foto.isEmpty ? const Icon(Icons.person, color: Colors.white38) : null,
                                        ),
                                      ),
                                      Positioned(
                                        bottom: -6,
                                        right: -4,
                                        child: Text(medallas[vi], style: TextStyle(fontSize: esPrimero ? 16 : 13)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(nombre, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1, textAlign: TextAlign.center),
                                  const SizedBox(height: 2),
                                  Text(equipo, style: const TextStyle(color: Colors.white38, fontSize: 9), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: rating >= 7.5 ? Colors.green : rating >= 6.5 ? const Color(0xFFFF9800) : Colors.red,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: altura,
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: medallaColor.withValues(alpha: 0.12),
                                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                                      border: Border(
                                        top: BorderSide(color: medallaColor.withValues(alpha: 0.6), width: 2),
                                        left: BorderSide(color: medallaColor.withValues(alpha: 0.25), width: 1),
                                        right: BorderSide(color: medallaColor.withValues(alpha: 0.25), width: 1),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(posLabel, style: TextStyle(color: medallaColor, fontSize: 22, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    _detalleSeccion('ESTADISTICAS'),
                    ...((stats['response'] as List).isNotEmpty
                      ? (stats['response'][0]['statistics'] as List).where((s) => ['Ball Possession', 'Shots on Goal', 'Corner Kicks', 'Fouls'].contains(s['type'])).map((s) {
                          final i = (stats['response'][0]['statistics'] as List).indexOf(s);
                          final valVisit = i < (stats['response'][1]['statistics'] as List).length ? stats['response'][1]['statistics'][i]['value']?.toString() ?? '-' : '-';
                          String label = s['type'];
                          if (label == 'Ball Possession') label = 'Posesion';
                          if (label == 'Shots on Goal') label = 'Tiros al arco';
                          if (label == 'Corner Kicks') label = 'Corners';
                          if (label == 'Fouls') label = 'Faltas';
                          return _statRow(label, s['value']?.toString() ?? '-', valVisit);
                        })
                      : []),
                    const SizedBox(height: 16),
                    // ALERTA IA — solo en partidos EN VIVO
                    if (isLive) ...[ 
                      _detalleSeccion('🧠 ALERTA IA'),
                      FutureBuilder<String>(
                        future: ApiService.getAlertaIA(
                          local: local,
                          visitante: visitante,
                          resultado: resultado,
                          minuto: minuto,
                          stats: stats,
                          eventos: eventos,
                        ),
                        builder: (context, snapIA) {
                          if (snapIA.connectionState == ConnectionState.waiting) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00C853).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3)),
                              ),
                              child: const Row(children: [
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C853))),
                                SizedBox(width: 10),
                                Text('Analizando el partido...', style: TextStyle(color: Color(0xFF00C853), fontSize: 13)),
                              ]),
                            );
                          }
                          final texto = snapIA.data ?? 'Sin análisis disponible.';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00C853).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3)),
                            ),
                            child: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)),
                          );
                        },
                      ),
                    ],
                    if (jugado && eventos.isNotEmpty) ...[
                      _detalleSeccion('FIGURA DEL PARTIDO HDF'),
                      Builder(builder: (context) {
                        final Map<String, int> puntos = {};
                        final Map<String, String> equipos = {};
                        for (var e in eventos) {
                          final jugador = e['player']?['name'] ?? '';
                          final tipo = e['type'] ?? '';
                          final detalle = e['detail'] ?? '';
                          final equipo = e['team']?['name'] ?? '';
                          if (jugador.isEmpty) continue;
                          puntos[jugador] ??= 0;
                          equipos[jugador] = equipo;
                          if (tipo == 'Goal' && detalle != 'Own Goal') puntos[jugador] = puntos[jugador]! + 3;
                          if (tipo == 'Goal' && detalle == 'Own Goal') puntos[jugador] = puntos[jugador]! - 2;
                          if (tipo == 'subst') { final sale = e['assist']?['name'] ?? ''; if (sale.isNotEmpty) { puntos[sale] ??= 0; equipos[sale] ??= equipo; } }
                          if (tipo == 'Card' && detalle == 'Yellow Card') puntos[jugador] = puntos[jugador]! - 1;
                          if (tipo == 'Card' && detalle == 'Red Card') puntos[jugador] = puntos[jugador]! - 3;
                        }
                        if (puntos.isEmpty) return const SizedBox();
                        final jugadores = List<Map<String, dynamic>>.from(snap.data?[4] ?? []);
                        final sorted = puntos.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                        final figura = jugadores.isNotEmpty ? MapEntry(jugadores.first['nombre'] as String, 0) : sorted.first;

                        // Para qué te traje: peor RATING entre los que jugaron al menos 30 min
                        // Si no hay ratings, usar el de menor puntaje por eventos con puntos negativos
                        MapEntry<String, dynamic> peor;
                        final conRating = jugadores.where((j) => j['tieneRating'] == true && (j['minutos'] as int? ?? 0) >= 30).toList();
                        if (conRating.isNotEmpty) {
                          conRating.sort((a, b) => (a['rating'] as double).compareTo(b['rating'] as double));
                          final peorJugador = conRating.first;
                          peor = MapEntry(peorJugador['nombre'] as String, peorJugador['rating']);
                          equipos[peorJugador['nombre'] as String] ??= peorJugador['equipo'] as String? ?? '';
                        } else {
                          // Fallback: peor puntuado por eventos (solo negativos, con al menos -1)
                          final conNegativos = sorted.where((e) => e.value < 0).toList();
                          peor = conNegativos.isNotEmpty ? conNegativos.last : sorted.last;
                        }
                        return Column(children: [
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFF00C853).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3))),
                            child: Row(children: [
                              const Text('⭐', style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('FIGURA DEL PARTIDO', style: TextStyle(color: Color(0xFF00C853), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                                Text(figura.key, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                                Text(equipos[figura.key] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              ])),
                            ]),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
                            child: Row(children: [
                              const Text('😤', style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('PARA QUE TE TRAJE', style: TextStyle(color: Colors.red, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                                Text(peor.key, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                                Text(equipos[peor.key] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              ])),
                            ]),
                          ),
                          const SizedBox(height: 8),
                        ]);
                      }),
                    ],
                    _detalleSeccion('RESULTADO MORAL'),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFF00C853).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3))),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          Text(local, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          Text('$moralLocal - $moralVisitante', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 20)),
                          Text(visitante, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ]),
                        const SizedBox(height: 8),
                        Text('🧠 $moralDesc', style: const TextStyle(color: Color(0xFF00C853), fontSize: 12), textAlign: TextAlign.center),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    _detalleSeccion('INCIDENCIAS'),
                    if (eventos.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Sin incidencias disponibles', style: TextStyle(color: Colors.white38, fontSize: 13)))
                    else
                      ...eventos.where((e) => ['Goal', 'Card', 'subst', 'Var'].contains(e['type'])).map((e) {
                        final tipo = e['type'];
                        final minuto = "${e['time']['elapsed']}'";
                        final equipo = e['team']['name'] ?? '';
                        String icono = 'âš½';
                        String tipoText = 'Gol: ${e['player']['name'] ?? ''}';
                        if (tipo == 'Card') {
                          icono = e['detail'] == 'Yellow Card' ? '🟡' : '🔴';
                          tipoText = '${e['detail'] == 'Yellow Card' ? 'Amarilla' : 'Roja'}: ${e['player']['name'] ?? ''}';
                        } else if (tipo == 'subst') {
                          icono = '🔄';
                          tipoText = 'Entra: ${e['player']['name'] ?? ''} / Sale: ${e['assist']['name'] ?? ''}';
                        } else if (tipo == 'Var') {
                          icono = '📺';
                          final detail = e['detail'] ?? '';
                          String varDesc = 'VAR';
                          if (detail == 'Goal cancelled') varDesc = 'VAR — Gol anulado';
                          else if (detail == 'Penalty confirmed') varDesc = 'VAR — Penal confirmado';
                          else if (detail == 'Penalty cancelled') varDesc = 'VAR — Penal anulado';
                          else if (detail == 'Card upgrade') varDesc = 'VAR — Tarjeta revisada';
                          else if (detail.isNotEmpty) varDesc = 'VAR — $detail';
                          tipoText = varDesc;
                        } else if (tipo == 'Goal') {
                          final detail = e['detail'] ?? '';
                          if (detail == 'Own Goal') {
                            icono = 'âš½';
                            tipoText = 'Gol en contra: ${e['player']['name'] ?? ''}';
                          } else if (detail == 'Penalty') {
                            tipoText = 'Penal: ${e['player']['name'] ?? ''}';
                          } else {
                            tipoText = 'Gol: ${e['player']['name'] ?? ''}';
                          }
                        }
                        return _incidencia(icono, minuto, tipoText, equipo, esVar: tipo == 'Var');
                      }),
                    const SizedBox(height: 16),
                    if (lineups.length >= 2) ...[
                      _detalleSeccion('FORMACIONES'),
                      const SizedBox(height: 8),
                      Builder(builder: (ctx) {
                        final pd = List<Map<String, dynamic>>.from(snap.data?[4] ?? []);
                        // Figura = jugador con mayor rating (mismo criterio que la sección FIGURA)
                        final conRating = pd.where((p) => p['tieneRating'] == true).toList();
                        final figuraId = conRating.isNotEmpty
                            ? conRating.reduce((a, b) => (a['rating'] as double) >= (b['rating'] as double) ? a : b)['id'] as int?
                            : null;
                        return _buildCancha(lineups, local, visitante, playersData: pd, figuraId: figuraId);
                      }),
                      const SizedBox(height: 16),
                    ] else ...[
                      _detalleSeccion('FORMACIONES'),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Sin formaciones disponibles', style: TextStyle(color: Colors.white38, fontSize: 13))),
                    ],
                  ] else ...[
                    const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('No hay estadisticas disponibles', style: TextStyle(color: Colors.white38), textAlign: TextAlign.center)),
                  ],
                ] else if (!jugado) ...[
                  _detalleSeccion('RACHAS'),
                  if (snap.connectionState == ConnectionState.waiting)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFF00C853))))
                  else ...[
                    _rachaWidget(local, rachaLocal, homeId, esLocal: true),
                    const SizedBox(height: 8),
                    _rachaWidget(visitante, rachaVisit, awayId, esLocal: false),
                  ],
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _detalleSeccion(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(titulo, style: const TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
    );
  }

  Widget _statRow(String stat, String local, String visitante) {
    final vLocal = double.tryParse(local.replaceAll('%', '').replaceAll('-', '0')) ?? 0;
    final vVisit = double.tryParse(visitante.replaceAll('%', '').replaceAll('-', '0')) ?? 0;
    final total = vLocal + vVisit;
    final pLocal = total > 0 ? vLocal / total : 0.5;
    final pVisit = total > 0 ? vVisit / total : 0.5;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(local, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          Text(stat, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          Text(visitante, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(children: [
            Expanded(flex: (pLocal * 100).round(), child: Container(height: 6, color: const Color(0xFF00C853))),
            Expanded(flex: (pVisit * 100).round(), child: Container(height: 6, color: const Color(0xFF2196F3))),
          ]),
        ),
      ]),
    );
  }

  Widget _incidencia(String icono, String minuto, String tipo, String equipo, {bool esVar = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: esVar ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5) : EdgeInsets.zero,
      decoration: esVar ? BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.35)),
      ) : null,
      child: Row(children: [
        Text(icono, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Text(minuto, style: TextStyle(
          color: esVar ? const Color(0xFFFFD700) : const Color(0xFF00C853),
          fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(child: Text(tipo, style: TextStyle(
          color: esVar ? const Color(0xFFFFD700) : Colors.white70,
          fontSize: 13, fontWeight: esVar ? FontWeight.w600 : FontWeight.normal))),
        Text(equipo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }

  Widget _historialRow(String local, String resultado, String visitante, String ganador) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(child: Text(local, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.right)),
        const SizedBox(width: 8),
        Text(resultado, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(child: Text(visitante, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Text(ganador, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }

  Widget _rachaWidget(String nombreEquipo, List<Map<String, dynamic>> todosPartidos, int? teamId, {required bool esLocal}) {
    if (todosPartidos.isEmpty || teamId == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Text('âž–', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nombreEquipo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            const Text('Sin datos disponibles', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ])),
        ]),
      );
    }

    // Filtrar partidos según condición (local o visitante)
    final condicion = esLocal ? 'local' : 'visitante';
    final filtrados = todosPartidos.where((p) {
      final hId = p['teams']['home']['id'] as int?;
      final aId = p['teams']['away']['id'] as int?;
      return esLocal ? hId == teamId : aId == teamId;
    }).toList();

    // Calcular racha general (todos los partidos)
    int sinGanarGen = 0, sinPerderGen = 0, ganandoGen = 0;
    bool rgGen = true, rspGen = true, rsgGen = true;
    for (var p in todosPartidos) {
      final hId = p['teams']['home']['id'] as int?;
      final esL = hId == teamId;
      final gh = p['goals']['home'] as int? ?? 0;
      final ga = p['goals']['away'] as int? ?? 0;
      final gano = esL ? gh > ga : ga > gh;
      final perdio = esL ? gh < ga : ga < gh;
      if (rsgGen && !gano) sinGanarGen++; else rsgGen = false;
      if (rspGen && !perdio) sinPerderGen++; else rspGen = false;
      if (rgGen && gano) ganandoGen++; else rgGen = false;
    }

    // Calcular racha como local/visitante
    int sinGanarCond = 0, sinPerderCond = 0, ganandoCond = 0;
    bool rgCond = true, rspCond = true, rsgCond = true;
    for (var p in filtrados) {
      final hId = p['teams']['home']['id'] as int?;
      final esL = hId == teamId;
      final gh = p['goals']['home'] as int? ?? 0;
      final ga = p['goals']['away'] as int? ?? 0;
      final gano = esL ? gh > ga : ga > gh;
      final perdio = esL ? gh < ga : ga < gh;
      if (rsgCond && !gano) sinGanarCond++; else rsgCond = false;
      if (rspCond && !perdio) sinPerderCond++; else rspCond = false;
      if (rgCond && gano) ganandoCond++; else rgCond = false;
    }

    // Línea 1: racha como local/visitante
    String textoCond;
    Color colorCond;
    if (ganandoCond >= 2) {
      textoCond = 'Ganó sus últimos $ganandoCond de $condicion';
      colorCond = const Color(0xFF00C853);
    } else if (sinPerderCond >= 3) {
      textoCond = 'Lleva $sinPerderCond sin perder de $condicion';
      colorCond = const Color(0xFF00C853);
    } else if (sinGanarCond >= 3) {
      textoCond = 'Lleva $sinGanarCond sin ganar de $condicion';
      colorCond = Colors.orange;
    } else if (sinGanarCond >= 2) {
      textoCond = 'Lleva $sinGanarCond sin ganar de $condicion';
      colorCond = Colors.orange;
    } else if (filtrados.isNotEmpty) {
      final ult = filtrados.first;
      final hId2 = ult['teams']['home']['id'] as int?;
      final esL2 = hId2 == teamId;
      final gh2 = ult['goals']['home'] as int? ?? 0;
      final ga2 = ult['goals']['away'] as int? ?? 0;
      if (esL2 ? gh2 > ga2 : ga2 > gh2) {
        textoCond = 'Ganó el último de $condicion';
        colorCond = const Color(0xFF00C853);
      } else if (gh2 == ga2) {
        textoCond = 'Empató el último de $condicion';
        colorCond = Colors.white54;
      } else {
        textoCond = 'Perdió el último de $condicion';
        colorCond = Colors.red;
      }
    } else {
      textoCond = 'Sin partidos de $condicion aún';
      colorCond = Colors.white38;
    }

    // Línea 2: racha general
    String textoGen;
    Color colorGen;
    if (ganandoGen >= 2) {
      textoGen = '$ganandoGen victorias seguidas en general';
      colorGen = const Color(0xFF00C853);
    } else if (sinPerderGen >= 3) {
      textoGen = '$sinPerderGen sin perder en general';
      colorGen = const Color(0xFF00C853);
    } else if (sinGanarGen >= 3) {
      textoGen = '$sinGanarGen sin ganar en general';
      colorGen = Colors.orange;
    } else if (sinGanarGen >= 2) {
      textoGen = '$sinGanarGen sin ganar en general';
      colorGen = Colors.orange;
    } else if (todosPartidos.isNotEmpty) {
      final ult = todosPartidos.first;
      final hId3 = ult['teams']['home']['id'] as int?;
      final esL3 = hId3 == teamId;
      final gh3 = ult['goals']['home'] as int? ?? 0;
      final ga3 = ult['goals']['away'] as int? ?? 0;
      if (esL3 ? gh3 > ga3 : ga3 > gh3) {
        textoGen = 'Ganó el último partido';
        colorGen = const Color(0xFF00C853);
      } else if (gh3 == ga3) {
        textoGen = 'Empató el último partido';
        colorGen = Colors.white54;
      } else {
        textoGen = 'Perdió el último partido';
        colorGen = Colors.red;
      }
    } else {
      textoGen = 'Sin datos generales';
      colorGen = Colors.white38;
    }

    final colorBorde = colorCond == const Color(0xFF00C853) ? const Color(0xFF00C853) : colorCond == Colors.orange ? Colors.orange : colorCond == Colors.red ? Colors.red : Colors.white24;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorBorde.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorBorde.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(nombreEquipo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        Text(textoCond, style: TextStyle(color: colorCond, fontSize: 12)),
        const SizedBox(height: 2),
        Text(textoGen, style: TextStyle(color: colorGen, fontSize: 12)),
      ]),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(color: Color(0xFF00C853), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 2));
  }

  Widget _buildCancha(List<Map<String, dynamic>> lineups, String local, String visitante, {List<Map<String, dynamic>> playersData = const [], int? figuraId}) {
    return _buildFormacionConSolapas(lineups, local, visitante, playersData: playersData, figuraId: figuraId);
  }

  Widget _buildFormacionConSolapas(List<Map<String, dynamic>> lineups, String local, String visitante, {List<Map<String, dynamic>> playersData = const [], int? figuraId}) {
    final teamLocal = lineups[0];
    final teamVisit = lineups[1];
    final formLocal = teamLocal['formation'] ?? '';
    final formVisit = teamVisit['formation'] ?? '';
    final playersLocal = List<Map<String, dynamic>>.from(teamLocal['startXI'] ?? []);
    final playersVisit = List<Map<String, dynamic>>.from(teamVisit['startXI'] ?? []);
    final subsLocal = List<Map<String, dynamic>>.from(teamLocal['substitutes'] ?? []);
    final subsVisit = List<Map<String, dynamic>>.from(teamVisit['substitutes'] ?? []);
    final coachLocal = teamLocal['coach']?['name'] as String? ?? '';
    final coachVisit = teamVisit['coach']?['name'] as String? ?? '';

    // Mapa rápido de stats por player id
    final Map<int, Map<String, dynamic>> statsMap = {};
    for (var p in playersData) {
      final id = p['id'];
      if (id != null) statsMap[id as int] = p;
    }

    // Obtener teamId local y visitante desde lineups
    final teamLocalId = teamLocal['team']?['id'] as int?;
    final teamVisitId = teamVisit['team']?['id'] as int?;

    Map<int, List<Map<String, dynamic>>> groupByPos(List<Map<String, dynamic>> players) {
      final Map<int, List<Map<String, dynamic>>> rows = {};
      for (var p in players) {
        final pos = (p['player']['pos'] as String? ?? 'M');
        int row;
        if (pos == 'G') row = 1;
        else if (pos == 'D') row = 2;
        else if (pos == 'M') row = 3;
        else row = 4;
        rows.putIfAbsent(row, () => []).add(p);
      }
      return rows;
    }

    Widget buildPlayerDot(Map<String, dynamic> p, bool isLocal) {
      final playerId = p['player']['id'] as int?;
      final stats = playerId != null ? statsMap[playerId] : null;
      final name = (p['player']['name'] ?? '') as String;
      final shortName = name.split(' ').last;
      final esCap = stats?['capitan'] == true;
      final foto = stats?['foto'] as String?;
      final number = (p['player']['number']?.toString().isNotEmpty == true)
          ? p['player']['number'].toString()
          : (stats?['numero'] != null && stats!['numero'] != 0)
              ? stats['numero'].toString()
              : '';
      final goles = stats?['goles'] as int? ?? 0;
      final amarillas = stats?['amarillas'] as int? ?? 0;
      final rojas = stats?['rojas'] as int? ?? 0;
      final esMejor = figuraId != null && playerId == figuraId;

      return Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isLocal ? const Color(0xFF00C853) : const Color(0xFF2196F3), width: 2),
                image: foto != null ? DecorationImage(image: NetworkImage(foto), fit: BoxFit.cover) : null,
                color: isLocal ? const Color(0xFF00C853) : const Color(0xFF2196F3),
              ),
              child: foto == null ? Center(child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))) : null,
            ),
            // ⭐ mejor jugador — arriba centro
            if (esMejor)
              const Positioned(
                top: -10, left: 0, right: 0,
                child: Center(child: Text('⭐', style: TextStyle(fontSize: 10))),
              ),
            // C capitán — arriba derecha
            if (esCap)
              Positioned(
                top: -4, right: -4,
                child: Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(color: Color(0xFFFFD700), shape: BoxShape.circle),
                  child: const Center(child: Text('C', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold))),
                ),
              ),
            // Número camiseta — abajo izquierda
            if (number.isNotEmpty)
              Positioned(
                bottom: -2, left: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: isLocal ? const Color(0xFF00C853) : const Color(0xFF2196F3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF0D1B2A), width: 1),
                  ),
                  child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
                ),
              ),
            // ⚽ goles — arriba izquierda
            if (goles > 0)
              Positioned(
                top: -4, left: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1B2A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Text(goles == 1 ? 'âš½' : 'âš½$goles', style: const TextStyle(fontSize: 8)),
                ),
              ),
            // Tarjeta — abajo derecha (roja tiene prioridad sobre amarilla)
            if (rojas > 0)
              Positioned(
                bottom: -2, right: -2,
                child: Container(
                  width: 10, height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5252),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: const Color(0xFF0D1B2A), width: 1),
                  ),
                ),
              )
            else if (amarillas > 0)
              Positioned(
                bottom: -2, right: -2,
                child: Container(
                  width: 10, height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD600),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: const Color(0xFF0D1B2A), width: 1),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        SizedBox(width: 50, child: Text(shortName, style: const TextStyle(color: Colors.white, fontSize: 9), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
        if (stats != null && stats['tieneRating'] == true) ...[
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: () {
                final r = stats['rating'] as double;
                if (r >= 7.5) return const Color(0xFF00C853);
                if (r >= 6.5) return const Color(0xFF1B2A3B);
                return const Color(0xFFFF5252);
              }(),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              (stats['rating'] as double).toStringAsFixed(1),
              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ]);
    }

    Widget buildRows(Map<int, List<Map<String, dynamic>>> rowsMap, bool isLocal, bool invertir) {
      final sortedKeys = rowsMap.keys.toList()..sort();
      if (invertir) sortedKeys.sort((a, b) => b.compareTo(a));
      return Column(mainAxisSize: MainAxisSize.min, children: sortedKeys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: rowsMap[row]!.map((p) => buildPlayerDot(p, isLocal)).toList()),
        );
      }).toList());
    }

    // ── SOLAPA CANCHA ──────────────────────────────────────────────
    Widget tabCancha = SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B5E20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2E7D32), width: 2),
        ),
        child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Text(visitante, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            Text(formVisit, style: const TextStyle(color: Color(0xFF2196F3), fontSize: 12, fontWeight: FontWeight.bold)),
            Text('DT: $coachVisit', style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ])),
          Container(height: 1, color: Colors.white12),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: buildRows(groupByPos(playersVisit), false, false)),
          Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: Colors.white24),
          Container(width: 60, height: 30, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24))),
          Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: Colors.white24),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: buildRows(groupByPos(playersLocal), true, true)),
          Container(height: 1, color: Colors.white12),
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Text(local, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            Text(formLocal, style: const TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold)),
            Text('DT: $coachLocal', style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ])),
          Container(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('SUPLENTES', style: const TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              Expanded(child: Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: subsLocal.map((p) => buildPlayerDot(p, true)).toList())),
              const SizedBox(width: 8),
              Expanded(child: Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: subsVisit.map((p) => buildPlayerDot(p, false)).toList())),
            ]),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );

    // ── HELPERS SOLAPAS ──────────────────────────────────────────────
    Widget headerTabla(List<String> cols) => Container(
      color: const Color(0xFF0D1B2A),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(children: [
        const SizedBox(width: 140),
        ...cols.map((c) => Expanded(child: Text(c, style: const TextStyle(color: Color(0xFF00C853), fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center))),
      ]),
    );

    Widget filaJugador(Map<String, dynamic> p, bool isLocal, List<Widget> celdas) {
      final foto = p['foto'] as String?;
      final nombre = (p['nombre'] ?? '') as String;
      final shortName = nombre.length > 16 ? nombre.substring(0, 16) : nombre;
      final esCap = p['capitan'] == true;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        ),
        child: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: isLocal ? const Color(0xFF00C853) : const Color(0xFF2196F3), width: 1.5),
              image: foto != null ? DecorationImage(image: NetworkImage(foto), fit: BoxFit.cover) : null,
              color: isLocal ? const Color(0xFF1B5E20) : const Color(0xFF0D2B4A),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 106,
            child: Row(children: [
              Flexible(child: Text(shortName, style: const TextStyle(color: Colors.white, fontSize: 11), overflow: TextOverflow.ellipsis)),
              if (esCap) ...[
                const SizedBox(width: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFFFD700), borderRadius: BorderRadius.circular(3)),
                  child: const Text('C', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
          ),
          ...celdas,
        ]),
      );
    }

    Widget celdaStat(String val, {Color color = Colors.white70}) =>
      Expanded(child: Text(val, style: TextStyle(color: color, fontSize: 11), textAlign: TextAlign.center));

    Widget seccionEquipo(String nombre, bool isLocal) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(nombre.toUpperCase(),
        style: TextStyle(
          color: isLocal ? const Color(0xFF00C853) : const Color(0xFF2196F3),
          fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5,
        ),
      ),
    );

    List<Map<String, dynamic>> jugadoresPorEquipo(int? tId) =>
      playersData.where((p) => p['equipoId'] == tId && p['suplente'] == false).toList();

    // ── SOLAPA RENDIMIENTO ──────────────────────────────────────────────
    Widget tabRendimiento = playersData.isEmpty
      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Sin datos de rendimiento', style: TextStyle(color: Colors.white38))))
      : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          headerTabla(['MIN', 'RAT', 'PASES%', 'TIROS']),
          seccionEquipo(local, true),
          ...jugadoresPorEquipo(teamLocalId).map((p) => filaJugador(p, true, [
            celdaStat('${p['minutos']}\''),
            celdaStat(
              (p['tieneRating'] == true) ? (p['rating'] as double).toStringAsFixed(1) : '-',
              color: () {
                final r = p['rating'] as double;
                if (!( p['tieneRating'] == true)) return Colors.white38;
                if (r >= 7.5) return const Color(0xFF00C853);
                if (r >= 6.5) return Colors.white70;
                return const Color(0xFFFF5252);
              }(),
            ),
            celdaStat('${p['pases']}%'),
            celdaStat('${p['tiros']}'),
          ])),
          const SizedBox(height: 8),
          seccionEquipo(visitante, false),
          ...jugadoresPorEquipo(teamVisitId).map((p) => filaJugador(p, false, [
            celdaStat('${p['minutos']}\''),
            celdaStat(
              (p['tieneRating'] == true) ? (p['rating'] as double).toStringAsFixed(1) : '-',
              color: () {
                final r = p['rating'] as double;
                if (!(p['tieneRating'] == true)) return Colors.white38;
                if (r >= 7.5) return const Color(0xFF00C853);
                if (r >= 6.5) return Colors.white70;
                return const Color(0xFFFF5252);
              }(),
            ),
            celdaStat('${p['pases']}%'),
            celdaStat('${p['tiros']}'),
          ])),
          const SizedBox(height: 8),
        ]));

    // ── SOLAPA GOLES ──────────────────────────────────────────────
    Widget tabGoles = playersData.isEmpty
      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Sin datos', style: TextStyle(color: Colors.white38))))
      : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          headerTabla(['GOL', 'AST', 'SAV']),
          seccionEquipo(local, true),
          ...jugadoresPorEquipo(teamLocalId).map((p) => filaJugador(p, true, [
            celdaStat('${p['goles']}', color: (p['goles'] as int) > 0 ? const Color(0xFF00C853) : Colors.white38),
            celdaStat('${p['asistencias']}', color: (p['asistencias'] as int) > 0 ? const Color(0xFF64B5F6) : Colors.white38),
            celdaStat(p['posicion'] == 'G' ? '${p['saves']}' : '-', color: (p['saves'] as int) > 0 ? const Color(0xFFFFD700) : Colors.white38),
          ])),
          const SizedBox(height: 8),
          seccionEquipo(visitante, false),
          ...jugadoresPorEquipo(teamVisitId).map((p) => filaJugador(p, false, [
            celdaStat('${p['goles']}', color: (p['goles'] as int) > 0 ? const Color(0xFF00C853) : Colors.white38),
            celdaStat('${p['asistencias']}', color: (p['asistencias'] as int) > 0 ? const Color(0xFF64B5F6) : Colors.white38),
            celdaStat(p['posicion'] == 'G' ? '${p['saves']}' : '-', color: (p['saves'] as int) > 0 ? const Color(0xFFFFD700) : Colors.white38),
          ])),
          const SizedBox(height: 8),
        ]));

    // ── SOLAPA TARJETAS ──────────────────────────────────────────────
    Widget tabTarjetas = playersData.isEmpty
      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Sin datos', style: TextStyle(color: Colors.white38))))
      : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          headerTabla(['🟨', '🟥', 'FALTAS']),
          seccionEquipo(local, true),
          ...jugadoresPorEquipo(teamLocalId).map((p) => filaJugador(p, true, [
            celdaStat('${p['amarillas']}', color: (p['amarillas'] as int) > 0 ? const Color(0xFFFFD600) : Colors.white38),
            celdaStat('${p['rojas']}', color: (p['rojas'] as int) > 0 ? const Color(0xFFFF5252) : Colors.white38),
            celdaStat('${p['faltas']}', color: (p['faltas'] as int) > 0 ? Colors.white70 : Colors.white38),
          ])),
          const SizedBox(height: 8),
          seccionEquipo(visitante, false),
          ...jugadoresPorEquipo(teamVisitId).map((p) => filaJugador(p, false, [
            celdaStat('${p['amarillas']}', color: (p['amarillas'] as int) > 0 ? const Color(0xFFFFD600) : Colors.white38),
            celdaStat('${p['rojas']}', color: (p['rojas'] as int) > 0 ? const Color(0xFFFF5252) : Colors.white38),
            celdaStat('${p['faltas']}', color: (p['faltas'] as int) > 0 ? Colors.white70 : Colors.white38),
          ])),
          const SizedBox(height: 8),
        ]));

    // ── WRAPPER CON TABS ──────────────────────────────────────────────
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1B2A3B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: const Color(0xFF00C853),
              indicatorWeight: 2,
              labelColor: const Color(0xFF00C853),
              unselectedLabelColor: Colors.white38,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              tabs: const [
                Tab(text: 'CANCHA'),
                Tab(text: 'RENDIMIENTO'),
                Tab(text: 'GOLES'),
                Tab(text: 'TARJETAS'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 520,
            child: TabBarView(
              children: [tabCancha, tabRendimiento, tabGoles, tabTarjetas],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredicciones() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ApiService.getPredicciones(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Color(0xFF00C853)),
            SizedBox(height: 12),
            Text('Analizando próxima fecha...', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        );
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(
          child: Text('No hay partidos para predecir', style: TextStyle(color: Colors.white54)),
        );
        final predicciones = snapshot.data!;
        final fecha = predicciones.first['fecha'];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              const Icon(Icons.auto_graph, color: Color(0xFF00C853), size: 18),
              const SizedBox(width: 8),
              Text('PREDICCIONES — FECHA $fecha', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.5)),
            ]),
            const SizedBox(height: 4),
            const Text('Basado en forma local/visitante e historial h2h', style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 16),
            ...predicciones.map((p) => _prediccionCard(p)),
          ],
        );
      },
    );
  }

  Widget _prediccionCard(Map<String, dynamic> p) {
    final homeName = p['homeName'] as String;
    final awayName = p['awayName'] as String;
    final homeLogo = p['homeLogo'] as String?;
    final awayLogo = p['awayLogo'] as String?;
    final pctL = p['pctLocal'] as double;
    final pctE = p['pctEmpate'] as double;
    final pctV = p['pctVisit'] as double;
    final fechaHora = p['fechaHora'] as String?;

    // Veredicto basado en porcentajes
    String veredicto; Color veredictoColor; double pctVeredicto;
    if (pctL >= pctV && pctL >= pctE) {
      veredicto = 'Gana $homeName'; veredictoColor = const Color(0xFF00C853); pctVeredicto = pctL;
    } else if (pctV >= pctL && pctV >= pctE) {
      veredicto = 'Gana $awayName'; veredictoColor = const Color(0xFF2196F3); pctVeredicto = pctV;
    } else {
      veredicto = 'Empate'; veredictoColor = Colors.amber; pctVeredicto = pctE;
    }

    String horaStr = '';
    if (fechaHora != null) {
      try {
        final dt = DateTime.parse(fechaHora).toLocal();
        horaStr = '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
      } catch (_) {}
    }

    Color resultColor(String r) {
      if (r == 'W') return const Color(0xFF00C853);
      if (r == 'L') return const Color(0xFFFF5252);
      return Colors.amber;
    }

    Widget logoEquipo(String? logo, double size) => logo != null
      ? Image.network(logo, width: size, height: size, errorBuilder: (_, __, ___) => Icon(Icons.shield, color: Colors.white38, size: size))
      : Icon(Icons.shield, color: Colors.white38, size: size);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        if (horaStr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(horaStr, style: const TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center),
          ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(child: Column(children: [
              logoEquipo(homeLogo, 36),
              const SizedBox(height: 6),
              Text(homeName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 8),
            const Text('VS', style: TextStyle(color: Colors.white24, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Expanded(child: Column(children: [
              logoEquipo(awayLogo, 36),
              const SizedBox(height: 6),
              Text(awayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
        // Veredicto principal con porcentaje
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: veredictoColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: veredictoColor.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(veredicto, style: TextStyle(color: veredictoColor, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: veredictoColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
              child: Text('${pctVeredicto.toStringAsFixed(0)}%', style: TextStyle(color: veredictoColor, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
        // Desglose %
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(child: Column(children: [
              Text('${pctL.toStringAsFixed(0)}%', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 13)),
              const Text('Local', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ])),
            Expanded(child: Column(children: [
              Text('${pctE.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
              const Text('Empate', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ])),
            Expanded(child: Column(children: [
              Text('${pctV.toStringAsFixed(0)}%', style: const TextStyle(color: Color(0xFF2196F3), fontWeight: FontWeight.bold, fontSize: 13)),
              const Text('Visitante', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ])),
          ]),
        ),
      ]),
    );
  }

  Widget _buildTablaMoral() {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: _getTablaMoralCached(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
            CircularProgressIndicator(color: Color(0xFF00C853)),
            SizedBox(height: 16),
            Text('Calculando Tabla Moral...', style: TextStyle(color: Colors.white54, fontSize: 13)),
            SizedBox(height: 4),
            Text('Puede tardar unos segundos', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ]));
        }
        final zonas = snapshot.data ?? {};
        if (snapshot.hasError) return Center(child: Text('Error: \${snapshot.error}', style: const TextStyle(color: Colors.red, fontSize: 11)));
        if (zonas.isEmpty) return const Center(child: Text('Calculando... si no carga, verific\u00e1 tu conexi\u00f3n', style: TextStyle(color: Colors.white54)));

        Widget buildZona(String zonaLabel, List<Map<String, dynamic>> tabla) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionTitle('\u2728 TABLA MORAL - $zonaLabel'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(8)),
              child: Row(children: const [
                SizedBox(width: 24, child: Text('#', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                SizedBox(width: 8),
                Expanded(child: Text('EQUIPO', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold))),
                SizedBox(width: 22, child: Text('PJ', style: TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center)),
                SizedBox(width: 22, child: Text('G', style: TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center)),
                SizedBox(width: 22, child: Text('E', style: TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center)),
                SizedBox(width: 22, child: Text('P', style: TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('DG', style: TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center)),
                SizedBox(width: 30, child: Text('PTS', style: TextStyle(color: Color(0xFF00C853), fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                SizedBox(width: 34, child: Text('\u0394Pts', style: TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              ]),
            ),
            const SizedBox(height: 4),
            ...tabla.asMap().entries.map((entry) {
              final i = entry.key;
              final eq = entry.value;
              final logo = eq['logo'] as String? ?? '';
              final pts = eq['pts'] as int;
              final ptsReal = eq['ptsReal'] as int;
              final delta = pts - ptsReal;
              final dg = (eq['gf'] as int) - (eq['gc'] as int);
              final esFav = _equipoFavoritoId != null && eq['id'].toString() == _equipoFavoritoId.toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2A3B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: esFav ? const Color(0xFF00C853).withValues(alpha: 0.5) : Colors.transparent),
                ),
                child: Row(children: [
                  SizedBox(width: 24, child: Text('${i+1}', style: TextStyle(color: i==0?const Color(0xFFFFD700):i==1?const Color(0xFFC0C0C0):i==2?const Color(0xFFCD7F32):Colors.white38, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                  const SizedBox(width: 4),
                  if (logo.isNotEmpty) Image.network(logo, width: 20, height: 20, errorBuilder: (_, __, ___) => const SizedBox(width: 20)) else const SizedBox(width: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text(eq['nombre'] as String, style: TextStyle(color: esFav ? const Color(0xFF00C853) : Colors.white, fontSize: 11, fontWeight: esFav ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis)),
                  SizedBox(width: 22, child: Text('${eq['pj']}', style: const TextStyle(color: Colors.white54, fontSize: 11), textAlign: TextAlign.center)),
                  SizedBox(width: 22, child: Text('${eq['g']}', style: const TextStyle(color: Colors.white54, fontSize: 11), textAlign: TextAlign.center)),
                  SizedBox(width: 22, child: Text('${eq['e']}', style: const TextStyle(color: Colors.white54, fontSize: 11), textAlign: TextAlign.center)),
                  SizedBox(width: 22, child: Text('${eq['p']}', style: const TextStyle(color: Colors.white54, fontSize: 11), textAlign: TextAlign.center)),
                  SizedBox(width: 26, child: Text(dg >= 0 ? '+$dg' : '$dg', style: TextStyle(color: dg > 0 ? Colors.green : dg < 0 ? Colors.red : Colors.white54, fontSize: 11), textAlign: TextAlign.center)),
                  SizedBox(width: 30, child: Text('$pts', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                  SizedBox(width: 34, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                    decoration: BoxDecoration(
                      color: delta > 0 ? Colors.green.withValues(alpha: 0.2) : delta < 0 ? Colors.red.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(delta > 0 ? '+$delta' : '$delta', style: TextStyle(color: delta > 0 ? Colors.green : delta < 0 ? Colors.red : Colors.white38, fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center),
                  )),
                ]),
              );
            }),
            const SizedBox(height: 12),
          ]);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Center(child: Text('Puntos seg\u00fan qui\u00e9n mereci\u00f3 ganar cada partido', style: TextStyle(color: Colors.white38, fontSize: 11))),
            const SizedBox(height: 12),
            if (zonas['Zona A'] != null) buildZona('Zona A', zonas['Zona A']!),
            if (zonas['Zona B'] != null) buildZona('Zona B', zonas['Zona B']!),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF1B2A3B), borderRadius: BorderRadius.circular(8)),
              child: const Text('\u0394Pts = moral menos real. Verde = merece m\u00e1s. Rojo = se beneficia.', style: TextStyle(color: Colors.white38, fontSize: 10)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCruces() {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: ApiService.getTablas(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        final zonas = snapshot.data ?? {};
        final zonaA = zonas['Zona A'] ?? [];
        final zonaB = zonas['Zona B'] ?? [];
        if (zonaA.length < 8 || zonaB.length < 8) {
          return Center(child: Text(
            'Zona A: ${zonaA.length} equipos, Zona B: ${zonaB.length} equipos\nSe necesitan 8 por zona',
            style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center));
        }

        // Reglamento: mayor posicion es local
        // 1A vs 8B, 1B vs 8A, 2A vs 7B, 2B vs 7A, 3A vs 6B, 3B vs 6A, 4A vs 5B, 4B vs 5A
        final cruces = [
          {'local': zonaA[0], 'visita': zonaB[7], 'label': '1\u00b0 Zona A vs 8\u00b0 Zona B'},
          {'local': zonaB[0], 'visita': zonaA[7], 'label': '1\u00b0 Zona B vs 8\u00b0 Zona A'},
          {'local': zonaA[1], 'visita': zonaB[6], 'label': '2\u00b0 Zona A vs 7\u00b0 Zona B'},
          {'local': zonaB[1], 'visita': zonaA[6], 'label': '2\u00b0 Zona B vs 7\u00b0 Zona A'},
          {'local': zonaA[2], 'visita': zonaB[5], 'label': '3\u00b0 Zona A vs 6\u00b0 Zona B'},
          {'local': zonaB[2], 'visita': zonaA[5], 'label': '3\u00b0 Zona B vs 6\u00b0 Zona A'},
          {'local': zonaA[3], 'visita': zonaB[4], 'label': '4\u00b0 Zona A vs 5\u00b0 Zona B'},
          {'local': zonaB[3], 'visita': zonaA[4], 'label': '4\u00b0 Zona B vs 5\u00b0 Zona A'},
        ];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('\U0001f3c6 CRUCES HIPOT\u00c9TICOS 8VOS'),
            const SizedBox(height: 4),
            const Center(child: Text('Seg\u00fan tabla real si el torneo terminara hoy', style: TextStyle(color: Colors.white38, fontSize: 11))),
            const SizedBox(height: 16),
            ...cruces.map((cruce) {
              final local = cruce['local'] as Map<String, dynamic>;
              final visita = cruce['visita'] as Map<String, dynamic>;
              final teamL = local['team'] as Map<String, dynamic>;
              final teamV = visita['team'] as Map<String, dynamic>;
              final logoL = teamL['logo'] as String? ?? '';
              final logoV = teamV['logo'] as String? ?? '';
              final nombreL = teamL['name'] as String? ?? '';
              final nombreV = teamV['name'] as String? ?? '';
              final idL = teamL['id']?.toString() ?? '';
              final idV = teamV['id']?.toString() ?? '';
              final esFavL = _equipoFavoritoId != null && idL == _equipoFavoritoId.toString();
              final esFavV = _equipoFavoritoId != null && idV == _equipoFavoritoId.toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2A3B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (esFavL || esFavV) ? const Color(0xFF00C853).withValues(alpha: 0.6) : const Color(0xFFFFD700).withValues(alpha: 0.2),
                    width: (esFavL || esFavV) ? 2 : 1,
                  ),
                ),
                child: Column(children: [
                  Text(cruce['label'] as String, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Column(children: [
                      if (logoL.isNotEmpty) Image.network(logoL, width: 40, height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.white38, size: 40)),
                      const SizedBox(height: 6),
                      Text(nombreL, style: TextStyle(color: esFavL ? const Color(0xFF00C853) : Colors.white, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)), child: const Text('LOCAL', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold))),
                    ])),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('VS', style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 18))),
                    Expanded(child: Column(children: [
                      if (logoV.isNotEmpty) Image.network(logoV, width: 40, height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.white38, size: 40)),
                      const SizedBox(height: 6),
                      Text(nombreV, style: TextStyle(color: esFavV ? const Color(0xFF00C853) : Colors.white, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)), child: const Text('VISITANTE', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold))),
                    ])),
                  ]),
                ]),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildHinchas() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('hinchas')
          .orderBy('votos', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('Aun no hay hinchas registrados', style: TextStyle(color: Colors.white54)));
        }
        final total = docs.fold<int>(0, (sum, d) => sum + (((d.data() as Map<String, dynamic>)['votos'] as num?)?.toInt() ?? 0));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('HINCHAS HDF STATS'),
            const SizedBox(height: 4),
            Center(child: Text('$total hinchas registrados en la app', style: const TextStyle(color: Colors.white38, fontSize: 12))),
            const SizedBox(height: 16),
            ...docs.asMap().entries.map((entry) {
              final i = entry.key;
              final data = entry.value.data() as Map<String, dynamic>;
              final nombre = data['nombre'] as String? ?? 'Equipo';
              final escudo = data['escudo'] as String? ?? '';
              final votos = (data['votos'] as num?)?.toInt() ?? 0;
              final pct = total > 0 ? votos / total : 0.0;
              final esMio = _equipoFavoritoId?.toString() == entry.value.id;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2A3B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: esMio ? const Color(0xFF00C853).withValues(alpha: 0.7) : Colors.transparent,
                    width: esMio ? 2 : 1,
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: i == 0 ? const Color(0xFFFFD700) : i == 1 ? const Color(0xFFC0C0C0) : i == 2 ? const Color(0xFFCD7F32) : Colors.white12,
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text('${i + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12))),
                    ),
                    const SizedBox(width: 10),
                    if (escudo.isNotEmpty)
                      Image.network(escudo, width: 30, height: 30, errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.white38, size: 30))
                    else
                      const Icon(Icons.shield, color: Colors.white38, size: 30),
                    const SizedBox(width: 10),
                    Expanded(child: Text(nombre, style: TextStyle(color: esMio ? const Color(0xFF00C853) : Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                    Text('$votos', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(width: 4),
                    Text(votos == 1 ? 'hincha' : 'hinchas', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    if (esMio) ...[const SizedBox(width: 6), const Icon(Icons.favorite, color: Color(0xFF00C853), size: 14)],
                  ]),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        i == 0 ? const Color(0xFFFFD700) : esMio ? const Color(0xFF00C853) : const Color(0xFF1565C0),
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${(pct * 100).toStringAsFixed(1)}% de los hinchas', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ]),
              );
            }),
          ],
        );
      },
    );
  }


}


class OnboardingCheck extends StatefulWidget {
  const OnboardingCheck({super.key});
  @override
  State<OnboardingCheck> createState() => _OnboardingCheckState();
}

class _OnboardingCheckState extends State<OnboardingCheck> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('equipo_favorito_id');
    if (!mounted) return;
    if (id != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D1B2A),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF00C853))),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  List<Map<String, dynamic>> _equipos = [];
  bool _cargando = true;
  int? _seleccionado;
  String? _nombreSeleccionado;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final equipos = await ApiService.getEquiposLiga();
    if (mounted) setState(() { _equipos = equipos; _cargando = false; });
  }

  Future<void> _guardar() async {
    if (_seleccionado == null) return;
    final prefs = await SharedPreferences.getInstance();
    // Si ya habia elegido antes, descontar el voto anterior
    final anteriorId = prefs.getInt('equipo_favorito_id');
    if (anteriorId != null && anteriorId != -1 && anteriorId != _seleccionado) {
      await FirebaseFirestore.instance.collection('hinchas').doc(anteriorId.toString()).set(
        {'votos': FieldValue.increment(-1), 'nombre': prefs.getString('equipo_favorito_nombre') ?? '', 'escudo': ''},
        SetOptions(merge: true),
      );
    }
    await prefs.setInt('equipo_favorito_id', _seleccionado!);
    await prefs.setString('equipo_favorito_nombre', _nombreSeleccionado ?? '');
    // Registrar voto en Firestore
    final equipoSelec = _equipos.firstWhere((e) => e['id'] == _seleccionado, orElse: () => {});
    await FirebaseFirestore.instance.collection('hinchas').doc(_seleccionado!.toString()).set(
      {'votos': FieldValue.increment(1), 'nombre': _nombreSeleccionado ?? '', 'escudo': equipoSelec['escudo'] ?? ''},
      SetOptions(merge: true),
    );
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Row(children: const [
                Text('HDF', style: TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 28, letterSpacing: 2)),
                Text(' STATS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28, letterSpacing: 2)),
              ]),
              const SizedBox(height: 32),
              const Text('¿Cuál es tu equipo?', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Te destacamos sus partidos en la pantalla principal.', style: TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 24),
              if (_cargando)
                const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF00C853))))
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 0.9,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _equipos.length,
                    itemBuilder: (context, i) {
                      final eq = _equipos[i];
                      final selec = _seleccionado == eq['id'];
                      return GestureDetector(
                        onTap: () => setState(() {
                          _seleccionado = eq['id'];
                          _nombreSeleccionado = eq['nombre'];
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: selec ? const Color(0xFFFFD700).withValues(alpha: 0.12) : const Color(0xFF1B2A3B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selec ? const Color(0xFFFFD700) : Colors.white12,
                              width: selec ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.network(eq['escudo'] as String, width: 44, height: 44,
                                errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.white38, size: 44)),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  eq['nombre'] as String,
                                  style: TextStyle(
                                    color: selec ? const Color(0xFFFFD700) : Colors.white70,
                                    fontSize: 10,
                                    fontWeight: selec ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _seleccionado != null ? _guardar : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    disabledBackgroundColor: Colors.white12,
                  ),
                  child: Text(
                    _seleccionado != null ? 'LISTO, ENTRAR A HDF STATS' : 'SELECCIÓN TU EQUIPO',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('equipo_favorito_id', -1);
                    if (!mounted) return;
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
                  },
                  child: const Text('Omitir por ahora', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}







