import 'package:flutter/material.dart';
import 'package:javornik_timerush/screens/profile_screen.dart';
import 'package:javornik_timerush/services/friend_service.dart';
import 'package:javornik_timerush/utils/constants.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  FriendsScreenState createState() => FriendsScreenState();
}

class FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FriendService _friendService = FriendService();
  final String _currentUserId = supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Přátelé", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue[800],
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue[800],
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: "Moji přátelé"),
            Tab(text: "Žádosti"),
          ],
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
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildFriendsList('accepted'),
            _buildFriendsList('received'),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsList(String status) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('friends')
          .stream(primaryKey: ['user_id', 'friend_id'])
          .eq('user_id', _currentUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final filteredFriends = snapshot.hasData
            ? snapshot.data!.where((f) => f['status'] == status).toList()
            : <Map<String, dynamic>>[];

        if (filteredFriends.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  status == 'accepted' ? Icons.people_outline : Icons.mail_outline,
                  size: 60,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 10),
                Text(
                  status == 'accepted' ? "Nemáte zatím žádné přátele." : "Žádné nové žádosti.",
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
          itemCount: filteredFriends.length,
          itemBuilder: (context, index) {
            final friendRecord = filteredFriends[index];
            final String friendId = friendRecord['friend_id'];

            return FutureBuilder<Map<String, dynamic>?>(
              future: supabase.from('profiles').select().eq('id', friendId).maybeSingle(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return Container(
                    height: 70,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                    child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }

                final userData = userSnapshot.data ?? {};
                final String username = userData['full_username'] ?? userData['username'] ?? "Neznámý";
                final String? photoUrl = userData['profile_picture'];

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 5, offset: const Offset(0, 2))],
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
                            builder: (context) => ProfileScreen(viewUserId: friendId),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 1),
                              ),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.blue[50],
                                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                child: photoUrl == null
                                    ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    username,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                                  ),
                                  if (status == 'received')
                                    const Text("Chce být tvůj přítel", style: TextStyle(fontSize: 12, color: Colors.blue)),
                                ],
                              ),
                            ),
                            if (status == 'received') ...[
                              InkWell(
                                onTap: () => _friendService.acceptFriendRequest(_currentUserId, friendId),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.green[50], shape: BoxShape.circle),
                                  child: const Icon(Icons.check, color: Colors.green, size: 20),
                                ),
                              ),
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () => _friendService.removeFriend(_currentUserId, friendId),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                                  child: const Icon(Icons.close, color: Colors.red, size: 20),
                                ),
                              ),
                            ] else ...[
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