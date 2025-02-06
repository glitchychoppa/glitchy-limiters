game 'gta5'
fx_version 'cerulean'
version '1.3.0'

server_scripts {
    'server.lua',
    '@oxmysql/lib/MySQL.lua'
}

shared_script {
    "config.lua"
}

client_scripts {
    'client.lua'
}

lua54 'yes'
