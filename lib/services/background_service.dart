import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/constants.dart';

const String channelId = 'my_foreground';
const int notifId = 888;

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

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
    enableVibration: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channelRunning);
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channelAlert);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: channelId,
      initialNotificationTitle: 'Javorník TimeRush',
      initialNotificationContent: 'Připravuji...',
      foregroundServiceNotificationId: notifId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  await notifications.initialize(
    const InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    ),
  );

  DateTime? startTime;
  Timer? timer;
  StreamSubscription<Position>? gpsStream;
  Map<String, dynamic>? tripData;
  bool isFinished = false;

  service.invoke('serviceReady');

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

    try {
      await notifications.show(
        notifId,
        'Výšlap probíhá 🏔️',
        'Čas: 00:00',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Javorník TimeRush',
            icon: '@mipmap/ic_launcher',
            ongoing: true,
            autoCancel: false,
            showWhen: false,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: false,
          ),
        ),
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
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Javorník TimeRush',
            icon: '@mipmap/ic_launcher',
            ongoing: true,
            autoCancel: false,
            showWhen: false,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: false,
          ),
        ),
      );
    });

    // GPS nastavení optimalizované pro Android i iOS na pozadí
    LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      );
    }

    gpsStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((pos) async {
      service.invoke('updateLocation', {'lat': pos.latitude, 'lng': pos.longitude});

      if (tripData != null && !isFinished) {
        double dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          tripData!['endLat'],
          tripData!['endLng'],
        );

        if (dist < AppConstants.goalTolerance) {
          isFinished = true;
          timer?.cancel();

          final elapsed = DateTime.now().difference(startTime!);
          final finalTimeStr = _formatDuration(elapsed);

          try {
            await _saveToSupabase(tripData!, finalTimeStr, elapsed.inSeconds);
          } catch (e) {
            print("SERVICE: Chyba ukládání do Supabase: $e");
          }

          service.invoke('tripFinished', {'finalTime': finalTimeStr});

          notifications.cancel(notifId);
          notifications.show(
            999,
            'CÍL DOSAŽEN! 🏆',
            'Čas: $finalTimeStr',
            NotificationDetails(
              android: AndroidNotificationDetails(
                'my_foreground_alert_v2',
                'Cíl Dosažen',
                importance: Importance.max,
                priority: Priority.high,
                playSound: true,
                enableVibration: true,
                vibrationPattern: Int64List.fromList([0, 1000, 500, 2000]),
                icon: '@mipmap/ic_launcher',
                styleInformation: BigTextStyleInformation('Gratulujeme! Váš čas je $finalTimeStr.'),
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
          );

          await Future.delayed(const Duration(seconds: 10));
          service.stopSelf();
        }
      }
    });
  });
}

Future<void> _saveToSupabase(Map<String, dynamic> data, String timeStr, int seconds) async {
  final client = SupabaseClient(AppConstants.supabaseUrl, AppConstants.supabaseAnonKey);
  final uid = data['userId'];
  final mountainId = data['mountainId'];
  final routeId = data['routeId'];
  final double distanceKm = (data['distanceKm'] as num?)?.toDouble() ?? 0.0;

  // 1. Zápis výšlapu
  await client.from('climbs').insert({
    'user_id': uid,
    'mountain_id': mountainId,
    'trail_id': routeId,
    'time': timeStr,
    'time_seconds': seconds,
    'distance_km': distanceKm,
    'date': DateTime.now().toIso8601String(),
    'is_auto_finished': true,
  });

  // 2. Aktualizace uživatelského profilu
  try {
    final profile = await client
        .from('profiles')
        .select('total_climbs, total_time_seconds, total_distance')
        .eq('id', uid)
        .maybeSingle();

    if (profile != null) {
      int totalClimbs = (profile['total_climbs'] as int? ?? 0) + 1;
      int totalSeconds = (profile['total_time_seconds'] as int? ?? 0) + seconds;
      double totalDist = ((profile['total_distance'] as num?)?.toDouble() ?? 0.0) + distanceKm;

      await client.from('profiles').update({
        'is_running': false,
        'total_climbs': totalClimbs,
        'total_time_seconds': totalSeconds,
        'total_distance': totalDist,
      }).eq('id', uid);
    }
  } catch (e) {
    print("SERVICE: Chyba aktualizace profilu: $e");
  }

  // 3. Aktualizace statistik dané hory
  try {
    final mStat = await client
        .from('mountain_stats')
        .select()
        .eq('user_id', uid)
        .eq('mountain_id', mountainId)
        .maybeSingle();

    if (mStat == null) {
      await client.from('mountain_stats').insert({
        'user_id': uid,
        'mountain_id': mountainId,
        'climbs_count': 1,
        'last_climb_date': DateTime.now().toIso8601String(),
        'best_time_seconds': seconds,
        'best_time_str': timeStr,
      });
    } else {
      int currentBest = (mStat['best_time_seconds'] as int? ?? 999999);
      Map<String, dynamic> updateData = {
        'climbs_count': (mStat['climbs_count'] as int? ?? 0) + 1,
        'last_climb_date': DateTime.now().toIso8601String(),
      };
      if (seconds < currentBest) {
        updateData['best_time_seconds'] = seconds;
        updateData['best_time_str'] = timeStr;
      }
      await client
          .from('mountain_stats')
          .update(updateData)
          .eq('user_id', uid)
          .eq('mountain_id', mountainId);
    }
  } catch (e) {
    print("SERVICE: Chyba aktualizace mountain_stats: $e");
  }
}

String _formatDuration(Duration d) {
  String twoDigits(int n) => n.toString().padLeft(2, "0");
  return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}";
}