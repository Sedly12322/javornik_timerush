import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:javornik_timerush/screens/profile_screen.dart';
import 'package:javornik_timerush/services/friend_service.dart';

class FriendsScreen extends StatefulWidget {
  @override
  _FriendsScreenState createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FriendService _friendService = FriendService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Přátelé", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white.withOpacity(0.9), // Průsvitná bílá
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.black87),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue[800],
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue[800],
          indicatorWeight: 3,
          labelStyle: TextStyle(fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: "Moji přátelé"),
            Tab(text: "Žádosti"),
          ],
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
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildFriendsList('accepted'), // Seznam přátel
            _buildFriendsList('received'), // Příchozí žádosti
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('friends')
          .where('status', isEqualTo: status)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

        if (snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                    status == 'accepted' ? Icons.people_outline : Icons.mail_outline,
                    size: 60, color: Colors.grey[300]
                ),
                SizedBox(height: 10),
                Text(
                  status == 'accepted' ? "Nemáte zatím žádné přátele." : "Žádné nové žádosti.",
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          // Padding nahoře, aby to nebylo nalepené na AppBar
          padding: EdgeInsets.fromLTRB(16, 20, 16, 20),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var friendDoc = snapshot.data!.docs[index];
            String friendId = friendDoc.id;

            // Načítání detailů uživatele
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(friendId).get(),
              builder: (context, userSnapshot) {
                // Zatímco se načítá, ukážeme placeholder kartu
                if (!userSnapshot.hasData) {
                  return Container(
                    height: 70,
                    margin: EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }

                var userData = userSnapshot.data!.data() as Map<String, dynamic>;
                String username = userData['username'] ?? "Neznámý";
                String? photoUrl = userData['profile_picture'];

                return Container(
                  margin: EdgeInsets.only(bottom: 10), // Mezera mezi kartami
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15), // Zaoblené rohy
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5, offset: Offset(0, 2))],
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () {
                        // Po kliknutí otevřeme jeho profil
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfileScreen(viewUserId: friendId),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            // 1. AVATAR
                            Container(
                              padding: EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
                              ),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.blue[50],
                                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                child: photoUrl == null ? Text(username[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)) : null,
                              ),
                            ),

                            SizedBox(width: 15),

                            // 2. JMÉNO
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      username,
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)
                                  ),
                                  if (status == 'received')
                                    Text("Chce být tvůj přítel", style: TextStyle(fontSize: 12, color: Colors.blue)),
                                ],
                              ),
                            ),

                            // 3. AKCE (Buď šipka, nebo tlačítka)
                            if (status == 'received') ...[
                              // Tlačítko PŘIJMOUT
                              InkWell(
                                onTap: () => _friendService.acceptFriendRequest(_currentUserId, friendId),
                                child: Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.green[50], shape: BoxShape.circle),
                                  child: Icon(Icons.check, color: Colors.green, size: 20),
                                ),
                              ),
                              SizedBox(width: 10),
                              // Tlačítko ODMÍTNOUT
                              InkWell(
                                onTap: () => _friendService.removeFriend(_currentUserId, friendId),
                                child: Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                                  child: Icon(Icons.close, color: Colors.red, size: 20),
                                ),
                              ),
                            ] else ...[
                              // Jen šipka pro existující přátele
                              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[300]),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}