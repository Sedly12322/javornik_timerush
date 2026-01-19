import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:javornik_timerush/screens/navigation_screen.dart';
import 'package:javornik_timerush/utils/constants.dart';

class RouteSelectionScreen extends StatefulWidget {
  @override
  _RouteSelectionScreenState createState() => _RouteSelectionScreenState();
}

class _RouteSelectionScreenState extends State<RouteSelectionScreen> {
  List<Map<String, dynamic>> mountains = [];
  List<Map<String, dynamic>>? _selectedMountainRoutes = [];

  // Indexy pro výběr
  int _selectedMountainIndex = -1;
  int _selectedRouteIndex = -1;

  String? _selectedMountainName;
  String? _selectedRouteName;

  LatLng _currentPosition = LatLng(50.0755, 14.4378);

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
      final snapshot = await FirebaseFirestore.instance.collection('mountains').get();
      final List<Map<String, dynamic>> loadedMountains = [];
      for (var doc in snapshot.docs) {
        String name = doc['name'];
        double lat = doc['lat'];
        double lng = doc['lng'];

        final routesSnapshot = await FirebaseFirestore.instance
            .collection('mountains').doc(doc.id).collection('trails').get();

        List<Map<String, dynamic>> routes = routesSnapshot.docs.map((routeDoc) {
          return {
            'name': routeDoc['name'],
            'polyline': routeDoc['polyline'],
          };
        }).toList();

        loadedMountains.add({'name': name, 'lat': lat, 'lng': lng, 'routes': routes});
      }
      if (mounted) setState(() => mountains = loadedMountains);
    } catch (e) {
      print('Chyba: $e');
    }
  }

  void _onMountainSelected(int index) {
    setState(() {
      _selectedMountainIndex = index;
      _selectedMountainName = mountains[index]['name'];
      _selectedMountainRoutes = List.from(mountains[index]['routes']);
      _selectedRouteIndex = -1;
      _selectedRouteName = null;
      _isMapExpanded = false; // Reset mapy při změně hory
    });

    // Posun na horu
    double lat = mountains[index]['lat'];
    double lng = mountains[index]['lng'];
    _mapController.move(LatLng(lat, lng), 13.0);
    _fetchWeather(lat: lat, lng: lng);
  }

  // --- ZDE JE HLAVNÍ OPRAVA ---
  void _onRouteSelected(int index) {
    setState(() {
      _selectedRouteIndex = index;
      _selectedRouteName = _selectedMountainRoutes![index]['name'];
    });

    // Okamžitě vypočítáme trasu a posuneme kameru
    String polylineEncoded = _selectedMountainRoutes![index]['polyline'];
    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> decoded = polylinePoints.decodePolyline(polylineEncoded);
    List<LatLng> routePoints = decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();

    if (routePoints.isNotEmpty) {
      // Spočítáme ohraničení (bounds)
      LatLngBounds bounds = _getRouteBounds(routePoints);

      // Plynule přiblížíme
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.all(60), // Větší padding, aby trasa nebyla nalepená na krajích
        ),
      );
    }
  }

  Future<List<LatLng>> _getRouteForSelectedRoute() async {
    if (_selectedRouteName == null || _selectedMountainRoutes == null) return [];

    final selectedRouteData = _selectedMountainRoutes!.firstWhere(
            (r) => r['name'] == _selectedRouteName,
        orElse: () => {}
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

  Future<void> resetStartTime() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'start_time': FieldValue.delete(),
        'is_running': false,
      });
    }
  }

  void _navigateToNavigationScreen() async {
    if (_selectedRouteName == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nejdřív vyber trasu!', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
      ));
      return;
    }

    List<LatLng> routePoints = await _getRouteForSelectedRoute();
    await resetStartTime();

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationScreen(
          currentPosition: _currentPosition,
          selectedRoute: _selectedRouteName!,
          selectedMountain: _selectedMountainName!,
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
        Position position = await Geolocator.getCurrentPosition();
        targetLat = position.latitude;
        targetLng = position.longitude;
      } else {
        targetLat = lat;
        targetLng = lng;
      }

      final apiKey = AppConstants.openWeatherApiKey;
      final response = await http.get(Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?lat=$targetLat&lon=$targetLng&appid=$apiKey&units=metric&lang=cz'
      ));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _weatherIconUrl = "http://openweathermap.org/img/wn/${data['weather'][0]['icon']}@2x.png";
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
    // Výška panelu
    final double panelHeight = MediaQuery.of(context).size.height * 0.55;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // Skryjeme titulek při fullscreenu
        title: _isMapExpanded ? null : Text("Kam vyrazíme?", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: _isMapExpanded ? Colors.transparent : Colors.white.withOpacity(0.9),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
        shape: _isMapExpanded ? null : RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
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
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"),

                    // TRASA
                    if (route.isNotEmpty)
                      PolylineLayer(polylines: [
                        Polyline(points: route, strokeWidth: 5.0, color: Colors.blueAccent)
                      ]),

                    // START a CÍL MARKERY
                    if (route.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: route.first, // Start
                            width: 60, height: 60,
                            child: Column(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(blurRadius: 5)]),
                                  child: Icon(Icons.play_arrow, color: Colors.green, size: 20),
                                ),
                                Text("Start", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black)),
                              ],
                            ),
                          ),
                          Marker(
                            point: route.last, // Cíl
                            width: 60, height: 60,
                            child: Column(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(blurRadius: 5)]),
                                  child: Icon(Icons.flag, color: Colors.red, size: 20),
                                ),
                                Text("Cíl", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black)),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),

          // TLAČÍTKO PRO ZVĚTŠENÍ MAPY (Plovoucí)
          AnimatedPositioned(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            // Když je panel dole (mapa expanded), tlačítko je nízko. Když panel nahoře, tlačítko je nad ním.
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
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: 0,
            right: 0,
            bottom: _isMapExpanded ? -panelHeight : 0, // Schová se pod obrazovku
            height: panelHeight,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Úchyt
                    GestureDetector(
                      onTap: () {
                        if (_isMapExpanded) setState(() => _isMapExpanded = false);
                      },
                      child: Center(
                        child: Container(
                          width: 40, height: 4,
                          margin: EdgeInsets.only(bottom: 15),
                          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),

                    // POČASÍ
                    if (_weatherIconUrl.isNotEmpty || _isLoadingWeather)
                      Center(
                        child: Container(
                          margin: EdgeInsets.only(bottom: 15),
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.blue.withOpacity(0.2)),
                          ),
                          child: _isLoadingWeather
                              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  _selectedMountainIndex == -1 ? "Aktuální poloha:" : "V cíli:",
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600])
                              ),
                              SizedBox(width: 5),
                              Image.network(_weatherIconUrl, width: 30, height: 30),
                              SizedBox(width: 5),
                              Text(_currentTemperature, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue[900])),
                              SizedBox(width: 8),
                              Container(width: 1, height: 15, color: Colors.grey),
                              SizedBox(width: 8),
                              Text(_weatherDescription, style: TextStyle(color: Colors.black87, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),

                    // VÝBĚR HORY
                    Row(
                      children: [
                        Icon(Icons.terrain, size: 18, color: Colors.grey[700]),
                        SizedBox(width: 8),
                        Text("Kam to bude?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                      ],
                    ),
                    SizedBox(height: 10),
                    SizedBox(
                      height: 90,
                      child: mountains.isEmpty
                          ? Center(child: CircularProgressIndicator())
                          : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: mountains.length,
                        itemBuilder: (context, index) {
                          bool isSelected = _selectedMountainIndex == index;
                          return GestureDetector(
                            onTap: () => _onMountainSelected(index),
                            child: AnimatedContainer(
                              duration: Duration(milliseconds: 200),
                              margin: EdgeInsets.only(right: 12, bottom: 5, top: 5),
                              width: 85,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.blueAccent : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: isSelected ? Colors.transparent : Colors.grey.shade200,
                                    width: 2
                                ),
                                boxShadow: isSelected
                                    ? [BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 8, offset: Offset(0,4))]
                                    : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: Offset(0,2))],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.landscape, size: 28, color: isSelected ? Colors.white : Colors.grey[400]),
                                  SizedBox(height: 6),
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
                                          fontWeight: FontWeight.bold
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

                    SizedBox(height: 20),

                    // VÝBĚR TRASY
                    if (_selectedMountainIndex != -1) ...[
                      Row(
                        children: [
                          Icon(Icons.alt_route, size: 18, color: Colors.grey[700]),
                          SizedBox(width: 8),
                          Text("Kudy půjdeme?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                        ],
                      ),
                      SizedBox(height: 10),

                      SizedBox(
                        height: 50,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedMountainRoutes!.length,
                          separatorBuilder: (context, index) => SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            bool isSelected = _selectedRouteIndex == index;
                            return ChoiceChip(
                              label: Text(_selectedMountainRoutes![index]['name']),
                              selected: isSelected,
                              selectedColor: Colors.blueAccent,
                              labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : Colors.black87,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal
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
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.touch_app, size: 40, color: Colors.grey[300]),
                              SizedBox(height: 10),
                              Text("Nejdřív vyber horu nahoře", style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      ),

                    Spacer(),

                    // TLAČÍTKO START
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedRouteIndex != -1 ? Colors.green : Colors.grey[300],
                          foregroundColor: Colors.white,
                          elevation: _selectedRouteIndex != -1 ? 8 : 0,
                          shadowColor: Colors.green.withOpacity(0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _selectedRouteIndex != -1 ? _navigateToNavigationScreen : null,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("ZAČÍT VÝŠLAP", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            if (_selectedRouteIndex != -1) ...[
                              SizedBox(width: 10),
                              Icon(Icons.directions_run)
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
        ],
      ),
    );
  }
}