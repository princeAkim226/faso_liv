import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../models/avis_livreur.dart';
import '../../services/avis_service.dart';
import '../../widgets/brand_widgets.dart';

final avisServiceProvider = Provider<AvisService>((ref) => AvisService());

/// Liste des notes reçues par le livreur.
class AvisLivreurScreen extends ConsumerStatefulWidget {
  const AvisLivreurScreen({super.key});

  @override
  ConsumerState<AvisLivreurScreen> createState() => _AvisLivreurScreenState();
}

class _AvisLivreurScreenState extends ConsumerState<AvisLivreurScreen> {
  List<AvisLivreur> _avis = [];
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
      final service = ref.read(avisServiceProvider);
      final list = await service.mesAvisRecus();
      await service.marquerCommeLus();
      if (!mounted) return;
      setState(() {
        _avis = list;
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

  @override
  Widget build(BuildContext context) {
    final moyenne = _avis.isEmpty
        ? null
        : _avis.map((a) => a.note).reduce((a, b) => a + b) / _avis.length;

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
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Text(
                      'Mes notes',
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
              if (moyenne != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppColors.ocre, size: 36),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              moyenne.toStringAsFixed(1),
                              style: GoogleFonts.outfit(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${_avis.length} avis client${_avis.length > 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
                                style:
                                    const TextStyle(color: AppColors.danger),
                              ),
                            ),
                          )
                        : _avis.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.star_outline_rounded,
                                        size: 56,
                                        color: AppColors.muted
                                            .withValues(alpha: 0.45),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Aucune note pour l\'instant',
                                        style: GoogleFonts.outfit(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Quand un client vous note après une course, '
                                        'l\'avis apparaît ici.',
                                        textAlign: TextAlign.center,
                                        style:
                                            TextStyle(color: AppColors.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _charger,
                                child: ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _avis.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final a = _avis[i];
                                    final date = DateFormat('dd/MM/yyyy HH:mm')
                                        .format(a.createdAt.toLocal());
                                    return Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: a.luParLivreur
                                            ? null
                                            : Border.all(
                                                color: AppColors.savane
                                                    .withValues(alpha: 0.45),
                                              ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  a.clientLabel,
                                                  style: GoogleFonts.dmSans(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              if (!a.luParLivreur)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.savane
                                                        .withValues(alpha: 0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  child: const Text(
                                                    'Nouveau',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: AppColors.savane,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              for (var s = 1; s <= 5; s++)
                                                Icon(
                                                  s <= a.note
                                                      ? Icons.star_rounded
                                                      : Icons
                                                          .star_outline_rounded,
                                                  size: 20,
                                                  color: AppColors.ocre,
                                                ),
                                              const Spacer(),
                                              Text(
                                                date,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (a.commentaire != null &&
                                              a.commentaire!.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              a.commentaire!,
                                              style: const TextStyle(
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
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
