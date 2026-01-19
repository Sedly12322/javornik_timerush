// lib/utils/constants.dart
class AppConstants {
  // POZOR: V produkci by tento klíč neměl být přímo v kódu, ale např. v .env souboru
  // Pro vývoj to zatím necháme zde, ale je to na jednom místě.
  static const String openWeatherApiKey = "f8b639faa2109c23051daa0a4b532182";

  // Tolerance v metrech pro detekci startu a cíle
  static const double gpsTolerance = 30.0;
}