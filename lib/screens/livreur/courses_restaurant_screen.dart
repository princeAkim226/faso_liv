import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../services/sooma_job_service.dart';
import '../../widgets/brand_widgets.dart';

/// Courses créées par les restaurants via Sôôma.
class CoursesRestaurantScreen extends StatefulWidget {
  const CoursesRestaurantScreen({super.key});

  @override
  State<CoursesRestaurantScreen> createState() =>
      _CoursesRestaurantScreenState();
}

class _CoursesRestaurantScreenState extends State<CoursesRestaurantScreen> {
  final _api = SoomaJobService();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  List<SoomaJob> _jobs = [];
  bool _pret = false;
  bool _chargement = true;
  String? _erreur;
  Timer? _gps;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final token = await _api.token();
    if (!mounted) return;
    if (token == null) {
      setState(() {
        _pret = false;
        _chargement = false;
      });
      return;
    }
    await _charger();
    _gps ??= Timer.periodic(const Duration(seconds: 8), (_) => _pousserGps());
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final jobs = await _api.mesCourses();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _pret = true;
        _chargement = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = e.message;
      });
    }
  }

  Future<void> _connecter() async {
    try {
      await _api.login(phone: _phone.text.trim(), password: _password.text);
      await _charger();
      _gps ??= Timer.periodic(const Duration(seconds: 8), (_) => _pousserGps());
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pousserGps() async {
    final actif = _jobs.any((j) =>
        j.status == 'assigned' || j.status == 'picked_up' || j.status == 'in_transit');
    if (!actif) return;
    try {
      final pos = await Geolocator.getCurrentPosition();
      await _api.position(lat: pos.latitude, lng: pos.longitude);
    } catch (_) {}
  }

  Future<void> _action(SoomaJob job, String action) async {
    try {
      if (action == 'accept') {
        await _api.accepter(job.jobId);
      } else {
        await _api.statut(job.jobId, action);
      }
      await _charger();
      await _pousserGps();
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  void dispose() {
    _gps?.cancel();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FasoBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Text(
                    'Courses restaurants',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: _chargement
                    ? const Center(child: CircularProgressIndicator())
                    : !_pret
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _phone,
                                  decoration: const InputDecoration(
                                    labelText: 'Téléphone livreur',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _password,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Mot de passe (6 caractères min.)',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _connecter,
                                  child: const Text('Continuer'),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _charger,
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                if (_erreur != null)
                                  Text(_erreur!, style: const TextStyle(color: AppColors.danger)),
                                if (_jobs.isEmpty)
                                  const Text('Aucune course restaurant pour le moment'),
                                for (final job in _jobs) _carte(job),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _carte(SoomaJob job) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.restaurantName, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('Client : ${job.clientName}'),
            Text(job.statutFr, style: const TextStyle(color: AppColors.savane)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (job.status == 'searching')
                  FilledButton(
                    onPressed: () => _action(job, 'accept'),
                    child: const Text('Accepter'),
                  ),
                if (job.status == 'assigned') ...[
                  OutlinedButton(
                    onPressed: () => _action(job, 'arrived_restaurant'),
                    child: const Text('Arrivé resto'),
                  ),
                  FilledButton(
                    onPressed: () => _action(job, 'picked_up'),
                    child: const Text('Colis pris'),
                  ),
                ],
                if (job.status == 'picked_up')
                  FilledButton(
                    onPressed: () => _action(job, 'in_transit'),
                    child: const Text('En route'),
                  ),
                if (job.status == 'in_transit')
                  FilledButton(
                    onPressed: () => _action(job, 'delivered'),
                    child: const Text('Livré'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
