/// Exceptions métier FasoLiv — messages en français pour l'UI.
class AppException implements Exception {
  AppException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class SoldeInsuffisantException extends AppException {
  SoldeInsuffisantException({
    required this.solde,
    required this.commission,
  }) : super(
          'Solde insuffisant (${solde.toStringAsFixed(0)} FCFA). '
          'Commission requise : ${commission.toStringAsFixed(0)} FCFA.',
          code: 'SOLDE_INSUFFISANT',
        );

  final double solde;
  final double commission;
}

class CodeOtpInvalideException extends AppException {
  CodeOtpInvalideException()
      : super(
          'Code OTP incorrect. Vérifiez le code fourni par le destinataire.',
          code: 'CODE_OTP_INVALIDE',
        );
}

class MobileMoneyException extends AppException {
  MobileMoneyException(super.message, {super.code});
}
