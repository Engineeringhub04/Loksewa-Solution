# Remaining Points

> Yo file = pachi garne kaam ko note matra. Ahile implement hudaina.
> Workflow: "remaining list dinus" → list herne → "yo yo gara" → implement → complete ma sarne.

---

## ✅ Complete

- [x] ~~**NOTE-1 — Blacklist check (pahile ko):** App ko Signup/Login page ma blacklist check add garnu parxa. `app_deleted_users` ma bhayeko (blacklisted) email le app bata feri signup/login garna **PAAUDINA** — aile app le yo check gardaina. Signup + login duitai ma email blacklist ma xa ki xaina herne, xa bhane block garne with message.~~
- [x] ~~**NOTE-2 — Role save (aile ko):** App ko Signup ma `users/{uid}` doc ma `role: 'user'` pani write garnu parxa. Aile `signup_screen.dart` le khali name, displayName, email matra lekhxa — tesaile naya account ko pani role field hudaina. Email-signup write + Google sign-in flow duitai ma `'role': 'user'` thapne.~~
- [x] ~~**NOTE-5 — Exam Section Description (नेपाली) App Display:** ExamSection le `descriptionNe` parse garne + exam_tab ko section banner le language anusar description chhanne (NE mode ma descriptionNe, khali bhaye EN fallback; EN mode ma ulto pani fallback).~~ — **Done v1.0.126 (2026-10-23):** `displayDescription(nepali)` ExamSection ma + banner update + tests.
- [x] ~~**NOTE-6 — Exam Rules Field-Matching (App Side):** `fetchExamRules` ko ID-sindhi hataayera field-matching engine — `app_exam_rules` sabai doc ek choti fetch (session cache), array scope normalize (legacy single-string pani), weighted specificity (subcourse 16 > course 8 > province 4 > section 2 > contentType 1; tie ma dherai dimension, ani doc id), card ko title/description language anusar (titleNe/descriptionNe). `firebase.rules` check: `app_exam_rules` read pahile nai `if true` (list sahit milne) — change chaina; one-edit + download-stamp clause haru pani field-exact verify bhaye.~~ — **Done v1.0.126 (2026-10-23).**

---

## 📌 Remaining

### NOTE-3 — Payment Rate Limit
`/payments/*` endpoints (init, verify, recheck, cancel, delete-request) ma rate limit chhaina — spam garera junk record banauna sakinchha. Paisa chori hudaina, tara nuisance + Firebase cost.

**Design:**
- Key = uid + endpoint (auth sabai ma chha, IP chainna)
- Naya collection `app_payments_ratelimit/{uid}` — per endpoint `{count, windowStart}`
- 1-hour sliding window; limit katyo → HTTP 429 `{ok:false, error:'rate_limited'}`
- Limits: init 10/hr, verify 30/hr, recheck 30/hr, cancel 30/hr, delete-request 10/hr
- Extra: 3 ota bhanda badi fresh pending bhayo bhane naya init refuse (`too_many_pending`)
- Rules: worker-only (deny-all), `app_payments` jastai
- App: 2 ota friendly message (`rate_limited`, `too_many_pending`) EN+NE

**Order:** worker helper → rules → app message → tests
**Timing:** Play Store launch agadi (ahile hoina)

### NOTE-4 — Website Platform Field
- Website signup le `users/{uid}` ma `platform: 'Website'` lekhne (app le `'app'` lekhchha — aile subscriptions ma chha, users ma pani)
- Admin website ko **Users page** ma `platform` column dekhaune (App / Website badge)

### NOTE-5 — Exam Section Description (नेपाली) App Display
✅ Complete ma sariyo (v1.0.126, 2026-10-23).

### NOTE-6 — Exam Rules Field-Matching (App Side)
✅ Complete ma sariyo (v1.0.126, 2026-10-23).
