# Toolkit for Servers

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/Greens-Organization/toolkit-for-servers?style=social)](https://github.com/Greens-Organization/toolkit-for-servers)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](https://github.com/Greens-Organization/toolkit-for-servers/releases)

🛠️ Um conjunto de scripts para configuração automática de servidores Linux com foco em segurança, desempenho e confiabilidade.

## 📋 Descrição

**Toolkit for Servers** é uma solução DevOps para configuração rápida e segura de servidores Linux. Com apenas um comando, você obtém um servidor configurado com as melhores práticas de segurança e desempenho, prontas para produção.

Este toolkit é especialmente útil para:
- Administradores de sistema que precisam configurar servidores rapidamente
- DevOps que buscam automação e consistência em suas infraestruturas
- Desenvolvedores que necessitam de ambientes seguros para deploy de aplicações

## ✨ Funcionalidades

- **🔒 Segurança SSH**: Configuração segura com autenticação por chave, porta personalizada, e sem acesso root direto
- **🧱 Firewall Robusto**: Regras automatizadas de firewall (UFW/Firewalld) adaptadas ao seu ambiente
- **🛡️ Proteção contra Ataques**: Instalação e configuração do Fail2ban para bloqueio de tentativas de força bruta
- **⚡ Otimizações de Desempenho**: Ajustes de kernel, escalonadores de I/O e configurações de rede para máximo desempenho

## 🚀 Instalação Rápida

### Instalação (Remota)

```bash
curl -fsSL https://grngroup.net/install.sh | sudo bash
```

### Instalação Personalizada

```bash
curl -fsSL https://grngroup.net/install.sh | sudo bash -s -- --ssh-port=2222 --no-fail2ban
```

### Instalação via Git (Local)

```bash
git clone https://github.com/Greens-Organization/toolkit-for-servers.git

cd toolkit-for-servers

sudo ./install-local.sh

sudo ./install-local.sh --ssh-port=2222 --no-fail2ban
```

## 📦 Compatibilidade

O toolkit foi testado e é compatível com:

- **Ubuntu** 20.04, 22.04, 24.04
- **Debian** 10, 11, 12
- **CentOS** 7, 8
- **AlmaLinux/Rocky Linux** 8, 9

## 🔧 Opções de Configuração

| Opção | Descrição | Padrão |
|-------|-----------|--------|
| `--ssh-port=PORTA` | Define uma porta SSH personalizada | `22` |
| `--no-firewall` | Desativa a configuração do firewall | `false` |
| `--no-fail2ban` | Desativa a instalação do Fail2ban | `false` |
| `--no-optimize` | Desativa otimizações de desempenho | `false` |
| `--help`, `-h` | Mostra mensagem de ajuda | - |

## 📂 Estrutura do Projeto

```
toolkit-for-servers/
├── docker
│   ├── almalinux-9.Dockerfile
│   ├── debian-12.Dockerfile
│   ├── README.md
│   └── ubuntu-22.04.Dockerfile
├── install-local.sh
├── install.sh
├── LICENSE
├── modules
│   ├── optimize_system.sh
│   ├── secure_ssh.sh
│   ├── setup_fail2ban.sh
│   └── setup_firewall.sh
├── motivation
│   ├── optimiza_system
│   │   ├── optimize_io_scheduler.md
│   │   ├── optimize_kernel.md
│   │   ├── optimize_network_stack.md
│   │   ├── optimize_resource_limits.md
│   │   └── README.md
│   ├── secure_ssh
│   │   ├── algorithms.md
│   │   ├── change_default_port.md
│   │   ├── connection_limit.md
│   │   ├── disable_root_login.md
│   │   ├── disable_unnecessary_resources.md
│   │   ├── idempotence.md
│   │   ├── key_vs_password_auth.md
│   │   ├── README.md
│   │   └── setup_timeout_connection.md
│   ├── setup_fail2ban
│   │   ├── cross_platform_compatibility.md
│   │   ├── docker_protection.md
│   │   ├── notification_and_actions.md
│   │   ├── README.md
│   │   └── ssh_protection.md
│   └── setup_firewall
│       ├── adapter_profiles.md
│       ├── anti_ddos_protection.md
│       ├── cross_platform_compatibility.md
│       └── README.md
├── README.md
├── run-container.sh
├── TESTING.md
├── tests
│   ├── test_helper.bash
│   └── test_secure_ssh.bats
└── test-suite.sh
```

Para ver a estrutura de pasta do projeto mais atualizada execute esse comando (mac/linux only): 
```bash
tree -L 2 -I 'motivation|.git' . > structure.txt
```


## 📊 Detalhes Técnicos

O Toolkit for Servers implementa várias otimizações técnicas avançadas, incluindo:

- Escalonadores de I/O otimizados para diferentes tipos de armazenamento (HDD, SSD, NVMe)
- Ajustes de parâmetros de kernel para melhor desempenho de rede e processamento
- Limites de recursos do sistema adequados para cargas de servidor
- Configurações de segurança proativas contra ameaças comuns

Saiba mais consultando os documentos técnicos na pasta `motivation/`.

## 🧪 Testes (WIP)


O projeto ainda não inclui uma suite de testes robusta para validar os scripts. Contudo, você pode nos ajudar com alguma contribuição nessa parte.

## 🛠️ Como Contribuir

Contribuições são bem-vindas! Siga estas etapas:

1. Fork este repositório
2. Crie uma branch para sua feature (`git checkout -b feature/nova-funcionalidade`)
3. Faça commit de suas alterações (`git commit -m 'Adiciona nova funcionalidade'`)
4. Envie para a branch (`git push origin feature/nova-funcionalidade`)
5. Abra um Pull Request

Por favor, certifique-se de que seus scripts passem em todos os testes antes de enviar um pull request.

## 📜 Licença

Este projeto está licenciado sob a licença MIT - veja o arquivo [LICENSE](LICENSE) para mais detalhes.

## 🤝 Agradecimentos

- Inspirado nas melhores práticas da comunidade DevOps e SysAdmin
- Um agradecimento especial a todos os contribuidores e testadores

---

<p align="center">
  <sub>Desenvolvido por GRN Group</sub>
</p>
