import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:javornik_timerush/screens/mountain_history_screen.dart';
import 'package:javornik_timerush/screens/search_users_screen.dart';
import 'package:javornik_timerush/screens/friends_screen.dart';
import 'package:javornik_timerush/services/friend_service.dart';
import 'package:javornik_timerush/utils/constants.dart';

class ProfileScreen extends StatefulWidget {
  final String? viewUserId;

  const ProfileScreen({super.key, this.viewUserId});

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  bool _isUploading = false;

  bool get _isMyProfile {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return false;
    return widget.viewUserId == null || widget.viewUserId == currentUser.id;
  }

  String get _targetUserId {
    return widget.viewUserId ?? supabase.auth.currentUser!.id;
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return "0m";
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    return "${hours}h ${minutes}m";
  }

  Future<void> _pickAndUploadImage() async {
    if (!_isMyProfile) return;

    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (pickedFile == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final user = supabase.auth.currentUser!;
      final file = File(pickedFile.path);
      final bytes = await file.readAsBytes();
      final fileExt = pickedFile.name.split('.').last;
      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await supabase.storage.from('user_images').uploadBinary(
        fileName,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );

      final downloadUrl = supabase.storage.from('user_images').getPublicUrl(fileName);

      await supabase.from('profiles').update({'profile_picture': downloadUrl}).eq('id', user.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profilová fotka byla úspěšně změněna!')),
        );
      }
    } catch (e) {
      print("Chyba při nahrávání fotky: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba při nahrávání fotky: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null && widget.viewUserId == null) {
      return const Scaffold(body: Center(child: Text("Nejste přihlášen")));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_isMyProfile ? "Můj Profil" : "Profil uživatele", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          if (_isMyProfile) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), shape: BoxShape.circle),
              child: IconButton(
                icon: Icon(Icons.people, color: Colors.blue[800]),
                tooltip: "Přátelé",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FriendsScreen())),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 15, left: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), shape: BoxShape.circle),
              child: IconButton(
                icon: Icon(Icons.search, color: Colors.blue[800]),
                tooltip: "Hledat uživatele",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SearchUsersScreen())),
              ),
            ),
          ]
        ],
      ),
      body: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 100, 20, 20),
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: supabase
                .from('profiles')
                .stream(primaryKey: ['id'])
                .eq('id', _targetUserId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: Padding(padding: EdgeInsets.all(50), child: CircularProgressIndicator()));
              }

              Map<String, dynamic>? data = snapshot.hasData && snapshot.data!.isNotEmpty ? snapshot.data!.first : null;
              String? photoUrl = data?['profile_picture'];
              int totalClimbs = data?['total_climbs'] ?? 0;
              int totalSeconds = data?['total_time_seconds'] ?? 0;
              double totalDist = (data?['total_distance'] as num?)?.toDouble() ?? 0.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. HLAVIČKA (Avatar + Jméno)
                  GestureDetector(
                    onTap: _pickAndUploadImage,
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.blue[50],
                            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                            child: _isUploading
                                ? const CircularProgressIndicator()
                                : (photoUrl == null ? Icon(Icons.person, size: 50, color: Colors.blue[200]) : null),
                          ),
                        ),
                        if (_isMyProfile)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                            ),
                          )
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    data?['full_username'] ?? data?['username'] ?? "Neznámý horal",
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black87),
                  ),
                  if (_isMyProfile)
                    Text(data?['email'] ?? "", style: TextStyle(color: Colors.grey[600], fontSize: 14)),

                  const SizedBox(height: 20),

                  // 2. TLAČÍTKO PRO PŘÁTELSTVÍ (Jen na cizím profilu)
                  if (!_isMyProfile && currentUserId != null)
                    StreamBuilder<String>(
                      stream: FriendService().getFriendshipStatus(currentUserId, _targetUserId),
                      builder: (context, friendSnap) {
                        if (!friendSnap.hasData) return const SizedBox();

                        String status = friendSnap.data!;
                        String text;
                        Color bgColor;
                        Color txtColor = Colors.white;
                        IconData icon;
                        VoidCallback? action;

                        if (status == 'accepted') {
                          text = "Jste přátelé";
                          bgColor = Colors.green;
                          icon = Icons.check_circle;
                          action = () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Odebrat přítele?"),
                                content: const Text("Opravdu chcete odebrat tohoto uživatele z přátel?"),
                                actions: [
                                  TextButton(child: const Text("Ne"), onPressed: () => Navigator.pop(ctx)),
                                  TextButton(
                                    child: const Text("Ano", style: TextStyle(color: Colors.red)),
                                    onPressed: () {
                                      FriendService().removeFriend(currentUserId, _targetUserId);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                ],
                              ),
                            );
                          };
                        } else if (status == 'sent') {
                          text = "Žádost odeslána";
                          bgColor = Colors.grey[300]!;
                          txtColor = Colors.black87;
                          icon = Icons.hourglass_top;
                          action = () => FriendService().removeFriend(currentUserId, _targetUserId);
                        } else if (status == 'received') {
                          text = "Přijmout žádost";
                          bgColor = Colors.blue;
                          icon = Icons.person_add;
                          action = () => FriendService().acceptFriendRequest(currentUserId, _targetUserId);
                        } else {
                          text = "Přidat do přátel";
                          bgColor = Colors.blueAccent;
                          icon = Icons.person_add_alt_1;
                          action = () => FriendService().sendFriendRequest(currentUserId, _targetUserId);
                        }

                        return SizedBox(
                          width: 200,
                          height: 45,
                          child: ElevatedButton.icon(
                            icon: Icon(icon, color: txtColor, size: 20),
                            label: Text(text, style: TextStyle(color: txtColor, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: bgColor,
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                            ),
                            onPressed: action,
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 30),

                  // 3. STATISTIKY (GRID)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Statistiky", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  const SizedBox(height: 15),

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                    childAspectRatio: 1.4,
                    children: [
                      _buildStatCard("Výšlapy", "$totalClimbs", Icons.landscape, Colors.green),
                      _buildStatCard("Čas v horách", _formatDuration(totalSeconds), Icons.timer, Colors.orange),
                      _buildStatCard("Vzdálenost", "${totalDist.toStringAsFixed(1)} km", Icons.directions_walk, Colors.blue),
                      _buildStatCard("Spálené kalorie", "${totalClimbs * 450} kcal", Icons.local_fire_department, Colors.red),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // 4. SEZNAM HOR
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Zdolal tyto hory", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  const SizedBox(height: 15),

                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: supabase
                        .from('mountain_stats')
                        .stream(primaryKey: ['user_id', 'mountain_id'])
                        .eq('user_id', _targetUserId),
                    builder: (context, mSnapshot) {
                      if (mSnapshot.connectionState == ConnectionState.waiting && !mSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!mSnapshot.hasData || mSnapshot.data!.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                          child: Column(
                            children: [
                              Icon(Icons.hiking, color: Colors.grey[300], size: 40),
                              const SizedBox(height: 10),
                              const Text("Zatím žádné zdolané hory.", style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      }

                      var stats = List<Map<String, dynamic>>.from(mSnapshot.data!);
                      stats.sort((a, b) => ((b['climbs_count'] as int? ?? 0)).compareTo((a['climbs_count'] as int? ?? 0)));

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: stats.length,
                        itemBuilder: (context, index) {
                          var doc = stats[index];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => MountainHistoryScreen(
                                        mountainID: doc['mountain_id'] ?? '',
                                        userId: _targetUserId,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.terrain, color: Colors.blue[800], size: 24),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              doc['mountain_id'] ?? '',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(Icons.emoji_events, size: 14, color: Colors.amber),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "${doc['best_time_str'] ?? '--:--'}",
                                                  style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w500, fontSize: 13),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          "${doc['climbs_count'] ?? 0}x",
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue[800]),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[300]),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
          const SizedBox(height: 2),
          Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 11), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}