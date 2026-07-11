-- =============================================================================
-- Abonnement mensuel livreur : 2 000 FCFA / mois
-- Sans abonnement actif → pas de passage « En ligne »
-- =============================================================================

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS abonnement_expire_at TIMESTAMPTZ;

COMMENT ON COLUMN profiles.abonnement_expire_at IS
  'Fin de validité de l''abonnement mensuel livreur (2 000 FCFA)';

-- Type de transaction pour l'historique (PG15+)
ALTER TYPE type_transaction ADD VALUE IF NOT EXISTS 'abonnement';

CREATE OR REPLACE FUNCTION public.abonnement_est_actif(p_user_id UUID DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = p_user_id
      AND type_utilisateur = 'livreur'
      AND abonnement_expire_at IS NOT NULL
      AND abonnement_expire_at > now()
  );
$$;

GRANT EXECUTE ON FUNCTION public.abonnement_est_actif(UUID) TO authenticated, anon;

-- Active / prolonge d'1 mois après paiement Mobile Money (démo / webhook)
CREATE OR REPLACE FUNCTION public.activer_abonnement_mensuel(
  p_reference TEXT DEFAULT NULL
)
RETURNS profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profil  profiles;
  v_base    TIMESTAMPTZ;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT * INTO v_profil
  FROM profiles
  WHERE id = v_user_id AND type_utilisateur = 'livreur'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Réservé aux livreurs';
  END IF;

  v_base := GREATEST(COALESCE(v_profil.abonnement_expire_at, now()), now());

  UPDATE profiles
  SET abonnement_expire_at = v_base + INTERVAL '1 month'
  WHERE id = v_user_id
  RETURNING * INTO v_profil;

  INSERT INTO transactions (
    user_id, montant, type, reference_mobile_money, statut
  ) VALUES (
    v_user_id,
    2000,
    'abonnement',
    COALESCE(p_reference, 'ABO-' || gen_random_uuid()::text),
    'reussi'
  );

  RETURN v_profil;
END;
$$;

GRANT EXECUTE ON FUNCTION public.activer_abonnement_mensuel(TEXT) TO authenticated;

-- Bloque le passage en ligne sans abonnement
CREATE OR REPLACE FUNCTION set_localisation_active(p_active BOOLEAN)
RETURNS profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profil  profiles;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF p_active AND NOT public.abonnement_est_actif(v_user_id) THEN
    RAISE EXCEPTION 'ABONNEMENT_REQUIS: Abonnement de 2 000 FCFA / mois requis pour passer en ligne';
  END IF;

  UPDATE profiles
  SET localisation_active = p_active
  WHERE id = v_user_id AND type_utilisateur = 'livreur'
  RETURNING * INTO v_profil;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Réservé aux livreurs';
  END IF;

  IF NOT p_active THEN
    UPDATE livreur_positions
    SET est_disponible = false
    WHERE livreur_id = v_user_id;
  END IF;

  RETURN v_profil;
END;
$$;

CREATE OR REPLACE FUNCTION upsert_livreur_position(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_disponible BOOLEAN DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = v_user_id AND type_utilisateur = 'livreur'
  ) THEN
    RAISE EXCEPTION 'Réservé aux livreurs';
  END IF;

  IF p_disponible AND NOT public.abonnement_est_actif(v_user_id) THEN
    RAISE EXCEPTION 'ABONNEMENT_REQUIS: Abonnement de 2 000 FCFA / mois requis pour passer en ligne';
  END IF;

  UPDATE profiles
  SET localisation_active = true
  WHERE id = v_user_id;

  INSERT INTO livreur_positions (livreur_id, position, est_disponible, updated_at)
  VALUES (
    v_user_id,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_disponible,
    now()
  )
  ON CONFLICT (livreur_id) DO UPDATE
  SET
    position = EXCLUDED.position,
    est_disponible = EXCLUDED.est_disponible,
    updated_at = now();
END;
$$;

-- Clients : ne montrer que les livreurs avec abonnement actif
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
    AND p.abonnement_expire_at IS NOT NULL
    AND p.abonnement_expire_at > now()
    AND (p_type_vehicule IS NULL OR p.type_vehicule = p_type_vehicule)
    AND ST_DWithin(
      lp.position,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_rayon_km * 1000
    )
  ORDER BY distance_km ASC;
$$;
