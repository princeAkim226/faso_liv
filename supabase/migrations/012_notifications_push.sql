  -- =============================================================================
  -- Notifications push : alerte livreur quand un client le choisit
  -- =============================================================================

  ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS fcm_token TEXT;

  COMMENT ON COLUMN profiles.fcm_token IS
    'Token Firebase Cloud Messaging pour notifications hors-app';

  CREATE TABLE IF NOT EXISTS notifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    titre       TEXT NOT NULL,
    corps       TEXT NOT NULL,
    type        TEXT NOT NULL DEFAULT 'info',
    data        JSONB NOT NULL DEFAULT '{}'::jsonb,
    lu          BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
  );

  CREATE INDEX IF NOT EXISTS idx_notifications_user
    ON notifications (user_id, created_at DESC);

  CREATE INDEX IF NOT EXISTS idx_notifications_non_lues
    ON notifications (user_id)
    WHERE lu = false;

  ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "User lit ses notifications" ON notifications;
  CREATE POLICY "User lit ses notifications"
    ON notifications FOR SELECT
    USING (auth.uid() = user_id);

  DROP POLICY IF EXISTS "User marque ses notifications lues" ON notifications;
  CREATE POLICY "User marque ses notifications lues"
    ON notifications FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

  -- Enregistre le token FCM du device connecté
  CREATE OR REPLACE FUNCTION enregistrer_fcm_token(p_token TEXT)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $$
  BEGIN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'Non authentifié';
    END IF;
    UPDATE profiles
    SET fcm_token = NULLIF(trim(p_token), '')
    WHERE id = auth.uid();
  END;
  $$;

  GRANT EXECUTE ON FUNCTION enregistrer_fcm_token(TEXT) TO authenticated;

  -- Crée une notif in-app pour le livreur (appelée à l'assignation)
  CREATE OR REPLACE FUNCTION creer_notification_livreur_choisi(
    p_livreur_id UUID,
    p_course_id UUID,
    p_client_prenom TEXT DEFAULT 'Un client'
  )
  RETURNS notifications
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $$
  DECLARE
    v_notif notifications;
  BEGIN
    INSERT INTO notifications (user_id, titre, corps, type, data)
    VALUES (
      p_livreur_id,
      'Nouvelle course !',
      COALESCE(NULLIF(trim(p_client_prenom), ''), 'Un client')
        || ' vous a choisi sur FasoLiv. Ouvrez l''app pour discuter.',
      'course_assignee',
      jsonb_build_object(
        'course_id', p_course_id,
        'type', 'course_assignee'
      )
    )
    RETURNING * INTO v_notif;

    RETURN v_notif;
  END;
  $$;

  GRANT EXECUTE ON FUNCTION creer_notification_livreur_choisi(UUID, UUID, TEXT)
    TO authenticated, service_role;

  -- Intègre la notif dans demarrer_course_avec_livreur
  CREATE OR REPLACE FUNCTION demarrer_course_avec_livreur(
    p_livreur_id UUID,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_description TEXT DEFAULT NULL
  )
  RETURNS courses
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $$
  DECLARE
    v_user_id UUID := auth.uid();
    v_course  courses;
    v_otp     TEXT;
    v_prenom  TEXT;
  BEGIN
    IF v_user_id IS NULL THEN
      RAISE EXCEPTION 'Non authentifié';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM profiles
      WHERE id = v_user_id AND type_utilisateur = 'demandeur'
    ) THEN
      RAISE EXCEPTION 'Réservé aux clients';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM profiles
      WHERE id = p_livreur_id AND type_utilisateur = 'livreur'
    ) THEN
      RAISE EXCEPTION 'Livreur invalide';
    END IF;

    SELECT prenom INTO v_prenom FROM profiles WHERE id = v_user_id;

    v_otp := lpad((floor(random() * 10000))::int::text, 4, '0');

    INSERT INTO courses (
      demandeur_id,
      livreur_id,
      statut,
      prix_total,
      commission,
      adresse_ramassage_gps,
      adresse_livraison_gps,
      code_otp_validation,
      description_colis,
      point_ramassage
    ) VALUES (
      v_user_id,
      p_livreur_id,
      'propose',
      1000,
      100,
      p_lat::text || ',' || p_lng::text,
      p_lat::text || ',' || p_lng::text,
      v_otp,
      NULLIF(trim(COALESCE(p_description, '')), ''),
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    )
    RETURNING * INTO v_course;

    PERFORM creer_notification_livreur_choisi(
      p_livreur_id,
      v_course.id,
      COALESCE(v_prenom, 'Un client')
    );

    RETURN v_course;
  END;
  $$;

  GRANT EXECUTE ON FUNCTION demarrer_course_avec_livreur(
    UUID, DOUBLE PRECISION, DOUBLE PRECISION, TEXT
  ) TO authenticated;

  -- Realtime notifications (in-app + déclenche affichage local)
  DO $$
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  EXCEPTION
    WHEN duplicate_object THEN NULL;
    WHEN undefined_object THEN NULL;
  END $$;
