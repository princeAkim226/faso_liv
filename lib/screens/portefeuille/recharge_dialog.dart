import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_exceptions.dart';
import '../../models/course.dart';
import '../../providers/portefeuille_provider.dart';
import '../../services/mobile_money_service.dart';

/// Dialogue invitant le livreur à recharger si solde < commission.
Future<void> afficherDialogueSoldeInsuffisant({
  required BuildContext context,
  required WidgetRef ref,
  required SoldeInsuffisantException exception,
  String? telephoneDefaut,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        icon: Icon(
          Icons.account_balance_wallet_outlined,
          color: Theme.of(ctx).colorScheme.error,
          size: 40,
        ),
        title: const Text('Solde insuffisant'),
        content: Text(
          '${exception.message}\n\n'
          'Rechargez votre portefeuille via Orange Money, Moov Money ou Wave '
          'pour accepter cette course.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              afficherDialogueRecharge(
                context: context,
                ref: ref,
                montantSuggere: exception.commission,
                telephoneDefaut: telephoneDefaut,
              );
            },
            child: const Text('Recharger'),
          ),
        ],
      );
    },
  );
}

/// Formulaire de recharge Mobile Money.
Future<void> afficherDialogueRecharge({
  required BuildContext context,
  required WidgetRef ref,
  double? montantSuggere,
  String? telephoneDefaut,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _DialogueRecharge(
      montantSuggere: montantSuggere,
      telephoneDefaut: telephoneDefaut,
    ),
  );
}

class _DialogueRecharge extends ConsumerStatefulWidget {
  const _DialogueRecharge({
    this.montantSuggere,
    this.telephoneDefaut,
  });

  final double? montantSuggere;
  final String? telephoneDefaut;

  @override
  ConsumerState<_DialogueRecharge> createState() => _DialogueRechargeState();
}

class _DialogueRechargeState extends ConsumerState<_DialogueRecharge> {
  late final TextEditingController _montantCtrl;
  late final TextEditingController _telCtrl;
  OperateurMobileMoney _operateur = OperateurMobileMoney.orangeMoney;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _montantCtrl = TextEditingController(
      text: widget.montantSuggere?.toStringAsFixed(0) ?? '',
    );
    _telCtrl = TextEditingController(text: widget.telephoneDefaut ?? '+226');
  }

  @override
  void dispose() {
    _montantCtrl.dispose();
    _telCtrl.dispose();
    super.dispose();
  }

  Future<void> _soumettre() async {
    if (!_formKey.currentState!.validate()) return;

    final montant = double.parse(_montantCtrl.text.trim());
    final ok = await ref.read(portefeuilleProvider.notifier).recharger(
          montant: montant,
          telephone: _telCtrl.text.trim(),
          operateur: _operateur,
        );

    if (!mounted) return;

    final etat = ref.read(portefeuilleProvider);
    final messenger = ScaffoldMessenger.of(context);

    if (ok) {
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(etat.messageSucces ?? 'Recharge initiée'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(etat.erreur ?? 'Échec de la recharge'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chargement = ref.watch(portefeuilleProvider).chargement;

    return AlertDialog(
      title: const Text('Recharger le portefeuille'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _montantCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Montant (FCFA)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n < 100) {
                    return 'Minimum 100 FCFA';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Numéro Mobile Money',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 8) {
                    return 'Numéro invalide';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<OperateurMobileMoney>(
                value: _operateur,
                decoration: const InputDecoration(
                  labelText: 'Opérateur',
                  prefixIcon: Icon(Icons.cell_tower),
                ),
                items: OperateurMobileMoney.values
                    .map(
                      (o) => DropdownMenuItem(
                        value: o,
                        child: Text(o.label),
                      ),
                    )
                    .toList(),
                onChanged: chargement
                    ? null
                    : (v) {
                        if (v != null) setState(() => _operateur = v);
                      },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: chargement ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: chargement ? null : _soumettre,
          child: chargement
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Payer'),
        ),
      ],
    );
  }
}

/// Helper : tente d'accepter une course et ouvre le dialogue si solde insuffisant.
Future<Course?> tenterAccepterCourse({
  required BuildContext context,
  required WidgetRef ref,
  required Course course,
  String? telephoneDefaut,
}) async {
  try {
    return await ref.read(portefeuilleProvider.notifier).accepterCourse(course);
  } on SoldeInsuffisantException catch (e) {
    if (context.mounted) {
      await afficherDialogueSoldeInsuffisant(
        context: context,
        ref: ref,
        exception: e,
        telephoneDefaut: telephoneDefaut,
      );
    }
    return null;
  }
}
