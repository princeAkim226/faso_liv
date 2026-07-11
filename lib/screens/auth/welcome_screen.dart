import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/brand_widgets.dart';
import 'espace_livreur_screen.dart';

/// Accueil : client sans compte, ou espace livreur.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: FasoBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 28),
                const BrandMark().animate().fadeIn().slideX(begin: -0.1),
                const Spacer(),
                Text(
                  'Des livreurs\nprès de vous.',
                  style: GoogleFonts.outfit(
                    fontSize: 40,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: AppColors.encre,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 120.ms)
                    .slideY(begin: 0.15, curve: Curves.easeOutCubic),
                const SizedBox(height: 16),
                Text(
                  'Un colis à faire partir ? Trouvez un livreur '
                  'disponible autour de vous, en quelques secondes.',
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    height: 1.45,
                    color: AppColors.muted,
                  ),
                ).animate().fadeIn(delay: 220.ms),
                const SizedBox(height: 36),
                _FeatureChip(
                  icon: Icons.verified_user_outlined,
                  label: 'Livreur vérifié',
                ).animate().fadeIn(delay: 280.ms).slideX(begin: -0.05),
                const SizedBox(height: 10),
                _FeatureChip(
                  icon: Icons.my_location_rounded,
                  label: 'Localisation temps réel',
                ).animate().fadeIn(delay: 340.ms).slideX(begin: -0.05),
                const SizedBox(height: 10),
                _FeatureChip(
                  icon: Icons.handshake_outlined,
                  label: 'Vous choisissez votre livreur',
                ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.05),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await ref.read(authProvider.notifier).entrerEnInvite();
                    },
                    child: const Text('Trouver un livreur'),
                  ),
                ).animate().fadeIn(delay: 450.ms).slideY(begin: 0.2),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const EspaceLivreurScreen(),
                        ),
                      );
                    },
                    child: const Text('Espace livreur'),
                  ),
                ).animate().fadeIn(delay: 500.ms),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.savane, size: 20),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w600,
              color: AppColors.encre,
            ),
          ),
        ],
      ),
    );
  }
}
