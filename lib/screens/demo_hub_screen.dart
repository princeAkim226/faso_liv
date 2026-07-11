import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../providers/portefeuille_provider.dart';
import '../screens/courses/validation_otp_screen.dart';
import '../screens/livreurs/selection_livreurs_screen.dart';
import '../screens/portefeuille/recharge_dialog.dart';

/// Hub de démonstration des modules clés FasoLiv.
///
/// Remplacez les IDs / coordonnées par des valeurs réelles après connexion.
class DemoHubScreen extends ConsumerStatefulWidget {
  const DemoHubScreen({super.key});

  @override
  ConsumerState<DemoHubScreen> createState() => _DemoHubScreenState();
}

class _DemoHubScreenState extends ConsumerState<DemoHubScreen> {
  // Valeurs de démo — à remplacer par la navigation réelle de l'app
  static const _courseIdDemo = '00000000-0000-0000-0000-000000000001';
  static const _latOuaga = 12.3714;
  static const _lngOuaga = -1.5197;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(portefeuilleProvider.notifier).chargerProfil();
    });
  }

  @override
  Widget build(BuildContext context) {
    final portefeuille = ref.watch(portefeuilleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FasoLiv'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Modules clés',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Livraison collaborative — Burkina Faso',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 20),
          _SoldeCarte(
            solde: portefeuille.solde,
            chargement: portefeuille.chargement,
            onRecharger: () => afficherDialogueRecharge(
              context: context,
              ref: ref,
              telephoneDefaut: portefeuille.profil?.telephone,
            ),
          ),
          const SizedBox(height: 24),
          _ModuleTile(
            icon: Icons.people_alt_outlined,
            title: 'Livreurs à proximité',
            subtitle: 'Sélection Peer-to-Peer (demandeur)',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SelectionLivreursScreen(
                    courseId: _courseIdDemo,
                    latitude: _latOuaga,
                    longitude: _lngOuaga,
                    rayonKm: 5,
                  ),
                ),
              );
            },
          ),
          _ModuleTile(
            icon: Icons.pin_outlined,
            title: 'Validation OTP',
            subtitle: 'Confirmer la livraison (livreur)',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ValidationOtpScreen(
                    courseId: _courseIdDemo,
                  ),
                ),
              );
            },
          ),
          _ModuleTile(
            icon: Icons.handshake_outlined,
            title: 'Accepter une course',
            subtitle: 'Contrôle solde vs commission (livreur)',
            onTap: () async {
              // Course factice pour illustrer le flux UI
              final courseDemo = Course(
                id: _courseIdDemo,
                demandeurId: 'demandeur-demo',
                statut: StatutCourse.propose,
                prixTotal: 2500,
                commission: 250,
                adresseRamassageGps: '12.3714,-1.5197',
                adresseLivraisonGps: '12.3650,-1.5300',
                codeOtpValidation: '1234',
                createdAt: DateTime.now(),
              );
              final result = await tenterAccepterCourse(
                context: context,
                ref: ref,
                course: courseDemo,
                telephoneDefaut: portefeuille.profil?.telephone,
              );
              if (!context.mounted) return;
              if (result != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Course acceptée'),
                    backgroundColor: Colors.green.shade700,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SoldeCarte extends StatelessWidget {
  const _SoldeCarte({
    required this.solde,
    required this.chargement,
    required this.onRecharger,
  });

  final double solde;
  final bool chargement;
  final VoidCallback onRecharger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Portefeuille virtuel',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          chargement
              ? const SizedBox(
                  height: 32,
                  width: 32,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : Text(
                  '${solde.toStringAsFixed(0)} FCFA',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRecharger,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Recharger'),
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
