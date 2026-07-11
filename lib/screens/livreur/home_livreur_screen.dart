import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../core/utils/ville_burkina.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../screens/abonnement/abonnement_dialog.dart';
import '../../services/avis_service.dart';
import '../../services/cnib_storage_service.dart';
import '../../widgets/brand_widgets.dart';
import '../../widgets/cnib_upload_tile.dart';
import '../chat/conversations_screen.dart';
import 'avis_livreur_screen.dart';

/// Accueil livreur : profil + activation localisation temps réel.
class HomeLivreurScreen extends ConsumerStatefulWidget {
  const HomeLivreurScreen({super.key});

  @override
  ConsumerState<HomeLivreurScreen> createState() => _HomeLivreurScreenState();
}

class _HomeLivreurScreenState extends ConsumerState<HomeLivreurScreen> {
  bool _enLigne = false;
  bool _chargementGps = false;
  Position? _dernierePosition;
  String? _statusGps;
  String? _villeDetectee;
  XFile? _recto;
  XFile? _verso;
  bool _uploadCnib = false;
  int _avisNonLus = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Rafraîchissement silencieux (ne pas remonter le splash AppGate)
      ref.read(authProvider.notifier).rafraichirProfil(silencieux: true);
      _detecterVille();
      _chargerAvisNonLus();
      // Écoute Realtime + enregistrement token FCM (notif hors-app)
      ref.read(pushNotificationServiceProvider).activerPourLivreur();
    });
  }

  Future<void> _chargerAvisNonLus() async {
    final n = await AvisService().nombreNonLus();
    if (!mounted) return;
    setState(() => _avisNonLus = n);
  }

  Future<void> _ouvrirAvis() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AvisLivreurScreen()),
    );
    if (!mounted) return;
    await ref.read(authProvider.notifier).rafraichirProfil(silencieux: true);
    await _chargerAvisNonLus();
  }

  Future<void> _detecterVille() async {
    try {
      final location = ref.read(locationServiceProvider);
      final pos = await location.positionActuelle();
      final ville = VilleBurkina.depuisCoordonnees(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _dernierePosition = pos;
        _villeDetectee = ville;
      });
      await ref.read(authProvider.notifier).synchroniserVilleDepuisGps(
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
    } catch (_) {
      // Permission refusée : on garde la ville du profil
    }
  }

  Future<void> _pickCnib(FaceCnib face) async {
    final source = await choisirSourcePhoto(context);
    if (source == null || !mounted) return;
    try {
      final file = await CnibStorageService().choisirImage(source: source);
      if (file == null || !mounted) return;
      setState(() {
        if (face == FaceCnib.recto) {
          _recto = file;
        } else {
          _verso = file;
        }
      });
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _enregistrerCnib() async {
    if (_recto == null || _verso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoutez le recto et le verso'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => _uploadCnib = true);
    final ok = await ref.read(authProvider.notifier).completerCnib(
          recto: _recto!,
          verso: _verso!,
        );
    if (!mounted) return;
    setState(() => _uploadCnib = false);
    if (ok) {
      setState(() {
        _recto = null;
        _verso = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CNIB enregistrée — vous pouvez passer en ligne'),
          backgroundColor: AppColors.savane,
        ),
      );
    } else {
      final err = ref.read(authProvider).erreur;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err ?? 'Échec enregistrement CNIB'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _toggleLocalisation(bool value) async {
    final profil = ref.read(authProvider).profil;
    if (value && profil?.cnibComplete != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Téléversez d\'abord le recto et le verso de votre CNIB '
            '(section ci-dessous).',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    if (value && profil?.abonnementActif != true) {
      final ok = await afficherDialogueAbonnement(
        context: context,
        ref: ref,
        telephoneDefaut: profil?.telephone,
      );
      if (!ok || !mounted) return;
      // Après paiement, l'utilisateur peut réactiver En ligne
      return;
    }

    final location = ref.read(locationServiceProvider);
    setState(() => _chargementGps = true);

    try {
      if (value) {
        await location.demarrerSuivi(
          onPosition: (pos) {
            if (!mounted) return;
            final ville =
                VilleBurkina.depuisCoordonnees(pos.latitude, pos.longitude);
            setState(() {
              _dernierePosition = pos;
              _villeDetectee = ville;
              _statusGps = 'Position diffusée';
            });
          },
          onError: (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$e'),
                backgroundColor: AppColors.danger,
              ),
            );
          },
        );
        setState(() {
          _enLigne = true;
          _statusGps = 'Vous êtes visible pour les clients';
        });
        await ref.read(authProvider.notifier).rafraichirProfil(silencieux: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'En ligne — visible pour les clients près de '
                '${_villeDetectee ?? 'vous'}',
              ),
              backgroundColor: AppColors.savane,
            ),
          );
        }
      } else {
        await location.arreterSuivi();
        setState(() {
          _enLigne = false;
          _statusGps = 'Hors ligne';
        });
        await ref.read(authProvider.notifier).rafraichirProfil();
      }
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
      setState(() => _enLigne = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
      setState(() => _enLigne = false);
    } finally {
      if (mounted) setState(() => _chargementGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profil = ref.watch(authProvider).profil;
    final enLigne = _enLigne || (profil?.localisationActive ?? false);
    final villeAffichee = _villeDetectee ?? profil?.ville ?? '…';
    final cnibOk = profil?.cnibComplete == true;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FasoBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const BrandMark(compact: true),
                  const Spacer(),
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
                  const SizedBox(width: 8),
                  BrandIconButton(
                    icon: Icons.logout_rounded,
                    tooltip: 'Déconnexion',
                    onPressed: () =>
                        ref.read(authProvider.notifier).deconnexion(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: enLigne
                        ? [AppColors.savane, AppColors.savaneFonce]
                        : [const Color(0xFF3D4A43), const Color(0xFF2A332E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (enLigne ? AppColors.savane : Colors.black)
                          .withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    AvatarLivreur(
                      initiales: profil?.initiales ?? '?',
                      radius: 36,
                      verifie: profil?.estVerifie ?? false,
                      enLigne: enLigne,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      profil?.nomComplet ?? 'Livreur',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        profil?.typeVehicule?.label,
                        villeAffichee,
                        if (cnibOk) 'CNIB vérifiée',
                      ].whereType<String>().join(' · '),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            enLigne
                                ? Icons.radar_rounded
                                : Icons.location_off_rounded,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  enLigne ? 'En ligne' : 'Hors ligne',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  _statusGps ??
                                      (enLigne
                                          ? 'Visible sur la carte clients'
                                          : 'Activez pour recevoir des courses'),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_chargementGps)
                            const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          else
                            Switch.adaptive(
                              value: enLigne,
                              activeColor: Colors.white,
                              activeTrackColor: AppColors.ocre,
                              onChanged: _toggleLocalisation,
                            ),
                        ],
                      ),
                    ),
                    if (_dernierePosition != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'GPS ${_dernierePosition!.latitude.toStringAsFixed(5)}, '
                        '${_dernierePosition!.longitude.toStringAsFixed(5)}'
                        '${_villeDetectee != null ? ' · $_villeDetectee' : ''}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ).animate().fadeIn().slideY(begin: 0.08),
              const SizedBox(height: 24),
              Text(
                'Votre fiche',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _InfoTile(
                icon: Icons.phone_outlined,
                label: 'Téléphone',
                value: profil?.telephone ?? '—',
              ),
              _InfoTile(
                icon: Icons.workspace_premium_outlined,
                label: 'Abonnement (2 000 F/mois)',
                value: profil?.abonnementActif == true
                    ? 'Actif jusqu\'au ${_fmtDate(profil!.abonnementExpireAt!)}'
                    : 'Inactif — requis pour En ligne',
                onTap: () => afficherDialogueAbonnement(
                  context: context,
                  ref: ref,
                  telephoneDefaut: profil?.telephone,
                ),
              ),
              _InfoTile(
                icon: Icons.location_city_outlined,
                label: 'Ville (auto GPS)',
                value: villeAffichee,
              ),
              _InfoTile(
                icon: Icons.sms_outlined,
                label: 'Vérification SMS',
                value: profil?.telephoneVerifie == true
                    ? 'Numéro vérifié'
                    : 'Non vérifié',
              ),
              _InfoTile(
                icon: Icons.badge_outlined,
                label: 'Pièce d\'identité',
                value: cnibOk
                    ? 'Recto et verso téléversés'
                    : 'Photos CNIB manquantes',
              ),
              if (!cnibOk) ...[
                const SizedBox(height: 8),
                Text(
                  'Les photos prises à l\'inscription n\'ont pas été '
                  'liées au profil (erreur serveur). Re-téléversez-les :',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: AppColors.muted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CnibUploadTile(
                      label: 'Recto',
                      hint: 'Face avant',
                      fichier: _recto,
                      erreur: false,
                      onChoisir: () => _pickCnib(FaceCnib.recto),
                      onEffacer: () => setState(() => _recto = null),
                    ),
                    const SizedBox(width: 12),
                    CnibUploadTile(
                      label: 'Verso',
                      hint: 'Face arrière',
                      fichier: _verso,
                      erreur: false,
                      onChoisir: () => _pickCnib(FaceCnib.verso),
                      onEffacer: () => setState(() => _verso = null),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _uploadCnib ? null : _enregistrerCnib,
                    child: _uploadCnib
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Enregistrer ma CNIB'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (_avisNonLus > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: AppColors.ocre.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _ouvrirAvis,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: AppColors.ocre),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _avisNonLus == 1
                                    ? '1 nouvel avis client — appuyez pour voir'
                                    : '$_avisNonLus nouveaux avis — appuyez pour voir',
                                style: GoogleFonts.dmSans(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              _InfoTile(
                icon: Icons.star_outline,
                label: 'Note',
                value: _avisNonLus > 0
                    ? '${profil?.noteMoyenne.toStringAsFixed(1) ?? '5.0'} / 5 · $_avisNonLus nouveau${_avisNonLus > 1 ? 'x' : ''}'
                    : '${profil?.noteMoyenne.toStringAsFixed(1) ?? '5.0'} / 5',
                onTap: _ouvrirAvis,
              ),
              _InfoTile(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Portefeuille',
                value:
                    '${profil?.soldePortefeuille.toStringAsFixed(0) ?? '0'} FCFA',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: Colors.black.withValues(alpha: 0.05)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.chat_rounded, color: AppColors.terre),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'La messagerie avec le client s\'ouvre automatiquement '
                        'dès que la course est payée.',
                        style:
                            TextStyle(color: AppColors.muted, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: AppColors.savane),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                      Text(
                        value,
                        style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  final local = d.toLocal();
  final jj = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  return '$jj/$mm/${local.year}';
}
