import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exceptions.dart';

enum FaceCnib { recto, verso }

/// Upload des photos CNIB (recto / verso) vers Supabase Storage.
/// On stocke le **chemin Stable** dans `profiles` (pas une URL signée expirable).
class CnibStorageService {
  CnibStorageService({
    SupabaseClient? client,
    ImagePicker? picker,
  })  : _supabase = client ?? Supabase.instance.client,
        _picker = picker ?? ImagePicker();

  final SupabaseClient _supabase;
  final ImagePicker _picker;

  static const bucket = 'cnib-docs';

  Future<XFile?> choisirImage({required ImageSource source}) async {
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (e) {
      throw AppException('Impossible d\'ouvrir la galerie / caméra : $e');
    }
  }

  /// Chemin stocké en base : `userId/recto.jpg`
  String cheminStockage(String userId, FaceCnib face, String ext) =>
      '$userId/${face.name}$ext';

  Future<String> uploaderFace({
    required String userId,
    required FaceCnib face,
    required XFile fichier,
  }) async {
    try {
      final ext = _extension(fichier.name);
      final path = cheminStockage(userId, face, ext);
      final bytes = await fichier.readAsBytes();

      await _supabase.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _mime(ext),
            ),
          );

      // Référence stable (pas d'URL signée qui expire)
      return path;
    } on StorageException catch (e) {
      throw AppException('Upload CNIB ${face.name} : ${e.message}');
    } catch (e) {
      throw AppException('Échec upload CNIB : $e');
    }
  }

  Future<({String rectoUrl, String versoUrl})> uploaderRectoVerso({
    required String userId,
    required XFile recto,
    required XFile verso,
  }) async {
    final rectoUrl = await uploaderFace(
      userId: userId,
      face: FaceCnib.recto,
      fichier: recto,
    );
    final versoUrl = await uploaderFace(
      userId: userId,
      face: FaceCnib.verso,
      fichier: verso,
    );
    return (rectoUrl: rectoUrl, versoUrl: versoUrl);
  }

  /// Si les fichiers existent déjà dans Storage (inscription partielle),
  /// retourne leurs chemins pour les rattacher au profil.
  Future<({String? recto, String? verso})> recupererCheminsExistants(
    String userId,
  ) async {
    try {
      final files = await _supabase.storage.from(bucket).list(path: userId);
      String? recto;
      String? verso;
      for (final f in files) {
        final name = f.name.toLowerCase();
        if (name.startsWith('recto')) {
          recto = '$userId/${f.name}';
        } else if (name.startsWith('verso')) {
          verso = '$userId/${f.name}';
        }
      }
      return (recto: recto, verso: verso);
    } catch (_) {
      return (recto: null, verso: null);
    }
  }

  String _extension(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0) return '.jpg';
    return name.substring(i).toLowerCase();
  }

  String _mime(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  static Future<Uint8List> lireOctets(XFile file) => file.readAsBytes();
}
