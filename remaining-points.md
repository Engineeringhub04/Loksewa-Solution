# Remaining Points

> Yo file = pachi garne kaam ko note matra. Ahile implement hudaina.
> Workflow: "remaining list dinus" → list herne → "yo yo gara" → implement → complete ma sarne.

---

## ✅ Complete

- [x] ~~**NOTE-1 — Blacklist check (pahile ko):** App ko Signup/Login page ma blacklist check add garnu parxa. `app_deleted_users` ma bhayeko (blacklisted) email le app bata feri signup/login garna **PAAUDINA** — aile app le yo check gardaina. Signup + login duitai ma email blacklist ma xa ki xaina herne, xa bhane block garne with message.~~
- [x] ~~**NOTE-2 — Role save (aile ko):** App ko Signup ma `users/{uid}` doc ma `role: 'user'` pani write garnu parxa. Aile `signup_screen.dart` le khali name, displayName, email matra lekhxa — tesaile naya account ko pani role field hudaina. Email-signup write + Google sign-in flow duitai ma `'role': 'user'` thapne.~~
- [x] ~~**NOTE-4 — Website signup platform + Admin Users column:** Website (`loksewa-solution-web`, auth/login.html `saveOrUpdateUser` create branch) le naya users doc ma `platform: 'Website'` lekhne (email + Google duwai flow); admin Users list ma Platform column (field nabhaye 'App').~~ — **Done 2026-10-23:** website commit `e8f7d581` (Cloudflare auto-deploy), admin commit `54df4ddc`.
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

### NOTE-7 — Exam Rules Card Icons
Rules card ko `icon` naam anusar harek card ma farak (realistic) icon dekhaune. Data ma bhayeka naam haru **Ionicon** naam hun (`time-outline`, `wifi-outline`, `phone-portrait-outline`, …).

**Design (settled 2026-10-23): naam batai asali icon load garne — sano mapping table banaune hoina.** Pura set bundle pani garinna; jun naam chahiyo, tehi icon matra on-demand load hunchha.
- **Admin preview — ✅ Done (2026-10-23):** Edit page ko preview le naam anusar ko asali Ionicon CDN bata on-demand load garchha (`cdn.jsdelivr.net/npm/ionicons@7.4.0/dist/ionicons/svg/<name>.svg`, session cache sahit) — aghi ko stem-map resolver hatyo. Naam valid bhayena (404) bhaye matra "?" fallback, jasle aile "yo Ionicon naam nai hoina" bhanne matra bujhauchha. Icon Name field ma type garda real naam haru ko suggestion pani aauchha (tehi package ko `dist/ionicons.json` index ek choti lazy load garera).
- **App side — baki (pachi ko APK round ma):** rules dialog le harek card ko aafno icon naam anusar dekhauune — aile app le naam lai bewasta garchha ra sabai card ma fixed shield icon dekhauchha. Flutter ma Ionicons-style icon font/package bundle garne, wa naam → Material icon map (prayog ma bhayeka naam haru cover garne); naam namile / invalid bhaye shield nai fallback.

**Timing:** app side pachi ko app update round ma (ahile hoina) — user, 2026-10-23

### NOTE-8 — Exam Rankings App-Side Scope Fields
App ko `saveExamAttempt()` (`lib/services/exam_service.dart`) le public row `app_exam_rankings` ma yita field lekhchha: examSetId, courseId, subcourseId, uid, name, photoURL, isPro, score, timeTakenSeconds, createdAt. Tara ExamSet sangai bhayeka **provinceId, sectionId, contentType** lekhdaaina — tesaile app bata aayeka row haru ma admin ko Province/Section filter, tracker ra Model Type column le kaam gardaina (data nai hudaina).

**Fix (pachi ko app round ma):**
- `saveExamAttempt()` le ExamSet bata **provinceId, sectionId, contentType** pani ranking row ma save garne (set nai source of truth ho).
- Tespachhi app-created row haru ma pani admin filter/tracker/Model Type sabai kaam garchha.

**Admin side bata sambodhan — ✅ Sakiyo (2026-10-24):**
- Admin panel ko temporary **"Seed Scope Data"** button le 2026-10-24 ma existing row haru ko exam set bata yahi 3 field backfill garyo, ra **"Delete Unset Data"** button le delete bhaisakeka exam set tira gaayeka (set nai nabhayeka) row haru safa garyo.
- Cleanup sakiyepachhi user ko decision anusar **dubai button tei din hataiyo** — yo NOTE ko app fix ship hunu aghi nai (user le rankings test app side bata garchha).
- Tara yo NOTE ko app fix ajhai baki chha: tyo nabhayesamma app bata **naya** aayeka ranking row haru ma feri provinceId, sectionId, contentType hudaina — tee row haru admin ko Province/Section filter, tracker ra Model Type column ma pardainan. Yo user le bujhera swikaareko chha.

**Sambandhit tayari — ✅ Done (2026-10-23):** admin-side correction (tracker, editor, delete, Bato A) sakiyo; `firebase.rules` ma admin lai `app_exam_rankings` create/update/delete permission disakiyo — user le rules file console ma publish garnu baki chha.

**Timing:** pachi ko app update round ma (ahile hoina) — user, 2026-10-23
