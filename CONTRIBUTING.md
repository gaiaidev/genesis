# Contributing

## Geliştirme
* Dal aç: `feat/<özellik>` veya `fix/<konu>`
* Kod kalitesi: `npm run ci:all` yeşil olmadan PR açma.

## Commit Mesajı
* Biçim: `type(scope): açıklama` (örn. `feat(api): add /health`)
* Korumalı dosyalar değiştiyse:
  ```
  Approved-By: <ad>
  ```

## PR Kontrol Listesi
* [ ] Lint & Typecheck yeşil
* [ ] Testler geçiyor
* [ ] Guards (anti-fake + no-padding) OK
* [ ] Perf p95 ≤ 200ms
