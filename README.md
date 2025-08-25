# boost-conan-cmake

Este é um repositório de estudo que demonstra como integrar as bibliotecas Boost com CMake usando o gerenciador de pacotes Conan. O projeto apresenta um exemplo prático de serialização usando Boost.Serialization e formatação de texto com a biblioteca fmt.

## 📋 Índice

- [Sobre o Projeto](#-sobre-o-projeto)
- [Pré-requisitos](#-pré-requisitos)
- [Instalação e Configuração](#-instalação-e-configuração)
- [Como Usar](#-como-usar)
- [Estrutura do Projeto](#-estrutura-do-projeto)
- [Tecnologias Utilizadas](#-tecnologias-utilizadas)
- [Exemplo de Código](#-exemplo-de-código)
- [CI/CD](#-cicd)
- [Contribuindo](#-contribuindo)
- [Licença](#-licença)

## 🎯 Sobre o Projeto

Este projeto demonstra uma integração completa entre:
- **Boost Libraries**: Especificamente Boost.Serialization para serialização de objetos
- **CMake**: Sistema de build moderno e multiplataforma
- **Conan**: Gerenciador de pacotes C++ para resolver dependências
- **fmt**: Biblioteca moderna de formatação de strings para C++

O exemplo implementa uma estrutura simples `VecXYZ` que representa um vetor 3D e demonstra como serializá-la em um arquivo de texto e depois deserializá-la, exibindo os valores usando formatação moderna.

## 🔧 Pré-requisitos

Antes de começar, certifique-se de ter instalado:

- **CMake** >= 3.16
- **Conan** >= 1.57.0 (gerenciador de pacotes)
- **Compilador C++17** compatível:
  - GCC >= 7
  - Clang >= 5
  - MSVC >= 2017
- **Python** >= 3.6 (para o Conan)

### Instalação do Conan

```bash
pip install conan
```

## 🚀 Instalação e Configuração

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/Fabio3rs/boost-conan-cmake.git
   cd boost-conan-cmake
   ```

2. **Configure o perfil do Conan (primeira vez):**
   ```bash
   conan profile detect --force
   ```

3. **Configure e compile o projeto:**
   ```bash
   mkdir build && cd build
   cmake .. -DCMAKE_BUILD_TYPE=Release
   cmake --build .
   ```

> **📝 Nota Importante**: Este projeto usa integração automática CMake-Conan através do arquivo `cmake/conan.cmake`. Durante a configuração do CMake, as dependências do Conan são automaticamente instaladas com base na configuração atual de compilação. Não é necessário executar `conan install` manualmente.

## 🎮 Como Usar

Após a compilação, execute o programa:

```bash
# No diretório build
./HelloWorld
```

**Saída esperada:**
```
Hello, world!
v2.x = 1
v2.y = 2
v2.z = 3
```

O programa:
1. Cria um objeto `VecXYZ` com valores (1.0, 2.0, 3.0)
2. Serializa o objeto em um arquivo chamado "filename"
3. Cria um novo objeto vazio
4. Deserializa os dados do arquivo
5. Exibe os valores recuperados

## 📁 Estrutura do Projeto

```
boost-conan-cmake/
├── .clang-format          # Configuração de formatação de código
├── .clang-tidy            # Configuração de análise estática
├── .github/
│   └── workflows/
│       └── cmake-single-platform.yml  # CI/CD com GitHub Actions
├── .gitignore             # Arquivos ignorados pelo Git
├── CMakeLists.txt         # Configuração principal do CMake
├── README.md              # Este arquivo
├── cmake/
│   └── conan.cmake        # Integração CMake-Conan
├── conanfile.txt          # Dependências do Conan
└── src/
    └── main.cpp           # Código fonte principal
```

## 🛠 Tecnologias Utilizadas

| Tecnologia | Versão | Propósito |
|------------|---------|-----------|
| **C++** | 17 | Linguagem de programação |
| **CMake** | ≥ 3.16 | Sistema de build |
| **Conan** | ≥ 1.57.0 | Gerenciamento de dependências |
| **Boost** | 1.84.0 | Biblioteca de utilidades C++ |
| **fmt** | 10.2.1 | Formatação de strings moderna |
| **Clang** | Latest | Compilador (CI/CD) |

### Integração Automática CMake-Conan

O projeto utiliza o arquivo `cmake/conan.cmake` para integração automática entre CMake e Conan. Durante a fase de configuração do CMake, o sistema:

1. **Detecta automaticamente** as configurações do compilador atual (`conan_cmake_autodetect`)
2. **Executa o Conan** com as configurações detectadas (`conan_cmake_run`)
3. **Instala dependências faltantes** automaticamente (flag `BUILD missing`)
4. **Configura variáveis** de ambiente para otimização (`-fdata-sections -ffunction-sections`)
5. **Inclui bibliotecas** no projeto através do `conanbuildinfo.cmake` gerado

Este processo elimina a necessidade de executar comandos `conan install` manualmente.

### Configurações Especiais

- **C++ Standard**: C++17 com extensões habilitadas
- **Otimizações**: Dead code elimination (`-fdata-sections -ffunction-sections`)
- **Linking**: Garbage collection de seções não utilizadas
- **Testing**: Framework CTest habilitado

## 💻 Exemplo de Código

O código principal demonstra serialização com Boost:

```cpp
#include <boost/archive/text_iarchive.hpp>
#include <boost/archive/text_oarchive.hpp>
#include <fmt/core.h>
#include <fstream>

namespace {
struct VecXYZ {
    float x{}, y{}, z{};
    
    // Necessário para serialização
    friend class boost::serialization::access;
    
    template <class Archive>
    void serialize(Archive &ar, const unsigned int version) {
        ar & x & y & z;  // Serializa todos os membros
    }
};
}

int main() {
    // Serialização
    VecXYZ v1{1.0F, 2.0F, 3.0F};
    std::ofstream ofs("filename");
    boost::archive::text_oarchive oa(ofs);
    oa << v1;  // Salva o objeto
    ofs.close();
    
    // Deserialização
    VecXYZ v2;
    std::ifstream ifs("filename");
    boost::archive::text_iarchive ia(ifs);
    ia >> v2;  // Carrega o objeto
    
    // Exibe usando fmt (C++20 style formatting)
    fmt::print("v2.x = {}\n", v2.x);
    fmt::print("v2.y = {}\n", v2.y);
    fmt::print("v2.z = {}\n", v2.z);
    
    return 0;
}
```

## 🔄 CI/CD

O projeto inclui uma pipeline do GitHub Actions que:

- ✅ Executa em Ubuntu (latest)
- ✅ Instala Conan automaticamente
- ✅ Configura cache para dependências
- ✅ Usa Clang como compilador
- ✅ Compila em modo Release
- ✅ Executa testes automatizados

## 🤝 Contribuindo

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

### Padrões de Código

O projeto usa:
- **clang-format** para formatação consistente
- **clang-tidy** para análise estática
- **C++17** como padrão mínimo

## 📝 Notas de Aprendizado

Este projeto é ideal para aprender:

1. **Gerenciamento de Dependências**: Como usar Conan integrado automaticamente com CMake
2. **Build System Moderno**: Integração CMake + Conan usando `cmake/conan.cmake`
3. **Automação de Build**: Como eliminar passos manuais na configuração de dependências
4. **Boost Libraries**: Uso prático de Boost.Serialization
5. **Formatação Moderna**: fmt como alternativa ao printf/iostream
6. **CI/CD**: Automação com GitHub Actions
7. **Boas Práticas**: Estrutura de projeto C++ moderna com build automatizado

## 📄 Licença

Este projeto é disponibilizado para fins educacionais. Sinta-se livre para usar como referência para seus próprios estudos.

---

**Feito com ❤️ para estudos de C++, CMake e Conan**
