# Por que alterar a Porta SSH Padrão

## Visão Geral

A mudança da porta SSH padrão (22) para uma porta não-padrão é uma prática implementada no Toolkit for Servers para aumentar a segurança dos servidores.

## Implementação no Toolkit

```bash
# Trecho do código que altera a porta SSH
local ssh_port="${1:-$CUSTOM_SSH_PORT}"

# Verifica se a porta está livre
if [ "$ssh_port" != "22" ]; then
    if command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":$ssh_port "; then
            log "WARN" "A porta $ssh_port já está em uso. Mantendo a porta SSH atual."
            ssh_port=$(grep "^Port " "$ssh_config" 2>/dev/null | awk '{print $2}')
            ssh_port=${ssh_port:-22}
        fi
    fi
fi

# Configuração aplicada
echo "Port $ssh_port" >> "$secure_ssh_config"
```

## Justificativa

A alteração da porta SSH padrão oferece diversas vantagens de segurança:

1. **Redução de ataques automatizados**: Bots maliciosos e scanners de vulnerabilidades geralmente focam na porta 22. O simples ato de mudar para outra porta reduz drasticamente o número de tentativas de ataque, pois a maioria dos ataques automatizados não escaneia todas as 65.535 portas possíveis.

2. **Menor volume de logs**: Servidores expostos à internet podem receber milhares de tentativas de conexão SSH diárias na porta 22. Mudar a porta reduz significativamente este volume, facilitando a análise de logs e detecção de padrões realmente suspeitos.

3. **Camada adicional de segurança**: Embora seja frequentemente chamada de "segurança por obscuridade", esta prática funciona como uma camada complementar em uma estratégia de defesa em profundidade. Quando combinada com outras medidas (autenticação por chave, fail2ban, etc.), aumenta a dificuldade para ataques bem-sucedidos.

4. **Menor superfície de ataque**: Em ambientes onde apenas usuários legítimos precisam acessar o sistema, não há razão para expor a porta SSH padrão a toda a internet.

## Considerações Importantes

1. **Não é uma solução completa**: A mudança de porta sozinha não substitui outras práticas de segurança como autenticação de chave SSH e configurações adequadas de firewall.

2. **Documentação necessária**: A porta não-padrão deve ser bem documentada para administradores legítimos do sistema.

3. **Ajustes de firewall**: É essencial atualizar as regras de firewall para permitir acesso à nova porta, como alertado pelo script:
   ```
   log "WARN" "Lembre-se de ajustar as regras de firewall para permitir a porta SSH $ssh_port"
   ```

4. **Portas recomendadas**: Ao escolher uma porta alternativa, considere:
   - Usar portas acima de 1024 (portas não privilegiadas)
   - Evitar portas comumente usadas por outros serviços
   - Evitar portas sequenciais fáceis de adivinhar (como 2222)
   - Considerar portas entre 10000-65535 para reduzir chance de conflitos

## Eficácia

Estudos e análises de logs de servidores mostram que servidores com SSH em portas não-padrão recebem 80-99% menos tentativas de login do que servidores que mantêm a porta 22 aberta, resultando em menor carga no servidor e redução significativa de riscos.

## Implementação com Ferramentas de Gestão

Se você utiliza ferramentas de gestão de configuração como Ansible, Puppet, ou Chef, certifique-se de que os playbooks ou receitas estejam atualizados para refletir a nova porta SSH.

## Exemplo de configuração no cliente

Para se conectar a um servidor com porta SSH não-padrão:

```bash
ssh -p PORTA_PERSONALIZADA usuario@servidor
```

Ou configure permanentemente no arquivo `~/.ssh/config`:

```
Host meuservidor
    HostName endereco.do.servidor
    Port PORTA_PERSONALIZADA
    User meuusuario
    IdentityFile ~/.ssh/minha_chave
```

## Referências

1. SANS Institute: "Securing SSH - Best Practices"
2. Linux Journal: "SSH: More Secure by Changing the Port"
3. DigitalOcean: "SSH Essentials: Working with SSH Servers, Clients, and Keys"
4. CIS Benchmarks para Linux: Recomendações para SSH
5. The Practical Linux Hardening Guide: https://github.com/trimstray/the-practical-linux-hardening-guide
