import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../core/utils/maps_navigation.dart';
import '../../providers/auth_provider.dart';

/// Carte intégrée (sans MapController — évite le crash « rendered at least once »).
class ItineraireMapScreen extends ConsumerStatefulWidget {
  const ItineraireMapScreen({
    super.key,
    required this.courseId,
    required this.pointClientLat,
    required this.pointClientLng,
    required this.titre,
    required this.modeLivreur,
    this.livreurId,
  });

  final String courseId;
  final double pointClientLat;
  final double pointClientLng;
  final String titre;
  final bool modeLivreur;
  final String? livreurId;

  @override
  ConsumerState<ItineraireMapScreen> createState() =>
      _ItineraireMapScreenState();
}

class _ItineraireMapScreenState extends ConsumerState<ItineraireMapScreen> {
  StreamSubscription<Position>? _gpsSub;
  Timer? _pollLivreur;
  RealtimeChannel? _channel;

  LatLng? _posLivreur;
  List<LatLng> _route = [];
  String? _banner;
  double? _distanceM;
  int _mapGeneration = 0;

  LatLng get _pointClient =>
      LatLng(widget.pointClientLat, widget.pointClientLng);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _demarrer());
  }

  Future<void> _demarrer() async {
    try {
      if (widget.modeLivreur) {
        await _demarrerModeLivreur();
      } else {
        await _demarrerModeClient();
      }
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _banner = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _banner = 'Localisation : $e');
    }
  }

  Future<void> _demarrerModeLivreur() async {
    final location = ref.read(locationServiceProvider);
    await location.assurerPermissions();
    final pos = await location.positionActuelle();
    if (!mounted) return;
    final moi = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _posLivreur = moi;
      _majDistance();
      _mapGeneration++;
    });
    await _chargerRoute(from: moi, to: _pointClient);

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen((p) {
      if (!mounted) return;
      setState(() {
        _posLivreur = LatLng(p.latitude, p.longitude);
        _majDistance();
      });
    });
  }

  Future<void> _demarrerModeClient() async {
    await _rafraichirPositionLivreur(recentrer: true);
    _pollLivreur = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _rafraichirPositionLivreur(),
    );

    final livreurId = widget.livreurId;
    if (livreurId != null && livreurId.isNotEmpty) {
      _channel = Supabase.instance.client
          .channel('suivi-livreur-$livreurId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'livreur_positions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'livreur_id',
              value: livreurId,
            ),
            callback: (_) => _rafraichirPositionLivreur(),
          )
          .subscribe();
    }
  }

  Future<void> _rafraichirPositionLivreur({bool recentrer = false}) async {
    try {
      final raw = await Supabase.instance.client.rpc(
        'position_livreur_pour_course',
        params: {'p_course_id': widget.courseId},
      );
      Map<String, dynamic>? row;
      if (raw is List && raw.isNotEmpty) {
        row = Map<String, dynamic>.from(raw.first as Map);
      } else if (raw is Map) {
        row = Map<String, dynamic>.from(raw);
      }
      if (row == null) {
        if (mounted && _posLivreur == null) {
          setState(() => _banner = 'En attente de la position du livreur…');
        }
        return;
      }
      final lat = (row['lat'] as num?)?.toDouble();
      final lng = (row['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      final next = LatLng(lat, lng);
      final first = _posLivreur == null;
      if (!mounted) return;
      setState(() {
        _posLivreur = next;
        _banner = null;
        _majDistance();
        if (recentrer || first) _mapGeneration++;
      });
      if (first || _route.isEmpty) {
        await _chargerRoute(from: next, to: _pointClient);
      }
    } catch (_) {
      if (!mounted) return;
      if (_posLivreur == null) {
        setState(() => _banner = 'En attente de la position du livreur…');
      }
    }
  }

  void _majDistance() {
    final livreur = _posLivreur;
    if (livreur == null) {
      _distanceM = null;
      return;
    }
    _distanceM = Geolocator.distanceBetween(
      livreur.latitude,
      livreur.longitude,
      widget.pointClientLat,
      widget.pointClientLng,
    );
  }

  void _recentrer() {
    setState(() => _mapGeneration++);
  }

  LatLng get _centreCarte {
    final l = _posLivreur;
    if (l == null) return _pointClient;
    return LatLng(
      (l.latitude + _pointClient.latitude) / 2,
      (l.longitude + _pointClient.longitude) / 2,
    );
  }

  double get _zoomCarte {
    final l = _posLivreur;
    if (l == null) return 15;
    final d = Geolocator.distanceBetween(
      l.latitude,
      l.longitude,
      widget.pointClientLat,
      widget.pointClientLng,
    );
    if (d < 300) return 16;
    if (d < 1000) return 15;
    if (d < 3000) return 14;
    if (d < 8000) return 13;
    return 12;
  }

  Future<void> _chargerRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        if (mounted) setState(() => _route = [from, to]);
        return;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = json['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        if (mounted) setState(() => _route = [from, to]);
        return;
      }
      final geom = routes.first['geometry'] as Map<String, dynamic>?;
      final coords = geom?['coordinates'] as List<dynamic>?;
      if (coords == null || coords.isEmpty) {
        if (mounted) setState(() => _route = [from, to]);
        return;
      }
      final points = <LatLng>[];
      for (final c in coords) {
        final pair = c as List<dynamic>;
        points.add(LatLng(
          (pair[1] as num).toDouble(),
          (pair[0] as num).toDouble(),
        ));
      }
      if (!mounted) return;
      setState(() => _route = points);
    } catch (_) {
      if (mounted) setState(() => _route = [from, to]);
    }
  }

  String get _distanceLabel {
    final m = _distanceM;
    if (m == null) return '…';
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _pollLivreur?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sousTitre = widget.modeLivreur
        ? 'Vers ${widget.titre}'
        : 'Livreur : ${widget.titre}';

    return Scaffold(
      backgroundColor: AppColors.ciel,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.modeLivreur ? 'Suivi du trajet' : 'Suivre mon livreur'),
            Text(
              sousTitre,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Recentrer',
            onPressed: _recentrer,
            icon: const Icon(Icons.my_location_rounded),
          ),
          if (widget.modeLivreur)
            IconButton(
              tooltip: 'Google Maps',
              onPressed: () => MapsNavigation.ouvrirItineraire(
                lat: widget.pointClientLat,
                lng: widget.pointClientLng,
                label: widget.titre,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            key: ValueKey('map-$_mapGeneration'),
            options: MapOptions(
              initialCenter: _centreCarte,
              initialZoom: _zoomCarte,
              minZoom: 5,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.faso_liv',
              ),
              if (_route.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route,
                      color: AppColors.savane,
                      strokeWidth: 5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pointClient,
                    width: 48,
                    height: 48,
                    child: const Icon(
                      Icons.home_rounded,
                      color: AppColors.terre,
                      size: 40,
                    ),
                  ),
                  if (_posLivreur != null)
                    Marker(
                      point: _posLivreur!,
                      width: 48,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.savane,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.delivery_dining_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (_banner != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _banner!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.terre),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(18),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.modeLivreur
                          ? 'Distance restante : $_distanceLabel'
                          : 'Livreur à : $_distanceLabel',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.modeLivreur
                          ? 'Pin vert = vous · Maison = client'
                          : 'Pin vert = livreur · Maison = votre point',
                      style: GoogleFonts.dmSans(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _recentrer,
                            icon: const Icon(Icons.center_focus_strong),
                            label: const Text('Recentrer'),
                          ),
                        ),
                        if (widget.modeLivreur) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => MapsNavigation.ouvrirItineraire(
                                lat: widget.pointClientLat,
                                lng: widget.pointClientLng,
                                label: widget.titre,
                              ),
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('Maps'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
