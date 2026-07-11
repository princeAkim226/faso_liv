import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/livreur_proche.dart';
import '../../providers/livreurs_provider.dart';

/// Écran demandeur : liste des livreurs à proximité + sélection P2P.
class SelectionLivreursScreen extends ConsumerStatefulWidget {
  const SelectionLivreursScreen({
    super.key,
    required this.courseId,
    required this.latitude,
    required this.longitude,
    this.rayonKm = 5.0,
  });

  final String courseId;
  final double latitude;
  final double longitude;
  final double rayonKm;

  @override
  ConsumerState<SelectionLivreursScreen> createState() =>
      _SelectionLivreursScreenState();
}

class _SelectionLivreursScreenState
    extends ConsumerState<SelectionLivreursScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(livreursProchesProvider.notifier).charger(
            RechercheLivreursParams(
              latitude: widget.latitude,
              longitude: widget.longitude,
              rayonKm: widget.rayonKm,
              courseId: widget.courseId,
            ),
          );
    });
  }

  Future<void> _choisir(LivreurProche livreur) async {
    final confirmer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer le livreur'),
        content: Text(
          'Proposer la course à ${livreur.nomComplet} '
          '(${livreur.distanceFormatee}) ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );

    if (confirmer != true || !mounted) return;

    final ok = await ref.read(livreursProchesProvider.notifier).choisirLivreur(
          courseId: widget.courseId,
          livreur: livreur,
        );

    if (!mounted) return;

    final etat = ref.read(livreursProchesProvider);
    final messenger = ScaffoldMessenger.of(context);

    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(etat.messageSucces ?? 'Livreur sélectionné'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(etat.erreur ?? 'Échec de la sélection'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(livreursProchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Livreurs à proximité'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: etat.chargement
                ? null
                : () => ref.read(livreursProchesProvider.notifier).charger(
                      RechercheLivreursParams(
                        latitude: widget.latitude,
                        longitude: widget.longitude,
                        rayonKm: widget.rayonKm,
                        courseId: widget.courseId,
                      ),
                    ),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(etat),
    );
  }

  Widget _buildBody(LivreursProchesState etat) {
    if (etat.chargement && etat.livreurs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Recherche des livreurs…'),
          ],
        ),
      );
    }

    if (etat.erreur != null && etat.livreurs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(etat.erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(livreursProchesProvider.notifier).charger(
                          RechercheLivreursParams(
                            latitude: widget.latitude,
                            longitude: widget.longitude,
                            rayonKm: widget.rayonKm,
                            courseId: widget.courseId,
                          ),
                        ),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (etat.livreurs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delivery_dining, size: 56, color: Colors.grey.shade500),
              const SizedBox(height: 12),
              Text(
                'Aucun livreur disponible dans un rayon de '
                '${widget.rayonKm.toStringAsFixed(0)} km.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Élargissez le rayon ou réessayez dans quelques minutes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => ref.read(livreursProchesProvider.notifier).charger(
                RechercheLivreursParams(
                  latitude: widget.latitude,
                  longitude: widget.longitude,
                  rayonKm: widget.rayonKm,
                  courseId: widget.courseId,
                ),
              ),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: etat.livreurs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final livreur = etat.livreurs[index];
              return _CarteLivreur(
                livreur: livreur,
                desactive: etat.selectionEnCours,
                onChoisir: () => _choisir(livreur),
              );
            },
          ),
        ),
        if (etat.selectionEnCours)
          const ColoredBox(
            color: Color(0x33000000),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _CarteLivreur extends StatelessWidget {
  const _CarteLivreur({
    required this.livreur,
    required this.onChoisir,
    this.desactive = false,
  });

  final LivreurProche livreur;
  final VoidCallback onChoisir;
  final bool desactive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                livreur.prenom.isNotEmpty
                    ? livreur.prenom[0].toUpperCase()
                    : '?',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    livreur.nomComplet,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.near_me,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        livreur.distanceFormatee,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.phone,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          livreur.telephone,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: desactive ? null : onChoisir,
              child: const Text('Choisir'),
            ),
          ],
        ),
      ),
    );
  }
}
