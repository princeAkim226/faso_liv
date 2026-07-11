// Edge Function : envoie une notification FCM au livreur choisi.
// Deploy: supabase functions deploy notify-livreur
// Secret: supabase secrets set FCM_SERVER_KEY=votre_cle_fcm
//
// Appelée automatiquement par le client après demarrer_course_avec_livreur,
// ou via Database Webhook sur INSERT notifications.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
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
      return new Response(JSON.stringify({ error: 'course_id ou livreur_id requis' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
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

      const nom = [client?.prenom, client?.nom].filter(Boolean).join(' ') || 'Un client'
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

    const fcmKey = Deno.env.get('FCM_SERVER_KEY')
    if (!fcmKey) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: 'FCM_SERVER_KEY non configurée (supabase secrets set FCM_SERVER_KEY=...)',
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      )
    }

    const fcmRes = await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: {
        Authorization: `key=${fcmKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        to: token,
        priority: 'high',
        notification: {
          title: titre,
          body: corps,
          sound: 'default',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        data: {
          type: 'course_assignee',
          course_id: courseId ?? '',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      }),
    })

    const fcmJson = await fcmRes.json()

    return new Response(
      JSON.stringify({ ok: fcmRes.ok, fcm: fcmJson }),
      {
        status: fcmRes.ok ? 200 : 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
