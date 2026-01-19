import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:javornik_timerush/screens/mountain_history_screen.dart';
import 'package:javornik_timerush/screens/search_users_screen.dart';
import 'package:javornik_timerush/screens/friends_screen.dart';
import 'package:javornik_timerush/services/friend_service.dart';

class ProfileScreen extends StatefulWidget {
  final String? viewUserId; // null = MŮJ profil, jinak CIZÍ

  ProfileScreen({this.viewUserId});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploading = false;

  bool get _isMyProfile {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    return widget.viewUserId == null || widget.viewUserId == currentUser.uid;
  }

  String get _targetUserId {
    return widget.viewUserId ?? FirebaseAuth.instance.currentUser!.uid;
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
      imageQuality: 50,
    );

    if (pickedFile == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      File file = File(pickedFile.path);
      final user = FirebaseAuth.instance.currentUser!;

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_images')
          .child('${user.uid}.jpg');

      await storageRef.putFile(file);
      String downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'profile_picture': downloadUrl});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profilová fotka změněna!')),
        );
      }
    } catch (e) {
      print("Chyba: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null && widget.viewUserId == null) {
      return Scaffold(body: Center(child: Text("Nejste přihlášen")));
    }

    return Scaffold(
      extendBodyBehindAppBar: true, // Gradient až nahoru
      appBar: AppBar(
        title: Text(_isMyProfile ? "Můj Profil" : "Profil uživatele", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.black87),
        actions: [
          if (_isMyProfile) ...[
            Container(
              margin: EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), shape: BoxShape.circle),
              child: IconButton(
                icon: Icon(Icons.people, color: Colors.blue[800]),
                tooltip: "Přátelé",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FriendsScreen())),
              ),
            ),
            Container(
              margin: EdgeInsets.only(right: 15, left: 5),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), shape: BoxShape.circle),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 100, 20, 20), // Top padding kvůli AppBaru
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. HLAVIČKA (Avatar + Jméno)
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(_targetUserId).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
                  if (!snapshot.data!.exists) return Text("Uživatel nenalezen");

                  var data = snapshot.data!.data() as Map<String, dynamic>?;
                  String? photoUrl = data != null && data.containsKey('profile_picture') ? data['profile_picture'] : null;

                  return Column(
                    children: [
                      // Avatar
                      GestureDetector(
                        onTap: _pickAndUploadImage,
                        child: Stack(
                          children: [
                            Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                              ),
                              child: CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.blue[50],
                                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                child: _isUploading
                                    ? CircularProgressIndicator()
                                    : (photoUrl == null ? Icon(Icons.person, size: 50, color: Colors.blue[200]) : null),
                              ),
                            ),
                            if (_isMyProfile)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                ),
                              )
                          ],
                        ),
                      ),
                      SizedBox(height: 15),
                      // Jméno
                      Text(
                        data?['username'] ?? "Neznámý horal",
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black87),
                      ),
                      if (_isMyProfile)
                        Text(data?['email'] ?? "", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    ],
                  );
                },
              ),

              SizedBox(height: 20),

              // 2. TLAČÍTKO PRO PŘÁTELSTVÍ (Jen na cizím profilu)
              if (!_isMyProfile)
                StreamBuilder<String>(
                  stream: FriendService().getFriendshipStatus(FirebaseAuth.instance.currentUser!.uid, _targetUserId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return SizedBox();

                    String status = snapshot.data!;
                    String text;
                    Color bgColor;
                    Color txtColor = Colors.white;
                    IconData icon;
                    VoidCallback? action;

                    switch (status) {
                      case 'accepted':
                        text = "Jste přátelé";
                        bgColor = Colors.green;
                        icon = Icons.check_circle;
                        action = () {
                          showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text("Odebrat přítele?"),
                                content: Text("Opravdu chcete odebrat tohoto uživatele z přátel?"),
                                actions: [
                                  TextButton(child: Text("Ne"), onPressed: () => Navigator.pop(ctx)),
                                  TextButton(
                                      child: Text("Ano", style: TextStyle(color: Colors.red)),
                                      onPressed: () {
                                        FriendService().removeFriend(FirebaseAuth.instance.currentUser!.uid, _targetUserId);
                                        Navigator.pop(ctx);
                                      }
                                  ),
                                ],
                              )
                          );
                        };
                        break;
                      case 'sent':
                        text = "Žádost odeslána";
                        bgColor = Colors.grey[300]!;
                        txtColor = Colors.black87;
                        icon = Icons.hourglass_top;
                        action = () => FriendService().removeFriend(FirebaseAuth.instance.currentUser!.uid, _targetUserId);
                        break;
                      case 'received':
                        text = "Přijmout žádost";
                        bgColor = Colors.blue;
                        icon = Icons.person_add;
                        action = () => FriendService().acceptFriendRequest(FirebaseAuth.instance.currentUser!.uid, _targetUserId);
                        break;
                      default:
                        text = "Přidat do přátel";
                        bgColor = Colors.blueAccent;
                        icon = Icons.person_add_alt_1;
                        action = () => FriendService().sendFriendRequest(FirebaseAuth.instance.currentUser!.uid, _targetUserId);
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

              SizedBox(height: 30),

              // 3. STATISTIKY (GRID)
              Align(alignment: Alignment.centerLeft, child: Text("Statistiky", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87))),
              SizedBox(height: 15),

              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(_targetUserId).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!.exists) return SizedBox();
                  var data = snapshot.data!.data() as Map<String, dynamic>?;

                  int totalClimbs = data?['total_climbs'] ?? 0;
                  int totalSeconds = data?['total_time_seconds'] ?? 0;

                  double totalDist = 0.0;
                  if (data != null && data.containsKey('total_distance')) {
                    totalDist = (data['total_distance'] as num).toDouble();
                  }

                  return GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                    childAspectRatio: 1.4,
                    children: [
                      _buildStatCard("Výšlapy", "$totalClimbs", Icons.landscape, Colors.green),
                      _buildStatCard("Čas v horách", _formatDuration(totalSeconds), Icons.timer, Colors.orange),
                      _buildStatCard("Vzdálenost", "${totalDist.toStringAsFixed(1)} km", Icons.directions_walk, Colors.blue),
                      _buildStatCard("Spálené kalorie", "${totalClimbs * 450} kcal", Icons.local_fire_department, Colors.red),
                    ],
                  );
                },
              ),

              SizedBox(height: 30),

              // 4. SEZNAM HOR
              Align(alignment: Alignment.centerLeft, child: Text("Zdolal tyto hory", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87))),
              SizedBox(height: 15),

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(_targetUserId)
                    .collection('mountain_stats')
                    .orderBy('climbs_count', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                      child: Column(
                        children: [
                          Icon(Icons.hiking, color: Colors.grey[300], size: 40),
                          SizedBox(height: 10),
                          Text("Zatím žádné zdolané hory.", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      var doc = snapshot.data!.docs[index];

                      return Container(
                        margin: EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 4))],
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
                                    mountainID: doc['mountainID'],
                                    userId: _targetUserId,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  // Ikonka hory
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.terrain, color: Colors.blue[800], size: 24),
                                  ),
                                  SizedBox(width: 16),
                                  // Texty
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            doc['mountainID'],
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)
                                        ),
                                        SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.emoji_events, size: 14, color: Colors.amber),
                                            SizedBox(width: 4),
                                            Text(
                                                "${doc['best_time_str']}",
                                                style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w500, fontSize: 13)
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Počet
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                        "${doc['climbs_count']}x",
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue[800])
                                    ),
                                  ),
                                  SizedBox(width: 10),
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
              SizedBox(height: 30),
            ],
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
          SizedBox(height: 2),
          Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 11), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}