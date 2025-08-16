# Genesis (Clean Core)

![CI](https://github.com/gaiaidev/genesis/actions/workflows/ci.yml/badge.svg)
![Release](https://github.com/gaiaidev/genesis/actions/workflows/release.yml/badge.svg)

Modern, temiz ve **padding yok** garantili üretim iskeleti.

## Hızlı Başlangıç
```bash
npm install
npm run dev            # /health @ http://localhost:3002
npm run ci:all         # lint + typecheck + test + guards + perf
npm run compose:safe   # çıktılar: build/genesis_out/
```

## Politikalar
* Korumalı yollar (composer/scripts/CI) için **commit mesajında** `Approved-By: <isim>` şarttır.
* Çıktılar yalnızca `build/` altına yazılır; depo kökü temiz kalır.

## Release
```bash
npm run release:patch  # ci:all geçerse tag + GitHub Release
```
