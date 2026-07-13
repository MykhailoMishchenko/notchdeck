# NotchDeck — Architecture

Модульная notch-платформа для macOS. Этот файл — источник истины по архитектурным решениям; сверяться с ним при интеграции внешних модулей (fan-control и др.).

## Слои

```
┌─────────────────────────────────────────────┐
│  App (main.swift, AppDelegate)              │  lifecycle, per-screen windows
├─────────────────────────────────────────────┤
│  Notch Layer (NotchWindow, Controller,      │  окно, геометрия, hover,
│  NotchGeometry)                             │  expand/collapse, pill-fallback
├─────────────────────────────────────────────┤
│  Widget Platform (Этап 2)                   │  NotchWidget protocol, registry,
│                                             │  push/poll scheduling, live-lock
├─────────────────────────────────────────────┤
│  Widgets (Этап 3)                           │  media / files shelf / calendar,
│                                             │  позже: fan-control (XPC)
└─────────────────────────────────────────────┘
```

Правило зависимостей: слои знают только о слое ниже. Виджеты не знают об окне; ядро не знает о конкретных виджетах.

## Этап 1 — решения по окну (реализовано)

### Геометрия
- **Primary source — рантайм**: `NSScreen.safeAreaInsets.top > 0` ⇒ экран с чёлкой; ширина выреза = `frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`.
- **Калибровочный словарь** `NotchGeometry.calibrated: [ModelIdentifier: NotchGeometry]` — радиусы углов и fallback-значения. В MVP заполнена единственная запись: `MacBookPro18,1/18,2` (16" M1 Pro/Max 2021), сверенная на реальном железе. Новые модели добавляются одной строкой.
- Экран без чёлки ⇒ `NotchGeometry.pill` — та же вью, форма «pill» у верхней кромки. Кодовый путь один, ветвление только в форме.

### Окно
- `NSPanel` (`.borderless`, `.nonactivatingPanel`): не забирает фокус у активного приложения при hover/кликах.
- `level = .statusBar` — поверх меню-бара; `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` — живёт во всех Spaces и поверх fullscreen-приложений.
- **Окно всегда имеет expanded-размер** — анимируется форма внутри SwiftUI (spring `response 0.38 / damping 0.78`), а не фрейм окна. Ресайз NSWindow в реальном времени дёргается; все зрелые notch-приложения делают так же.
- Следствие: невидимая часть окна перекрывает меню-бар ⇒ `PassThroughHostingView.hitTest` пропускает события мыши насквозь везде, кроме текущей интерактивной зоны (вырез в collapsed / панель в expanded). Зону отдаёт контроллер, а не SwiftUI — единственная точка истины.

### Мультимонитор
- `AppDelegate` держит `[CGDirectDisplayID: NotchWindowController]`, диффит по `NSApplication.didChangeScreenParametersNotification`: подключился экран — создали контроллер (notch или pill — решает `NotchGeometry.detect`), отключился — снесли, поменялся фрейм — пересоздали.

## Этап 2 — протокол NotchWidget (ЧЕРНОВИК, финализируется на Этапе 2)

```swift
protocol NotchWidget {
    var id: String { get }
    var displayName: String { get }
    var collapsedView: AnyView { get }
    var expandedView: AnyView { get }
    var updateInterval: TimeInterval? { get }   // nil = push-based
    func onAppear()
    func onDisappear()
}
```

Планируемые решения (будут уточнены при реализации):
- **WidgetRegistry** — единственная точка регистрации; порядок отображения персистится, drag&drop reorder.
- **Push vs poll**: `updateInterval == nil` ⇒ виджет сам публикует обновления (ObservableObject/Combine); иначе платформа дергает его по таймеру, только пока виджет видим.
- **Live-lock**: механизм `holdExpanded` — виджет сообщает «идёт live-обновление, не сворачивай» (кейс температурных датчиков).
- **External-process-backed widgets** (Этап 4): виджет-обёртка, чей источник данных — XPC/socket к внешнему привилегированному демону. Платформа не требует повышенных прав; entitlements остаются минимальными. Fan-control подключится как обычный `NotchWidget`, дергающий XPC внутри себя.

## Сборка

- SPM executable (без Xcode-проекта); `swift run NotchDeck` для разработки.
- `scripts/bundle.sh [debug|release]` — собирает `NotchDeck.app` (`LSUIElement=true`, ad-hoc подпись). Бандл обязателен для `SMAppService` (автозапуск, Этап 3.5).
