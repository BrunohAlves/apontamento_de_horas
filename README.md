# Apontamento de Horas Automatizado

## Visão Geral

Este projeto automatiza o processo de apontamento de horas entre o **Clockify** e o **Redmine**, facilitando a sincronização de tarefas e entradas de tempo entre os dois sistemas. Ele foi desenvolvido para ajudar equipes que utilizam ambas as ferramentas a manter seus registros de tempo consistentes e atualizados.

## Funcionalidades

- **Sincronização de Projetos e Tarefas**: Os Projetos e Tarefas criadas no Redmine são sincronizadas com o Clockify, garantindo que todas as atividades estejam disponíveis para registro de tempo.
- **Sincronização de Entradas de Tempo**: As entradas de tempo registradas no Clockify são automaticamente lançadas no Redmine.
- **Atualização Diferencial**: Apenas os novos projetos, tarefas, entradas de tempo ou aquelas que sofreram alterações são sincronizadas, otimizando o desempenho.
- **Tratamento Robusto de Erros**: Implementação de logs detalhados e tratamento de exceções para facilitar a identificação e resolução de problemas.

## Índice

- [Apontamento de Horas Automatizado](#apontamento-de-horas-automatizado)
  - [Visão Geral](#visão-geral)
  - [Funcionalidades](#funcionalidades)
  - [Índice](#índice)
  - [Pré-requisitos](#pré-requisitos)
  - [Instalação](#instalação)
- [Configuração](#configuração)
    - [API do Redmine](#api-do-redmine)
    - [Clockify](#clockify)
    - [Lançamento de Horas no Clockify](#lançamento-de-horas-no-clockify)
    - [Configuração da Crontab](#configuração-da-crontab)

## Pré-requisitos

Antes de começar, certifique-se de ter o seguinte instalado em seu ambiente:

- **Ruby** (versão 2.5 ou superior): [Instalação do Ruby](https://www.ruby-lang.org/pt/downloads/)
- **Bundler**: Gerenciador de dependências do Ruby (`gem install bundler`)
- **Acesso ao Clockify**:
  - **Chave de API**: Disponível em [Configurações da sua conta no Clockify](https://clockify.me/user/settings)
  - **E-mail da conta**
- **Acesso ao Redmine**:
  - **Chave de API**: Disponível em sua página de perfil no Redmine
  - **URL do Redmine**

## Instalação

1. **Clone o Repositório**

   ```bash
   git clone https://github.com/seu_usuario/seu_projeto.git
   cd seu_projeto
   ```

2. **Instale as dependências**
Na raiz do projeto, execute:

   ```bash
   bundle install
   ```

# Configuração

As configurações necessárias para o funcionamento do script são fornecidas através de variáveis de ambiente.

### API do Redmine
Para utilizar esta ferramenta, é necessário ter acesso à API do Redmine. Você pode obtê-la [aqui](https://sh.autoseg.com/my/account).

1. No menu do lado direito, clique em "Mostrar no bloco: Chave de Acesso API".
2. A chave de acesso API deve ser adicionada ao arquivo `app.rb` no trecho onde está sendo instanciado o token.
3. Além disso, também é necessário adicionar o link do redmine no connector, onde está sendo instanciado para utilização da API.

### Clockify

Para utilizar esta ferramenta, é necessário ter acesso ao Clockify.
Você pode obtê-lo [aqui](https://app.clockify.me/tracker)

As informações necessárias do Clockify são:

1. Chave da API - Obtida [aqui](https://app.clockify.me/user/preferences#advanced), no final da página.
2. E-mail utilizado para a conta.
3. Você será incluído no Workspace de nome 'Turia', no qual os projetos dos clientes e as tarefas já existem.

### Lançamento de Horas no Clockify
Por convenção, se o funcionário deseja utilizar esta ferramenta, os lançamentos de horas devem sempre ser feitos dentro do clockify e não no Redmine.
Dentro do Clockify, o Workspace e os lançamentos devem seguir os seguintes critérios:

- Nome do Workspace: Turia;
- Selecione o Projeto (Cliente);
- Dentro do projeto, selecione a tarefa;
- Lançamento das horas:
  - Descrição da Atividade;
  - Tempo de inicio e fim.

1. **Variáveis de ambiente**
Defina as seguintes variáveis de ambiente:

    **Redmine**
    - REDMINE_API_KEY: Sua chave de API do Redmine
    - REDMINE_BASE_URI: URL base do seu Redmine (exemplo: https://redmine.seusite.com)

    **Clockify**
    - CLOCKIFY_API_KEY: Sua chave de API do Clockify
    - CLOCKIFY_WORKSPACE_NAME: Nome do seu workspace no Clockify
    - CLOCKIFY_USER_EMAIL: Seu e-mail cadastrado no Clockify


Uso
Para executar o script, basta rodar o seguinte comando na raiz do projeto:

```
ruby lib/app.rb
```

O script realizará as seguintes ações:

1. **Conexão com o Clockify:** Autentica usando sua chave de API e obtém informações do workspace e do usuário.
2. **Conexão com o Redmine:** Autentica usando sua chave de API e prepara-se para interagir com a API do Redmine.
3. **Sincronização de Projetos e Tarefas:**
- Obtém todos os projetos as issues (tarefas) do Redmine atualizadas desde a última sincronização.
- Para cada projeto no Redmine, verifica se existe no Clockify; se não, cria o projeto.
- Para cada tarefa, verifica se existe no Clockify; se não, cria a tarefa.
4. **Sincronização de Entradas de Tempo:**
- Obtém todas as entradas de tempo do Clockify desde a última sincronização.
- Para cada entrada de tempo, cria uma entrada correspondente no Redmine.

### Configuração da Crontab

Para configurar a tarefa na Crontab, siga os passos abaixo:

1. Certifique-se de saber onde o Ruby está instalado executando o comando `which ruby`.
    ```
    which ruby
    ```
2. No arquivo schedule.rb, deve ser adicionado o caminho do diretório onde o projeto está instalado, e o caminho onde o Ruby está instalado.
3. Após adicionado as informações corretas no schedule, basta executar o comando `whenever --update-crontab` na raiz do projeto, que o agendamento será adicionado.
4. Exemplo de agendamento diário às 18:04 na Crontab:
    ```
    4 18 * * * /bin/bash -l -c 'cd /caminho/para/seu_projeto && /caminho/para/ruby lib/app.rb >> logs/apontamento_de_horas.log 2>&1'
    ```
   Lembre-se de substituir os valores de exemplo pelos caminhos e configurações reais do seu ambiente.

**Substitua:**
/caminho/para/seu_projeto: Caminho absoluto até o diretório do projeto.
/caminho/para/ruby: Caminho para o executável do Ruby obtido anteriormente.

**Salve e Saia do Editor**
O cron agora está configurado para executar o script automaticamente no horário especificado.

**Estrutura do Projeto**
lib/: Contém o código-fonte principal.
app.rb: Ponto de entrada do script.
differential_updater.rb: Lógica de atualização diferencial.
connector/: Classes responsáveis pela conexão com o Clockify e o Redmine.
clockify_connector.rb
redmine_connector.rb
support/: Módulos de suporte e utilidades.
error_handling.rb
logs/: Diretório onde os logs de execução são armazenados.
