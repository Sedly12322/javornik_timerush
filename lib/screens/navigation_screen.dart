import 'dart:async';
import 'dart:ui'; // Potřeba pro font features
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:javornik_timerush/utils/constants.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng currentPosition;
  final String selectedRoute;
  final String selectedMountain;
  final Future<List<LatLng>> selectedPolyline;

  NavigationScreen({
    required this.currentPosition,
    required this.selectedRoute,
    required this.selectedMountain,
    required this.selectedPolyline,
  });

  @override
  _NavigationScreenState createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> with TickerProviderStateMixin {
  late MapController _mapController;
  LatLng _currentMapPosition = LatLng(0, 0);

  bool _isNearStart = false;
  bool _isTimerRunning = false;
  bool _isRouteLoaded = false;
  bool _userPannedMap = false;

  // Zámek proti dvojitému uložení
  bool _isSaving = false;

  Timer? _uiTimer;
  StreamSubscription<Position>? _gpsStream;
  DateTime? _startTime;
  String _elapsedTimeString = "00:00";

  double _distToStart = 0;
  double _distToEnd = 9999;

  List<LatLng> _cachedRoute = [];
  late LatLng _startPoint;
  late LatLng _endPoint;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _mapController = MapController();
    _currentMapPosition = widget.currentPosition;

    _ensurePermissions();
    _startGps();
    _connectToService();
  }

  @override
  void dispose() {
    _gpsStream?.cancel();
    _uiTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _ensurePermissions() async {
    await Geolocator.requestPermission();
    await FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  void _startGps() {
    _gpsStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0)
    ).listen((pos) {
      if (!mounted) return;
      final newPos = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _currentMapPosition = newPos;

        if (_isRouteLoaded) {
          _distToStart = Geolocator.distanceBetween(newPos.latitude, newPos.longitude, _startPoint.latitude, _startPoint.longitude);
          _distToEnd = Geolocator.distanceBetween(newPos.latitude, newPos.longitude, _endPoint.latitude, _endPoint.longitude);

          _isNearStart = _distToStart < AppConstants.gpsTolerance;

          // DVOJITÁ KONTROLA CÍLE
          if (_isTimerRunning && _distToEnd < 80.0 && !_isSaving) {
            print("UI: Detekován cíl přímo v aplikaci!");
            _finishTripByUI();
          }
        }
      });

      if (!_userPannedMap) _mapController.move(newPos, 16.0);
    });
  }

  void _connectToService() {
    final service = FlutterBackgroundService();

    service.on('updateTime').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _isTimerRunning = true;
          if (_startTime == null) {
            _startTime = DateTime.now().subtract(Duration(seconds: event['elapsed']));
            _startUiTicker();
          }
        });
      }
    });

    service.on('tripFinished').listen((event) {
      if (mounted && !_isSaving) {
        String finalTime = event?['finalTime'] ?? _elapsedTimeString;
        _showSuccessDialog(finalTime);
      }
    });
  }

  void _startUiTicker() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(Duration(seconds: 1), (t) {
      if (_startTime != null && mounted) {
        setState(() {
          final d = DateTime.now().difference(_startTime!);
          String twoDigits(int n) => n.toString().padLeft(2, "0");
          _elapsedTimeString = "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}";
        });
      }
    });
  }

  void _startTimer() async {
    // 1. Validace vzdálenosti
    if (!_isNearStart) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Jste příliš daleko od startu!"),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // 2. Validace přihlášení
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Chyba: Nepřihlášen")));
      return;
    }

    // 3. UI Update (Tlačítko se změní)
    setState(() {
      _isTimerRunning = true;
      _startTime = DateTime.now();
      _userPannedMap = false;
      _isSaving = false;
    });
    _startUiTicker();

    // 4. BEZPEČNÝ START SLUŽBY
    try {
      final service = FlutterBackgroundService();

      // Pokud služba neběží, nastartujeme ji
      if (!await service.isRunning()) {
        await service.startService();
        // DŮLEŽITÉ: Počkáme, až se Android vzpamatuje
        await Future.delayed(Duration(seconds: 1));
      }

      // 5. Odeslání dat
      service.invoke("startTracking", {
        'userId': user.uid,
        'mountainId': widget.selectedMountain,
        'routeId': widget.selectedRoute,
        'endLat': _endPoint.latitude,
        'endLng': _endPoint.longitude,
      });

      // 6. Zápis do DB
      FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'is_running': true,
        'start_time': DateTime.now().toIso8601String()
      }, SetOptions(merge: true));

    } catch (e) {
      // ZÁCHRANNÁ BRZDA: Pokud nastane chyba, aplikace nespadne!
      print("CRITICKÁ CHYBA: $e");

      setState(() {
        _isTimerRunning = false; // Reset tlačítka
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Chyba startu: $e"),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ));
    }
  }

  void _finishTripByUI() async {
    setState(() {
      _isSaving = true;
      _isTimerRunning = false;
    });
    _uiTimer?.cancel();

    FlutterBackgroundService().invoke("stopService");
    final uid = FirebaseAuth.instance.currentUser!.uid;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
            child: Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                child: CircularProgressIndicator(color: Colors.green)
            )
        )
    );

    try {
      await _saveClimbOutput(uid, widget.selectedMountain, widget.selectedRoute, _elapsedTimeString);
      if(mounted) Navigator.pop(context);
      _showSuccessDialog(_elapsedTimeString);
    } catch (e) {
      if(mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Chyba uložení: $e")));
    }
  }

  void _abort() {
    FlutterBackgroundService().invoke("stopService");
    FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).set({'is_running': false}, SetOptions(merge: true));
    Navigator.pop(context);
  }

  void _showSuccessDialog(String time) {
    _uiTimer?.cancel();
    setState(() => _isTimerRunning = false);

    showDialog(
        context: context, barrierDismissible: false,
        builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Colors.white,
            title: Column(children: [
              Icon(Icons.emoji_events_rounded, size: 60, color: Colors.orangeAccent),
              SizedBox(height: 10),
              Text("CÍL DOSAŽEN!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22))
            ]),
            content: Text("Váš čas: $time\n\nVýšlap byl úspěšně uložen.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
            actions: [
              Center(
                child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: StadiumBorder(),
                        padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12)
                    ),
                    child: Text("Pokračovat", style: TextStyle(color: Colors.white, fontSize: 16)),
                    onPressed: () { Navigator.pop(ctx); Navigator.pop(context); }
                ),
              )
            ]
        )
    );
  }

  Future<void> _saveClimbOutput(String userId, String mountainId, String routeId, String timeStr) async {
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(userId);
    final batch = firestore.batch();

    List<String> parts = timeStr.split(':');
    int seconds = int.parse(parts[0]) * 60 + int.parse(parts[1]);

    double distanceKm = 0.0;
    if (_cachedRoute.isNotEmpty) {
      for (int i = 0; i < _cachedRoute.length - 1; i++) {
        distanceKm += Geolocator.distanceBetween(_cachedRoute[i].latitude, _cachedRoute[i].longitude, _cachedRoute[i+1].latitude, _cachedRoute[i+1].longitude);
      }
      distanceKm /= 1000.0;
    }

    final climbRef = userRef.collection('climbs').doc();
    batch.set(climbRef, {
      'mountainID': mountainId, 'trailID': routeId, 'time': timeStr, 'time_seconds': seconds,
      'distance_km': distanceKm, 'date': DateTime.now(),
    });

    batch.set(userRef, {
      'total_climbs': FieldValue.increment(1), 'total_time_seconds': FieldValue.increment(seconds),
      'is_running': false
    }, SetOptions(merge: true));

    final mountainStatsRef = userRef.collection('mountain_stats').doc(mountainId);
    final statsDoc = await mountainStatsRef.get();

    if (!statsDoc.exists) {
      batch.set(mountainStatsRef, {'mountainID': mountainId, 'climbs_count': 1, 'last_climb_date': DateTime.now(), 'best_time_seconds': seconds, 'best_time_str': timeStr});
    } else {
      int currentBest = statsDoc.data()?['best_time_seconds'] ?? 999999;
      Map<String, dynamic> updateData = {'climbs_count': FieldValue.increment(1), 'last_climb_date': DateTime.now()};
      if (seconds < currentBest) { updateData['best_time_seconds'] = seconds; updateData['best_time_str'] = timeStr; }
      batch.update(mountainStatsRef, updateData);
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. MAPA
          Positioned.fill(child: FutureBuilder<List<LatLng>>(
              future: widget.selectedPolyline,
              builder: (ctx, snap) {
                if (snap.hasData && _cachedRoute.isEmpty) {
                  _cachedRoute = snap.data!;
                  if (_cachedRoute.isNotEmpty) {
                    _startPoint = _cachedRoute.first;
                    _endPoint = _cachedRoute.last;
                    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() { _isRouteLoaded = true; }));
                  }
                }
                return FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                        initialCenter: widget.currentPosition,
                        initialZoom: 15.5,
                        onPositionChanged: (p, g) { if(g) setState(() => _userPannedMap = true); }
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                      ),
                      if(_cachedRoute.isNotEmpty)
                        PolylineLayer(polylines: [
                          Polyline(points: _cachedRoute, color: Colors.blueAccent, strokeWidth: 5.0, borderStrokeWidth: 2.0, borderColor: Colors.white.withOpacity(0.5))
                        ]),
                      MarkerLayer(markers: [
                        // UŽIVATEL
                        if (_currentMapPosition.latitude != 0) Marker(
                            point: _currentMapPosition, width: 70, height: 70,
                            child: Container(
                                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))]),
                                padding: EdgeInsets.all(5),
                                child: Container(
                                    decoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                                    child: Icon(Icons.navigation, color: Colors.white, size: 30)
                                )
                            )
                        ),
                        // START / CÍL
                        if (_isRouteLoaded) ...[
                          Marker(point: _startPoint, width: 50, height: 50, child: Icon(Icons.flag_rounded, color: Colors.green[700], size: 45)),
                          Marker(point: _endPoint, width: 50, height: 50, child: Icon(Icons.flag_circle_rounded, color: Colors.red[700], size: 45))
                        ]
                      ])
                    ]
                );
              }
          )),

          // 2. TLAČÍTKO ZPĚT (Plovoucí)
          Positioned(
            top: 50, left: 20,
            child: GestureDetector(
              onTap: () => _isTimerRunning ? null : Navigator.pop(context),
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                child: Icon(Icons.arrow_back, color: Colors.black87),
              ),
            ),
          ),

          // 3. PLOVOUCÍ INFO (Vzdálenost)
          if (_isTimerRunning && _isRouteLoaded)
            Positioned(
                top: 55, left: 80, right: 20,
                child: Center(
                  child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_circle_outlined, size: 20, color: Colors.redAccent),
                          SizedBox(width: 8),
                          Text("Cíl za: ${_distToEnd.toStringAsFixed(0)} m", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16))
                        ],
                      )
                  ),
                )
            ),

          // 4. TLAČÍTKO PRO VYCENTROVÁNÍ
          if (_userPannedMap)
            Positioned(
                right: 20, bottom: 260,
                child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.my_location, color: Colors.blueAccent),
                    onPressed: () { setState(() => _userPannedMap = false); _mapController.move(_currentMapPosition, 16); }
                )
            ),

          // 5. SPODNÍ PANEL (Dashboard)
          Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: EdgeInsets.only(bottom: 0),
                padding: EdgeInsets.fromLTRB(25, 25, 25, 35),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, spreadRadius: 5)]
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [

                  // --- STAV A: PŘED STARTEM ---
                  if (!_isTimerRunning) ...[
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text("Vzdálenost ke startu", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                      Text("${_distToStart.toStringAsFixed(0)} m", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: _isNearStart ? Colors.green[700] : Colors.redAccent)),
                    ]),
                    SizedBox(height: 20),
                    SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _isNearStart ? Colors.green[600] : Colors.grey[300],
                              elevation: _isNearStart ? 5 : 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                          ),
                          onPressed: _isNearStart ? _startTimer : null,
                          child: Text(
                              "START",
                              style: TextStyle(color: _isNearStart ? Colors.white : Colors.grey[500], fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5)
                          ),
                        )
                    ),
                    if (!_isNearStart)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text("Přibližte se ke startu (${AppConstants.gpsTolerance} m)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      )

                    // --- STAV B: BĚŽÍ VÝŠLAP ---
                  ] else ...[
                    Text("ČAS VÝŠLAPU", style: TextStyle(color: Colors.grey[500], fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
                    SizedBox(height: 5),
                    // Velký čas
                    Text(_elapsedTimeString, style: TextStyle(fontSize: 65, fontWeight: FontWeight.w700, color: Colors.grey[900], height: 1.0, fontFeatures: [FontFeature.tabularFigures()])),
                    SizedBox(height: 25),

                    // Ovládání
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.close_rounded, size: 18),
                            label: Text("VZDÁT"),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red[300],
                                side: BorderSide(color: Colors.red.withOpacity(0.3)),
                                padding: EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ),
                            onPressed: () {
                              showDialog(context: context, builder: (ctx) => AlertDialog(
                                  title: Text("Ukončit výšlap?"),
                                  content: Text("Opravdu chcete skončit? Váš pokus nebude uložen."),
                                  actions: [
                                    TextButton(child: Text("Zpět"), onPressed: () => Navigator.pop(ctx)),
                                    TextButton(child: Text("Ukončit", style: TextStyle(color: Colors.red)), onPressed: () { Navigator.pop(ctx); _abort(); })
                                  ]
                              ));
                            },
                          ),
                        ),
                      ],
                    )
                  ]
                ]),
              )
          )
        ],
      ),
    );
  }
}