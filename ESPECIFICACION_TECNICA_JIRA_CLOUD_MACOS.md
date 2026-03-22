# Especificación Técnica Arquitectónica
## Módulo de Integración Nativo macOS con Jira Cloud

- **Rol emisor**: Lead Systems Architect
- **Tipo de documento**: Especificación técnica (Spec-Driven Development)
- **Alcance**: Diseño arquitectónico y criterios verificables, sin código de implementación
- **Versión**: 1.0
- **Fecha**: 2026-03-22

---

## 1) Contexto, alcance y restricciones

### 1.1 Objetivo
Diseñar un módulo nativo para macOS que permita consultar issues en Jira Cloud con búsqueda JQL, selección múltiple, paginación incremental y representación visual de estado, bajo una arquitectura robusta, segura y preparada para evolución de autenticación.

### 1.2 Plataforma y stack obligatorio
- **SO objetivo**: macOS **13 Ventura o superior**.
- **UI**: SwiftUI (declarative UI) alineado con macOS HIG.
- **Concurrencia**: Swift Structured Concurrency (`async/await`, `Task`, cancelación cooperativa).
- **Arquitectura**: MVVM.
- **Red y autenticación**: Programación orientada a protocolos (POP).
- **Modelado de datos**: `Decodable` con aplanamiento de JSON anidado en DTO.
- **Seguridad**: credenciales en **Keychain Services**. Prohibido almacenar secretos en `UserDefaults`.

### 1.3 Alcance funcional
Incluye:
1. Búsqueda JQL por POST en Jira Cloud.
2. Debouncing de entrada.
3. Selección múltiple nativa de resultados.
4. Paginación por `startAt`/`maxResults` con scroll infinito.
5. Construcción local de URL web de issue.
6. Badge de estado semántico por `statusCategory`.

No incluye:
- Implementación OAuth2 completa (solo diseño preparado).
- Sincronización offline avanzada.

---

## 2) Arquitectura propuesta (A-SPEC)

### 2.1 Vista de alto nivel (MVVM)

**View (SwiftUI)**
- `IssueSearchView`: campo de búsqueda, lista de resultados, estados de carga/error.
- `StatusBadgeView`: presentación tipo cápsula/pill del estado Jira.

**ViewModel**
- `IssueSearchViewModel` (MainActor):
  - estado de UI (`searchTerm`, `items`, `isLoading`, `error`, `selection`, `hasMore`).
  - coordinación de debouncing, paginación y cancelación.
  - construcción de URL web local por issue.

**Model / DTO / Mapper**
- DTOs `Decodable` para respuesta Jira con aplanamiento de JSON nested.
- Entidad de dominio `JiraIssue` simplificada para UI.

**Servicios**
- `JiraAPIClient` (protocolo + implementación URLSession).
- `AuthenticationProvider` (protocolo estrategia de auth).
- `BasicAuthenticationProvider` (inicial).
- `KeychainCredentialStore` para persistencia segura.
- `Logger` con Apple Unified Logging (`OSLog`).

### 2.2 Dependencias y DI
- **Constructor injection obligatorio** en ViewModels:
  - `IssueSearchViewModel(networkService: JiraAPIClientProtocol, authProvider: AuthenticationProvider, logger: LoggerProtocol, clock: ClockProtocol?)`
- Beneficios: testabilidad, desacoplamiento y sustitución futura de estrategia OAuth2.

### 2.3 Contratos de red (POP)
- `AuthenticationProvider`
  - responsabilidad: producir encabezados de autenticación para request saliente.
  - variantes esperadas: Basic (inicial), OAuth2 (futuro).

- `JiraAPIClientProtocol`
  - responsabilidad: ejecutar búsqueda paginada en Jira Cloud y mapear errores técnicos a errores de dominio.

---

## 3) Especificaciones funcionales (F-SPEC)

### F-01 Búsqueda JQL por POST
**Requisito**
- El módulo debe consumir `POST /rest/api/3/search` (no GET) para evitar límites de longitud de URL.

**Construcción JQL dinámica**
- Formato requerido:
  - `assignee = currentUser() AND (summary ~ "*{searchTerm}*" OR key = "{searchTerm}")`
