import 'package:supabase_flutter/supabase_flutter.dart';

class AppConstants {
  // Supabase konfigurace
  static const String supabaseUrl = "https://xbvszksjfokjbrslsrqe.supabase.co";
  static const String supabaseAnonKey =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhidnN6a3NqZm9ramJyc2xzcnFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg1MzExOTIsImV4cCI6MjEwNDEwNzE5Mn0.kt7Gbg23uLhB9xcS904NP05RhbMGEvTAWV1OFu_I6KA";

  // OpenWeather API klíč
  static const String openWeatherApiKey = "f8b639faa2109c23051daa0a4b532182";

  // Tolerance v metrech pro detekci startu a cíle
  static const double gpsTolerance = 30.0;
  static const double goalTolerance = 80.0;
}

final supabase = Supabase.instance.client;