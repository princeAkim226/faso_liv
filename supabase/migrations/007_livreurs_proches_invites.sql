-- =============================================================================
-- Visibilité livreurs pour clients / mode invité
-- À exécuter si « Aucun livreur » alors qu’un livreur est En ligne
-- =============================================================================

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

REVOKE ALL ON FUNCTION get_livreurs_proches(
  DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, type_vehicule
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION get_livreurs_proches(
  DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, type_vehicule
) TO anon, authenticated;

-- Test manuel (remplacer par vos coords) :
-- SELECT * FROM get_livreurs_proches(11.2144, -4.3026, 15, NULL);
