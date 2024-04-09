every 1.day, at: '06:15 pm' do
    command "cd ~/Documents/apontamento_de_horas && ~/.rbenv/shims/ruby ~/Documents/apontamento_de_horas/app.rb >> ~/Documents/apontamento_de_horas/logs/apontamento_de_horas.log 2>&1"
end