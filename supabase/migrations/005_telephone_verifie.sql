-- Téléphone vérifié par SMS (OTP)
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS telephone_verifie BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN profiles.telephone_verifie IS
  'true après validation du code SMS à l''inscription';
