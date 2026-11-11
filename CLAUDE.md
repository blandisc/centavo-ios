# CLAUDE.md

Guía para agentes que trabajan en este repo.

## Qué es
Centavo (en el iPhone se llama **Al día**; decisión del 2026-10-17): tracker de gastos minimalista para iOS. El identificador y el código siguen como Centavo. Captura cada pago de Apple Wallet con la automatización «Transacción» de Atajos, que llama al App Intent `LogExpenseIntent`. Offline y on-device. Decisiones en [docs/DECISIONS.md](docs/DECISIONS.md): léelas antes de proponer algo que las toque y agrega las nuevas en el mismo PR.

## Arquitectura
- `Packages/CentavoCore` — lógica pura (Foundation). Todo lo que se pueda probar sin app va aquí, con `swift test`.
- `Centavo/` — app SwiftUI. `Model/` (SwiftData, `Store.container` compartido por UI e intent), `Intents/` (App Intents), `Screens/`, `App/`.
- El `.xcodeproj` se genera con `xcodegen generate`; nunca se versiona.

## Verificar
Se trabaja como Orbital (decisión del dueño, 2026-11-02: «tú tardas demasiado»):
- **Directo a `main`.** Sin rama ni PR: cambio → `Tools/verify.sh` (lint, `swift test` y build; unos minutos) → commit → push. La CI corre después, sin esperarla; si falla, se arregla en el siguiente commit.
- **Simulador solo para lo que cambió:** las 2–4 pruebas de interfaz de esa pantalla, nunca la suite completa (~35 min). La suite completa corre sola en GitHub al entrar a `main`; se revisa su resultado al día siguiente, no se espera.
- **Revisión independiente con un agente solo si puede perder o corromper datos** (guardado, respaldo, migraciones, «Mi dinero»). Textos, animaciones y pantallas, no.
- Builds con `-jobs 4`, máximo 2 en la Mac sumando sesiones, y `-derivedDataPath /tmp/dd-centavo` (`verify.sh` ya lo hace).
- La CI tiene tres partes: «Pruebas y build» (compila la versión **Release** y dice cuánto pesa), «Pruebas de datos» (`CentavoTests`: guardado, captura, fijos y respaldo) y el simulador en dos máquinas (capturas y flujos), que no se cancela con un push nuevo.

## Diseño
**Lectura obligatoria antes de cualquier trabajo de interfaz: [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md)** (tokens, componentes, receta de pantalla nueva, reglas «nunca», Dynamic Type). Las pantallas se arman solo con tokens de `Centavo/Theme/` y componentes de `Centavo/Components/`; `Tools/lint-design.sh` (en `verify.sh` y en la CI de cada PR) falla con cualquier número, tamaño de letra o color suelto.
Estilo **«Noche ticket»** aprobado por el dueño: modo oscuro forzado, acento latón, tipografía de ticket (IBM Plex Mono). Colores, tipografía, espacios, radios, tamaños, opacidades y animaciones viven en `Centavo/Theme/`; nunca se escriben sueltos en una pantalla.
La **estructura es nativa de Apple** (Human Interface Guidelines): `NavigationStack` con barra superior e inferior del sistema, `List` con `swipeActions`, `Form`, `Menu`, hojas y botones estándar. En iOS 26 eso es Liquid Glass sin código extra: **no lo tapes con piezas propias** (barras o botones hechos a mano). Lo que se viste (fondos, tipografía, colores) usa los tokens de `Theme`.
- Cuidado: dentro de un `Button` el estilo jerárquico (`.primary`) sigue el acento; usa colores explícitos de `Theme`.
- La referencia visual son las **capturas del simulador de la CI** (artefacto `capturas`; las de los flujos, en `capturas-flujos`). Los bocetos están en el lienzo: https://claude.ai/artifact/EuRdR9c1mQ4nNivNwQGVYN
- Si una petición de diseño puede leerse de dos maneras, **pregunta antes de cambiar lo aprobado**. Detalle en [docs/DECISIONS.md](docs/DECISIONS.md).

## Reglas
- **Sin servidor propio.** Ni servidor, ni telemetría, ni cuenta de Centavo. La única red es el iCloud privado de la persona, que sincroniza el sistema (decisión del 2026-10-15); la app no hace llamadas por su cuenta.
- **Minimalismo.** Antes de agregar una pantalla o un ajuste, pregunta si cabe en lo que ya existe.
- **Componentes nativos** de SwiftUI y estilos del sistema (Dynamic Type, modo oscuro). Nada de tamaños de fuente fijos.
- **Copy en es-MX**, sin suponer género.
- Commits directos a `main` con un mensaje que diga qué cambia para la persona. Entrada en CHANGELOG para cambios visibles.

## Tablero
Multica, workspace **Centavo** (prefijo `CEN`). Usa `--workspace-id` o `multica workspace switch centavo` antes de crear issues. Estados: todo → in_progress → in_review → done.
