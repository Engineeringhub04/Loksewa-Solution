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
- [x] ~~**NOTE-3 — Payment Rate Limit:** `/payments/*` endpoints (init, verify, recheck, cancel, delete-request) ma rate limit thiena — spam garera junk record banauna sakinthyo.~~ — **Done 2026-10-28 (Phase-5 payments port, loksewa-api `src/payments.js`):** design jasto thiyo testai — key = uid + endpoint, 1-hour window, D1 table `payment_rate_limits` ma count; limits init 10/hr, verify/recheck/cancel 30/hr, delete-request 10/hr → HTTP 429 `rate_limited`; 3 ota bhanda badi fresh pending (initiated < 1h, same uid+purchaseType) bhaye naya init refuse → 429 `too_many_pending`. Smoke-verified live: 11th init → 429 rate_limited, 4th pending init → 429 too_many_pending. (Original design ko Firestore collection ko satta D1 table — worker Cloudflare ma sareko le.)
- [x] ~~**NOTE-11 — Cloudflare Login (Auth) Migration — Password Claim Flow:** Firebase Authentication ka khata haru Cloudflare tira sarne — email, uid (thyakkai uही), bhaneko date, signup tarika sarne, password column khali (null); email → 6-anka ko code (khata praman) → "Set Your Password" → login + password save. Trigger = password field null bhayeko lai matra (Google khata ko email normal email-login form ma haale pani aauchha; "Continue with Google" button flow ustai).~~ — **Done 2026-10-28:** Bhag 1 + claim flow **Round-1 (v1.0.127)** mai ship bhayo (auth data D1 ma, claim/reset code flow, dual session). Baki raheko auth bhag — **Change Password** (pahile Firebase password matra badlinthyo, CF login password ustai rahanchthyo), **logout ma CF refresh token revoke**, **signup rollback + self-delete ko CF DELETE /auth/account** — **Phase-3 (Profile tree) Cloudflare migration ma pura bhayo (2026-10-28):** ChangePasswordScreen → POST /auth/change-password (arkako session haru revoke), AuthService.logout → POST /auth/logout best-effort, deleteCurrentAccount → CF delete pahile, tes pachi Firebase identity delete best-effort.
- [x] ~~**NOTE-21 — App Popup Correction (Default Popup → AppModalShell):** App bhar ka purana default AlertDialog/simple popup haru global AppModalShell design ma badalne — Notice ko link popup (pahile khali URL + Close matra thiyo, kei khuldaina thiyo) ra Gorkhapatra ko source popup (Close + Copy link) duwai AppModalShell ma: link app bahira browser ma khulne context sahit, URL dekhaune (selectable), **Cancel + Open** button (Open le popup banda garera link external browser ma kholchha; Gorkhapatra ko purano Copy link hataiyo — user order). Sangai app-wide sweep: admin exam-answer confirm, admin report confirm, additional-topic leave + limit, mock-test submit, live-exam join, subject-quiz exit, daily-quiz leave + submit, downloads clear-all, daily-test rules dialog, achievements badge info — sabai AppModalShell ma convert (return value, barrier behavior, button outcome ustai; text haru AppLanguage.tr EN/NE ma). Image viewer, subcourse picker bottom sheet ra already-AppModalShell popup haru ustai chhodiyo.~~ — **Done 2026-11-02 (v1.0.129):** mathi bhane jasto sabai popup AppModalShell ma; lib/ ma AlertDialog/showDialog bhanne default popup baki chhaina (sanctioned image viewer + selection bottom sheet bahek).

---

## 📌 Remaining

### NOTE-10 — Payment App-Open (Wallet App Cha Bhane SDK Method, Natra Aile Kai Web)
User ko idea (2026-10-24 discuss, 2026-10-25 note add garne order): payment garda **phone ma wallet app (eSewa/Khalti) already installed cha bhane sidhai tyo app khulera payment hos**, chhaina bhane **aile kai WebView web flow** hos.

**Pahile verify garnu parne (implement bhanda agadi, yo kram ma):**
- **Khalti:** Khalti ko Flutter SDK config ma `openInKhalti` flag cha ("WebView kholne ki Khalti app ma kholne" bhanne chhanchha) — test build ma user ko phone ma sachchai app khulchha ki khuldaina + tes pachhi pani worker lookup verify ustai chalna paryo, check garne.
- **eSewa:** pub.dev ko `esewa_flutter` package **WebView matra** ho (ePay v2 form) — tyo app-open ko praman HO hoina. eSewa ko native SDK wa checkout deep-link bata app khulchha ki khuldaina, kun SDK ho pahile chhutyaaune — user le kun app ma eSewa khuleko dekheko ho tyo bata suru garne.

