import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { createReadStream } from 'node:fs'
import { join } from 'node:path'
import { timingSafeEqual } from 'node:crypto'
import bcrypt from 'bcryptjs'
import jwt from 'jsonwebtoken'
import pg from 'pg'

const PORT = Number(process.env.PORT || 3000)
const DATABASE_URL = process.env.DATABASE_URL
const SOOMA_API_KEY = process.env.SOOMA_API_KEY || ''
const JWT_SECRET = process.env.JWT_SECRET || ''
const PUBLIC_DIR = join(process.cwd(), 'public')
const SQL_FILE = join(process.cwd(), 'sql', '001_init.sql')
const ALLOWED_ORIGINS = (process.env.CORS_ORIGINS || 'https://sooma.raaga-bf.com')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean)

if (!DATABASE_URL) throw new Error('DATABASE_URL manquant')
if (!SOOMA_API_KEY) throw new Error('SOOMA_API_KEY manquant')
if (!JWT_SECRET) throw new Error('JWT_SECRET manquant')

const pool = new pg.Pool({ connectionString: DATABASE_URL })
const lastLocationWebhook = new Map()

function haversineKm(aLat, aLng, bLat, bLng) {
  const R = 6371
  const dLat = ((bLat - aLat) * Math.PI) / 180
  const dLng = ((bLng - aLng) * Math.PI) / 180
  const s1 = Math.sin(dLat / 2) ** 2
  const s2 =
    Math.cos((aLat * Math.PI) / 180) *
    Math.cos((bLat * Math.PI) / 180) *
    Math.sin(dLng / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(s1 + s2))
}

function etaMinutes(driver, dest) {
  if (!driver?.lat || !driver?.lng || dest?.lat == null || dest?.lng == null) return null
  const km = haversineKm(driver.lat, driver.lng, Number(dest.lat), Number(dest.lng))
  return Math.max(1, Math.round((km / 25) * 60))
}

function safeEqual(a, b) {
  const aa = Buffer.from(String(a))
  const bb = Buffer.from(String(b))
  if (aa.length !== bb.length) return false
  return timingSafeEqual(aa, bb)
}

async function readBody(req) {
  const chunks = []
  for await (const c of req) chunks.push(c)
  if (!chunks.length) return {}
  const raw = Buffer.concat(chunks).toString('utf8')
  if (!raw) return {}
  return JSON.parse(raw)
}

function send(res, status, body, headers = {}) {
  const payload = typeof body === 'string' ? body : JSON.stringify(body)
  res.writeHead(status, {
    'content-type': typeof body === 'string' ? 'text/plain; charset=utf-8' : 'application/json; charset=utf-8',
    ...headers,
  })
  res.end(payload)
}

function corsHeaders(req) {
  const origin = req.headers.origin
  const headers = {
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'Content-Type, Authorization, X-Sooma-Key',
    vary: 'Origin',
  }
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    headers['access-control-allow-origin'] = origin
  }
  return headers
}

function soomaAuth(req) {
  const key = req.headers['x-sooma-key']
  const bearer = (req.headers.authorization || '').replace(/^Bearer\s+/i, '')
  return safeEqual(key || '', SOOMA_API_KEY) || safeEqual(bearer || '', SOOMA_API_KEY)
}

function driverAuth(req) {
  const bearer = (req.headers.authorization || '').replace(/^Bearer\s+/i, '')
  if (!bearer || bearer === SOOMA_API_KEY) return null
  try {
    const payload = jwt.verify(bearer, JWT_SECRET)
    if (payload.role !== 'driver' || !payload.sub) return null
    return payload.sub
  } catch {
    return null
  }
}

async function loadJob(id) {
  const { rows } = await pool.query(
    `SELECT j.*, d.name AS driver_name, d.phone AS driver_phone,
            d.lat AS driver_lat, d.lng AS driver_lng, d.heading AS driver_heading
     FROM jobs j
     LEFT JOIN drivers d ON d.id = j.driver_id
     WHERE j.id = $1`,
    [id],
  )
  return rows[0] || null
}

