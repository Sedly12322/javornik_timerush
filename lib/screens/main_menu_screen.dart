import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:javornik_timerush/screens/auth_screen.dart';
import 'package:javornik_timerush/screens/profile_screen.dart';
import 'package:javornik_timerush/screens/friends_screen.dart';
import 'package:javornik_timerush/screens/search_users_screen.dart';
import 'package:javornik_timerush/screens/route_selection_screen.dart';
import 'package:javornik_timerush/screens/about_screen.dart';
import 'package:javornik_timerush/screens/leaderboard_selection_screen.dart'; // <--- NOVÝ IMPORT

class MainMenuScreen extends StatefulWidget {
  @override
  _MainMenuScreenState createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  void _signOut() async {
    await _auth.signOut();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Image.asset(
          "assets/images/logofinal.png",
          width: 120,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.logout, color: Colors.blueGrey, size: 20),
              onPressed: _signOut,
              tooltip: "Odhlásit se",
            ),
          )
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
            builder: (context, snapshot) {
              String username = "Horale";
              String? photoUrl;

              if (snapshot.hasData && snapshot.data!.exists) {
                var data = snapshot.data!.data() as Map<String, dynamic>;
                username = data['username'] ?? "Horale";
                photoUrl = data['profile_picture'];
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 10),

                    // 1. HLAVIČKA
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Vítej zpět,", style: TextStyle(fontSize: 16, color: Colors.blueGrey[700])),
                              Text(username, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black87)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen())),
                          child: Container(
                            padding: EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                            ),
                            child: CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.blue[50],
                              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                              child: photoUrl == null ? Icon(Icons.person, size: 28, color: Colors.blue[300]) : null,
                            ),
                          ),
                        )
                      ],
                    ),

                    SizedBox(height: 30),

                    // 2. HLAVNÍ KARTA (START)
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => RouteSelectionScreen()),
                        );
                      },
                      child: Container(
                        height: 160,
                        width: double.infinity,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(25),
                            image: DecorationImage(
                              image: NetworkImage("https://images.unsplash.com/photo-1519681393784-d8e5b5a45460?ixlib=rb-1.2.1&auto=format&fit=crop&w=1350&q=80"),
                              fit: BoxFit.cover,
                            ),
                            boxShadow: [
                              BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 15, offset: Offset(0, 8))
                            ]
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(25),
                            gradient: LinearGradient(
                              colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                            ),
                          ),
                          padding: EdgeInsets.all(25),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                                child: Icon(Icons.directions_run, color: Colors.white, size: 24),
                              ),
                              SizedBox(height: 10),
                              Text("JÍT NA HORU", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              Text("Vyber trasu a spusť stopky", style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 30),
                    Text("Menu", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    SizedBox(height: 15),

                    // 3. MŘÍŽKA MENU
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 15,
                        mainAxisSpacing: 15,
                        childAspectRatio: 1.3,
                        children: [
                          _buildMenuCard(
                            title: "Žebříčky", // <--- NOVÉ TLAČÍTKO
                            icon: Icons.emoji_events,
                            color: Colors.amber,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => LeaderboardSelectionScreen())),
                          ),
                          _buildMenuCard(
                            title: "Můj Profil",
                            icon: Icons.person,
                            color: Colors.blueAccent,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen())),
                          ),
                          _buildMenuCard(
                            title: "Přátelé",
                            icon: Icons.people,
                            color: Colors.green,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FriendsScreen())),
                          ),
                          _buildMenuCard(
                            title: "Hledat",
                            icon: Icons.search,
                            color: Colors.purple,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SearchUsersScreen())),
                          ),
                          _buildMenuCard(
                            title: "O aplikaci",
                            icon: Icons.info_outline,
                            color: Colors.orange,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AboutScreen())),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard({required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: Offset(0, 4))],
            border: Border.all(color: Colors.grey.shade50)
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 26, color: color),
            ),
            SizedBox(height: 10),
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}