# NotchDeck

Модульная notch-платформа для macOS (MVP). Область вокруг чёлки MacBook Pro как интерактивное пространство с системой виджетов.

Эталонное железо: MacBook Pro 16" M1 Pro 2021 (`MacBookPro18,1`). Для экранов без чёлки — pill-fallback.

## Запуск

```bash
swift run NotchDeck          # dev
./scripts/bundle.sh release  # собрать NotchDeck.app
```

## Статус

- [x] Этап 1 — каркас notch-окна (hover expand/collapse, pill-fallback, мультимонитор)
- [ ] Этап 2 — система виджетов (`NotchWidget` + registry)
- [ ] Этап 3 — MVP-виджеты: media / files shelf / calendar
- [ ] Этап 3.5 — Settings + автозапуск
- [ ] Этап 4 — задел под fan-control (XPC-backed widgets)

Архитектура: см. [ARCHITECTURE.md](ARCHITECTURE.md).
