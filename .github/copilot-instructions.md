# Copilot Instructions

**Scope**: C++ repositories (C++20/23) for APIs/services.
**Goal**: Generate safe, readable, testable, and efficient code aligned with the *C++ Core Guidelines* and **NASA Power of Ten (P10)**.
**Priority**: If these rules conflict with history or prior style, **these rules win**.

# Copilot Quick Rules

- Use **C++20/23**, clean with `-Wall -Wextra -Wpedantic`; prefer STL, no raw `new/delete`.  
- Apply **RAII** (`unique_ptr`/`span`/`string_view`), const-correctness, full initialization.  
- Functions short, cohesive, `[[nodiscard]]` + `noexcept` where applicable.  
- Use `std::expected<T,E>` for recoverable errors; exceptions only for exceptional cases.  
- Follow **CppCoreGuidelines** + **NASA P10**: no unchecked returns, no UB, no deep pointers, no complex macros.  
- No globals; minimal scope; no allocation in hot paths (pre-allocate/pool).  
- HTTP handlers: validate → service → serialize; never access DB/Redis directly.  
- Structured errors `{code,msg,trace_id}`; structured logs (no PII, include `trace_id`).  
- All external calls must have timeout + cancellation support.  
- Code must pass `clang-tidy` (`cppcoreguidelines`, `bugprone`, `performance`, `readability`).  
- **Avoid** pointer arithmetic, complex macros, hidden control flow, global state.  
- **Always** keep warnings=0, tidy clean, and tests (unit+integration) present.

# Detailed Guidelines
---

## Compilation

* Use **C++20/23**. GNU extensions may be enabled, but prefer standard C++ features.
* Code must compile cleanly with `-Wall -Wextra -Wpedantic` (or `/W4`).
* Prefer STL headers and types.

---

## Design

* **RAII ownership**: `std::unique_ptr` by default; `std::shared_ptr` only if needed. Avoid raw `new/delete`.
* **No raw arrays / (ptr,len)**: use `std::span`, `std::string_view`, `std::vector`, or `std::array`.
* **Const correctness**: mark parameters, variables, and methods `const` when possible.
* **Initialization**: initialize all members and use uniform `{}` init.
* **Interfaces**: functions ≤ \~80 lines, cohesive, one responsibility.
* **Error handling**: use `std::expected<T,E>` for recoverable errors; exceptions only for exceptional conditions.
* Mark functions `[[nodiscard]]` and `noexcept` where applicable.
* Prefer composition over inheritance; finalize classes/overrides if possible.
* Prefer ranges/algorithms over manual loops.

---

## NASA Power of Ten (adapted)

* No `goto`; avoid recursion unless bounded.
* Loops must have clear bounds (no unguarded `while(true)`).
* Avoid dynamic allocation after initialization; pre-allocate hot paths.
* Functions must be short, focused, and assert frequently.
* Minimize scope, no unchecked return codes.
* Avoid complex macros; prefer `constexpr`, `enum class`, templates.
* No pointer arithmetic or deep indirection.
* Compile with all warnings; treat warnings as errors in CI.

---

## Style

* **Naming**: `snake_case` for functions/locals, `PascalCase` for types, `SCREAMING_SNAKE_CASE` for constants.
* **Headers**: one per unit; `#pragma once` allowed.
* **Namespaces**: avoid global pollution; prefer `namespace api::v1 { … }`.
* **Includes**: local → project → third-party → STL.
* Format compatible with LLVM `clang-format`.

---

## API/Service Code

* HTTP handlers: validate → domain call → serialize result.
* No direct DB/Redis in controllers; use services/repositories.
* Always validate inputs (types, limits, enums).
* Structured error returns: `{ code, message, trace_id }`.
* Logs: structured, no PII, include `trace_id` and latency.
* External calls: always set timeouts and support cancellation.
* Never serialize raw pointers; validate sizes/required fields.

---

## Reliability & Security

* **No UB**: do not suppress sanitizers without justification.
* Avoid data races: use mutexes/atomics.
* Avoid allocation in hot paths: use `reserve`, SSO, `string_view`.
* Validate input strictly; no logging secrets; no stack traces in prod.

---

## Testing

* Unit + integration tests required for new/changed code.
* Enforce minimum coverage in CI.
* Tests must be deterministic (no real clock/network).

---

## Preprocessor / GNU Extensions

* Avoid logic macros; if unavoidable, provide standard fallback.
* Use `__VA_OPT__` for variadic macros; `, ##__VA_ARGS__` only in compat headers.
* Use `decltype` not `typeof`; statement-expr → lambda IIFE fallback.
* Mark extensions with `// GNU EXTENSION: justify`.

---

## Automation

* Code must pass `clang-tidy` with at least:
  `cppcoreguidelines-*`, `bugprone-*`, `performance-*`, `readability-*`.
* No dead code or unused includes.
* TODOs must have context and task reference (`TODO[ABC-123]: …`).

---

## Handler Reference Layout

```cpp
auto UsersHandler::get_by_id(const Request& req) -> Response {
  const auto id = parse_id(req.path_param("id"));
  if (!id) return http::bad_request("invalid_id");

  auto res = svc_.fetch_user(*id); // std::expected
  if (!res) return http::from_error(res.error());

  return http::ok(dto::User::from_domain(*res));
}
```

---

## DO NOT Generate

* Ignored return values, catch-all exceptions, suppressed errors.
* Mutable global singletons.
* Direct `new/delete`, `malloc/free` in high-level code.
* Macros that obscure control flow.

---

## TL;DR

* **Prioritize** RAII, spans/views, `[[nodiscard]]`, short functions, strict validation, timeouts, structured logs.
* **Avoid** allocations in hot paths, complex macros, pointer arithmetic, global state, exceptions for normal flow.
* **Always** keep warnings = 0, `clang-tidy` clean, and tests present.
