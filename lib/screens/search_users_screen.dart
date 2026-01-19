import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:javornik_timerush/screens/profile_screen.dart';

class SearchUsersScreen extends StatefulWidget {
  @override
  _SearchUsersScreenState createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
        title: Container(
          height: 45,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: "Hledat uživatele...",
              hintStyle: TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.search, color: Colors.grey),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, color: Colors.grey, size: 20),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = "";
                  });
                },
              )
                  : null,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 10),
            ),
            onChanged: (val) {
              setState(() {
                _searchQuery = val.toLowerCase();
              });
            },
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Color.fromRGBO(200, 228, 255, 0.5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(child: Text("Žádní uživatelé v databázi."));
            }

            var users = snapshot.data!.docs.where((doc) {
              var data = doc.data() as Map<String, dynamic>;
              String username = (data['username'] ?? "").toString().toLowerCase();
              String discriminator = (data['discriminator'] ?? "").toString();

              // Vytvoříme plné jméno pro hledání (např. "dominik#1234")
              String fullName = "$username$discriminator".toLowerCase();

              // Hledáme buď jen ve jméně, nebo v celém řetězci
              return username.contains(_searchQuery) || fullName.contains(_searchQuery);
            }).toList();

            return ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 20),
              itemCount: users.length,
              itemBuilder: (context, index) {
                var data = users[index].data() as Map<String, dynamic>;
                String userId = users[index].id;
                String username = data['username'] ?? "Neznámý";
                String? photoUrl = data['profile_picture'];

                return Container(
                  margin: EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5, offset: Offset(0, 2))],
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfileScreen(viewUserId: userId),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            // Avatar
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

                            // Jméno
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      username,
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)
                                  ),
                                  Text("Horal", style: TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),

                            // Šipka
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
      ),
    );
  }
}