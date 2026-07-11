import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/brand_widgets.dart';

/// Écran de saisie du code SMS à 6 chiffres.
class SmsOtpScreen extends ConsumerStatefulWidget {
  const SmsOtpScreen({
    super.key,
    required this.telephone,
    this.pourInscription = true,
  });

  final String telephone;
  final bool pourInscription;

  @override
  ConsumerState<SmsOtpScreen> createState() => _SmsOtpScreenState();
}

class _SmsOtpScreenState extends ConsumerState<SmsOtpScreen> {
  final _codeCtrl = TextEditingController();
  final _focus = FocusNode();
  bool _envoiEnCours = true;
  bool _verifEnCours = false;
  bool _modeDemo = false;
  String? _info;
  String? _erreur;
  int _secondes = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _envoyer());
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    setState(() {
      _envoiEnCours = true;
      _erreur = null;
    });
    try {
      final res = await ref
          .read(smsOtpServiceProvider)
          .envoyerCode(widget.telephone);
      if (!mounted) return;
      setState(() {
        _envoiEnCours = false;
        _modeDemo = res.modeDemo;
        _info = res.message;
        _secondes = 60;
      });
      _demarrerCompteARebours();
      _focus.requestFocus();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _envoiEnCours = false;
        _erreur = e.message;
      });
    }
  }

  void _demarrerCompteARebours() {
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted || _secondes <= 0) return false;
      setState(() => _secondes--);
      return _secondes > 0;
    });
  }

  Future<void> _verifier() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _erreur = 'Entrez les 6 chiffres du code SMS');
      return;
    }

    setState(() {
      _verifEnCours = true;
      _erreur = null;
    });

    try {
      await ref.read(smsOtpServiceProvider).verifierCode(
            telephone: widget.telephone,
            code: code,
            forcerModeDemo: _modeDemo,
          );

      if (widget.pourInscription) {
        final ok =
            await ref.read(authProvider.notifier).finaliserInscriptionApresOtp();
        if (!mounted) return;
        if (!ok) {
          setState(() {
            _verifEnCours = false;
            _erreur = ref.read(authProvider).erreur ?? 'Inscription échouée';
          });
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Téléphone vérifié. Bienvenue sur FasoLiv !'),
            backgroundColor: AppColors.savane,
          ),
        );
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        await ref.read(authProvider.notifier).rafraichirProfil();
        if (!mounted) return;
        if (ref.read(authProvider).estConnecte) {
          Navigator.of(context).popUntil((r) => r.isFirst);
        } else {
          setState(() {
            _verifEnCours = false;
            _erreur = _modeDemo
                ? 'Mode démo : utilisez la connexion email, '
                    'ou configurez Phone Auth dans Supabase.'
                : 'Aucun compte trouvé pour ce numéro.';
          });
        }
      }
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifEnCours = false;
        _erreur = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifEnCours = false;
        _erreur = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FasoBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                  'Vérification SMS',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Entrez le code à 6 chiffres envoyé au\n${widget.telephone}',
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 28),
                if (_envoiEnCours)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  if (_info != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: (_modeDemo ? AppColors.ocre : AppColors.savane)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _info!,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  TextField(
                    controller: _codeCtrl,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 12,
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      labelText: 'Code SMS',
                    ),
                    onChanged: (v) {
                      if (v.length == 6) _verifier();
                    },
                    onSubmitted: (_) => _verifier(),
                  ),
                  if (_erreur != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _erreur!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _verifEnCours ? null : _verifier,
                      child: _verifEnCours
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Valider le code'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _secondes > 0 || _envoiEnCours ? null : _envoyer,
                      child: Text(
                        _secondes > 0
                            ? 'Renvoyer le code (${_secondes}s)'
                            : 'Renvoyer le code',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
