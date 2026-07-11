import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_theme.dart';

/// Fond dégradé signature FasoLiv.
class FasoBackground extends StatelessWidget {
  const FasoBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFFBF5),
            Color(0xFFF3F0E8),
            Color(0xFFE8F2EC),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _Blob(
              size: 220,
              color: AppColors.ocre.withValues(alpha: 0.18),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -70,
            child: _Blob(
              size: 180,
              color: AppColors.savane.withValues(alpha: 0.12),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Logo texte de marque.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.compact = false,
    this.light = false,
  });

  final bool compact;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = light ? Colors.white : AppColors.savaneFonce;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 36 : 48,
          height: compact ? 36 : 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.savane, AppColors.savaneFonce],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(compact ? 12 : 16),
            boxShadow: [
              BoxShadow(
                color: AppColors.savane.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.delivery_dining_rounded,
            color: Colors.white,
            size: compact ? 20 : 26,
          ),
        ),
        SizedBox(width: compact ? 10 : 14),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Faso',
                style: GoogleFonts.outfit(
                  fontSize: compact ? 22 : 28,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              TextSpan(
                text: 'Liv',
                style: GoogleFonts.outfit(
                  fontSize: compact ? 22 : 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.terre,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bouton d'action visible sur fond clair (évite les ronds blancs invisibles).
class BrandIconButton extends StatelessWidget {
  const BrandIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.savane.withValues(alpha: 0.14),
        foregroundColor: AppColors.savaneFonce,
      ),
    );
  }
}

/// Avatar avec initiales + badge vérifié.
class AvatarLivreur extends StatelessWidget {
  const AvatarLivreur({
    super.key,
    required this.initiales,
    this.radius = 28,
    this.verifie = false,
    this.enLigne = false,
  });

  final String initiales;
  final double radius;
  final bool verifie;
  final bool enLigne;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.savane.withValues(alpha: 0.15),
          child: Text(
            initiales,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w700,
              fontSize: radius * 0.7,
              color: AppColors.savaneFonce,
            ),
          ),
        ),
        if (enLigne)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        if (verifie)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified,
                size: 16,
                color: AppColors.savane,
              ),
            ),
          ),
      ],
    );
  }
}
