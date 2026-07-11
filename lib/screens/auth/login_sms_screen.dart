import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../services/sms_otp_service.dart';
import '../../widgets/brand_widgets.dart';
import 'sms_otp_screen.dart';

/// Connexion livreur par numéro de téléphone + SMS.
class LoginSmsScreen extends StatefulWidget {
  const LoginSmsScreen({super.key});

  @override
  State<LoginSmsScreen> createState() => _LoginSmsScreenState();
}

class _LoginSmsScreenState extends State<LoginSmsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tel = TextEditingController(text: '+226 ');
  final _otp = SmsOtpService();
  bool _chargement = false;

  @override
  void dispose() {
    _tel.dispose();
    super.dispose();
  }

  Future<void> _continuer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _chargement = true);
    try {
      final phone = _otp.normaliser(_tel.text);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SmsOtpScreen(
            telephone: phone,
            pourInscription: false,
          ),
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FasoBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(height: 8),
                  const BrandMark(compact: true),
                  const SizedBox(height: 28),
                  Text(
                    'Connexion SMS',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Recevez un code de vérification sur votre téléphone.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _tel,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone',
                      prefixIcon: Icon(Icons.phone_android),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 8) {
                        return 'Numéro invalide';
                      }
                      return null;
                    },
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _chargement ? null : _continuer,
                      child: _chargement
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Recevoir le code'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
