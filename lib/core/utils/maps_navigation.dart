import 'package:url_launcher/url_launcher.dart';

import 'app_exceptions.dart';

/// Ouvre Google Maps / navigation vers une position GPS.
class MapsNavigation {
  MapsNavigation._();

  /// Itinéraire vers [lat],[lng] (mode voiture).
  static Future<void> ouvrirItineraire({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final dest = '$lat,$lng';
    final qLabel = Uri.encodeComponent(label?.trim().isNotEmpty == true
        ? label!.trim()
        : 'Point FasoLiv');

    // 1) Intent navigation Google Maps (Android)
    final nav = Uri.parse('google.navigation:q=$dest&mode=d');
    if (await canLaunchUrl(nav)) {
      final ok = await launchUrl(nav, mode: LaunchMode.externalApplication);
      if (ok) return;
    }

    // 2) URL universelle Google Maps (Android + iOS + navigateur)
    final web = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$dest'
      '&travelmode=driving',
    );
    if (await canLaunchUrl(web)) {
      final ok = await launchUrl(web, mode: LaunchMode.externalApplication);
      if (ok) return;
    }

    // 3) Schéma geo de secours
    final geo = Uri.parse('geo:$dest?q=$dest($qLabel)');
    if (await canLaunchUrl(geo)) {
      final ok = await launchUrl(geo, mode: LaunchMode.externalApplication);
      if (ok) return;
    }

    throw AppException(
      'Impossible d\'ouvrir Google Maps. '
      'Installez Maps ou vérifiez votre connexion.',
    );
  }
}
