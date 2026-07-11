import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/validation_otp_provider.dart';

/// Écran livreur : saisie du code OTP à 4 chiffres fourni par le destinataire.
class ValidationOtpScreen extends ConsumerStatefulWidget {
  const ValidationOtpScreen({
    super.key,
    required this.courseId,
  });

  final String courseId;

  @override
  ConsumerState<ValidationOtpScreen> createState() =>
      _ValidationOtpScreenState();
}

class _ValidationOtpScreenState extends ConsumerState<ValidationOtpScreen> {
  final _otpCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(validationOtpProvider.notifier)
          .chargerCourse(widget.courseId);
    });
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (!_formKey.currentState!.validate()) return;

    final ok = await ref
        .read(validationOtpProvider.notifier)
        .valider(_otpCtrl.text.trim());

    if (!mounted) return;

    final etat = ref.read(validationOtpProvider);
    final messenger = ScaffoldMessenger.of(context);

    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Livraison validée ! Commission débitée. Merci pour votre service.',
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(etat.erreur ?? 'Code incorrect'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(validationOtpProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Validation de livraison')),
      body: etat.chargement
          ? const Center(child: CircularProgressIndicator())
          : etat.erreur != null && etat.course == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(etat.erreur!, textAlign: TextAlign.center),
                  ),
                )
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 64,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Code secret du destinataire',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Demandez le code à 4 chiffres au destinataire '
                            'pour confirmer la remise du colis.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                          ),
                          if (etat.course != null) ...[
                            const SizedBox(height: 20),
                            _InfoCourse(
                              adresse: etat.course!.adresseLivraisonGps,
                              commission: etat.course!.commission,
                            ),
                          ],
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _otpCtrl,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              letterSpacing: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              counterText: '',
                              hintText: '••••',
                              labelText: 'Code OTP',
                            ),
                            validator: (v) {
                              if (v == null || !RegExp(r'^\d{4}$').hasMatch(v)) {
                                return 'Entrez exactement 4 chiffres';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) {
                              if (!etat.validationEnCours) _valider();
                            },
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed:
                                etat.validationEnCours ? null : _valider,
                            icon: etat.validationEnCours
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(
                              etat.validationEnCours
                                  ? 'Validation…'
                                  : 'Confirmer la livraison',
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _InfoCourse extends StatelessWidget {
  const _InfoCourse({
    required this.adresse,
    required this.commission,
  });

  final String adresse;
  final double commission;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  adresse,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                'Commission : ${commission.toStringAsFixed(0)} FCFA',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
