import 'package:cloud_firestore/cloud_firestore.dart';

class FriendService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Odeslat žádost
  Future<void> sendFriendRequest(String currentUserId, String targetUserId) async {
    // 1. U mě: Stav 'sent' (odesláno)
    await _db.collection('users').doc(currentUserId).collection('friends').doc(targetUserId).set({
      'status': 'sent',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 2. U něj: Stav 'received' (přijato)
    await _db.collection('users').doc(targetUserId).collection('friends').doc(currentUserId).set({
      'status': 'received',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Přijmout žádost
  Future<void> acceptFriendRequest(String currentUserId, String targetUserId) async {
    // U obou nastavíme status 'accepted'
    await _db.collection('users').doc(currentUserId).collection('friends').doc(targetUserId).update({
      'status': 'accepted',
    });
    await _db.collection('users').doc(targetUserId).collection('friends').doc(currentUserId).update({
      'status': 'accepted',
    });
  }

  // Zrušit přátelství / Odmítnout žádost
  Future<void> removeFriend(String currentUserId, String targetUserId) async {
    await _db.collection('users').doc(currentUserId).collection('friends').doc(targetUserId).delete();
    await _db.collection('users').doc(targetUserId).collection('friends').doc(currentUserId).delete();
  }

  // Zjistit status (pro tlačítko v profilu)
  Stream<String> getFriendshipStatus(String currentUserId, String targetUserId) {
    return _db
        .collection('users')
        .doc(currentUserId)
        .collection('friends')
        .doc(targetUserId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return 'none';
      return snapshot.data()?['status'] ?? 'none';
    });
  }
}