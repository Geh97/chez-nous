// Chez nous : lit les agendas Google (adresse secrète iCal) des membres de l'espace
// de l'utilisateur connecté et renvoie leurs événements. Les adresses ne quittent jamais le serveur.
import ICAL from "npm:ical.js@2";
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const PREFIX = "https://calendar.google.com/calendar/ical/";
const DAY = 864e5;
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

function secretKey(): string {
  try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!; }
  catch { return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!; }
}

type Out = { owner: string; id: string; title: string; allDay: boolean; date?: string; start?: string; end?: string };

function parseFeed(text: string, owner: string, from: Date, to: Date): Out[] {
  const comp = new ICAL.Component(ICAL.parse(text));
  for (const tz of comp.getAllSubcomponents("vtimezone")) ICAL.TimezoneService.register(tz);
  const masters = new Map<string, any>(), exceptions: any[] = [];
  for (const v of comp.getAllSubcomponents("vevent")) {
    const e = new ICAL.Event(v);
    if (e.isRecurrenceException()) exceptions.push(e); else masters.set(e.uid, e);
  }
  for (const ex of exceptions) {
    const m = masters.get(ex.uid);
    if (m) m.relateException(ex); else masters.set(ex.uid + ex.recurrenceId, ex);
  }
  const fromT = ICAL.Time.fromJSDate(from, true), toT = ICAL.Time.fromJSDate(to, true);
  const out: Out[] = [];
  const cancelled = (item: any) => String(item.component.getFirstPropertyValue("status") || "").toUpperCase() === "CANCELLED";
  const push = (item: any, s: any, e: any) => {
    if (cancelled(item)) return;
    const title = item.summary || "(Sans titre)";
    if (s.isDate) {
      const d = s.clone(); let k = 0;
      do { out.push({ owner, id: `${item.uid}|${d.toString()}`, title, allDay: true, date: d.toString() }); d.adjust(1, 0, 0, 0); k++; }
      while (e && d.compare(e) < 0 && k < 31);
    } else {
      out.push({ owner, id: `${item.uid}|${s.toString()}`, title, allDay: false,
        start: s.toJSDate().toISOString(), end: (e || s).toJSDate().toISOString() });
    }
  };
  for (const ev of masters.values()) {
    if (ev.isRecurring()) {
      const it = ev.iterator(); let next, n = 0;
      while ((next = it.next()) && n++ < 20000) {
        if (next.compare(toT) > 0) break;
        const det = ev.getOccurrenceDetails(next);
        if (det.endDate.compare(fromT) < 0) continue;
        push(det.item, det.startDate, det.endDate);
      }
    } else if (ev.startDate && ev.startDate.compare(toT) <= 0 && (ev.endDate || ev.startDate).compare(fromT) >= 0) {
      push(ev, ev.startDate, ev.endDate);
    }
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), { auth: { persistSession: false } });
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "auth" }, 401);
    const { data: u, error: ue } = await admin.auth.getUser(jwt);
    if (ue || !u?.user) return json({ error: "auth" }, 401);

    const { data: me } = await admin.from("members").select("space_id").eq("user_id", u.user.id).maybeSingle();
    if (!me) return json({ events: [], status: {} });
    const { data: mem } = await admin.from("members").select("user_id").eq("space_id", me.space_id);
    const ids = (mem || []).map((m: any) => m.user_id);
    const { data: feeds } = await admin.from("calendar_feeds").select("user_id,url").in("user_id", ids);

    const from = new Date(Date.now() - 62 * DAY), to = new Date(Date.now() + 366 * DAY);
    const results = await Promise.all((feeds || []).map(async (f: any) => {
      try {
        if (!f.url.startsWith(PREFIX)) throw new Error("adresse");
        const r = await fetch(f.url, { redirect: "follow" });
        if (!r.ok) throw new Error("http " + r.status);
        return { uid: f.user_id, ok: true, events: parseFeed(await r.text(), f.user_id, from, to) };
      } catch (_e) {
        return { uid: f.user_id, ok: false, events: [] as Out[] };
      }
    }));
    return json({
      events: results.flatMap((r) => r.events),
      status: Object.fromEntries(results.map((r) => [r.uid, r.ok])),
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
