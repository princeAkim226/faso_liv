-- =============================================================================
-- FasoLiv v3 — CNIB recto/verso + accès client sans compte (anon)
-- =============================================================================

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS cnib_recto_url TEXT,
  ADD COLUMN IF NOT EXISTS cnib_verso_url TEXT;

COMMENT ON COLUMN profiles.cnib_recto_url IS 'URL Storage photo recto CNIB (livreurs)';
COMMENT ON COLUMN profiles.cnib_verso_url IS 'URL Storage photo verso CNIB (livreurs)';

-- CNIB photos : obligatoires pour passer en ligne (pas à la création du compte)
CREATE OR REPLACE FUNCTION assert_livreur_complet()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.type_utilisateur = 'livreur' THEN
    IF NEW.cnib IS NULL OR length(trim(NEW.cnib)) < 5 THEN
      RAISE EXCEPTION 'Un livreur doit renseigner son numéro CNIB';
    END IF;
    IF NEW.type_vehicule IS NULL THEN
      RAISE EXCEPTION 'Un livreur doit indiquer son type de véhicule';
    END IF;
    IF NEW.localisation_active = true
       AND (NEW.cnib_recto_url IS NULL OR NEW.cnib_verso_url IS NULL) THEN
      RAISE EXCEPTION 'Téléversez le recto et le verso de votre CNIB avant de passer en ligne';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- Storage bucket privé pour pièces d'identité
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'cnib-docs',
  'cnib-docs',
  false,
  5242880, -- 5 Mo
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Le livreur upload uniquement dans son dossier user_id/...
DROP POLICY IF EXISTS "Livreur upload CNIB" ON storage.objects;
CREATE POLICY "Livreur upload CNIB"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'cnib-docs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Livreur lit sa CNIB" ON storage.objects;
CREATE POLICY "Livreur lit sa CNIB"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'cnib-docs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Livreur met à jour sa CNIB" ON storage.objects;
CREATE POLICY "Livreur met à jour sa CNIB"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'cnib-docs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Livreur supprime sa CNIB" ON storage.objects;
CREATE POLICY "Livreur supprime sa CNIB"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'cnib-docs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- -----------------------------------------------------------------------------
-- Clients sans compte : lecture publique des livreurs en ligne
-- -----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION get_livreurs_proches(
  DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, type_vehicule
) TO anon;

-- Positions des livreurs disponibles visibles en lecture (sans CNIB)
DROP POLICY IF EXISTS "Public lit positions disponibles" ON livreur_positions;
CREATE POLICY "Public lit positions disponibles"
  ON livreur_positions FOR SELECT
  TO anon, authenticated
  USING (est_disponible = true);

-- Profils livreurs en ligne : infos publiques seulement (pas le CNIB texte)
-- Note: SELECT * exposerait cnib — préférer une vue publique
CREATE OR REPLACE VIEW public.livreurs_public AS
SELECT
  p.id,
  p.nom,
  p.prenom,
  p.telephone,
  p.ville,
  p.type_vehicule,
  p.note_moyenne,
  p.est_verifie,
  p.photo_url,
  p.localisation_active,
  -- Indique si les docs CNIB sont fournis, sans exposer les URLs
  (p.cnib_recto_url IS NOT NULL AND p.cnib_verso_url IS NOT NULL) AS cnib_fournie
FROM profiles p
WHERE p.type_utilisateur = 'livreur';

GRANT SELECT ON public.livreurs_public TO anon, authenticated;
