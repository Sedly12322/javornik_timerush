import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class MountainHistoryScreen extends StatefulWidget {
  final String mountainID;
  final String? userId; // ID uživatele

  MountainHistoryScreen({required this.mountainID, this.userId});

  @override
  _MountainHistoryScreenState createState() => _MountainHistoryScreenState();
}

class _MountainHistoryScreenState extends State<MountainHistoryScreen> {
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      targetUid = user.uid;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .collection('climbs')
          .where('mountainID', isEqualTo: widget.mountainID)
          .get();

      List<Map<String, dynamic>> loadedClimbs = snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data();
        String trailName = data['trailID'] ?? 'Neznámá trasa';
        int seconds = data['time_seconds'] ?? 999999;

        return {
          'id': doc.id,
          'trailID': trailName,
          'time': data['time'] ?? '??:??',
          'time_seconds': seconds,
          'date': (data['date'] as Timestamp).toDate(),
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
      tempClimbs.sort((a, b) => b['date'].compareTo(a['date']));
    } else {
      tempClimbs.sort((a, b) => a['time_seconds'].compareTo(b['time_seconds']));
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
        title: Text(widget.mountainID, style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.black),
        actions: [
          // Tlačítko pro řazení
          Container(
            margin: EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                shape: BoxShape.circle
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
                PopupMenuItem(
                    value: 'date',
                    child: Row(children: [Icon(Icons.calendar_month, size: 18), SizedBox(width: 8), Text("Podle data")])
                ),
                PopupMenuItem(
                    value: 'time',
                    child: Row(children: [Icon(Icons.timer, size: 18), SizedBox(width: 8), Text("Podle času (PB)")])
                ),
              ],
            ),
          )
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
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
                padding: EdgeInsets.symmetric(vertical: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 16),
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
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)
                    ),
                    Spacer(),
                    if (_sortBy == 'time')
                      Text("Seřazeno podle nejlepších časů", style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              // 3. SEZNAM VÝŠLAPŮ
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _displayedClimbs.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.hiking, size: 60, color: Colors.grey[300]),
                      SizedBox(height: 10),
                      Text("Žádný záznam pro tento filtr.", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 5, 16, 20),
                  itemCount: _displayedClimbs.length,
                  itemBuilder: (context, index) {
                    final climb = _displayedClimbs[index];

                    // Formátování data (bezpečná varianta)
                    String dateStr;
                    try {
                      dateStr = DateFormat('d. MMMM yyyy, HH:mm', 'cs_CZ').format(climb['date']);
                    } catch (e) {
                      dateStr = DateFormat('dd.MM.yyyy HH:mm').format(climb['date']);
                    }

                    // Zlatá karta, pokud řadíme podle času a je to první položka (rekord)
                    bool isGold = (_sortBy == 'time' && index == 0);

                    return Container(
                      margin: EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isGold ? Color(0xFFFFFBE6) : Colors.white, // Jemně žlutá pro PB
                        borderRadius: BorderRadius.circular(16),
                        border: isGold ? Border.all(color: Colors.orange.withOpacity(0.5), width: 1.5) : null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            // IKONA
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isGold ? Colors.orange : Colors.blue[50],
                                shape: BoxShape.circle,
                                boxShadow: isGold ? [BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 8)] : [],
                              ),
                              child: Icon(
                                isGold ? Icons.emoji_events : Icons.directions_walk,
                                color: isGold ? Colors.white : Colors.blue[800],
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 16),

                            // INFO
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      climb['trailID'],
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Colors.black87
                                      )
                                  ),
                                  SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                                      SizedBox(width: 4),
                                      Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // ČAS
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                    climb['time'],
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: isGold ? Colors.orange[800] : Colors.blue[900],
                                        letterSpacing: 0.5
                                    )
                                ),
                                if (isGold)
                                  Text("PB", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10)),
                              ],
                            ),
                          ],
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