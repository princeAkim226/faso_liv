import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'auth/welcome_screen.dart';
import 'demandeur/home_demandeur_screen.dart';
import 'livreur/home_livreur_screen.dart';

/// Route : invité / client connecté / livreur.
class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final invite = ref.watch(modeInviteProvider);

    if (auth.chargement) {
      return const Scaffold(
        backgroundColor: AppColors.ciel,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.savane),
              SizedBox(height: 16),
              Text('FasoLiv', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }

    // Session présente mais profil pas encore chargé
    if (auth.user != null && auth.profil == null) {
      if (auth.erreur != null) {
        // Session OK mais profil en erreur → retry / message
        return Scaffold(
          backgroundColor: AppColors.ciel,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'FasoLiv',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    auth.erreur!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        ref.read(authProvider.notifier).rafraichirProfil(),
                    child: const Text('Réessayer'),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(authProvider.notifier).deconnexion(),
                    child: const Text('Se déconnecter'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return const Scaffold(
        backgroundColor: AppColors.ciel,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.savane),
        ),
      );
    }

    // Livreurs authentifiés
    if (auth.estConnecte && auth.estLivreur) {
      return const HomeLivreurScreen();
    }

    // Client connecté (rare) OU invité sans compte
    if (invite || (auth.estConnecte && !auth.estLivreur)) {
      return const HomeDemandeurScreen();
    }

    return const WelcomeScreen();
  }
}
