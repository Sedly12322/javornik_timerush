import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const String channelId = 'my_foreground';
const int notifId = 888;

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // --- KROK 1: NEJDŘÍV VYTVOŘIT KANÁL (Kritická oprava) ---
  // Musí to být předtím, než zavoláme service.configure()
  const AndroidNotificationChannel channelRunning = AndroidNotificationChannel(
    channelId,
    'Javorník TimeRush',
    description: 'Běží časomíra',
    importance: Importance.low,
  );

  const AndroidNotificationChannel channelAlert = AndroidNotificationChannel(
      'my_foreground_alert_v2',
      'Cíl Dosažen',
      importance: Importance.max,
      playSound: true,
      enableVibration: true
  );

  // Vytvoříme kanály v systému
  await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channelRunning);
  await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channelAlert);

  // --- KROK 2: AŽ TEĎ KONFIGUROVAT SLUŽBU ---
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: channelId, // Teď už tento kanál existuje!
      initialNotificationTitle: 'Javorník TimeRush',
      initialNotificationContent: 'Připravuji...',
      foregroundServiceNotificationId: notifId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    print("SERVICE ERROR: Firebase init failed: $e");
  }

  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

  // Inicializace ikony
  // Používáme @mipmap/ic_launcher, to je standardní ikona aplikace
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  await notifications.initialize(
      const InitializationSettings(android: initializationSettingsAndroid)
  );

  DateTime? startTime;
  Timer? timer;
  StreamSubscription<Position>? gpsStream;
  Map<String, dynamic>? tripData;
  bool isFinished = false;

  service.on('stopService').listen((event) {
    timer?.cancel();
    gpsStream?.cancel();
    notifications.cancelAll();
    service.stopSelf();
  });

  service.on('startTracking').listen((event) async {
    tripData = event;
    startTime = DateTime.now();
    isFinished = false;

    timer?.cancel();
    gpsStream?.cancel();

    // Okamžitá notifikace
    try {
      await notifications.show(
          notifId,
          'Výšlap probíhá 🏔️',
          'Čas: 00:00',
          const NotificationDetails(android: AndroidNotificationDetails(
              channelId, 'Javorník TimeRush',
              icon: '@mipmap/ic_launcher',
              ongoing: true, autoCancel: false, onlyAlertOnce: true, showWhen: false
          ))
      );
    } catch (e) {
      print("Chyba zobrazení notifikace: $e");
    }

    // Časovač
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (startTime == null || isFinished) return;

      final elapsed = DateTime.now().difference(startTime!);
      service.invoke('updateTime', {'elapsed': elapsed.inSeconds});

      notifications.show(
          notifId,
          'Výšlap probíhá 🏔️',
          'Čas: ${_formatDuration(elapsed)}',
          const NotificationDetails(android: AndroidNotificationDetails(
              channelId, 'Javorník TimeRush',
              icon: '@mipmap/ic_launcher',
              ongoing: true, autoCancel: false, onlyAlertOnce: true, showWhen: false
          ))
      );
    });

    // GPS
    gpsStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 5)
    ).listen((pos) async {
      service.invoke('updateLocation', {'lat': pos.latitude, 'lng': pos.longitude});

      if (tripData != null && !isFinished) {
        double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, tripData!['endLat'], tripData!['endLng']);

        // Zvýšeno na 80m pro jistotu
        if (dist < 80.0) {
          isFinished = true;
          timer?.cancel();

          final finalTimeStr = _formatDuration(DateTime.now().difference(startTime!));

          try {
            await _saveToFirebase(tripData!, finalTimeStr, DateTime.now().difference(startTime!).inSeconds);
          } catch (e) {
            print("SERVICE: Chyba ukládání: $e");
          }

          service.invoke('tripFinished', {'finalTime': finalTimeStr});

          notifications.cancel(notifId);
          notifications.show(
              999,
              'CÍL DOSAŽEN! 🏆',
              'Čas: $finalTimeStr',
              NotificationDetails(android: AndroidNotificationDetails(
                  'my_foreground_alert_v2', 'Cíl Dosažen',
                  importance: Importance.max, priority: Priority.high,
                  playSound: true, enableVibration: true,
                  vibrationPattern: Int64List.fromList([0, 1000, 500, 2000]),
                  icon: '@mipmap/ic_launcher',
                  styleInformation: BigTextStyleInformation('Gratulujeme! Váš čas je $finalTimeStr.')
              ))
          );

          await Future.delayed(const Duration(seconds: 10));
          service.stopSelf();
        }
      }
    });
  });
}

Future<void> _saveToFirebase(Map<String, dynamic> data, String timeStr, int seconds) async {
  final db = FirebaseFirestore.instance;
  final batch = db.batch();
  final uid = data['userId'];

  final climbRef = db.collection('users').doc(uid).collection('climbs').doc();
  batch.set(climbRef, {
    'mountainID': data['mountainId'],
    'trailID': data['routeId'],
    'time': timeStr,
    'time_seconds': seconds,
    'date': DateTime.now(),
    'distance_km': 0.0,
    'is_auto_finished': true
  });

  batch.set(db.collection('users').doc(uid), {
    'is_running': false,
    'total_climbs': FieldValue.increment(1),
    'total_time_seconds': FieldValue.increment(seconds),
  }, SetOptions(merge: true));

  await batch.commit();
}

String _formatDuration(Duration d) {
  String twoDigits(int n) => n.toString().padLeft(2, "0");
  return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}";
}