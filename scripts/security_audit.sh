#!/usr/bin/env bash
#
# boost-conan-cmake - Enhanced Security Check (Shell)
# - Código-fonte: padrões inseguros (C/C++)
# - Credenciais/SQL/Network: heurísticas
# - Permissões de arquivos
# - Dockerfile (multi-stage): boas práticas e diferenças de base (Ubuntu/Debian vs Alpine)
# - Integrações opcionais: hadolint, gitleaks, semgrep, cppcheck
# - Executa o cve_security_check.py e define exit code por severidade via jq
#
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  security_check.sh [-p DIR] [-o FILE] [--json]
                    [--fail-on {any,low,medium,high,critical}]
                    [--exclude DIR]... [--include DIR]... [--include-build]

Opções:
  -p, --project-root DIR   Diretório raiz do projeto (default: $PWD)
  -o, --output FILE        Arquivo de relatório texto (default: security_report.txt)
  --json                   Também produzir JSON resumido com achados heurísticos
  --fail-on LEVEL          Nível para 'exit 1' (any|low|medium|high|critical). Padrão: any
  --exclude DIR            Diretórios extras para ignorar (pode repetir)
  --include DIR            Diretórios adicionais para inspecionar (pode repetir). Default: src
  --include-build          Inclui diretórios de build na varredura (desabilitado por padrão)
  -h, --help               Mostrar ajuda
EOF
}

# -------------------- defaults / args --------------------
PROJECT_ROOT="$(pwd)"
REPORT_FILE="security_report.txt"
JSON_OUT="false"
FAIL_ON="any"
INCLUDES=("src")
EXCLUDES=("vendor" "third_party" "build" "cmake-build*" ".git" ".vscode" ".idea")
INCLUDE_BUILD="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project-root) PROJECT_ROOT="$2"; shift 2;;
    -o|--output) REPORT_FILE="$2"; shift 2;;
    --json) JSON_OUT="true"; shift;;
    --fail-on) FAIL_ON="${2,,}"; shift 2;;
    --exclude) EXCLUDES+=("$2"); shift 2;;
    --include) INCLUDES+=("$2"); shift 2;;
    --include-build) INCLUDE_BUILD="true"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "arg desconhecido: $1"; usage; exit 2;;
  esac
done

cd "$PROJECT_ROOT"

# include build dirs se flag
if [[ "$INCLUDE_BUILD" == "true" ]]; then
  INCLUDES+=("build" "cmake-build*")
  # e não exclui build
  EXCLUDES=("${EXCLUDES[@]/build}")
  EXCLUDES=("${EXCLUDES[@]/cmake-build*}")
fi

have() { command -v "$1" >/dev/null 2>&1; }
timestamp() { date +"%Y-%m-%dT%H:%M:%S%z"; }

# Preferir rg (ripgrep)
GREP_BIN="grep"
GREP_PCRE_SWITCH="-E"   # manter -E e usar [[:space:]] em vez de \s
if have rg; then
  GREP_BIN="rg"
  GREP_PCRE_SWITCH=""   # não necessário no rg
fi

# Verificar ferramentas opcionais (principalmente para CI)
HADOLINT_AVAILABLE=$(have hadolint && echo "true" || echo "false")
GITLEAKS_AVAILABLE=$(have gitleaks && echo "true" || echo "false")  
SEMGREP_AVAILABLE=$(have semgrep && echo "true" || echo "false")
CPPCHECK_AVAILABLE=$(have cppcheck && echo "true" || echo "false")
JQ_AVAILABLE=$(have jq && echo "true" || echo "false")

# -------------------- saída / helpers --------------------
# inicia relatório
{
  echo "boost-conan-cmake Security Report"
  echo "Generated: $(date)"
  echo "Project Root: $PROJECT_ROOT"
  echo "==============================================="
  echo
} > "$REPORT_FILE"

report_section() { echo "$1" | tee -a "$REPORT_FILE"; }

# coletores de achados para json simples
declare -a FINDINGS_JSON
add_finding_json() { # level, category, message, file(optional)
  local lvl="$1"; local cat="$2"; local msg="$3"; local file="${4:-}"
  local obj="{\"level\":\"$lvl\",\"category\":\"$cat\",\"message\":$(printf '%s' "$msg" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"
  if [[ -n "$file" ]]; then
    obj="$obj, \"file\":$(printf '%s' "$file" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"
  fi
  obj="$obj}"
  FINDINGS_JSON+=("$obj")
}

