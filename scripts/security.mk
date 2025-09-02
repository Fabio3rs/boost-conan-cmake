# Makefile addon for boost-conan-cmake security checks
# Add these targets to your existing Makefile or create a new one

.PHONY: security-check security-audit security-full security-report clean-reports

# Basic security check using Python script
security-check:
	@echo "🔍 Running CVE Security Check..."
	@python3 scripts/cve_security_check.py --project-root . --output security_report.txt
	@echo "✅ Security check complete. Report saved to security_report.txt"

# Comprehensive security audit using bash script
security-audit:
	@echo "🛡️ Running Security Audit..."
	@./scripts/security_audit.sh . security_audit.txt
	@echo "✅ Security audit complete. Report saved to security_audit.txt"

# Full security analysis (both tools)
security-full: security-audit security-check
	@echo "🎯 Running Full Security Analysis..."
	@python3 scripts/cve_security_check.py --format json --output security_detailed.json
	@echo "✅ Full security analysis complete:"
	@echo "   - Text report: security_audit.txt"
	@echo "   - Summary report: security_report.txt"
	@echo "   - Detailed JSON: security_detailed.json"

# Generate formatted security report
security-report: security-full
	@echo "📊 Generating Combined Security Report..."
	@echo "# boost-conan-cmake Security Analysis Report" > SECURITY_REPORT.md
	@echo "Generated: $(shell date)" >> SECURITY_REPORT.md
	@echo "" >> SECURITY_REPORT.md
	@echo "## Summary" >> SECURITY_REPORT.md
	@echo "\`\`\`" >> SECURITY_REPORT.md
	@tail -20 security_report.txt >> SECURITY_REPORT.md
	@echo "\`\`\`" >> SECURITY_REPORT.md
	@echo "" >> SECURITY_REPORT.md
	@echo "## Detailed Analysis" >> SECURITY_REPORT.md
	@echo "- Full audit report: \`security_audit.txt\`" >> SECURITY_REPORT.md
	@echo "- CVE check report: \`security_report.txt\`" >> SECURITY_REPORT.md
	@echo "- Machine-readable data: \`security_detailed.json\`" >> SECURITY_REPORT.md
	@echo "✅ Combined report generated: SECURITY_REPORT.md"

# Clean up security reports
clean-reports:
	@echo "🧹 Cleaning security reports..."
	@rm -f security_*.txt security_*.json SECURITY_REPORT.md test_security_report*
	@echo "✅ Reports cleaned"

# Quick security status check
security-status:
	@echo "📋 Quick Security Status Check:"
	@echo "Dependencies:"
	@grep -A 10 "DEPENDENCIES:" security_report.txt 2>/dev/null || echo "  Run 'make security-check' first"
	@echo ""
	@echo "Recent vulnerabilities found:"
	@grep -A 5 "VULNERABILITIES:" security_report.txt 2>/dev/null || echo "  Run 'make security-check' first"

# Security help
security-help:
	@echo "🛡️ boost-conan-cmake Security Tools Help"
	@echo "============================="
	@echo ""
	@echo "Available targets:"
	@echo "  security-check    - Run Python CVE scanner"
	@echo "  security-audit    - Run comprehensive bash audit"
	@echo "  security-full     - Run both tools with detailed output"
	@echo "  security-report   - Generate combined markdown report"
	@echo "  security-status   - Show quick status from last scan"
	@echo "  clean-reports     - Remove all security report files"
	@echo "  security-help     - Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make security-check      # Quick CVE check"
	@echo "  make security-full       # Complete analysis"
	@echo "  make security-report     # Generate markdown report"
	@echo ""
	@echo "Files generated:"
	@echo "  security_report.txt      # Text summary"
	@echo "  security_audit.txt       # Detailed audit"
	@echo "  security_detailed.json   # Machine-readable data"
	@echo "  SECURITY_REPORT.md       # Combined markdown report"

# Install dependencies for security tools
security-deps:
	@echo "📦 Installing security tool dependencies..."
	@which python3 >/dev/null || (echo "❌ Python3 not found" && exit 1)
	@python3 -c "import json, re, urllib.request" 2>/dev/null || (echo "❌ Required Python modules missing" && exit 1)
	@which git >/dev/null || (echo "❌ Git not found" && exit 1)
	@echo "✅ All dependencies satisfied"