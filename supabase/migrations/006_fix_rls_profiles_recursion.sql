-- =============================================================================
-- Fix : récursion infinie RLS sur profiles
-- Cause : une policy SELECT sur profiles faisait EXISTS (SELECT … FROM profiles)
-- =============================================================================

-- Helper SECURITY DEFINER : lit le type sans repasser par RLS
CREATE OR REPLACE FUNCTION public.mon_type_utilisateur()
RETURNS type_utilisateur
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT type_utilisateur
  FROM profiles
  WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.est_demandeur()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND type_utilisateur = 'demandeur'
  );
$$;

GRANT EXECUTE ON FUNCTION public.mon_type_utilisateur() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.est_demandeur() TO authenticated, anon;

-- Remplace la policy récursive
DROP POLICY IF EXISTS "Les demandeurs voient les profils livreurs" ON profiles;
CREATE POLICY "Les demandeurs voient les profils livreurs"
  ON profiles FOR SELECT
  USING (
    type_utilisateur = 'livreur'
    AND public.est_demandeur()
  );

-- Upsert client (inscription) : INSERT + UPDATE de son propre profil
DROP POLICY IF EXISTS "Insertion de son propre profil" ON profiles;
CREATE POLICY "Insertion de son propre profil"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Positions : même piège si l’ancienne policy est encore active
DROP POLICY IF EXISTS "Demandeurs lisent les positions disponibles" ON livreur_positions;
-- Conservé si 003 n’a pas été appliqué ; sinon « Public lit positions… » suffit
CREATE POLICY "Demandeurs lisent les positions disponibles"
  ON livreur_positions FOR SELECT
  USING (
    est_disponible = true
    AND public.est_demandeur()
  );

-- Trigger auth : préremplir véhicule / ville pour éviter l’échec assert_livreur_complet
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    nom,
    prenom,
    telephone,
    type_utilisateur,
    type_vehicule,
    numero_plaque,
    ville,
    telephone_verifie
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nom', ''),
    COALESCE(NEW.raw_user_meta_data->>'prenom', ''),
    COALESCE(NEW.raw_user_meta_data->>'telephone', NEW.phone, ''),
    COALESCE(
      (NEW.raw_user_meta_data->>'type_utilisateur')::type_utilisateur,
      'demandeur'
    ),
    CASE
      WHEN NEW.raw_user_meta_data->>'type_vehicule' IS NULL
        OR NEW.raw_user_meta_data->>'type_vehicule' = ''
      THEN NULL
      ELSE (NEW.raw_user_meta_data->>'type_vehicule')::type_vehicule
    END,
    NULLIF(trim(COALESCE(NEW.raw_user_meta_data->>'numero_plaque', '')), ''),
    COALESCE(NEW.raw_user_meta_data->>'ville', 'Ouagadougou'),
    COALESCE((NEW.raw_user_meta_data->>'telephone_verifie')::boolean, false)
  );
  RETURN NEW;
END;
$$;

-- Mode invité : la RPC ne doit PAS passer par RLS (sinon JOIN profiles = récursion)
CREATE OR REPLACE FUNCTION get_livreurs_proches(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_rayon_km DOUBLE PRECISION DEFAULT 5.0,
  p_type_vehicule type_vehicule DEFAULT NULL
)
RETURNS TABLE (
  livreur_id       UUID,
  nom              TEXT,
  prenom           TEXT,
  telephone        TEXT,
  ville            TEXT,
  type_vehicule    type_vehicule,
  note_moyenne     NUMERIC,
  est_verifie      BOOLEAN,
  photo_url        TEXT,
  distance_km      DOUBLE PRECISION,
  localisation_active BOOLEAN,
  updated_at       TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    lp.livreur_id,
    p.nom,
    p.prenom,
    p.telephone,
    p.ville,
    p.type_vehicule,
    p.note_moyenne,
    p.est_verifie,
    p.photo_url,
    ROUND(
      (ST_Distance(
        lp.position,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
      ) / 1000.0)::numeric,
      2
    )::double precision AS distance_km,
    p.localisation_active,
    lp.updated_at
  FROM livreur_positions lp
  INNER JOIN profiles p ON p.id = lp.livreur_id
  WHERE
    lp.est_disponible = true
    AND p.localisation_active = true
    AND p.type_utilisateur = 'livreur'
    AND (p_type_vehicule IS NULL OR p.type_vehicule = p_type_vehicule)
    AND ST_DWithin(
      lp.position,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_rayon_km * 1000
    )
  ORDER BY distance_km ASC;
$$;

GRANT EXECUTE ON FUNCTION get_livreurs_proches(
  DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, type_vehicule
) TO anon, authenticated;