- `searchTerm` debe normalizarse (trim) antes de construir JQL.
- Si `searchTerm` vacío: no disparar búsqueda remota y limpiar resultados locales.

**Payload mínimo**
- `jql`, `startAt`, `maxResults` (=50), y campos mínimos requeridos para UI.

### F-02 Debouncing de entrada (300–500 ms)
**Requisito**
- La búsqueda debe esperar entre 300 y 500 ms tras el último cambio de texto.

**Política recomendada**
- Valor por defecto: **400 ms**.
- Reinicio del temporizador ante cada pulsación.
- Cancelación de tarea previa para evitar respuestas fuera de orden.

### F-03 Selección múltiple nativa
**Requisito**
- La lista de issues debe usar `List(selection:)` vinculada a `Set<IssueID>` en ViewModel.
- Debe respetar comportamiento nativo macOS (Cmd+Click / Shift+Click).

**Persistencia de selección**
- Solo en memoria de sesión de vista.
- Si una issue desaparece por nueva búsqueda, removerla del `Set`.

### F-04 Paginación + scroll infinito
**Requisito**
- Paginación por cursor offset con `startAt` + `maxResults` en lotes de 50.
- Carga incremental al hacer `onAppear` del último elemento visible.

**Reglas**
- Evitar cargas concurrentes (`isLoadingPage` guard).
- Detener cuando respuesta devuelva menos de `maxResults`.
- `startAt` siguiente = total acumulado local.

### F-05 Generación de URL web de issue
**Requisito**
- La URL web se genera localmente en VM con patrón:
  - `https://{user-domain}.atlassian.net/browse/{issueKey}`

**Validaciones**
- Rechazar dominio vacío o inválido antes de abrir URL.
- Rechazar `issueKey` vacío.

### F-06 UI de estado (StatusBadgeView)
**Requisito**
- Componente visual tipo cápsula (pill/capsule).
- Mapeo semántico por `statusCategory` de Jira.

**Mapa semántico base**
- `to do` → neutro/azul grisáceo.
- `in progress` → azul/índigo.
- `done` → verde.
- desconocido → gris fallback.

**Accesibilidad**
- Contraste adecuado y etiqueta textual visible (no solo color).

---

## 4) Especificaciones no funcionales (NF-SPEC)

### NF-01 Mitigación de rate limiting
- Interceptar HTTP **429**.
- Leer header `Retry-After` (segundos o fecha HTTP).
- Reintentar con backoff exponencial con jitter acotado.
- Límite de reintentos recomendado: 3.
- Si excede reintentos: propagar error tipado de rate limit.

### NF-02 Observabilidad (OSLog)
- Registrar errores de red y eventos de control de flujo en `OSLog`.
- No loggear PII ni credenciales (email/token/header Authorization).
- Incluir metadatos seguros: endpoint, status code, duración, intento #.

### NF-03 Estrategia de autenticación
- Definir `AuthenticationProvider` como protocolo de estrategia.
- Implementación inicial: `BasicAuthenticationProvider` usando Base64 `email:token`.
- Preparado para extensión futura a OAuth2 sin romper consumidores.

### NF-04 Inyección de dependencias
- Constructor injection para Network Service y Auth Provider en VM.
- Prohibido acoplar VM a singletons concretos de red/auth.

### NF-05 Manejo de errores centrado
- Mapear errores de `URLSession`, DNS, timeout/offline y API Jira a enum Swift fuertemente tipado.
- El enum debe exponer un mensaje apto para UI y categoría técnica para logging.

---

## 5) Diseño de datos y mapeo DTO

### 5.1 Principio
- Respuesta Jira llega anidada (`issues[*].fields.status.statusCategory...`).
- DTO `Decodable` debe aplanar al modelo de dominio sin exponer estructura REST a la UI.

### 5.2 Modelo de dominio esperado (conceptual)
- `id`
- `key`
- `summary`
- `statusName`
- `statusCategory`

### 5.3 Regla de resiliencia
- Campos opcionales deben tener defaults seguros de presentación para evitar fallo total de render.

---

## 6) Seguridad

### 6.1 Almacenamiento de credenciales
- **Obligatorio**: Keychain Services (`kSecClassGenericPassword` o equivalente).
- **Prohibido**: `UserDefaults`, archivos planos, logs de consola con secretos.

