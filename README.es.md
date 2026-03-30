# OpenMac

OpenMac es una app Kanban de agentes IA, pensada para macOS, para planificar, asignar y ejecutar flujos de trabajo.

## Idiomas

- [English](README.md)
- [繁體中文](README.zh-Hant.md)
- [简体中文](README.zh-Hans.md)
- [Français](README.fr.md)
- Español (actual)
- [日本語](README.ja.md)
- [한국어](README.ko.md)

## Capturas

### Tablero Kanban
![OpenMac Kanban Overview](docs/images/kanban-overview.jpg)

### Consola en vivo del agente
![OpenMac Agent Live Console](docs/images/agent-live-console.jpg)

## Caracteristicas

- Flujo Kanban de agentes IA (`To Do`, `In Progress`, `Review`, `Done`)
- Autoasignacion por habilidades y carga
- Ejecucion por lotes de tareas asignadas (`Run Assigned`)
- Opciones runtime: `Local Mock` y `OpenAI Compatible`
- Autenticacion OpenAI compatible: `API Key` o `Codex Bridge`
- PM Planner:
  - Genera tickets ejecutables desde un brief de proyecto
  - Permite editar tickets antes de crearlos
  - Plantillas rapidas (`SaaS Product`, `Desktop App`, `Developer API`)
  - Flujo `Create + Run Assigned`
- Consola live con salida y logs debug copiables
- Recomendaciones de salud del tablero, limites WIP y triage manual
- Importacion/exportacion JSON del workspace
- UI multilenguaje (EN/ZH-TW/ZH-CN/FR/ES/JA/KO), fallback a ingles

## Stack tecnico

- Swift
- SwiftUI
- XCTest / Swift Testing
- Proyecto Xcode (`OpenMac.xcodeproj`)

## Estructura del proyecto

```text
OpenMac/
  Domain/         # modelos, logica de dispatch, motor de planificacion
  ViewModels/     # orquestacion del tablero e integracion runtime
  Views/          # vistas SwiftUI reutilizables
  Localization/   # ajustes y resolucion de idioma
  *.lproj/        # strings localizados
OpenMacTests/     # pruebas unitarias / de logica
OpenMacUITests/   # pruebas UI
```

## Inicio rapido

1. Clona este repositorio.
2. Abre `OpenMac.xcodeproj` en Xcode.
3. Selecciona el scheme `OpenMac`.
4. Ejecuta en `My Mac`.

## Configuracion AI Runtime

### Opcion A: API Key

- Configura `OPENAI_API_KEY` (o `OPENAI_COMPAT_API_KEY`) en el entorno.
- Opcional: define `OPENAI_BASE_URL` si usas un endpoint compatible.

### Opcion B: Codex Bridge

1. Instala Codex CLI o Codex app.
2. Ejecuta `codex login` en Terminal.
3. En la app, selecciona `OpenAI Compatible` + `Codex Bridge`.

## Tests (TDD-friendly)

Ejecutar todos los tests:

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS'
```

Ejecutar un target especifico:

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS' -only-testing:OpenMacTests
```

