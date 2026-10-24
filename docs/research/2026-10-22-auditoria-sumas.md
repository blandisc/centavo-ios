# Auditoría de sumas y «Hoy puedes gastar» — 2026-10-22

Commit auditado: `97421b3` (main). Tres revisiones independientes (carga de datos, aritmética, de punta a punta). Solo lectura; las 210 pruebas de CentavoCore pasan. Pendiente de revisión por Claude.

## Resumen
Las sumas son correctas (todo es `Decimal`) para lo que incluyen, y la app carga todos los gastos sin límite. Lo que falla es qué entra al total y algunos cálculos derivados.

## Hallazgos (de más a menos importante)

1. **Con presupuesto, las otras monedas desaparecen del encabezado.** `ExpenseListView.swift:728` (`if allowance == nil, !summary.others.isEmpty`) oculta «+ … aparte». Introducido en #69 (6e6f21a). `ExpenseListView.swift:100-102` pasa solo `summary.primary.amount` al presupuesto. `docs/DECISIONS.md:161` y el comentario en `BudgetPage.swift:45` quedaron desactualizados.
2. **Marcadores de peso no reconocidos.** `CurrencyResolver.swift:7-34` / `MonthSummary.swift:87,91`: «MN», «M.N.», «MXN$», «MN$», «$MXN» se archivan como otra moneda (probado: «319.00 MN» → encabezado $0). Wallet guarda el marcador crudo (`ExpenseRecorder.swift:51`). Arreglo: normalizar a ISO al capturar y agregar esos alias.
3. ✅ **Arreglado.** **«Hoy puedes gastar» casi no baja al gastar hoy.** `BudgetPace.swift:46`: `(budget - spent - reserved) / (days - day + 1)` — lo gastado hoy se reparte entre los días restantes. Probado: $630 → gasto $630 → muestra $567. Arreglo: `max(0, (budget − reserved − gastadoAntesDeHoy) / díasRestantes − gastadoHoy)`.
4. ✅ **Arreglado.** **«Te quedan» (Siri) no resta fijos por venir pero «al día» sí.** `MonthStatus.swift:27/31`, `BudgetStore.swift:33`. Ej.: «Te quedan $4,000: $200 al día» con $2,000 de renta apartados.
5. ✅ **Arreglado.** **«En qué se va» no cuadra con «Llevas».** `MonthSummary.swift:160-162` (`filter { $0.amount > 0 }`), `WhereItGoes.swift:44` suma solo positivos; excluye reembolsos/categorías netas negativas y sin categoría negativa. También `CategoryShare.key` (`MonthSummary.swift:188`) no hace trim y `:92` sí («Café » suma pero no filtra).
6. **Wallet sin símbolo de moneda se pierde.** `WalletNotice.swift:34-37` → nil; `UnreadNotice.swift:16` solo avisa avisos de una línea sin dígitos; `LogWalletNoticeIntent.swift:52` borra el aviso con el siguiente legible. #65 (252e8f7) quitó el rescate on-device; `CHANGELOG.md:12` desactualizado.
7. **Duplicados (5 min).** `CaptureGuard.swift:33-44` descarta dos compras reales iguales (probado) y no une «BBVA» vs «BBVA México» (doble conteo si ambas automatizaciones están activas). `recordByHand` no revisa duplicados.
8. **Fijos con mismo comercio y monto.** `RecurringExpenses.swift:20,36,47`: llave `merchant|amount|año-mes` compartida; solo se registra uno. Arreglo: incluir ID del original.
9. **Encabezados por día** (`ExpenseListView.swift:1015-1028`) solo suman moneda principal.
10. **Menores:** transferencias SPEI enviadas cuentan como gasto (`WalletNotice.swift:198`); guiones vuelven negativo un monto (`AmountParser.swift:42`, riesgo vía Siri); 3 decimales se leen como miles (`AmountParser.swift:57`); filtro de día/categoría no muestra su suma (`FilterRow`); CSV fusiona entradas del mismo segundo (`ExpenseImporter.swift:15-21`); dos iPhone con iCloud pueden duplicar fijos; `expectedToDate` cuenta hoy como transcurrido.

## Lo que está bien
Carga sin límites (`@Query` completo), cortes de mes con la zona del teléfono (Monterrey sin horario de verano), borrar/ocultar tarjetas y categorías (#93) no afecta totales, reembolsos restan, reservas de fijos sin doble conteo, importación CSV exacta.

## Estado
- Arreglados en `fix/hoy-puedes-gastar-en-que-se-va`: #3, #4 y #5.
- Resto: pendiente.
