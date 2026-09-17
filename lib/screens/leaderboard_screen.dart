import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:javornik_timerush/utils/constants.dart';

class LeaderboardScreen extends StatefulWidget {
  final String selectedMountain;
  final String selectedRoute;

  const LeaderboardScreen({
    super.key,
    required this.selectedMountain,
    required this.selectedRoute,
  });

  @override
  LeaderboardScreenState createState() => LeaderboardScreenState();
}

class LeaderboardScreenState extends State<LeaderboardScreen> {
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
      final List<dynamic> records = await supabase
          .from('climbs')
          .select('time, time_seconds, date, profiles(username, full_username, profile_picture)')
          .eq('mountain_id', widget.selectedMountain)
          .eq('trail_id', widget.selectedRoute)
          .order('time_seconds', ascending: true)
          .limit(100);

      List<Map<String, dynamic>> tempLeaderboard = [];
      Set<String> processedUsernames = {};

      for (var row in records) {
        final profile = row['profiles'] as Map<String, dynamic>?;
        final username = profile?['full_username'] ?? profile?['username'] ?? 'Neznámý horal';
        if (processedUsernames.contains(username)) continue;
        processedUsernames.add(username);

        DateTime date = DateTime.tryParse(row['date']?.toString() ?? '') ?? DateTime.now();
        String formattedDate = DateFormat('d. MMMM yyyy', 'cs_CZ').format(date);

        tempLeaderboard.add({
          'username': username,
          'profile_picture': profile?['profile_picture'],
          'time': row['time'] ?? '??:??',
          'seconds': row['time_seconds'] ?? 0,
          'date': formattedDate,
          'avatar_color': _getUsernameColor(username),
        });

        if (tempLeaderboard.length >= 50) break;
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
          _errorMessage = "Nepodařilo se načíst žebříček: $e";
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
            const Text("ŽEBŘÍČEK", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.black87)),
            Text(widget.selectedMountain, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
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
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                      ),
                    )
                  : _leaderboardData.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.timer_off_outlined, size: 80, color: Colors.black12),
                              SizedBox(height: 10),
                              Text("Zatím tu nikdo neběžel.", style: TextStyle(fontSize: 18, color: Colors.black54, fontWeight: FontWeight.bold)),
                              Text("Buď první legenda!", style: TextStyle(fontSize: 14, color: Colors.blueGrey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          itemCount: _leaderboardData.length,
                          itemBuilder: (context, index) {
                            final entry = _leaderboardData[index];

                            Color tileColor = Colors.white;
                            Color titleColor = Colors.black87;
                            Color timeBgColor = Colors.grey[100]!;
                            Widget? rankWidget;
                            double elevation = 2;
                            double scale = 1.0;

                            if (index == 0) {
                              tileColor = const Color(0xFFFFD700);
                              timeBgColor = Colors.white.withValues(alpha: 0.5);
                              elevation = 8;
                              scale = 1.05;
                              rankWidget = const Icon(Icons.emoji_events, color: Colors.white, size: 30);
                            } else if (index == 1) {
                              tileColor = const Color(0xFFE0E0E0);
                              elevation = 5;
                              rankWidget = const Text("#2", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black54));
                            } else if (index == 2) {
                              tileColor = const Color(0xFFCD7F32);
                              titleColor = Colors.white;
                              timeBgColor = Colors.white.withValues(alpha: 0.3);
                              elevation = 5;
                              rankWidget = const Text("#3", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white70));
                            } else {
                              rankWidget = Text("#${index + 1}", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[400]));
                            }

                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: elevation, offset: const Offset(0, 3))],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    color: tileColor,
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                                      leading: Container(
                                        width: 40,
                                        alignment: Alignment.center,
                                        child: rankWidget,
                                      ),
                                      title: Row(
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white, width: 2),
                                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                                            ),
                                            child: CircleAvatar(
                                              radius: 20,
                                              backgroundColor: entry['avatar_color'],
                                              backgroundImage: entry['profile_picture'] != null
                                                  ? NetworkImage(entry['profile_picture'])
                                                  : null,
                                              child: entry['profile_picture'] == null
                                                  ? Text(
                                                      entry['username'].isNotEmpty ? entry['username'][0].toUpperCase() : '?',
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
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
                                                  style: TextStyle(fontSize: 11, color: titleColor.withValues(alpha: 0.6)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: timeBgColor,
                                          borderRadius: BorderRadius.circular(12),
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