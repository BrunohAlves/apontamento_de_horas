# Apontamento de Horas

Este é um projeto para o apontamento de horas no Redmine através de um arquivo CSV.

### Configuraçôes 

Para instalar as dependências, basta executar o comando `bundle install` na raiz do repositório.

### API do Redmine

Para utilizar esta ferramenta, é necessário ter acesso à API do Redmine. Você pode obtê-la em [https://endereço_do_redmine/my/account](https://endereço_do_redmine/my/account).

1. No menu do lado direito, clique em "Mostrar no bloco: Chave de Acesso API".
2. A chave de acesso API deve ser adicionada ao arquivo `app.rb` no trecho onde está sendo instanciado o token.
3. Além disso, também é necessário adicionar o link do redmine no conector, onde está sendo instanciado para utilização da API.

### Arquivo CSV

As informações no arquivo CSV devem estar no seguinte formato:
<br/>issue_id,hours,comments,spent_on<br/>
id_do_ticket,01:30,teste,2023-10-03

### Configuração da Crontab

Para configurar a tarefa na Crontab, siga os passos abaixo:

1. Certifique-se de saber onde o Ruby está instalado executando o comando `which ruby`.
2. Exemplo de entrada na Crontab:

15 18 * * * /bin/bash -l -c 'cd /caminho_do_projeto && /caminho_do_ruby /caminho_do_projeto/app.rb >> /caminho_para_arquivo_de_log 2>&1'

Lembre-se de substituir os valores de exemplo pelos caminhos e configurações reais do seu ambiente.
