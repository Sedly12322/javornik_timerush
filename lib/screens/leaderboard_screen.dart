import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class LeaderboardScreen extends StatefulWidget {
  final String selectedMountain;
  final String selectedRoute;

  LeaderboardScreen({
    required this.selectedMountain,
    required this.selectedRoute,
  });

  @override
  _LeaderboardScreenState createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _leaderboardData = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    try {
      // 1. COLLECTION GROUP QUERY
      // Hledáme ve všech podkolekcích 'climbs' napříč celou databází
      final querySnapshot = await FirebaseFirestore.instance
          .collectionGroup('climbs')
          .where('mountainID', isEqualTo: widget.selectedMountain)
          .where('trailID', isEqualTo: widget.selectedRoute)
          .orderBy('time_seconds', descending: false) // Nejrychlejší čas první
          .limit(50) // Top 50
          .get();

      List<Map<String, dynamic>> tempLeaderboard = [];
      Set<String> processedUserIds = {}; // Proti duplicitám (zobrazíme jen nejlepší čas uživatele)

      for (var doc in querySnapshot.docs) {
        // Získáme referenci na uživatele (rodič rodiče dokumentu climb)
        // climb path: users/{userId}/climbs/{climbId}
        DocumentReference userRef = doc.reference.parent.parent!;
        String userId = userRef.id;

        // Pokud už jsme tohoto uživatele zpracovali (měl lepší čas), přeskočíme ho
        if (processedUserIds.contains(userId)) continue;
        processedUserIds.add(userId);

        // Načteme aktuální data uživatele (jméno, fotka)
        final userSnap = await userRef.get();

        // Pokud uživatel už neexistuje (smazaný účet), přeskočíme
        if (!userSnap.exists) continue;

        final userData = userSnap.data() as Map<String, dynamic>;
        final climbData = doc.data();

        // Formátování data
        DateTime date = (climbData['date'] as Timestamp).toDate();
        String formattedDate = DateFormat('d. MMMM yyyy', 'cs_CZ').format(date);

        tempLeaderboard.add({
          'username': userData['username'] ?? 'Neznámý horal',
          'profile_picture': userData['profile_picture'],
          'time': climbData['time'],
          'seconds': climbData['time_seconds'],
          'date': formattedDate,
          'avatar_color': _getUsernameColor(userData['username'] ?? 'A'),
        });
      }

      if (mounted) {
        setState(() {
          _leaderboardData = tempLeaderboard;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("CHYBA ŽEBŘÍČKU: $e");
      if (mounted) {
        setState(() {
          // Pokud chyba obsahuje 'failed-precondition', je to chybějící index
          if (e.toString().contains('failed-precondition')) {
            _errorMessage = "Chybí databázový index.\nPodívej se do konzole a klikni na odkaz od Firebase.";
          } else {
            _errorMessage = "Nepodařilo se načíst žebříček.";
          }
          _isLoading = false;
        });
      }
    }
  }

  Color _getUsernameColor(String username) {
    final int hash = username.codeUnits.fold(0, (p, c) => p + c);
    return Colors.primaries[hash % Colors.primaries.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Column(
          children: [
            Text("ŽEBŘÍČEK", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.black87)),
            Text("${widget.selectedMountain}", style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.4],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red)),
              ))
              : _leaderboardData.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_off_outlined, size: 80, color: Colors.black12),
                SizedBox(height: 10),
                Text("Zatím tu nikdo neběžel.", style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                Text("Buď první legenda!", style: TextStyle(fontSize: 14, color: Colors.blueGrey)),
              ],
            ),
          )
              : ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            itemCount: _leaderboardData.length,
            itemBuilder: (context, index) {
              final entry = _leaderboardData[index];

              // Nastavení stylu pro stupně vítězů
              Color tileColor = Colors.white;
              Color titleColor = Colors.black87;
              Color timeBgColor = Colors.grey[100]!;
              Widget? rankWidget;
              double elevation = 2;
              double scale = 1.0;

              if (index == 0) {
                tileColor = Color(0xFFFFD700); // Zlatá
                timeBgColor = Colors.white.withOpacity(0.5);
                elevation = 8;
                scale = 1.05; // První místo je trochu větší
                rankWidget = Icon(Icons.emoji_events, color: Colors.white, size: 30);
              } else if (index == 1) {
                tileColor = Color(0xFFE0E0E0); // Stříbrná
                elevation = 5;
                rankWidget = Text("#2", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black54));
              } else if (index == 2) {
                tileColor = Color(0xFFCD7F32); // Bronzová
                titleColor = Colors.white;
                timeBgColor = Colors.white.withOpacity(0.3);
                elevation = 5;
                rankWidget = Text("#3", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white70));
              } else {
                rankWidget = Text("#${index + 1}", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[400]));
              }

              return Transform.scale(
                scale: scale,
                child: Container(
                  margin: EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: elevation, offset: Offset(0, 3))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      color: tileColor,
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),

                        // 1. POŘADÍ
                        leading: Container(
                          width: 40,
                          alignment: Alignment.center,
                          child: rankWidget,
                        ),

                        // 2. PROFIL
                        title: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]
                              ),
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: entry['avatar_color'],
                                backgroundImage: entry['profile_picture'] != null
                                    ? NetworkImage(entry['profile_picture'])
                                    : null,
                                child: entry['profile_picture'] == null
                                    ? Text(entry['username'][0].toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                    : null,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry['username'],
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: titleColor),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                      entry['date'],
                                      style: TextStyle(fontSize: 11, color: titleColor.withOpacity(0.6))
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // 3. ČAS
                        trailing: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: timeBgColor,
                              borderRadius: BorderRadius.circular(12)
                          ),
                          child: Text(
                            entry['time'],
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: titleColor),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}