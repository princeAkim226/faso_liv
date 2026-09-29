import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../models/course.dart';
import '../../models/course_historique.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/brand_widgets.dart';
import '../chat/chat_screen.dart';

/// Historique simple des courses (client ou livreur).
class HistoriqueCoursesScreen extends ConsumerStatefulWidget {
  const HistoriqueCoursesScreen({super.key});

  @override
  ConsumerState<HistoriqueCoursesScreen> createState() =>
      _HistoriqueCoursesScreenState();
}

class _HistoriqueCoursesScreenState
    extends ConsumerState<HistoriqueCoursesScreen> {
  List<CourseHistorique> _items = [];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final list =
          await ref.read(courseServiceProvider).mesCoursesHistorique();
      if (!mounted) return;
      setState(() {
        _items = list;
        _chargement = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
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

  Color _couleurStatut(StatutCourse s) {
    switch (s) {
      case StatutCourse.livre:
        return AppColors.savane;
      case StatutCourse.annule:
        return AppColors.danger;
      case StatutCourse.accepte:
        return const Color(0xFF1565C0);
      case StatutCourse.recupere:
        return AppColors.terre;
      default:
        return AppColors.muted;
    }
  }

  void _ouvrirChat(CourseHistorique c) {
    final monId = ref.read(authProvider).user?.id;
    if (monId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          courseId: c.courseId,
          titre: c.titre,
          monUserId: monId,
          telephoneLivreur: c.interlocuteurTelephone,
          livreurId: c.livreurId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy · HH:mm');

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
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Text(
                      'Historique',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _chargement ? null : _charger,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _chargement
                    ? const Center(child: CircularProgressIndicator())
                    : _erreur != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _erreur!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.danger),
                              ),
                            ),
                          )
                        : _items.isEmpty
                            ? Center(
                                child: Text(
                                  'Aucune course pour le moment',
                                  style: GoogleFonts.dmSans(
                                    color: AppColors.muted,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _items.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final c = _items[i];
                                  final color = _couleurStatut(c.statut);
                                  return Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () => _ouvrirChat(c),
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor:
                                                  color.withValues(alpha: 0.15),
                                              child: Icon(
                                                Icons.local_shipping_outlined,
                                                color: color,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    c.titre,
                                                    style: GoogleFonts.dmSans(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    fmt.format(
                                                      c.createdAt.toLocal(),
                                                    ),
                                                    style: const TextStyle(
                                                      color: AppColors.muted,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: color.withValues(
                                                      alpha: 0.12,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      8,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    c.statut.labelFr,
                                                    style: TextStyle(
                                                      color: color,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                const Icon(
                                                  Icons.chevron_right_rounded,
                                                  color: AppColors.muted,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
