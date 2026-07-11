import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_theme.dart';
import '../models/livreur_proche.dart';
import '../models/profile.dart';
import 'brand_widgets.dart';

IconData iconVehicule(TypeVehicule? type) {
  switch (type) {
    case TypeVehicule.moto:
      return Icons.two_wheeler;
    case TypeVehicule.tricycle:
      return Icons.airport_shuttle;
    case TypeVehicule.voiture:
      return Icons.directions_car;
    case TypeVehicule.velo:
      return Icons.pedal_bike;
    case null:
      return Icons.local_shipping_outlined;
  }
}

/// Carte profil livreur pour la liste de recherche.
class LivreurCard extends StatelessWidget {
  const LivreurCard({
    super.key,
    required this.livreur,
    required this.onChoisir,
    this.onMessage,
  });

  final LivreurProche livreur;
  final VoidCallback onChoisir;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: AppColors.savaneFonce.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              AvatarLivreur(
                initiales: livreur.initiales,
                verifie: livreur.estVerifie,
                enLigne: livreur.localisationActive,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      livreur.nomComplet,
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          iconVehicule(livreur.typeVehicule),
                          size: 15,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          livreur.typeVehicule?.label ?? 'Transport',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.star_rounded,
                            size: 15, color: AppColors.ocre),
                        const SizedBox(width: 2),
                        Text(
                          livreur.noteMoyenne.toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.savane.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.near_me_rounded,
                        size: 14, color: AppColors.savane),
                    const SizedBox(width: 4),
                    Text(
                      livreur.distanceFormatee,
                      style: GoogleFonts.dmSans(
                        color: AppColors.savaneFonce,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (onMessage != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onMessage,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Message'),
                  ),
                ),
              if (onMessage != null) const SizedBox(width: 10),
              Expanded(
                flex: onMessage != null ? 1 : 1,
                child: FilledButton(
                  onPressed: onChoisir,
                  child: const Text('Choisir'),
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }
}