# grep/rg wrapper
grep_code() { # $1 pattern; $2.. paths (ou usa INCLUDES)
  local pattern="$1"; shift || true
  local paths=("$@")
  [[ ${#paths[@]} -eq 0 ]] && paths=("${INCLUDES[@]}")

  if [[ "$GREP_BIN" == "rg" ]]; then
    # constrói ignores
    local ig=()
    for ex in "${EXCLUDES[@]}"; do ig+=( -g "!$ex" ); done
    rg --no-heading --line-number --color never "${ig[@]}" "$pattern" "${paths[@]}" || true
  else
    # grep clássico: vamos varrer por find, ignorando binários
    local find_args=()
    for ex in "${EXCLUDES[@]}"; do find_args+=( -path "*/$ex/*" -prune -o ); done
    # arquivos comuns de C/C++ + headers e também .cxx/.cc
    find_args+=( -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cxx' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) -print )
    while IFS= read -r f; do
      grep -nI -H ${GREP_PCRE_SWITCH} "$pattern" "$f" || true
    done < <(find "${paths[@]}" "${find_args[@]}")
  fi
}

# ------------------ cabeçalho console -------------------
echo "🛡️  boost-conan-cmake Enhanced Security Check"
echo "=================================="
echo "Project Root: $PROJECT_ROOT"
echo "Report File: $REPORT_FILE"
echo

# ------------------ SOURCE CODE SECURITY ----------------
report_section "SOURCE CODE SECURITY ANALYSIS:"
report_section "=============================="

# 1) Funções perigosas
report_section "Potentially dangerous function usage:"
dangerous_functions=( strcpy strcat sprintf gets scanf strncpy strncat snprintf sscanf system popen exec )
for func in "${dangerous_functions[@]}"; do
  matches=$(grep_code "(^|[^A-Za-z0-9_])${func}[[:space:]]*\\(" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    count=$(printf "%s\n" "$matches" | wc -l | tr -d ' ')
    report_section "  ⚠️  $func: $count occurrences (showing up to 5)"
    printf "%s\n" "$matches" | head -5 >> "$REPORT_FILE"
    add_finding_json "medium" "code" "dangerous function: $func ($count hits)"
  fi
done
report_section ""

# 2) SQL injection (concatenação)
report_section "SQL Injection Risk Analysis:"
sql_patterns=(
  '"SELECT[^"]*"[[:space:]]*\+'
  '"INSERT[^"]*"[[:space:]]*\+'
  '"UPDATE[^"]*"[[:space:]]*\+'
  '"DELETE[^"]*"[[:space:]]*\+'
  '[Qq]uery[[:space:]]*=[[:space:]]*".*\+"'
)
for pat in "${sql_patterns[@]}"; do
  matches=$(grep_code "$pat" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    cnt=$(printf "%s\n" "$matches" | wc -l | tr -d ' ')
    report_section "  ⚠️  Potential SQL concat: $cnt matches"
    printf "%s\n" "$matches" | head -3 >> "$REPORT_FILE"
    add_finding_json "high" "code" "possible SQL injection by string concatenation ($cnt)"
  fi
done
report_section ""

# 3) Credenciais hardcoded (mascarar)
report_section "Credential Security Analysis:"
cred_pats=(
  'password[[:space:]]*=[[:space:]]*["'\''"][^"'\''"]+["'\'']'
  'api[_-]?key[[:space:]]*=[[:space:]]*["'\''"][^"'\''"]+["'\'']'
  'secret[[:space:]]*=[[:space:]]*["'\''"][^"'\''"]+["'\'']'
  'token[[:space:]]*=[[:space:]]*["'\''"][^"'\''"]+["'\'']'
)
for pat in "${cred_pats[@]}"; do
  matches=$(grep_code "$pat" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    cnt=$(printf "%s\n" "$matches" | wc -l | tr -d ' ')
    report_section "  ⚠️  Potential hardcoded credentials: $cnt matches"
    printf "%s\n" "$matches" | sed 's/\(.*:\).*/\1CREDENTIAL_DETECTED/' | head -3 >> "$REPORT_FILE"
    add_finding_json "high" "secrets" "potential hardcoded credentials ($cnt)"
  fi
done
report_section ""

# 4) Rede insegura
report_section "Network Security Analysis:"
network_pats=(
  'http://'
  '\btelnet://'
  'CURLOPT_SSL_VERIFYPEER[[:space:]]*\([[:space:]]*0\)'
  'CURLOPT_SSL_VERIFYHOST[[:space:]]*\([[:space:]]*0\)'
  'SSL_VERIFY_NONE'
)
for pat in "${network_pats[@]}"; do
  matches=$(grep_code "$pat" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    cnt=$(printf "%s\n" "$matches" | wc -l | tr -d ' ')
    report_section "  ⚠️  Insecure network usage ($pat): $cnt occurrences"
    printf "%s\n" "$matches" | head -5 >> "$REPORT_FILE"
    add_finding_json "medium" "network" "insecure network usage: $pat ($cnt)"
  fi
done
report_section ""

# ------------------ DEPENDÊNCIAS (dpkg) ---------------
report_section "DEPENDENCY VERSION ANALYSIS:"
report_section "============================"
if have dpkg; then
  report_section "System Package Versions:"
  get_pkg_ver() {
    local name="$1"
    local v
    v=$(dpkg -l | awk -v n="^ii[[:space:]]+$name[[:space:]]" '$0 ~ n {print $3; exit}')
    echo "${v:-not installed}"
  }
  for pkg in openssl libssl-dev zlib1g-dev libmysqlcppconn-dev libcurl4-openssl-dev; do
    v=$(get_pkg_ver "$pkg")
    report_section "  $pkg: $v"
  done
  report_section ""
fi

# ------------------ SUBMODULES --------------------------
if [[ -f ".gitmodules" ]]; then
  report_section "Git Submodule Security:"
  while IFS= read -r line; do
    if [[ $line =~ url\ =\ (.+) ]]; then
      url="${BASH_REMATCH[1]}"
      if [[ $url =~ ^http:// ]]; then
        report_section "  ⚠️  Insecure HTTP URL: $url"
        add_finding_json "medium" "git" "submodule over HTTP" "$url"
      elif [[ $url =~ github\.com ]]; then
        report_section "  ✓ GitHub URL: $url"
      else
        report_section "  ℹ️  External URL: $url"
      fi
    fi
  done < .gitmodules
  report_section ""
fi

# ------------------ BUILD CONFIG (CMake) ----------------
report_section "BUILD CONFIGURATION SECURITY:"
report_section "=============================="
if [[ -f "CMakeLists.txt" ]]; then
  report_section "Security compilation flags:"
  cm_has() { grep -q "$1" CMakeLists.txt; }
  flags=("_FORTIFY_SOURCE" "fstack-protector" "fsanitize" "Wformat-security" "fPIE" "RELRO" "NX")
  for f in "${flags[@]}"; do
    if cm_has "$f"; then report_section "  ✓ $f: enabled"
    else report_section "  ⚠️  $f: not found"; add_finding_json "low" "build" "missing security flag $f"
    fi
  done
  if grep -q "CMAKE_BUILD_TYPE.*Debug" CMakeLists.txt; then
    report_section "  ⚠️  Debug configuration detected"
    add_finding_json "low" "build" "Debug build type referenced in CMakeLists"
  fi
  report_section ""
fi

# ------------------ PERMISSÕES --------------------------
report_section "FILE PERMISSIONS ANALYSIS:"
report_section "=========================="
dangerous_files=$(find . -type f \( -perm /002 -o -perm /020 \) 2>/dev/null | head -10 || true)
if [[ -n "$dangerous_files" ]]; then
  report_section "Files with world/group write permissions:"
  printf "%s\n" "$dangerous_files" >> "$REPORT_FILE"
  add_finding_json "medium" "permissions" "world/group-writable files present"
else
  report_section "✓ No files with dangerous permissions found"
fi

dangerous_dirs=$(find . -type d -perm /002 ! -perm /1000 2>/dev/null | head -10 || true)
if [[ -n "$dangerous_dirs" ]]; then
  report_section "Directories world-writable without sticky bit:"
  printf "%s\n" "$dangerous_dirs" >> "$REPORT_FILE"
  add_finding_json "medium" "permissions" "world-writable directories without sticky bit"
fi

# fontes com bit executável
susp_exec=$(find src/ \( -name "*.c" -o -name "*.cc" -o -name "*.cxx" -o -name "*.cpp" -o -name "*.hpp" -o -name "*.h" \) -type f -executable 2>/dev/null | head -5 || true)
if [[ -n "$susp_exec" ]]; then
  report_section "⚠️  Source files with executable permissions:"
  printf "%s\n" "$susp_exec" >> "$REPORT_FILE"
  add_finding_json "low" "permissions" "source files marked executable"
fi
report_section ""

# ------------------ DOCKERFILE (multi-stage) ------------
report_section "CONTAINER SECURITY ANALYSIS:"
report_section "============================="
if [[ -f "Dockerfile" ]]; then
  # hadolint se houver
  if have hadolint; then
    report_section "Hadolint:"
    hadolint Dockerfile | tee -a "$REPORT_FILE" || true
    report_section ""
  fi

  # parse multi-stage
  declare -i stage_idx=0
  declare -a STAGE_BASE STAGE_NAME STAGE_USER_FOUND STAGE_HEALTH_FOUND STAGE_WARNINGS

  while IFS= read -r line; do
    # normaliza
    ltrim="$(sed -E 's/^[[:space:]]+//' <<<"$line")"
    upline="$(tr '[:lower:]' '[:upper:]' <<<"$ltrim")"

    if [[ "$upline" =~ ^FROM[[:space:]]+([^[:space:]]+)([[:space:]]+AS[[:space:]]+([A-Za-z0-9._-]+))? ]]; then
      base="${BASH_REMATCH[1]}"
      name="${BASH_REMATCH[3]:-stage$stage_idx}"
      STAGE_BASE[$stage_idx]="$base"
      STAGE_NAME[$stage_idx]="$name"
      STAGE_USER_FOUND[$stage_idx]=0
      STAGE_HEALTH_FOUND[$stage_idx]=0
      STAGE_WARNINGS[$stage_idx]=""
      stage_idx=$((stage_idx+1))
      continue
    fi

    # atributos por estágio (somente se há ao menos um estágio)
    if (( stage_idx > 0 )); then
      cur=$((stage_idx-1))
      # USER
      if [[ "$upline" =~ ^USER[[:space:]]+(.+) ]]; then
        STAGE_USER_FOUND[$cur]=1
      fi
      # HEALTHCHECK
      if [[ "$upline" =~ ^HEALTHCHECK ]]; then
        STAGE_HEALTH_FOUND[$cur]=1
      fi
    fi
  done < Dockerfile

  total_stages=$stage_idx
  if (( total_stages == 0 )); then
    report_section "  ℹ️  No FROM statements found."
  else
    for i in $(seq 0 $((total_stages-1))); do
      base="${STAGE_BASE[$i]}"
      name="${STAGE_NAME[$i]}"
      report_section "Stage [$i] '$name' base: $base"

      # checks por base
      if [[ "$base" =~ :latest($|@) ]]; then
        report_section "  ⚠️  Using ':latest' tag"
        add_finding_json "low" "container" "stage '$name' uses :latest tag" "Dockerfile"
      fi

      # pin por digest
      if [[ ! "$base" =~ @sha256: ]]; then
        report_section "  ⚠️  Not pinned by digest (consider FROM image@sha256:...)"
        add_finding_json "low" "container" "stage '$name' not pinned by digest" "Dockerfile"
      fi

      # USER / HEALTHCHECK
      if [[ "${STAGE_USER_FOUND[$i]}" -eq 0 ]]; then
        report_section "  ⚠️  No USER defined in this stage (defaults to root)"
        add_finding_json "low" "container" "stage '$name' has no USER" "Dockerfile"
      fi
      if [[ "${STAGE_HEALTH_FOUND[$i]}" -eq 0 ]]; then
        report_section "  ⚠️  No HEALTHCHECK in this stage"
        add_finding_json "low" "container" "stage '$name' has no HEALTHCHECK" "Dockerfile"
      fi

      # Regras por distro (heurística)
      base_lc="$(tr '[:upper:]' '[:lower:]' <<<"$base")"
      if [[ "$base_lc" == *ubuntu* || "$base_lc" == *debian* ]]; then
        # apt higiene: update+install na mesma RUN; limpeza de listas
        if grep -qE 'apt(-get)?[[:space:]]+update' Dockerfile && ! grep -q '/var/lib/apt/lists' Dockerfile; then
          report_section "  ⚠️  Consider cleaning apt lists to shrink image"
        fi
      elif [[ "$base_lc" == *alpine* ]]; then
        # apk add sem --no-cache
        if grep -qE 'apk[[:space:]]+add' Dockerfile && ! grep -qE 'apk[[:space:]]+add.*--no-cache' Dockerfile; then
          report_section "  ⚠️  Alpine: use 'apk add --no-cache' to avoid caches"
          add_finding_json "low" "container" "apk add without --no-cache" "Dockerfile"
        fi
      fi
    done

    # regras gerais do arquivo (independente de estágio)
    grep -qE '^\s*ADD\s' Dockerfile && {
      report_section "  ⚠️  Use COPY instead of ADD (unless you need ADD features)."
      add_finding_json "low" "container" "ADD used in Dockerfile" "Dockerfile"
    }

    # detectar cópias multi-stage
    if grep -qE -- '--from=' Dockerfile; then
      report_section "  ✓ Multi-stage COPY detected (--from=...)"
    fi

    # contexto específico solicitado: build em Ubuntu e runtime em Alpine
    # apenas informativo (heurística)
    has_ubuntu_stage=$(grep -iE '^from[[:space:]]+.*ubuntu' Dockerfile || true)
    has_alpine_stage=$(grep -iE '^from[[:space:]]+.*alpine' Dockerfile || true)
    if [[ -n "$has_ubuntu_stage" && -n "$has_alpine_stage" ]]; then
      report_section "  ℹ️  Multi-stage using Ubuntu (build) + Alpine (runtime) detected."
      report_section "     - Verifique compatibilidade glibc vs musl ao copiar binários."
      add_finding_json "info" "container" "ubuntu build + alpine runtime (check musl/glibc)"
    fi
  fi
  report_section ""
else
  report_section "No Dockerfile found."
  report_section ""
fi

# ------------------ RECOMENDAÇÕES FIXAS (resumo) -------
report_section "SECURITY RECOMMENDATIONS (General):"
report_section "==================================="
cat >> "$REPORT_FILE" << 'EOF'
HIGH:
- Use parameterized queries (evitar concatenação) e valide entradas.
- Mantenha toolchain e bibliotecas criptográficas atualizadas.
- Evite credenciais no código (use variáveis de ambiente/secret managers).

MEDIUM:
- Ative flags de hardening (-fstack-protector-strong, -D_FORTIFY_SOURCE=2, -Wl,-z,relro,-z,now).
- Configure scanners de CVE no CI (OSV-Scanner/Trivy/Grype).

LOW:
- Evite :latest e responsabilize imagens por digest.
- Inclua HEALTHCHECK e usuário não-root em todos os estágios do container.
EOF
report_section ""

# ------------------ FERRAMENTAS OPCIONAIS ---------------
if have gitleaks; then
  report_section "Gitleaks scan:"
  gitleaks detect --no-git --source "${INCLUDES[0]}" --redact --report-path gitleaks.json || true
  report_section "  (output em gitleaks.json)"
  report_section ""
fi

if have semgrep; then
  report_section "Semgrep scan (security audit rules):"
  semgrep --quiet --config p/r2c-security-audit --include "${INCLUDES[@]}" || true
  report_section ""
fi

if have cppcheck; then
  report_section "Cppcheck (security/performance):"
  cppcheck --enable=warning,style,performance,portability,security --quiet "${INCLUDES[@]}" 2>>"$REPORT_FILE" || true
  report_section ""
fi

# ------------------ PYTHON CVE CHECKER ------------------
if [[ -f "scripts/cve_security_check.py" ]]; then
  echo "🐍 Running Python CVE checker..."
  PY_JSON="${REPORT_FILE%.txt}_detailed.json"
  if have python3; then
    python3 scripts/cve_security_check.py --project-root "$PROJECT_ROOT" --output "$PY_JSON" --format json || true
    echo "✅ Detailed JSON report generated: $PY_JSON"
  else
    echo "⚠️  Python3 não encontrado; pulando CVE checker Python."
  fi
fi

# ------------------ JSON resumo (heurístico) ------------
if [[ "$JSON_OUT" == "true" ]]; then
  JSON_PATH="${REPORT_FILE%.txt}_summary.json"
  {
    echo '{'
    echo '  "generated": "'"$(timestamp)"'",'
    echo '  "project_root": '"$(python3 - <<PYEOF
import json,sys,os
print(json.dumps(os.getcwd()))
PYEOF
)"','
    echo '  "findings": ['
    for i in "${!FINDINGS_JSON[@]}"; do
      printf "    %s" "${FINDINGS_JSON[$i]}"
      [[ $i -lt $((${#FINDINGS_JSON[@]}-1)) ]] && printf ","
      printf "\n"
    done
    echo '  ]'
    echo '}'
  } > "$JSON_PATH"
  echo "🧾 Summary JSON saved to: $JSON_PATH"
fi

# ------------------ EXIT CODE por severidade ------------
# Preferimos usar o JSON detalhado do Python (contém contagem por severidade)
EXIT_STATUS=0
if have jq && [[ -f "${REPORT_FILE%.txt}_detailed.json" ]]; then
  case "$FAIL_ON" in
    any)      QUERY='.summary.vulnerabilities_found > 0' ;;
    low)      QUERY='(.summary.low_count + .summary.medium_count + .summary.high_count + .summary.critical_count) > 0' ;;
    medium)   QUERY='(.summary.medium_count + .summary.high_count + .summary.critical_count) > 0' ;;
    high)     QUERY='(.summary.high_count + .summary.critical_count) > 0' ;;
    critical) QUERY='.summary.critical_count > 0' ;;
    *)        QUERY='.summary.vulnerabilities_found > 0' ;;
  esac
  if jq -e "$QUERY" "${REPORT_FILE%.txt}_detailed.json" >/dev/null; then
    EXIT_STATUS=1
  fi
else
  # fallback: se houve achados heurísticos relevantes, e FAIL_ON=any
  if [[ "$FAIL_ON" == "any" && ${#FINDINGS_JSON[@]} -gt 0 ]]; then
    EXIT_STATUS=1
  fi
fi

# ------------------ FERRAMENTAS OPCIONAIS (CI) --------
if [[ "$HADOLINT_AVAILABLE" == "true" ]] && [[ -f "Dockerfile" ]]; then
  report_section "DOCKERFILE ANALYSIS (Hadolint):"
  report_section "================================"
  hadolint Dockerfile || report_section "⚠️ Hadolint encontrou problemas no Dockerfile"
  report_section ""
fi

if [[ "$GITLEAKS_AVAILABLE" == "true" ]]; then
  report_section "SECRETS SCAN (Gitleaks):"
  report_section "========================="
  if gitleaks detect --source . --no-git 2>/dev/null; then
    report_section "✅ Nenhum segredo detectado"
  else
    report_section "⚠️ Gitleaks pode ter encontrado segredos potenciais"
    add_finding_json "medium" "secrets" "potential secrets detected by gitleaks"
  fi
  report_section ""
fi

if [[ "$SEMGREP_AVAILABLE" == "true" ]]; then
  report_section "STATIC ANALYSIS (Semgrep):"
  report_section "=========================="
  if [[ -f ".semgrep.yml" ]]; then
    semgrep --config=.semgrep.yml --quiet . || report_section "⚠️ Semgrep encontrou problemas"
  else
    semgrep --config=auto --quiet . || report_section "⚠️ Semgrep encontrou problemas"
  fi
  report_section ""
fi

if [[ "$CPPCHECK_AVAILABLE" == "true" ]] && [[ -d "src" ]]; then
  report_section "C++ STATIC ANALYSIS (Cppcheck):"
  report_section "==============================="
  cppcheck --enable=warning,style,performance,portability --quiet src/ || report_section "⚠️ Cppcheck encontrou problemas"
  report_section ""
fi

# ------------------ resumo final ------------------------
report_section ""
report_section "SCAN COMPLETE"
report_section "============="
report_section "Report saved to: $REPORT_FILE"

# Mostrar status das ferramentas opcionais
report_section ""
report_section "🔧 Optional Tools Status:"
report_section "  Hadolint (Dockerfile): $([[ "$HADOLINT_AVAILABLE" == "true" ]] && echo "✅ Available" || echo "❌ Not available (CI only)")"
report_section "  Gitleaks (Secrets): $([[ "$GITLEAKS_AVAILABLE" == "true" ]] && echo "✅ Available" || echo "❌ Not available (CI only)")"
report_section "  Semgrep (Static): $([[ "$SEMGREP_AVAILABLE" == "true" ]] && echo "✅ Available" || echo "❌ Not available (CI only)")"
report_section "  Cppcheck (C++): $([[ "$CPPCHECK_AVAILABLE" == "true" ]] && echo "✅ Available" || echo "❌ Not available (CI only)")"
report_section "  jq (JSON): $([[ "$JQ_AVAILABLE" == "true" ]] && echo "✅ Available" || echo "❌ Not available")"
report_section ""
report_section "💡 Note: Optional tools are mainly for CI/CD workflows"
report_section "    Local development requires only basic tools (python3, bash, grep)"
report_section ""

echo "🏁 Security analysis complete!"
exit $EXIT_STATUS
