import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/brand_widgets.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Hub livreur : connexion et inscription classiques.
/// La vérification SMS intervient après le formulaire d'inscription.
class EspaceLivreurScreen extends StatelessWidget {
  const EspaceLivreurScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FasoBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(height: 8),
                const BrandMark(compact: true)
                    .animate()
                    .fadeIn()
                    .slideX(begin: -0.05),
                const Spacer(),
                Text(
                  'Espace livreur',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.encre,
                  ),
                ).animate().fadeIn(delay: 80.ms),
                const SizedBox(height: 10),
                Text(
                  'Connectez-vous à votre compte ou créez-en un '
                  'pour recevoir des courses près de vous.',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    height: 1.45,
                    color: AppColors.muted,
                  ),
                ).animate().fadeIn(delay: 120.ms),
                const SizedBox(height: 32),
                _ActionCard(
                  icon: Icons.login_rounded,
                  title: 'Se connecter',
                  subtitle: 'J\'ai déjà un compte',
                  color: AppColors.savane,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                ).animate().fadeIn(delay: 180.ms).slideY(begin: 0.08),
                const SizedBox(height: 14),
                _ActionCard(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'Créer un compte',
                  subtitle: 'Nouveau livreur',
                  color: AppColors.terre,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RegisterScreen(),
                      ),
                    );
                  },
                ).animate().fadeIn(delay: 240.ms).slideY(begin: 0.08),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
