import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:javornik_timerush/utils/constants.dart';

class MountainHistoryScreen extends StatefulWidget {
  final String mountainID;
  final String? userId;

  const MountainHistoryScreen({super.key, required this.mountainID, this.userId});

  @override
  MountainHistoryScreenState createState() => MountainHistoryScreenState();
}

class MountainHistoryScreenState extends State<MountainHistoryScreen> {
  List<Map<String, dynamic>> _allClimbs = [];
  List<Map<String, dynamic>> _displayedClimbs = [];
  List<String> _availableTrails = ['Všechny trasy'];
  String _selectedTrail = 'Všechny trasy';
  bool _isLoading = true;
  String _sortBy = 'date'; // 'date' nebo 'time'

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    String? targetUid = widget.userId;
    if (targetUid == null) {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      targetUid = user.id;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final List<dynamic> data = await supabase
          .from('climbs')
          .select()
          .eq('user_id', targetUid)
          .eq('mountain_id', widget.mountainID);

      List<Map<String, dynamic>> loadedClimbs = data.map((item) {
        String trailName = item['trail_id'] ?? 'Neznámá trasa';
        int seconds = item['time_seconds'] ?? 999999;
        DateTime date = DateTime.tryParse(item['date']?.toString() ?? '') ?? DateTime.now();

        return {
          'id': item['id'].toString(),
          'trailID': trailName,
          'time': item['time'] ?? '??:??',
          'time_seconds': seconds,
          'date': date,
        };
      }).toList();

      Set<String> uniqueTrails = loadedClimbs.map((c) => c['trailID'] as String).toSet();
      List<String> sortedTrails = uniqueTrails.toList()..sort();
      List<String> trailsList = ['Všechny trasy', ...sortedTrails];

      if (mounted) {
        setState(() {
          _allClimbs = loadedClimbs;
          _availableTrails = trailsList;
          if (!_availableTrails.contains(_selectedTrail)) {
            _selectedTrail = 'Všechny trasy';
          }
          _isLoading = false;
        });
        _applyFilterAndSort();
      }
    } catch (e) {
      print("CHYBA: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilterAndSort() {
    List<Map<String, dynamic>> tempClimbs;
    if (_selectedTrail == 'Všechny trasy') {
      tempClimbs = List.from(_allClimbs);
    } else {
      tempClimbs = _allClimbs.where((c) => c['trailID'] == _selectedTrail).toList();
    }

    if (_sortBy == 'date') {
      tempClimbs.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    } else {
      tempClimbs.sort((a, b) => (a['time_seconds'] as int).compareTo(b['time_seconds'] as int));
    }

    setState(() {
      _displayedClimbs = tempClimbs;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.mountainID, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: PopupMenuButton<String>(
              icon: Icon(Icons.sort, color: Colors.blue[900]),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              onSelected: (value) {
                setState(() {
                  _sortBy = value;
                });
                _applyFilterAndSort();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'date',
                  child: Row(children: [Icon(Icons.calendar_month, size: 18), SizedBox(width: 8), Text("Podle data")]),
                ),
                const PopupMenuItem(
                  value: 'time',
                  child: Row(children: [Icon(Icons.timer, size: 18), SizedBox(width: 8), Text("Podle času (PB)")]),
                ),
              ],
            ),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 1. FILTR TRAS (CHIPS)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: _availableTrails.map((trail) {
                      bool isSelected = _selectedTrail == trail;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(trail),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedTrail = trail;
                              });
                              _applyFilterAndSort();
                            }
                          },
                          backgroundColor: Colors.white,
                          selectedColor: Colors.blueAccent,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // 2. POČÍTADLO
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                child: Row(
                  children: [
                    Text(
                      "Zobrazeno ${_displayedClimbs.length} výšlapů",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const Spacer(),
                    if (_sortBy == 'time')
                      const Text("Seřazeno podle nejlepších časů", style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              // 3. SEZNAM VÝŠLAPŮ
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _displayedClimbs.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.hiking, size: 60, color: Colors.grey),
                                SizedBox(height: 10),
                                Text("Žádný záznam pro tento filtr.", style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 5, 16, 20),
                            itemCount: _displayedClimbs.length,
                            itemBuilder: (context, index) {
                              final climb = _displayedClimbs[index];

                              String dateStr;
                              try {
                                dateStr = DateFormat('d. MMMM yyyy, HH:mm', 'cs_CZ').format(climb['date']);
                              } catch (e) {
                                dateStr = DateFormat('dd.MM.yyyy HH:mm').format(climb['date']);
                              }

                              bool isGold = (_sortBy == 'time' && index == 0);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: isGold ? const Color(0xFFFFFBE6) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: isGold ? Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 1.5) : null,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    )
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  leading: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isGold ? Colors.orange[100] : Colors.blue[50],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isGold ? Icons.emoji_events : Icons.directions_walk,
                                      color: isGold ? Colors.orange[800] : Colors.blue[800],
                                      size: 22,
                                    ),
                                  ),
                                  title: Text(
                                    climb['trailID'],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                                  ),
                                  subtitle: Text(dateStr, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                  trailing: Text(
                                    climb['time'],
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      color: isGold ? Colors.orange[900] : Colors.black87,
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
}