import 'package:flutter/material.dart';
import 'package:javornik_timerush/screens/leaderboard_screen.dart';
import 'package:javornik_timerush/utils/constants.dart';

class LeaderboardSelectionScreen extends StatefulWidget {
  const LeaderboardSelectionScreen({super.key});

  @override
  LeaderboardSelectionScreenState createState() => LeaderboardSelectionScreenState();
}

class LeaderboardSelectionScreenState extends State<LeaderboardSelectionScreen> {
  List<Map<String, dynamic>> mountains = [];
  List<Map<String, dynamic>>? _selectedMountainRoutes = [];

  int _selectedMountainIndex = -1;
  String? _selectedMountainId;
  String? _selectedMountainName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMountains();
  }

  Future<void> _loadMountains() async {
    try {
      final List<dynamic> data = await supabase
          .from('mountains')
          .select('id, name, trails(id, name, description, color, icon)');

      final List<Map<String, dynamic>> loadedMountains = [];
      for (var item in data) {
        String id = item['id'].toString();
        String name = item['name'];
        List<dynamic> rawTrails = item['trails'] ?? [];

        List<Map<String, dynamic>> routes = rawTrails.map((trail) {
          return {
            'id': trail['id'].toString(),
            'name': trail['name'],
            'description': trail['description'] ?? '',
            'color': trail['color'],
            'icon': trail['icon'],
          };
        }).toList();

        loadedMountains.add({
          'id': id,
          'name': name,
          'routes': routes,
        });
      }

      if (mounted) {
        setState(() {
          mountains = loadedMountains;
          _isLoading = false;
          if (mountains.isNotEmpty) {
            _onMountainSelected(0);
          }
        });
      }
    } catch (e) {
      print('Chyba při načítání hor ze Supabase: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onMountainSelected(int index) {
    setState(() {
      _selectedMountainIndex = index;
      _selectedMountainId = mountains[index]['id'];
      _selectedMountainName = mountains[index]['name'];
      _selectedMountainRoutes = List.from(mountains[index]['routes']);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("VÝBĚR ŽEBŘÍČKU", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5, color: Colors.black87)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), shape: BoxShape.circle),
          child: const BackButton(color: Colors.black),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.4],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : mountains.isEmpty
                  ? const Center(child: Text("Žádné hory v databázi."))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),

                        // 1. HORIZONTÁLNÍ VÝBĚR HORY
                        SizedBox(
                          height: 45,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: mountains.length,
                            itemBuilder: (context, index) {
                              bool isSelected = _selectedMountainIndex == index;
                              return GestureDetector(
                                onTap: () => _onMountainSelected(index),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 10),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.blueAccent : Colors.white,
                                    borderRadius: BorderRadius.circular(25),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      )
                                    ],
                                  ),
                                  child: Text(
                                    mountains[index]['name'],
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 20),

                        // NADPIS TRASY
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 25.0),
                          child: Text(
                            _selectedMountainName ?? "Trasy",
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.black87),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // 2. SEZNAM TRAS
                        Expanded(
                          child: _selectedMountainRoutes == null || _selectedMountainRoutes!.isEmpty
                              ? const Center(child: Text("Pro tuto horu nejsou žádné trasy."))
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  itemCount: _selectedMountainRoutes!.length,
                                  itemBuilder: (context, index) {
                                    final route = _selectedMountainRoutes![index];

                                    Color routeColor = _hexToColor(route['color']);
                                    IconData routeIcon = _getIconByName(route['icon']);

                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => LeaderboardScreen(
                                              selectedMountain: _selectedMountainId ?? _selectedMountainName!,
                                              selectedRoute: route['id'],
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 15),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))
                                          ],
                                          border: Border.all(color: Colors.white, width: 2),
                                        ),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.all(15),
                                          leading: Container(
                                            width: 50,
                                            height: 50,
                                            decoration: BoxDecoration(
                                              color: routeColor.withValues(alpha: 0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(routeIcon, color: routeColor, size: 28),
                                          ),
                                          title: Text(
                                            route['name'],
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
                                          ),
                                          subtitle: route['description'] != null && route['description'].isNotEmpty
                                              ? Text(route['description'], style: TextStyle(color: Colors.grey[600], fontSize: 12))
                                              : null,
                                          trailing: Container(
                                            padding: const EdgeInsets.all(8),
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

  Color _hexToColor(String? hexColor) {
    if (hexColor == null) return Colors.blue;
    try {
      hexColor = hexColor.toUpperCase().replaceAll("#", "");
      if (hexColor.length == 6) {
        hexColor = "FF$hexColor";
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