import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:javornik_timerush/screens/navigation_screen.dart';
import 'package:javornik_timerush/utils/constants.dart';

class RouteSelectionScreen extends StatefulWidget {
  const RouteSelectionScreen({super.key});

  @override
  RouteSelectionScreenState createState() => RouteSelectionScreenState();
}

class RouteSelectionScreenState extends State<RouteSelectionScreen> {
  List<Map<String, dynamic>> mountains = [];
  List<Map<String, dynamic>>? _selectedMountainRoutes = [];

  // Indexy pro výběr
  int _selectedMountainIndex = -1;
  int _selectedRouteIndex = -1;

  String? _selectedMountainId;
  String? _selectedMountainName;
  String? _selectedRouteId;
  String? _selectedRouteName;

  LatLng _currentPosition = const LatLng(50.0755, 14.4378);

  // Počasí
  String _weatherIconUrl = "";
  String _currentTemperature = "";
  String _weatherDescription = "";
  bool _isLoadingWeather = false;

  final MapController _mapController = MapController();

  // Stav pro zvětšení mapy
  bool _isMapExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadMountains();
    _fetchWeather();
  }

  Future<void> _loadMountains() async {
    try {
      final List<dynamic> data = await supabase
          .from('mountains')
          .select('id, name, lat, lng, trails(id, name, polyline, description, color, icon)');

      final List<Map<String, dynamic>> loadedMountains = [];
      for (var item in data) {
        String id = item['id'].toString();
        String name = item['name'];
        double lat = (item['lat'] as num).toDouble();
        double lng = (item['lng'] as num).toDouble();
        List<dynamic> rawTrails = item['trails'] ?? [];

        List<Map<String, dynamic>> routes = rawTrails.map((trail) {
          return {
            'id': trail['id'].toString(),
            'name': trail['name'],
            'polyline': trail['polyline'],
            'description': trail['description'] ?? '',
            'color': trail['color'],
            'icon': trail['icon'],
          };
        }).toList();

        loadedMountains.add({
          'id': id,
          'name': name,
          'lat': lat,
          'lng': lng,
          'routes': routes,
        });
      }

      if (mounted) setState(() => mountains = loadedMountains);
    } catch (e) {
      print('Chyba při načítání hor ze Supabase: $e');
    }
  }

  void _onMountainSelected(int index) {
    setState(() {
      _selectedMountainIndex = index;
      _selectedMountainId = mountains[index]['id'];
      _selectedMountainName = mountains[index]['name'];
      _selectedMountainRoutes = List.from(mountains[index]['routes']);
      _selectedRouteIndex = -1;
      _selectedRouteId = null;
      _selectedRouteName = null;
      _isMapExpanded = false;
    });

    double lat = mountains[index]['lat'];
    double lng = mountains[index]['lng'];
    _mapController.move(LatLng(lat, lng), 13.0);
    _fetchWeather(lat: lat, lng: lng);
  }

  void _onRouteSelected(int index) {
    setState(() {
      _selectedRouteIndex = index;
      _selectedRouteId = _selectedMountainRoutes![index]['id'];
      _selectedRouteName = _selectedMountainRoutes![index]['name'];
    });

    String polylineEncoded = _selectedMountainRoutes![index]['polyline'];
    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> decoded = polylinePoints.decodePolyline(polylineEncoded);
    List<LatLng> routePoints = decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();

    if (routePoints.isNotEmpty) {
      LatLngBounds bounds = _getRouteBounds(routePoints);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60),
        ),
      );
    }
  }

  Future<List<LatLng>> _getRouteForSelectedRoute() async {
    if (_selectedRouteName == null || _selectedMountainRoutes == null) return [];

    final selectedRouteData = _selectedMountainRoutes!.firstWhere(
      (r) => r['name'] == _selectedRouteName,
      orElse: () => {},
    );

    if (selectedRouteData.isEmpty || !selectedRouteData.containsKey('polyline')) return [];

    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> decoded = polylinePoints.decodePolyline(selectedRouteData['polyline']);
    return decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  LatLngBounds _getRouteBounds(List<LatLng> route) {
    if (route.isEmpty) return LatLngBounds(_currentPosition, _currentPosition);
    double minLat = route[0].latitude, maxLat = route[0].latitude;
    double minLng = route[0].longitude, maxLng = route[0].longitude;
    for (var p in route) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  void _navigateToNavigationScreen() async {
    if (_selectedRouteName == null || _selectedRouteId == null || _selectedMountainId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nejdřív vyber trasu!', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
      ));
      return;
    }

    List<LatLng> routePoints = await _getRouteForSelectedRoute();

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationScreen(
          currentPosition: _currentPosition,
          selectedRouteId: _selectedRouteId!,
          selectedRouteName: _selectedRouteName!,
          selectedMountainId: _selectedMountainId!,
          selectedMountainName: _selectedMountainName!,
          selectedPolyline: Future.value(routePoints),
        ),
      ),
    );
  }

  Future<void> _fetchWeather({double? lat, double? lng}) async {
    setState(() {
      _isLoadingWeather = true;
    });

    try {
      double targetLat;
      double targetLng;

      if (lat == null || lng == null) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          setState(() => _isLoadingWeather = false);
          return;
        }

        Position position = await Geolocator.getCurrentPosition();
        targetLat = position.latitude;
        targetLng = position.longitude;
      } else {
        targetLat = lat;
        targetLng = lng;
      }

      const apiKey = AppConstants.openWeatherApiKey;
      final response = await http.get(Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?lat=$targetLat&lon=$targetLng&appid=$apiKey&units=metric&lang=cz'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _weatherIconUrl = "https://openweathermap.org/img/wn/${data['weather'][0]['icon']}@2x.png";
            _currentTemperature = "${data['main']['temp'].toStringAsFixed(1)}°C";
            String desc = data['weather'][0]['description'];
            _weatherDescription = desc.isNotEmpty ? "${desc[0].toUpperCase()}${desc.substring(1)}" : desc;
            if (lat == null) {
              _currentPosition = LatLng(targetLat, targetLng);
            }
          });
        }
      }
    } catch (e) {
      print("Chyba počasí: $e");
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double panelHeight = MediaQuery.of(context).size.height * 0.58;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: _isMapExpanded ? null : const Text("Kam vyrazíme?", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: _isMapExpanded ? Colors.transparent : Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        shape: _isMapExpanded ? null : const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
      ),
      body: Stack(
        children: [
          // 1. MAPA
          Positioned.fill(
            child: FutureBuilder<List<LatLng>>(
              future: _getRouteForSelectedRoute(),
              builder: (context, snapshot) {
                List<LatLng> route = snapshot.data ?? [];

                return FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition,
                    initialZoom: 13.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: 'com.example.javornik_timerush',
                    ),
                    if (route.isNotEmpty)
                      PolylineLayer(polylines: [
                        Polyline(points: route, strokeWidth: 5.0, color: Colors.blueAccent)
                      ]),
                    if (route.isNotEmpty)
                      MarkerLayer(markers: [
                        Marker(
                          point: route.first,
                          width: 40,
                          height: 40,
                          child: Icon(Icons.flag_rounded, color: Colors.green[700], size: 35),
                        ),
                        Marker(
                          point: route.last,
                          width: 40,
                          height: 40,
                          child: Icon(Icons.flag_circle_rounded, color: Colors.red[700], size: 35),
                        ),
                      ])
                  ],
                );
              },
            ),
          ),

          // TLAČÍTKO PRO ZVĚTŠENÍ MAPY
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            bottom: _isMapExpanded ? 30 : panelHeight + 20,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              elevation: 4,
              child: Icon(_isMapExpanded ? Icons.vertical_align_top : Icons.map, color: Colors.blue[900]),
              onPressed: () {
                setState(() {
                  _isMapExpanded = !_isMapExpanded;
                });
              },
            ),
          ),

          // 2. SPODNÍ PANEL (Vyjíždějící)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: 0,
            right: 0,
            bottom: _isMapExpanded ? -panelHeight : 0,
            height: panelHeight,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Úchyt
                        GestureDetector(
                          onTap: () {
                            if (_isMapExpanded) setState(() => _isMapExpanded = false);
                          },
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),

                        // POČASÍ
                        if (_weatherIconUrl.isNotEmpty || _isLoadingWeather)
                          Center(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                              ),
                              child: _isLoadingWeather
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                            _selectedMountainIndex == -1 ? "Aktuální poloha:" : "V cíli:",
                                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                        const SizedBox(width: 5),
                                        Image.network(_weatherIconUrl, width: 30, height: 30, errorBuilder: (_, __, ___) => const Icon(Icons.cloud, size: 24)),
                                        const SizedBox(width: 5),
                                        Text(_currentTemperature, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue[900])),
                                        const SizedBox(width: 8),
                                        Container(width: 1, height: 15, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        Flexible(child: Text(_weatherDescription, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87, fontSize: 13))),
                                      ],
                                    ),
                            ),
                          ),

                        // VÝBĚR HORY
                        Row(
                          children: [
                            Icon(Icons.terrain, size: 18, color: Colors.grey[700]),
                            const SizedBox(width: 8),
                            Text("Kam to bude?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 90,
                          child: mountains.isEmpty
                              ? const Center(child: CircularProgressIndicator())
                              : ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: mountains.length,
                                  itemBuilder: (context, index) {
                                    bool isSelected = _selectedMountainIndex == index;
                                    return GestureDetector(
                                      onTap: () => _onMountainSelected(index),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        margin: const EdgeInsets.only(right: 12, bottom: 5, top: 5),
                                        width: 85,
                                        decoration: BoxDecoration(
                                          color: isSelected ? Colors.blueAccent : Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isSelected ? Colors.transparent : Colors.grey.shade200,
                                            width: 2,
                                          ),
                                          boxShadow: isSelected
                                              ? [BoxShadow(color: Colors.blue.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 4))]
                                              : [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.landscape, size: 28, color: isSelected ? Colors.white : Colors.grey[400]),
                                            const SizedBox(height: 6),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                              child: Text(
                                                mountains[index]['name'],
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isSelected ? Colors.white : Colors.black87,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            )
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),

                        const SizedBox(height: 15),

                        // VÝBĚR TRASY
                        if (_selectedMountainIndex != -1) ...[
                          Row(
                            children: [
                              Icon(Icons.alt_route, size: 18, color: Colors.grey[700]),
                              const SizedBox(width: 8),
                              Text("Kudy půjdeme?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 50,
                            child: _selectedMountainRoutes == null || _selectedMountainRoutes!.isEmpty
                                ? const Center(child: Text("Žádné trasy."))
                                : ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _selectedMountainRoutes!.length,
                                    separatorBuilder: (context, index) => const SizedBox(width: 10),
                                    itemBuilder: (context, index) {
                                      bool isSelected = _selectedRouteIndex == index;
                                      return ChoiceChip(
                                        label: Text(_selectedMountainRoutes![index]['name']),
                                        selected: isSelected,
                                        selectedColor: Colors.blueAccent,
                                        labelStyle: TextStyle(
                                          color: isSelected ? Colors.white : Colors.black87,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                        backgroundColor: Colors.grey[100],
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        onSelected: (bool selected) {
                                          if (selected) _onRouteSelected(index);
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.touch_app, size: 36, color: Colors.grey[300]),
                                  const SizedBox(height: 6),
                                  Text("Nejdřív vyber horu nahoře", style: TextStyle(color: Colors.grey[500])),
                                ],
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),

                        // TLAČÍTKO START
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _selectedRouteIndex != -1 ? Colors.green : Colors.grey[300],
                              foregroundColor: Colors.white,
                              elevation: _selectedRouteIndex != -1 ? 6 : 0,
                              shadowColor: Colors.green.withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _selectedRouteIndex != -1 ? _navigateToNavigationScreen : null,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("ZAČÍT VÝŠLAP", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                if (_selectedRouteIndex != -1) ...[
                                  const SizedBox(width: 10),
                                  const Icon(Icons.directions_run)
                                ]
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}