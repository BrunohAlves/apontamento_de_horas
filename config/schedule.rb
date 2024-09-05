every 1.minute do
# every 1.day, at: '06:15 pm' do
# every :saturday, at: '12:00 am' do
    command "cd /home/rapha/Documentos/Projetos/apontamento_de_horas && /home/rapha/.rbenv/shims/ruby /home/rapha/Documentos/Projetos/apontamento_de_horas/app.rb >> /home/rapha/Documentos/Projetos/apontamento_de_horas/logs/apontamento_de_horas.log 2>&1"
end
