import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/fasoliv_api_config.dart';
import '../core/utils/app_exceptions.dart';

class SoomaJob {
  SoomaJob({
    required this.jobId,
    required this.status,
    required this.restaurantName,
    required this.clientName,
    this.restaurantAddress,
    this.clientAddress,
    this.feeXof,
  });

  final String jobId;
  final String status;
  final String restaurantName;
  final String clientName;
  final String? restaurantAddress;
  final String? clientAddress;
  final num? feeXof;

  String get statutFr {
    switch (status) {
      case 'searching':
        return 'Disponible';
      case 'assigned':
        return 'Assignée';
      case 'picked_up':
        return 'Colis pris';
      case 'in_transit':
        return 'En route';
      case 'delivered':
        return 'Livrée';
      case 'cancelled':
        return 'Annulée';
      case 'failed':
        return 'Échec';
      default:
        return status;
    }
  }

  factory SoomaJob.fromJson(Map<String, dynamic> json) {
    final resto = json['restaurant'] as Map<String, dynamic>? ?? {};
    final client = json['client'] as Map<String, dynamic>? ?? {};
    return SoomaJob(
      jobId: json['jobId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      restaurantName: resto['name']?.toString() ?? 'Restaurant',
      clientName: client['name']?.toString() ?? 'Client',
      restaurantAddress: resto['address']?.toString(),
      clientAddress: client['address']?.toString(),
      feeXof: json['feeXof'] as num?,
    );
  }
}

class SoomaJobService {
  static const _kToken = 'fasoliv_driver_token';

  Future<String?> token() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kToken);
  }

  Future<void> login({required String phone, required String password}) async {
    final res = await http.post(
      Uri.parse('${FasoLivApiConfig.baseUrl}/v1/drivers/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'phone': phone, 'password': password}),
    );
    if (res.statusCode == 401) {
      final created = await http.post(
        Uri.parse('${FasoLivApiConfig.baseUrl}/v1/drivers/register'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'name': phone,
          'phone': phone,
          'password': password,
        }),
      );
      if (created.statusCode != 201 && created.statusCode != 200) {
        throw AppException('Connexion livreur API impossible');
      }
      await _sauverToken(jsonDecode(created.body) as Map<String, dynamic>);
      return;
    }
    if (res.statusCode != 200) {
      throw AppException('Connexion livreur API impossible');
    }
    await _sauverToken(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> _sauverToken(Map<String, dynamic> body) async {
    final token = body['token']?.toString();
    if (token == null || token.isEmpty) {
      throw AppException('Token livreur manquant');
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
  }

  Future<List<SoomaJob>> mesCourses() async {
    final t = await token();
    if (t == null) throw AppException('Connectez-vous aux courses restaurants');
    final res = await http.get(
      Uri.parse('${FasoLivApiConfig.baseUrl}/v1/driver/jobs'),
      headers: {'authorization': 'Bearer $t'},
    );
    if (res.statusCode != 200) {
      throw AppException('Courses indisponibles (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (data['jobs'] as List<dynamic>? ?? []);
    return list
        .map((e) => SoomaJob.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> accepter(String jobId) => _post('/v1/driver/jobs/$jobId/accept');

  Future<void> statut(String jobId, String status) =>
      _post('/v1/driver/jobs/$jobId/status', {'status': status});

  Future<void> position({
    required double lat,
    required double lng,
  }) =>
      _post('/v1/driver/location', {'lat': lat, 'lng': lng});

  Future<void> _post(String path, [Map<String, dynamic>? body]) async {
    final t = await token();
    if (t == null) throw AppException('Session livreur API absente');
    final res = await http.post(
      Uri.parse('${FasoLivApiConfig.baseUrl}$path'),
      headers: {
        'authorization': 'Bearer $t',
        'content-type': 'application/json',
      },
      body: jsonEncode(body ?? {}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppException('Action refusée (${res.statusCode})');
    }
  }
}
