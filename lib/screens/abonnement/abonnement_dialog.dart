import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../providers/auth_provider.dart';
import '../../services/abonnement_service.dart';
import '../../services/mobile_money_service.dart';

/// Dialogue d'abonnement mensuel livreur (2 000 FCFA).
Future<bool> afficherDialogueAbonnement({
  required BuildContext context,
  required WidgetRef ref,
  String? telephoneDefaut,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AbonnementSheet(telephoneDefaut: telephoneDefaut),
  );
  return result == true;
}

class _AbonnementSheet extends ConsumerStatefulWidget {
  const _AbonnementSheet({this.telephoneDefaut});

  final String? telephoneDefaut;

  @override
  ConsumerState<_AbonnementSheet> createState() => _AbonnementSheetState();
}

class _AbonnementSheetState extends ConsumerState<_AbonnementSheet> {
  late final TextEditingController _tel;
  OperateurMobileMoney _operateur = OperateurMobileMoney.orangeMoney;
  bool _chargement = false;

  @override
  void initState() {
    super.initState();
    _tel = TextEditingController(
      text: widget.telephoneDefaut ?? '+226 ',
    );
  }

  @override
  void dispose() {
    _tel.dispose();
    super.dispose();
  }

  Future<void> _payer() async {
    setState(() => _chargement = true);
    try {
      final profil = await AbonnementService().souscrire(
        telephone: _tel.text.trim(),
        operateur: _operateur,
      );
      ref.read(authProvider.notifier).appliquerProfil(profil);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abonnement activé pour 1 mois — vous pouvez passer en ligne'),
          backgroundColor: AppColors.savane,
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Abonnement livreur',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pour activer votre compte et apparaître auprès des clients, '
              'souscrivez à l\'abonnement mensuel.',
              style: GoogleFonts.dmSans(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.savane.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.savane.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_rounded,
                      color: AppColors.savane, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${AbonnementService.prixMensuelFcfa.toStringAsFixed(0)} FCFA',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.savane,
                          ),
                        ),
                        Text(
                          'par mois · renouvelable',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tel,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numéro Mobile Money',
                prefixIcon: Icon(Icons.phone_android_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OperateurMobileMoney>(
              value: _operateur,
              decoration: const InputDecoration(labelText: 'Opérateur'),
              items: OperateurMobileMoney.values
                  .map(
                    (o) => DropdownMenuItem(value: o, child: Text(o.label)),
                  )
                  .toList(),
              onChanged: _chargement
                  ? null
                  : (v) {
                      if (v != null) setState(() => _operateur = v);
                    },
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _chargement ? null : _payer,
                child: _chargement
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Payer ${AbonnementService.prixMensuelFcfa.toStringAsFixed(0)} FCFA',
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _chargement ? null : () => Navigator.pop(context),
                child: const Text('Plus tard'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
