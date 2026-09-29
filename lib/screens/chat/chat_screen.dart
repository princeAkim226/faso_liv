import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../core/utils/maps_navigation.dart';
import '../../models/course.dart';
import '../../models/message_chat.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../courses/validation_otp_screen.dart';
import '../livreur/itineraire_map_screen.dart';

/// Chat client ↔ livreur — ouvert dès que le livreur est choisi.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.courseId,
    required this.titre,
    required this.monUserId,
    this.modeDemo = false,
    this.telephoneLivreur,
    this.livreurId,
  });

  final String courseId;
  final String titre;
  final String monUserId;
  final bool modeDemo;
  final String? telephoneLivreur;
  final String? livreurId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  final _commentaireNote = TextEditingController();
  final _scroll = ScrollController();
  final List<MessageChat> _messages = [];
  final Set<String> _idsConnus = {};
  bool _chargement = true;
  bool _verrouille = false;
  String? _erreur;
  RealtimeChannel? _channel;
  Timer? _poll;
  int _noteChoisie = 0;
  bool _noteEnvoyee = false;
  bool _envoiNote = false;
  double? _destLat;
  double? _destLng;
  String? _courseLivreurId;
  StatutCourse? _statutCourse;
  bool _actionStatut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    if (widget.modeDemo) {
      setState(() {
        _messages.addAll([
          MessageChat(
            id: '1',
            courseId: widget.courseId,
            senderId: 'livreur',
            contenu: 'Bonjour ! Je suis en route vers le point de ramassage.',
            createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
          MessageChat(
            id: '2',
            courseId: widget.courseId,
            senderId: widget.monUserId,
            contenu: 'Parfait, le colis est prêt. Merci !',
            createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
          ),
        ]);
        _chargement = false;
      });
      return;
    }

    try {
      // Position client + id livreur + statut (carte / actions)
      try {
        final course =
            await ref.read(courseServiceProvider).getCourse(widget.courseId);
        final point = course.pointRamassage ?? course.pointLivraison;
        if (mounted) {
          setState(() {
            if (point != null) {
              _destLat = point.lat;
              _destLng = point.lng;
            }
            _courseLivreurId = course.livreurId ?? widget.livreurId;
            _statutCourse = course.statut;
          });
        }
      } catch (_) {}

      final msgs = await ref
          .read(messagingServiceProvider)
          .chargerMessages(widget.courseId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        _idsConnus
          ..clear()
          ..addAll(msgs.map((m) => m.id));
        _chargement = false;
      });

      _channel = ref.read(messagingServiceProvider).souscrire(
            courseId: widget.courseId,
            onInsert: (m) {
              if (!mounted) return;
              if (!_idsConnus.add(m.id)) return;
              setState(() => _messages.add(m));
              _scrollBas();
            },
          );

      // Secours si Realtime n'est pas encore activé sur le projet
      _poll = ref.read(messagingServiceProvider).demarrerPolling(
            courseId: widget.courseId,
            idsConnus: _idsConnus,
            onNouveau: (m) {
              if (!mounted) return;
              setState(() {
                if (!_messages.any((e) => e.id == m.id)) {
                  _messages.add(m);
                }
              });
              _scrollBas();
            },
          );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _verrouille = e.code == 'CHAT_VERROUILLE';
        _erreur = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = '$e';
      });
    }
  }

  void _scrollBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _envoyer() async {
    final texte = _ctrl.text.trim();
    if (texte.isEmpty) return;

    if (widget.modeDemo) {
      setState(() {
        _messages.add(
          MessageChat(
            id: DateTime.now().toIso8601String(),
            courseId: widget.courseId,
            senderId: widget.monUserId,
            contenu: texte,
            createdAt: DateTime.now(),
          ),
        );
      });
      _ctrl.clear();
      _scrollBas();
      return;
    }

    try {
      final msg = await ref.read(messagingServiceProvider).envoyer(
            courseId: widget.courseId,
            contenu: texte,
          );
      _ctrl.clear();
      if (!mounted) return;
      if (_idsConnus.add(msg.id)) {
        setState(() => _messages.add(msg));
      }
      _scrollBas();
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _appeler() async {
    final tel = widget.telephoneLivreur;
    if (tel == null || tel.isEmpty) return;
    final digits = tel.replaceAll(RegExp(r'\D'), '');
    final uri = Uri(scheme: 'tel', path: '+$digits');
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Numéro : $tel')),
      );
    }
  }

  Future<void> _ouvrirCarteDansApp() async {
    final lat = _destLat;
    final lng = _destLng;
    if (lat == null || lng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Position GPS indisponible pour cette course'),
        ),
      );
      return;
    }
    final estLivreur = ref.read(authProvider).profil?.estLivreur == true;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItineraireMapScreen(
          courseId: widget.courseId,
          pointClientLat: lat,
          pointClientLng: lng,
          titre: widget.titre,
          modeLivreur: estLivreur,
          livreurId: _courseLivreurId ?? widget.livreurId,
        ),
      ),
    );
  }

  Future<void> _ouvrirItineraire() async {
    final lat = _destLat;
    final lng = _destLng;
    if (lat == null || lng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Position du client indisponible pour cette course'),
        ),
      );
      return;
    }
    try {
      await MapsNavigation.ouvrirItineraire(
        lat: lat,
        lng: lng,
        label: widget.titre,
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
    }
  }

  Future<void> _avancerStatutCourse() async {
    final statut = _statutCourse;
    if (statut == null || _actionStatut) return;

    if (statut == StatutCourse.recupere) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ValidationOtpScreen(courseId: widget.courseId),
        ),
      );
      try {
        final course =
            await ref.read(courseServiceProvider).getCourse(widget.courseId);
        if (mounted) setState(() => _statutCourse = course.statut);
      } catch (_) {}
      return;
    }

    final next = statut.prochainStatutDb;
    if (next == null) return;

    setState(() => _actionStatut = true);
    try {
      final course = await ref.read(courseServiceProvider).avancerStatut(
            courseId: widget.courseId,
            nouveauStatut: next,
          );
      if (!mounted) return;
      setState(() {
        _statutCourse = course.statut;
        _actionStatut = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Statut : ${course.statut.labelFr}'),
          backgroundColor: AppColors.savane,
        ),
      );
      // Recharge messages (message système)
      final msgs = await ref
          .read(messagingServiceProvider)
          .chargerMessages(widget.courseId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        _idsConnus
          ..clear()
          ..addAll(msgs.map((m) => m.id));
      });
      _scrollBas();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _actionStatut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionStatut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _envoyerNote() async {
    final profil = ref.read(authProvider).profil;
    if (profil == null || profil.estLivreur) return;
    if (_noteChoisie < 1 || widget.modeDemo || _envoiNote) return;
    setState(() => _envoiNote = true);
    try {
      await ref.read(courseServiceProvider).noterLivreur(
            courseId: widget.courseId,
            note: _noteChoisie,
            commentaire: _commentaireNote.text.trim().isEmpty
                ? null
                : _commentaireNote.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _noteEnvoyee = true;
        _envoiNote = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Avis enregistré — le livreur verra votre note sur son profil',
          ),
          backgroundColor: AppColors.savane,
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _envoiNote = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _channel?.unsubscribe();
    _ctrl.dispose();
    _commentaireNote.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profil = ref.watch(authProvider).profil;
    // Seul le client (demandeur) peut noter — jamais le livreur
    final peutNoter = profil != null && !profil.estLivreur;
    final estLivreur = profil?.estLivreur == true;
    final aDestination = _destLat != null && _destLng != null;

    return Scaffold(
      backgroundColor: AppColors.ciel,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.titre),
            Text(
              widget.modeDemo
                  ? 'Aperçu messagerie'
                  : (_verrouille
                      ? 'Verrouillée'
                      : (widget.telephoneLivreur ?? 'Messagerie')),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
        actions: [
          if (aDestination)
            IconButton(
              onPressed: _ouvrirCarteDansApp,
              icon: const Icon(Icons.map_rounded),
              tooltip: estLivreur ? 'Suivre le trajet' : 'Suivre mon livreur',
            ),
          if (widget.telephoneLivreur != null &&
              widget.telephoneLivreur!.isNotEmpty)
            IconButton(
              onPressed: _appeler,
              icon: const Icon(Icons.call_rounded),
              tooltip: 'Appeler',
            ),
        ],
      ),
      body: Column(
        children: [
          if (aDestination)
            Material(
              color: const Color(0xFFE8F5EE),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.map_rounded, color: AppColors.savane),
                title: Text(
                  estLivreur
                      ? 'Se rendre chez le client'
                      : 'Suivre mon livreur',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  estLivreur
                      ? 'Carte dans FasoLiv — suivi GPS en direct'
                      : 'Voir le livreur se déplacer vers vous',
                ),
                trailing: FilledButton(
                  onPressed: _ouvrirCarteDansApp,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(estLivreur ? 'Suivre' : 'Carte'),
                ),
              ),
            ),
          if (estLivreur && aDestination)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _ouvrirItineraire,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Ouvrir Google Maps'),
                ),
              ),
            ),
          if (_statutCourse != null &&
              _statutCourse != StatutCourse.annule &&
              !widget.modeDemo)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5EBE7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flag_rounded,
                          size: 18, color: AppColors.savane),
                      const SizedBox(width: 8),
                      Text(
                        'Statut : ${_statutCourse!.labelFr}',
                        style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _StatutStepper(statut: _statutCourse!),
                  if (estLivreur &&
                      _statutCourse!.prochaineActionLivreur != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            _actionStatut ? null : _avancerStatutCourse,
                        child: _actionStatut
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_statutCourse!.prochaineActionLivreur!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (widget.telephoneLivreur != null &&
              widget.telephoneLivreur!.isNotEmpty)
            Material(
              color: Colors.white,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.phone, color: AppColors.savane),
                title: Text(
                  widget.telephoneLivreur!,
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  estLivreur ? 'Numéro du client' : 'Numéro du livreur',
                ),
                trailing: TextButton(
                  onPressed: _appeler,
                  child: const Text('Appeler'),
                ),
              ),
            ),
          if (peutNoter && _noteEnvoyee && !widget.modeDemo)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.savane.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '✓ Votre note a été envoyée au livreur',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.savane,
                ),
              ),
            ),
          if (peutNoter && !_noteEnvoyee && !widget.modeDemo)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Noter ce livreur',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _noteChoisie = i),
                          icon: Icon(
                            i <= _noteChoisie
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: AppColors.ocre,
                          ),
                        ),
                    ],
                  ),
                  if (_noteChoisie > 0) ...[
                    TextField(
                      controller: _commentaireNote,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Commentaire (optionnel)',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _envoiNote ? null : _envoyerNote,
                        child: _envoiNote
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Envoyer la note'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_verrouille)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.terre.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _erreur ?? 'Messagerie indisponible pour cette course.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: _chargement
                ? const Center(child: CircularProgressIndicator())
                : _erreur != null && _messages.isEmpty && !_verrouille
                    ? Center(child: Text(_erreur!))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final moi = m.senderId == widget.monUserId;
                          return _Bulle(message: m, moi: moi);
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      enabled: !_verrouille || widget.modeDemo,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _verrouille && !widget.modeDemo
                            ? 'Messagerie verrouillée'
                            : 'Écrire un message…',
                        filled: true,
                        fillColor: AppColors.ciel,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _envoyer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        (_verrouille && !widget.modeDemo) ? null : _envoyer,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(14),
                    ),
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatutStepper extends StatelessWidget {
  const _StatutStepper({required this.statut});

  final StatutCourse statut;

  int get _index {
    switch (statut) {
      case StatutCourse.propose:
        return 0;
      case StatutCourse.accepte:
        return 1;
      case StatutCourse.recupere:
        return 2;
      case StatutCourse.livre:
        return 3;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    const steps = ['Assignée', 'En route', 'Sur place', 'Livrée'];
    final idx = _index;
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= idx
                    ? AppColors.savane
                    : AppColors.muted.withValues(alpha: 0.25),
              ),
            ),
          Column(
            children: [
              Icon(
                i <= idx ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: i <= idx ? AppColors.savane : AppColors.muted,
              ),
              const SizedBox(height: 2),
              Text(
                steps[i],
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: i == idx ? FontWeight.w700 : FontWeight.w500,
                  color: i <= idx ? AppColors.savaneFonce : AppColors.muted,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.message, required this.moi});

  final MessageChat message;
  final bool moi;

  @override
  Widget build(BuildContext context) {
    final heure = DateFormat.Hm().format(message.createdAt.toLocal());
    return Align(
      alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: moi ? AppColors.savane : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(moi ? 18 : 4),
            bottomRight: Radius.circular(moi ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              moi ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.contenu,
              style: GoogleFonts.dmSans(
                color: moi ? Colors.white : AppColors.encre,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              heure,
              style: TextStyle(
                fontSize: 10,
                color: moi
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
