import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../models/livreur_proche.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/brand_widgets.dart';
import '../../widgets/livreur_card.dart';
import '../chat/chat_screen.dart';
import '../chat/conversations_screen.dart';

/// Accueil client : recherche de livreurs selon localisation + filtres.
class HomeDemandeurScreen extends ConsumerStatefulWidget {
  const HomeDemandeurScreen({super.key});

  @override
  ConsumerState<HomeDemandeurScreen> createState() =>
      _HomeDemandeurScreenState();
}

class _HomeDemandeurScreenState extends ConsumerState<HomeDemandeurScreen>
    with WidgetsBindingObserver {
  List<LivreurProche> _livreurs = [];
  bool _chargement = false;
  String? _erreur;
  double _rayonKm = 5;
  TypeVehicule? _filtreVehicule;
  Position? _position;
  bool _modeApercu = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _rechercher());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _rechercher();
    }
  }

  Future<void> _rechercher() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final location = ref.read(locationServiceProvider);
      final pos = await location.positionActuelle();
      _position = pos;

      final liste = await ref.read(livreurServiceProvider).getLivreursProches(
            latitude: pos.latitude,
            longitude: pos.longitude,
            rayonKm: _rayonKm,
            typeVehicule: _filtreVehicule,
          );

      if (!mounted) return;
      setState(() {
        _livreurs = liste;
        _chargement = false;
        _modeApercu = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Ne plus masquer l'erreur avec des fausses données
      setState(() {
        _livreurs = [];
        _chargement = false;
        _modeApercu = false;
        _erreur = e is AppException ? e.message : '$e';
      });
    }
  }

  Future<void> _ouvrirDetail(LivreurProche livreur) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LivreurSheet(
        livreur: livreur,
        onChoisir: () {
          Navigator.pop(ctx);
          // Après fermeture du sheet : enchaîne sans redemander « Choisir »
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _contacterLivreur(livreur);
          });
        },
      ),
    );
  }

  Future<void> _contacterLivreur(LivreurProche livreur) async {
    final auth = ref.read(authProvider);
    String? monId = auth.user?.id;

    // Invité : prénom seul — puis on continue immédiatement (pas de 2e choix)
    if (monId == null || auth.profil == null || auth.profil!.estLivreur) {
      final prenom = await _demanderPrenomClient();
      if (prenom == null) return;
      if (!mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final profil = await ref.read(authProvider.notifier).assurerCompteClient(
            prenom: prenom,
          );

      if (!mounted) return;
      Navigator.of(context).pop(); // loader compte

      if (profil == null) {
        final err = ref.read(authProvider).erreur;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err ?? 'Impossible de démarrer la discussion'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      monId = profil.id;
    }

    final userId = monId;
    if (userId == null) return;

    final pos = _position;
    if (pos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Position GPS indisponible')),
      );
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final course = await ref.read(courseServiceProvider).demarrerAvecLivreur(
            livreurId: livreur.livreurId,
            latitude: pos.latitude,
            longitude: pos.longitude,
          );

      if (!mounted) return;
      Navigator.of(context).pop(); // loader course

      // Popup automatique : Appeler + Messagerie (sans rechoisir)
      await _afficherContactEtMessagerie(
        livreur: livreur,
        courseId: course.id,
        monUserId: userId,
      );
    } on AppException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<String?> _demanderPrenomClient() async {
    final prenomCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Votre prénom'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pour discuter avec le livreur, indiquez simplement '
                'votre prénom. Aucun numéro n\'est requis.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: prenomCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Prénom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
                onFieldSubmitted: (_) {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx, true);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Continuer'),
          ),
        ],
      ),
    );

    final prenom = prenomCtrl.text.trim();
    prenomCtrl.dispose();
    if (ok != true || prenom.isEmpty) return null;
    return prenom;
  }

  Future<void> _afficherContactEtMessagerie({
    required LivreurProche livreur,
    required String courseId,
    required String monUserId,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              livreur.nomComplet,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Livreur choisi — appelez ou envoyez un message',
              style: GoogleFonts.dmSans(color: AppColors.muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5EE),
                child: Icon(Icons.phone, color: AppColors.savane),
              ),
              title: const Text('Téléphone'),
              subtitle: Text(
                livreur.telephone,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
              ),
              trailing: IconButton.filledTonal(
                onPressed: () => _appeler(livreur.telephone),
                icon: const Icon(Icons.call),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.savane.withValues(alpha: 0.14),
                  foregroundColor: AppColors.savaneFonce,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatScreen(
                        courseId: courseId,
                        titre: livreur.nomComplet,
                        monUserId: monUserId,
                        telephoneLivreur: livreur.telephone,
                        livreurId: livreur.livreurId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Ouvrir la messagerie'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Plus tard'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _appeler(String telephone) async {
    final digits = telephone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri(scheme: 'tel', path: '+$digits');
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Numéro : $telephone')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profil = ref.watch(authProvider).profil;
    final invite = ref.watch(modeInviteProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FasoBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (invite) {
                          ref.read(authProvider.notifier).quitterInvite();
                        } else {
                          ref.read(authProvider.notifier).deconnexion();
                        }
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: invite ? 'Retour' : 'Déconnexion',
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            invite
                                ? 'Mode invité'
                                : 'Bonjour ${profil?.prenom ?? ''}',
                            style: GoogleFonts.dmSans(
                              color: AppColors.muted,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Livreurs près de vous',
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!invite)
                      BrandIconButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        tooltip: 'Messagerie',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ConversationsScreen(),
                            ),
                          );
                        },
                      ),
                    if (!invite) const SizedBox(width: 4),
                    if (!invite)
                      BrandIconButton(
                        icon: Icons.logout_rounded,
                        tooltip: 'Déconnexion',
                        onPressed: () =>
                            ref.read(authProvider.notifier).deconnexion(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _FilterChip(
                      label: 'Tous',
                      selected: _filtreVehicule == null,
                      onTap: () {
                        setState(() => _filtreVehicule = null);
                        _rechercher();
                      },
                    ),
                    ...TypeVehicule.values.map(
                      (v) => _FilterChip(
                        label: v.label,
                        selected: _filtreVehicule == v,
                        onTap: () {
                          setState(() => _filtreVehicule = v);
                          _rechercher();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.radar, size: 18, color: AppColors.savane),
                    const SizedBox(width: 8),
                    Text(
                      'Rayon ${_rayonKm.toStringAsFixed(0)} km',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Expanded(
                      child: Slider(
                        value: _rayonKm,
                        min: 1,
                        max: 15,
                        divisions: 14,
                        activeColor: AppColors.savane,
                        onChanged: (v) => setState(() => _rayonKm = v),
                        onChangeEnd: (_) => _rechercher(),
                      ),
                    ),
                    IconButton(
                      onPressed: _chargement ? null : _rechercher,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              if (_erreur != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _erreur!,
                      style: const TextStyle(fontSize: 12, color: AppColors.danger),
                    ),
                  ),
                ),
              if (_modeApercu)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.ocre.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Aperçu UI — ${_erreur ?? 'données démo'}. '
                      'Configurez Supabase + GPS pour les vrais livreurs.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              Expanded(
                child: _chargement
                    ? const Center(child: CircularProgressIndicator())
                    : _livreurs.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_search_rounded,
                                    size: 64,
                                    color:
                                        AppColors.muted.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Aucun livreur en ligne\ndans ce rayon',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.outfit(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Sur l\'autre téléphone : switch « En ligne » '
                                    'actif + GPS autorisé.\n'
                                    'Ici : élargissez le rayon puis actualisez.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _rechercher,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Actualiser'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _rechercher,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              itemCount: _livreurs.length,
                              itemBuilder: (context, i) {
                                final l = _livreurs[i];
                                return LivreurCard(
                                  livreur: l,
                                  onChoisir: () => _ouvrirDetail(l),
                                );
                              },
                            ),
                          ),
              ),
              if (_position != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: Text(
                      'Votre position : ${_position!.latitude.toStringAsFixed(4)}, '
                      '${_position!.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.savane.withValues(alpha: 0.2),
        checkmarkColor: AppColors.savaneFonce,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _LivreurSheet extends StatelessWidget {
  const _LivreurSheet({
    required this.livreur,
    required this.onChoisir,
  });

  final LivreurProche livreur;
  final VoidCallback onChoisir;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 20),
          AvatarLivreur(
            initiales: livreur.initiales,
            radius: 40,
            verifie: livreur.estVerifie,
            enLigne: true,
          ).animate().scale(curve: Curves.easeOutBack),
          const SizedBox(height: 14),
          Text(
            livreur.nomComplet,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${livreur.typeVehicule?.label ?? 'Livreur'} · '
            '${livreur.distanceFormatee} · ★ ${livreur.noteMoyenne}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          if (livreur.estVerifie)
            const Chip(
              avatar: Icon(Icons.verified, size: 16, color: AppColors.savane),
              label: Text('Identité vérifiée (CNIB)'),
              backgroundColor: Color(0xFFE8F5EE),
            ),
          const SizedBox(height: 12),
          Text(
            'Après le choix : numéro visible + messagerie',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onChoisir,
              child: const Text('Choisir ce livreur'),
            ),
          ),
        ],
      ),
    );
  }
}
