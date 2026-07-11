import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme/app_theme.dart';

/// Zone d'upload pour une face de la CNIB (recto ou verso).
class CnibUploadTile extends StatelessWidget {
  const CnibUploadTile({
    super.key,
    required this.label,
    required this.hint,
    required this.fichier,
    required this.onChoisir,
    required this.onEffacer,
    this.erreur = false,
  });

  final String label;
  final String hint;
  final XFile? fichier;
  final VoidCallback onChoisir;
  final VoidCallback onEffacer;
  final bool erreur;

  @override
  Widget build(BuildContext context) {
    final hasFile = fichier != null;
    final borderColor = hasFile
        ? AppColors.savane
        : (erreur ? AppColors.danger : Colors.black.withValues(alpha: 0.1));

    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onChoisir,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor,
                width: hasFile || erreur ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasFile
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder(
                        future: fichier!.readAsBytes(),
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const ColoredBox(
                              color: Color(0xFFE8F2EC),
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          return Image.memory(
                            snap.data!,
                            fit: BoxFit.cover,
                          );
                        },
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: onEffacer,
                            icon: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (erreur ? AppColors.danger : AppColors.savane)
                              .withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          color: erreur ? AppColors.danger : AppColors.savane,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: erreur ? AppColors.danger : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          hint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: erreur ? AppColors.danger : AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Dialogue source photo (caméra / galerie).
Future<ImageSource?> choisirSourcePhoto(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
            const SizedBox(height: 16),
            const Text(
              'Photo CNIB',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.savane),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.terre),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
}
