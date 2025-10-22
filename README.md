# KipuBank

**Descripción**  
KipuBank es un contrato inteligente didáctico que permite a los usuarios depositar ETH en bóvedas personales y retirarlo respetando límites por transacción y un límite global del banco (`bankCap`). El diseño enfatiza buenas prácticas de seguridad: errores personalizados, patrón checks-effects-interactions, y protección contra reentrancy.

## Características
- Depositar ETH en una bóveda personal (`deposit()` / receive / fallback).
- Retirar ETH hasta un límite por transacción (`withdrawLimit`).
- Límite global (`bankCap`) fijado en el despliegue.
- Eventos `Deposit` y `Withdraw` para trazabilidad.
- Contadores globales y por usuario de depósitos y retiros.
- Errores personalizados para condiciones revert.
- Funciones: `external payable`, `private`, `external view`.
