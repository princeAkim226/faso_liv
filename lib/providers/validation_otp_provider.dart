import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_exceptions.dart';
import '../models/course.dart';
import 'service_providers.dart';

/// État de la validation OTP côté livreur.
class ValidationOtpState {
  const ValidationOtpState({
    this.course,
    this.chargement = false,
    this.validationEnCours = false,
    this.erreur,
    this.succes = false,
  });

  final Course? course;
  final bool chargement;
  final bool validationEnCours;
  final String? erreur;
  final bool succes;

  ValidationOtpState copyWith({
    Course? course,
    bool? chargement,
    bool? validationEnCours,
    String? erreur,
    bool? succes,
    bool clearErreur = false,
  }) {
    return ValidationOtpState(
      course: course ?? this.course,
      chargement: chargement ?? this.chargement,
      validationEnCours: validationEnCours ?? this.validationEnCours,
      erreur: clearErreur ? null : (erreur ?? this.erreur),
      succes: succes ?? this.succes,
    );
  }
}

class ValidationOtpNotifier extends StateNotifier<ValidationOtpState> {
  ValidationOtpNotifier(this._ref) : super(const ValidationOtpState());

  final Ref _ref;

  Future<void> chargerCourse(String courseId) async {
    state = state.copyWith(chargement: true, clearErreur: true);
    try {
      final course =
          await _ref.read(courseServiceProvider).getCourse(courseId);
      state = state.copyWith(course: course, chargement: false);
    } on AppException catch (e) {
      state = state.copyWith(chargement: false, erreur: e.message);
    } catch (e) {
      state = state.copyWith(chargement: false, erreur: 'Erreur : $e');
    }
  }

  /// Compare le code saisi avec `code_otp_validation` via RPC sécurisée.
  Future<bool> valider(String codeOtp) async {
    final course = state.course;
    if (course == null) {
      state = state.copyWith(erreur: 'Aucune course chargée.');
      return false;
    }

    state = state.copyWith(
      validationEnCours: true,
      clearErreur: true,
      succes: false,
    );

    try {
      final miseAJour = await _ref.read(courseServiceProvider).validerLivraisonOtp(
            courseId: course.id,
            codeOtp: codeOtp,
          );
      state = state.copyWith(
        course: miseAJour,
        validationEnCours: false,
        succes: true,
      );
      return true;
    } on CodeOtpInvalideException catch (e) {
      state = state.copyWith(validationEnCours: false, erreur: e.message);
      return false;
    } on AppException catch (e) {
      state = state.copyWith(validationEnCours: false, erreur: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        validationEnCours: false,
        erreur: 'Erreur : $e',
      );
      return false;
    }
  }
}

final validationOtpProvider =
    StateNotifierProvider.autoDispose<ValidationOtpNotifier, ValidationOtpState>(
  (ref) => ValidationOtpNotifier(ref),
);
