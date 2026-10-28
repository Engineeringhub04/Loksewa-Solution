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
- [x] ~~**NOTE-7 — Exam Rules Card Icons:** Rules card ko `icon` naam anusar harek card ma farak icon dekhaune (data ma bhayeka naam haru Ionicon naam hun). Admin preview ✅ Done (2026-10-23, Ionicons CDN on-demand load); app side baki thiyo — app le naam bewasta garera sabai card ma fixed shield icon dekhauchthyo.~~ — **Done 2026-10-28 (Phase-2 Cloudflare migration, app side):** `examRuleIconData()` (`lib/services/exam_service.dart`) le stored Ionicon naam lai Material icon ma map garchha (`-outline`/`-sharp` suffix hataayera, common naam haru cover garne), naam namile / invalid bhaye shield fallback; exam_tab ko rules popup le harek card ma tesko aafno icon dekhaauchha.
- [x] ~~**NOTE-8 — Exam Rankings App-Side Scope Fields:** App ko `saveExamAttempt()` le public row `app_exam_rankings` ma examSetId, courseId, subcourseId, uid, name, photoURL, isPro, score, timeTakenSeconds, createdAt lekhthyo, tara ExamSet sangai bhayeka **provinceId, sectionId, contentType** lekhdaaina thiyo — app bata aayeka row haru ma admin ko Province/Section filter, tracker ra Model Type column le kaam gardaina thiyo. Admin side bata ko sambodhan (existing row backfill + dead-row cleanup, button haru hataiyo) ra sambandhit tayari (rules sahit) ✅ 2026-10-23/24 mai sakisakeko thiyo.~~ — **Done 2026-10-28 (Phase-2 Cloudflare migration, app side):** `saveExamAttempt()` aba POST /exam/attempts — payload le ExamSet bata **provinceId, sectionId, contentType** pani ranking row ma pathaaunchha (set nai source of truth), tesaile app-created naya row haru ma pani admin filter/tracker/Model Type sabai kaam garchha.
- [x] ~~**NOTE-9 — Exam Provinces Course/Subcourse Scope (App Side):** Admin panel le `app_exam_provinces` doc haru ma courseIds / subcourseIds array field thapeko thiyo (khali = All), tara app le parse nai gardaina thiyo — `ExamProvince` le id, nameEn, nameNe, order matra parse garthyo, `fetchExamProvinces()` le kunai scope parameter lidaina thiyo, exam_tab le pani sabai province pill haru dekhauchthyo. (Sections ko scope pahile nai pura thiyo — feri nagarne.)~~ — **Done 2026-10-28 (Phase-2 Cloudflare migration, app side):** `ExamProvince` le **courseIds/subcourseIds** pani parse garchha, `fetchExamProvinces({courseId, subcourseId})` le `ExamSection.inScope()` jastai filter garchha (scope list khali/absent bhaye **All** — sadhai dekhine), ra exam_tab le sections lai gareko jasto selected courseId/subcourseId pass garchha.

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

### NOTE-10 — Payment App-Open (Wallet App Cha Bhane SDK Method, Natra Aile Kai Web)
User ko idea (2026-10-24 discuss, 2026-10-25 note add garne order): payment garda **phone ma wallet app (eSewa/Khalti) already installed cha bhane sidhai tyo app khulera payment hos**, chhaina bhane **aile kai WebView web flow** hos.

**Pahile verify garnu parne (implement bhanda agadi, yo kram ma):**
- **Khalti:** Khalti ko Flutter SDK config ma `openInKhalti` flag cha ("WebView kholne ki Khalti app ma kholne" bhanne chhanchha) — test build ma user ko phone ma sachchai app khulchha ki khuldaina + tes pachhi pani worker lookup verify ustai chalna paryo, check garne.
- **eSewa:** pub.dev ko `esewa_flutter` package **WebView matra** ho (ePay v2 form) — tyo app-open ko praman HO hoina. eSewa ko native SDK wa checkout deep-link bata app khulchha ki khuldaina, kun SDK ho pahile chhutyaaune — user le kun app ma eSewa khuleko dekheko ho tyo bata suru garne.

**Badli nahune:**
- Worker-side verify sadhai ustai: `POST /payments/init` + `/payments/verify` — app-open le checkout khulne tarika matra badalchha, bharosa ko nirnaya kahile badlidaina.
- Android pahile; iOS chhuttai test (purano iOS ma web fallback ko seto hune purano tathya ajhai lagu).

**Timing:** mathi ko verify sakiyepachhi matra implement; ahile note matra — user, 2026-10-25

### NOTE-11 — Cloudflare Login (Auth) Migration — Password Claim Flow
Firebase Authentication ka khata haru Cloudflare tira sarne yojana (user ko design 2026-10-28 + assistant ko email-code correction user le swikaareko). App aile public xaina — khata haru khali user kai kehi test ID matra xan, volume sano chha.

**Bhag 1 — Khata ko tathya sarne (password bahek):**
- Firebase Auth bata: **email, uid (thyakkai uही, ek akshar pani naferine), bhaneko date, signup tarika (Google / email-password)** Cloudflare ma sarne.
- Password column **khali (null)** baschha — purano password sardaina.

**Bhag 2 — App login page (Cloudflare version ma, pachi ko kaam):**
- Login page ma **"Login with new password"** jasto link → ustai (duplicate) UI page: pahile **email field matra**.
- Email haale pachhi system le herchha: tyo khata ko **password field null chha bhane** → tyo email ma **6-anka ko code** pathaaune (khata kas ko ho praman — code bina password rakhna dinu hudaina, natra email thahaaune le aru ko khata kabja garna sakchha).
- Code mile pachhi **"Set Your Password"** field dekhinchha → password rakhe pachhi login + password save.
- Ek choti password set bhaye pachhi sadhai normal login; login page le password-nasareko khata lai "wrong password" matra navani claim flow tira pathaaune.

**Trigger niyam (user ko spashta, 2026-10-28):** Set Your Password **password field null bhayeko lai matra** aauchha — provider junsukai hos. Google khata ko pani password hudaina, tesaile tesko email **normal email-login form ma** haale Set Your Password aauchha; **"Continue with Google" button** bata jada chai kei password field dekhiidaina (tyo flow ustai).

**UID:** Cloudflare ma auth hami aafai banauchhau — uid khali text ID ho, purano uid ustai sarne (system le naya banaaune hoina); pachi ka naya signup le pani purano style kai random ID pauchan.

**Timing:** pachi ko Cloudflare migration round ma; ahile note matra — user, 2026-10-28
