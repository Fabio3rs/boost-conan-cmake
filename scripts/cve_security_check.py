#!/usr/bin/env python3
"""
CVE Security Check Script for boost-conan-cmake Project
============================================

Este script realiza checagens de segurança (CVE) para o projeto C++ boost-conan-cmake
e suas dependências, consultando fontes oficiais (OSV e NVD) dinamicamente,
sem CVEs hardcoded.

Recursos:
- Analisa dependências do Conan
- Checa dependências de sistema (apt) e versões exatas
- Analisa git submodules (por commit)
- Consulta OSV.dev (querybatch) e NVD (CPE/CVE)
- Gera relatório detalhado, com deduplicação
- Recomendações gerais

Requisitos:
- Python 3.8+
- requests

Uso:
    python3 scripts/cve_security_check.py [--format json|text] [--output FILE]
                                          [--nvd-api-key KEY] [--ecosystem Ubuntu|Debian]
                                          [--offline]
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import requests


# ----------------------------- Clientes de API --------------------------------


class OSVClient:
    BASE = "https://api.osv.dev/v1"

    def query_batch(self, packages: List[Dict]) -> Dict:
        """
        packages: lista de entradas no formato:
          {"package": {"name": "openssl", "ecosystem": "Ubuntu"}, "version": "1.1.1f-1ubuntu2.16"}
          {"package": {"name": "zlib", "ecosystem": "Debian"}, "version": "1:1.2.13-1"}
          {"commit": "<gitsha>"}  # se for submodule com commit conhecido
        """
        if not packages:
            return {"results": []}
        r = requests.post(
            f"{self.BASE}/querybatch", json={"queries": packages}, timeout=45
        )
        r.raise_for_status()
        return r.json()  # {"results": [...]}


class NVDClient:
    CVE_URL = "https://services.nvd.nist.gov/rest/json/cves/2.0"
    CPE_URL = "https://services.nvd.nist.gov/rest/json/cpes/2.0"

    def __init__(self, api_key: Optional[str] = None):
        self.session = requests.Session()
        if api_key:
            self.session.headers["apiKey"] = api_key

    def find_cpe_candidates(self, keyword: str, max_rows: int = 10) -> List[Dict]:
        params = {"keywordSearch": keyword, "resultsPerPage": max_rows}
        r = self.session.get(self.CPE_URL, params=params, timeout=45)
        r.raise_for_status()
        return r.json().get("products", [])

    def cves_by_cpe(self, cpe_name: str) -> Dict:
        # cpe_name pode conter a versão: ex.: cpe:2.3:a:openssl:openssl:1.1.1:*:*:*:*:*:*:*
        params = {"cpeName": cpe_name, "resultsPerPage": 2000}
        r = self.session.get(self.CVE_URL, params=params, timeout=60)
        r.raise_for_status()
        return r.json()


# ------------------------------ Checker principal -----------------------------


class CVEChecker:
    """Main class for CVE security checking"""

    def __init__(
        self,
        project_root: str,
        nvd_api_key: Optional[str] = None,
        ecosystem: Optional[str] = None,
        offline: bool = False,
    ):
        self.project_root = Path(project_root)
        self.vulnerabilities: List[Dict] = []
        self.dependencies: Dict[str, Dict] = {
            "conan": {},
            "system": {},
            "submodules": {},
            "cmake": {},
        }

        # novos
        self.offline = offline
        self.osv = OSVClient()
        self.nvd = NVDClient(api_key=nvd_api_key)
        self.ecosystem = ecosystem or self._infer_ecosystem_from_dockerfile()

    # --------------------------- Utilidades internas --------------------------

    @staticmethod
    def _sev_order(sev: str) -> int:
        order = {"LOW": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}
        return order.get((sev or "").upper(), -1)

    @staticmethod
    def _highest_severity(vulns_for_pkg):
        best = "UNKNOWN"
        best_score = -1
        for v in vulns_for_pkg:
            sev = (
                v.get("severity")
                or (v.get("cvss") or {}).get("baseSeverity")
                or "UNKNOWN"
            ).upper()
            s = CVEChecker._sev_order(sev)
            if s > best_score:
                best, best_score = sev, s
        return best

    @staticmethod
    def _osv_fixed_versions(v: dict):
        """
        Tenta extrair versões corrigidas do campo `affected[*].ranges[*].events[*].fixed`
        e/ou limites superiores.
        """
        fixed = set()
        for aff in v.get("affected") or []:
            for r in aff.get("ranges") or []:
                for ev in r.get("events") or []:
                    fx = ev.get("fixed")
                    if fx:
                        fixed.add(fx)
                # Alguns advisories usam 'introduced'/'last_affected' sem 'fixed'
                last = r.get("events", [{}])[-1]
                if last.get("limit"):  # ex.: "< 1.2.13"
                    fixed.add(last["limit"])
        return sorted(fixed)

    def _glob(self, pattern: str):
        return list(self.project_root.glob(pattern))

    def _has_dependabot(self) -> bool:
        for p in (".github/dependabot.yml", ".github/dependabot.yaml"):
            if (self.project_root / p).is_file():
                return True
        return False

    def _has_renovate(self) -> bool:
        candidates = [
            "renovate.json",
            ".github/renovate.json",
            "renovate.json5",
            ".renovaterc",
            ".renovaterc.json",
        ]
        return any((self.project_root / p).is_file() for p in candidates)

    def _workflow_contains(self, substrings: list) -> bool:
        for wf in self._glob(".github/workflows/*.y*ml"):
            try:
                txt = wf.read_text(encoding="utf-8", errors="ignore").lower()
                if all(s.lower() in txt for s in substrings):
                    return True
            except Exception:
                pass
        return False

    def _has_osv_scanner_ci(self) -> bool:
        # procura por uso do osv-scanner no GitHub Actions
        return self._workflow_contains(["osv-scanner"])  # ação oficial ou docker

    def _has_trivy_ci(self) -> bool:
        return self._workflow_contains(["trivy"])

    def _has_grype_ci(self) -> bool:
        return self._workflow_contains(["grype"])

    def _has_security_md(self) -> bool:
        return any(
            (self.project_root / p).is_file()
            for p in ["SECURITY.md", ".github/SECURITY.md"]
        )

    def run_security_check(self) -> Dict:
        """Main method to run complete security check"""
        print("🔍 Starting CVE Security Check for boost-conan-cmake Project")
        print("=" * 50)

        # Coleta de dependências
        self._collect_conan_dependencies()
        self._collect_system_dependencies()
        self._collect_git_submodules()
        self._collect_cmake_info()

        # Análise de vulnerabilidades (OSV/NVD)
        self._check_vulnerabilities()

        # Gera relatório
        report = self._generate_report()
        return report

    def _ecosystem_from_base(self, base: str) -> Optional[str]:
        b = (base or "").lower()
        if "ubuntu" in b:
            return "Ubuntu"
        if "debian" in b:
            return "Debian"
        if "alpine" in b:
            return "Alpine"
        return None

    # --- novo: parser multi-stage do Dockerfile
    def _parse_dockerfile_stages(self, text: str):
        """
        Retorna lista de estágios:
        [{"name": "builder", "base": "ubuntu:24.04", "ecosystem": "Ubuntu",
        "body": "...linhas do estágio..."}]
        """
        stages = []
        cur = None
        for line in text.splitlines():
            m = re.match(
                r"^\s*FROM\s+([^\s]+)(?:\s+AS\s+([A-Za-z0-9._-]+))?",
                line,
                re.IGNORECASE,
            )
            if m:
                if cur:
                    stages.append(cur)
                base = m.group(1)
                name = m.group(2) or f"stage{len(stages)}"
                cur = {
                    "name": name,
                    "base": base,
                    "ecosystem": self._ecosystem_from_base(base),
                    "body": "",
                }
            elif cur:
                cur["body"] += line + "\n"
        if cur:
            stages.append(cur)
        return stages

    # --- substitua: antes retornava só 1 ecosistema; agora guardamos os estágios
    def _infer_ecosystem_from_dockerfile(self) -> Optional[str]:
        dockerfile = self.project_root / "Dockerfile"
        if not dockerfile.exists():
            self.docker_stages = []
            return None
        try:
            txt = dockerfile.read_text(encoding="utf-8", errors="ignore")
            self.docker_stages = self._parse_dockerfile_stages(txt)  # <-- salva
            # heurística: se houver vários estágios, o último é runtime
            if self.docker_stages:
                return self.docker_stages[-1].get("ecosystem")
        except Exception:
            self.docker_stages = []
        return None

    @staticmethod
    def _clean_version(ver: str) -> str:
        # remove sufixos tipo " (installed)"
        return re.sub(r"\s*\(installed\)\s*$", "", ver or "").strip()

    @staticmethod
    def ubuntu_pkg_to_osv_query(name: str, version: str) -> Dict:
        return {"package": {"name": name, "ecosystem": "Ubuntu"}, "version": version}

    @staticmethod
    def debian_pkg_to_osv_query(name: str, version: str) -> Dict:
        return {"package": {"name": name, "ecosystem": "Debian"}, "version": version}

    def guess_cpe_for_conan(self, name: str, version: str) -> Optional[str]:
        """Heurística para mapear pacote (Conan) -> CPE 2.3 e injetar versão."""
        try:
            candidates = self.nvd.find_cpe_candidates(keyword=name)
        except Exception:
            return None

        name_l = (name or "").lower()
        best = None
        for item in candidates:
            cpe = item.get("cpe", {})
            cpe23 = cpe.get("cpeName")
            if not cpe23:
                continue
            parts = cpe23.split(":")
            # preferir application/library (a)
            if (
                len(parts) >= 5
                and parts[2] == "a"
                and (
                    parts[3].lower() == name_l
                    or parts[4].lower() == name_l
                    or name_l in parts[4].lower()
                )
            ):
                best = parts
                break

        if not best:
            return None

        # garantir 13 campos e injetar versão no campo 5 (index 5 zero-based)
        best += ["*"] * (13 - len(best))
        best[5] = version or "*"
        return ":".join(best[:13])

    # ----------------------------- Coleta de deps -----------------------------

    def _collect_conan_dependencies(self):
        """Parse conanfile.txt for dependencies"""
        conanfile = self.project_root / "conanfile.txt"
        if not conanfile.exists():
            print("⚠️  conanfile.txt not found")
            return

        print("📦 Analyzing Conan dependencies...")

        content = conanfile.read_text(encoding="utf-8", errors="ignore")

        # Parse requires section
        in_requires = False
        for line in content.split("\n"):
            line = line.strip()
            if line == "[requires]":
                in_requires = True
                continue
            elif line.startswith("["):
                in_requires = False
                continue

            if in_requires and line and not line.startswith("#"):
                if "/" in line:
                    name, version = line.split("/", 1)
                    self.dependencies["conan"][name] = {
                        "version": version,
                        "source": "conanfile.txt",
                    }
                    print(f"  └─ {name}: {version}")

    # --- substitua: antes retornava só 1 ecosistema; agora guardamos os estágios
    def _infer_ecosystem_from_dockerfile(self) -> Optional[str]:
        dockerfile = self.project_root / "Dockerfile"
        if not dockerfile.exists():
            self.docker_stages = []
            return None
        try:
            txt = dockerfile.read_text(encoding="utf-8", errors="ignore")
            self.docker_stages = self._parse_dockerfile_stages(txt)  # <-- salva
            # heurística: se houver vários estágios, o último é runtime
            if self.docker_stages:
                return self.docker_stages[-1].get("ecosystem")
        except Exception:
            self.docker_stages = []
        return None

    # --- novo: extrair pacotes apt/apk por estágio (com possíveis versões)
    def _packages_from_stage(self, stage_body: str):
        apt = []
        apk = []
        # APT: linhas RUN ... apt-get/apt install ...
        for m in re.finditer(
            r"RUN\s+.*?(?:apt-get|apt)\s+.*?install\s+([^\n\\]+(?:\\\s*\n[^\n\\]+)*)",
            stage_body,
            flags=re.IGNORECASE,
        ):
            chunk = re.sub(r"\\\s*\n", " ", m.group(1))
            for tok in re.findall(r"\b([a-zA-Z0-9][\w.+-]*)(?:=([^\s]+))?\b", chunk):
                name, ver = tok
                # filtrar flags
                if name.lower() in {
                    "-y",
                    "--yes",
                    "--no-install-recommends",
                    "install",
                }:
                    continue
                if name.startswith("-"):
                    continue
                apt.append((name, ver or ""))

        # APK: linhas RUN ... apk add ...
        for m in re.finditer(
            r"RUN\s+.*?apk\s+add\s+([^\n\\]+(?:\\\s*\n[^\n\\]+)*)",
            stage_body,
            flags=re.IGNORECASE,
        ):
            chunk = re.sub(r"\\\s*\n", " ", m.group(1))
            for tok in re.findall(r"\b([a-zA-Z0-9][\w.+-]*)(?:=([^\s]+))?\b", chunk):
                name, ver = tok
                if name.lower() in {"--no-cache", "--update", "--virtual"}:
                    continue
                if name.startswith("-"):
                    continue
                apk.append((name, ver or ""))
        return apt, apk

    # --- altere: coleta de dependências de sistema agora respeita estágios
    def _collect_system_dependencies(self):
        print("\n🔧 Analyzing system dependencies...")

        # 1) CMake (como antes)
        cmake_file = self.project_root / "CMakeLists.txt"
        if cmake_file.exists():
            content = cmake_file.read_text(encoding="utf-8", errors="ignore")
            find_packages = re.findall(r"find_package\s*\(\s*(\w+).*?\)", content)
            for pkg in find_packages:
                if pkg not in ["PkgConfig", "CTest", "GoogleTest", "GTest"]:
                    version = self._get_cmake_package_version(pkg)
                    self.dependencies["system"][pkg] = {
                        "version": version,
                        "source": "CMakeLists.txt",
                        "required": True,
                    }
                    print(f"  └─ {pkg}: {version}")
            if "OpenSSL" in content:
                version = self._get_cmake_package_version("OpenSSL")
                self.dependencies["system"]["OpenSSL"] = {
                    "version": version,
                    "source": "CMakeLists.txt",
                    "critical": True,
                }
            if "mysqlcppconn" in content:
                version = self._get_cmake_package_version("MySQL_CPP_Connector")
                self.dependencies["system"]["MySQL_CPP_Connector"] = {
                    "version": version,
                    "source": "CMakeLists.txt",
                    "critical": True,
                }

        # 2) Dockerfile multi-stage
        self.dependencies.setdefault("system_by_stage", [])
        dockerfile = self.project_root / "Dockerfile"
        if dockerfile.exists():
            text = dockerfile.read_text(encoding="utf-8", errors="ignore")
            stages = getattr(
                self, "docker_stages", None
            ) or self._parse_dockerfile_stages(text)
            for st in stages:
                apt, apk = self._packages_from_stage(st["body"])
                entry = {
                    "stage": st["name"],
                    "base": st["base"],
                    "ecosystem": st["ecosystem"],
                    "apt": [],
                    "apk": [],
                }
                # resolver versões do host quando possível (somente apt e se rodando em host deb/ubuntu)
                for name, ver in apt:
                    v = ver or self._get_system_package_version(name)
                    entry["apt"].append({"name": name, "version": v})
                    # também projeta num mapa “flat” para compatibilidade com saída antiga
                    if name not in self.dependencies["system"]:
                        self.dependencies["system"][name] = {
                            "version": v,
                            "source": f"Dockerfile:{st['name']}",
                            "package_manager": "apt",
                        }
                        print(f"  └─ {name}: {v}")
                for name, ver in apk:
                    entry["apk"].append({"name": name, "version": ver or "unknown"})
                self.dependencies["system_by_stage"].append(entry)

    def _get_system_package_version(self, package_name: str) -> str:
        # 1) tenta dpkg -l direto
        try:
            result = subprocess.run(
                ["dpkg", "-l", package_name], capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                lines = [ln for ln in result.stdout.splitlines() if ln.startswith("ii")]
                if lines:
                    parts = lines[0].split()
                    if len(parts) >= 3:
                        return parts[2]  # versão dpkg completa
        except Exception:
            pass

        # 2) heurísticas por binário (apenas para exibir algo ao usuário)
        if package_name in ("curl", "libcurl4", "libcurl4-openssl-dev"):
            try:
                r = subprocess.run(
                    ["curl", "--version"], capture_output=True, text=True, timeout=5
                )
                if r.returncode == 0:
                    sp = r.stdout.split()
                    return f"{sp[1]} (installed)" if len(sp) > 1 else "installed"
            except Exception:
                pass

        if package_name == "openssl":
            try:
                r = subprocess.run(
                    ["openssl", "version"], capture_output=True, text=True, timeout=5
                )
                if r.returncode == 0:
                    sp = r.stdout.split()
                    return f"{sp[1]} (installed)" if len(sp) > 1 else "installed"
            except Exception:
                pass

        return "system"

    def _get_cmake_package_version(self, package_name: str) -> str:
        """Tenta detectar a versão de pacotes resolvidos por CMake."""
        try:
            if package_name == "OpenSSL":
                try:
                    result = subprocess.run(
                        ["openssl", "version"],
                        capture_output=True,
                        text=True,
                        timeout=5,
                    )
                    if result.returncode == 0:
                        out = result.stdout.split()
                        version = out[1] if len(out) > 1 else "unknown"
                        return f"{version} (installed)"
                except Exception:
                    pass

            elif package_name == "ZLIB":
                try:
                    result = subprocess.run(
                        ["dpkg", "-l", "zlib1g"],
                        capture_output=True,
                        text=True,
                        timeout=5,
                    )
                    if result.returncode == 0:
                        lines = [
                            line
                            for line in result.stdout.split("\n")
                            if line.startswith("ii")
                        ]
                        if lines:
                            version = (
                                lines[0].split()[2]
                                if len(lines[0].split()) > 2
                                else "unknown"
                            )
                            return f"{version} (installed)"
                except Exception:
                    pass

            elif package_name == "Threads":
                return "pthread (system)"

            elif package_name == "MySQL_CPP_Connector":
                try:
                    result = subprocess.run(
                        ["dpkg", "-l", "libmysqlclient-dev"],
                        capture_output=True,
                        text=True,
                        timeout=5,
                    )
                    if result.returncode == 0:
                        lines = [
                            line
                            for line in result.stdout.split("\n")
                            if line.startswith("ii")
                        ]
                        if lines:
                            version = (
                                lines[0].split()[2]
                                if len(lines[0].split()) > 2
                                else "unknown"
                            )
                            return f"{version} (mysql-client-dev)"
                except Exception:
                    pass

            return "required"

        except ImportError:
            return "required"

    def _collect_git_submodules(self):
        """Collect information about git submodules"""
        print("\n🔗 Analyzing git submodules...")

        gitmodules = self.project_root / ".gitmodules"
        if not gitmodules.exists():
            print("  └─ No .gitmodules found")
            return

        try:
            content = gitmodules.read_text(encoding="utf-8", errors="ignore")

            # Parse submodule information
            current_submodule = None
            for line in content.split("\n"):
                line = line.strip()
                if line.startswith("[submodule"):
                    m = re.search(r'"([^"]+)"', line)
                    current_submodule = m.group(1) if m else None
                elif line.startswith("url =") and current_submodule:
                    url = line.split("=", 1)[1].strip()
                    self.dependencies["submodules"][current_submodule] = {
                        "url": url,
                        "source": ".gitmodules",
                    }
                    print(f"  └─ {current_submodule}: {url}")

            # Get submodule commit info
            try:
                result = subprocess.run(
                    ["git", "submodule", "status"],
                    cwd=self.project_root,
                    capture_output=True,
                    text=True,
                )
                if result.returncode == 0:
                    for line in result.stdout.split("\n"):
                        if line.strip():
                            parts = line.strip().split()
                            if len(parts) >= 2:
                                commit = parts[0].lstrip("-+")
                                path = parts[1]
                                if path in self.dependencies["submodules"]:
                                    self.dependencies["submodules"][path][
                                        "commit"
                                    ] = commit
            except Exception as e:
                print(f"  ⚠️  Could not get submodule status: {e}")

        except Exception as e:
            print(f"  ⚠️  Error reading .gitmodules: {e}")

    def _collect_cmake_info(self):
        """Collect CMake version requirements"""
        print("\n🔨 Analyzing CMake configuration...")

        cmake_file = self.project_root / "CMakeLists.txt"
        if cmake_file.exists():
            content = cmake_file.read_text(encoding="utf-8", errors="ignore")

            # Extract CMake minimum version
            cmake_version = re.search(
                r"cmake_minimum_required\s*\(\s*VERSION\s+([0-9.]+)", content
            )
            if cmake_version:
                version = cmake_version.group(1)
                self.dependencies["cmake"]["minimum_version"] = {
                    "version": version,
                    "source": "CMakeLists.txt",
                }
                print(f"  └─ Minimum CMake version: {version}")

            # Extract C++ standard
            cxx_std = re.search(r"CMAKE_CXX_STANDARD\s+(\d+)", content)
            if cxx_std:
                std = cxx_std.group(1)
                self.dependencies["cmake"]["cxx_standard"] = {
                    "version": std,
                    "source": "CMakeLists.txt",
                }
                print(f"  └─ C++ Standard: C++{std}")

    # ------------------------ Consultas OSV/NVD + dedupe ----------------------

    def _query_osv_for_system(self) -> List[Dict]:
        if self.offline:
            return []
        findings = []

        # preferir system_by_stage quando disponível
        sys_by_stage = self.dependencies.get("system_by_stage") or []
        if sys_by_stage:
            for st in sys_by_stage:
                eco = st.get("ecosystem")
                if eco not in ("Ubuntu","Debian","Alpine"):
                    continue
                queries = []
                meta = []
                # apt
                for p in st.get("apt", []):
                    name = p.get("name"); ver = self._clean_version(p.get("version",""))
                    if not name or not ver or ver in ("system","required","unknown"):
                        continue
                    if eco in ("Ubuntu","Debian"):
                        q = (self.ubuntu_pkg_to_osv_query(name, ver) if eco=="Ubuntu"
                            else self.debian_pkg_to_osv_query(name, ver))
                        queries.append(q); meta.append((f"{st['stage']}::{name}", eco, ver))
                # apk (Alpine) — só funciona bem se versão estiver presente
                for p in st.get("apk", []):
                    if eco != "Alpine": continue
                    name = p.get("name"); ver = p.get("version","")
                    if not name or not ver or ver == "unknown":
                        continue
                    queries.append({"package": {"name": name, "ecosystem": "Alpine"}, "version": ver})
                    meta.append((f"{st['stage']}::{name}", "Alpine", ver))
                if not queries:
                    continue
                try:
                    resp = self.osv.query_batch(queries)
                    stage_findings = self._osv_results_to_findings(resp, meta)
                    findings.extend(stage_findings)
                except Exception as e:
                    print(f"  ⚠️  OSV query failed for stage {st.get('stage')}: {e}")
            return findings

        # fallback (comportamento antigo)
        if not self.ecosystem:
            return []
        queries = []; meta = []
        for pkg, info in self.dependencies.get("system", {}).items():
            ver = self._clean_version(info.get("version",""))
            if not ver or ver in ("system","required","unknown"):
                continue
            if self.ecosystem=="Ubuntu":
                queries.append(self.ubuntu_pkg_to_osv_query(pkg, ver)); meta.append((pkg,"Ubuntu",ver))
            elif self.ecosystem=="Debian":
                queries.append(self.debian_pkg_to_osv_query(pkg, ver)); meta.append((pkg,"Debian",ver))
        if not queries:
            return []
        resp = self.osv.query_batch(queries)
        return self._osv_results_to_findings(resp, meta)


    def _query_osv_for_submodules(self) -> List[Dict]:
        if self.offline:
            return []
        queries = []
        for _name, info in self.dependencies.get("submodules", {}).items():
            commit = (info.get("commit") or "").strip("-+ ")
            if commit:
                queries.append({"commit": commit})
        if not queries:
            return []
        resp = self.osv.query_batch(queries)
        return self._osv_results_to_findings(resp)

    def _query_nvd_for_conan(self) -> List[Dict]:
        if self.offline:
            return []
        findings: List[Dict] = []
        for name, info in self.dependencies.get("conan", {}).items():
            ver = self._clean_version(info.get("version", ""))
            if not ver or ver.lower() == "unknown":
                continue
            cpe = self.guess_cpe_for_conan(name, ver)
            if not cpe:
                continue
            data = self.nvd.cves_by_cpe(cpe)
            findings.extend(
                self._nvd_results_to_findings(data, package=name, version=ver)
            )
        return findings

    def _osv_results_to_findings(
        self, osv_batch_resp: Dict, meta: Optional[List] = None
    ) -> List[Dict]:
        findings = []
        results = osv_batch_resp.get("results") or []
        for idx, res in enumerate(results):
            # usa meta quando disponível (querybatch)
            pkg_name, eco, ver = (None, None, None)
            if meta and idx < len(meta):
                pkg_name, eco, ver = meta[idx]
            # fallback caso o endpoint traga package embutido
            if not pkg_name:
                pkg = res.get("package") or {}
                pkg_name = pkg.get("name")
                eco = pkg.get("ecosystem")
                ver = res.get("version")
            for v in res.get("vulns") or []:
                sev = None
                for sv in v.get("severity") or []:
                    sev = sv.get("severity") or sev
                findings.append(
                    {
                        "source": "OSV",
                        "id": v.get("id"),
                        "package": pkg_name,
                        "ecosystem": eco,
                        "version": ver,
                        "summary": v.get("summary"),
                        "severity": sev,
                        "references": [
                            r.get("url") for r in (v.get("references") or [])
                        ],
                        "aliases": v.get("aliases") or [],
                        "affected": v.get("affected") or [],
                    }
                )
        return findings

    def _enrich_osv_with_nvd(self, items: List[Dict]) -> None:
        for f in items:
            if f.get("source") != "OSV" or f.get("severity"):
                continue
            aliases = f.get("aliases") or []
            cve_ids = [a for a in aliases if a.startswith("CVE-")]

            if not cve_ids:
                fid = f.get("id") or ""
                # novo: traduzir UBUNTU-CVE-YYYY-NNNN -> CVE-YYYY-NNNN
                m = re.match(r"UBUNTU-CVE-(\d{4}-\d+)$", fid)
                if m:
                    cve_ids = [f"CVE-{m.group(1)}"]
                elif fid.startswith("CVE-"):
                    cve_ids = [fid]

            if not cve_ids:
                continue

            try:
                data = self.nvd.session.get(
                    self.nvd.CVE_URL, params={"cveId": cve_ids[0]}, timeout=30
                ).json()
                vulns = data.get("vulnerabilities") or []
                if not vulns:
                    continue
                cve = vulns[0].get("cve", {})
                metrics = cve.get("metrics", {})
                for key in ("cvssMetricV31", "cvssMetricV30"):
                    if key in metrics and metrics[key]:
                        f["cvss"] = metrics[key][0].get("cvssData")
                        break
            except Exception:
                pass

    def _nvd_results_to_findings(
        self, nvd_resp: Dict, package: str, version: str
    ) -> List[Dict]:
        findings = []
        for item in nvd_resp.get("vulnerabilities", []):
            cve = item.get("cve", {})
            metrics = cve.get("metrics", {})
            cvss = None
            for key in ("cvssMetricV31", "cvssMetricV30"):
                if key in metrics and metrics[key]:
                    cvss = metrics[key][0].get("cvssData")
                    break
            findings.append(
                {
                    "source": "NVD",
                    "id": cve.get("id"),
                    "package": package,
                    "version": version,
                    "summary": (cve.get("descriptions") or [{}])[0].get("value"),
                    "cvss": cvss,
                    "references": [r.get("url") for r in (cve.get("references") or [])],
                }
            )
        return findings

    def _dedupe_findings(self, items: List[Dict]) -> List[Dict]:
        seen = set()
        out = []
        for it in items:
            key = it.get("id") or (
                it.get("source"),
                it.get("package"),
                it.get("version"),
                it.get("summary"),
            )
            if key in seen:
                continue
            seen.add(key)
            out.append(it)
        return out

    # ------------------------- Pipeline de verificação ------------------------

    def _check_vulnerabilities(self):
        """Check for known vulnerabilities in dependencies (dinâmico via OSV/NVD)"""
        print("\n🛡️  Checking for known vulnerabilities (OSV/NVD)...")

        findings: List[Dict] = []
        try:
            findings.extend(self._query_osv_for_system())
        except Exception as e:
            print(f"  ⚠️  OSV system query failed: {e}")

        try:
            findings.extend(self._query_osv_for_submodules())
        except Exception as e:
            print(f"  ⚠️  OSV submodules query failed: {e}")

        try:
            findings.extend(self._query_nvd_for_conan())
        except Exception as e:
            print(f"  ⚠️  NVD conan query failed: {e}")

        # (Opcional) manter fallbacks antigos comentados:
        # for name, info in self.dependencies["conan"].items():
        #     findings.extend(self._check_conan_cve(name, info["version"]))
        # for name, _info in self.dependencies["system"].items():
        #     findings.extend(self._check_system_cve(name))
        self._enrich_osv_with_nvd(findings)
        self.vulnerabilities = self._dedupe_findings(findings)
        print(f"  └─ Found {len(self.vulnerabilities)} potential security issues")

    # ------------------------------- Relatório --------------------------------

    @staticmethod
    def _severity_of(v: Dict) -> str:
        # Prioriza v['severity'] (OSV). Caso não exista, usa CVSS (NVD).
        sev = (v.get("severity") or "").upper()
        if sev:
            return sev
        cvss = v.get("cvss") or {}
        base_sev = (cvss.get("baseSeverity") or "").upper()
        if base_sev:
            return base_sev
        # deduzir pela pontuação se disponível
        score = cvss.get("baseScore")
        if isinstance(score, (int, float)):
            if score >= 9.0:
                return "CRITICAL"
            if score >= 7.0:
                return "HIGH"
            if score >= 4.0:
                return "MEDIUM"
            return "LOW"
        return "UNKNOWN"

    def _generate_report(self) -> Dict:
        """Generate comprehensive security report"""
        print("\n📋 Generating security report...")

        # Contagem por severidade
        crit = high = med = low = 0
        for v in self.vulnerabilities:
            s = self._severity_of(v)
            if s == "CRITICAL":
                crit += 1
            elif s == "HIGH":
                high += 1
            elif s == "MEDIUM":
                med += 1
            elif s == "LOW":
                low += 1

        report = {
            "scan_date": datetime.now().isoformat(),
            "project": "boost-conan-cmake",
            "summary": {
                "total_dependencies": sum(
                    len(deps) for deps in self.dependencies.values()
                ),
                "vulnerabilities_found": len(self.vulnerabilities),
                "critical_count": crit,
                "high_count": high,
                "medium_count": med,
                "low_count": low,
            },
            "dependencies": self.dependencies,
            "vulnerabilities": self.vulnerabilities,
            "recommendations": self._generate_recommendations(),
        }

        return report

    def _generate_recommendations(self) -> List[Dict]:
        recs: List[Dict] = []

        # 0) contexto
        ecosystem = getattr(self, "ecosystem", None)  # Ubuntu/Debian ou None
        base_image = None
        try:
            df = (self.project_root / "Dockerfile").read_text(
                encoding="utf-8", errors="ignore"
            )
            m = re.search(
                r"^\s*FROM\s+([^\s:]+):?([^\s]*)",
                df,
                flags=re.MULTILINE | re.IGNORECASE,
            )
            if m:
                base_image = (
                    m.group(1) + (":" + m.group(2) if m.group(2) else "")
                ).strip()
        except Exception:
            pass

        # 1) Recomendações gerais (só se faltar)
        if not self._has_dependabot() and not self._has_renovate():
            recs.append(
                {
                    "priority": "HIGH",
                    "category": "General",
                    "title": "Enable automated dependency scanning",
                    "description": "Monitore CVEs em PRs (OSV-Scanner/Dependabot/Renovate).",
                    "action": "Adicionar .github/dependabot.yml ou Renovate + osv-scanner no CI",
                }
            )
        else:
            # já tem algum gerenciador de atualizações — sugerir verificação leve
            tools = []
            if self._has_dependabot():
                tools.append("Dependabot")
            if self._has_renovate():
                tools.append("Renovate")
            recs.append(
                {
                    "priority": "LOW",
                    "category": "General",
                    "title": "Verificar config de atualização automática",
                    "description": f"Encontrado: {', '.join(tools)}",
                    "action": "Garantir escopos (ecosistemas C/C++, Docker, GitHub Actions) e frequência adequados",
                }
            )

        # Scanner de vulnerabilidades no CI (só se faltar)
        if not (
            self._has_osv_scanner_ci() or self._has_trivy_ci() or self._has_grype_ci()
        ):
            recs.append(
                {
                    "priority": "HIGH",
                    "category": "CI",
                    "title": "Adicionar scanner de CVEs no CI",
                    "description": "Falhar PRs quando CVEs novas forem detectadas.",
                    "action": "Integrar osv-scanner (ou Trivy/Grype) nas pipelines (code + SBOM + image)",
                }
            )
        else:
            scanners = []
            if self._has_osv_scanner_ci():
                scanners.append("OSV-Scanner")
            if self._has_trivy_ci():
                scanners.append("Trivy")
            if self._has_grype_ci():
                scanners.append("Grype")
            recs.append(
                {
                    "priority": "LOW",
                    "category": "CI",
                    "title": "Ajustar threshold do scanner",
                    "description": f"Scanner detectado: {', '.join(scanners)}",
                    "action": "Definir políticas (ex.: fail-on-severity=HIGH) e escopos (SBOM/Docker)",
                }
            )

        # Guia de segurança (somente se faltar)
        if not self._has_security_md():
            recs.append(
                {
                    "priority": "MEDIUM",
                    "category": "Policy",
                    "title": "Adicionar SECURITY.md",
                    "description": "Define canal de reporte e janelas de correção.",
                    "action": "Criar SECURITY.md (templates do GitHub) com SLA de resposta",
                }
            )

        # 2) Imagem base: sugestão se tag antiga/sem LTS explícito
        if base_image:
            tip = None
            if "ubuntu" in base_image.lower():
                # heurística simples: se não mencionar 22.04/24.04
                if not any(
                    x in base_image for x in ["22.04", "24.04", "jammy", "noble"]
                ):
                    tip = "Migrar para Ubuntu LTS recente (22.04/24.04) e rebuild periódico"
            elif "debian" in base_image.lower():
                if not any(
                    x in base_image for x in ["bookworm", "bullseye", "12", "11"]
                ):
                    tip = "Usar Debian estável (bookworm/bullseye) com atualizações de segurança"
            if tip:
                recs.append(
                    {
                        "priority": "HIGH",
                        "category": "Container",
                        "title": f"Revisar imagem base ({base_image})",
                        "description": "Imagens genéricas/antigas acumulam CVEs de pacotes base.",
                        "action": tip,
                    }
                )

        # 3) Agrupar vulnerabilidades por pacote
        by_pkg: Dict[str, List[Dict]] = {}
        for v in self.vulnerabilities:
            pkg = v.get("package") or "unknown"
            by_pkg.setdefault(pkg, []).append(v)

        # 4) Recomendações específicas por pacote
        for pkg, vulns in sorted(by_pkg.items()):
            # severidade consolidada
            sev = CVEChecker._highest_severity(vulns)

            # OSV → tentar versões corrigidas para sugerir upgrade direto
            fixed_candidates = []
            for v in vulns:
                if v.get("source") == "OSV":
                    fixed_candidates.extend(CVEChecker._osv_fixed_versions(v))
            fixed_candidates = sorted(
                {f for f in fixed_candidates if f and f not in ("*",)}
            )

            current_ver = None
            # tentar achar a versão vista no inventário
            if pkg in self.dependencies.get("system", {}):
                current_ver = self._clean_version(
                    self.dependencies["system"][pkg].get("version", "")
                )
            elif pkg in self.dependencies.get("conan", {}):
                current_ver = self._clean_version(
                    self.dependencies["conan"][pkg].get("version", "")
                )

            # construir ação
            action = None
            if ecosystem in ("Ubuntu", "Debian") and pkg in self.dependencies.get(
                "system", {}
            ):
                # apt upgrade
                if fixed_candidates:
                    action = f"Atualizar via apt: sudo apt-get update && sudo apt-get install --only-upgrade {pkg}"
                else:
                    action = f"Aplicar atualizações de segurança via apt para {pkg}"
            elif pkg in self.dependencies.get("conan", {}):
                # Conan
                if fixed_candidates:
                    action = f"Subir versão no conanfile/lock e rebuild (ex.: {pkg}/{fixed_candidates[0]}+)"
                else:
                    action = "Atualizar a referência no conanfile/lockfile para versão corrigida e regenerar build"
            elif pkg in self.dependencies.get("submodules", {}):
                # Submodule (se vier pelo OSV commit advisory)
                action = (
                    "Atualizar o submódulo para um commit/tag após o patch de segurança"
                )

            # construir descrição com alguns CVEs/refs
            ids = []
            for v in vulns:
                vid = v.get("id")
                if vid:
                    ids.append(vid)
            ids = sorted(set(ids))[:5]
            refs = []
            for v in vulns:
                refs.extend(v.get("references") or [])
            refs = [r for r in refs if r][:5]

            title = f"Mitigar CVEs em {pkg}"
            desc_parts = []
            if current_ver:
                desc_parts.append(f"Versão atual detectada: {current_ver}")
            if ids:
                desc_parts.append(f"IDs: {', '.join(ids)}")
            if fixed_candidates:
                desc_parts.append(
                    f"Versões corrigidas sugeridas (indicativas): {', '.join(fixed_candidates[:3])}"
                )
            if refs:
                desc_parts.append(f"Refs: {', '.join(refs)}")
            description = (
                " | ".join(desc_parts)
                if desc_parts
                else "Atualizar para versão corrigida disponível."
            )

            # prioridade conforme severidade consolidada
            priority = {"CRITICAL": "CRITICAL", "HIGH": "HIGH", "MEDIUM": "MEDIUM"}.get(
                sev, "LOW"
            )

            recs.append(
                {
                    "priority": priority,
                    "category": "Package",
                    "title": title,
                    "description": description,
                    "action": action or "Aplicar patch/upgrade conforme fornecedor",
                }
            )

        # 5) Hardening de build só se detectar C++ projeto
        if "cxx_standard" in self.dependencies.get("cmake", {}):
            recs.append(
                {
                    "priority": "MEDIUM",
                    "category": "Build",
                    "title": "Ativar flags de hardening",
                    "description": "Proteções adicionais ajudam a mitigar explorações de memória.",
                    "action": "Adicionar -fstack-protector-strong, -D_FORTIFY_SOURCE=2, -Wl,-z,relro,-z,now",
                }
            )

        return recs


# ------------------------------ CLI / Output ---------------------------------


def format_text_report(report: Dict) -> str:
    """Format report as human-readable text"""
    lines: List[str] = []

    summary = report.get("summary", {})
    lines.append(f"Scan Date: {report.get('scan_date', 'unknown')}")
    lines.append(f"Project: {report.get('project', 'unknown')}")
    lines.append("")

    lines.append("SUMMARY:")
    lines.append(f"  Total Dependencies: {summary.get('total_dependencies', 0)}")
    lines.append(f"  Vulnerabilities Found: {summary.get('vulnerabilities_found', 0)}")
    lines.append(f"    Critical: {summary.get('critical_count', 0)}")
    lines.append(f"    High: {summary.get('high_count', 0)}")
    lines.append(f"    Medium: {summary.get('medium_count', 0)}")
    lines.append(f"    Low: {summary.get('low_count', 0)}")
    lines.append("")

    # Dependencies section
    lines.append("DEPENDENCIES:")
    deps = report.get("dependencies", {})

    if deps.get("conan"):
        lines.append("  Conan Packages:")
        for name, info in deps["conan"].items():
            lines.append(f"    - {name}: {info.get('version', 'unknown')}")

    if deps.get("system"):
        lines.append("  System Packages:")
        for name, info in deps["system"].items():
            lines.append(f"    - {name}: {info.get('version', 'unknown')}")

    if deps.get("submodules"):
        lines.append("  Git Submodules:")
        for name, info in deps["submodules"].items():
            commit = (info.get("commit") or "unknown")[:8]
            lines.append(f"    - {name}: {commit}")

    lines.append("")

    # Vulnerabilities section
    vulns = report.get("vulnerabilities", [])
    if vulns:
        lines.append("VULNERABILITIES:")
        for v in vulns:
            pkg = v.get("package", "unknown")
            ver = v.get("version", "unknown")
            src = v.get("source", "")
            vid = v.get("id")
            sev = (
                v.get("severity")
                or (v.get("cvss", {}) or {}).get("baseSeverity")
                or "UNKNOWN"
            ).upper()
            lines.append(f"  [{sev}] {pkg} {ver}  ({src})")
            if vid:
                lines.append(f"    ID: {vid}")
            if v.get("summary"):
                lines.append(f"    Summary: {v['summary']}")
            refs = v.get("references") or []
            if refs:
                lines.append(
                    f"    Refs: {', '.join(refs[:5])}{' ...' if len(refs)>5 else ''}"
                )
            lines.append("")

    # Recommendations section
    recommendations = report.get("recommendations", [])
    if recommendations:
        lines.append("RECOMMENDATIONS:")
        for rec in recommendations:
            priority = rec.get("priority", "UNKNOWN")
            title = rec.get("title", "Unknown")
            lines.append(f"  [{priority}] {title}")
            if rec.get("description"):
                lines.append(f"    {rec['description']}")
            if rec.get("action"):
                lines.append(f"    Action: {rec['action']}")
            lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="CVE Security Check for boost-conan-cmake")
    parser.add_argument(
        "--format", choices=["json", "text"], default="text", help="Output format"
    )
    parser.add_argument("--output", "-o", help="Output file (default: stdout)")
    parser.add_argument("--project-root", default=".", help="Project root directory")
    parser.add_argument(
        "--nvd-api-key",
        default=os.getenv("NVD_API_KEY"),
        help="NVD API key (optional, aumenta a cota)",
    )
    parser.add_argument(
        "--ecosystem",
        choices=["Ubuntu", "Debian"],
        help="Forçar ecossistema para pacotes de sistema",
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Pula chamadas de rede (só parsing local)",
    )

    args = parser.parse_args()

    checker = CVEChecker(
        project_root=args.project_root,
        nvd_api_key=args.nvd_api_key,
        ecosystem=args.ecosystem,
        offline=args.offline,
    )

    try:
        report = checker.run_security_check()

        # Format output
        if args.format == "json":
            output = json.dumps(report, indent=2, ensure_ascii=False)
        else:
            output = format_text_report(report)

        # Write output
        if args.output:
            Path(args.output).parent.mkdir(parents=True, exist_ok=True)
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(output)
            print(f"\n✅ Security report written to: {args.output}")
        else:
            print("\n" + "=" * 50)
            print("SECURITY REPORT")
            print("=" * 50)
            print(output)

        # Exit code
        vulnerability_count = len(report.get("vulnerabilities", []))
        if vulnerability_count > 0:
            print(f"\n⚠️  {vulnerability_count} security issues found!")
            sys.exit(1)
        else:
            print("\n✅ No critical security issues detected")
            sys.exit(0)

    except Exception as e:
        print(f"❌ Error during security check: {e}")
        sys.exit(2)


if __name__ == "__main__":
    main()
