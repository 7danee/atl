fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author '7danee'
description 'ATL (Auftragslieferung) - faction vs faction Pounder delivery event'
version '2.0.0'

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
    'locales/*.lua'
}

server_scripts {
    'server.lua'
}

client_scripts {
    'client.lua'
}

dependencies {
    'es_extended',
    'ox_inventory'
}