**Badli nahune:**
- Worker-side verify sadhai ustai: `POST /payments/init` + `/payments/verify` — app-open le checkout khulne tarika matra badalchha, bharosa ko nirnaya kahile badlidaina.
- Android pahile; iOS chhuttai test (purano iOS ma web fallback ko seto hune purano tathya ajhai lagu).

**Timing:** mathi ko verify sakiyepachhi matra implement; ahile note matra — user, 2026-10-25

### NOTE-12 — QOTD Showing Date: App-Side Auto Nepali Date (Preload Self-Heal)
User ko design (2026-10-29 discuss). Sangai decide bhayeko admin-side design: website le QOTD save garda question ko final `dateKey` bata Nepali (BS) date **auto-fill** garne (naam converter jastai — manual lekheko nachalaune, khali/mis bhaye matra auto); admin side ajhai implement bhayeko **chhaina**. Yo note **app side** ko lagi:

- App ma **Question of the Day page khulne bela**, page ko **preloading animation chalirako samaya bhitra** live question ko `showingDate` check garne:
  - **Xaina bhane:** question ko `dateKey` (English date) bata sahi Nepali (BS) date hisab garera **save garne + tehi dekhaune**.
  - **Wrong xa bhane:** correct Nepali date le **update garera dekhaune**.
- Sabai kaam preload bhitra sakine — user le sidhai sahi Nepali date matra dekhchha (splash → home → QOTD, jaha bata aaye pani).
- **Accuracy:** AD→BS conversion fixed official calendar table bata hunchha — `dateKey` sahi bhaye Nepali date pani **100% sahi** (anuman/hisab hoina, table lookup ho).
- **Implement garda chhutyaaune:** app le save/update garna worker write path chahinchha ki display-matra hisab paryapta hunchha — build round ma decide garne.

**Timing:** ahile note matra — user, 2026-10-29

### NOTE-13 — QOTD Home Card: Farkida Real-Time COMPLETED Flip (App-Side Hook)
**Server side sakisakyo (2026-10-30):** GET /qotd le aba prashna sangai login gareko user ko **result + summary** pani pathauchha — answer disake pachhi QOTD page feri kholda diyeko answer nai dekhauchha (feri dina mildaina), ra home card **pull-to-refresh / app restart** ma COMPLETED hunchha. **Baki yo note app side ko matra ho:**

- **Samasya:** `home_tab` ma QOTD card ko `onPress` **bare `context.push('/question-of-the-day')`** matra ho — QOTD page bata back auda home data **kahile reload hudaina**. Home ko `_load()` initState ra pull-to-refresh ma matra chalne bhayekale, answer diera farkine bitikai pani card **LIVE nai** baschha; refresh/restart pachhi matra COMPLETED flip hunchha.
- **Fix (build round ma):** `/question-of-the-day` route pop bhayepachhi home data **reload** garne — ya ta pura `_load()` feri chalaune, ya ta halka tarika: `fetchQotdDay` matra feri chalayera **qotdStatus matra** refresh garne. App bhitra pahile dekhi bhayeko **bell badge ko shared-notifier pattern** sanga milaera garda pani hunchha (page le status badalne bitikai home le thaha paune).
- **Badli nahune:** server bundle (qotd/question/result/summary/greetings) ustai; yo note le NOTE-12 (showing date) lai chhundaina — tyo chhuttai ho.

**Timing:** ahile note matra — user, 2026-10-30 (server-matra fix garne nirnaya anusar; app hook arko build round ma)

### NOTE-14 — Notice Heading: H1/H2/H3 Size Levels (App Renderer)
**Panel side sakisakyo (2026-10-30):** admin NoticeEditPage ma content blocks aba **visual card editor** bata banchha (heading / text / image cards, image upload + reorder) — blocks ko stored shape ustai chha (`{type:'heading', text}` adi). **Yo note app side ko matra ho:**

- **Samasya:** app ko notice renderer (`notice_detail_screen.dart`) le `heading` block lai **eutai size** ma dekhauchha — `ExpoType.h3`, bold. Block ma level bhanne kura aile chhaina, tesaile H1/H2/H3 jasto farak size sambhav chhaina.
- **Fix (build round ma):** heading block ma optional **`level` field (1 | 2 | 3)** support garne — `level` anusar H1/H2/H3 sizes (ExpoType scale bata) ma render garne; `level` nabhayeko purano block aile kai size (h3) mai dekhauchha (backward compatible).
- **Tespachhi:** panel editor ko Heading card ma level chhanne option (H1/H2/H3) thapne — data shape ma `level` save hunchha; tapasamma panel le heading eutai rakchha.
- **Badli nahune:** aru block types (text ko `**bold**` + auto-link, image block, `[img:KEY]` token) ustai.

