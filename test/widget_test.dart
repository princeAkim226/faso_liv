import 'package:flutter_test/flutter_test.dart';
import 'package:faso_liv/core/theme/app_theme.dart';

void main() {
  test('Palette FasoLiv définie', () {
    expect(AppColors.savane.toARGB32(), isNonZero);
    expect(AppColors.terre.toARGB32(), isNonZero);
  });
}
