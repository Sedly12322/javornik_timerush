import 'package:flutter_test/flutter_test.dart';
import 'package:javornik_timerush/utils/helpers.dart';
import 'package:javornik_timerush/utils/constants.dart';

void main() {
  group('Helpers & Constants Tests', () {
    test('generateDiscriminator returns valid discriminator format #XXXX', () {
      for (int i = 0; i < 50; i++) {
        final disc = generateDiscriminator();
        expect(disc.startsWith('#'), isTrue);
        expect(disc.length, equals(5));
        final number = int.tryParse(disc.substring(1));
        expect(number, isNotNull);
        expect(number! >= 1000 && number <= 9999, isTrue);
      }
    });

    test('AppConstants has valid Supabase configuration', () {
      expect(AppConstants.supabaseUrl, isNotEmpty);
      expect(AppConstants.supabaseAnonKey, isNotEmpty);
      expect(AppConstants.gpsTolerance, greaterThan(0));
      expect(AppConstants.goalTolerance, greaterThan(0));
    });
  });
}