**Timing:** ahile note matra — user, 2026-10-30

### NOTE-15 — Home Banner Targeting: targetSubcourseIds Honor Garne (App Renderer)
**Panel + server side sakisakyo (2026-10-30, Section 9.3):** admin Home Banners ma aba **Course/Sub-course targeting** chha — banner doc ma `targetSubcourseIds` array save hunchha (Notices kai pattern), ra worker GET /banners le doc jasto chha testai pathauchha. **Yo note app side ko matra ho — app le aile yo field padhdaina, tesaile targeted banner pani sabai lai dekhauchha jabasamma yo fix hudaina:**

- **Niyam:** `targetSubcourseIds` **empty (wa field nai nabhayeko) = All users** — login gareko ra **guest** sabai lai dekhauchha. **Non-empty = tyo list ma subcourseId bhayeko login user lai matra** dekhauchha; guest le All-targeted banner matra dekhauchha.
- **Fix (build round ma):** `home_tab` le banners filter garda yo niyam lagaune — user ko `subcourseId` sanga match garne; list bahira ko user/guest lai non-empty-target banner **hide** garne. Order (worker le `order` asc pathauchha) ustai rakhne.
- **Badli nahune:** banner ko aru field haru (heading/subheading/backgroundColor/imageLink/linkUrl) ustai; targeting nabhayeko purano banner sabai lai dekhine nai rahanchha (backward compatible).

**Timing:** ahile note matra — user, 2026-10-30

### NOTE-16 — Home Banner Expiry: expiresAt Bitisake Pachhi App Ma Hide Garne (App Renderer)
**Panel + server side sakisakyo (2026-10-30, 9.3 expiry follow-up):** admin Home Banner editor ma aba **optional Expiry Date & Time** chha — banner doc ma `expiresAt` (ISO instant) save hunchha, **blank = permanent** (kahile expire hudaina). Editor ma BS (Nepali) date+time auto-display ra 'Expired Time' live-countdown card pani chha, ra list ma Expiry + Expired Time column haru chhan. Worker GET /banners le doc jasto chha testai pathauchha (naya column `expiresAt` set bhaye sangai aauchha). **Yo note app side ko matra ho — app le aile yo field padhdaina, tesaile expired banner pani app ma dekhai rahanchha jabasamma yo fix hudaina:**

- **Niyam:** `expiresAt` **blank/nabhayeko = permanent** — sadhai dekhauchha. `expiresAt` **future ma = dekhauchha**; `expiresAt` **bitisakeko (past) = app ma bilkulai dekhauudaina** (banner list batai hide).
- **Fix (build round ma) — dui madhye euta chhanne:**
  1. **App-side filter:** `home_tab` / banner fetch le render garnu aghi `expiresAt` check garne — past bhaye skip garne. Sajilo, tara purano app version haru ma expired banner dekhai rahanchha.
  2. **Worker-central filter (sifaris):** GET /banners le nai past-`expiresAt` row haru **filter garera** pathaune — sabai app version ma ekai choti lagu hunchha, app update napari pani purano app le expired banner paaudaina. Blank/future row ustai pathaune.
- **Badli nahune:** banner ko aru field haru (heading/subheading/backgroundColor/imageLink/linkUrl/order/targetSubcourseIds) ustai; expiry nabhayeko purano banner sadhai dekhine nai rahanchha (backward compatible).

**Timing:** ahile note matra — user, 2026-10-30

### NOTE-17 — Developers: Panel-Le Rakheko Developer App Ma Na-Dekhne (Slider Chhaina) + isActive Show/Hide (App Renderer)
**Panel + server side sakisakyo (2026-10-30, 9.4):** admin Developers page le aba asali field haru nai edit garchha — `name`, `title`, `description`, `bio`, `photoUrl`, `viewUrl`, `isActive` (Show in App tick box), `createdAt`, `updatedAt` — ra worker GET /developers le **sabai** row haru pathauchha (order as stored). **Tara app ma panel-bata thapeko naya developer dekhidaina — karan app side ma chha (praman sahit):**

