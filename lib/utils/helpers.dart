import 'dart:math';

String generateDiscriminator() {
  // Vygeneruje číslo od 1000 do 9999
  int randomNum = 1000 + Random().nextInt(9000);
  return "#$randomNum";
}