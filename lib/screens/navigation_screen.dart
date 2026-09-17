import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:javornik_timerush/utils/constants.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng currentPosition;
  final String selectedRouteId;
  final String selectedRouteName;
  final String selectedMountainId;
  final String selectedMountainName;
  final Future<List<LatLng>> selectedPolyline;

  const NavigationScreen({
    super.key,
    required this.currentPosition,
    required this.selectedRouteId,
    required this.selectedRouteName,
    required this.selectedMountainId,
    required this.selectedMountainName,
    required this.selectedPolyline,
  });

  @override
  NavigationScreenState createState() => NavigationScreenState();
}

class NavigationScreenState extends State<NavigationScreen> with TickerProviderStateMixin {
  late MapController _mapController;
  LatLng _currentMapPosition = const LatLng(0, 0);

  bool _isNearStart = false;
  bool _isTimerRunning = false;
  bool _isRouteLoaded = false;
  bool _userPannedMap = false;
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

  StreamSubscription? _serviceSubscriptionTime;
  StreamSubscription? _serviceSubscriptionTrip;

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
    _serviceSubscriptionTime?.cancel();
    _serviceSubscriptionTrip?.cancel();
    _gpsStream?.cancel();
    _uiTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _ensurePermissions() async {
    await Geolocator.requestPermission();
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  void _startGps() {
    LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }

    _gpsStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((pos) {
      if (!mounted) return;
      final newPos = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _currentMapPosition = newPos;

        if (_isRouteLoaded) {
          _distToStart = Geolocator.distanceBetween(
            newPos.latitude,
            newPos.longitude,
            _startPoint.latitude,
            _startPoint.longitude,
          );
          _distToEnd = Geolocator.distanceBetween(
            newPos.latitude,
            newPos.longitude,
            _endPoint.latitude,
            _endPoint.longitude,
          );

          _isNearStart = _distToStart < AppConstants.gpsTolerance;

          // Detekce cíle
          if (_isTimerRunning && _distToEnd < AppConstants.goalTolerance && !_isSaving) {
            _finishTripByUI();
          }
        }
      });

      if (!_userPannedMap) _mapController.move(newPos, 16.0);
    });
  }

  void _connectToService() {
    final service = FlutterBackgroundService();

    _serviceSubscriptionTime = service.on('updateTime').listen((event) {
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

    _serviceSubscriptionTrip = service.on('tripFinished').listen((event) {
      if (mounted && !_isSaving) {
        _isSaving = true;
        String finalTime = event?['finalTime'] ?? _elapsedTimeString;
        _uiTimer?.cancel();
        setState(() => _isTimerRunning = false);
        _showSuccessDialog(finalTime);
      }
    });
  }

  void _startUiTicker() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_startTime != null && mounted) {
        setState(() {
          final d = DateTime.now().difference(_startTime!);
          String twoDigits(int n) => n.toString().padLeft(2, "0");
          _elapsedTimeString = "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}";
        });
      }
    });
  }

  double _calculateRouteDistanceKm() {
    if (_cachedRoute.isEmpty) return 0.0;
    double distMeters = 0.0;
    for (int i = 0; i < _cachedRoute.length - 1; i++) {
      distMeters += Geolocator.distanceBetween(
        _cachedRoute[i].latitude,
        _cachedRoute[i].longitude,
        _cachedRoute[i + 1].latitude,
        _cachedRoute[i + 1].longitude,
      );
    }
    return distMeters / 1000.0;
  }

  void _startTimer() async {
    if (!_isNearStart) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Jste příliš daleko od startu!"),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chyba: Nepřihlášen")));
      return;
    }

    setState(() {
      _isTimerRunning = true;
      _startTime = DateTime.now();
      _userPannedMap = false;
      _isSaving = false;
    });
    _startUiTicker();

    try {
      final service = FlutterBackgroundService();

      if (!await service.isRunning()) {
        await service.startService();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final double distanceKm = _calculateRouteDistanceKm();

      service.invoke("startTracking", {
        'userId': user.id,
        'mountainId': widget.selectedMountainId,
        'routeId': widget.selectedRouteId,
        'distanceKm': distanceKm,
        'endLat': _endPoint.latitude,
        'endLng': _endPoint.longitude,
      });

      // Zápis stavu uživatele do Supabase
      await supabase.from('profiles').update({
        'is_running': true,
        'start_time': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
    } catch (e) {
      print("Chyba startu: $e");
      setState(() {
        _isTimerRunning = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Chyba startu: $e"),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _finishTripByUI() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _isTimerRunning = false;
    });
    _uiTimer?.cancel();

    final service = FlutterBackgroundService();
    service.invoke("stopService");

    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: const CircularProgressIndicator(color: Colors.green),
        ),
      ),
    );

    try {
      await _saveClimbOutput(user.id, widget.selectedMountainId, widget.selectedRouteId, _elapsedTimeString);
      if (mounted) Navigator.pop(context); // zavřít loading
      _showSuccessDialog(_elapsedTimeString);
    } catch (e) {
      if (mounted) Navigator.pop(context); // zavřít loading
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Chyba uložení: $e")));
    }
  }

  void _abort() async {
    FlutterBackgroundService().invoke("stopService");
    final user = supabase.auth.currentUser;
    if (user != null) {
      await supabase.from('profiles').update({'is_running': false}).eq('id', user.id);
    }
    if (mounted) Navigator.pop(context);
  }

  void _showSuccessDialog(String time) {
    _uiTimer?.cancel();
    setState(() => _isTimerRunning = false);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Column(children: [
          Icon(Icons.emoji_events_rounded, size: 60, color: Colors.orangeAccent),
          SizedBox(height: 10),
          Text("CÍL DOSAŽEN!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22))
        ]),
        content: Text("Váš čas: $time\n\nVýšlap byl úspěšně uložen.", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              ),
              child: const Text("Pokračovat", style: TextStyle(color: Colors.white, fontSize: 16)),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
            ),
          )
        ],
      ),
    );
  }

  Future<void> _saveClimbOutput(String userId, String mountainId, String routeId, String timeStr) async {
    List<String> parts = timeStr.split(':');
    int seconds = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    double distanceKm = _calculateRouteDistanceKm();

    // 1. Uložit výšlap
    await supabase.from('climbs').insert({
      'user_id': userId,
      'mountain_id': mountainId,
      'trail_id': routeId,
      'time': timeStr,
      'time_seconds': seconds,
      'distance_km': distanceKm,
      'date': DateTime.now().toIso8601String(),
    });

    // 2. Aktualizovat uživatelský profil
    try {
      final profile = await supabase
          .from('profiles')
          .select('total_climbs, total_time_seconds, total_distance')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null) {
        int totalClimbs = (profile['total_climbs'] as int? ?? 0) + 1;
        int totalSeconds = (profile['total_time_seconds'] as int? ?? 0) + seconds;
        double totalDist = ((profile['total_distance'] as num?)?.toDouble() ?? 0.0) + distanceKm;

        await supabase.from('profiles').update({
          'is_running': false,
          'total_climbs': totalClimbs,
          'total_time_seconds': totalSeconds,
          'total_distance': totalDist,
        }).eq('id', userId);
      }
    } catch (e) {
      print("Chyba aktualizace profilu: $e");
    }

    // 3. Aktualizovat mountain_stats
    try {
      final mStat = await supabase
          .from('mountain_stats')
          .select()
          .eq('user_id', userId)
          .eq('mountain_id', mountainId)
          .maybeSingle();

      if (mStat == null) {
        await supabase.from('mountain_stats').insert({
          'user_id': userId,
          'mountain_id': mountainId,
          'climbs_count': 1,
          'last_climb_date': DateTime.now().toIso8601String(),
          'best_time_seconds': seconds,
          'best_time_str': timeStr,
        });
      } else {
        int currentBest = (mStat['best_time_seconds'] as int? ?? 999999);
        Map<String, dynamic> updateData = {
          'climbs_count': (mStat['climbs_count'] as int? ?? 0) + 1,
          'last_climb_date': DateTime.now().toIso8601String(),
        };
        if (seconds < currentBest) {
          updateData['best_time_seconds'] = seconds;
          updateData['best_time_str'] = timeStr;
        }
        await supabase
            .from('mountain_stats')
            .update(updateData)
            .eq('user_id', userId)
            .eq('mountain_id', mountainId);
      }
    } catch (e) {
      print("Chyba aktualizace statistik hory: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isTimerRunning,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showAbortDialog();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            // 1. MAPA
            Positioned.fill(
              child: FutureBuilder<List<LatLng>>(
                future: widget.selectedPolyline,
                builder: (ctx, snap) {
                  if (snap.hasData && _cachedRoute.isEmpty) {
                    _cachedRoute = snap.data!;
                    if (_cachedRoute.isNotEmpty) {
                      _startPoint = _cachedRoute.first;
                      _endPoint = _cachedRoute.last;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isRouteLoaded = true);
                      });
                    }
                  }
                  return FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: widget.currentPosition,
                      initialZoom: 15.5,
                      onPositionChanged: (p, g) {
                        if (g) setState(() => _userPannedMap = true);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
                        userAgentPackageName: 'com.example.javornik_timerush',
                      ),
                      if (_cachedRoute.isNotEmpty)
                        PolylineLayer(polylines: [
                          Polyline(
                            points: _cachedRoute,
                            color: Colors.blueAccent,
                            strokeWidth: 5.0,
                            borderStrokeWidth: 2.0,
                            borderColor: Colors.white.withValues(alpha: 0.5),
                          )
                        ]),
                      MarkerLayer(markers: [
                        if (_currentMapPosition.latitude != 0)
                          Marker(
                            point: _currentMapPosition,
                            width: 70,
                            height: 70,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))
                                ],
                              ),
                              padding: const EdgeInsets.all(5),
                              child: Container(
                                decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                                child: const Icon(Icons.navigation, color: Colors.white, size: 30),
                              ),
                            ),
                          ),
                        if (_isRouteLoaded) ...[
                          Marker(point: _startPoint, width: 50, height: 50, child: Icon(Icons.flag_rounded, color: Colors.green[700], size: 45)),
                          Marker(point: _endPoint, width: 50, height: 50, child: Icon(Icons.flag_circle_rounded, color: Colors.red[700], size: 45))
                        ]
                      ])
                    ],
                  );
                },
              ),
            ),

            // TLAČÍTKO ZPĚT (Plovoucí)
            Positioned(
              top: 50,
              left: 20,
              child: GestureDetector(
                onTap: () {
                  if (_isTimerRunning) {
                    _showAbortDialog();
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                  child: const Icon(Icons.arrow_back, color: Colors.black87),
                ),
              ),
            ),

            // PLOVOUCÍ INFO (Vzdálenost)
            if (_isTimerRunning && _isRouteLoaded)
              Positioned(
                top: 55,
                left: 80,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flag_circle_outlined, size: 20, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Text(
                          "Cíl za: ${_distToEnd.toStringAsFixed(0)} m",
                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
                        )
                      ],
                    ),
                  ),
                ),
              ),

            // TLAČÍTKO PRO VYCENTROVÁNÍ
            if (_userPannedMap)
              Positioned(
                right: 20,
                bottom: 260,
                child: FloatingActionButton(
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: Colors.blueAccent),
                  onPressed: () {
                    setState(() => _userPannedMap = false);
                    _mapController.move(_currentMapPosition, 16);
                  },
                ),
              ),

            // SPODNÍ PANEL (Dashboard)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.fromLTRB(25, 25, 25, 35),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, spreadRadius: 5)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isTimerRunning) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Vzdálenost ke startu", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                          Text(
                            "${_distToStart.toStringAsFixed(0)} m",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: _isNearStart ? Colors.green[700] : Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isNearStart ? Colors.green[600] : Colors.grey[300],
                            elevation: _isNearStart ? 5 : 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          onPressed: _isNearStart ? _startTimer : null,
                          child: Text(
                            "START",
                            style: TextStyle(
                              color: _isNearStart ? Colors.white : Colors.grey[500],
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                      if (!_isNearStart)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text("Přibližte se ke startu (${AppConstants.gpsTolerance.toStringAsFixed(0)} m)", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        )
                    ] else ...[
                      Text("ČAS VÝŠLAPU", style: TextStyle(color: Colors.grey[500], fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text(
                        _elapsedTimeString,
                        style: TextStyle(
                          fontSize: 65,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[900],
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 25),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text("VZDÁT"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red[300],
                                side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _showAbortDialog,
                            ),
                          ),
                        ],
                      )
                    ]
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showAbortDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ukončit výšlap?"),
        content: const Text("Opravdu chcete skončit? Váš pokus nebude uložen."),
        actions: [
          TextButton(child: const Text("Zpět"), onPressed: () => Navigator.pop(ctx)),
          TextButton(
            child: const Text("Ukončit", style: TextStyle(color: Colors.red)),
            onPressed: () {
              Navigator.pop(ctx);
              _abort();
            },
          )
        ],
      ),
    );
  }
}