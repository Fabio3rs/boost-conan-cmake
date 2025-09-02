# Política de Segurança

## Versões Suportadas

Este projeto segue uma política de segurança para as seguintes versões:

| Versão | Suporte de Segurança |
|--------|----------------------|
| main   | ✅ Suporte ativo     |
| tags   | ✅ Suporte por 90 dias após release |

## Reportando Vulnerabilidades

### Como Reportar

Se você descobrir uma vulnerabilidade de segurança, por favor **NÃO** abra uma issue pública. Em vez disso:

1. **Email**: Envie detalhes para fabio3rs@gmail.com
2. **GitHub Security**: Use o [GitHub Security Advisory](https://github.com/Fabio3rs/boost-conan-cmake/security/advisories) (preferido)
3. **Assunto**: Use o prefixo `[SECURITY]` no email

### Informações Necessárias

Por favor inclua as seguintes informações no seu reporte:

- **Descrição**: Descrição clara da vulnerabilidade
- **Impacto**: Potencial impacto de segurança
- **Reprodução**: Passos detalhados para reproduzir a vulnerabilidade
- **Ambiente**: Versões do sistema, compilador, dependências
- **Mitigação**: Sugestões de correção, se houver

### Processo de Resposta

#### Cronograma

- **Confirmação**: 48 horas para confirmação do recebimento
- **Análise**: 7 dias para análise inicial e classificação de severidade  
- **Correção**: 
  - **Crítica**: 24-48 horas
  - **Alta**: 7 dias
  - **Média**: 30 dias
  - **Baixa**: 90 dias

#### Classificação de Severidade

- **Crítica**: Execução remota de código, escalação de privilégios
- **Alta**: Bypass de autenticação, exposição de dados sensíveis
- **Média**: Injeção limitada, DoS, vazamento de informações  
- **Baixa**: Problemas de configuração, informational

### Política de Divulgação

1. **Correção Privada**: Desenvolvemos correção em repositório privado
2. **Verificação**: Testamos a correção com o reportador (se disponível)
3. **Release**: Publicamos correção em release de segurança
4. **Advisory**: Publicamos advisory com créditos ao descobridor
5. **Divulgação**: Após 90 dias, detalhes podem ser divulgados publicamente

### Reconhecimento

Reportadores de vulnerabilidades válidas serão reconhecidos em:

- Release notes da correção
- GitHub Security Advisory
- Arquivo CONTRIBUTORS.md
- Hall of Fame de segurança (quando implementado)

## Recursos de Segurança do Projeto

### Análise Contínua

- ✅ **GitHub Dependabot**: Atualizações automáticas de dependências
- ✅ **CVE Scanner**: Verificação de vulnerabilidades conhecidas  
- ✅ **Trivy Scanner**: Análise de containers e filesystems
- ✅ **Security Audit**: Verificação de padrões de código inseguros
- ✅ **SARIF Upload**: Integração com GitHub Security tab

### Build Seguro

- ✅ **Clang/GCC**: Compiladores modernos com warnings habilitados
- ✅ **Static Analysis**: clang-tidy para análise estática
- ✅ **Dead Code Removal**: Eliminação de código não utilizado
- ⚠️ **Hardening Flags**: Em processo de implementação

### Container Security

- ✅ **Multi-stage Builds**: Redução de superficie de ataque
- ✅ **Minimal Runtime**: Base Alpine para runtime
- ✅ **No Root**: Execução como usuário não-privilegiado
- ✅ **Dependency Scanning**: Análise de imagens base

## Configurações Recomendadas

### Para Desenvolvimento

```bash
# Clone com verificação de assinatura
git clone --recurse-submodules https://github.com/Fabio3rs/boost-conan-cmake.git
cd boost-conan-cmake

# Verificar integridade das dependências
conan install . --build=missing

# Build com flags de segurança
cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo -DENABLE_HARDENING=ON
```

### Para Produção

```bash
# Use sempre tags verificadas
git checkout <tag-verificada>

# Build com máximas proteções
cmake -DCMAKE_BUILD_TYPE=Release -DENABLE_HARDENING=ON -DENABLE_SANITIZERS=OFF

# Verificar binários
checksec --file=HelloWorld
```

## Dependências e Auditoria

### Fontes Confiáveis

- **Conan Center**: Apenas pacotes do Conan Center oficial
- **Ubuntu/Alpine**: Imagens base oficiais com atualizações de segurança
- **GitHub Actions**: Actions verificadas e com hash fixo

### Verificação Regular

- **Semanal**: Scan automático de CVEs
- **Release**: Auditoria completa antes de cada release  
- **Dependências**: Verificação de integridade de todas as dependências

## Contato

- **Maintainer**: Fabio3rs
- **Security Email**: fabio3rs@gmail.com
- **GitHub**: [@Fabio3rs](https://github.com/Fabio3rs)

---

**Última atualização**: Setembro 2025
**Próxima revisão**: Janeiro 2026
