import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/constants.dart';

class FriendService {
  // Odeslat žádost
  Future<void> sendFriendRequest(String currentUserId, String targetUserId) async {
    try {
      await supabase.rpc('send_friend_request', params: {
        'target_user_id': targetUserId,
      });
    } catch (e) {
      debugPrint("RPC send_friend_request selhalo ($e), zkouším přímý zápis...");
      // 1. U mě: Stav 'sent' (odesláno)
      await supabase.from('friends').upsert({
        'user_id': currentUserId,
        'friend_id': targetUserId,
        'status': 'sent',
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2. U něj: Stav 'received' (přijato)
      await supabase.from('friends').upsert({
        'user_id': targetUserId,
        'friend_id': currentUserId,
        'status': 'received',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  // Přijmout žádost
  Future<void> acceptFriendRequest(String currentUserId, String targetUserId) async {
    try {
      await supabase.rpc('accept_friend_request', params: {
        'target_user_id': targetUserId,
      });
    } catch (e) {
      debugPrint("RPC accept_friend_request selhalo ($e), zkouším přímý zápis...");
      await supabase.from('friends').update({'status': 'accepted'}).match({
        'user_id': currentUserId,
        'friend_id': targetUserId,
      });
      await supabase.from('friends').update({'status': 'accepted'}).match({
        'user_id': targetUserId,
        'friend_id': currentUserId,
      });
    }
  }

  // Zrušit přátelství / Odmítnout žádost
  Future<void> removeFriend(String currentUserId, String targetUserId) async {
    try {
      await supabase.rpc('remove_friend', params: {
        'target_user_id': targetUserId,
      });
    } catch (e) {
      debugPrint("RPC remove_friend selhalo ($e), zkouším přímý zápis...");
      await supabase.from('friends').delete().match({
        'user_id': currentUserId,
        'friend_id': targetUserId,
      });
      await supabase.from('friends').delete().match({
        'user_id': targetUserId,
        'friend_id': currentUserId,
      });
    }
  }

  // Zjistit status pro profil
  Stream<String> getFriendshipStatus(String currentUserId, String targetUserId) {
    return supabase
        .from('friends')
        .stream(primaryKey: ['user_id', 'friend_id'])
        .eq('user_id', currentUserId)
        .map((records) {
      final match = records.where((r) => r['friend_id'] == targetUserId).toList();
      if (match.isEmpty) return 'none';
      return (match.first['status'] as String?) ?? 'none';
    });
  }
}