- **Karan:** `lib/screens/learn/home_tab.dart` le developers lai **euta matra** variable ma rakhchha — `developer = devs.first` — ra **euta matra** `DeveloperCard` render garchha. App ma developers ko **slider/carousel nai chhaina** (PageView carousel banner ko lagi matra chha — `widgets/home/banner_carousel.dart`). GET /developers le sabai row pathaye pani app le **pahilo row matra** dekhauchha; row haru stored order ma aauchhan, tesaile purano row (kishan-raut) sadhai pahilo hunchha ra pachhi thapeko developer kahile dekhidaina.
- **Fix (build round ma):**
  1. **Slider banaune:** banners jastai — GET /developers ka **sabai** (dekhaune) row haru lai auto-slide hune carousel ma render garne (DeveloperCard pratyek row ko lagi: `name`, `description`, `photoUrl`, `viewUrl` — field naam haru aile kai ustai).
  2. **isActive honor garne:** panel ma naya **Show in App** tick box chha — doc ma `isActive` save hunchha. **Niyam: `isActive` nabhayeko (absent) = DEKHAUNE** (purana row haru ma yo field nai chhaina, tiniharu dekhai rahanuparchha); `isActive == false` bhaye matra tyo developer lai slider bata hide garne. (App kai idiom ho — plans/theory ma `!= false` bhanera check gare jastai.)
- **Badli nahune:** worker GET /developers ustai (sabai row pathauchha — filter app le garne); panel ka field naam haru ustai; `links` field panel bata hataieko chha (app le kahile padhena, sabai row ma empty thiyo) — app le teslai khojne hoina.

**Timing:** ahile note matra — user, 2026-10-30

### NOTE-18 — GK & PM Topics: targetSubcourseIds Honor Garne (App Renderer)
**Panel + server side sakisakyo (2026-10-30, 8.5 amendment):** admin 'GK & PM Topic Data' page le aba pratyek **topic entry bhitra** nai Course/Sub-course targeting rakhchha — GK/PM page doc (`app_additional_feature_pages/{gk|pm}__all__all`) ko `topics[]` bhitra ko pratyek entry ma `targetSubcourseIds` (sub-course id haru ko array) save hunchha. Worker GET /features/:featureId le doc jasto chha testai pathauchha — topics haru ma yo field set bhaye sangai aauchha. **Yo note app side ko matra ho — app le aile yo field padhdaina, tesaile targeted topic pani sabai lai dekhai rahanchha jabasamma yo fix hudaina:**

- **Niyam:** `targetSubcourseIds` **nabhayeko (absent) wa khali (empty) = All** — sabai lai dekhauchha, login nagareko guest lai pani. `targetSubcourseIds` **non-empty bhaye:** topic tyo bela matra dekhauchha jab **login gareko** user ko `subcourseId` tyo list bhitra chha; guest lai tyasto topic **dekhauudaina** (guest sanga sub-course nai hudaina).
- **Fix (build round ma):** `additional_feature_home.dart` ko topic list — aile `isPublished !== false` filter matra chha; tesma mathiko scope check thapne (signed-in user ko subcourseId sanga match garne; user context nabhaye All-targeted topic matra). Order/sort ustai.
- **Badli nahune:** topic ko aru field haru (titleEn/titleNp/slug/order/questionCount/questionBankId) ustai; targeting nabhayeko purano topic sabai lai dekhine nai rahanchha (backward compatible).

**Timing:** ahile note matra — user, 2026-10-30

## NOTE-19 — Onboarding: append database slides after the built-ins (app round)
Today `_loadRemoteSlides` REPLACES the 4 hardcoded slides only when /onboarding returns >=4 shown rows; with 0-3 rows the database slides are invisible. Desired (user's model, 2026-10-31): the 4 built-ins ALWAYS show first (orders 1-4, bundled, fast), and database slides (orders 5+) APPEND after them in order. The worker already filters hidden (enabled=false) rows server-side. While the splash + first built-in slides are on screen, the app must background-prefetch and disk-cache the database slides' images (deadline-guarded, never blocks the built-ins) so slides 5+ appear without delay and later opens are instant from cache. Implement when the app round is ordered.

## NOTE-20 — Onboarding: honor per-slide color + >4-slide chrome (app round)
Database slides now carry a `color` field (admin ColorField) which the app does not read (palette is hardcoded cream/navy). Honor `color` per slide when present (fallback = current palette). Also with more than 4 slides: Skip currently jumps to index 3 and the morph-CTA timing assumes 4 pages — make both follow the real slide count.
