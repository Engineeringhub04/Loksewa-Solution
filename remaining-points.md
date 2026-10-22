# Remaining Points

> Yo file = pachi garne kaam ko note matra. Ahile implement hudaina.
> Workflow: "remaining list dinus" → list herne → "yo yo gara" → implement → complete ma sarne.

---

## ✅ Complete

- [x] ~~**NOTE-1 — Blacklist check (pahile ko):** App ko Signup/Login page ma blacklist check add garnu parxa. `app_deleted_users` ma bhayeko (blacklisted) email le app bata feri signup/login garna **PAAUDINA** — aile app le yo check gardaina. Signup + login duitai ma email blacklist ma xa ki xaina herne, xa bhane block garne with message.~~
- [x] ~~**NOTE-2 — Role save (aile ko):** App ko Signup ma `users/{uid}` doc ma `role: 'user'` pani write garnu parxa. Aile `signup_screen.dart` le khali name, displayName, email matra lekhxa — tesaile naya account ko pani role field hudaina. Email-signup write + Google sign-in flow duitai ma `'role': 'user'` thapne.~~

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
Admin website ko Exam Sections edit page ma aba **Description (नेपाली)** field pani chha — English description bata auto-convert bhayera `app_exam_sections/{id}` doc ma `descriptionNe` field ma save hunchha. Tara **app le aile `descriptionNe` padhdai padaina** — student lai sadhai English `description` matra dekhauchha. (Exam Set ko `titleNe` jastai: field admin ma store matra hunchha, app display pachi ko kaam.)

**App ma garnu parne (pachi, ahile hoina):**
- `lib/services/exam_service.dart` ko ExamSection model ma `descriptionNe` parse garne (name ma jastai: `descriptionNe: (fields['descriptionNe'] ?? '').toString()`)
- `lib/screens/learn/exam_tab.dart` ma section description render garda language anusar chhanne: Nepali mode + `descriptionNe` khali chhaina bhane `descriptionNe`, natra `description` — name ko lagi bhayeko pick pattern (`nepali && nameNe.isNotEmpty ? nameNe : nameEn`) jastai
- Test: Nepali language ma section description Nepali mai dekhine, English ma English; `descriptionNe` nabhayeko purano section ma duwai ma English fallback

**Timing:** Arko app update round sangai (admin tira ready chha — field ra converter duwai live)
