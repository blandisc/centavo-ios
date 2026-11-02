# Formato de «Mi dinero» para importar

Lo usa «¿Lo tienes en Excel?» (paso 1 de la primera vez en «Mi dinero»). La app copia unas instrucciones; la IA de la persona las sigue con su Excel y devuelve este formato; la persona lo pega o lo sube, lo revisa y lo guarda. Al día nunca recibe el Excel. El lector vive en `MoneyImport` (CentavoCore) y las instrucciones las genera `MoneyImport.instructions(main:)`.

## Columnas

`tipo,nombre,institucion,moneda,monto,tasa_anual,tipo_cambio,repite`

| Columna | Qué lleva |
|---|---|
| `tipo` | `cuenta`, `inversion`, `tarjeta`, `prestamo`, `otros` (otra deuda), `me_deben`, `por_caer`, `ingreso`. Se aceptan sinónimos en español e inglés (`ahorro`, `credit card`, `salary`…). |
| `nombre` | Corto, como en el Excel. |
| `institucion` | Banco, tarjeta o lugar (`Nu`, `Amex`). Opcional. |
| `moneda` | Código de tres letras. Vacío = la moneda principal. |
| `monto` | Positivo, punto decimal. Cuentas: saldo de hoy; deudas: lo que se debe hoy; ingresos: lo que entra al mes. Se tolera `$` y comas de miles; «k», «mil» o «M» no se leen y quedan para revisar. |
| `tasa_anual` | En %, solo el número. Rendimiento en cuentas e inversiones, interés en tarjetas y préstamos. Una fracción (0.105) se lee como 10.5 % y se avisa. |
| `tipo_cambio` | Cuántas unidades de la moneda principal vale 1 de la moneda de la fila. Solo si viene en el Excel; si falta, la revisión lo pide. Si trae varios distintos para la misma moneda, la revisión deja elegir. |
| `repite` | `si` en ingresos. Un ingreso de una sola vez queda para revisar: si aún no llega, se cambia a `por_caer`. |

Separadores aceptados: coma, punto y coma, tabulador o tabla de Markdown. Un bloque ```` ``` ```` alrededor se ignora; las líneas que empiezan con `#` son notas de la IA y se muestran en la revisión. El CSV de gastos (`Fecha, Comercio, …`) se reconoce y se manda a Ajustes.

**Más adelante:** el mismo formato con una columna `corte` (mes) y `movimiento` (inversiones) cargará la historia de cortes.