function publicJob(row) {
  if (!row) return null
  const driver = row.driver_id
    ? {
        id: row.driver_id,
        name: row.driver_name,
        phone: row.driver_phone,
        lat: row.driver_lat,
        lng: row.driver_lng,
        heading: row.driver_heading,
      }
    : null
  const dest = row.status === 'assigned' || row.status === 'picked_up'
    ? row.restaurant
    : row.client
  return {
    jobId: row.id,
    externalId: row.external_id,
    status: row.status,
    restaurant: row.restaurant,
    client: row.client,
    note: row.note,
    feeXof: row.fee_xof == null ? null : Number(row.fee_xof),
    driver,
    etaMinutes: etaMinutes(driver, dest),
    updatedAt: row.updated_at,
  }
}

async function notify(row, event) {
  if (!row?.callback_url) return
  if (event === 'location_update') {
    const prev = lastLocationWebhook.get(row.id) || 0
    if (Date.now() - prev < 8000) return
    lastLocationWebhook.set(row.id, Date.now())
  }
  const body = { event, ...publicJob(row) }
  try {
    await fetch(row.callback_url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-fasoliv-event': event },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(5000),
    })
  } catch (err) {
    console.error('webhook', event, err.message)
  }
}

async function migrate() {
  const sql = await readFile(SQL_FILE, 'utf8')
  await pool.query(sql)
}

