## ⚠️ Aviso: Limitações do uso de `systemd` em containers

Estes Dockerfiles foram projetados para containers que executam `systemd` como processo PID 1. Isso é útil para testes de serviços como `sshd`, `ufw`, `firewalld`, `fail2ban` e outros que dependem do `systemd`. No entanto, existem **importantes limitações e requisitos** para que funcionem corretamente.

### 🧱 Requisitos para rodar com `systemd` dentro do container

Para executar corretamente esses containers baseados em **AlmaLinux**, **Debian** ou **Ubuntu**, é necessário:

* Docker com suporte a namespaces de cgroups (idealmente com `--cgroupns=host`);
* Montagem de `/sys/fs/cgroup` com permissão de leitura e escrita (`rw`);
* Execução em um **host Linux nativo**, *não WSL* ou ambientes limitados;
* O uso de `--privileged` ao rodar o container;
* Uso de `ENTRYPOINT ["/usr/sbin/init"]` para garantir que o `systemd` seja o PID 1.

### ⚠️ Ambiente não suportado: WSL (Windows Subsystem for Linux)

> ⚠️ **Executar esses containers em WSL (incluindo WSL 2 com Docker Desktop) não é suportado.**

Ao tentar rodar nesses ambientes, você encontrará erros como:

```text
Failed to allocate manager object: Read-only file system
Exiting PID 1...
```

Isso ocorre porque:

* O WSL não expõe a hierarquia de cgroups de forma adequada para o `systemd`;
* O volume `/sys/fs/cgroup` é montado como somente leitura (`ro`);
* O kernel do WSL não implementa as permissões completas de cgroups para containers com `systemd`.

### ✅ Alternativas e soluções

* 🐧 **Use um host Linux nativo** (ou uma VM com Linux) para executar os containers corretamente;
* 🧪 **Evite usar `systemd`** se possível, e substitua por processos diretos com `tini`, supervisores leves ou chamadas diretas (`CMD ["/usr/sbin/sshd", "-D"]`).

---

### 🛠 Exemplo de comando compatível (em Linux):

```bash
docker run --rm -it --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  --tmpfs /tmp \
  nome-da-imagem
```
