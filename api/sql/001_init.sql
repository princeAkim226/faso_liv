-- Base dédiée faso_liv (user faso_liv_app). Ne pas exécuter sur postgres/sooma/syras/merveille.

CREATE TABLE IF NOT EXISTS drivers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  phone         TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  lat           DOUBLE PRECISION,
  lng           DOUBLE PRECISION,
  heading       DOUBLE PRECISION,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS jobs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id   TEXT NOT NULL UNIQUE,
  status        TEXT NOT NULL DEFAULT 'searching'
    CHECK (status IN (
      'searching', 'assigned', 'picked_up', 'in_transit',
      'delivered', 'cancelled', 'failed'
    )),
  restaurant    JSONB NOT NULL,
  client        JSONB NOT NULL,
  note          TEXT,
  fee_xof       NUMERIC(12, 2),
  callback_url  TEXT NOT NULL,
  driver_id     UUID REFERENCES drivers(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_jobs_driver ON jobs (driver_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS job_positions (
  id          BIGSERIAL PRIMARY KEY,
  job_id      UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  driver_id   UUID NOT NULL REFERENCES drivers(id),
  lat         DOUBLE PRECISION NOT NULL,
  lng         DOUBLE PRECISION NOT NULL,
  heading     DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_job_positions_job
  ON job_positions (job_id, recorded_at DESC);