const server = createServer(async (req, res) => {
  const cors = corsHeaders(req)
  if (req.method === 'OPTIONS') {
    res.writeHead(204, cors)
    res.end()
    return
  }

  const url = new URL(req.url || '/', `http://${req.headers.host}`)
  const path = url.pathname

  try {
    if (req.method === 'GET' && path === '/health') {
      await pool.query('SELECT 1')
      return send(res, 200, { ok: true, service: 'fasoliv-api' }, cors)
    }

    if (req.method === 'GET' && (path === '/version.json' || path === '/fasoliv.apk' || path === '/')) {
      if (path === '/') {
        const html = await readFile(join(PUBLIC_DIR, 'index.html'))
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', ...cors })
        res.end(html)
        return
      }
      if (path === '/version.json') {
        const json = await readFile(join(PUBLIC_DIR, 'version.json'))
        res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', ...cors })
        res.end(json)
        return
      }
      const apk = join(PUBLIC_DIR, 'fasoliv.apk')
      try {
        await readFile(apk)
      } catch {
        return send(res, 404, { error: 'APK pas encore publiée' }, cors)
      }
      res.writeHead(200, {
        'content-type': 'application/vnd.android.package-archive',
        'content-disposition': 'attachment; filename="fasoliv.apk"',
        ...cors,
      })
      createReadStream(apk).pipe(res)
      return
    }

    if (req.method === 'POST' && path === '/v1/drivers/register') {
      const body = await readBody(req)
      const name = String(body.name || '').trim()
      const phone = String(body.phone || '').trim()
      const password = String(body.password || '')
      if (!name || !phone || password.length < 6) {
        return send(res, 400, { error: 'name, phone et password (6+) requis' }, cors)
      }
      const hash = await bcrypt.hash(password, 10)
      const { rows } = await pool.query(
        `INSERT INTO drivers (name, phone, password_hash)
         VALUES ($1, $2, $3)
         ON CONFLICT (phone) DO NOTHING
         RETURNING id, name, phone`,
        [name, phone, hash],
      )
      if (!rows[0]) return send(res, 409, { error: 'Téléphone déjà inscrit' }, cors)
      const token = jwt.sign({ sub: rows[0].id, role: 'driver' }, JWT_SECRET, { expiresIn: '30d' })
      return send(res, 201, { token, driver: rows[0] }, cors)
    }

    if (req.method === 'POST' && path === '/v1/drivers/login') {
      const body = await readBody(req)
      const phone = String(body.phone || '').trim()
      const password = String(body.password || '')
      const { rows } = await pool.query(
        'SELECT id, name, phone, password_hash FROM drivers WHERE phone = $1',
        [phone],
      )
      const driver = rows[0]
      if (!driver || !(await bcrypt.compare(password, driver.password_hash))) {
        return send(res, 401, { error: 'Identifiants invalides' }, cors)
      }
      const token = jwt.sign({ sub: driver.id, role: 'driver' }, JWT_SECRET, { expiresIn: '30d' })
      return send(res, 200, { token, driver: { id: driver.id, name: driver.name, phone: driver.phone } }, cors)
    }

    const driverId = driverAuth(req)

    if (driverId && req.method === 'GET' && path === '/v1/driver/jobs') {
      const { rows } = await pool.query(
        `SELECT j.*, d.name AS driver_name, d.phone AS driver_phone,
                d.lat AS driver_lat, d.lng AS driver_lng, d.heading AS driver_heading
         FROM jobs j
         LEFT JOIN drivers d ON d.id = j.driver_id
         WHERE j.status = 'searching' OR j.driver_id = $1
         ORDER BY j.created_at DESC
         LIMIT 50`,
        [driverId],
      )
      return send(res, 200, { jobs: rows.map(publicJob) }, cors)
    }

    const accept = path.match(/^\/v1\/driver\/jobs\/([0-9a-f-]{36})\/accept$/)
    if (driverId && req.method === 'POST' && accept) {
      const { rows } = await pool.query(
        `UPDATE jobs SET status = 'assigned', driver_id = $2, updated_at = now()
         WHERE id = $1 AND status = 'searching'
         RETURNING id`,
        [accept[1], driverId],
      )
      if (!rows[0]) return send(res, 409, { error: 'Course déjà prise ou introuvable' }, cors)
      const job = await loadJob(accept[1])
      await notify(job, 'driver_assigned')
      return send(res, 200, publicJob(job), cors)
    }

    const statusPath = path.match(/^\/v1\/driver\/jobs\/([0-9a-f-]{36})\/status$/)
    if (driverId && req.method === 'POST' && statusPath) {
      const body = await readBody(req)
      const next = String(body.status || '')
      const allowed = {
        assigned: ['picked_up', 'failed'],
        picked_up: ['in_transit', 'failed'],
        in_transit: ['delivered', 'failed'],
      }
      const job = await loadJob(statusPath[1])
      if (!job || job.driver_id !== driverId) return send(res, 404, { error: 'Course introuvable' }, cors)
      if (next === 'arrived_restaurant') {
        if (job.status !== 'assigned') return send(res, 409, { error: 'Statut incompatible' }, cors)
        await notify(job, 'arrived_restaurant')
        return send(res, 200, publicJob(job), cors)
      }
      if (!(allowed[job.status] || []).includes(next)) {
        return send(res, 409, { error: `Transition ${job.status} → ${next} refusée` }, cors)
      }
      await pool.query('UPDATE jobs SET status = $2, updated_at = now() WHERE id = $1', [job.id, next])
      const updated = await loadJob(job.id)
      const event = next === 'in_transit' ? 'driver_departed' : next === 'delivered' ? 'delivered' : next
      await notify(updated, event)
      return send(res, 200, publicJob(updated), cors)
    }

    if (driverId && req.method === 'POST' && path === '/v1/driver/location') {
      const body = await readBody(req)
      const lat = Number(body.lat)
      const lng = Number(body.lng)
      const heading = body.heading == null ? null : Number(body.heading)
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        return send(res, 400, { error: 'lat/lng requis' }, cors)
      }
      await pool.query(
        'UPDATE drivers SET lat = $2, lng = $3, heading = $4, updated_at = now() WHERE id = $1',
        [driverId, lat, lng, heading],
      )
      const { rows } = await pool.query(
        `SELECT id FROM jobs
         WHERE driver_id = $1 AND status IN ('assigned', 'picked_up', 'in_transit')`,
        [driverId],
      )
      for (const job of rows) {
        await pool.query(
          `INSERT INTO job_positions (job_id, driver_id, lat, lng, heading)
           VALUES ($1, $2, $3, $4, $5)`,
          [job.id, driverId, lat, lng, heading],
        )
        const full = await loadJob(job.id)
        await notify(full, 'location_update')
      }
      return send(res, 200, { ok: true, jobs: rows.length }, cors)
    }

    if (!soomaAuth(req) && path.startsWith('/v1/jobs')) {
      return send(res, 401, { error: 'Clé Sôôma invalide' }, cors)
    }

    if (req.method === 'POST' && path === '/v1/jobs') {
      const body = await readBody(req)
      const externalId = String(body.externalId || '').trim()
      const restaurant = body.restaurant
      const client = body.client
      const callbackUrl = String(body.callbackUrl || '').trim()
      if (!externalId || !restaurant?.lat || !client?.lat || !callbackUrl) {
        return send(res, 400, { error: 'externalId, restaurant, client, callbackUrl requis' }, cors)
      }
      const { rows } = await pool.query(
        `INSERT INTO jobs (external_id, restaurant, client, note, fee_xof, callback_url)
         VALUES ($1, $2::jsonb, $3::jsonb, $4, $5, $6)
         ON CONFLICT (external_id) DO UPDATE SET updated_at = jobs.updated_at
         RETURNING id, external_id, status, (xmax = 0) AS inserted`,
        [
          externalId,
          JSON.stringify(restaurant),
          JSON.stringify(client),
          body.note || null,
          body.feeXof ?? null,
          callbackUrl,
        ],
      )
      const row = rows[0]
      return send(res, row.inserted ? 201 : 200, { jobId: row.id, status: row.status, externalId: row.external_id }, cors)
    }

    const one = path.match(/^\/v1\/jobs\/([0-9a-f-]{36})$/)
    if (req.method === 'GET' && one) {
      const job = await loadJob(one[1])
      if (!job) return send(res, 404, { error: 'Course introuvable' }, cors)
      return send(res, 200, publicJob(job), cors)
    }

    const track = path.match(/^\/v1\/jobs\/([0-9a-f-]{36})\/track$/)
    if (req.method === 'GET' && track) {
      const job = await loadJob(track[1])
      if (!job) return send(res, 404, { error: 'Course introuvable' }, cors)
      const { rows } = await pool.query(
        `SELECT lat, lng, heading, recorded_at
         FROM job_positions WHERE job_id = $1
         ORDER BY recorded_at ASC LIMIT 500`,
        [job.id],
      )
      return send(res, 200, {
        ...publicJob(job),
        trail: rows.map((p) => ({
          lat: p.lat,
          lng: p.lng,
          heading: p.heading,
          ts: p.recorded_at,
        })),
      }, cors)
    }

    const cancel = path.match(/^\/v1\/jobs\/([0-9a-f-]{36})\/cancel$/)
    if (req.method === 'POST' && cancel) {
      const { rows } = await pool.query(
        `UPDATE jobs SET status = 'cancelled', updated_at = now()
         WHERE id = $1 AND status NOT IN ('delivered', 'cancelled')
         RETURNING id`,
        [cancel[1]],
      )
      if (!rows[0]) return send(res, 409, { error: 'Annulation impossible' }, cors)
      const job = await loadJob(cancel[1])
      await notify(job, 'cancelled')
      return send(res, 200, publicJob(job), cors)
    }

    return send(res, 404, { error: 'Introuvable' }, cors)
  } catch (err) {
    console.error(err)
    return send(res, 500, { error: 'Erreur serveur' }, cors)
  }
})

await migrate()
server.listen(PORT, '0.0.0.0', () => {
  console.log(`fasoliv-api :${PORT}`)
})
