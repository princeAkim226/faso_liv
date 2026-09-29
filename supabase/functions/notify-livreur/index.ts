// Edge Function : push FCM HTTP v1 au livreur choisi.
//
// Secrets :
//   supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON --env-file ...
//   (contenu JSON du compte de service Firebase Admin SDK)
//
// Deploy :
//   supabase functions deploy notify-livreur

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import * as jose from 'https://deno.land/x/jose@v4.15.5/index.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

type ServiceAccount = {
  project_id: string
  client_email: string
  private_key: string
}

async function getFcmAccessToken(sa: ServiceAccount): Promise<string> {
  const pem = sa.private_key.replace(/\\n/g, '\n')
  const privateKey = await jose.importPKCS8(pem, 'RS256')

  const jwt = await new jose.SignJWT({
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(privateKey)

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  const tokenJson = await tokenRes.json()
  if (!tokenRes.ok || !tokenJson.access_token) {
    throw new Error(
      `OAuth token échoué : ${JSON.stringify(tokenJson)}`,
    )
  }
  return tokenJson.access_token as string
}

function loadServiceAccount(): ServiceAccount {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')
  if (!raw) {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT_JSON manquant. '
        + 'supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON=...',
    )
  }
  return JSON.parse(raw) as ServiceAccount
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await req.json()
    const courseId = body.course_id as string | undefined
    const livreurId = body.livreur_id as string | undefined

    if (!courseId && !livreurId) {
      return new Response(
        JSON.stringify({ error: 'course_id ou livreur_id requis' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      )
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    let targetLivreurId = livreurId
    let titre = 'Nouvelle course !'
    let corps = 'Un client vous a choisi sur FasoLiv.'

    if (courseId) {
      const { data: course, error } = await supabase
        .from('courses')
        .select('id, livreur_id, demandeur_id')
        .eq('id', courseId)
        .single()

      if (error || !course?.livreur_id) {
        return new Response(JSON.stringify({ error: 'Course introuvable' }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      targetLivreurId = course.livreur_id

      const { data: client } = await supabase
        .from('profiles')
        .select('prenom, nom')
        .eq('id', course.demandeur_id)
        .maybeSingle()

      const nom =
        [client?.prenom, client?.nom].filter(Boolean).join(' ') || 'Un client'
      corps = `${nom} vous a choisi. Ouvrez FasoLiv pour discuter.`
    }

    const { data: livreur } = await supabase
      .from('profiles')
      .select('fcm_token, prenom')
      .eq('id', targetLivreurId!)
      .maybeSingle()

    const token = livreur?.fcm_token as string | undefined
    if (!token) {
      return new Response(
        JSON.stringify({
          ok: true,
          skipped: true,
          reason: 'Pas de token FCM pour ce livreur',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const sa = loadServiceAccount()
    const accessToken = await getFcmAccessToken(sa)

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: titre,
              body: corps,
            },
            data: {
              type: 'course_assignee',
              course_id: courseId ?? '',
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
            android: {
              priority: 'HIGH',
              notification: {
                channel_id: 'fasoliv_courses',
                sound: 'default',
              },
            },
          },
        }),
      },
    )

    const fcmJson = await fcmRes.json()

    return new Response(JSON.stringify({ ok: fcmRes.ok, fcm: fcmJson }), {
      status: fcmRes.ok ? 200 : 502,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
