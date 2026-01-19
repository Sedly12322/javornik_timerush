import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:javornik_timerush/screens/leaderboard_screen.dart';

class LeaderboardSelectionScreen extends StatefulWidget {
  @override
  _LeaderboardSelectionScreenState createState() => _LeaderboardSelectionScreenState();
}

class _LeaderboardSelectionScreenState extends State<LeaderboardSelectionScreen> {
  // Data načtená z Firebase
  List<Map<String, dynamic>> mountains = [];
  List<Map<String, dynamic>>? _selectedMountainRoutes = [];

  // Index vybrané hory
  int _selectedMountainIndex = -1;
  String? _selectedMountainName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMountains();
  }

  // Logika převzatá z tvého RouteSelectionScreen
  Future<void> _loadMountains() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('mountains').get();
      final List<Map<String, dynamic>> loadedMountains = [];

      for (var doc in snapshot.docs) {
        String name = doc['name'];
        // Lat/Lng pro žebříček nepotřebujeme, ale načteme ID dokumentu
        String id = doc.id;

        // Načtení podkolekce 'trails'
        final routesSnapshot = await FirebaseFirestore.instance
            .collection('mountains').doc(doc.id).collection('trails').get();

        List<Map<String, dynamic>> routes = routesSnapshot.docs.map((routeDoc) {
          // Zkusíme najít 'id', pokud není, použijeme 'name' (pro kompatibilitu)
          var data = routeDoc.data();
          return {
            'name': data['name'],
            'id': data['id'] ?? data['name'], // Důležité pro párování s DB
            'description': data['description'] ?? '', // Pokud máš v DB popis
            'color': data['color'], // Pokud máš v DB barvu
            'icon': data['icon'], // Pokud máš v DB ikonu
          };
        }).toList();

        loadedMountains.add({
          'id': id,
          'name': name,
          'routes': routes
        });
      }

      if (mounted) {
        setState(() {
          mountains = loadedMountains;
          _isLoading = false;

          // Automaticky vybereme první horu, pokud existuje
          if (mountains.isNotEmpty) {
            _onMountainSelected(0);
          }
        });
      }
    } catch (e) {
      print('Chyba při načítání hor: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onMountainSelected(int index) {
    setState(() {
      _selectedMountainIndex = index;
      _selectedMountainName = mountains[index]['name'];
      _selectedMountainRoutes = List.from(mountains[index]['routes']);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("VÝBĚR ŽEBŘÍČKU", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5, color: Colors.black87)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), shape: BoxShape.circle),
          child: BackButton(color: Colors.black),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.5],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // NADPIS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 10),
                child: Text(
                  "Vyber horu",
                  style: TextStyle(fontSize: 16, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                ),
              ),

              // 1. HORIZONTÁLNÍ VÝBĚR HORY (Z tvé DB)
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  itemCount: mountains.length,
                  itemBuilder: (context, index) {
                    bool isSelected = _selectedMountainIndex == index;
                    return GestureDetector(
                      onTap: () => _onMountainSelected(index),
                      child: Container(
                        margin: EdgeInsets.only(right: 15),
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blueAccent : Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(color: Colors.blueAccent.withOpacity(0.4), blurRadius: 10, offset: Offset(0, 4))
                            else
                              BoxShadow(color: Colors.black12, blurRadius: 5)
                          ],
                        ),
                        child: Text(
                          mountains[index]['name'],
                          style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 15
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              SizedBox(height: 20),

              // NADPIS TRASY
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25.0),
                child: Text(
                  _selectedMountainName ?? "Trasy",
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.black87),
                ),
              ),

              SizedBox(height: 10),

              // 2. SEZNAM TRAS (Načtený z tvé DB)
              Expanded(
                child: _selectedMountainRoutes == null || _selectedMountainRoutes!.isEmpty
                    ? Center(child: Text("Pro tuto horu nejsou žádné trasy."))
                    : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  itemCount: _selectedMountainRoutes!.length,
                  itemBuilder: (context, index) {
                    final route = _selectedMountainRoutes![index];

                    // Zkusíme zjistit barvu/ikonu, pokud nejsou v DB, dáme default
                    Color routeColor = _hexToColor(route['color']);
                    IconData routeIcon = _getIconByName(route['icon']);

                    return GestureDetector(
                      onTap: () {
                        // Otevřeme žebříček pro vybranou trasu
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LeaderboardScreen(
                              selectedMountain: _selectedMountainName!,
                              selectedRoute: route['id'], // Předáváme ID trasy
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: EdgeInsets.only(bottom: 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: Offset(0, 5))
                          ],
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.all(15),
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: routeColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(routeIcon, color: routeColor, size: 28),
                          ),
                          title: Text(
                            route['name'],
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
                          ),
                          // Pokud máš v DB description, zobrazíme ho
                          subtitle: route['description'] != null && route['description'].isNotEmpty
                              ? Text(route['description'], style: TextStyle(color: Colors.grey[600], fontSize: 12))
                              : null,
                          trailing: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(10)
                            ),
                            child: Icon(Icons.emoji_events, size: 20, color: Colors.amber[700]),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Pomocné funkce pro barvy a ikony (pokud bys je v DB neměl, použijí se defaultní)
  Color _hexToColor(String? hexColor) {
    if (hexColor == null) return Colors.blue;
    try {
      hexColor = hexColor.toUpperCase().replaceAll("#", "");
      if (hexColor.length == 6) {
        hexColor = "FF" + hexColor;
      }
      return Color(int.parse(hexColor, radix: 16));
    } catch (e) {
      return Colors.blue;
    }
  }

  IconData _getIconByName(String? iconName) {
    switch (iconName) {
      case 'terrain': return Icons.terrain;
      case 'nature_people': return Icons.nature_people;
      case 'landscape': return Icons.landscape;
      case 'hiking': return Icons.hiking;
      case 'directions_walk': return Icons.directions_walk;
      default: return Icons.directions_walk;
    }
  }
}