### 6.2 Políticas
- Nunca persistir token en memoria más tiempo del necesario.
- Sanitizar logs para excluir Authorization y payload sensible.
- Validar dominio Atlassian antes de construir URLs y requests.

---

## 7) Flujo de interacción (resumen)
1. Usuario escribe en búsqueda.
2. Debouncer espera 400 ms.
3. VM cancela búsqueda previa si aplica.
4. VM solicita página 0 (`startAt=0`, `maxResults=50`) vía API client.
5. API client añade auth por `AuthenticationProvider`.
6. Mapper convierte DTO `Decodable` a `JiraIssue` plano.
7. View renderiza lista + `StatusBadgeView`.
8. Al aparecer último elemento, VM pide siguiente página.
9. Errores se traducen a enum tipado para UI + OSLog técnico sin PII.

---

## 8) Casos borde (EC)

### EC-01 HTTP 429
- Comportamiento esperado: aplicar `Retry-After` + backoff exponencial + límite de reintentos.
- UI: mensaje de espera/reintento y estado no bloqueante.

### EC-02 DNS por subdominio inválido
- Comportamiento esperado: detectar error de resolución y mapear a error de configuración de dominio.
- UI: sugerir corrección del subdominio.

### EC-03 Keychain corrupto/ilegible
- Comportamiento esperado: capturar error de lectura, invalidar sesión auth actual, solicitar reingreso de credenciales.
- UI: mensaje seguro (sin detalles sensibles).

### EC-04 Timeout / offline
- Comportamiento esperado: mapear a error de conectividad, mantener últimos resultados visibles si existen.
- UI: opción de reintentar.

---

## 9) Criterios de aceptación verificables (AC)

### AC-01 Debouncing
- Dado ingreso rápido de texto (múltiples cambios en < 400 ms),
- cuando se estabiliza entrada,
- entonces se ejecuta **solo 1 request** por ventana de debounce.

### AC-02 Persistencia segura en Keychain
- Dadas credenciales válidas,
- cuando se guardan,
- entonces se recuperan correctamente desde Keychain,
- y no existen secretos equivalentes en `UserDefaults`.

### AC-03 Aplanamiento de datos
- Dada respuesta Jira con estructura nested,
- cuando se decodifica,
- entonces el modelo de dominio expone campos planos necesarios para UI sin dependencia de estructura REST anidada.

### AC-04 Render de colores de estado
- Dado cada `statusCategory` soportado (`to do`, `in progress`, `done`),
- cuando se renderiza `StatusBadgeView`,
- entonces se aplica el color semántico correcto y texto legible.

### AC-05 Paginación incremental
- Dada una búsqueda con más de 50 resultados,
- cuando aparece el último elemento de la página actual,
- entonces se solicita la siguiente página (`startAt += 50`) sin duplicados.

### AC-06 Manejo de 429
- Dado un 429 con `Retry-After`,
- cuando se procesa la respuesta,
- entonces el cliente espera el intervalo indicado y reintenta hasta el límite configurado.

---

## 10) Consideraciones de cumplimiento con macOS HIG
- Preferir controles nativos (`List(selection:)`, `ProgressView`, `Alert`, `Label`).
- Feedback de estados de carga/error claro y no intrusivo.
- Soporte de teclado y selección múltiple estándar de macOS.
- Evitar color como único canal de estado (usar texto + forma + color).

---

## 11) Riesgos y mitigaciones
- **Riesgo**: exceso de requests por escritura continua.  
  **Mitigación**: debouncing + cancelación de tareas.
- **Riesgo**: lockout temporal por rate limiting.  
  **Mitigación**: `Retry-After` + backoff exponencial.
- **Riesgo**: migración futura a OAuth2 con alto acoplamiento.  
  **Mitigación**: Strategy Pattern con `AuthenticationProvider`.
- **Riesgo**: exposición de datos sensibles.  
  **Mitigación**: Keychain obligatorio + logging no-PII.

---

## 12) Definición de terminado (DoD)
Se considera completada la fase de diseño cuando:
1. El equipo valida esta especificación como contrato técnico de implementación.
2. Se aprueban interfaces de protocolo (auth/red/errores) y criterios AC.
3. Se confirma trazabilidad entre F-SPEC, NF-SPEC, EC y AC.

