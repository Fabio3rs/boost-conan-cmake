# CVE Security Check - Guia de Verificação de Vulnerabilidades para boost-conan-cmake

Este diretório contém ferramentas abrangentes para verificação de vulnerabilidades CVE (Common Vulnerabilities and Exposures) no projeto boost-conan-cmake.

## 🛡️ Ferramentas Disponíveis

### 1. Script Python Principal - `cve_security_check.py`

**Funcionalidades:**
- ✅ Análise de dependências Conan
- ✅ Verificação de bibliotecas do sistema
- ✅ Escaneamento de submódulos Git
- ✅ Detecção de CVEs conhecidas
- ✅ Recomendações de atualização
- ✅ Relatórios em JSON e texto

**Uso:**
```bash
# Execução básica
python3 scripts/cve_security_check.py

# Salvar relatório em arquivo
python3 scripts/cve_security_check.py --output security_report.txt

# Gerar relatório JSON
python3 scripts/cve_security_check.py --format json --output report.json
```

### 2. Script de Auditoria Bash - `security_audit.sh`

**Funcionalidades:**
- 🔍 Análise de código fonte para padrões perigosos
- 🔐 Detecção de credenciais hardcoded
- 🌐 Análise de segurança de rede
- 📋 Verificação de configurações de build
- 🐳 Auditoria de segurança de containers
- 📁 Análise de permissões de arquivos

**Uso:**
```bash
# Execução padrão
./scripts/security_audit.sh

# Especificar diretório e arquivo de relatório
./scripts/security_audit.sh /caminho/projeto relatorio_seguranca.txt
```

## 📊 Dependências Atualmente Monitoradas

### Dependências Conan (conanfile.txt)
- **poco/1.13.3** - Framework C++ para desenvolvimento de aplicações de rede
- **zlib/1.2.13** - Biblioteca de compressão de dados

### Dependências do Sistema (CMakeLists.txt/Dockerfile)
- **OpenSSL** - Biblioteca criptográfica (CRÍTICO)
- **MySQL C++ Connector** - Conector C++ para MySQL (CRÍTICO)
- **ZLIB** - Biblioteca de compressão
- **Pistache** - Framework HTTP para C++
- **GoogleTest** - Framework de testes

### Submódulos Git
- **CppDbModelTemplate** - Template para modelos de banco de dados
- **cppapiframework** - Framework customizado de API
- **pistache** - Fork do framework HTTP Pistache

## ⚠️ Vulnerabilidades Comuns Detectadas

### CVEs de Alto Risco Conhecidas
1. **OpenSSL**: CVE-2024-2511, CVE-2024-0727
2. **zlib**: CVE-2022-37434 (buffer overflow)
3. **libcurl**: CVE-2024-2398, CVE-2023-46218
4. **MySQL Connector**: CVE-2023-22084

### Padrões de Código Inseguros
- Funções C perigosas: `strcpy`, `sprintf`, `gets`
- Queries SQL dinâmicas (risco de injection)
- Comunicação HTTP não criptografada
- Credenciais hardcoded no código

## 🔧 Configuração do Dependabot

O arquivo `.github/dependabot.yml` configura:
- ✅ Atualizações automáticas semanais
- ✅ Monitoramento de imagens Docker
- ✅ Verificação de submódulos Git
- ✅ Atualizações de GitHub Actions

## 📈 Interpretação dos Relatórios

### Níveis de Severidade
- **CRITICAL**: Vulnerabilidade crítica, ação imediata necessária
- **HIGH**: Alto risco, deve ser resolvida rapidamente
- **MEDIUM**: Risco moderado, planejar correção
- **LOW**: Baixo risco, monitorar e corrigir quando possível

### Exemplo de Saída
```
SUMMARY:
  Total Dependencies: 12
  Vulnerabilities Found: 3
    Critical: 0
    High: 2
    Medium: 1
    Low: 0

VULNERABILITIES:
  [HIGH] OpenSSL
    CVE: CVE-2024-2511
    Description: Cryptographic library
    Recommendation: Update to OpenSSL 3.0.13+ or 1.1.1w+
```

## 🚀 Recomendações de Implementação

### Ações Imediatas
1. **Executar verificação inicial**:
   ```bash
   ./scripts/security_audit.sh
   python3 scripts/cve_security_check.py --output initial_scan.txt
   ```

2. **Configurar monitoramento automatizado**:
   - Habilitar Dependabot no GitHub
   - Configurar alertas de segurança
   - Integrar verificações no CI/CD

3. **Atualizar dependências críticas**:
   ```bash
   # Atualizar pacotes do sistema
   apt update && apt upgrade

   # Revisar conanfile.txt para últimas versões
   # Atualizar submódulos Git
   git submodule update --remote
   ```

### Configurações de Build Seguras

Adicione estas flags ao CMakeLists.txt:
```cmake
# Flags de segurança adicionais recomendadas
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fstack-protector-strong")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D_FORTIFY_SOURCE=2")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wformat -Wformat-security")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIE")

# Linker flags de segurança
add_link_options("-Wl,-z,relro,-z,now")
add_link_options("-pie")
```

### Monitoramento Contínuo

1. **Executar verificações semanalmente**:
   ```bash
   # Criar cron job
   echo "0 2 * * 1 /caminho/para/scripts/security_audit.sh" | crontab -
   ```

2. **Integração com CI/CD**:
   ```yaml
   # .github/workflows/security.yml
   - name: Security Scan
     run: |
       python3 scripts/cve_security_check.py --format json --output security.json
       ./scripts/security_audit.sh
   ```

3. **Alertas automatizados**:
   - Configurar notificações por email
   - Integrar com Slack/Discord
   - Criar issues automaticamente para vulnerabilidades críticas

## 📚 Recursos Adicionais

### Bases de Dados CVE
- [NIST National Vulnerability Database](https://nvd.nist.gov/)
- [MITRE CVE List](https://cve.mitre.org/)
- [GitHub Security Advisories](https://github.com/advisories)

### Ferramentas Complementares
- **git-secrets**: Detectar credenciais em commits
- **semgrep**: Análise estática de código
- **snyk**: Scanning de vulnerabilidades
- **OWASP ZAP**: Teste de segurança de aplicações web

### Práticas de Segurança
1. Nunca committar credenciais no código
2. Usar HTTPS para todas as comunicações
3. Validar todas as entradas do usuário
4. Implementar logging de segurança
5. Realizar revisões de código focadas em segurança
6. Manter todas as dependências atualizadas
7. Implementar princípio de menor privilégio
8. Usar containerização com usuários não-root

## 🆘 Suporte e Contribuições

Para reportar problemas ou sugerir melhorias:
1. Abrir issue no repositório
2. Incluir saída completa dos scripts
3. Descrever o ambiente de execução
4. Anexar logs relevantes

---

**⚡ Última atualização**: Este documento deve ser atualizado sempre que novas vulnerabilidades forem descobertas ou ferramentas forem adicionadas.