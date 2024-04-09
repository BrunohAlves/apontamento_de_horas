# Apontamento de Horas

Este é um projeto para o apontamento de horas no Redmine através de um arquivo CSV.

### Configuraçôes 

Para instalar as dependências, basta executar o comando `bundle install` na raiz do repositório.

### API do Redmine

Para utilizar esta ferramenta, é necessário ter acesso à API do Redmine. Você pode obtê-la em [Aqui](https://endereço_do_redmine/my/account).

1. No menu do lado direito, clique em "Mostrar no bloco: Chave de Acesso API".
2. A chave de acesso API deve ser adicionada ao arquivo `app.rb` no trecho onde está sendo instanciado o token.
3. Além disso, também é necessário adicionar o link do redmine no conector, onde está sendo instanciado para utilização da API.

### Clockify

Para utilizar esta ferramenta, é necessário ter acesso ao Clockify. Você pode obtê-lo em [Aqui](https://app.clockify.me/tracker)
As informações necessárias do Clockify são:
1. Chave da API - Obtida [Aqui](https://app.clockify.me/user/settings), no final da página.
2. E-mail utilizado para a conta.

### Configuração da Crontab

Para configurar a tarefa na Crontab, siga os passos abaixo:

1. Certifique-se de saber onde o Ruby está instalado executando o comando `which ruby`.
2. No arquivo schedule.rb, deve ser adicionado o caminho do diretório onde o projeto está instalado, e o caminho onde o Ruby está instalado.
3. Após adicionado as informações corretas no schedule, basta executar o comando `whenever --update-crontab` na raiz do projeto, que o agendamento será adicionado.
4. Exemplo de entrada na Crontab:

4 18 * * * /bin/bash -l -c 'cd ~/Documents/apontamento_de_horas && ~/.rbenv/shims/ruby ~/Documents/apontamento_de_horas/app.rb >> ~/Documents/apontamento_de_horas/logs/apontamento_de_horas.log 2>&1'

Lembre-se de substituir os valores de exemplo pelos caminhos e configurações reais do seu ambiente.
